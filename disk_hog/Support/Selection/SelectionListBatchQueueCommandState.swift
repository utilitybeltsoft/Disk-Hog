import Combine
import Foundation

@MainActor
final class SelectionListBatchQueueCommandState: ObservableObject {
    static let shared: SelectionListBatchQueueCommandState = SelectionListBatchQueueCommandState()

    private weak var session: ScanSession?
    private var items: [DiskItem] = []
    @Published private(set) var isActive: Bool = false

    private init() {}

    var canToggle: Bool {
        guard let session, session.isUpdatingTree == false else { return false }
        return actionableItems.isEmpty == false
    }

    var title: String {
        guard actionableItems.isEmpty == false else {
            return String(localized: "Add to Cleanup Queue")
        }
        if actionableItems.allSatisfy(CleanupQueueStore.shared.isDirectlyQueued) {
            return String(localized: "Already Queued for Finder Trash: Undo")
        }
        return actionableItems.count == 1
            ? String(localized: "Add to Cleanup Queue")
            : String(localized: "Add \(actionableItems.count) Items to Cleanup Queue")
    }

    func activate(session: ScanSession, items: [DiskItem]) {
        self.session = session
        self.items = items
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        session = nil
        items = []
        isActive = false
    }

    func toggle() {
        guard let session, canToggle else { return }
        let items: [DiskItem] = actionableItems
        if items.allSatisfy(CleanupQueueStore.shared.isDirectlyQueued) {
            for item: DiskItem in items {
                CleanupQueueStore.shared.remove(item)
            }
        } else {
            CleanupQueueStore.shared.enqueue(items, from: session)
        }
        objectWillChange.send()
    }

    private var actionableItems: [DiskItem] {
        items.filter { DiskItemDeletionPolicy.canDelete($0) }
    }
}
