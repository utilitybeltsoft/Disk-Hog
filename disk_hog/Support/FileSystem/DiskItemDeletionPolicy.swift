import AppKit
import Foundation
import Darwin

nonisolated enum DiskItemDeletionMethod: Sendable {
    case moveToTrash
    case deletePermanently
}

nonisolated enum DiskItemDeletionPolicy {
    enum Protection: String, Error, LocalizedError {
        case specialItem, protectedLocation, runningApplication, trash

        var errorDescription: String? {
            switch self {
            case .specialItem: String(localized: "Scan roots and synthetic items cannot be deleted.")
            case .protectedLocation: String(localized: "This location is protected from deletion.")
            case .runningApplication: String(localized: "The running application and its enclosing folders are protected.")
            case .trash: String(localized: "Items already in the Trash cannot be deleted here.")
            }
        }
    }

    private static let trashDirectoryCache: NSCache<NSString, NSURL> = NSCache()
    private static let accountLock = NSLock()
    private static let cachedHomes = accountHomes()
    private static let protectedContainers = ["/", "/Applications", "/Users", "/Library", "/usr", "/private", "/Volumes"]
        .map { entryURL(URL(fileURLWithPath: $0)) }
    private static let cachedApplication = canonicalURL(Bundle.main.bundleURL)

    /// Enumerate account records, including homes outside /Users. Serialize the
    /// process-wide passwd iterator; copy each string before advancing it.
    private static func accountHomes() -> [URL] {
        accountLock.withLock {
            var homes = [FileManager.default.homeDirectoryForCurrentUser]
            setpwent()
            defer { endpwent() }
            while let record = getpwent() {
                if let directory = record.pointee.pw_dir {
                    let path = String(cString: directory)
                    if path.hasPrefix("/"), path != "/" {
                        homes.append(URL(fileURLWithPath: path))
                    }
                }
            }
            return Array(Set(Set(homes).map { canonicalURL($0) }))
        }
    }

    static func canDelete(_ item: DiskItem, trashDirectoryURL: URL? = nil) -> Bool {
        !item.isSpecialItem && !item.isRoot
            && protection(for: item.url, trashDirectoryURL: trashDirectoryURL) == nil
    }

    static func validateDeletion(at url: URL) throws {
        if let reason = protection(for: url, refresh: true) { throw reason }
    }

    /// URL-level checks are also used immediately before filesystem mutation.
    /// Explicit context keeps tests independent of installed accounts and volumes.
    static func protection(
        for url: URL,
        homeDirectories: [URL]? = nil,
        applicationURL: URL? = nil,
        volumeURL: URL? = nil,
        trashDirectoryURL: URL? = nil,
        refresh: Bool = false
    ) -> Protection? {
        let entry = entryURL(url)
        let path = entry.path
        if protectedContainers.contains(entry)
            || isWithin(entry, directory: URL(fileURLWithPath: "/System")) {
            return .protectedLocation
        }

        let app = applicationURL.map { canonicalURL($0) } ?? (refresh ? canonicalURL(Bundle.main.bundleURL) : cachedApplication)
        if isWithin(entry, directory: app) || isWithin(app, directory: entry) { return .runningApplication }

        var homes = homeDirectories.map { $0.map { canonicalURL($0) } } ?? (refresh ? accountHomes() : cachedHomes)
        // Structural fallback also covers accounts unavailable to directory lookup.
        let components = entry.pathComponents
        if components.count >= 3, components[1] == "Users" {
            homes.append(URL(fileURLWithPath: "/Users").appendingPathComponent(components[2]))
        }
        for home in homes {
            if [home, home.appendingPathComponent("Library"), home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Desktop")].contains(entry)
                || isWithin(home, directory: entry) {
                return .protectedLocation
            }
            if isWithin(entry, directory: home.appendingPathComponent(".Trash")) { return .trash }
        }

        let volume = volumeURL ?? (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
        if let volume {
            if entry == canonicalURL(volume) { return .protectedLocation }
            if contains(entry, in: volume.appendingPathComponent(".Trashes")) { return .trash }
        }
        // Works even for unavailable/unmounted volumes or failed Trash lookup.
        if components.count == 3, components[1] == "Volumes" { return .protectedLocation }
        if (components.count >= 4 && components[1] == "Volumes" && components[3] == ".Trashes")
            || path == "/.Trashes" || path.hasPrefix("/.Trashes/") { return .trash }
        let trash = trashDirectoryURL ?? trashDirectory(for: url, refresh: refresh)
        if contains(entry, in: trash) { return .trash }
        return nil
    }

    /// Compare directory entries, not final symlink targets. A link outside a
    /// queued folder remains a separate deletion even when it points inside it.
    static func contains(_ itemURL: URL, in directoryURL: URL) -> Bool {
        isWithin(entryURL(itemURL), directory: entryURL(directoryURL))
    }

    /// Inputs already have their parent paths canonicalized.
    private static func isWithin(_ itemURL: URL, directory: URL) -> Bool {
        let itemComponents = itemURL.pathComponents
        let directoryComponents = directory.pathComponents
        return itemComponents.count >= directoryComponents.count
            && itemComponents.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }

    static func entryURL(_ url: URL) -> URL {
        guard url.path != "/" else { return url }
        return canonicalURL(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent)
    }

    private static func canonicalURL(_ url: URL) -> URL {
        if let resolved = realpath(url.path, nil) {
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
        guard url.path != "/" else { return url }
        return canonicalURL(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).standardizedFileURL
    }

    static func deletionMethod(for itemURL: URL) throws -> DiskItemDeletionMethod {
        let values: URLResourceValues = try itemURL.resourceValues(forKeys: [.volumeIsLocalKey])
        return values.volumeIsLocal == false ? .deletePermanently : .moveToTrash
    }

    static func trashDirectory(
        for itemURL: URL,
        refresh: Bool = false,
        cache: NSCache<NSString, NSURL> = trashDirectoryCache,
        resolve: (URL) throws -> URL = {
            try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                        appropriateFor: $0, create: false)
        }
    ) -> URL {
        let cacheKey: NSString = volumeIdentifier(for: itemURL) as NSString
        if !refresh, let cached = cache.object(forKey: cacheKey) {
            return cached as URL
        }

        guard let resolved = try? resolve(itemURL) else {
            // A fallback is useful for this check, but is not a resolved volume
            // Trash directory. Retry next time, including after a failed refresh
            // of a previously successful entry.
            cache.removeObject(forKey: cacheKey)
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        }
        cache.setObject(resolved as NSURL, forKey: cacheKey)
        return resolved
    }

    /// A cheap-enough-to-call-per-touch stand-in for "which volume is this on,"
    /// used only to group cache entries - falls back to the item's own path (still
    /// correct, just grouped per-item instead of per-volume) if the resource value
    /// can't be read.
    private static func volumeIdentifier(for itemURL: URL) -> String {
        (try? itemURL.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path ?? itemURL.path
    }
}

@MainActor
enum DiskItemDeletionCoordinator {
    static func requestQueueUndo(of item: DiskItem, queue: CleanupQueueStore) {
        queue.remove(item)
    }

    static func requestQueueing(
        of item: DiskItem,
        from session: ScanSession?,
        queue: CleanupQueueStore
    ) {
        guard let session else {
            return
        }
        guard queue.enqueue(item, from: session) else {
            return
        }
    }

    static func requestDeletion(
        of item: DiskItem,
        from session: ScanSession?,
        presentingWindow: NSWindow?
    ) {
        guard let session, DiskItemDeletionPolicy.canDelete(item) else {
            return
        }

        Task {
            do {
                let method: DiskItemDeletionMethod = try await Task.detached(priority: .userInitiated) {
                    try DiskItemDeletionPolicy.deletionMethod(for: item.url)
                }.value

                switch method {
                case .moveToTrash:
                    session.delete(item, using: .moveToTrash)
                case .deletePermanently:
                    confirmPermanentDeletion(
                        of: item,
                        from: session,
                        presentingWindow: presentingWindow
                    )
                }
            } catch {
                presentFailure(error, presentingWindow: presentingWindow)
            }
        }
    }

    private static func confirmPermanentDeletion(
        of item: DiskItem,
        from session: ScanSession,
        presentingWindow: NSWindow?
    ) {
        let alert: NSAlert = NSAlert()
        alert.messageText = String(
            localized: "\"\(item.displayName)\" cannot be moved to the Trash."
        )
        alert.informativeText = String(
            localized: "This item is on a network volume. Do you want to delete it permanently?"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete Permanently"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        present(alert, on: presentingWindow) { response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            session.delete(item, using: .deletePermanently)
        }
    }

    private static func presentFailure(_ error: Error, presentingWindow: NSWindow?) {
        let alert: NSAlert = NSAlert(error: error)
        present(alert, on: presentingWindow) { _ in }
    }

    private static func present(
        _ alert: NSAlert,
        on window: NSWindow?,
        completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) {
        if let window {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    completion(response)
                }
            }
        } else {
            completion(alert.runModal())
        }
    }
}
