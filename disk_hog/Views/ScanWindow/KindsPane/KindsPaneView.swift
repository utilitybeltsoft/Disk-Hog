import SwiftUI

struct KindsPaneView: View {
    @ObservedObject var session: ScanSession
    @Binding var selectedFilter: SelectionListFilter?
    let onShowSelectionList: (SelectionListFilter) -> Void
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var kindStatistics: [TreemapKindStatistic] = []

    var body: some View {
        KindStatisticTableView(
            statistics: kindStatistics,
            selectedFilter: $selectedFilter,
            activePane: activePane,
            onShowSelectionList: onShowSelectionList
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .kinds)
        }
        .overlay {
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: "Color Map of File Distribution",
                    message: session.isBuildingTreemap
                        ? "Pending treemap completion"
                        : "Pending scan completion"
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
        .onAppear {
            updateKindStatistics()
        }
        .onChange(of: session.rootItem?.id) {
            updateKindStatistics()
        }
        .onChange(of: selectedKindSelectionKey) {
            updateSelectedKindName()
        }
    }

    private var selectedKindSelectionKey: SelectedKindSelectionKey {
        SelectedKindSelectionKey(item: selectedItem.wrappedValue)
    }

    private func updateKindStatistics() {
        guard session.rootItem != nil else {
            kindStatistics = []
            return
        }

        kindStatistics = session.presentationMetrics?.kindStatistics ?? []
        updateSelectedKindName()
    }

    private func updateSelectedKindName() {
        guard let filter: SelectionListFilter = Self.selectedFilter(
            for: selectedItem.wrappedValue,
            statistics: kindStatistics
        ) else {
            selectedFilter = nil
            return
        }

        selectedFilter = filter
    }

    static func selectedFilter(
        for item: DiskItem?,
        statistics: [TreemapKindStatistic]
    ) -> SelectionListFilter? {
        guard let kindName: String = item?.kindName,
              statistics.contains(where: { $0.kindName == kindName }) else {
            return nil
        }

        return .kind(kindName)
    }
}

private struct SelectedKindSelectionKey: Equatable {
    let path: String?
    let kindName: String?

    init(item: DiskItem?) {
        path = item?.path
        kindName = item?.kindName
    }
}
