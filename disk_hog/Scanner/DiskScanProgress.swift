import Foundation

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
