import SwiftUI

struct KindsPaneView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var kindStatistics: [TreemapKindStatistic] = []
    @State private var selectedKindName: String?

    var body: some View {
        KindStatisticTableView(
            statistics: kindStatistics,
            selectedKindName: $selectedKindName,
            activePane: activePane
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .kinds)
        }
        .overlay {
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: "Color Map of File Distribution",
                    message: "Pending scan completion"
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
            selectedKindName = nil
            return
        }

        selectedKindName = kindName
    }
}
