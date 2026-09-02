import Combine
import SwiftUI

@MainActor
final class ScanWindowSelectionCoordinator: ObservableObject {
    @Published private(set) var selectedItem: DiskItem?
    /// Root-to-parent chain for `selectedItem`, when the selection's source
    /// already knows it (e.g. a treemap click resolved via the layout plan).
    /// Empty means the receiver should resolve ancestors itself.
    private(set) var lastKnownAncestorChain: [DiskItem] = []

    func setSelectedItem(_ item: DiskItem?, ancestorChain: [DiskItem] = []) {
        guard selectedItem !== item else {
            return
        }

        lastKnownAncestorChain = ancestorChain
        selectedItem = item
    }
}

enum ScanWindowPane {
    case files
    case kinds
    case treemap
}
