import Foundation

nonisolated final class DiskDirectoryTraversal {
    private let hardlinkDeduplicator: any HardlinkDeduplicating
    private let itemFactory: any DiskItemBuilding
    private let packageSizer: any OpaquePackageSizing
    private let resourceValuesProvider: DiskInventoryZScanner.ResourceValuesProvider

    init(
        resourceValuesProvider: @escaping DiskInventoryZScanner.ResourceValuesProvider,
        hardlinkDeduplicator: any HardlinkDeduplicating,
        itemFactory: any DiskItemBuilding,
        packageSizer: any OpaquePackageSizing
    ) {
        self.resourceValuesProvider = resourceValuesProvider
        self.hardlinkDeduplicator = hardlinkDeduplicator
        self.itemFactory = itemFactory
        self.packageSizer = packageSizer
    }

    func loadChildren(
        of item: DiskItemBuilder,
        settings: DiskScanSettings,
        progressState: ScanProgressState,
        progressHandler: DiskInventoryZScanner.ProgressHandler?
    ) async throws -> ScanProgressState {
        var progressState: ScanProgressState = progressState
        if !item.isFolder {
            return progressState
        }

        progressState.updateCurrentPath(item.path)
        if progressState.shouldPublish() {
            await progressHandler?(progressState.snapshot())
        }
        item.removeAllChildren()

        var itemStack: [DiskItemBuilder] = [item]
        guard let directoryEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(
            at: item.url,
            includingPropertiesForKeys: DiskScanResourceKeys.item,
            options: [],
            errorHandler: { url, _ in url != item.url }
        ) else {
            item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
            progressState.setScannedBytes(item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
            return progressState
        }

        var lastEnumLevel: Int = 1
        var lastItemWasDirectory: Bool = false
        var lastDirectoryItem: DiskItemBuilder?
        var filesSinceYield: Int = 0

        while let currentURL: URL = directoryEnumerator.nextObject() as? URL {
            filesSinceYield += 1
            if filesSinceYield >= 64 {
                filesSinceYield = 0
                try Task.checkCancellation()
                if progressState.shouldPublish() {
                    await progressHandler?(progressState.snapshot())
                }
            }
            if DiskScanFileSystemRules.shouldSkip(currentURL) {
                directoryEnumerator.skipDescendants()
                continue
            }

            let currentValues: URLResourceValues
            do {
                currentValues = try resourceValuesProvider(currentURL, Set(DiskScanResourceKeys.item))
            } catch {
                directoryEnumerator.skipDescendants()
                continue
            }

            if directoryEnumerator.level > lastEnumLevel {
                if let lastDirectoryItem: DiskItemBuilder = lastDirectoryItem {
                    itemStack.append(lastDirectoryItem)
                } else if lastItemWasDirectory {
                    throw DiskScannerError.traversalInconsistency(
                        "A directory was reported without a matching item."
                    )
                }
            } else if directoryEnumerator.level < lastEnumLevel {
                let levelsWalkedUp: Int = lastEnumLevel - directoryEnumerator.level
                for _: Int in 0..<levelsWalkedUp where itemStack.count > 1 {
                    itemStack.removeLast()
                }
            }

            guard let parentItem: DiskItemBuilder = itemStack.last else {
                throw DiskScannerError.traversalInconsistency(
                    "A child item was reported without a parent."
                )
            }

            let currentItem: DiskItemBuilder = itemFactory.makeItem(
                url: currentURL,
                values: currentValues,
                in: item
            )
            parentItem.appendChild(currentItem, updateSize: false)
            progressState.recordItem(currentItem)
            let isCurrentDirectory: Bool = currentValues.isDirectory ?? false

            if !isCurrentDirectory {
                hardlinkDeduplicator.markDuplicateIfNeeded(item: currentItem, values: currentValues)
            }

            if DiskScanFileSystemRules.isFirmlink(currentURL) {
                directoryEnumerator.skipDescendants()
                progressState = try await loadChildren(
                    of: currentItem,
                    settings: settings,
                    progressState: progressState,
                    progressHandler: progressHandler
                )
            } else if currentValues.isVolume ?? false {
                directoryEnumerator.skipDescendants()
            } else if (currentValues.isPackage ?? false) && !settings.lookInsidePackages {
                directoryEnumerator.skipDescendants()
                let packageSize: OpaquePackageSize = try packageSizer.size(of: currentURL)
                currentItem.setOpaquePackageSize(
                    allocated: packageSize.allocated,
                    logical: packageSize.logical
                )
            } else if !isCurrentDirectory {
                let byteCount: UInt64 = currentItem.isHardlinkDuplicate
                    ? 0
                    : currentItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
                progressState.addScannedBytes(byteCount)
            }

            if isCurrentDirectory {
                progressState.updateCurrentPath(currentURL.path)
            }
            lastItemWasDirectory = isCurrentDirectory
            lastDirectoryItem = lastItemWasDirectory ? currentItem : nil
            lastEnumLevel = directoryEnumerator.level
        }

        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        progressState.setScannedBytes(item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        return progressState
    }
}
