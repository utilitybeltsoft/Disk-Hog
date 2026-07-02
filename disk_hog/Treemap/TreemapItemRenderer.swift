import AppKit // ✓ Swift-only: Swift/AppKit import replacing TMVItem.h:9 Foundation import plus NSRect/NSBitmapImageRep use.

nonisolated protocol TreemapItemRendererDataSource: AnyObject { // ✓ Z: TreeMapView.h:80 NSObject(TreeMapViewDataSource) supplies item tree callbacks.
    func treemapItemRendererChild(_ index: Int, of item: AnyObject) -> AnyObject // ✓ Z: TreeMapView.h:83 treeMapView:child:ofItem: required data source method.
    func treemapItemRendererIsNode(_ item: AnyObject) -> Bool // ✓ Z: TreeMapView.h:84 treeMapView:isNode: required data source method.
    func treemapItemRendererNumberOfChildren(of item: AnyObject) -> Int // ✓ Z: TreeMapView.h:85 treeMapView:numberOfChildrenOfItem: required data source method.
    func treemapItemRendererWeight(of item: AnyObject) -> UInt64 // ✓ Z: TreeMapView.h:86 treeMapView:weightByItem: required data source method.
} // ✓ Swift-only: closes Swift protocol replacing Objective-C informal data source category.

nonisolated protocol TreemapItemRendererDelegate: AnyObject { // ✓ Z: TreeMapView.h:90 NSObject(TreeMapViewDelegate) supplies optional display callback.
    func treemapItemRendererWillDisplay(_ item: AnyObject, with renderer: TreemapItemRenderer) // ✓ Z: TreeMapView.h:92 treeMapView:willDisplayItem:withRenderer: optional delegate method.
} // ✓ Swift-only: closes Swift protocol replacing Objective-C informal delegate category.

