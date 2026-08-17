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
    let onZoomIn: (DiskItem) -> Void
    let onZoomOut: () -> Void
    let isInteractionEnabled: Bool
    let onPreviewSpaceChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectionCoordinator: selectionCoordinator,
            hoveredItem: hoveredItem,
            activePane: activePane
        )
    }

    func makeNSView(context: Context) -> ZStyleTreemapNSView {
        let view: ZStyleTreemapNSView = ZStyleTreemapNSView()
        view.onSelectItem = { item in
            context.coordinator.activePane.wrappedValue = .treemap
            context.coordinator.selectionCoordinator.setSelectedItem(item)
        }
        view.onHoverItem = { item in
            context.coordinator.hoveredItem.wrappedValue = item
        }
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.isInteractionEnabled = isInteractionEnabled
        view.onPreviewSpaceChanged = onPreviewSpaceChanged
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
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.isInteractionEnabled = isInteractionEnabled
        nsView.onPreviewSpaceChanged = onPreviewSpaceChanged
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
        weak var view: ZStyleTreemapNSView?
        private var selectionCancellable: AnyCancellable?

        init(
            selectionCoordinator: ScanWindowSelectionCoordinator,
            hoveredItem: Binding<DiskItem?>,
            activePane: Binding<ScanWindowPane?>
        ) {
            self.selectionCoordinator = selectionCoordinator
            self.hoveredItem = hoveredItem
            self.activePane = activePane
        }

        func observeSelection() {
            selectionCancellable = selectionCoordinator.$selectedItem.sink { [weak self] item in
                self?.view?.applySelectedItem(item)
            }
        }
    }
}
