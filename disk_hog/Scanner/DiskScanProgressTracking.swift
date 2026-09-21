import Foundation

actor ScanProgressAggregator {
    private var activeProgressByChild: [Int: DiskScanProgress] = [:]
    private var completedFileCount: Int = 0
    private var completedFolderCount: Int = 0
    private var completedByteCount: UInt64 = 0
    private var currentPath: String
    private var publicationRateLimiter: ScanProgressRateLimiter = ScanProgressRateLimiter()
    private var lastPublishedByteCount: UInt64 = 0

    init(currentPath: String) {
        self.currentPath = currentPath
    }

    var scannedFileCount: Int {
        completedFileCount + activeProgressByChild.values.reduce(0) { $0 + $1.scannedFileCount }
    }

    var scannedFolderCount: Int {
        completedFolderCount + activeProgressByChild.values.reduce(0) { $0 + $1.scannedFolderCount }
    }

    func updateChild(id: Int, progress: DiskScanProgress) -> DiskScanProgress? {
        activeProgressByChild[id] = progress
        currentPath = progress.currentPath
        guard publicationRateLimiter.shouldPublish() else {
            return nil
        }
        return snapshot()
    }

    func finishChild(id: Int, progress: DiskScanProgress) -> DiskScanProgress {
        activeProgressByChild[id] = nil
        completedFileCount += progress.scannedFileCount
        completedFolderCount += progress.scannedFolderCount
        completedByteCount += progress.scannedByteCount
        currentPath = progress.currentPath
        return snapshot()
    }

    private func snapshot() -> DiskScanProgress {
        let activeProgress: [DiskScanProgress] = Array(activeProgressByChild.values)
        let computedByteCount: UInt64 = completedByteCount + activeProgress.reduce(0) { $0 + $1.scannedByteCount }
        let byteCount: UInt64 = max(lastPublishedByteCount, computedByteCount)
        lastPublishedByteCount = byteCount
        return DiskScanProgress(
            scannedFileCount: completedFileCount + activeProgress.reduce(0) { $0 + $1.scannedFileCount },
            scannedFolderCount: completedFolderCount + activeProgress.reduce(0) { $0 + $1.scannedFolderCount },
            scannedByteCount: byteCount,
            currentPath: currentPath
        )
    }
}

nonisolated struct ScanProgressState {
    private(set) var scannedFileCount: Int = 0
    private(set) var scannedFolderCount: Int = 0
    private(set) var scannedByteCount: UInt64 = 0
    private(set) var currentPath: String
    private(set) var skippedItems: [ScanSkippedItem] = []
    private var publicationRateLimiter: ScanProgressRateLimiter = ScanProgressRateLimiter()

    init(currentPath: String) {
        self.currentPath = currentPath
    }

    mutating func recordItem(_ item: DiskItemBuilder) {
        if item.isFolder {
            scannedFolderCount += 1
        } else {
            scannedFileCount += 1
        }
    }

    mutating func recordSkippedItem(_ item: ScanSkippedItem) {
        skippedItems.append(item)
    }

    mutating func setScannedFileCount(_ count: Int) { scannedFileCount = count }
    mutating func setScannedFolderCount(_ count: Int) { scannedFolderCount = count }
    mutating func addScannedBytes(_ byteCount: UInt64) { scannedByteCount += byteCount }
    mutating func setScannedBytes(_ byteCount: UInt64) { scannedByteCount = byteCount }
    mutating func updateCurrentPath(_ path: String) { currentPath = path }
    mutating func shouldPublish() -> Bool { publicationRateLimiter.shouldPublish() }

    func snapshot() -> DiskScanProgress {
        DiskScanProgress(
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            scannedByteCount: scannedByteCount,
            currentPath: currentPath
        )
    }
}

nonisolated private struct ScanProgressRateLimiter {
    private static let refreshInterval: TimeInterval = 0.25
    private var lastPublishTime: CFAbsoluteTime = 0

    mutating func shouldPublish() -> Bool {
        let now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        if lastPublishTime != 0 && now - lastPublishTime < Self.refreshInterval {
            return false
        }
        lastPublishTime = now
        return true
    }
}
