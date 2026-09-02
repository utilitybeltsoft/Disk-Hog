import AppKit
import SwiftUI

struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var selectionCoordinator: ScanWindowSelectionCoordinator
    @ObservedObject var navigation: TreemapNavigationState
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var isRecalculating: Bool = false
    @State private var showsRecalculatingBadge: Bool = false

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
                isRecalculating: $isRecalculating,
                onZoomIn: { item in navigation.zoom(into: item) },
                onZoomOut: { navigation.zoomOut() }
            )
            .overlay {
                PaneBorderView(isActive: activePane.wrappedValue == .treemap)
            }
            .overlay(alignment: .top) {
                if showsRecalculatingBadge {
                    recalculatingBadge
                }
            }
            .onChange(of: isRecalculating) { _, isRecalculating in
                if isRecalculating {
                    // Debounced so a fast re-render (most zooms) never flashes
                    // the badge at all; only a genuinely slow one shows it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if self.isRecalculating {
                            showsRecalculatingBadge = true
                        }
                    }
                } else {
                    showsRecalculatingBadge = false
                }
            }
            if session.rootItem == nil || session.isBuildingTreemap {
                ScanPanePlaceholderView(
                    title: session.isBuildingTreemap ? "Preparing treemap" : "Treemap",
                    message: session.isBuildingTreemap
                        ? treemapPreparationMessage
                        : "Pending scan completion",
                    showsProgress: session.isBuildingTreemap,
                    progress: session.treemapPreparationProgress
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
    }

    private var recalculatingBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Recalculating…")
        }
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var treemapPreparationPercentage: Int {
        Int(((session.treemapPreparationProgress ?? 0) * 100).rounded(.down))
    }

    private var treemapPreparationMessage: LocalizedStringKey {
        guard session.treemapPreparationProgress != nil else {
            return "Preparing file distribution…"
        }
        return "Preparing file distribution: \(treemapPreparationPercentage)%"
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
