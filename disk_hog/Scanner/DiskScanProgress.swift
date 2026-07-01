import Foundation

nonisolated struct DiskScanProgress: Sendable {
    let scannedFileCount: Int
    let scannedFolderCount: Int
    let scannedByteCount: UInt64
    let currentPath: String
}

nonisolated enum DiskScannerError: Error, Equatable {
    case topLevelEnumerationFailed
    case zMethodNotPorted(String)
}
