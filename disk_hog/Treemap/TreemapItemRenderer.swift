import AppKit

@MainActor
final class TreemapItemRenderer {
    private static let cushionScaleFactor: CGFloat = 0.9

    private weak var dataSource: TreemapDiskItemDataSource?
    private var renderedItem: DiskItem
    private var rectValue: NSRect
    private var childRenderers: [TreemapItemRenderer]?
    private let cushionRenderer: TreemapCushionRenderer
    private var childRendererReconciliationCountValue: Int

    init(dataSource: TreemapDiskItemDataSource, renderedItem item: DiskItem) {
        self.renderedItem = item
        self.dataSource = dataSource
        self.rectValue = .zero
        self.cushionRenderer = TreemapCushionRenderer()
        self.childRendererReconciliationCountValue = 0
    }

    func refresh(with item: DiskItem) {
        renderedItem = item
        rectValue = .zero
        cushionRenderer.setRect(.zero)
        childRenderers = nil
    }

    func setCushionColor(_ color: NSColor) {
        cushionRenderer.setColor(color)
    }

    func calcLayout(_ proposedRect: NSRect) {
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

    private func layoutChilds() {
        let children: [TreemapItemRenderer] = childEnumerator
        var rows: [Double] = []
        var childsPerRow: [Int] = []
        var childWidths: [Double] = []
        let horizontalRows: Bool = arrangeChildsOnRows(children: children, rows: &rows, childsPerRow: &childsPerRow, childWidths: &childWidths)
        let parentWidth: Int = Int(horizontalRows ? rectValue.width : rectValue.height)
        let parentHeight: Int = Int(horizontalRows ? rectValue.height : rectValue.width)
        let parentBottom: Int = Int(horizontalRows ? rectValue.maxY : rectValue.maxX)
        let parentRight: Int = Int(horizontalRows ? rectValue.maxX : rectValue.maxY)
        let parentLeft: Int = Int(horizontalRows ? rectValue.minX : rectValue.minY)
        var childIndex: Int = 0
        var top: Int = Int(horizontalRows ? rectValue.minY : rectValue.minX)
        for row: Int in 0..<rows.count {
            var bottom: Int = top + Int((rows[row] * Double(parentHeight)).rounded())
            if bottom > parentBottom || row == rows.count - 1 {
                bottom = parentBottom
            }
            var left: Int = parentLeft
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
                children[childIndex].calcLayout(childRect)
                left = right
                childIndex += 1
            }
            top = bottom
        }
    }

    private func arrangeChildsOnRows(children: [TreemapItemRenderer], rows: inout [Double], childsPerRow: inout [Int], childWidths: inout [Double]) -> Bool {
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
        let horizontal: Bool = rectValue.size.width >= rectValue.size.height
        var width: Double = 1
        if horizontal {
            if rectValue.size.height > 0 {
                width = Double(rectValue.size.width / rectValue.size.height)
            }
        } else {
            if rectValue.size.width > 0 {
                width = Double(rectValue.size.height / rectValue.size.width)
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
                let childRenderer: TreemapItemRenderer = TreemapItemRenderer(dataSource: dataSource, renderedItem: childItem)
                childRenderers!.append(childRenderer)
            }
        }
    }
}

private struct RowCalculation {
    let rowHeight: Double
    let childsUsed: Int
}
