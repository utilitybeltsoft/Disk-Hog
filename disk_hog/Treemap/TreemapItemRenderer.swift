import AppKit

@MainActor
final class TreemapItemRenderer {
    private static let cushionScaleFactor: CGFloat = 0.9

    private weak var dataSource: TreemapDiskItemDataSource?
    private weak var parentRenderer: TreemapItemRenderer?
    private var renderedItem: DiskItem
    private var rectValue: NSRect
    private var unroundedRectValue: NSRect
    private var childRenderers: [TreemapItemRenderer]?
    private let cushionRenderer: TreemapCushionRenderer
    private var childRendererReconciliationCountValue: Int

    init(
        dataSource: TreemapDiskItemDataSource,
        renderedItem item: DiskItem,
        parentRenderer: TreemapItemRenderer? = nil
    ) {
        self.renderedItem = item
        self.dataSource = dataSource
        self.parentRenderer = parentRenderer
        self.rectValue = .zero
        self.unroundedRectValue = .zero
        self.cushionRenderer = TreemapCushionRenderer()
        self.childRendererReconciliationCountValue = 0
    }

    func refresh(with item: DiskItem) {
        renderedItem = item
        rectValue = .zero
        unroundedRectValue = .zero
        cushionRenderer.setRect(.zero)
        childRenderers = nil
    }

    func setCushionColor(_ color: NSColor) {
        cushionRenderer.setColor(color)
    }

    func calcLayout(_ proposedRect: NSRect) {
        unroundedRectValue = proposedRect
        let rect: NSRect = NSIntegralRect(proposedRect)
        if rectValue.equalTo(rect) {
            return
        }
        assert(rect.origin.x - CGFloat(Int(rect.origin.x)) == 0.0)
        assert(rect.origin.y - CGFloat(Int(rect.origin.y)) == 0.0)
        assert(rect.size.width - CGFloat(Int(rect.size.width)) == 0.0)
        assert(rect.size.height - CGFloat(Int(rect.size.height)) == 0.0)
        rectValue = rect
        cushionRenderer.setRect(rect)
        if rect.height < 1 || rect.width < 1 {
            return
        }
        if !isLeaf {
            layoutChilds()
        }
    }

    func drawCushion(in bitmap: NSBitmapImageRep, backingScaleFactor: CGFloat) {
        drawCushion(
            in: bitmap,
            backingScaleFactor: backingScaleFactor,
            parentCushion: nil,
            cushionHeightFactor: 0.5
        )
    }

    func cushionSnapshots() -> [TreemapCushionSnapshot] {
        var snapshots: [TreemapCushionSnapshot] = []
        appendCushionSnapshots(parentSurface: nil, heightFactor: 0.5, to: &snapshots)
        return snapshots
    }

    var isLeaf: Bool {
        guard let dataSource: TreemapDiskItemDataSource = dataSource else { return true }
        return !dataSource.isNode(renderedItem)
    }

    var item: DiskItem {
        renderedItem
    }

    var weight: UInt64 {
        dataSource?.weight(of: renderedItem) ?? 0
    }

    var rect: NSRect {
        rectValue
    }

    var unroundedRect: NSRect {
        unroundedRectValue
    }

    var parent: TreemapItemRenderer? {
        parentRenderer
    }

    var navigationRect: NSRect {
        rectValue.isEmpty ? unroundedRectValue : rectValue
    }

    var materializedRendererCount: Int {
        1 + (childRenderers ?? []).reduce(0) { count, childRenderer in
            count + childRenderer.materializedRendererCount
        }
    }

    var childRendererReconciliationCount: Int {
        childRendererReconciliationCountValue + (childRenderers ?? []).reduce(0) { count, childRenderer in
            count + childRenderer.childRendererReconciliationCount
        }
    }

    var childEnumerator: [TreemapItemRenderer] {
        assert(!isLeaf, "method 'childEnumerator' can only be invoked for nodes, not for leafs")
        ensureChildRenderers()
        return childRenderers ?? []
    }

    var childCount: Int {
        guard !isLeaf, let dataSource: TreemapDiskItemDataSource = dataSource else {
            return 0
        }
        return dataSource.numberOfChildren(of: renderedItem)
    }

