import SwiftUI

struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        ZStack {
            AppKitTreemapView(
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

