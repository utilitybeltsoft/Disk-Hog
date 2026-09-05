import Foundation

/// The "add to / already in the cleanup queue" title and enablement rule, shared by
/// every place that offers to toggle a single item's cleanup-queue membership - a
/// right-click context menu item, and the equivalent Commands-menu/keyboard-shortcut
/// command. (The selection list's *batch* queue command in AppCommandRouter has its
/// own shape - it aggregates over many items, including pluralizing the title - but
/// reuses `addTitle`/`undoTitle` so its wording can't drift from these.)
enum CleanupQueueMenuPresentation {
    static let addTitle: String = String(localized: "Add to Cleanup Queue")
    static let undoTitle: String = String(localized: "Already Queued for Finder Trash: Undo")

    static func title(isDirectlyQueued: Bool) -> String {
        isDirectlyQueued ? undoTitle : addTitle
    }

    /// `isAlreadyQueued` covers both direct membership and membership via a queued
    /// ancestor folder; only a directly-queued item can be toggled back off once an
    /// ancestor already covers it.
    static func isEnabled(item: DiskItem, isDirectlyQueued: Bool, isAlreadyQueued: Bool) -> Bool {
        DiskItemDeletionPolicy.canDelete(item) && (isDirectlyQueued || !isAlreadyQueued)
    }
}
