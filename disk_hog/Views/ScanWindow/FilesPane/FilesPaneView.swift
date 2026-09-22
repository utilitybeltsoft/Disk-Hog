import SwiftUI

struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let navigation: TreemapNavigationState
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var mode: FilesInspectionMode = .largestFiles

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspect", selection: $mode) {
                Text("Folder Tree").tag(FilesInspectionMode.tree)
                Text("Largest Files").tag(FilesInspectionMode.largestFiles)
                Text("Largest Folders").tag(FilesInspectionMode.largestFolders)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            Divider()
            if mode == .tree {
                tree
            } else {
                LargestItemsView(session: session, selectionCoordinator: selectionCoordinator,
                                 navigation: navigation,
                                 category: mode == .largestFiles ? .files : .folders,
                                 onShowTree: { mode = .tree })
            }
        }
        .onTapGesture { activePane.wrappedValue = .files }
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .files)
        }
    }

    private var tree: some View {
        DiskItemOutlineView(
            session: session,
            rootItem: session.rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane,
            onActivateItem: { item, allowingFileFallback in
                navigation.zoom(into: item, allowingFileFallback: allowingFileFallback)
            },
            onZoomOut: { navigation.zoomOut() }
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .files)
        }
        .overlay {
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: "Navigable List View",
                    message: session.isBuildingTreemap
                        ? "Pending treemap completion"
                        : "Pending scan completion"
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
    }
}

private enum FilesInspectionMode {
    case tree, largestFiles, largestFolders
}
