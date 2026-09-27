import Foundation


nonisolated final class DiskInventoryZScanner {
    typealias ProgressHandler = @Sendable (DiskScanProgress) async -> Void
    typealias ResourceValuesProvider = @Sendable (URL, Set<URLResourceKey>) throws -> URLResourceValues

    private let directoryTraversal: DiskDirectoryTraversal
    private let hardlinkDeduplicator: any HardlinkDeduplicating
    private let itemFactory: any DiskItemBuilding
    private let packageSizer: any OpaquePackageSizing
    private let recursiveResourceValuesProvider: ResourceValuesProvider
    private let resourceBudget: ScanResourceBudget

    init(
        recursiveResourceValuesProvider: @escaping ResourceValuesProvider = { url, keys in
            try url.resourceValues(forKeys: keys)
        },
        hardlinkDeduplicator: any HardlinkDeduplicating = HardlinkDeduplicator(),
        itemFactory: any DiskItemBuilding = DiskItemBuilderFactory(),
        packageSizer: any OpaquePackageSizing = FileSystemOpaquePackageSizer(),
        resourceBudget: ScanResourceBudget = .shared
    ) {
        self.recursiveResourceValuesProvider = recursiveResourceValuesProvider
        self.hardlinkDeduplicator = hardlinkDeduplicator
        self.itemFactory = itemFactory
        self.packageSizer = packageSizer
        self.resourceBudget = resourceBudget
        self.directoryTraversal = DiskDirectoryTraversal(
            resourceValuesProvider: recursiveResourceValuesProvider,
            hardlinkDeduplicator: hardlinkDeduplicator,
            itemFactory: itemFactory,
            packageSizer: packageSizer
        )
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault,
        progressHandler: ProgressHandler? = nil,
        stageHandler: (@Sendable (DiskScanStage) async -> Void)? = nil
    ) async throws -> DiskScanOutcome {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }
        hardlinkDeduplicator.reset()
        let rootBuilder: DiskItemBuilder = itemFactory.makeItem(url: rootURL, values: nil)
        var progressState: ScanProgressState = ScanProgressState(currentPath: rootURL.path)

        await stageHandler?(.enumeratingRootItems)
        await progressHandler?(progressState.snapshot())

        let rootEnumerationPermit: ScanResourcePermit = try await resourceBudget.acquireTraversalPermit()
        // A work item owns a mutable builder while that subtree is traversed. Clear
        // its queue slot as soon as it is submitted so a completed builder can be
        // released after it becomes an immutable packed chunk, rather than keeping
        // both representations alive until every sibling has finished scanning.
        var topLevelWorkItems: [TopLevelScanWorkItem?] = []
        do {
            let topLevelChildren: [URL] = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: DiskScanResourceKeys.item,
                options: []
            )
            for (sourceOrder, childURL) in topLevelChildren.enumerated() {
                try Task.checkCancellation()
                if DiskScanFileSystemRules.shouldSkip(childURL) {
                    continue
                }

                let values: URLResourceValues
                do {
                    values = try recursiveResourceValuesProvider(childURL, Set(DiskScanResourceKeys.item))
                } catch {
                    progressState.recordSkippedItem(ScanSkippedItem(path: childURL.path, reason: error.localizedDescription))
                    continue
                }
                topLevelWorkItems.append(
                    TopLevelScanWorkItem(
                        sourceOrder: sourceOrder,
                        item: itemFactory.makeItem(url: childURL, values: values),
                        isDirectory: values.isDirectory ?? false,
                        isPackage: values.isPackage ?? false,
                        isVolume: values.isVolume ?? false,
                        values: values
                    )
                )
            }
            await rootEnumerationPermit.release()
        } catch is CancellationError {
            await rootEnumerationPermit.release()
            throw CancellationError()
        } catch {
            await rootEnumerationPermit.release()
            throw DiskScannerError.topLevelEnumerationFailed(path: rootURL.path, underlyingDescription: error.localizedDescription)
        }

        let progressAggregator: ScanProgressAggregator = ScanProgressAggregator(currentPath: rootURL.path)
        let (packagingUpdates, packagingContinuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let packagingProgress = ScanPackagingProgress(subtreeCount: topLevelWorkItems.count, continuation: packagingContinuation)
        // One consumer preserves publication order and bounds pending UI work.
        let packagingReporter = Task {
            for await percent in packagingUpdates {
                guard !Task.isCancelled else { break }
                await stageHandler?(.packagingScanResults(percent: percent))
            }
        }
        defer {
            packagingContinuation.finish()
            packagingReporter.cancel()
        }
        var topLevelResults: [TopLevelScanResult] = []
        await stageHandler?(.scanningFiles)
        try await withThrowingTaskGroup(of: TopLevelScanResult.self) { taskGroup in
            var nextWorkItemIndex: Int = 0

            func submitNextTaskIfAvailable() {
                guard nextWorkItemIndex < topLevelWorkItems.count else {
                    return
                }
                guard let workItem: TopLevelScanWorkItem = topLevelWorkItems[nextWorkItemIndex] else {
                    preconditionFailure("A top-level scan work item was submitted more than once.")
                }
                topLevelWorkItems[nextWorkItemIndex] = nil
                nextWorkItemIndex += 1

                let settings: DiskScanSettings = settings
                let recursiveResourceValuesProvider: ResourceValuesProvider = recursiveResourceValuesProvider
                let hardlinkDeduplicator: any HardlinkDeduplicating = hardlinkDeduplicator
                let itemFactory: any DiskItemBuilding = itemFactory
                let packageSizer: any OpaquePackageSizing = packageSizer
                let progressAggregator: ScanProgressAggregator = progressAggregator
                let progressHandler: ProgressHandler? = progressHandler
                let resourceBudget: ScanResourceBudget = resourceBudget

                taskGroup.addTask {
                    let permit: ScanResourcePermit = try await resourceBudget.acquireTraversalPermit()
                    let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
                        recursiveResourceValuesProvider: recursiveResourceValuesProvider,
                        hardlinkDeduplicator: hardlinkDeduplicator,
                        itemFactory: itemFactory,
                        packageSizer: packageSizer,
                        resourceBudget: resourceBudget
                    )
                    do {
                        let result: TopLevelScanResult = try await scanner.scanTopLevelWorkItem(
                            workItem,
                            settings: settings,
                            progressAggregator: progressAggregator,
                            progressHandler: progressHandler,
                            packagingProgress: packagingProgress
                        )
                        await permit.release()
                        return result
                    } catch {
                        await permit.release()
                        throw error
                    }
                }
            }

            // Bound how many top-level items become live tasks at once - a directory
            // with a very large number of immediate children would otherwise spawn a
            // task for every single one up front, even though the traversal budget
            // only lets a handful actually run concurrently. Every task beyond that
            // limit would just immediately suspend waiting for a permit anyway, so
            // creating them eagerly only adds suspended-task/continuation overhead
            // with no benefit. Instead, submit only as many as the budget allows, and
            // add the next one each time a task completes and frees its slot.
            let initialTaskCount: Int = min(topLevelWorkItems.count, resourceBudget.maximumConcurrentFilesystemTraversals)
            for _ in 0..<initialTaskCount {
                submitNextTaskIfAvailable()
            }

            for try await result: TopLevelScanResult in taskGroup {
                topLevelResults.append(result)
                submitNextTaskIfAvailable()
            }
        }

        packagingContinuation.finish()
        await packagingReporter.value
        await stageHandler?(.finalizingScan)
        topLevelResults.sort { first, second in
            DiskItemBuilderOrdering.areInOrder(
                firstName: first.name,
                firstAllocatedSize: first.allocatedSizeValue,
                firstLogicalSize: first.logicalSizeValue,
                firstIsSpecialItem: first.isSpecialItem,
                secondName: second.name,
                secondAllocatedSize: second.allocatedSizeValue,
                secondLogicalSize: second.logicalSizeValue,
                secondIsSpecialItem: second.isSpecialItem,
                usePhysicalSize: settings.usePhysicalSize
            )
        }
        rootBuilder.allocatedSizeValue = topLevelResults.reduce(0) { $0 + $1.allocatedSizeValue }
        rootBuilder.logicalSizeValue = topLevelResults.reduce(0) { $0 + $1.logicalSizeValue }
        progressState.setScannedBytes(rootBuilder.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        progressState.setScannedFileCount(await progressAggregator.scannedFileCount)
        progressState.setScannedFolderCount(await progressAggregator.scannedFolderCount)
        await progressHandler?(progressState.snapshot())
        let allSkippedItems: [ScanSkippedItem] = progressState.skippedItems + topLevelResults.flatMap(\.skippedItems)
        return DiskScanOutcome(
            item: DiskItem.chunkedRoot(
                rootChunk: rootBuilder.packedChunk(isRoot: true),
                childChunks: topLevelResults.map(\.chunk)
            ),
            skippedItems: allSkippedItems
        )
    }

    func scanItem(
        at itemURL: URL,
        from source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault
    ) async throws -> DiskScanOutcome {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }

        let standardizedRootPath: String = rootURL.standardizedFileURL.path
        let standardizedItemURL: URL = itemURL.standardizedFileURL
        guard FilePathContainment.contains(standardizedItemURL.path, in: standardizedRootPath) else {
            throw DiskScannerError.itemOutsideScanRoot(path: standardizedItemURL.path)
        }

        let values: URLResourceValues = try recursiveResourceValuesProvider(
            standardizedItemURL,
            Set(DiskScanResourceKeys.item)
        )
        hardlinkDeduplicator.reset()
        // Normalize for containment/resource lookup above, but preserve the
        // caller's tree identity when constructing the replacement item.
        let item: DiskItemBuilder = itemFactory.makeItem(url: itemURL, values: values)

        var skippedItems: [ScanSkippedItem] = []
        if item.isFolder && !(item.isPackage && !settings.lookInsidePackages) && values.isVolume != true {
            var progressState: ScanProgressState = ScanProgressState(currentPath: item.path)
            progressState.recordItem(item)
            progressState = try await directoryTraversal.loadChildren(
                of: item,
                settings: settings,
                progressState: progressState,
                progressHandler: nil
            )
            skippedItems = progressState.skippedItems
        } else if item.isDirectory && item.isPackage && !settings.lookInsidePackages {
            let packageSize: OpaquePackageSize = try packageSizer.size(of: item.url)
            item.setOpaquePackageSize(allocated: packageSize.allocated, logical: packageSize.logical)
        } else if !item.isDirectory {
            hardlinkDeduplicator.markDuplicateIfNeeded(item: item, values: values)
        }

        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        return DiskScanOutcome(item: item.freeze(isRoot: false), skippedItems: skippedItems)
    }

    private func scanTopLevelWorkItem(
        _ workItem: TopLevelScanWorkItem,
        settings: DiskScanSettings,
        progressAggregator: ScanProgressAggregator,
        progressHandler: ProgressHandler?,
        packagingProgress: ScanPackagingProgress
    ) async throws -> TopLevelScanResult {
        try Task.checkCancellation()

        var progressState: ScanProgressState = ScanProgressState(currentPath: workItem.item.path)
        progressState.recordItem(workItem.item)

        if workItem.isDirectory && !workItem.isVolume && (!workItem.isPackage || settings.lookInsidePackages) {
            progressState = try await directoryTraversal.loadChildren(
                of: workItem.item,
                settings: settings,
                progressState: progressState
            ) { progress in
                if let snapshot: DiskScanProgress = await progressAggregator.updateChild(
                    id: workItem.sourceOrder,
                    progress: progress
                ) {
                    await progressHandler?(snapshot)
                }
            }
        } else if workItem.isDirectory && workItem.isPackage && !settings.lookInsidePackages {
            let packageSize: OpaquePackageSize = try packageSizer.size(of: workItem.item.url)
            workItem.item.setOpaquePackageSize(
                allocated: packageSize.allocated,
                logical: packageSize.logical
            )
            progressState.setScannedBytes(workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        } else if !workItem.isDirectory {
            hardlinkDeduplicator.markDuplicateIfNeeded(item: workItem.item, values: workItem.values)
            if workItem.item.isHardlinkDuplicate {
                workItem.item.allocatedSizeValue = 0
                workItem.item.logicalSizeValue = 0
            }
            progressState.setScannedBytes(workItem.item.isHardlinkDuplicate ? 0 : workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        }

        progressState.updateCurrentPath(workItem.item.path)
        let aggregateProgress: DiskScanProgress = await progressAggregator.finishChild(
            id: workItem.sourceOrder,
            progress: progressState.snapshot()
        )
        await progressHandler?(aggregateProgress)
        // Each top-level builder owns its entire arena: this is the exact number
        // of items the four packing passes will visit.
        packagingProgress.finishTraversal(itemCount: workItem.item.arena.records.count)
        try Task.checkCancellation()

        return TopLevelScanResult(
            chunk: workItem.item.packedChunk(isRoot: false) { units in
                packagingProgress.advance(by: units)
            },
            name: workItem.item.name,
            allocatedSizeValue: workItem.item.allocatedSizeValue,
            logicalSizeValue: workItem.item.logicalSizeValue,
            isSpecialItem: workItem.item.isSpecialItem,
            skippedItems: progressState.skippedItems
        )
    }
}

private nonisolated struct TopLevelScanWorkItem: @unchecked Sendable {
    let sourceOrder: Int
    let item: DiskItemBuilder
    let isDirectory: Bool
    let isPackage: Bool
    let isVolume: Bool
    let values: URLResourceValues
}

private nonisolated struct TopLevelScanResult: Sendable {
    let chunk: PackedDiskItemChunk
    let name: String
    let allocatedSizeValue: UInt64
    let logicalSizeValue: UInt64
    let isSpecialItem: Bool
    let skippedItems: [ScanSkippedItem]
}
