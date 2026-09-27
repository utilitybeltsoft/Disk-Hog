import Foundation

/// Evidence from real directory access, not an authoritative TCC permission query.
nonisolated enum FullDiskAccessStatus: Equatable, Sendable {
    case available
    case protectedAccessDenied
    case inconclusive
}

nonisolated enum FileAccessFailure: Equatable {
    case protectedAccessDenied
    case filesystemPermission
    case missing
    case other

    static func classify(_ error: Error) -> Self {
        let error = error as NSError
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return classify(underlying)
        }
        if error.domain == NSPOSIXErrorDomain {
            switch error.code {
            case Int(EPERM): return .protectedAccessDenied
            case Int(EACCES): return .filesystemPermission
            case Int(ENOENT), Int(ENOTDIR): return .missing
            default: return .other
            }
        }
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError: return .protectedAccessDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .missing
            default: return .other
            }
        }
        return .other
    }
}

nonisolated struct FullDiskAccessService: Sendable {
    let directories: [URL]
    let listDirectory: @Sendable (URL) throws -> Void

    init(directories: [URL] = Self.protectedDirectories(),
         listDirectory: @escaping @Sendable (URL) throws -> Void = {
             _ = try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
         }) {
        self.directories = directories
        self.listDirectory = listDirectory
    }

    static func protectedDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Mail", "Messages", "Safari", "Application Support/AddressBook"].map {
            home.appendingPathComponent("Library", isDirectory: true).appendingPathComponent($0, isDirectory: true)
        }
    }

    /// Attempt access even before Settings opens so macOS can record the requesting app.
    /// Do not inspect or modify TCC databases, and do not read users' file contents.
    func check() -> FullDiskAccessStatus {
        var readable = 0
        var denied = false
        var uncertain = false
        for directory in directories {
            do {
                try listDirectory(directory)
                readable += 1
            } catch {
                switch FileAccessFailure.classify(error) {
                case .protectedAccessDenied: denied = true
                case .filesystemPermission, .other: uncertain = true
                case .missing: break
                }
            }
        }
        if denied { return .protectedAccessDenied }
        return readable >= 2 && !uncertain ? .available : .inconclusive
    }

    func checkAsync() async -> FullDiskAccessStatus {
        await Task.detached(priority: .utility) { check() }.value
    }
}
