import AppKit

nonisolated final class TreemapViewRendererWeakReference: @unchecked Sendable {
    weak var value: TreemapViewRenderer?

    init(_ value: TreemapViewRenderer) {
        self.value = value
    }
}

@MainActor
final class TreemapViewRenderer {
    private static let directSiblingNavigationLimit: Int = 256
    private var rootItemRenderer: TreemapItemRenderer?
    private weak var dataSource: TreemapDiskItemDataSource?
    private var selectedRenderer: TreemapItemRenderer?
    private var touchedRenderer: TreemapItemRenderer?
    private var cachedContent: NSBitmapImageRep?
    private var cachedSize: NSSize?
    private var cachedScale: CGFloat?
    private var cachedColorSpace: NSColorSpace?
    private var pendingBitmapRequestID: UUID?
    private var directionalNavigationIndex: TreemapDirectionalNavigationIndex?
    var onCachedBitmapReady: (() -> Void)?
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

    var bitmapDiagnosticsDescription: String {
        guard let cachedContent else {
            return "no cached bitmap"
        }
        return "size=\(NSStringFromSize(cachedContent.size)), pixels=\(cachedContent.pixelsWide)x\(cachedContent.pixelsHigh), scale=\(cachedScale ?? 0)"
    }

    func invalidateCanvasCache() {
        deallocContentCache()
    }

    func reloadData() {
        assert(!zoomingInProgress, "cannot reload tree map while zooming is in progress")
        deallocContentCache()
        selectedRenderer = nil
        touchedRenderer = nil
        directionalNavigationIndex = nil
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
        _ = selectRenderedItem(byPathToItem: path)
    }

