import Foundation

/// One coherent published tree. Copying this value shares the packed DiskItem
/// snapshot; it does not copy nodes or traverse the tree.
struct ScanSessionSnapshot {
    var source: ScanSource
    var root: DiskItem?
    var metrics: TreemapPresentationMetrics?
    var selection: DiskItem?
    var skippedItems: [ScanSkippedItem] = []
    var freshness = SnapshotFreshness()
    var fileCount = 0
    var folderCount = 0
    var byteCount: UInt64 = 0
    var appliedSizeMode: Bool?
    var space = ScanSessionSpaceItems()

    mutating func clearForScan() {
        self = ScanSessionSnapshot(source: source, freshness: freshness)
    }

    mutating func acceptScan(_ result: ScanSessionScanResult, files: Int, folders: Int,
                             usePhysicalSize: Bool, startedAt: Date, finishedAt: Date) {
        source = result.source
        root = result.rootItem
        metrics = result.presentationMetrics
        selection = result.rootItem
        skippedItems = result.skippedItems
        fileCount = files
        folderCount = folders
        appliedSizeMode = result.builtUsingPhysicalSize
        updateSizes(usePhysicalSize: usePhysicalSize)
        freshness.record(startedAt: startedAt, finishedAt: finishedAt,
                         hasSkippedItems: !skippedItems.isEmpty,
                         refreshedPath: result.rootItem.path, rootPath: result.rootItem.path)
    }

    mutating func acceptTree(_ result: ScanSessionTreeUpdateResult, usePhysicalSize: Bool,
                             refreshStartedAt: Date?, finishedAt: Date, preserveSelection: Bool = false) {
        let selectionPath = preserveSelection ? (selection?.path ?? result.selectionPath) : result.selectionPath
        source = result.source
        root = result.rootItem
        metrics = result.presentationMetrics
        selection = result.rootItem.item(atPath: selectionPath, allowAncestors: true) ?? result.rootItem
        if let removedPaths = result.removedSubtreePaths {
            skippedItems.removeAll { skipped in
                removedPaths.contains { FilePathContainment.contains(skipped.path, in: $0) }
            }
        } else {
            skippedItems = Self.mergingSkippedItems(skippedItems, replacingSubtreeAt: result.refreshedSubtreePath,
                                                   with: result.skippedItems)
        }
        let counts = result.rootItem.scanCounts(includeSelf: false)
        fileCount = counts.files
        folderCount = counts.folders
        appliedSizeMode = result.builtUsingPhysicalSize
        updateSizes(usePhysicalSize: usePhysicalSize)
        if let refreshStartedAt {
            freshness.record(startedAt: refreshStartedAt, finishedAt: finishedAt,
                             hasSkippedItems: !result.skippedItems.isEmpty,
                             refreshedPath: result.refreshedSubtreePath, rootPath: result.rootItem.path)
        }
    }

    mutating func acceptSizeMode(_ result: ScanSessionSizeModeUpdateResult) {
        root = result.rootItem
        metrics = result.presentationMetrics
        selection = result.rootItem.item(atPath: result.selectionPath, allowAncestors: true) ?? result.rootItem
        appliedSizeMode = result.usePhysicalSize
        updateSizes(usePhysicalSize: result.usePhysicalSize)
    }

    private mutating func updateSizes(usePhysicalSize: Bool) {
        guard let root else { return }
        byteCount = root.sizeValue(usePhysicalSize: usePhysicalSize)
        space = ScanSessionSpaceItems(source: source, scannedSize: byteCount)
    }

    func isAffectedBySkippedContent(_ item: DiskItem) -> Bool {
        skippedItems.contains { FilePathContainment.contains($0.path, in: item.path) }
    }

    static func mergingSkippedItems(_ existing: [ScanSkippedItem], replacingSubtreeAt path: String,
                                    with newItems: [ScanSkippedItem]) -> [ScanSkippedItem] {
        existing.filter { !FilePathContainment.contains($0.path, in: path) } + newItems
    }
}

struct ScanSessionSpaceItems {
    var free: DiskItem?
    var other: DiskItem?

    init() {}

    init(source: ScanSource, scannedSize: UInt64) {
        guard source.volumeKind != .folder, let total = source.totalCapacity,
              let available = source.availableCapacity, total >= available else { return }
        let used = total - available
        let otherSize = used > scannedSize ? used - scannedSize : 0
        free = DiskItem(url: source.url, itemType: .freeSpace,
                        allocatedSizeValue: available, logicalSizeValue: available)
        other = DiskItem(url: source.url, itemType: .otherSpace,
                         allocatedSizeValue: otherSize, logicalSizeValue: otherSize)
    }
}

struct ScanSessionActivity {
    var state: ScanSessionState = .ready
    var startedAt: Date?
    var completedAt: Date?
    var fileCount = 0
    var folderCount = 0
    var byteCount: UInt64 = 0
    var currentPath: String
    var stage: DiskScanStage = .enumeratingRootItems
    var isUpdatingTree = false
    var isBuildingTreemap = false
    var treemapProgress: Double?
    var packageContentsOutOfSync = false

    mutating func beginScan(path: String, now: Date) {
        self = ScanSessionActivity(state: .scanning, startedAt: now, currentPath: path,
                                  packageContentsOutOfSync: packageContentsOutOfSync)
    }

    mutating func apply(_ progress: DiskScanProgress) {
        fileCount = progress.scannedFileCount
        folderCount = progress.scannedFolderCount
        byteCount = progress.scannedByteCount
        currentPath = progress.currentPath
    }

    func elapsedTime(referenceDate: Date) -> TimeInterval {
        guard let startedAt else { return .zero }
        return max(.zero, (completedAt ?? referenceDate).timeIntervalSince(startedAt))
    }
}

struct ScanSessionSpaceVisibility {
    var free = false
    var other = false
}
