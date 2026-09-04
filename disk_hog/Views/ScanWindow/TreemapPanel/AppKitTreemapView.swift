import AppKit
import Combine
import SwiftUI

struct AppKitTreemapView: NSViewRepresentable {
    let session: ScanSession
    let source: ScanSource
    let rootItem: DiskItem?
    let presentationMetrics: TreemapPresentationMetrics?
    let showsFreeSpace: Bool
    let showsOtherSpace: Bool
    let freeSpaceItem: DiskItem?
    let otherSpaceItem: DiskItem?
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let hoveredItem: Binding<DiskItem?>
    let activePane: Binding<ScanWindowPane?>
    let isRecalculating: Binding<Bool>
    let renderProgress: Binding<Double?>
    let onZoomIn: (DiskItem, Bool) -> Void
    let onZoomOut: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectionCoordinator: selectionCoordinator,
            hoveredItem: hoveredItem,
            activePane: activePane,
            isRecalculating: isRecalculating,
            renderProgress: renderProgress
        )
    }

    func makeNSView(context: Context) -> ZStyleTreemapNSView {
        let view: ZStyleTreemapNSView = ZStyleTreemapNSView()
        view.onSelectItem = { item, ancestorChain in
            context.coordinator.activePane.wrappedValue = .treemap
            context.coordinator.selectionCoordinator.setSelectedItem(item, ancestorChain: ancestorChain)
        }
        view.onHoverItem = { item in
            context.coordinator.hoveredItem.wrappedValue = item
        }
        view.onRenderPendingChange = { isPending in
            context.coordinator.isRecalculating.wrappedValue = isPending
        }
        view.onRenderProgressChange = { fraction in
            context.coordinator.renderProgress.wrappedValue = fraction
        }
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        context.coordinator.view = view
        context.coordinator.observeSelection()
        view.configure(
            session: session,
            source: source,
            rootItem: rootItem,
            presentationMetrics: presentationMetrics,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            selectedItem: selectionCoordinator.selectedItem
        )
        return view
    }

    func updateNSView(_ nsView: ZStyleTreemapNSView, context: Context) {
        context.coordinator.selectionCoordinator = selectionCoordinator
        context.coordinator.hoveredItem = hoveredItem
        context.coordinator.activePane = activePane
        context.coordinator.isRecalculating = isRecalculating
        context.coordinator.renderProgress = renderProgress
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.configure(
            session: session,
            source: source,
            rootItem: rootItem,
            presentationMetrics: presentationMetrics,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            selectedItem: selectionCoordinator.selectedItem
        )
    }

    final class Coordinator {
        var selectionCoordinator: ScanWindowSelectionCoordinator
        var hoveredItem: Binding<DiskItem?>
        var activePane: Binding<ScanWindowPane?>
        var isRecalculating: Binding<Bool>
        var renderProgress: Binding<Double?>
        weak var view: ZStyleTreemapNSView?
        private var selectionCancellable: AnyCancellable?

        init(
            selectionCoordinator: ScanWindowSelectionCoordinator,
            hoveredItem: Binding<DiskItem?>,
            activePane: Binding<ScanWindowPane?>,
            isRecalculating: Binding<Bool>,
            renderProgress: Binding<Double?>
        ) {
            self.selectionCoordinator = selectionCoordinator
            self.hoveredItem = hoveredItem
            self.activePane = activePane
            self.isRecalculating = isRecalculating
            self.renderProgress = renderProgress
        }

        func observeSelection() {
            selectionCancellable = selectionCoordinator.$selectedItem.sink { [weak self] item in
                self?.view?.applySelectedItem(item)
            }
        }
    }
}