    func appendLayoutDiagnostics(
        to rows: inout [[String: Any]],
        displayFolderPath: String,
        depth: Int,
        childIndex: Int,
        sequence: inout Int
    ) {
        let displayPath: String = Self.displayPath(
            displayFolderPath: displayFolderPath,
            displayName: renderedItem.displayName
        )
        rows.append([
            "recordType": "layout",
            "sequence": sequence,
            "depth": depth,
            "childIndex": childIndex,
            "path": renderedItem.path,
            "displayPath": displayPath,
            "displayName": renderedItem.displayName,
            "kindName": renderedItem.kindName ?? "",
            "isLeaf": isLeaf,
            "isNode": !isLeaf,
            "childCount": childCount,
            "weight": weight,
            "rectX": Double(rectValue.origin.x),
            "rectY": Double(rectValue.origin.y),
            "rectWidth": Double(rectValue.size.width),
            "rectHeight": Double(rectValue.size.height)
        ])
        sequence += 1

        let currentChildRenderers: [TreemapItemRenderer] = isLeaf ? [] : childEnumerator
        for (index, childRenderer) in currentChildRenderers.enumerated() {
            childRenderer.appendLayoutDiagnostics(
                to: &rows,
                displayFolderPath: displayPath,
                depth: depth + 1,
                childIndex: index,
                sequence: &sequence
            )
        }
    }

    private static func displayPath(displayFolderPath: String, displayName: String) -> String {
        if displayFolderPath.isEmpty {
            return displayName
        }

        return (displayFolderPath as NSString).appendingPathComponent(displayName)
    }

    func child(at index: Int) -> TreemapItemRenderer {
        childEnumerator[index]
    }

    func hitTest(_ point: NSPoint) -> TreemapItemRenderer? {
        if !rectValue.contains(point) {
            return nil
        }
        if isLeaf {
            return self
        }
        let currentChildRenderers: [TreemapItemRenderer] = childEnumerator
        for childRenderer: TreemapItemRenderer in currentChildRenderers {
            let hitChildRenderer: TreemapItemRenderer? = childRenderer.hitTest(point)
            if hitChildRenderer != nil {
                return hitChildRenderer
            }
        }
        if currentChildRenderers.isEmpty {
            return self
        }
        return nil
    }

    private func drawCushion(in bitmap: NSBitmapImageRep, backingScaleFactor: CGFloat, parentCushion: TreemapCushionRenderer?, cushionHeightFactor heightFactor: CGFloat) {
        if rectValue.height < 1 || rectValue.width < 1 {
            return
        }
        if let parentCushion: TreemapCushionRenderer = parentCushion {
            cushionRenderer.setSurface(parentCushion.surfaceValues())
            cushionRenderer.addRidgeByHeightFactor(heightFactor)
        }
        if isLeaf {
            dataSource?.prepareRenderer(self, for: renderedItem)
            cushionRenderer.renderCushion(in: bitmap, backingScaleFactor: backingScaleFactor)
        } else {
            for childRenderer: TreemapItemRenderer in childEnumerator {
                childRenderer.drawCushion(
                    in: bitmap,
                    backingScaleFactor: backingScaleFactor,
                    parentCushion: cushionRenderer,
                    cushionHeightFactor: heightFactor * Self.cushionScaleFactor
                )
            }
        }
    }

