import Foundation

nonisolated struct DiskScanProgress: Sendable {
    let scannedFileCount: Int
    let scannedFolderCount: Int
    let scannedByteCount: UInt64
    let currentPath: String
}

nonisolated enum DiskScannerError: LocalizedError {
    case topLevelEnumerationFailed(path: String, underlyingDescription: String)
    case zMethodNotPorted(String)

    var errorDescription: String? {
        switch self {
        case let .topLevelEnumerationFailed(path, underlyingDescription):
            return "Could not list the top level of \"\(path)\". \(underlyingDescription)"
        case let .zMethodNotPorted(methodName):
            return "Scanner method is not implemented yet: \(methodName)."
        }
    }
}
