import SwiftUI

struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        DiskItemOutlineView(
            session: session,
            rootItem: session.rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .files)
        }
        .overlay {
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: "Navigable List View",
                    message: "Pending scan completion"
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
    }
}
