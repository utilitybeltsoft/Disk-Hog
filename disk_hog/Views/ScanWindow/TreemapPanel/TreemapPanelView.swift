import AppKit
import SwiftUI

struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var selectionCoordinator: ScanWindowSelectionCoordinator
    @ObservedObject var navigation: TreemapNavigationState
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                navigationBar
                mainTreemap
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
                onZoomOut: { navigation.zoomOut() }
            )
            .overlay {
                PaneBorderView(isActive: activePane.wrappedValue == .treemap)
            }
            if session.rootItem == nil || session.isBuildingTreemap {
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
            Button { navigation.zoom(into: selectionCoordinator.selectedItem) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Zoom In")
                    Text("↩")
                }
                .fixedSize()
            }
            .disabled(navigation.canZoom(into: selectionCoordinator.selectedItem) == false)

            Button { navigation.zoomOut() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                    Text("⇧↩")
                }
                .fixedSize()
            }
            .disabled(navigation.canZoomOut == false)

            ScrollViewReader { breadcrumbProxy in
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
                .onChange(of: navigation.zoomPath.last?.id) {
                    guard let lastItem: DiskItem = navigation.zoomPath.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        breadcrumbProxy.scrollTo(lastItem.id, anchor: .trailing)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .layoutPriority(1)
        }
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
        .padding(.horizontal, ScanWindowMetrics.mainSplitHorizontalPadding)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

}
