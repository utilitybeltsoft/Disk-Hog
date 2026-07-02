import AppKit // ✓ Swift-only: Swift/AppKit import replacing TreeMapView.h:12 Cocoa import and TreeMapView.m:9 imports.

typealias TreemapCellID = TreemapItemRenderer // ✓ Z: TreeMapView.h:16 typedef TMVItem* TMVCellId.

nonisolated protocol TreemapViewRendererDataSource: TreemapItemRendererDataSource { // ✓ Z: TreeMapView.h:80 NSObject(TreeMapViewDataSource) category supplies required callbacks.
} // ✓ Swift-only: closes named Swift data source protocol while preserving the TMVItem callback shape from TreeMapView.h:83-86.

nonisolated protocol TreemapViewRendererDelegate: TreemapItemRendererDelegate { // ✓ Z: TreeMapView.h:90 NSObject(TreeMapViewDelegate) category supplies optional callbacks.
    func treemapViewRendererShouldSelectItem(_ item: AnyObject) -> Bool // ✓ Z: TreeMapView.h:93 treeMapView:shouldSelectItem: optional delegate method.
} // ✓ Swift-only: closes named Swift delegate protocol replacing Objective-C informal delegate category.

extension TreemapViewRendererDelegate { // ✓ Swift-only: Swift protocol extension supplies Objective-C optional delegate default.
    func treemapViewRendererShouldSelectItem(_ item: AnyObject) -> Bool { // ✓ Z: TreeMapView.h:93 treeMapView:shouldSelectItem: optional delegate method.
        true // ✓ Swift-only: default preserves Objective-C behavior when delegate does not implement shouldSelectItem:.
    } // ✓ Swift-only: closes default should-select implementation.
} // ✓ Swift-only: closes Swift optional-method emulation.

