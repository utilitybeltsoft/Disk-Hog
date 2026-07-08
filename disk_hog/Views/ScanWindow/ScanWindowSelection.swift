import Combine
import SwiftUI

@MainActor
final class ScanWindowSelectionCoordinator: ObservableObject {
    @Published private(set) var selectedItem: DiskItem?

    func setSelectedItem(_ item: DiskItem?) {
        guard selectedItem !== item else {
            return
        }

        selectedItem = item
    }
}

enum ScanWindowPane {
    case files
    case kinds
    case treemap
}
