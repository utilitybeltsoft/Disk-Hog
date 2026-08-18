import Combine
import Foundation

@MainActor
final class AppCommandRouter: ObservableObject {
    static let shared: AppCommandRouter = AppCommandRouter()

    private weak var selectionListSession: ScanSession?
    private var selectionListItems: [DiskItem] = []
    @Published private(set) var isSelectionListBatchQueueActive: Bool = false

    init() {}

    var canToggleSelectionListBatchQueue: Bool {
        guard let selectionListSession, selectionListSession.isUpdatingTree == false else {
            return false
        }
        return actionableSelectionListItems.isEmpty == false
    }

    var selectionListBatchQueueTitle: String {
        guard actionableSelectionListItems.isEmpty == false else {
            return String(localized: "Add to Cleanup Queue")
        }
        if actionableSelectionListItems.allSatisfy(CleanupQueueStore.shared.isDirectlyQueued) {
            return String(localized: "Already Queued for Finder Trash: Undo")
        }
        return actionableSelectionListItems.count == 1
            ? String(localized: "Add to Cleanup Queue")
            : String(localized: "Add \(actionableSelectionListItems.count) Items to Cleanup Queue")
    }

    func activateSelectionListBatchQueue(session: ScanSession, items: [DiskItem]) {
        selectionListSession = session
        selectionListItems = items
        isSelectionListBatchQueueActive = true
    }

    func deactivateSelectionListBatchQueue() {
        guard isSelectionListBatchQueueActive else { return }
        selectionListSession = nil
        selectionListItems = []
        isSelectionListBatchQueueActive = false
    }

    func toggleSelectionListBatchQueue() {
        guard let selectionListSession, canToggleSelectionListBatchQueue else { return }
        let items: [DiskItem] = actionableSelectionListItems
        if items.allSatisfy(CleanupQueueStore.shared.isDirectlyQueued) {
            for item: DiskItem in items {
                CleanupQueueStore.shared.remove(item)
            }
        } else {
            CleanupQueueStore.shared.enqueue(items, from: selectionListSession)
        }
        objectWillChange.send()
    }

    private var actionableSelectionListItems: [DiskItem] {
        selectionListItems.filter { DiskItemDeletionPolicy.canDelete($0) }
    }
}
