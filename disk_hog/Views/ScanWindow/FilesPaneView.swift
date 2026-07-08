import SwiftUI

struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        DiskItemOutlineView(
            rootItem: session.rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .files)
        }
    }
}

