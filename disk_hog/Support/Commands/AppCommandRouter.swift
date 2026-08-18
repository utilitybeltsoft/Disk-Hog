import Combine
import Foundation

@MainActor
final class AppCommandRouter: ObservableObject {
    private struct SelectionListQueueTarget: Equatable {
        let path: String
        let itemURL: URL
    }

    static let shared: AppCommandRouter = AppCommandRouter()

    @Published var canScanSelectedVolume: Bool = false
    private weak var selectionListSession: ScanSession?
    private var selectionListItemPaths: [String] = []
    private var cachedSelectionListQueueTargets: [SelectionListQueueTarget]?
    private var notificationCancellable: AnyCancellable?
    @Published private(set) var isSelectionListBatchQueueActive: Bool = false

    init() {
        notificationCancellable = NotificationCenter.default.publisher(for: .scanSessionTreeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let session: ScanSession = notification.object as? ScanSession,
                      self.selectionListSession === session else {
                    return
                }
                self.cachedSelectionListQueueTargets = nil
                self.objectWillChange.send()
            }
    }

    var canToggleSelectionListBatchQueue: Bool {
        guard let selectionListSession, selectionListSession.isUpdatingTree == false else {
            return false
        }
        return selectionListQueueTargets.isEmpty == false
    }

    var selectionListBatchQueueTitle: String {
        let targets: [SelectionListQueueTarget] = selectionListQueueTargets
        guard targets.isEmpty == false else {
            return String(localized: "Add to Cleanup Queue")
        }
        if targets.allSatisfy({ CleanupQueueStore.shared.isDirectlyQueued(at: $0.itemURL) }) {
            return String(localized: "Already Queued for Finder Trash: Undo")
        }
        return targets.count == 1
            ? String(localized: "Add to Cleanup Queue")
            : String(localized: "Add \(targets.count) Items to Cleanup Queue")
    }

    func activateSelectionListBatchQueue(session: ScanSession, items: [DiskItem]) {
        selectionListSession = session
        selectionListItemPaths = items.map(\.path)
        cachedSelectionListQueueTargets = nil
        isSelectionListBatchQueueActive = true
    }

    func deactivateSelectionListBatchQueue() {
        guard isSelectionListBatchQueueActive else { return }
        selectionListSession = nil
        selectionListItemPaths = []
        cachedSelectionListQueueTargets = nil
        isSelectionListBatchQueueActive = false
    }

    func toggleSelectionListBatchQueue() {
        guard let selectionListSession, canToggleSelectionListBatchQueue else { return }
        let targets: [SelectionListQueueTarget] = selectionListQueueTargets
        if targets.allSatisfy({ CleanupQueueStore.shared.isDirectlyQueued(at: $0.itemURL) }) {
            for target: SelectionListQueueTarget in targets {
                CleanupQueueStore.shared.remove(at: target.itemURL)
            }
        } else {
            guard let rootItem: DiskItem = selectionListSession.rootItem else {
                return
            }
            let items: [DiskItem] = targets.compactMap { rootItem.item(atPath: $0.path) }
            CleanupQueueStore.shared.enqueue(items, from: selectionListSession)
        }
        objectWillChange.send()
    }

    private var selectionListQueueTargets: [SelectionListQueueTarget] {
        if let cachedSelectionListQueueTargets {
            return cachedSelectionListQueueTargets
        }
        guard let rootItem: DiskItem = selectionListSession?.rootItem else {
            return []
        }
        let targets: [SelectionListQueueTarget] = selectionListItemPaths.compactMap { path in
            guard let item: DiskItem = rootItem.item(atPath: path),
                  DiskItemDeletionPolicy.canDelete(item) else {
                return nil
            }
            return SelectionListQueueTarget(path: item.path, itemURL: item.url.standardizedFileURL)
        }
        cachedSelectionListQueueTargets = targets
        return targets
    }
}
