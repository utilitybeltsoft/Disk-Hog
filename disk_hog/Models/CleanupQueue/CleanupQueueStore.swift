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
        guard !items.contains(where: { queuedItem in
            queuedItem.itemURL == itemURL
                || (queuedItem.isFolder && DiskItemDeletionPolicy.contains(itemURL, in: queuedItem.itemURL))
        }) else {
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

    func remove(ids: Set<CleanupQueueItem.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    func removeAll() {
        items.removeAll()
    }

    func setSelected(_ isSelected: Bool, for id: CleanupQueueItem.ID) {
        guard let index: Int = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].isSelected = isSelected
    }
}
