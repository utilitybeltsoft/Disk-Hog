import SwiftUI

struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        ZStack {
            AppKitTreemapView(
                session: session,
                source: session.source,
                rootItem: session.rootItem,
                presentationMetrics: session.presentationMetrics,
                selectionCoordinator: selectionCoordinator,
                hoveredItem: hoveredItem,
                activePane: activePane
            )
            .overlay {
                PaneBorderView(isActive: activePane.wrappedValue == .treemap)
            }
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: session.isBuildingTreemap ? "Preparing treemap" : "Treemap",
                    message: session.isBuildingTreemap ? "Preparing file distribution" : "Pending scan completion",
                    showsProgress: session.isBuildingTreemap
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
