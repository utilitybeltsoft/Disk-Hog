import SwiftUI

struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @ObservedObject var navigation: TreemapNavigationState
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        GeometryReader { geometry in
            let showsPreview: Bool = geometry.size.width >= Self.previewMinimumWindowWidth
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    navigationBar
                    mainTreemap
                }
                if showsPreview {
                    Divider()
                    previewPane
                        .frame(width: Self.previewWidth)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainTreemap: some View {
        ZStack {
            AppKitTreemapView(
                session: session,
                source: session.source,
                rootItem: navigation.zoomRoot,
                presentationMetrics: session.presentationMetrics,
                showsFreeSpace: session.showsFreeSpace,
                showsOtherSpace: session.showsOtherSpace,
                freeSpaceItem: session.freeSpaceItem,
                otherSpaceItem: session.otherSpaceItem,
                selectionCoordinator: selectionCoordinator,
                hoveredItem: hoveredItem,
                activePane: activePane,
                onZoomIn: { item in navigation.zoom(into: item) },
                onZoomOut: { navigation.zoomOut() },
                isInteractionEnabled: navigation.isPreviewActive == false,
                onPreviewSpaceChanged: { isHeld in
                    isHeld ? navigation.beginPreview() : navigation.endPreview()
                }
            )
            .overlay {
                PaneBorderView(isActive: activePane.wrappedValue == .treemap)
            }
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: session.isBuildingTreemap ? "Preparing treemap" : "Treemap",
                    message: session.isBuildingTreemap
                        ? "Preparing file distribution: \(treemapPreparationPercentage)%"
                        : "Pending scan completion",
                    showsProgress: session.isBuildingTreemap,
                    progress: session.treemapPreparationProgress
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
    }

    private var treemapPreparationPercentage: Int {
        Int(((session.treemapPreparationProgress ?? 0) * 100).rounded(.down))
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            Button { navigation.zoomOut() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(navigation.canZoomOut == false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(navigation.zoomPath.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Button(item.displayName) { navigation.zoom(toPathIndex: index) }
                            .buttonStyle(.plain)
                            .foregroundStyle(index == navigation.zoomPath.indices.last ? .primary : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
        .padding(.horizontal, ScanWindowMetrics.mainSplitHorizontalPadding)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            if navigation.isPreviewActive {
                Text("Preview active — release Space to return")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            if let item: DiskItem = previewItem {
                Text(item.displayName)
                    .lineLimit(2)
                Text("\(item.childCount) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AppKitTreemapView(
                    session: session,
                    source: session.source,
                    rootItem: item,
                    presentationMetrics: session.presentationMetrics,
                    showsFreeSpace: false,
                    showsOtherSpace: false,
                    freeSpaceItem: nil,
                    otherSpaceItem: nil,
                    selectionCoordinator: selectionCoordinator,
                    hoveredItem: .constant(nil),
                    activePane: activePane,
                    onZoomIn: { item in navigation.commitPreviewZoom(into: item) },
                    onZoomOut: {},
                    isInteractionEnabled: navigation.isPreviewActive,
                    onPreviewSpaceChanged: { _ in }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            navigation.isPreviewActive ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: navigation.isPreviewActive ? 2 : 1
                        )
                }
            } else {
                Spacer()
                Text("Hover a folder to preview its contents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var previewItem: DiskItem? { navigation.previewRoot }

    private static let previewWidth: CGFloat = 280
    private static let previewMinimumWindowWidth: CGFloat = 1_120
}
