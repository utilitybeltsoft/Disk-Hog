import SwiftUI

struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let navigation: TreemapNavigationState
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var mode: FilesInspectionMode = .largestFiles
    @State private var visitedModes: Set<FilesInspectionMode> = [.largestFiles]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspect", selection: $mode) {
                Text("Folder Tree").tag(FilesInspectionMode.tree)
                Text("Largest Files").tag(FilesInspectionMode.largestFiles)
                Text("Largest Folders").tag(FilesInspectionMode.largestFolders)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Inspection view")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            Divider()
            ZStack {
                if mode == .tree { tree }
                // Keep visited native tables mounted so their selection and scroll
                // positions survive switching views. Each retains at most 1,000 rows.
                ForEach([FilesInspectionMode.largestFiles, .largestFolders], id: \.self) { rankedMode in
                    if visitedModes.contains(rankedMode) {
                        LargestItemsView(session: session, selectionCoordinator: selectionCoordinator,
                                         navigation: navigation,
                                         category: rankedMode == .largestFiles ? .files : .folders,
                                         isActive: mode == rankedMode,
                                         onShowTree: { mode = .tree })
                            .opacity(mode == rankedMode ? 1 : 0)
                            .allowsHitTesting(mode == rankedMode)
                            .disabled(mode != rankedMode)
                            .accessibilityHidden(mode != rankedMode)
                    }
                }
            }
        }
        .onChange(of: mode) { visitedModes.insert(mode) }
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
                    title: "Folder Tree",
                    message: "Pending scan completion"
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
    }
}

private enum FilesInspectionMode: Hashable {
    case tree, largestFiles, largestFolders
}
