import Combine
import Foundation

@MainActor
final class InspectorWindowContext: ObservableObject {
    let session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator

    @Published var selectionListFilter: SelectionListFilter?
    let selectionListDataStore: SelectionListDataStore = SelectionListDataStore()

    private(set) var didAutomaticallyShowDiskUsage: Bool = false

    init(session: ScanSession, selectionCoordinator: ScanWindowSelectionCoordinator) {
        self.session = session
        self.selectionCoordinator = selectionCoordinator
    }

    var isVolumeScan: Bool {
        session.source.volumeKind != .folder
    }

    func selectKind(_ kindName: String) {
        selectionListFilter = .kind(kindName)
    }

    func selectAllKinds() {
        selectionListFilter = .all
    }

    func markDiskUsageAutomaticallyShown() {
        didAutomaticallyShowDiskUsage = true
    }
}
