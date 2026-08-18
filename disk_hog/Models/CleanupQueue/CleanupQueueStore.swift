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
    /// Values cached from the most recently published scan tree.  Keeping
    /// scalars here avoids retaining a tree node while making list rendering
    /// independent of repeated path walks.
    var allocatedSize: UInt64
    var logicalSize: UInt64
    let source: ScanSource
    let sessionReference: ScanSessionWeakReference
    var isSelected: Bool
    var status: CleanupQueueItemStatus

    var volumeName: String { source.displayName }
    var parentPath: String { itemURL.deletingLastPathComponent().path }
}

@MainActor
final class CleanupQueueStore: ObservableObject {
    static let shared: CleanupQueueStore = CleanupQueueStore()

    @Published private(set) var items: [CleanupQueueItem] = []
    private let trashItem: @Sendable (URL, ScanSource) throws -> Void
    private let refreshSession: @MainActor (ScanSession) -> Void
    private var notificationCancellable: AnyCancellable?

    init(
        trashItem: @escaping @Sendable (URL, ScanSource) throws -> Void = CleanupQueueStore.moveToFinderTrash,
        refreshSession: @escaping @MainActor (ScanSession) -> Void = { session in
            guard let rootItem: DiskItem = session.rootItem else { return }
            session.refresh(rootItem)
        }
    ) {
        self.trashItem = trashItem
        self.refreshSession = refreshSession
        notificationCancellable = NotificationCenter.default.publisher(for: .scanSessionTreeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let session: ScanSession = notification.object as? ScanSession else {
                    return
                }
                self.refreshCachedSizes(for: session)
            }
    }

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
                sessionReference: ScanSessionWeakReference(session),
                isSelected: true,
                status: .ready
            )
        )
        return true
    }

    func contains(_ item: DiskItem) -> Bool {
        contains(at: item.url)
    }

    func contains(at itemURL: URL) -> Bool {
        let itemURL: URL = itemURL.standardizedFileURL
        return items.contains { queuedItem in
            queuedItem.itemURL == itemURL
                || (queuedItem.isFolder && DiskItemDeletionPolicy.contains(itemURL, in: queuedItem.itemURL))
        }
    }

    func isDirectlyQueued(_ item: DiskItem) -> Bool {
        isDirectlyQueued(at: item.url)
    }

    func isDirectlyQueued(at itemURL: URL) -> Bool {
        let itemURL: URL = itemURL.standardizedFileURL
        return items.contains { $0.itemURL == itemURL }
    }

    func remove(_ item: DiskItem) {
        remove(at: item.url)
    }

    func remove(at itemURL: URL) {
        let itemURL: URL = itemURL.standardizedFileURL
        items.removeAll { $0.itemURL == itemURL }
    }

    func remove(ids: Set<CleanupQueueItem.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    func removeAll() {
        items.removeAll()
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

        let trashItem: @Sendable (URL, ScanSource) throws -> Void = trashItem
        let refreshSession: @MainActor (ScanSession) -> Void = refreshSession
        Task { [trashItem, refreshSession] in
            var sessionsToRefresh: [ObjectIdentifier: ScanSession] = [:]
            for item: CleanupQueueItem in selectedItems {
                guard isProcessing(item.id) else {
                    continue
                }

                let cannotMoveToTrash: Bool = await Task.detached(priority: .userInitiated) {
                    Self.cannotMoveToFinderTrash(item.itemURL)
                }.value
                guard isProcessing(item.id) else {
                    continue
                }
                guard cannotMoveToTrash == false else {
                    updateStatus(.cannotMoveToTrash, for: item.id)
                    continue
                }

                let source: ScanSource = item.sessionReference.value?.source ?? item.source
                let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                    try trashItem(item.itemURL, source)
                }.result

                switch result {
                case .success:
                    remove(ids: [item.id])
                    if let session: ScanSession = item.sessionReference.value {
                        sessionsToRefresh[ObjectIdentifier(session)] = session
                    }
                case .failure(let error):
                    updateStatus(Self.status(for: error), for: item.id)
                }
            }
            for session: ScanSession in sessionsToRefresh.values {
                refreshSession(session)
            }
        }
    }

    private func updateStatus(_ status: CleanupQueueItemStatus, for id: CleanupQueueItem.ID) {
        guard let index: Int = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].status = status
    }

    private func refreshCachedSizes(for session: ScanSession) {
        guard let rootItem: DiskItem = session.rootItem else {
            return
        }

        var updatedItems: [CleanupQueueItem] = items
        var didChange: Bool = false
        for index: Int in updatedItems.indices where updatedItems[index].sessionReference.value === session {
            guard let currentItem: DiskItem = rootItem.item(atPath: updatedItems[index].itemURL.path) else {
                continue
            }
            let allocatedSize: UInt64 = currentItem.allocatedSizeValue
            let logicalSize: UInt64 = currentItem.logicalSizeValue
            guard updatedItems[index].allocatedSize != allocatedSize
                    || updatedItems[index].logicalSize != logicalSize else {
                continue
            }
            updatedItems[index].allocatedSize = allocatedSize
            updatedItems[index].logicalSize = logicalSize
            didChange = true
        }

        if didChange {
            items = updatedItems
        }
    }

    private func isProcessing(_ id: CleanupQueueItem.ID) -> Bool {
        items.contains { $0.id == id && $0.status == .processing }
    }

    private nonisolated static func moveToFinderTrash(
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
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: itemURL, resultingItemURL: &resultingURL)
    }

    private nonisolated static func cannotMoveToFinderTrash(_ itemURL: URL) -> Bool {
        guard let values: URLResourceValues = try? itemURL.resourceValues(
            forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey]
        ) else {
            return false
        }
        return values.volumeIsLocal == false || values.volumeIsReadOnly == true
    }

    private static func status(for error: Error) -> CleanupQueueItemStatus {
        let cocoaError: CocoaError? = error as? CocoaError
        switch cocoaError?.code {
        case .fileNoSuchFile:
            return .missing
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .inaccessible
        case .fileWriteVolumeReadOnly:
            return .cannotMoveToTrash
        default:
            return .failed(error.localizedDescription)
        }
    }
}
