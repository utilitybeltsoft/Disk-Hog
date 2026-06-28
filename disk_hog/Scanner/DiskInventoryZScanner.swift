import Foundation

nonisolated final class DiskInventoryZScanner: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (DiskScanProgress) -> Void

    private let fileManager: FileManager
    private let kindResolver: DiskInventoryZKindResolver
    private let firmlinkTable: DiskInventoryZFirmlinkTable

    init(
        fileManager: FileManager = .default,
        kindResolver: DiskInventoryZKindResolver = DiskInventoryZKindResolver(),
        firmlinkTable: DiskInventoryZFirmlinkTable = DiskInventoryZFirmlinkTable()
    ) {
        self.fileManager = fileManager
        self.kindResolver = kindResolver
        self.firmlinkTable = firmlinkTable
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault,
        progressHandler: ProgressHandler? = nil
    ) throws -> DiskItem {
        let profile: ScanPerformanceRecorder = .shared
        profile.reset(appName: "Disk Hog", rootPath: source.path)
        let scanStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        try Task.checkCancellation()

        let rootURL: URL = URL(fileURLWithPath: source.path)
        let rootValues: URLResourceValues = resourceValues(for: rootURL, keys: Self.topLevelProperties)
        let rootItem: DiskItem = DiskItem(
            url: rootURL,
            isDirectory: rootValues.isDirectory ?? true,
            isPackage: rootValues.isPackage ?? false
        )

        var counters: DiskInventoryZScanCounters = DiskInventoryZScanCounters()
        var hardlinks: Set<AnyHashable> = []
        var lastProgressTime: TimeInterval = 0

        let topLevelURLs: [URL] = try profile.measure("topLevel.enumeration") {
            try topLevelContents(of: rootURL)
        }
        for childURL: URL in topLevelURLs {
            try Task.checkCancellation()

            guard !Self.shouldSkipAlways(childURL) else {
                continue
            }

            emitProgressIfNeeded(
                progress(
                    counters: counters,
                    currentPath: childURL.path,
                    rootItem: rootItem
                ),
                lastProgressTime: &lastProgressTime,
                progressHandler: progressHandler
            )

            let childValues: URLResourceValues = profile.measure("topLevel.resourceValues") {
                resourceValues(for: childURL, keys: Self.urlProperties)
            }
            let orphan: DiskItem = profile.measure("topLevel.orphanInit") {
                makeItem(
                    url: childURL,
                    values: childValues,
                    parent: nil,
                    setKindString: true,
                    usePhysicalSize: settings.usePhysicalSize,
                    counters: &counters
                )
            }

            if orphan.isDirectory && childValues.isVolume != true && (!orphan.isPackage || settings.lookInsidePackages) {
                try profile.measure("topLevel.loadChildren") {
                    try loadChildrenAndSetKindStrings(
                        of: orphan,
                        setKindStrings: true,
                        settings: settings,
                        counters: &counters,
                        hardlinks: &hardlinks,
                        lastProgressTime: &lastProgressTime,
                        progressHandler: progressHandler
                    )
                }
            } else if orphan.isDirectory && orphan.isPackage && !settings.lookInsidePackages {
                let packageSize: UInt64 = try profile.measure("package.opaqueSize.topLevel") {
                    try opaquePackageSize(
                        at: childURL,
                        settings: settings
                    )
                }
                orphan.allocatedSizeValue = packageSize
                orphan.logicalSizeValue = packageSize
            } else {
                applyHardlinkDedup(
                    to: orphan,
                    values: childValues,
                    hardlinks: &hardlinks
                )
            }

            profile.measure("topLevel.insertChild") {
                rootItem.appendChild(orphan, updateSize: true)
            }
            emitProgressIfNeeded(
                progress(
                    counters: counters,
                    currentPath: childURL.path,
                    rootItem: rootItem
                ),
                lastProgressTime: &lastProgressTime,
                progressHandler: progressHandler
            )
        }

        _ = profile.measure("root.recalculateSize") {
            rootItem.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        }
        progressHandler?(
            progress(
                counters: counters,
                currentPath: rootURL.path,
                rootItem: rootItem
            )
        )

        profile.addTime("scan.total", seconds: CFAbsoluteTimeGetCurrent() - scanStartTime)
        profile.setValue("items.files", value: UInt64(counters.fileCount))
        profile.setValue("items.folders", value: UInt64(counters.folderCount))
        profile.setValue("items.total", value: UInt64(counters.fileCount + counters.folderCount))
        _ = try? profile.write()

        return rootItem
    }

    private func loadChildrenAndSetKindStrings(
        of root: DiskItem,
        setKindStrings: Bool,
        settings: DiskScanSettings,
        counters: inout DiskInventoryZScanCounters,
        hardlinks: inout Set<AnyHashable>,
        lastProgressTime: inout TimeInterval,
        progressHandler: ProgressHandler?
    ) throws {
        guard root.isFolder else {
            return
        }

        emitProgressIfNeeded(
            progress(
                counters: counters,
                currentPath: root.path,
                rootItem: root
            ),
            lastProgressTime: &lastProgressTime,
            progressHandler: progressHandler
        )

        let loadStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        root.removeAllChildren()

        var shouldSetKindStrings: Bool = setKindStrings
        if shouldSetKindStrings && !root.isRoot && !settings.lookInsidePackages {
            shouldSetKindStrings = !root.isPackage
        }

        guard let directoryEnumerator: FileManager.DirectoryEnumerator = fileManager.enumerator(
            at: root.url,
            includingPropertiesForKeys: Self.urlProperties,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        var itemStack: [DiskItem] = [root]
        var lastEnumLevel: Int = Metrics.rootEnumeratorLevel
        var lastItemWasDirectory: Bool = false
        var lastDirectoryItem: DiskItem?
        var filesSinceYield: Int = 0

        for case let currentURL as URL in directoryEnumerator {
            filesSinceYield += Metrics.itemIncrement
            if filesSinceYield >= Metrics.continuationPollInterval {
                filesSinceYield = 0
                try Task.checkCancellation()
                emitProgressIfNeeded(
                    progress(
                        counters: counters,
                        currentPath: currentURL.path,
                        rootItem: root
                    ),
                    lastProgressTime: &lastProgressTime,
                    progressHandler: progressHandler
                )
            }

            if Self.shouldSkipAlways(currentURL) {
                directoryEnumerator.skipDescendants()
                continue
            }

            let currentValues: URLResourceValues = ScanPerformanceRecorder.shared.measure("resource.cacheResourcesInArray") {
                resourceValues(for: currentURL, keys: Self.urlProperties)
            }
            let currentLevel: Int = directoryEnumerator.level
            if currentLevel > lastEnumLevel {
                if lastItemWasDirectory, let lastDirectoryItem: DiskItem = lastDirectoryItem {
                    itemStack.append(lastDirectoryItem)
                    emitProgressIfNeeded(
                        progress(
                            counters: counters,
                            currentPath: lastDirectoryItem.path,
                            rootItem: root
                        ),
                        lastProgressTime: &lastProgressTime,
                        progressHandler: progressHandler
                    )
                }
            } else if currentLevel < lastEnumLevel {
                let levelsWalkedUp: Int = lastEnumLevel - currentLevel
                for _ in 0..<levelsWalkedUp where itemStack.count > Metrics.minimumStackDepth {
                    itemStack.removeLast()
                }
            }

            let parent: DiskItem = itemStack[itemStack.count - Metrics.parentStackOffset]
            let currentItem: DiskItem = ScanPerformanceRecorder.shared.measure("item.currentItemInitCall") {
                makeItem(
                    url: currentURL,
                    values: currentValues,
                    parent: parent,
                    setKindString: shouldSetKindStrings,
                    usePhysicalSize: settings.usePhysicalSize,
                    counters: &counters
                )
            }

            ScanPerformanceRecorder.shared.measure("hardlink.check") {
                applyHardlinkDedup(
                    to: currentItem,
                    values: currentValues,
                    hardlinks: &hardlinks
                )
            }

            let isFirmlink: Bool = ScanPerformanceRecorder.shared.measure("firmlink.check") {
                firmlinkTable.isFirmlink(currentURL)
            }

            if isFirmlink {
                directoryEnumerator.skipDescendants()
                try loadChildrenAndSetKindStrings(
                    of: currentItem,
                    setKindStrings: shouldSetKindStrings,
                    settings: settings,
                    counters: &counters,
                    hardlinks: &hardlinks,
                    lastProgressTime: &lastProgressTime,
                    progressHandler: progressHandler
                )
            } else if currentValues.isVolume == true {
                directoryEnumerator.skipDescendants()
            } else if currentItem.isPackage && !settings.lookInsidePackages {
                directoryEnumerator.skipDescendants()
                let packageSize: UInt64 = try ScanPerformanceRecorder.shared.measure("package.opaqueSize.recursive") {
                    try opaquePackageSize(
                        at: currentURL,
                        settings: settings
                    )
                }
                currentItem.allocatedSizeValue = packageSize
                currentItem.logicalSizeValue = packageSize
            }

            lastItemWasDirectory = currentItem.isDirectory
            lastDirectoryItem = lastItemWasDirectory ? currentItem : nil
            lastEnumLevel = currentLevel
        }

        _ = ScanPerformanceRecorder.shared.measure("folder.recalculateSize.afterLoadChildren") {
            root.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        }
        ScanPerformanceRecorder.shared.addTime("folder.loadChildren.total", seconds: CFAbsoluteTimeGetCurrent() - loadStartTime)
    }

    private func topLevelContents(of rootURL: URL) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: Self.topLevelProperties,
                options: []
            )
        } catch {
            throw DiskScannerError.topLevelEnumerationFailed
        }
    }

    private func makeItem(
        url: URL,
        values: URLResourceValues,
        parent: DiskItem?,
        setKindString: Bool,
        usePhysicalSize: Bool,
        counters: inout DiskInventoryZScanCounters
    ) -> DiskItem {
        ScanPerformanceRecorder.shared.addTime("item.isDirectory", seconds: 0)
        let isDirectory: Bool = values.isDirectory ?? false
        let item: DiskItem = ScanPerformanceRecorder.shared.measure("item.init") {
            DiskItem(
                url: url,
                parent: parent,
                allocatedSizeValue: isDirectory ? 0 : sizeValue(values: values, usePhysicalSize: usePhysicalSize),
                logicalSizeValue: isDirectory ? 0 : sizeValue(values: values, usePhysicalSize: false),
                kindName: setKindString ? kindResolver.kindName(typeIdentifier: values.typeIdentifier, url: url) : nil,
                isDirectory: isDirectory,
                isPackage: values.isPackage ?? false,
                isAliasOrSymbolicLink: values.isAliasFile ?? false
            )
        }

        parent?.appendChild(item, updateSize: false)

        if isDirectory {
            counters.folderCount += Metrics.itemIncrement
        } else {
            counters.fileCount += Metrics.itemIncrement
        }

        return item
    }

    private func applyHardlinkDedup(
        to item: DiskItem,
        values: URLResourceValues,
        hardlinks: inout Set<AnyHashable>
    ) {
        guard !item.isDirectory else {
            return
        }

        guard let linkCount: Int = values.linkCount, linkCount > Metrics.singleLinkCount else {
            return
        }

        guard let identifierObject: NSObject = values.fileResourceIdentifier as? NSObject else {
            return
        }

        let identifier: AnyHashable = AnyHashable(identifierObject)
        if hardlinks.contains(identifier) {
            item.isHardlinkDuplicate = true
        } else {
            hardlinks.insert(identifier)
        }
    }

    private func opaquePackageSize(
        at url: URL,
        settings: DiskScanSettings
    ) throws -> UInt64 {
        try Task.checkCancellation()

        guard let packageEnumerator: FileManager.DirectoryEnumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Self.packageProperties,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var size: UInt64 = 0
        for case let childURL as URL in packageEnumerator {
            try Task.checkCancellation()

            let values: URLResourceValues = resourceValues(for: childURL, keys: Self.packageProperties)
            if settings.usePhysicalSize {
                size += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            } else {
                size += UInt64(values.fileAllocatedSize ?? 0)
            }
        }

        return size
    }

    private func resourceValues(
        for url: URL,
        keys: [URLResourceKey]
    ) -> URLResourceValues {
        ScanPerformanceRecorder.shared.measure("url.getResourceValue.cacheFill") {
            (try? url.resourceValues(forKeys: Set(keys))) ?? URLResourceValues()
        }
    }

    private func emitProgressIfNeeded(
        _ progress: DiskScanProgress,
        lastProgressTime: inout TimeInterval,
        progressHandler: ProgressHandler?
    ) {
        guard let progressHandler: ProgressHandler = progressHandler else {
            return
        }

        let now: TimeInterval = Date.timeIntervalSinceReferenceDate
        guard lastProgressTime == 0 || now - lastProgressTime >= Metrics.progressRefreshInterval else {
            return
        }

        lastProgressTime = now
        ScanPerformanceRecorder.shared.measure("progress.checkpoint") {
            progressHandler(progress)
        }
    }

    private func progress(
        counters: DiskInventoryZScanCounters,
        currentPath: String,
        rootItem: DiskItem
    ) -> DiskScanProgress {
        DiskScanProgress(
            scannedFileCount: counters.fileCount,
            scannedFolderCount: counters.folderCount,
            scannedByteCount: rootItem.allocatedSizeValue,
            currentPath: currentPath
        )
    }

    private func sizeValue(
        values: URLResourceValues,
        usePhysicalSize: Bool
    ) -> UInt64 {
        if usePhysicalSize {
            return UInt64(values.totalFileAllocatedSize ?? values.totalFileSize ?? 0)
        }

        return UInt64(values.totalFileSize ?? values.fileSize ?? 0)
    }

    private static func shouldSkipAlways(_ url: URL) -> Bool {
        if url.path == "/Volumes" {
            return true
        }

        let leaf: String = url.lastPathComponent
        return leaf == ".nofollow" || leaf == ".resolve"
    }

    private static let topLevelProperties: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isVolumeKey,
        .nameKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey
    ]

    private static let urlProperties: [URLResourceKey] = [
        .nameKey,
        .isVolumeKey,
        .isPackageKey,
        .isDirectoryKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .linkCountKey,
        .fileResourceIdentifierKey,
        .isAliasFileKey,
        .totalFileSizeKey
    ]

    private static let packageProperties: [URLResourceKey] = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey
    ]
}

nonisolated private struct DiskInventoryZScanCounters {
    var fileCount: Int = 0
    var folderCount: Int = 0
}

nonisolated private enum DiskInventoryZScannerMetrics {
    static let continuationPollInterval: Int = 64
    static let rootEnumeratorLevel: Int = 1
    static let progressRefreshInterval: TimeInterval = 0.25
    static let itemIncrement: Int = 1
    static let parentStackOffset: Int = 1
    static let minimumStackDepth: Int = 1
    static let singleLinkCount: Int = 1
}

private typealias Metrics = DiskInventoryZScannerMetrics
