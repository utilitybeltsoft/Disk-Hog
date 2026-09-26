import Combine
import SwiftUI

@MainActor
final class ScanWindowSelectionCoordinator: ObservableObject {
    enum Origin { case other, treemap }
    @Published private(set) var selectedItem: DiskItem?
    @Published private(set) var treemapRevealRequest = 0
    private(set) var selectionOrigin: Origin = .other
    /// Root-to-parent chain for `selectedItem`, when the selection's source
    /// already knows it (e.g. a treemap click resolved via the layout plan).
    /// Empty means the receiver should resolve ancestors itself.
    private(set) var lastKnownAncestorChain: [DiskItem] = []

    func setSelectedItem(_ item: DiskItem?, ancestorChain: [DiskItem] = [], origin: Origin = .other) {
        // A direct treemap click is an explicit reveal request even if the item
        // was already selected from a ranked list. Synthetic space has no tree row.
        if origin == .treemap, let item {
            selectionOrigin = origin
            if !item.isSpecialItem { treemapRevealRequest += 1 }
        }
        guard selectedItem != item else {
            return
        }

        lastKnownAncestorChain = ancestorChain
        selectionOrigin = origin
        selectedItem = item
    }
}

enum ScanWindowPane {
    case files
    case kinds
    case treemap
}
