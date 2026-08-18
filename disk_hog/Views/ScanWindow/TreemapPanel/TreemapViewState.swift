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
    private var lastDirectionalMove: (origin: DiskItem, direction: TreemapNavigationDirection)?

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
            lastDirectionalMove = nil
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

        lastDirectionalMove = nil
        self.selectedItem = selectedItem
        syncSelectionToRenderer()
        return true
    }

    func select(_ hitResult: TreemapHitResult) {
        lastDirectionalMove = nil
        renderer?.selectItem(by: hitResult.cellID)
        selectedItem = hitResult.item
    }

    func selectNeighbor(in direction: TreemapNavigationDirection) -> DiskItem? {
        if let lastDirectionalMove,
           direction == lastDirectionalMove.direction.opposite,
           renderer?.selectItem(byRenderedItem: lastDirectionalMove.origin) == true {
            self.lastDirectionalMove = nil
            selectedItem = lastDirectionalMove.origin
            return lastDirectionalMove.origin
        }
        guard let origin: DiskItem = selectedItem else { return nil }
        let item: DiskItem? = renderer?.selectNeighbor(in: direction)
        guard let item else { return nil }
        selectedItem = item
        lastDirectionalMove = (origin: origin, direction: direction)
        return item
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
            return
        }

        let selectionPath: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item)
        guard selectionPath.isEmpty == false else {
            renderer?.selectItem(by: nil)
            return
        }

        _ = renderer?.selectRenderedItem(byPathToItem: selectionPath)
    }
}

private extension TreemapNavigationDirection {
    var opposite: TreemapNavigationDirection {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }
}

struct TreemapHitResult {
    let item: DiskItem
    let cellID: TreemapItemRenderer
}
