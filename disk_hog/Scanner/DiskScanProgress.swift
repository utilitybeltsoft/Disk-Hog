import Foundation

nonisolated enum DiskScanStage: Equatable, Sendable {
    case enumeratingRootItems
    case scanningFiles
    case packagingScanResults(percent: Int)
    case finalizingScan
}

/// Combines all subtree packing work, publishing only once traversal has fixed
/// the grand total. Work completed before that point still counts.
nonisolated final class ScanPackagingProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingTraversals: Int
    private var totalUnits = 0
    private var completedUnits = 0
    private var lastPercent = -1
    private let continuation: AsyncStream<Int>.Continuation

    init(subtreeCount: Int, continuation: AsyncStream<Int>.Continuation) {
        remainingTraversals = subtreeCount
        self.continuation = continuation
    }

    func finishTraversal(itemCount: Int) {
        lock.withLock {
            totalUnits += itemCount * 4
            remainingTraversals -= 1
            publishIfNeeded()
        }
    }

    func advance(by units: Int) {
        lock.withLock {
            completedUnits += units
            publishIfNeeded()
        }
    }

    private func publishIfNeeded() {
        guard remainingTraversals == 0, totalUnits > 0 else { return }
        let percent = Int(Double(completedUnits) / Double(totalUnits) * 100)
        guard percent > lastPercent else { return }
        lastPercent = percent
        continuation.yield(percent)
    }
}

nonisolated struct DiskScanProgress: Sendable {
    let scannedFileCount: Int
    let scannedFolderCount: Int
    let scannedByteCount: UInt64
    let currentPath: String
}

nonisolated enum DiskScannerError: LocalizedError {
    case topLevelEnumerationFailed(path: String, underlyingDescription: String)
    case itemOutsideScanRoot(path: String)
    case traversalInconsistency(String)

    var errorDescription: String? {
        switch self {
        case let .topLevelEnumerationFailed(path, underlyingDescription):
            return String(localized: "Could not list the top level of \"\(path)\". \(underlyingDescription)")
        case let .itemOutsideScanRoot(path):
            return String(localized: "Could not refresh \"\(path)\" because it is outside the scanned folder.")
        case let .traversalInconsistency(detail):
            return String(localized: "Scanner traversal failed because the directory structure changed unexpectedly. \(detail)")
        }
    }
}