    func selectRenderedItem(byPathToItem path: [DiskItem]) -> Bool {
        assert(path.count > 0, "path must contain at least 1 component")
        let rendererToSelect: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path)
        guard let rendererToSelect else {
            return false
        }
        populateUnroundedRects(byPathToItem: path)
        selectItem(by: rendererToSelect)
        return true
    }

    func selectItem(byRenderedItem item: DiskItem) -> Bool {
        let path: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item)
        guard path.isEmpty == false else {
            return false
        }
        return selectRenderedItem(byPathToItem: path)
    }

    func itemRect(by cellID: TreemapItemRenderer?) -> NSRect {
        if let cellID: TreemapItemRenderer = cellID {
            return cellID.rect
        } else {
            return .zero
        }
    }

    func selectedItemUnroundedRect() -> NSRect {
        selectedRenderer?.unroundedRect ?? .zero
    }

    func selectNeighbor(in direction: TreemapNavigationDirection) -> DiskItem? {
        guard let selectedRenderer else { return nil }
        let parent: TreemapItemRenderer = selectedRenderer.parent ?? rootItemRenderer ?? selectedRenderer
        guard parent !== selectedRenderer else { return nil }
        let selectedRect: NSRect = selectedRenderer.navigationRect
        guard selectedRect.isEmpty == false else { return nil }
        let siblingCandidate: TreemapItemRenderer?
        if parent.isLeaf == false && parent.childCount <= Self.directSiblingNavigationLimit {
            siblingCandidate = nearestNeighbor(
                among: parent.childEnumerator,
                from: selectedRenderer,
                selectedRect: selectedRect,
                direction: direction
            )
        } else {
            siblingCandidate = nil
        }
        let candidate: TreemapItemRenderer? = siblingCandidate ?? directionalNavigationIndex?.nearestNeighbor(
            from: selectedRenderer,
            selectedRect: selectedRect,
            direction: direction
        )
        guard let candidate else { return nil }
        selectItem(by: candidate)
        return candidate.item
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
        directionalNavigationIndex = nil
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
        if let cachedContent,
           cachedSize == size,
           cachedScale == scale,
           colorSpacesMatch(cachedColorSpace, colorSpace) {
            return cachedContent
        }
        allocContentCache(size: size, scale: scale, colorSpace: colorSpace)
        guard let cachedContent else {
            return nil
        }
        if let rootItemRenderer {
            rootItemRenderer.drawCushion(in: cachedContent, backingScaleFactor: scale)
        }
        return cachedContent
    }

    func cachedImageOrRequestRendering(size: NSSize, scale: CGFloat = 1) -> NSBitmapImageRep? {
        if let cachedContent,
           cachedSize == size,
           cachedScale == scale {
            return cachedContent
        }
        guard pendingBitmapRequestID == nil,
              let rootItemRenderer else {
            return nil
        }
        let pixelsWide: Int = max(Int((size.width * scale).rounded(.up)), 1)
        let pixelsHigh: Int = max(Int((size.height * scale).rounded(.up)), 1)
        var navigationRenderers: [TreemapItemRenderer] = []
        let snapshots: [TreemapCushionSnapshot] = rootItemRenderer.cushionSnapshots(
            navigationRenderers: &navigationRenderers
        )
        directionalNavigationIndex = TreemapDirectionalNavigationIndex(
            renderers: navigationRenderers,
            bounds: rootItemRenderer.navigationRect
        )
        let requestID: UUID = UUID()
        let rendererReference: TreemapViewRendererWeakReference = TreemapViewRendererWeakReference(self)
        pendingBitmapRequestID = requestID
        Task.detached(priority: .userInitiated) {
            let pixels: Data = TreemapBitmapRasterizer.render(
                snapshots: snapshots,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                scale: Double(scale)
            )
            await MainActor.run {
                rendererReference.value?.installRenderedBitmap(
                    pixels,
                    requestID: requestID,
                    size: size,
                    scale: scale,
                    pixelsWide: pixelsWide,
                    pixelsHigh: pixelsHigh
                )
            }
        }
        return nil
    }

    var zoomingInProgress: Bool {
        false
    }

    private func allocContentCache(size: NSSize, scale: CGFloat, colorSpace: NSColorSpace?) {
        deallocContentCache()
        if let bitmap: NSBitmapImageRep = NSBitmapImageRep.treemapImageRepCompatible(withBounds: NSRect(origin: .zero, size: size), backingScaleFactor: scale, colorSpace: colorSpace) {
            cachedContent = bitmap
            cachedSize = size
            cachedScale = scale
            cachedColorSpace = colorSpace
        }
    }

    private func deallocContentCache() {
        cachedContent = nil
        cachedSize = nil
        cachedScale = nil
        cachedColorSpace = nil
        pendingBitmapRequestID = nil
    }

    private func installRenderedBitmap(
        _ pixels: Data,
        requestID: UUID,
        size: NSSize,
        scale: CGFloat,
        pixelsWide: Int,
        pixelsHigh: Int
    ) {
        guard pendingBitmapRequestID == requestID,
              let bitmap: NSBitmapImageRep = NSBitmapImageRep.treemapImageRepCompatible(
                withBounds: NSRect(origin: .zero, size: size),
                backingScaleFactor: scale,
                colorSpace: nil
              ),
              bitmap.pixelsWide == pixelsWide,
              bitmap.pixelsHigh == pixelsHigh,
              let destination: UnsafeMutablePointer<UInt8> = bitmap.bitmapData else {
            return
        }
        pixels.withUnsafeBytes { source in
            guard let sourceAddress: UnsafeRawPointer = source.baseAddress else { return }
            let sourceBytesPerRow: Int = pixelsWide * 3
            guard source.count == sourceBytesPerRow * pixelsHigh else { return }
            for row: Int in 0..<pixelsHigh {
                memcpy(
                    destination.advanced(by: row * bitmap.bytesPerRow),
                    sourceAddress.advanced(by: row * sourceBytesPerRow),
                    sourceBytesPerRow
                )
            }
        }
        cachedContent = bitmap
        cachedSize = size
        cachedScale = scale
        cachedColorSpace = nil
        pendingBitmapRequestID = nil
        onCachedBitmapReady?()
    }

    private func colorSpacesMatch(_ first: NSColorSpace?, _ second: NSColorSpace?) -> Bool {
        switch (first, second) {
        case (nil, nil):
            true
        case let (first?, second?):
            first.isEqual(second)
        default:
            false
        }
    }

    private func nearestNeighbor(
        among renderers: [TreemapItemRenderer],
        from selectedRenderer: TreemapItemRenderer,
        selectedRect: NSRect,
        direction: TreemapNavigationDirection
    ) -> TreemapItemRenderer? {
        let selectedCenter: NSPoint = NSPoint(x: selectedRect.midX, y: selectedRect.midY)
        return renderers
            .filter { $0 !== selectedRenderer && $0.item.isSpecialItem == false }
            .compactMap { renderer -> (TreemapItemRenderer, CGFloat)? in
                let rect: NSRect = renderer.navigationRect
                guard rect.isEmpty == false else { return nil }
                let center: NSPoint = NSPoint(x: rect.midX, y: rect.midY)
                let primaryDistance: CGFloat
                let crossDistance: CGFloat
                switch direction {
                case .left:
                    primaryDistance = selectedCenter.x - center.x
                    crossDistance = abs(selectedCenter.y - center.y)
                case .right:
                    primaryDistance = center.x - selectedCenter.x
                    crossDistance = abs(selectedCenter.y - center.y)
                case .up:
                    primaryDistance = selectedCenter.y - center.y
                    crossDistance = abs(selectedCenter.x - center.x)
                case .down:
                    primaryDistance = center.y - selectedCenter.y
                    crossDistance = abs(selectedCenter.x - center.x)
                }
                guard primaryDistance > 0 else { return nil }
                return (renderer, primaryDistance + crossDistance * 0.25)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private func findTreemapItem(byPathToDataItem path: [DiskItem]) -> TreemapItemRenderer? {
        if rootItemRenderer == nil {
            return nil
        }
        assert(path.count > 0, "path must contain at least 1 component")
        var parent: TreemapItemRenderer = rootItemRenderer!
        var child: TreemapItemRenderer? = rootItemRenderer
        for dataItem: DiskItem in path.dropFirst() {
            guard !parent.isLeaf else {
                return nil
            }
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

    private func populateUnroundedRects(byPathToItem path: [DiskItem]) {
        guard var parent: TreemapItemRenderer = rootItemRenderer else { return }
        for dataItem: DiskItem in path.dropFirst() {
            parent.layoutUnroundedChilds()
            guard let child: TreemapItemRenderer = parent.childEnumerator.first(where: { $0.item == dataItem }) else {
                return
            }
            parent = child
        }
    }
}

enum TreemapNavigationDirection: Equatable {
    case left
    case right
    case up
    case down
}
