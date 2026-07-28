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
        .onChange(of: selectedItem.wrappedValue?.id) {
            updateSelectedKindName()
        }
    }

    private func updateKindStatistics() {
        guard let rootItem: DiskItem = session.rootItem else {
            kindStatistics = []
            return
        }

        kindStatistics = session.presentationMetrics?.kindStatistics ?? TreemapDiskItemDataSource.kindStatistics(
            for: rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize
        )
        updateSelectedKindName()
    }

    private func updateSelectedKindName() {
        guard let item: DiskItem = selectedItem.wrappedValue,
              !item.isFolder,
              let kindName: String = item.kindName,
              kindStatistics.contains(where: { $0.kindName == kindName }) else {
            selectedFilter = nil
            return
        }

        selectedFilter = .kind(kindName)
    }
}
