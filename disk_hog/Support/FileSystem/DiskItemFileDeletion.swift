import Foundation

/// Shared filesystem mutation boundary. Callers retain ownership of queue status,
/// cancellation, and tree reconciliation; this operation never falls back from
/// moving to Trash to permanent deletion.
nonisolated enum DiskItemFileDeletion {
    /// The queue has no surrounding source-access lifetime, so acquire it here.
    static func moveToFinderTrash(
        itemURL: URL,
        source: ScanSource
    ) throws {
        let sourceURL: URL = try source.resolvingBookmark().url
        let didStartAccessing: Bool = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try perform(at: itemURL, using: .moveToTrash)
    }

    /// The tree worker already holds source access through reconciliation.
    /// Validate again at the actual mutation boundary, including for direct callers.
    static func perform(at url: URL, using method: DiskItemDeletionMethod) throws {
        try DiskItemDeletionPolicy.validateDeletion(at: url)
        switch method {
        case .deletePermanently:
            try FileManager.default.removeItem(at: url)
        case .moveToTrash:
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }
}
