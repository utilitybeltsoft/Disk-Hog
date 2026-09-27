import Combine
import Foundation

@MainActor
final class ScanWindowCommandState: ObservableObject {
    static let shared: ScanWindowCommandState = ScanWindowCommandState()

    private weak var activeContext: ScanWindowCommandContext?
    private var activeContextCancellable: AnyCancellable?

    let cleanupQueue: CleanupQueueStore

    init(cleanupQueue: CleanupQueueStore? = nil) {
        let cleanupQueue = cleanupQueue ?? .shared
        self.cleanupQueue = cleanupQueue
    }

    var canOpenSelectedItem: Bool { activeContext?.canOpenSelectedItem ?? false }
    var canRevealSelectedItem: Bool { activeContext?.canRevealSelectedItem ?? false }
    var canSelectParentFolder: Bool { activeContext?.canSelectParentFolder ?? false }
    var canZoomIn: Bool { activeContext?.canZoomIn ?? false }
    var canZoomOut: Bool { activeContext?.canZoomOut ?? false }
    var canToggleFreeSpace: Bool { activeContext?.canToggleFreeSpace ?? false }
    var canToggleOtherSpace: Bool { activeContext?.canToggleOtherSpace ?? false }
    var showsFreeSpace: Bool { activeContext?.showsFreeSpace ?? false }
    var showsOtherSpace: Bool { activeContext?.showsOtherSpace ?? false }
    #if FILE_MATCHING_DIAGNOSTICS
    var canCopyMatchingFile: Bool { activeContext?.canCopyMatchingFile ?? false }
    #endif

    var commandSelectedItem: DiskItem? { activeContext?.commandSelectedItem }

    var canToggleSelectedItemInCleanupQueue: Bool {
        guard let item: DiskItem = commandSelectedItem,
              item.isSpecialItem == false,
              let session: ScanSession = activeContext?.actionSession,
              session.isUpdatingTree == false else {
            return false
        }
        return CleanupQueueMenuPresentation.isEnabled(
            item: item,
            isDirectlyQueued: cleanupQueue.isDirectlyQueued(item),
            isAlreadyQueued: cleanupQueue.contains(item)
        )
    }

    var selectedItemCleanupQueueCommandTitle: String {
        guard let item: DiskItem = commandSelectedItem else {
            return CleanupQueueMenuPresentation.addTitle
        }
        return CleanupQueueMenuPresentation.title(isDirectlyQueued: cleanupQueue.isDirectlyQueued(item))
    }

    func activate(_ context: ScanWindowCommandContext) {
        guard activeContext !== context else { return }
        activeContext = context
        activeContextCancellable = context.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }

    func deactivate(if context: ScanWindowCommandContext? = nil) {
        if let context, activeContext !== context { return }
        guard activeContext != nil else { return }
        activeContext = nil
        activeContextCancellable = nil
        objectWillChange.send()
    }

    func openSelectedItem() { activeContext?.openSelectedItem() }
    func revealSelectedItemInFinder() { activeContext?.revealSelectedItemInFinder() }
    func selectParentFolder() { activeContext?.selectParentFolder() }
    func zoomIn() { activeContext?.zoomIn() }
    func zoomOut() { activeContext?.zoomOut() }

    func toggleSelectedItemInCleanupQueue() {
        guard canToggleSelectedItemInCleanupQueue,
              let item: DiskItem = commandSelectedItem,
              let session: ScanSession = activeContext?.actionSession else {
            return
        }
        if cleanupQueue.isDirectlyQueued(item) {
            DiskItemDeletionCoordinator.requestQueueUndo(of: item, queue: cleanupQueue)
        } else {
            DiskItemDeletionCoordinator.requestQueueing(of: item, from: session, queue: cleanupQueue)
        }
    }

    func toggleFreeSpace() { activeContext?.toggleFreeSpace() }
    func toggleOtherSpace() { activeContext?.toggleOtherSpace() }
    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() { activeContext?.copyMatchingFile() }
    #endif
}
