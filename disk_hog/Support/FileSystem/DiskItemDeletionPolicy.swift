import AppKit
import Foundation

nonisolated enum DiskItemDeletionMethod: Sendable {
    case moveToTrash
    case deletePermanently
}

nonisolated enum DiskItemDeletionPolicy {
    static func canDelete(
        _ item: DiskItem,
        trashDirectoryURL: URL? = nil
    ) -> Bool {
        guard !item.isSpecialItem, !item.isRoot else {
            return false
        }

        let resolvedTrashURL: URL? = trashDirectoryURL ?? trashDirectory(for: item.url)
        return resolvedTrashURL.map {
            !contains(item.url, in: $0)
        } ?? true
    }

    static func contains(_ itemURL: URL, in directoryURL: URL) -> Bool {
        let itemComponents: [String] = standardizedComponents(of: itemURL)
        let directoryComponents: [String] = standardizedComponents(of: directoryURL)
        guard itemComponents.count >= directoryComponents.count else {
            return false
        }
        return itemComponents.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }

    static func deletionMethod(for itemURL: URL) throws -> DiskItemDeletionMethod {
        let values: URLResourceValues = try itemURL.resourceValues(forKeys: [.volumeIsLocalKey])
        return values.volumeIsLocal == false ? .deletePermanently : .moveToTrash
    }

    private static func trashDirectory(for itemURL: URL) -> URL? {
        if let volumeTrashURL: URL = try? FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: itemURL,
            create: false
        ) {
            return volumeTrashURL
        }

        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    private static func standardizedComponents(of url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}

@MainActor
enum DiskItemDeletionCoordinator {
    static func requestQueueing(
        of item: DiskItem,
        from session: ScanSession?
    ) {
        guard let session else {
            return
        }
        guard CleanupQueueStore.shared.enqueue(item, from: session) else {
            return
        }
        InspectorWindowController.shared.show(tab: .cleanupQueue)
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
