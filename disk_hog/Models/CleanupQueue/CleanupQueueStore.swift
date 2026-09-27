import Combine
import Foundation

enum CleanupQueueItemStatus: Equatable {
    case ready
    case missing
    case inaccessible
    case cannotMoveToTrash
    case protected
    case processing
    case failed(String)
}

@MainActor
struct CleanupQueueItem: Identifiable {
    let id: UUID
    let itemURL: URL
    let treePath: String
    let displayName: String
    let isFolder: Bool
    /// Values cached from the most recently published scan tree.  Keeping
    /// scalars here avoids retaining a tree node while making list rendering
    /// independent of repeated path walks.
    var allocatedSize: UInt64
    var logicalSize: UInt64
    /// True when the scan couldn't determine this item's real size (e.g. a
    /// permission-denied folder) - `allocatedSize`/`logicalSize` are then just the
    /// scanner's placeholder 0, not a verified empty size.
    var isSizeUnknown: Bool
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
    private let reconcileSession: @MainActor (ScanSession, ScanSessionCleanupBatch) -> Void
    private var notificationCancellable: AnyCancellable?

    init(
        trashItem: @escaping @Sendable (URL, ScanSource) throws -> Void = DiskItemFileDeletion.moveToFinderTrash,
        reconcileSession: @escaping @MainActor (ScanSession, ScanSessionCleanupBatch) -> Void = { session, batch in
            session.reconcileAfterCleanup(batch)
        }
    ) {
        self.trashItem = trashItem
        self.reconcileSession = reconcileSession
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
                treePath: item.path,
                displayName: item.displayName,
                isFolder: item.isFolder,
                allocatedSize: item.allocatedSizeValue,
                logicalSize: item.logicalSizeValue,
                isSizeUnknown: session.isAffectedBySkippedContent(item),
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
            DiskItemDeletionPolicy.entryURL(queuedItem.itemURL) == DiskItemDeletionPolicy.entryURL(itemURL)
                || (queuedItem.isFolder && DiskItemDeletionPolicy.contains(itemURL, in: queuedItem.itemURL))
        }
    }

    func isDirectlyQueued(_ item: DiskItem) -> Bool {
        isDirectlyQueued(at: item.url)
    }

    func isDirectlyQueued(at itemURL: URL) -> Bool {
        let itemURL: URL = itemURL.standardizedFileURL
        return items.contains { DiskItemDeletionPolicy.entryURL($0.itemURL) == DiskItemDeletionPolicy.entryURL(itemURL) }
    }

    func remove(_ item: DiskItem) {
        remove(at: item.url)
    }

    func remove(at itemURL: URL) {
        let itemURL: URL = itemURL.standardizedFileURL
        items.removeAll { DiskItemDeletionPolicy.entryURL($0.itemURL) == DiskItemDeletionPolicy.entryURL(itemURL) }
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

        var initialRoots: [ObjectIdentifier: ScanSessionCleanupBaseline] = [:]
        for item in selectedItems {
            if let session = item.sessionReference.value, let baseline = session.cleanupBaseline {
                initialRoots[ObjectIdentifier(session)] = baseline
            }
            updateStatus(.processing, for: item.id)
        }

        let trashItem: @Sendable (URL, ScanSource) throws -> Void = trashItem
        let reconcileSession: @MainActor (ScanSession, ScanSessionCleanupBatch) -> Void = reconcileSession
        Task { [trashItem, reconcileSession, initialRoots] in
            var successfulBatches: [ObjectIdentifier: (session: ScanSession, paths: [String])] = [:]
            for item: CleanupQueueItem in selectedItems {
                guard isProcessing(item.id) else {
                    continue
                }

                let eligibility: Result<Bool, Error> = await Task.detached(priority: .userInitiated) {
                    if let reason = DiskItemDeletionPolicy.protection(for: item.itemURL) { throw reason }
                    return Self.cannotMoveToFinderTrash(item.itemURL)
                }.result
                guard isProcessing(item.id) else {
                    continue
                }
                let cannotMoveToTrash: Bool
                switch eligibility {
                case .success(let unavailable): cannotMoveToTrash = unavailable
                case .failure(let error):
                    updateStatus(Self.status(for: error), for: item.id)
                    continue
                }
                guard cannotMoveToTrash == false else {
                    updateStatus(.cannotMoveToTrash, for: item.id)
                    continue
                }

                let source: ScanSource = item.sessionReference.value?.source ?? item.source
                let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                    try DiskItemDeletionPolicy.validateDeletion(at: item.itemURL)
                    try trashItem(item.itemURL, source)
                }.result

                switch result {
                case .success:
                    remove(ids: [item.id])
                    if let session: ScanSession = item.sessionReference.value {
                        successfulBatches[ObjectIdentifier(session), default: (session, [])].paths.append(item.treePath)
                    }
                case .failure(let error):
                    updateStatus(Self.status(for: error), for: item.id)
                }
            }
            for (id, success) in successfulBatches {
                reconcileSession(success.session, ScanSessionCleanupBatch(
                    baseline: initialRoots[id], paths: success.paths
                ))
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
            guard let currentItem: DiskItem = rootItem.item(atPath: updatedItems[index].treePath) else {
                continue
            }
            let allocatedSize: UInt64 = currentItem.allocatedSizeValue
            let logicalSize: UInt64 = currentItem.logicalSizeValue
            let isSizeUnknown: Bool = session.isAffectedBySkippedContent(currentItem)
            guard updatedItems[index].allocatedSize != allocatedSize
                    || updatedItems[index].logicalSize != logicalSize
                    || updatedItems[index].isSizeUnknown != isSizeUnknown else {
                continue
            }
            updatedItems[index].allocatedSize = allocatedSize
            updatedItems[index].logicalSize = logicalSize
            updatedItems[index].isSizeUnknown = isSizeUnknown
            didChange = true
        }

        if didChange {
            items = updatedItems
        }
    }

    private func isProcessing(_ id: CleanupQueueItem.ID) -> Bool {
        items.contains { $0.id == id && $0.status == .processing }
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
        if error is DiskItemDeletionPolicy.Protection { return .protected }
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
