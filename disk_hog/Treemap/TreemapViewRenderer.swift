import AppKit

@MainActor
final class TreemapViewRenderer {
    private var rootItemRenderer: TreemapItemRenderer?
    private weak var dataSource: TreemapDiskItemDataSource?
    private var selectedRenderer: TreemapItemRenderer?
    private var touchedRenderer: TreemapItemRenderer?
    private var cachedContent: NSBitmapImageRep?
    private let rootItem: DiskItem

    init(dataSource: TreemapDiskItemDataSource) {
        self.rootItem = dataSource.root
        self.dataSource = dataSource
    }

    var selectedItem: DiskItem? {
        selectedRenderer == nil ? nil : selectedRenderer!.item
    }

    var selectedCellID: TreemapItemRenderer? {
        selectedRenderer
    }

    var rootCellID: TreemapItemRenderer? {
        rootItemRenderer
    }

    var materializedRendererCount: Int {
        rootItemRenderer?.materializedRendererCount ?? 0
    }

    var childRendererReconciliationCount: Int {
        rootItemRenderer?.childRendererReconciliationCount ?? 0
    }

    func invalidateCanvasCache() {
        deallocContentCache()
    }

    func reloadData() {
        assert(!zoomingInProgress, "cannot reload tree map while zooming is in progress")
        deallocContentCache()
        selectedRenderer = nil
        touchedRenderer = nil
        guard let dataSource: TreemapDiskItemDataSource = dataSource else {
            return
        }
        if rootItemRenderer == nil {
            rootItemRenderer = TreemapItemRenderer(dataSource: dataSource, renderedItem: rootItem)
        } else {
            rootItemRenderer?.refresh(with: rootItem)
        }
    }

    func cellID(by point: NSPoint, inViewCoordinates viewCoordinates: Bool) -> TreemapItemRenderer? {
        let rendererPoint: NSPoint = point
        _ = viewCoordinates
        return rootItemRenderer?.hitTest(rendererPoint)
    }

    func item(by cellID: TreemapItemRenderer) -> DiskItem {
        cellID.item
    }

    func selectItem(by cellID: TreemapItemRenderer?) {
        guard cellID !== selectedRenderer else { return }
        if let item: DiskItem = cellID?.item, dataSource?.shouldSelect(item) == false {
            return
        }
        selectedRenderer = cellID
    }

    func selectItem(byPathToItem path: [DiskItem]) {
        assert(path.count > 0, "path must contain at least 1 component")
        let rendererToSelect: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path)
        if rendererToSelect != nil {
            selectItem(by: rendererToSelect)
        }
    }

    func selectItem(byRenderedItem item: DiskItem) -> Bool {
        let path: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item)
        guard path.isEmpty == false,
              let renderer: TreemapItemRenderer = findTreemapItem(byPathToDataItem: path) else {
            return false
        }
        selectItem(by: renderer)
        return true
    }

    func itemRect(by cellID: TreemapItemRenderer?) -> NSRect {
        if let cellID: TreemapItemRenderer = cellID {
            return cellID.rect
        } else {
            return .zero
        }
    }

    func itemRect(byPathToItem path: [DiskItem]) -> NSRect {
        assert(path.count > 0, "path must contain at least 1 component")
        let renderer: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path)
        if let renderer: TreemapItemRenderer = renderer {
            return renderer.rect
        } else {
            return .zero
        }
    }

    func calcLayout(_ bounds: NSRect) {
        rootItemRenderer?.calcLayout(bounds)
        deallocContentCache()
    }

    func layoutDiagnosticsRows() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var sequence: Int = 0
        rootItemRenderer?.appendLayoutDiagnostics(
            to: &rows,
            displayFolderPath: "",
            depth: 0,
            childIndex: 0,
            sequence: &sequence
        )
        return rows
    }

    func drawInCache(size: NSSize, scale: CGFloat = 1, colorSpace: NSColorSpace? = nil) -> NSBitmapImageRep? {
        if cachedContent != nil {
            return cachedContent
        }
        allocContentCache(size: size, scale: scale, colorSpace: colorSpace)
        if rootItemRenderer != nil {
            rootItemRenderer?.drawCushion(in: cachedContent!)
        }
        return cachedContent
    }

    var zoomingInProgress: Bool {
        false
    }

    private func allocContentCache(size: NSSize, scale: CGFloat, colorSpace: NSColorSpace?) {
        cachedContent = nil
        cachedContent = NSBitmapImageRep.treemapImageRepCompatible(withBounds: NSRect(origin: .zero, size: size), backingScaleFactor: scale, colorSpace: colorSpace)
    }

    private func deallocContentCache() {
        if cachedContent != nil {
            cachedContent = nil
        }
    }

    private func findTreemapItem(byPathToDataItem path: [DiskItem]) -> TreemapItemRenderer? {
        if rootItemRenderer == nil {
            return nil
        }
        assert(path.count > 0, "path must contain at least 1 component")
        var parent: TreemapItemRenderer = rootItemRenderer!
        var child: TreemapItemRenderer? = rootItemRenderer
        for dataItem: DiskItem in path.dropFirst() {
            child = parent.childEnumerator.first { renderer in
                renderer.item == dataItem
            }
            if child == nil {
                return nil
            }
            parent = child!
        }
        return child
    }
}