nonisolated final class TreemapItemRenderer: @unchecked Sendable { // ✓ Z: TMVItem.h:13 declares TMVItem object holding display information for one cell.
    private static let cushionScaleFactor: CGFloat = 0.9 // ✓ Z: TMVItem.m:13 #define CUSHION_SCALE_FACTOR 0.9f.

    private weak var dataSource: TreemapItemRendererDataSource? // ✓ Z: TMVItem.h:15 id _dataSource.
    private weak var delegate: TreemapItemRendererDelegate? // ✓ Z: TMVItem.h:16 id _delegate.
    private var renderedItem: AnyObject // ✓ Z: TMVItem.h:17 id _item.
    private var rectValue: NSRect // ✓ Z: TMVItem.h:20 NSRect _rect.
    private var childRenderers: [TreemapItemRenderer]? // ✓ Z: TMVItem.h:21 NSMutableArray *_childRenderers.
    private let cushionRenderer: TreemapCushionRenderer // ✓ Z: TMVItem.h:22 TMVCushionRenderer *_cushionRenderer.

    init(dataSource: TreemapItemRendererDataSource, delegate: TreemapItemRendererDelegate?, renderedItem item: AnyObject) { // ✓ Z: TMVItem.m:63 initWithDataSource:delegate:renderedItem:treeMapView:.
        self.renderedItem = item // ✓ Z: TMVItem.m:67 _item = item.
        self.dataSource = dataSource // ✓ Z: TMVItem.m:68 _dataSource = dataSource.
        self.delegate = delegate // ✓ Z: TMVItem.m:69 _delegate = delegate.
        self.rectValue = .zero // ✓ Z: TMVItem.m:71 _rect = NSZeroRect.
        self.cushionRenderer = TreemapCushionRenderer() // ✓ Z: TMVItem.m:73 _cushionRenderer = [[TMVCushionRenderer alloc] init].
        if !isLeaf { // ✓ Z: TMVItem.m:75 if (![self isLeaf]).
            createChildRenderers() // ✓ Z: TMVItem.m:76 [self createChildRenderers].
        } // ✓ Z: TMVItem.m:75-76 closes child-renderer creation guard.
    } // ✓ Z: TMVItem.m:79 closes initWithDataSource:delegate:renderedItem:treeMapView:.

    func refresh(with item: AnyObject) { // ✓ Z: TMVItem.m:89 - refreshWithItem:.
        renderedItem = item // ✓ Z: TMVItem.m:91 _item = item.
        rectValue = .zero // ✓ Z: TMVItem.m:92 _rect = NSZeroRect.
        cushionRenderer.setRect(.zero) // ✓ Z: TMVItem.m:94 [_cushionRenderer setRect:NSZeroRect].
        if !isLeaf { // ✓ Z: TMVItem.m:96 if (![self isLeaf]).
            createChildRenderers() // ✓ Z: TMVItem.m:97 [self createChildRenderers].
        } else { // ✓ Z: TMVItem.m:98 else.
            childRenderers = nil // ✓ Z: TMVItem.m:100-101 releases child renderers and sets _childRenderers = nil.
        } // ✓ Z: TMVItem.m:102 closes leaf/non-leaf refresh branch.
    } // ✓ Z: TMVItem.m:103 closes refreshWithItem:.

    func setCushionColor(_ color: NSColor) { // ✓ Z: TMVItem.m:105 - setCushionColor:.
        cushionRenderer.setColor(color) // ✓ Z: TMVItem.m:107 [_cushionRenderer setColor:color].
    } // ✓ Z: TMVItem.m:108 closes setCushionColor:.

    func calcLayout(_ proposedRect: NSRect) { // ✓ Z: TMVItem.m:110 - calcLayout:.
        let rect: NSRect = proposedRect.integral // ✓ Z: TMVItem.m:117 rect = NSIntegralRect(rect).
        if rectValue.equalTo(rect) { // ✓ Z: TMVItem.m:119 if (NSEqualRects(_rect, rect)).
            return // ✓ Z: TMVItem.m:120 return.
        } // ✓ Z: TMVItem.m:119-120 closes unchanged-rect guard.
        assert(rect.origin.x - CGFloat(Int(rect.origin.x)) == 0.0) // ✓ Z: TMVItem.m:124 asserts integral rect.origin.x.
        assert(rect.origin.y - CGFloat(Int(rect.origin.y)) == 0.0) // ✓ Z: TMVItem.m:125 asserts integral rect.origin.y.
        assert(rect.size.width - CGFloat(Int(rect.size.width)) == 0.0) // ✓ Z: TMVItem.m:126 asserts integral rect.size.width.
        assert(rect.size.height - CGFloat(Int(rect.size.height)) == 0.0) // ✓ Z: TMVItem.m:127 asserts integral rect.size.height.
        rectValue = rect // ✓ Z: TMVItem.m:129 _rect = rect.
        cushionRenderer.setRect(rect) // ✓ Z: TMVItem.m:130 [_cushionRenderer setRect:rect].
        if rect.height < 1 || rect.width < 1 { // ✓ Z: TMVItem.m:132-136 returns when converted rect is too small.
            return // ✓ Z: TMVItem.m:136 return.
        } // ✓ Z: TMVItem.m:132-136 closes too-small guard.
        if !isLeaf { // ✓ Z: TMVItem.m:139 if (![self isLeaf]).
            layoutChilds() // ✓ Z: TMVItem.m:140 [self layoutChilds].
        } // ✓ Z: TMVItem.m:139-140 closes layout-child guard.
    } // ✓ Z: TMVItem.m:141 closes calcLayout:.

    func drawCushion(in bitmap: NSBitmapImageRep) { // ✓ Z: TMVItem.m:191 - drawCushionInBitmap:.
        drawCushion(in: bitmap, parentCushion: nil, cushionHeightFactor: 0.5) // ✓ Z: TMVItem.m:193 drawCushionInBitmap:parentCushion:nil cushionHeightFactor:0.5f.
    } // ✓ Z: TMVItem.m:194 closes drawCushionInBitmap:.

    var isLeaf: Bool { // ✓ Z: TMVItem.m:196 - isLeaf.
        guard let dataSource: TreemapItemRendererDataSource = dataSource else { return true } // ✓ Swift-only: weak data source can be nil after owner lifetime; leaf is safest fallback.
        return !dataSource.treemapItemRendererIsNode(renderedItem) // ✓ Z: TMVItem.m:198 return ![_dataSource treeMapView:_view isNode:_item].
    } // ✓ Z: TMVItem.m:199 closes isLeaf.

    var item: AnyObject { // ✓ Z: TMVItem.m:201 - item.
        renderedItem // ✓ Z: TMVItem.m:203 return _item.
    } // ✓ Z: TMVItem.m:204 closes item.

    var weight: UInt64 { // ✓ Z: TMVItem.m:206 - weight.
        dataSource?.treemapItemRendererWeight(of: renderedItem) ?? 0 // ✓ Z: TMVItem.m:208 return [_dataSource treeMapView:_view weightByItem:_item].
    } // ✓ Z: TMVItem.m:209 closes weight.

    var rect: NSRect { // ✓ Z: TMVItem.m:211 - rect.
        rectValue // ✓ Z: TMVItem.m:213 return _rect.
    } // ✓ Z: TMVItem.m:214 closes rect.

    var childEnumerator: [TreemapItemRenderer] { // ✓ Z: TMVItem.m:216 - childEnumerator.
        assert(childRenderers != nil, "method 'childEnumerator' can only be invoked for nodes, not for leafs") // ✓ Z: TMVItem.m:218 NSAssert(_childRenderers != nil, ...).
        return childRenderers ?? [] // ✓ Z: TMVItem.m:220 return [_childRenderers objectEnumerator].
    } // ✓ Z: TMVItem.m:221 closes childEnumerator.

    var childCount: Int { // ✓ Z: TMVItem.m:228 - childCount.
        childRenderers?.count ?? 0 // ✓ Z: TMVItem.m:230 return [_childRenderers count].
    } // ✓ Z: TMVItem.m:231 closes childCount.

    func child(at index: Int) -> TreemapItemRenderer { // ✓ Z: TMVItem.m:223 - childAtIndex:.
        childRenderers![index] // ✓ Z: TMVItem.m:225 return [_childRenderers objectAtIndex:childIndex].
    } // ✓ Z: TMVItem.m:226 closes childAtIndex:.

    func hitTest(_ point: NSPoint) -> TreemapItemRenderer? { // ✓ Z: TMVItem.m:233 - hitTest:.
        if !rectValue.contains(point) { // ✓ Z: TMVItem.m:235 if (!NSPointInRect(aPoint, _rect)).
            return nil // ✓ Z: TMVItem.m:236 return nil.
        } // ✓ Z: TMVItem.m:235-236 closes outside-rect guard.
        if isLeaf { // ✓ Z: TMVItem.m:238 if ([self isLeaf]).
            return self // ✓ Z: TMVItem.m:240 return self.
        } // ✓ Z: TMVItem.m:238-241 closes leaf hit branch.
        for childRenderer: TreemapItemRenderer in childRenderers ?? [] { // ✓ Z: TMVItem.m:244-247 enumerates _childRenderers.
            let hitChildRenderer: TreemapItemRenderer? = childRenderer.hitTest(point) // ✓ Z: TMVItem.m:248 TMVItem *hittedChildRenderer = [childRenderer hitTest:aPoint].
            if hitChildRenderer != nil { // ✓ Z: TMVItem.m:249 if (hittedChildRenderer != nil).
                return hitChildRenderer // ✓ Z: TMVItem.m:250 return hittedChildRenderer.
            } // ✓ Z: TMVItem.m:249-250 closes child-hit branch.
        } // ✓ Z: TMVItem.m:246-251 closes child enumeration.
        return nil // ✓ Z: TMVItem.m:252 return nil.
    } // ✓ Z: TMVItem.m:254 closes hitTest:.

    private func drawCushion(in bitmap: NSBitmapImageRep, parentCushion: TreemapCushionRenderer?, cushionHeightFactor heightFactor: CGFloat) { // ✓ Z: TMVItem.m:262 drawCushionInBitmap:parentCushion:cushionHeightFactor:.
        if rectValue.height < 1 || rectValue.width < 1 { // ✓ Z: TMVItem.m:264-268 returns when converted rect is too small.
            return // ✓ Z: TMVItem.m:268 return.
        } // ✓ Z: TMVItem.m:264-268 closes too-small guard.
        if let parentCushion: TreemapCushionRenderer = parentCushion { // ✓ Z: TMVItem.m:271 if (parentCushion != NULL).
            cushionRenderer.setSurface(parentCushion.surfaceValues()) // ✓ Z: TMVItem.m:273 [_cushionRenderer setSurface:[parentCushion surface]].
            cushionRenderer.addRidgeByHeightFactor(heightFactor) // ✓ Z: TMVItem.m:274 [_cushionRenderer addRidgeByHeightFactor:heightFactor].
        } // ✓ Z: TMVItem.m:271-275 closes parent-cushion branch.
        if isLeaf { // ✓ Z: TMVItem.m:277 if ([self isLeaf]).
            delegate?.treemapItemRendererWillDisplay(renderedItem, with: self) // ✓ Z: TMVItem.m:279-280 optional delegate willDisplayItem callback.
            cushionRenderer.renderCushion(in: bitmap) // ✓ Z: TMVItem.m:282 [_cushionRenderer renderCushionInBitmap:bitmap].
        } else { // ✓ Z: TMVItem.m:303 else.
            for childRenderer: TreemapItemRenderer in childRenderers ?? [] { // ✓ Z: TMVItem.m:305-306 for i over _childRenderers.
                childRenderer.drawCushion(in: bitmap, parentCushion: cushionRenderer, cushionHeightFactor: heightFactor * Self.cushionScaleFactor) // ✓ Z: TMVItem.m:307 recursive drawCushionInBitmap:parentCushion:cushionHeightFactor:.
            } // ✓ Z: TMVItem.m:306-307 closes child cushion loop.
        } // ✓ Z: TMVItem.m:302-308 closes leaf/non-leaf cushion branch.
    } // ✓ Z: TMVItem.m:309 closes private drawCushionInBitmap:parentCushion:cushionHeightFactor:.

    private func layoutChilds() { // ✓ Z: TMVItem.m:311 - layoutChilds.
        var rows: [Double] = [] // ✓ Z: TMVItem.m:315 NSMutableArray *rows stores row height fractions.
        var childsPerRow: [Int] = [] // ✓ Z: TMVItem.m:316 NSMutableArray *childsPerRow stores children per row.
        var childWidths: [Double] = [] // ✓ Z: TMVItem.m:317 NSMutableArray *childWidths stores child width fractions.
        let horizontalRows: Bool = arrangeChildsOnRows(rows: &rows, childsPerRow: &childsPerRow, childWidths: &childWidths) // ✓ Z: TMVItem.m:321-324 arrangeChildsOnRows:... rowsAreHoriz:&horizontalRows.
        let parentWidth: Int = Int(horizontalRows ? rectValue.width : rectValue.height) // ✓ Z: TMVItem.m:326 const int parentWidth = horizontalRows ? NSWidth(_rect) : NSHeight(_rect).
        let parentHeight: Int = Int(horizontalRows ? rectValue.height : rectValue.width) // ✓ Z: TMVItem.m:327 const int parentHeight = horizontalRows ? NSHeight(_rect) : NSWidth(_rect).
        let parentBottom: Int = Int(horizontalRows ? rectValue.maxY : rectValue.maxX) // ✓ Z: TMVItem.m:329 parentBottom from NSMaxY/NSMaxX.
        let parentRight: Int = Int(horizontalRows ? rectValue.maxX : rectValue.maxY) // ✓ Z: TMVItem.m:330 parentRight from NSMaxX/NSMaxY.
        let parentLeft: Int = Int(horizontalRows ? rectValue.minX : rectValue.minY) // ✓ Z: TMVItem.m:331 parentLeft from NSMinX/NSMinY.
        var childIndex: Int = 0 // ✓ Z: TMVItem.m:333 unsigned childIndex = 0.
        var top: Int = Int(horizontalRows ? rectValue.minY : rectValue.minX) // ✓ Z: TMVItem.m:336 int top = horizontalRows ? NSMinY(_rect) : NSMinX(_rect).
        for row: Int in 0..<rows.count { // ✓ Z: TMVItem.m:338 for (row = 0; row < [rows count]; row++).
            var bottom: Int = top + Int((rows[row] * Double(parentHeight)).rounded()) // ✓ Z: TMVItem.m:340 bottom = top + roundf(rowHeight * parentHeight).
            if bottom > parentBottom || row == rows.count - 1 { // ✓ Z: TMVItem.m:342 if bottom > parentBottom || last row.
                bottom = parentBottom // ✓ Z: TMVItem.m:343 bottom = parentBottom.
            } // ✓ Z: TMVItem.m:342-343 closes bottom correction.
            var left: Int = parentLeft // ✓ Z: TMVItem.m:345 int left = parentLeft.
            for column: Int in 0..<childsPerRow[row] { // ✓ Z: TMVItem.m:347 for column < childsPerRow[row].
                var right: Int = left + Int((childWidths[childIndex] * Double(parentWidth)).rounded()) // ✓ Z: TMVItem.m:349 right = left + roundf(childWidth * parentWidth).
                if right > parentRight || column == childsPerRow[row] - 1 { // ✓ Z: TMVItem.m:351 if right > parentRight || last child in row.
                    right = parentRight // ✓ Z: TMVItem.m:352 right = parentRight.
                } // ✓ Z: TMVItem.m:351-352 closes right correction.
                let childRect: NSRect // ✓ Z: TMVItem.m:354 NSRect rcChild.
                if horizontalRows { // ✓ Z: TMVItem.m:355 if (horizontalRows).
                    childRect = NSRect(x: left, y: top, width: right - left, height: bottom - top) // ✓ Z: TMVItem.m:357-360 sets horizontal child rect.
                } else { // ✓ Z: TMVItem.m:362 else.
                    childRect = NSRect(x: top, y: left, width: bottom - top, height: right - left) // ✓ Z: TMVItem.m:364-367 sets vertical child rect.
                } // ✓ Z: TMVItem.m:355-368 closes orientation branch.
                childRenderers![childIndex].calcLayout(childRect) // ✓ Z: TMVItem.m:370-372 childRenderer = _childRenderers[childIndex]; [childRenderer calcLayout:rcChild].
                left = right // ✓ Z: TMVItem.m:374 left = right.
                childIndex += 1 // ✓ Z: TMVItem.m:347 column++, childIndex++.
            } // ✓ Z: TMVItem.m:347-375 closes column loop.
            top = bottom // ✓ Z: TMVItem.m:377 top = bottom.
        } // ✓ Z: TMVItem.m:338-378 closes row loop.
    } // ✓ Z: TMVItem.m:385 closes layoutChilds.

    private func arrangeChildsOnRows(rows: inout [Double], childsPerRow: inout [Int], childWidths: inout [Double]) -> Bool { // ✓ Z: TMVItem.m:387 arrangeChildsOnRows:childsPerRow:childWidths:rowsAreHoriz:.
        let childCount: Int = childRenderers?.count ?? 0 // ✓ Z: TMVItem.m:392 NSUInteger childCount = [_childRenderers count].
        if weight == 0 { // ✓ Z: TMVItem.m:396 if ([self weight] == 0).
            rows.append(1) // ✓ Z: TMVItem.m:398-399 adds row height 1.
            childsPerRow.append(childCount) // ✓ Z: TMVItem.m:402-403 adds all children in one row.
            let standardWidth: Double = 1.0 / Double(childCount) // ✓ Z: TMVItem.m:406 id standardWidth = numberWithDouble:1.0/childCount.
            for _: Int in 0..<childCount { // ✓ Z: TMVItem.m:407 for i < childCount.
                childWidths.append(standardWidth) // ✓ Z: TMVItem.m:408 [childWidths addObject:standardWidth].
            } // ✓ Z: TMVItem.m:407-408 closes standard-width loop.
            return true // ✓ Z: TMVItem.m:410 *horizontal = TRUE.
        } // ✓ Z: TMVItem.m:396-411 closes zero-weight branch.
        let horizontal: Bool = rectValue.size.width >= rectValue.size.height // ✓ Z: TMVItem.m:414 *horizontal = _rect.size.width >= _rect.size.height.
        var width: Double = 1 // ✓ Z: TMVItem.m:416 double width = 1.
        if horizontal { // ✓ Z: TMVItem.m:417 if (*horizontal).
            if rectValue.size.height > 0 { // ✓ Z: TMVItem.m:419 if (_rect.size.height > 0).
                width = Double(rectValue.size.width / rectValue.size.height) // ✓ Z: TMVItem.m:420 width = _rect.size.width / _rect.size.height.
            } // ✓ Z: TMVItem.m:419-420 closes horizontal height guard.
        } else { // ✓ Z: TMVItem.m:422 else.
            if rectValue.size.width > 0 { // ✓ Z: TMVItem.m:424 if (_rect.size.width > 0).
                width = Double(rectValue.size.height / rectValue.size.width) // ✓ Z: TMVItem.m:425 width = _rect.size.height / _rect.size.width.
            } // ✓ Z: TMVItem.m:424-425 closes vertical width guard.
        } // ✓ Z: TMVItem.m:417-426 closes width calculation.
        var index: Int = 0 // ✓ Z: TMVItem.m:428 for (i = 0; i < childCount;).
        while index < childCount { // ✓ Z: TMVItem.m:428 loops until all children used.
            let result: RowCalculation = calculateRow(startChildIndex: index, rowWidth: width, childWidths: &childWidths) // ✓ Z: TMVItem.m:430-434 calculateRow:rowWidth:childsUsed:childWidths:.
            rows.append(result.rowHeight) // ✓ Z: TMVItem.m:436-437 adds rowHeight.
            childsPerRow.append(result.childsUsed) // ✓ Z: TMVItem.m:440-441 adds childsUsed.
            index += result.childsUsed // ✓ Z: TMVItem.m:444 i += childsUsed.
        } // ✓ Z: TMVItem.m:428-445 closes row arrangement loop.
        return horizontal // ✓ Z: TMVItem.m:414 stores horizontal orientation through output pointer.
    } // ✓ Z: TMVItem.m:447 closes arrangeChildsOnRows:.

    private func calculateRow(startChildIndex: Int, rowWidth: Double, childWidths: inout [Double]) -> RowCalculation { // ✓ Z: TMVItem.m:449 calculateRow:rowWidth:childsUsed:childWidths:.
        let minProportion: Double = 0.4 // ✓ Z: TMVItem.m:454 static const double minProportion = 0.4.
        let mySize: Double = Double(weight) // ✓ Z: TMVItem.m:455 const double mySize = [self weight].
        var index: Int = startChildIndex // ✓ Z: TMVItem.m:456 NSUInteger i.
        var sizeUsed: Double = 0 // ✓ Z: TMVItem.m:457 double sizeUsed = 0.
        var rowHeight: Double = 0 // ✓ Z: TMVItem.m:458 double rowHeight = 0.
        let childCount: Int = childRenderers?.count ?? 0 // ✓ Z: TMVItem.m:459 NSUInteger childCount = [_childRenderers count].
        while index < childCount { // ✓ Z: TMVItem.m:463 for (i = startChildIndex; i < childCount; i++).
            let childSize: Double = Double(childRenderers![index].weight) // ✓ Z: TMVItem.m:465 double childSize = [[_childRenderers objectAtIndex:i] weight].
            if childSize == 0 { // ✓ Z: TMVItem.m:466 if (childSize == 0).
                assert(index > startChildIndex) // ✓ Z: TMVItem.m:468 NSAssert(i > startChildIndex, ...).
                break // ✓ Z: TMVItem.m:469 break.
            } // ✓ Z: TMVItem.m:466-470 closes zero-size guard.
            sizeUsed += childSize // ✓ Z: TMVItem.m:472 sizeUsed += childSize.
            let virtualRowHeight: Double = sizeUsed / mySize // ✓ Z: TMVItem.m:473 double virtualRowHeight = sizeUsed / mySize.
            assert(virtualRowHeight > 0 && virtualRowHeight <= 1) // ✓ Z: TMVItem.m:474 asserts calculated parent size is valid.
            let childWidth: Double = childSize / mySize * rowWidth / virtualRowHeight // ✓ Z: TMVItem.m:480 double childWidth = childSize / mySize * rowWidth / virtualRowHeight.
            if childWidth / virtualRowHeight < minProportion { // ✓ Z: TMVItem.m:482 if childWidth / virtualRowHeight < minProportion.
                assert(index > startChildIndex) // ✓ Z: TMVItem.m:484 NSAssert(i > startChildIndex, ...).
                break // ✓ Z: TMVItem.m:492 break.
            } // ✓ Z: TMVItem.m:482-493 closes min-proportion branch.
            rowHeight = virtualRowHeight // ✓ Z: TMVItem.m:494 rowHeight = virtualRowHeight.
            index += 1 // ✓ Z: TMVItem.m:463 i++.
        } // ✓ Z: TMVItem.m:463-495 closes row scan loop.
        assert(index > startChildIndex) // ✓ Z: TMVItem.m:496 NSAssert(i > startChildIndex, ...).
        while index < childCount && childRenderers![index].weight == 0 { // ✓ Z: TMVItem.m:502 while remaining children have weight 0.
            index += 1 // ✓ Z: TMVItem.m:503 i++.
        } // ✓ Z: TMVItem.m:502-503 closes zero-sized child inclusion loop.
        let childsUsed: Int = index - startChildIndex // ✓ Z: TMVItem.m:505 *childsUsed = i - startChildIndex.
        let rowSize: Double = mySize * rowHeight // ✓ Z: TMVItem.m:508 double rowSize = mySize * rowHeight.
        for offset: Int in 0..<childsUsed { // ✓ Z: TMVItem.m:511 for i = 0; i < *childsUsed; i++.
            let childSize: Double = Double(childRenderers![startChildIndex + offset].weight) // ✓ Z: TMVItem.m:513 childSize = child renderer weight.
            let childWidth: Double = childSize / rowSize // ✓ Z: TMVItem.m:514 double cw = childSize / rowSize.
            childWidths.append(childWidth) // ✓ Z: TMVItem.m:517-518 adds child width to childWidths.
        } // ✓ Z: TMVItem.m:511-520 closes child width loop.
        return RowCalculation(rowHeight: rowHeight, childsUsed: childsUsed) // ✓ Z: TMVItem.m:522 return rowHeight plus childsUsed out parameter.
    } // ✓ Z: TMVItem.m:523 closes calculateRow:.

    private func createChildRenderers() { // ✓ Z: TMVItem.m:525 - createChildRenderers.
        guard let dataSource: TreemapItemRendererDataSource = dataSource else { return } // ✓ Swift-only: weak data source can be nil after owner lifetime; no children can be built.
        let childCount: Int = dataSource.treemapItemRendererNumberOfChildren(of: renderedItem) // ✓ Z: TMVItem.m:527 childCount = [_dataSource treeMapView:_view numberOfChildrenOfItem:_item].
        if childRenderers == nil { // ✓ Z: TMVItem.m:529 if (_childRenderers == nil).
            childRenderers = [] // ✓ Z: TMVItem.m:530 _childRenderers = [[NSMutableArray alloc] initWithCapacity:childCount].
        } // ✓ Z: TMVItem.m:529-530 closes child renderer allocation.
        var existingRendererCount: Int = childRenderers?.count ?? 0 // ✓ Z: TMVItem.m:532 NSUInteger existingRendererCount = [_childRenderers count].
        if existingRendererCount > childCount { // ✓ Z: TMVItem.m:535 if existingRendererCount > childCount.
            childRenderers!.removeSubrange(childCount..<existingRendererCount) // ✓ Z: TMVItem.m:537 removeObjectsInRange:NSMakeRange(childCount, existingRendererCount - childCount).
            existingRendererCount = childCount // ✓ Z: TMVItem.m:538 existingRendererCount = childCount.
        } // ✓ Z: TMVItem.m:535-539 closes supernumerary renderer removal.
        for index: Int in 0..<childCount { // ✓ Z: TMVItem.m:543 for i = 0; i < childCount; i++.
            let childItem: AnyObject = dataSource.treemapItemRendererChild(index, of: renderedItem) // ✓ Z: TMVItem.m:545 childItem = [_dataSource treeMapView:_view child:i ofItem:_item].
            if index < existingRendererCount { // ✓ Z: TMVItem.m:549 if i < existingRendererCount.
                childRenderers![index].refresh(with: childItem) // ✓ Z: TMVItem.m:551 refreshWithItem:childItem.
            } else { // ✓ Z: TMVItem.m:553 else.
                let childRenderer: TreemapItemRenderer = TreemapItemRenderer(dataSource: dataSource, delegate: delegate, renderedItem: childItem) // ✓ Z: TMVItem.m:555-558 initWithDataSource:delegate:renderedItem:treeMapView:.
                childRenderers!.append(childRenderer) // ✓ Z: TMVItem.m:560 [_childRenderers addObject:childRenderer].
            } // ✓ Z: TMVItem.m:549-563 closes recycle/create branch.
        } // ✓ Z: TMVItem.m:543-564 closes child renderer initialization loop.
    } // ✓ Z: TMVItem.m:565 closes createChildRenderers.
} // ✓ Z: TMVItem.m:567 closes TMVItem(Private) implementation.

private struct RowCalculation { // ✓ Swift-only: Swift tuple-like value replacing calculateRow rowHeight return plus childsUsed out pointer.
    let rowHeight: Double // ✓ Z: TMVItem.m:522 returns rowHeight.
    let childsUsed: Int // ✓ Z: TMVItem.m:451 NSUInteger *childsUsed out parameter.
} // ✓ Swift-only: closes Swift row calculation value.