    private func appendCushionSnapshots(
        parentSurface: [CGFloat]?,
        heightFactor: CGFloat,
        to snapshots: inout [TreemapCushionSnapshot]
    ) {
        guard rectValue.height >= 1, rectValue.width >= 1 else { return }
        var surface: [CGFloat] = parentSurface ?? cushionRenderer.surfaceValues()
        if parentSurface != nil {
            let h4: CGFloat = 4 * heightFactor
            surface[2] += (h4 / rectValue.width) * (rectValue.maxX + rectValue.minX)
            surface[0] -= h4 / rectValue.width
            surface[3] += (h4 / rectValue.height) * (rectValue.maxY + rectValue.minY)
            surface[1] -= h4 / rectValue.height
        }
        if isLeaf {
            cushionRenderer.setSurface(surface)
            dataSource?.prepareRenderer(self, for: renderedItem)
            let color: NSColor = cushionRenderer.color
            snapshots.append(TreemapCushionSnapshot(
                x: Double(rectValue.minX), y: Double(rectValue.minY),
                width: Double(rectValue.width), height: Double(rectValue.height),
                surface: surface.map(Double.init),
                red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent)
            ))
        } else {
            for child: TreemapItemRenderer in childEnumerator {
                child.appendCushionSnapshots(
                    parentSurface: surface,
                    heightFactor: heightFactor * Self.cushionScaleFactor,
                    to: &snapshots
                )
            }
        }
    }

    private func layoutChilds() {
        let children: [TreemapItemRenderer] = childEnumerator
        var rows: [Double] = []
        var childsPerRow: [Int] = []
        var childWidths: [Double] = []
        let horizontalRows: Bool = arrangeChildsOnRows(
            children: children,
            layoutRect: rectValue,
            rows: &rows,
            childsPerRow: &childsPerRow,
            childWidths: &childWidths
        )
        let parentWidth: Int = Int(horizontalRows ? rectValue.width : rectValue.height)
        let parentHeight: Int = Int(horizontalRows ? rectValue.height : rectValue.width)
        let parentBottom: Int = Int(horizontalRows ? rectValue.maxY : rectValue.maxX)
        let parentRight: Int = Int(horizontalRows ? rectValue.maxX : rectValue.maxY)
        let parentLeft: Int = Int(horizontalRows ? rectValue.minX : rectValue.minY)
        let unroundedParentWidth: CGFloat = horizontalRows ? rectValue.width : rectValue.height
        let unroundedParentHeight: CGFloat = horizontalRows ? rectValue.height : rectValue.width
        let unroundedParentBottom: CGFloat = horizontalRows ? rectValue.maxY : rectValue.maxX
        let unroundedParentRight: CGFloat = horizontalRows ? rectValue.maxX : rectValue.maxY
        let unroundedParentLeft: CGFloat = horizontalRows ? rectValue.minX : rectValue.minY
        let unroundedRowStart: CGFloat = horizontalRows ? rectValue.minY : rectValue.minX
        var childIndex: Int = 0
        var top: Int = Int(horizontalRows ? rectValue.minY : rectValue.minX)
        var unroundedTop: CGFloat = unroundedRowStart
        for row: Int in 0..<rows.count {
            var bottom: Int = top + Int((rows[row] * Double(parentHeight)).rounded())
            if bottom > parentBottom || row == rows.count - 1 {
                bottom = parentBottom
            }
            let unroundedBottom: CGFloat = row == rows.count - 1
                ? unroundedParentBottom
                : unroundedTop + CGFloat(rows[row]) * unroundedParentHeight
            var left: Int = parentLeft
            var unroundedLeft: CGFloat = unroundedParentLeft
            for column: Int in 0..<childsPerRow[row] {
                var right: Int = left + Int((childWidths[childIndex] * Double(parentWidth)).rounded())
                if right > parentRight || column == childsPerRow[row] - 1 {
                    right = parentRight
                }
                let childRect: NSRect
                if horizontalRows {
                    childRect = NSRect(x: left, y: top, width: right - left, height: bottom - top)
                } else {
                    childRect = NSRect(x: top, y: left, width: bottom - top, height: right - left)
                }
                let unroundedRight: CGFloat = column == childsPerRow[row] - 1
                    ? unroundedParentRight
                    : unroundedLeft + CGFloat(childWidths[childIndex]) * unroundedParentWidth
                children[childIndex].unroundedRectValue = horizontalRows
                    ? NSRect(
                        x: unroundedLeft,
                        y: unroundedTop,
                        width: unroundedRight - unroundedLeft,
                        height: unroundedBottom - unroundedTop
                    )
                    : NSRect(
                        x: unroundedTop,
                        y: unroundedLeft,
                        width: unroundedBottom - unroundedTop,
                        height: unroundedRight - unroundedLeft
                    )
                children[childIndex].calcLayout(childRect)
                left = right
                unroundedLeft = unroundedRight
                childIndex += 1
            }
            top = bottom
            unroundedTop = unroundedBottom
        }
    }

    func layoutUnroundedChilds() {
        guard !isLeaf, unroundedRectValue.isEmpty == false else { return }
        let children: [TreemapItemRenderer] = childEnumerator
        var rows: [Double] = []
        var childsPerRow: [Int] = []
        var childWidths: [Double] = []
        let horizontalRows: Bool = arrangeChildsOnRows(
            children: children,
            layoutRect: unroundedRectValue,
            rows: &rows,
            childsPerRow: &childsPerRow,
            childWidths: &childWidths
        )
        let parentWidth: CGFloat = horizontalRows ? unroundedRectValue.width : unroundedRectValue.height
        let parentHeight: CGFloat = horizontalRows ? unroundedRectValue.height : unroundedRectValue.width
        let parentBottom: CGFloat = horizontalRows ? unroundedRectValue.maxY : unroundedRectValue.maxX
        let parentRight: CGFloat = horizontalRows ? unroundedRectValue.maxX : unroundedRectValue.maxY
        let parentLeft: CGFloat = horizontalRows ? unroundedRectValue.minX : unroundedRectValue.minY
        let parentRowStart: CGFloat = horizontalRows ? unroundedRectValue.minY : unroundedRectValue.minX
        var childIndex: Int = 0
        var top: CGFloat = parentRowStart
        for row: Int in 0..<rows.count {
            let bottom: CGFloat = row == rows.count - 1
                ? parentBottom
                : top + CGFloat(rows[row]) * parentHeight
            var left: CGFloat = parentLeft
            for column: Int in 0..<childsPerRow[row] {
                let right: CGFloat = column == childsPerRow[row] - 1
                    ? parentRight
                    : left + CGFloat(childWidths[childIndex]) * parentWidth
                children[childIndex].unroundedRectValue = horizontalRows
                    ? NSRect(x: left, y: top, width: right - left, height: bottom - top)
                    : NSRect(x: top, y: left, width: bottom - top, height: right - left)
                left = right
                childIndex += 1
            }
            top = bottom
        }
    }

    private func arrangeChildsOnRows(
        children: [TreemapItemRenderer],
        layoutRect: NSRect,
        rows: inout [Double],
        childsPerRow: inout [Int],
        childWidths: inout [Double]
    ) -> Bool {
        let childCount: Int = children.count
        if weight == 0 {
            rows.append(1)
            childsPerRow.append(childCount)
            let standardWidth: Double = 1.0 / Double(childCount)
            for _: Int in 0..<childCount {
                childWidths.append(standardWidth)
            }
            return true
        }
        let horizontal: Bool = layoutRect.size.width >= layoutRect.size.height
        var width: Double = 1
        if horizontal {
            if layoutRect.size.height > 0 {
                width = Double(layoutRect.size.width / layoutRect.size.height)
            }
        } else {
            if layoutRect.size.width > 0 {
                width = Double(layoutRect.size.height / layoutRect.size.width)
            }
        }
        var index: Int = 0
        while index < childCount {
            let result: RowCalculation = calculateRow(children: children, startChildIndex: index, rowWidth: width, childWidths: &childWidths)
            rows.append(result.rowHeight)
            childsPerRow.append(result.childsUsed)
            index += result.childsUsed
        }
        return horizontal
    }

    private func calculateRow(children: [TreemapItemRenderer], startChildIndex: Int, rowWidth: Double, childWidths: inout [Double]) -> RowCalculation {
        let minProportion: Double = 0.4
        let mySize: Double = Double(weight)
        var index: Int = startChildIndex
        var sizeUsed: Double = 0
        var rowHeight: Double = 0
        let childCount: Int = children.count
        while index < childCount {
            let childSize: Double = Double(children[index].weight)
            if childSize == 0 {
                if index == startChildIndex {
                    // Do not rely on size ordering for progress. A zero-weight
                    // child has no drawable area, but still needs a finite row.
                    childWidths.append(1)
                    return RowCalculation(rowHeight: 0, childsUsed: 1)
                }
                break
            }
            sizeUsed += childSize
            let virtualRowHeight: Double = sizeUsed / mySize
            assert(virtualRowHeight > 0 && virtualRowHeight <= 1)
            let childWidth: Double = childSize / mySize * rowWidth / virtualRowHeight
            if childWidth / virtualRowHeight < minProportion {
                assert(index > startChildIndex)
                break
            }
            rowHeight = virtualRowHeight
            index += 1
        }
        assert(index > startChildIndex)
        while index < childCount && children[index].weight == 0 {
            index += 1
        }
        let childsUsed: Int = index - startChildIndex
        let rowSize: Double = mySize * rowHeight
        for offset: Int in 0..<childsUsed {
            let childSize: Double = Double(children[startChildIndex + offset].weight)
            let childWidth: Double = childSize / rowSize
            childWidths.append(childWidth)
        }
        return RowCalculation(rowHeight: rowHeight, childsUsed: childsUsed)
    }

    private func ensureChildRenderers() {
        childRendererReconciliationCountValue += 1
        guard let dataSource: TreemapDiskItemDataSource = dataSource else { return }
        let childCount: Int = dataSource.numberOfChildren(of: renderedItem)
        if childRenderers == nil {
            childRenderers = []
        }
        var existingRendererCount: Int = childRenderers?.count ?? 0
        if existingRendererCount > childCount {
            childRenderers!.removeSubrange(childCount..<existingRendererCount)
            existingRendererCount = childCount
        }
        for index: Int in 0..<childCount {
            let childItem: DiskItem = dataSource.child(index, of: renderedItem)
            if index < existingRendererCount {
                if childRenderers![index].item != childItem {
                    childRenderers![index].refresh(with: childItem)
                }
            } else {
                let childRenderer: TreemapItemRenderer = TreemapItemRenderer(
                    dataSource: dataSource,
                    renderedItem: childItem,
                    parentRenderer: self
                )
                childRenderers!.append(childRenderer)
            }
        }
    }
}

private struct RowCalculation {
    let rowHeight: Double
    let childsUsed: Int
}
