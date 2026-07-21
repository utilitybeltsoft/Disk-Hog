import Foundation


nonisolated final class DiskInventoryZScanner {
    typealias ProgressHandler = @Sendable (DiskScanProgress) async -> Void
    typealias ResourceValuesProvider = @Sendable (URL, Set<URLResourceKey>) throws -> URLResourceValues

    private let directoryTraversal: DiskDirectoryTraversal
    private let hardlinkDeduplicator: HardlinkDeduplicator
    private let itemFactory: DiskItemBuilderFactory
    private let recursiveResourceValuesProvider: ResourceValuesProvider

    init(
        recursiveResourceValuesProvider: @escaping ResourceValuesProvider = { url, keys in
            try url.resourceValues(forKeys: keys)
        }
    ) {
        let hardlinkDeduplicator: HardlinkDeduplicator = HardlinkDeduplicator()
        let itemFactory: DiskItemBuilderFactory = DiskItemBuilderFactory()
        self.recursiveResourceValuesProvider = recursiveResourceValuesProvider
        self.hardlinkDeduplicator = hardlinkDeduplicator
        self.itemFactory = itemFactory
        self.directoryTraversal = DiskDirectoryTraversal(
            resourceValuesProvider: recursiveResourceValuesProvider,
            hardlinkDeduplicator: hardlinkDeduplicator,
            itemFactory: itemFactory
        )
    }

    private init(
        recursiveResourceValuesProvider: @escaping ResourceValuesProvider,
        hardlinkDeduplicator: HardlinkDeduplicator = HardlinkDeduplicator()
    ) {
        let itemFactory: DiskItemBuilderFactory = DiskItemBuilderFactory()
        self.recursiveResourceValuesProvider = recursiveResourceValuesProvider
        self.hardlinkDeduplicator = hardlinkDeduplicator
        self.itemFactory = itemFactory
        self.directoryTraversal = DiskDirectoryTraversal(
            resourceValuesProvider: recursiveResourceValuesProvider,
            hardlinkDeduplicator: hardlinkDeduplicator,
            itemFactory: itemFactory
        )
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DiskItem {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }
        hardlinkDeduplicator.reset()
        let rootBuilder: DiskItemBuilder = itemFactory.makeItem(url: rootURL, values: nil)
        var progressState: ScanProgressState = ScanProgressState(currentPath: rootURL.path)

        await progressHandler?(progressState.snapshot())

        let topLevelChildren: [URL]
        do {
            topLevelChildren = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: DiskScanResourceKeys.item,
                options: []
            )
        } catch {
            throw DiskScannerError.topLevelEnumerationFailed(path: rootURL.path, underlyingDescription: error.localizedDescription)
        }

        let progressAggregator: ScanProgressAggregator = ScanProgressAggregator(currentPath: rootURL.path)
        var topLevelWorkItems: [TopLevelScanWorkItem] = []
        for (sourceOrder, childURL) in topLevelChildren.enumerated() {
            try Task.checkCancellation()
            if DiskScanFileSystemRules.shouldSkip(childURL) {
                continue
            }

            let values: URLResourceValues
            do {
                values = try recursiveResourceValuesProvider(childURL, Set(DiskScanResourceKeys.item))
            } catch {
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

        try await withThrowingTaskGroup(of: TopLevelScanResult.self) { taskGroup in
            for workItem: TopLevelScanWorkItem in topLevelWorkItems {
                let settings: DiskScanSettings = settings
                let recursiveResourceValuesProvider: ResourceValuesProvider = recursiveResourceValuesProvider
                let hardlinkDeduplicator: HardlinkDeduplicator = hardlinkDeduplicator
                let progressAggregator: ScanProgressAggregator = progressAggregator
                let progressHandler: ProgressHandler? = progressHandler

                taskGroup.addTask {
                    let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
                        recursiveResourceValuesProvider: recursiveResourceValuesProvider,
                        hardlinkDeduplicator: hardlinkDeduplicator
                    )
                    return try await scanner.scanTopLevelWorkItem(
                        workItem,
                        settings: settings,
                        progressAggregator: progressAggregator,
                        progressHandler: progressHandler
                    )
                }
            }

            for try await result: TopLevelScanResult in taskGroup {
                rootBuilder.appendChild(result.item, updateSize: true)
            }
        }

        rootBuilder.sortChildrenInDiskInventoryZOrder(recursive: false, usePhysicalSize: settings.usePhysicalSize)
        progressState.setScannedBytes(rootBuilder.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        progressState.setScannedFileCount(await progressAggregator.scannedFileCount)
        progressState.setScannedFolderCount(await progressAggregator.scannedFolderCount)
        await progressHandler?(progressState.snapshot())
        return rootBuilder.freeze()
    }

    func scanItem(
        at itemURL: URL,
        from source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault
    ) async throws -> DiskItem {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }

        let standardizedRootPath: String = rootURL.standardizedFileURL.path
        let standardizedItemURL: URL = itemURL.standardizedFileURL
        let rootPrefix: String = standardizedRootPath.hasSuffix("/") ? standardizedRootPath : standardizedRootPath + "/"
        guard standardizedItemURL.path == standardizedRootPath || standardizedItemURL.path.hasPrefix(rootPrefix) else {
            throw DiskScannerError.itemOutsideScanRoot(path: standardizedItemURL.path)
        }

        let values: URLResourceValues = try recursiveResourceValuesProvider(
            standardizedItemURL,
            Set(DiskScanResourceKeys.item)
        )
        hardlinkDeduplicator.reset()
        let item: DiskItemBuilder = itemFactory.makeItem(url: standardizedItemURL, values: values)

        if item.isFolder && !(item.isPackage && !settings.lookInsidePackages) && values.isVolume != true {
            var progressState: ScanProgressState = ScanProgressState(currentPath: item.path)
            progressState.recordItem(item)
            _ = try await directoryTraversal.loadChildren(
                of: item,
                settings: settings,
                progressState: progressState,
                progressHandler: nil
            )
        } else if item.isDirectory && item.isPackage && !settings.lookInsidePackages {
            let packageSize: OpaquePackageSize = try OpaquePackageSizer.size(of: item.url)
            item.allocatedSizeValue = packageSize.allocated
            item.logicalSizeValue = packageSize.logical
        } else if !item.isDirectory {
            hardlinkDeduplicator.markDuplicateIfNeeded(item: item, values: values)
        }

        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        return item.freeze(isRoot: false)
    }

    private func scanTopLevelWorkItem(
        _ workItem: TopLevelScanWorkItem,
        settings: DiskScanSettings,
        progressAggregator: ScanProgressAggregator,
        progressHandler: ProgressHandler?
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
            let packageSize: OpaquePackageSize = try OpaquePackageSizer.size(of: workItem.item.url)
            workItem.item.allocatedSizeValue = packageSize.allocated
            workItem.item.logicalSizeValue = packageSize.logical
            progressState.setScannedBytes(workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        } else if !workItem.isDirectory {
            hardlinkDeduplicator.markDuplicateIfNeeded(item: workItem.item, values: workItem.values)
            progressState.setScannedBytes(workItem.item.isHardlinkDuplicate ? 0 : workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        }

        progressState.updateCurrentPath(workItem.item.path)
        let aggregateProgress: DiskScanProgress = await progressAggregator.finishChild(
            id: workItem.sourceOrder,
            progress: progressState.snapshot()
        )
        await progressHandler?(aggregateProgress)

        return TopLevelScanResult(item: workItem.item)
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
    let item: DiskItemBuilder
}
