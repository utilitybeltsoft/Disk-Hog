import Darwin
import Foundation

nonisolated final class ScanSessionWeakReference: @unchecked Sendable {
    weak var value: ScanSession?

    init(_ value: ScanSession) {
        self.value = value
    }
}

nonisolated enum ScanSessionWorkOperation: Equatable, Sendable {
    case scan(UUID)
    case treeUpdate(UUID)
}

extension ScanSessionWorkOperation {
    var id: UUID {
        switch self {
        case .scan(let id), .treeUpdate(let id):
            id
        }
    }
}

nonisolated struct ScanSessionRescanCoordinator {
    private(set) var activeOperation: ScanSessionWorkOperation?
    private var hasPendingRescan: Bool = false

    mutating func beginScan() -> ScanSessionWorkOperation {
        begin(.scan(UUID()))
    }

    mutating func beginTreeUpdate() -> ScanSessionWorkOperation {
        begin(.treeUpdate(UUID()))
    }

    mutating func requestRescan() -> ScanSessionWorkOperation? {
        guard let activeOperation else {
            return nil
        }
        hasPendingRescan = true
        return activeOperation
    }

    mutating func finish(_ operation: ScanSessionWorkOperation) -> Bool {
        guard activeOperation == operation else {
            return false
        }
        activeOperation = nil
        return true
    }

    mutating func consumePendingRescan() -> Bool {
        defer { hasPendingRescan = false }
        return hasPendingRescan
    }

    private mutating func begin(_ operation: ScanSessionWorkOperation) -> ScanSessionWorkOperation {
        precondition(activeOperation == nil)
        activeOperation = operation
        return operation
    }
}

enum ScanSessionState: Hashable {
    case ready
    case scanning
    case complete
    case cancelled
    case failed

    var title: String {
        switch self {
        case .ready:
            return String(localized: "Ready")
        case .scanning:
            return String(localized: "Scanning")
        case .complete:
            return String(localized: "Complete")
        case .cancelled:
            return String(localized: "Cancelled")
        case .failed:
            return String(localized: "Failed")
        }
    }
}

enum ScanSessionOperation: Equatable {
    case scan(itemName: String)
    case refresh(itemName: String)
    case deletion(itemName: String, method: DiskItemDeletionMethod)

    var itemName: String {
        switch self {
        case .scan(let itemName), .refresh(let itemName), .deletion(let itemName, _):
            return itemName
        }
    }

    var action: String {
        switch self {
        case .scan:
            return String(localized: "scan")
        case .refresh:
            return String(localized: "refresh")
        case .deletion(_, .moveToTrash):
            return String(localized: "move to the Trash")
        case .deletion(_, .deletePermanently):
            return String(localized: "delete")
        }
    }
}

struct ScanSessionFailure: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let recoverySuggestion: String

    init(error: Error, operation: ScanSessionOperation) {
        self.id = UUID()
        self.title = String(localized: "Couldn't \(operation.action) \"\(operation.itemName)\".")

        switch Self.category(for: error) {
        case .permissionDenied:
            self.message = String(localized: "Disk Hog does not have permission to \(operation.action) this item.")
            self.recoverySuggestion = String(localized: "Check the item's permissions, or choose a folder that Disk Hog is allowed to access.")
        case .readOnlyVolume:
            self.message = String(localized: "This volume is read-only, so Disk Hog cannot \(operation.action) this item.")
            self.recoverySuggestion = String(localized: "Choose a writable volume, or make the change in Finder if it is available there.")
        case .itemUnavailable:
            self.message = String(localized: "The item is no longer available at the expected location.")
            self.recoverySuggestion = String(localized: "Refresh the enclosing folder or scan it again.")
        case .busyOrProtected:
            self.message = String(localized: "The item may be in use, locked, or protected by macOS.")
            self.recoverySuggestion = String(localized: "Close apps that may be using it, then try again. If it is protected, use Finder or change its permissions first.")
        case .other:
            self.message = error.localizedDescription
            self.recoverySuggestion = String(localized: "Try again. If the problem continues, check that the volume is available and that Disk Hog has access to it.")
        }
    }

    var statusMessage: String {
        title
    }

    private enum Category {
        case permissionDenied
        case readOnlyVolume
        case itemUnavailable
        case busyOrProtected
        case other
    }

    private static func category(for error: Error) -> Category {
        let errors: [NSError] = errorChain(startingAt: error as NSError)

        if errors.contains(where: { $0.domain == NSPOSIXErrorDomain && $0.code == Int(EROFS) })
            || errors.contains(where: { $0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteVolumeReadOnlyError }) {
            return .readOnlyVolume
        }
        if errors.contains(where: { $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EACCES) || $0.code == Int(EPERM)) })
            || errors.contains(where: {
                $0.domain == NSCocoaErrorDomain
                    && ($0.code == NSFileReadNoPermissionError || $0.code == NSFileWriteNoPermissionError)
            }) {
            return .permissionDenied
        }
        if errors.contains(where: { $0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOENT) })
            || errors.contains(where: {
                $0.domain == NSCocoaErrorDomain
                    && ($0.code == NSFileNoSuchFileError || $0.code == NSFileReadNoSuchFileError)
            }) {
            return .itemUnavailable
        }
        if errors.contains(where: { $0.domain == NSPOSIXErrorDomain && $0.code == Int(EBUSY) }) {
            return .busyOrProtected
        }
        return .other
    }

    private static func errorChain(startingAt error: NSError) -> [NSError] {
        var errors: [NSError] = [error]
        var currentError: NSError? = error
        while let underlyingError: NSError = currentError?.userInfo[NSUnderlyingErrorKey] as? NSError,
              !errors.contains(where: { $0 === underlyingError }) {
            errors.append(underlyingError)
            currentError = underlyingError
        }
        return errors
    }
}

#if FILE_MATCHING_DIAGNOSTICS
enum DiagnosticsExportState: Hashable {
    case idle
    case writing(String)
    case written(String)
    case failed(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .writing(let path):
            return "Writing diagnostics: \(path)"
        case .written(let path):
            return "Diagnostics written: \(path)"
        case .failed(let message):
            return "Diagnostics failed: \(message)"
        }
    }

    var isWriting: Bool {
        if case .writing = self {
            return true
        }

        return false
    }
}
#endif
