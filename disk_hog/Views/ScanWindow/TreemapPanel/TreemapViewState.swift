import AppKit

@MainActor
final class TreemapViewState {
    private(set) var source: ScanSource?
    private(set) var rootItem: DiskItem?
    private(set) var selectedItem: DiskItem?
    private(set) var renderer: TreemapViewRenderer?

    private var presentationMetrics: TreemapPresentationMetrics?
    private var rendererDataSource: TreemapDiskItemDataSource?
    private var showsFreeSpace: Bool = false
    private var showsOtherSpace: Bool = false
    private var freeSpaceItem: DiskItem?
    private var otherSpaceItem: DiskItem?
    private var lastSelectionDiagnostic: String?

    func configure(
        source: ScanSource,
        rootItem: DiskItem?,
        presentationMetrics: TreemapPresentationMetrics?,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?,
        selectedItem: DiskItem?
    ) -> Bool {
        self.source = source
        var needsDisplay: Bool = false

        if self.rootItem !== rootItem
            || self.presentationMetrics !== presentationMetrics
            || self.showsFreeSpace != showsFreeSpace
            || self.showsOtherSpace != showsOtherSpace
            || self.freeSpaceItem !== freeSpaceItem
            || self.otherSpaceItem !== otherSpaceItem {
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            self.showsFreeSpace = showsFreeSpace
            self.showsOtherSpace = showsOtherSpace
            self.freeSpaceItem = freeSpaceItem
            self.otherSpaceItem = otherSpaceItem
            rebuildRenderer()
            needsDisplay = true
        }

        if self.selectedItem !== selectedItem {
            self.selectedItem = selectedItem
            syncSelectionToRenderer()
            needsDisplay = true
        }
        return needsDisplay
    }

    func applySelectedItem(_ selectedItem: DiskItem?) -> Bool {
        guard self.selectedItem !== selectedItem else {
            return false
        }

        self.selectedItem = selectedItem
        syncSelectionToRenderer()
        return true
    }

    func select(_ hitResult: TreemapHitResult) {
        renderer?.selectItem(by: hitResult.cellID)
        selectedItem = hitResult.item
    }

    func hitResult(at point: NSPoint) -> TreemapHitResult? {
        guard let cellID: TreemapItemRenderer = renderer?.cellID(by: point, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID),
              !item.isSpecialItem else {
            return nil
        }
        return TreemapHitResult(item: item, cellID: cellID)
    }

    func prepareLayout(in bounds: NSRect) {
        guard let rootItem: DiskItem = rootItem else {
            return
        }
        if renderer == nil {
            rebuildRenderer()
        }
        guard renderer?.rootCellID?.rect != bounds else {
            return
        }

        renderer?.calcLayout(bounds)
        syncSelectionToRenderer()
        if let renderer: TreemapViewRenderer = renderer {
            TreemapLayoutDiagnostics.recordLayoutChange(
                rootItem: rootItem,
                size: bounds.size,
                renderer: renderer,
                minimumRenderableSide: ScanWindowMetrics.minimumRenderableTreemapSide
            )
        }
    }

    private func rebuildRenderer() {
        guard let rootItem: DiskItem = rootItem else {
            renderer = nil
            rendererDataSource = nil
            return
        }

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: rootItem,
            usePhysicalSize: source?.scanSettings?.usePhysicalSize
                ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize,
            showFreeSpace: showsFreeSpace,
            showOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            presentationMetrics: presentationMetrics
        )
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        rendererDataSource = dataSource
        self.renderer = renderer
        syncSelectionToRenderer()
    }

    private func syncSelectionToRenderer() {
        guard let item: DiskItem = selectedItem,
              let rootItem: DiskItem = rootItem else {
            renderer?.selectItem(by: nil)
            logSelectionDiagnostic(selectionPath: [], didSelectRenderer: false)
            return
        }

        let selectionPath: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item)
        guard selectionPath.isEmpty == false else {
            renderer?.selectItem(by: nil)
            logSelectionDiagnostic(selectionPath: selectionPath, didSelectRenderer: false)
            return
        }

        let didSelectRenderer: Bool = renderer?.selectRenderedItem(byPathToItem: selectionPath) ?? false
        logSelectionDiagnostic(selectionPath: selectionPath, didSelectRenderer: didSelectRenderer)
    }

    private func logSelectionDiagnostic(selectionPath: [DiskItem], didSelectRenderer: Bool) {
        let selectedRenderer: TreemapItemRenderer? = renderer?.selectedCellID
        let selectedRect: NSRect = renderer?.itemRect(by: selectedRenderer) ?? .zero
        let message: String =
            """
            Treemap external selection diagnostic
              map root: \(rootItem?.path ?? "<none>")
              selected item: \(selectedItem?.path ?? "<none>")
              selection path: \(selectionPath.map(\.path).joined(separator: " -> "))
              renderer resolved: \(didSelectRenderer)
              rendered item: \(selectedRenderer?.item.path ?? "<none>")
              rendered rect: \(NSStringFromRect(selectedRect))
            """
        guard message != lastSelectionDiagnostic else { return }
        lastSelectionDiagnostic = message
        NSLog("%@", message)
    }
}

struct TreemapHitResult {
    let item: DiskItem
    let cellID: TreemapItemRenderer
}

struct TreemapHoverRegion {
    let item: DiskItem
    let rect: NSRect
}
