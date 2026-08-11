import Combine
import Foundation

enum CleanupQueueItemStatus: Equatable {
    case ready
    case missing
    case inaccessible
    case cannotMoveToTrash
    case processing
    case failed(String)
}

@MainActor
struct CleanupQueueItem: Identifiable {
    let id: UUID
    let itemURL: URL
    let displayName: String
    let isFolder: Bool
    let allocatedSize: UInt64
    let logicalSize: UInt64
    let source: ScanSource
    let session: ScanSession
    var isSelected: Bool
    var status: CleanupQueueItemStatus

    var volumeName: String { source.displayName }
    var parentPath: String { itemURL.deletingLastPathComponent().path }
}

@MainActor
final class CleanupQueueStore: ObservableObject {
    static let shared: CleanupQueueStore = CleanupQueueStore()

    @Published private(set) var items: [CleanupQueueItem] = []

    private init() {}

    @discardableResult
    func enqueue(_ item: DiskItem, from session: ScanSession) -> Bool {
        guard DiskItemDeletionPolicy.canDelete(item) else {
            return false
        }

        let itemURL: URL = item.url.standardizedFileURL
        guard !contains(item) else {
            return false
        }

        if item.isFolder {
            items.removeAll { queuedItem in
                DiskItemDeletionPolicy.contains(queuedItem.itemURL, in: itemURL)
            }
        }

        items.append(
            CleanupQueueItem(
                id: UUID(),
                itemURL: itemURL,
                displayName: item.displayName,
                isFolder: item.isFolder,
                allocatedSize: item.allocatedSizeValue,
                logicalSize: item.logicalSizeValue,
                source: session.source,
                session: session,
                isSelected: true,
                status: .ready
            )
        )
        return true
    }

    func contains(_ item: DiskItem) -> Bool {
        let itemURL: URL = item.url.standardizedFileURL
        return items.contains { queuedItem in
            queuedItem.itemURL == itemURL
                || (queuedItem.isFolder && DiskItemDeletionPolicy.contains(itemURL, in: queuedItem.itemURL))
        }
    }

    func isDirectlyQueued(_ item: DiskItem) -> Bool {
        let itemURL: URL = item.url.standardizedFileURL
        return items.contains { $0.itemURL == itemURL }
    }

    func remove(_ item: DiskItem) {
        let itemURL: URL = item.url.standardizedFileURL
        items.removeAll { $0.itemURL == itemURL }
    }

    func remove(ids: Set<CleanupQueueItem.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    func removeAll() {
        items.removeAll()
    }

    func enqueueDroppedItem(at url: URL) {
        guard let queuedItem: (item: DiskItem, session: ScanSession) = ScanWindowRegistry.shared.queuedItem(at: url) else {
            return
        }
        _ = enqueue(queuedItem.item, from: queuedItem.session)
    }

    func enqueue(_ items: [DiskItem], from session: ScanSession) {
        let sortedItems: [DiskItem] = items
            .filter { DiskItemDeletionPolicy.canDelete($0) }
            .sorted { $0.url.pathComponents.count < $1.url.pathComponents.count }
        var queuedParentURLs: [URL] = []
        for item: DiskItem in sortedItems {
            guard !queuedParentURLs.contains(where: { DiskItemDeletionPolicy.contains(item.url, in: $0) }) else {
                continue
            }
            _ = enqueue(item, from: session)
            if item.isFolder {
                queuedParentURLs.append(item.url)
            }
        }
    }

    func setSelected(_ isSelected: Bool, for id: CleanupQueueItem.ID) {
        guard let index: Int = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].isSelected = isSelected
    }

    var selectedReadyItems: [CleanupQueueItem] {
        items.filter { $0.isSelected && $0.status == .ready }
    }

    func moveSelectedItemsToFinderTrash() {
        let selectedItems: [CleanupQueueItem] = selectedReadyItems
        guard !selectedItems.isEmpty else {
            return
        }

        for item: CleanupQueueItem in selectedItems {
            updateStatus(.processing, for: item.id)
        }

        Task {
            for item: CleanupQueueItem in selectedItems {
                let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                    try CleanupQueueStore.moveToFinderTrash(
                        itemURL: item.itemURL,
                        sourceBookmarkData: item.source.bookmarkData
                    )
                }.result

                switch result {
                case .success:
                    remove(ids: [item.id])
                    item.session.refresh(
                        DiskItem(
                            url: item.itemURL.deletingLastPathComponent(),
                            isDirectory: true,
                            isRoot: false
                        )
                    )
                case .failure(let error):
                    updateStatus(Self.status(for: error), for: item.id)
                }
            }
        }
    }

    private func updateStatus(_ status: CleanupQueueItemStatus, for id: CleanupQueueItem.ID) {
        guard let index: Int = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].status = status
    }

    private nonisolated static func moveToFinderTrash(
        itemURL: URL,
        sourceBookmarkData: Data?
    ) throws {
        let sourceURL: URL?
        if let sourceBookmarkData {
            var isStale: Bool = false
            sourceURL = try URL(
                resolvingBookmarkData: sourceBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } else {
            sourceURL = nil
        }
        let didStartAccessing: Bool = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStartAccessing {
                sourceURL?.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: itemURL, resultingItemURL: &resultingURL)
    }

    private static func status(for error: Error) -> CleanupQueueItemStatus {
        let cocoaError: CocoaError? = error as? CocoaError
        switch cocoaError?.code {
        case .fileNoSuchFile:
            return .missing
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .inaccessible
        default:
            return .failed(error.localizedDescription)
        }
    }
}
