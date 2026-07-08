import AppKit

typealias TreemapCellID = TreemapItemRenderer

nonisolated protocol TreemapViewRendererDataSource: TreemapItemRendererDataSource {
}

nonisolated protocol TreemapViewRendererDelegate: TreemapItemRendererDelegate {
    func treemapViewRendererShouldSelectItem(_ item: AnyObject) -> Bool
}

extension TreemapViewRendererDelegate {
    func treemapViewRendererShouldSelectItem(_ item: AnyObject) -> Bool {
        true
    }
}

nonisolated final class TreemapViewRenderer: @unchecked Sendable {
    private var rootItemRenderer: TreemapItemRenderer?
    private weak var delegate: TreemapViewRendererDelegate?
    private weak var dataSource: TreemapViewRendererDataSource?
    private var selectedRenderer: TreemapItemRenderer?
    private var touchedRenderer: TreemapItemRenderer?
    private var cachedContent: NSBitmapImageRep?
    private let rootItem: AnyObject
    private var rendererIndex: [ObjectIdentifier: TreemapItemRenderer] = [:]

    init(rootItem: AnyObject, dataSource: TreemapViewRendererDataSource, delegate: TreemapViewRendererDelegate?) {
        self.rootItem = rootItem
        self.dataSource = dataSource
        self.delegate = delegate
    }

    var selectedItem: AnyObject? {
        selectedRenderer == nil ? nil : selectedRenderer!.item
    }

    var selectedCellID: TreemapCellID? {
        selectedRenderer
    }

    var rootCellID: TreemapCellID? {
        rootItemRenderer
    }

    func invalidateCanvasCache() {
        deallocContentCache()
    }

    func reloadData() {
        assert(!zoomingInProgress, "cannot reload tree map while zooming is in progress")
        deallocContentCache()
        selectedRenderer = nil
        touchedRenderer = nil
        guard let dataSource: TreemapViewRendererDataSource = dataSource else {
            rendererIndex.removeAll(keepingCapacity: false)
            return
        }
        if rootItemRenderer == nil {
            rootItemRenderer = TreemapItemRenderer(dataSource: dataSource, delegate: delegate, renderedItem: rootItem)
        } else {
            rootItemRenderer?.refresh(with: rootItem)
        }
        rebuildRendererIndex()
    }

    func cellID(by point: NSPoint, inViewCoordinates viewCoordinates: Bool) -> TreemapCellID? {
        let rendererPoint: NSPoint = point
        _ = viewCoordinates
        return rootItemRenderer?.hitTest(rendererPoint)
    }

    func item(by cellID: TreemapCellID) -> AnyObject {
        cellID.item
    }

    func selectItem(by cellID: TreemapCellID?) {
        guard cellID !== selectedRenderer else { return }
        if let item: AnyObject = cellID?.item, delegate?.treemapViewRendererShouldSelectItem(item) == false {
            return
        }
        selectedRenderer = cellID
    }

    func selectItem(byPathToItem path: [AnyObject]) {
        assert(path.count > 0, "path must contain at least 1 component")
        let rendererToSelect: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path)
        if rendererToSelect != nil {
            selectItem(by: rendererToSelect)
        }
    }

    func selectItem(byRenderedItem item: AnyObject) -> Bool {
        guard let renderer: TreemapItemRenderer = rendererIndex[ObjectIdentifier(item)] else {
            return false
        }
        selectItem(by: renderer)
        return true
    }

    func itemRect(by cellID: TreemapCellID?) -> NSRect {
        if let cellID: TreemapCellID = cellID {
            return cellID.rect
        } else {
            return .zero
        }
    }

    func itemRect(byPathToItem path: [AnyObject]) -> NSRect {
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
        rootItemRenderer?.appendLayoutDiagnostics(to: &rows, depth: 0, childIndex: 0, sequence: &sequence)
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

    private func rebuildRendererIndex() {
        rendererIndex.removeAll(keepingCapacity: true)
        rootItemRenderer?.appendRendererIndex(to: &rendererIndex)
    }

    private func findTreemapItem(byPathToDataItem path: [AnyObject]) -> TreemapItemRenderer? {
        if rootItemRenderer == nil {
            return nil
        }
        assert(path.count > 0, "path must contain at least 1 component")
        var parent: TreemapItemRenderer = rootItemRenderer!
        var child: TreemapItemRenderer? = rootItemRenderer
        for dataItem: AnyObject in path.dropFirst() {
            child = parent.childEnumerator.first { renderer in
                renderer.item === dataItem
            }
            if child == nil {
                return nil
            }
            parent = child!
        }
        return child
    }
}