nonisolated final class TreemapViewRenderer: @unchecked Sendable { // ✓ Z: TreeMapView.h:18 @interface TreeMapView owns renderer tree state.
    private var rootItemRenderer: TreemapItemRenderer? // ✓ Z: TreeMapView.h:20 TMVItem *_rootItemRenderer.
    private weak var delegate: TreemapViewRendererDelegate? // ✓ Z: TreeMapView.h:21 IBOutlet id delegate.
    private weak var dataSource: TreemapViewRendererDataSource? // ✓ Z: TreeMapView.h:22 IBOutlet id dataSource.
    private var selectedRenderer: TreemapItemRenderer? // ✓ Z: TreeMapView.h:23 TMVItem *_selectedRenderer.
    private var touchedRenderer: TreemapItemRenderer? // ✓ Z: TreeMapView.h:24 TMVItem *_touchedRenderer.
    private var cachedContent: NSBitmapImageRep? // ✓ Z: TreeMapView.h:25 NSBitmapImageRep *_cachedContent.
    private let rootItem: AnyObject // ✓ Swift-only: Swift uses an explicit root item where Z passes nil to mean root.

    init(rootItem: AnyObject, dataSource: TreemapViewRendererDataSource, delegate: TreemapViewRendererDelegate?) { // ✓ Z: TreeMapView.m:35 initWithFrame: plus TreeMapView.m:125 setDataSource: and TreeMapView.m:101 setDelegate:.
        self.rootItem = rootItem // ✓ Swift-only: stores explicit Swift root replacing Z's nil-root convention from TreeMapView.h:78.
        self.dataSource = dataSource // ✓ Z: TreeMapView.m:127 dataSource = new_dataSource.
        self.delegate = delegate // ✓ Z: TreeMapView.m:110 delegate = new_delegate.
    } // ✓ Swift-only: closes Swift initializer replacing NSView/NIB initialization.

    var selectedItem: AnyObject? { // ✓ Z: TreeMapView.m:332 - selectedItem.
        selectedRenderer == nil ? nil : selectedRenderer!.item // ✓ Z: TreeMapView.m:334 return _selectedRenderer == nil ? nil : [_selectedRenderer item].
    } // ✓ Z: TreeMapView.m:335 closes selectedItem.

    var rootCellID: TreemapCellID? { // ✓ Swift-only: exposes root renderer for SwiftUI/AppKit integration that cannot access ivars.
        rootItemRenderer // ✓ Z: TreeMapView.h:20 _rootItemRenderer is retained as the root cell identity.
    } // ✓ Swift-only: closes root renderer accessor.

    func invalidateCanvasCache() { // ✓ Z: TreeMapView.m:396 - invalidateCanvasCache.
        deallocContentCache() // ✓ Z: TreeMapView.m:398 [self deallocContentCache].
    } // ✓ Z: TreeMapView.m:399 closes invalidateCanvasCache.

    func reloadData() { // ✓ Z: TreeMapView.m:401 - reloadData.
        assert(!zoomingInProgress, "cannot reload tree map while zooming is in progress") // ✓ Z: TreeMapView.m:403 NSAssert(![self zoomingInProgress], ...).
        deallocContentCache() // ✓ Z: TreeMapView.m:405 [self deallocContentCache].
        selectedRenderer = nil // ✓ Z: TreeMapView.m:407 _selectedRenderer = nil.
        touchedRenderer = nil // ✓ Z: TreeMapView.m:408 _touchedRenderer = nil.
        guard let dataSource: TreemapViewRendererDataSource = dataSource else { return } // ✓ Swift-only: weak data source can be nil after owner lifetime; reload cannot proceed.
        if rootItemRenderer == nil { // ✓ Z: TreeMapView.m:410 if (_rootItemRenderer == nil).
            rootItemRenderer = TreemapItemRenderer(dataSource: dataSource, delegate: delegate, renderedItem: rootItem) // ✓ Z: TreeMapView.m:412-415 alloc initWithDataSource:delegate:renderedItem:nil treeMapView:self.
        } else { // ✓ Z: TreeMapView.m:417 else.
            rootItemRenderer?.refresh(with: rootItem) // ✓ Z: TreeMapView.m:418 [_rootItemRenderer refreshWithItem:nil].
        } // ✓ Z: TreeMapView.m:410-418 closes root renderer create/refresh branch.
    } // ✓ Z: TreeMapView.m:424 closes reloadData.

    func cellID(by point: NSPoint, inViewCoordinates viewCoordinates: Bool) -> TreemapCellID? { // ✓ Z: TreeMapView.m:320 cellIdByPoint:inViewCoords:.
        let rendererPoint: NSPoint = point // ✓ Swift-only: Phase 3 has no NSView backing conversion; caller supplies renderer coordinates.
        _ = viewCoordinates // ✓ Swift-only: preserves Z API shape until NSView/SwiftUI integration supplies coordinate conversion.
        return rootItemRenderer?.hitTest(rendererPoint) // ✓ Z: TreeMapView.m:329 return [_rootItemRenderer hitTest:point].
    } // ✓ Z: TreeMapView.m:330 closes cellIdByPoint:inViewCoords:.

    func item(by cellID: TreemapCellID) -> AnyObject { // ✓ Z: TreeMapView.m:337 - itemByCellId:.
        cellID.item // ✓ Z: TreeMapView.m:341 return [cellId item].
    } // ✓ Z: TreeMapView.m:342 closes itemByCellId:.

    func selectItem(by cellID: TreemapCellID?) { // ✓ Z: TreeMapView.m:344 - selectItemByCellId:.
        guard cellID !== selectedRenderer else { return } // ✓ Z: TreeMapView.m:346 if (cellId != _selectedRenderer).
        if let item: AnyObject = cellID?.item, delegate?.treemapViewRendererShouldSelectItem(item) == false { // ✓ Z: TreeMapView.h:93 optional shouldSelectItem: delegate hook.
            return // ✓ Swift-only: preserves Objective-C optional selection veto without a respondsToSelector check.
        } // ✓ Swift-only: closes Swift optional selection veto.
        selectedRenderer = cellID // ✓ Z: TreeMapView.m:348 _selectedRenderer = cellId.
    } // ✓ Z: TreeMapView.m:355 closes selectItemByCellId:.

    func selectItem(byPathToItem path: [AnyObject]) { // ✓ Z: TreeMapView.m:357 - selectItemByPathToItem:.
        assert(path.count > 0, "path must contain at least 1 component") // ✓ Z: TreeMapView.m:360 NSAssert([path count] > 0, ...).
        let rendererToSelect: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path) // ✓ Z: TreeMapView.m:362 TMVItem *rendererToSelect = [self findTMVItemByPathToDataItem:path].
        if rendererToSelect != nil { // ✓ Z: TreeMapView.m:364 if (rendererToSelect != nil).
            selectItem(by: rendererToSelect) // ✓ Z: TreeMapView.m:365 [self selectItemByCellId:rendererToSelect].
        } // ✓ Z: TreeMapView.m:364-365 closes found-renderer branch.
    } // ✓ Z: TreeMapView.m:366 closes selectItemByPathToItem:.

    func itemRect(by cellID: TreemapCellID?) -> NSRect { // ✓ Z: TreeMapView.m:368 - itemRectByCellId:.
        if let cellID: TreemapCellID = cellID { // ✓ Z: TreeMapView.m:372 if (cellId != nil).
            return cellID.rect // ✓ Z: TreeMapView.m:375 return converted [cellId rect].
        } else { // ✓ Z: TreeMapView.m:376 else.
            return .zero // ✓ Z: TreeMapView.m:377 return NSZeroRect.
        } // ✓ Z: TreeMapView.m:372-377 closes rect/nil branch.
    } // ✓ Z: TreeMapView.m:378 closes itemRectByCellId:.

    func itemRect(byPathToItem path: [AnyObject]) -> NSRect { // ✓ Z: TreeMapView.m:381 - itemRectByPathToItem:.
        assert(path.count > 0, "path must contain at least 1 component") // ✓ Z: TreeMapView.m:384 NSAssert([path count] > 0, ...).
        let renderer: TreemapItemRenderer? = findTreemapItem(byPathToDataItem: path) // ✓ Z: TreeMapView.m:386 TMVItem *renderer = [self findTMVItemByPathToDataItem:path].
        if let renderer: TreemapItemRenderer = renderer { // ✓ Z: TreeMapView.m:388 if (renderer != nil).
            return renderer.rect // ✓ Z: TreeMapView.m:391 return converted [renderer rect].
        } else { // ✓ Z: TreeMapView.m:392 else.
            return .zero // ✓ Z: TreeMapView.m:393 return NSZeroRect.
        } // ✓ Z: TreeMapView.m:388-393 closes renderer/nil branch.
    } // ✓ Z: TreeMapView.m:394 closes itemRectByPathToItem:.

    func calcLayout(_ bounds: NSRect) { // ✓ Z: TreeMapView.m:189-192 updateLayout branch calls [_rootItemRenderer calcLayout:viewBounds].
        rootItemRenderer?.calcLayout(bounds) // ✓ Z: TreeMapView.m:192 [_rootItemRenderer calcLayout:viewBounds].
        deallocContentCache() // ✓ Z: TreeMapView.m:194 [self deallocContentCache].
    } // ✓ Swift-only: closes extracted layout helper for non-NSView integration.

    func drawInCache(size: NSSize) -> NSBitmapImageRep? { // ✓ Z: TreeMapView.m:659 - drawInCache.
        if cachedContent != nil { // ✓ Z: TreeMapView.m:661 if (_cachedContent != nil).
            return cachedContent // ✓ Z: TreeMapView.m:662 return.
        } // ✓ Z: TreeMapView.m:661-662 closes existing-cache guard.
        allocContentCache(size: size) // ✓ Z: TreeMapView.m:664 [self allocContentCache].
        if rootItemRenderer != nil { // ✓ Z: TreeMapView.m:666 if (_rootItemRenderer != NULL).
            rootItemRenderer?.drawCushion(in: cachedContent!) // ✓ Z: TreeMapView.m:668 [_rootItemRenderer drawCushionInBitmap:_cachedContent].
        } // ✓ Z: TreeMapView.m:666-669 closes root draw branch.
        return cachedContent // ✓ Swift-only: returns cache for SwiftUI/AppKit bridge drawing.
    } // ✓ Z: TreeMapView.m:670 closes drawInCache.

    var zoomingInProgress: Bool { // ✓ Z: TreeMapView.m:514 - zoomingInProgress.
        false // ✓ Z: TreeMapView.m:516 return _zoomer != nil; Phase 3 has no ZoomInfo object yet.
    } // ✓ Z: TreeMapView.m:517 closes zoomingInProgress.

    private func allocContentCache(size: NSSize) { // ✓ Z: TreeMapView.m:672 - allocContentCache.
        cachedContent = nil // ✓ Z: TreeMapView.m:674 [_cachedContent release].
        cachedContent = NSBitmapImageRep( // ✓ Z: TreeMapView.m:676 _cachedContent = [[NSBitmapImageRep imageRepCompatibleWithView:self] retain].
            bitmapDataPlanes: nil, // ✓ Swift-only: explicit Swift bitmap constructor argument replacing imageRepCompatibleWithView helper.
            pixelsWide: max(Int(size.width), 1), // ✓ Swift-only: explicit pixel width replacing NSView backing-size helper.
            pixelsHigh: max(Int(size.height), 1), // ✓ Swift-only: explicit pixel height replacing NSView backing-size helper.
            bitsPerSample: 8, // ✓ Z: TreeMapView.m:637 bitmap has 24 bit color depth.
            samplesPerPixel: 3, // ✓ Z: TreeMapView.m:637 bitmap has 24 bit color depth.
            hasAlpha: false, // ✓ Z: TreeMapView.m:637 comment says no alpha component.
            isPlanar: false, // ✓ Swift-only: explicit Swift bitmap constructor argument matching Z's RGB bitmap helper.
            colorSpaceName: .deviceRGB, // ✓ Swift-only: explicit Swift bitmap constructor argument matching Z's RGB bitmap helper.
            bytesPerRow: 0, // ✓ Swift-only: explicit Swift bitmap constructor argument lets AppKit calculate row bytes.
            bitsPerPixel: 0 // ✓ Swift-only: explicit Swift bitmap constructor argument lets AppKit calculate pixel bits.
        ) // ✓ Swift-only: closes Swift bitmap allocation expression.
    } // ✓ Z: TreeMapView.m:677 closes allocContentCache.

    private func deallocContentCache() { // ✓ Z: TreeMapView.m:679 - deallocContentCache.
        if cachedContent != nil { // ✓ Z: TreeMapView.m:681 if (_cachedContent != nil).
            cachedContent = nil // ✓ Z: TreeMapView.m:683-684 release and nil _cachedContent.
        } // ✓ Z: TreeMapView.m:681-685 closes cache-release branch.
    } // ✓ Z: TreeMapView.m:686 closes deallocContentCache.

    private func findTreemapItem(byPathToDataItem path: [AnyObject]) -> TreemapItemRenderer? { // ✓ Z: TreeMapView.m:688 - findTMVItemByPathToDataItem:.
        if rootItemRenderer == nil { // ✓ Z: TreeMapView.m:690 if (_rootItemRenderer == nil).
            return nil // ✓ Z: TreeMapView.m:691 return nil.
        } // ✓ Z: TreeMapView.m:690-691 closes missing-root guard.
        assert(path.count > 0, "path must contain at least 1 component") // ✓ Z: TreeMapView.m:693 NSAssert([path count] > 0, ...).
        var parent: TreemapItemRenderer = rootItemRenderer! // ✓ Z: TreeMapView.m:695 TMVItem *parent = _rootItemRenderer.
        var child: TreemapItemRenderer? = rootItemRenderer // ✓ Z: TreeMapView.m:696 TMVItem *child = _rootItemRenderer.
        for dataItem: AnyObject in path.dropFirst() { // ✓ Z: TreeMapView.m:698-702 enumerates path and starts with second item.
            child = parent.childEnumerator.first { renderer in // ✓ Z: TreeMapView.m:704-707 enumerates children while child item is not dataItem.
                renderer.item === dataItem // ✓ Z: TreeMapView.m:707 [child item] != dataItem pointer identity comparison.
            } // ✓ Swift-only: closes Swift first(where:) equivalent of Objective-C while enumeration.
            if child == nil { // ✓ Z: TreeMapView.m:709 if (child == nil).
                return nil // ✓ Z: TreeMapView.m:710 return nil.
            } // ✓ Z: TreeMapView.m:709-710 closes not-found guard.
            parent = child! // ✓ Z: TreeMapView.m:712 parent = child.
        } // ✓ Z: TreeMapView.m:702-713 closes path enumeration.
        return child // ✓ Z: TreeMapView.m:715 return child.
    } // ✓ Z: TreeMapView.m:716 closes findTMVItemByPathToDataItem:.
} // ✓ Z: TreeMapView.m:755 closes TreeMapView private implementation.
