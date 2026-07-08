import AppKit

nonisolated final class TreemapItemRenderer: @unchecked Sendable {
    private static let cushionScaleFactor: CGFloat = 0.9

    private weak var dataSource: TreemapDiskItemDataSource?
    private var renderedItem: DiskItem
    private var rectValue: NSRect
    private var childRenderers: [TreemapItemRenderer]?
    private let cushionRenderer: TreemapCushionRenderer

    init(dataSource: TreemapDiskItemDataSource, renderedItem item: DiskItem) {
        self.renderedItem = item
        self.dataSource = dataSource
        self.rectValue = .zero
        self.cushionRenderer = TreemapCushionRenderer()
        if !isLeaf {
            createChildRenderers()
        }
    }

    func refresh(with item: DiskItem) {
        renderedItem = item
        rectValue = .zero
        cushionRenderer.setRect(.zero)
        if !isLeaf {
            createChildRenderers()
        } else {
            childRenderers = nil
        }
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

    func drawCushion(in bitmap: NSBitmapImageRep) {
        drawCushion(in: bitmap, parentCushion: nil, cushionHeightFactor: 0.5)
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

    var childEnumerator: [TreemapItemRenderer] {
        assert(childRenderers != nil, "method 'childEnumerator' can only be invoked for nodes, not for leafs")
        return childRenderers ?? []
    }

    var childCount: Int {
        childRenderers?.count ?? 0
    }

    func appendRendererIndex(to index: inout [ObjectIdentifier: TreemapItemRenderer]) {
        index[ObjectIdentifier(renderedItem)] = self
        guard let childRenderers: [TreemapItemRenderer] = childRenderers else {
            return
        }

        for childRenderer: TreemapItemRenderer in childRenderers {
            childRenderer.appendRendererIndex(to: &index)
        }
    }

    func appendLayoutDiagnostics(to rows: inout [[String: Any]], depth: Int, childIndex: Int, sequence: inout Int) {
        rows.append([
            "recordType": "layout",
            "sequence": sequence,
            "depth": depth,
            "childIndex": childIndex,
            "path": renderedItem.path,
            "displayPath": renderedItem.displayPath,
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

        for (index, childRenderer) in (childRenderers ?? []).enumerated() {
            childRenderer.appendLayoutDiagnostics(
                to: &rows,
                depth: depth + 1,
                childIndex: index,
                sequence: &sequence
            )
        }
    }

    func child(at index: Int) -> TreemapItemRenderer {
        childRenderers![index]
    }

    func hitTest(_ point: NSPoint) -> TreemapItemRenderer? {
        if !rectValue.contains(point) {
            return nil
        }
        if isLeaf {
            return self
        }
        for childRenderer: TreemapItemRenderer in childRenderers ?? [] {
            let hitChildRenderer: TreemapItemRenderer? = childRenderer.hitTest(point)
            if hitChildRenderer != nil {
                return hitChildRenderer
            }
        }
        return nil
    }

    private func drawCushion(in bitmap: NSBitmapImageRep, parentCushion: TreemapCushionRenderer?, cushionHeightFactor heightFactor: CGFloat) {
        if rectValue.height < 1 || rectValue.width < 1 {
            return
        }
        if let parentCushion: TreemapCushionRenderer = parentCushion {
            cushionRenderer.setSurface(parentCushion.surfaceValues())
            cushionRenderer.addRidgeByHeightFactor(heightFactor)
        }
        if isLeaf {
            dataSource?.prepareRenderer(self, for: renderedItem)
            cushionRenderer.renderCushion(in: bitmap)
        } else {
            for childRenderer: TreemapItemRenderer in childRenderers ?? [] {
                childRenderer.drawCushion(in: bitmap, parentCushion: cushionRenderer, cushionHeightFactor: heightFactor * Self.cushionScaleFactor)
            }
        }
    }

    private func layoutChilds() {
        var rows: [Double] = []
        var childsPerRow: [Int] = []
        var childWidths: [Double] = []
        let horizontalRows: Bool = arrangeChildsOnRows(rows: &rows, childsPerRow: &childsPerRow, childWidths: &childWidths)
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
                childRenderers![childIndex].calcLayout(childRect)
                left = right
                childIndex += 1
            }
            top = bottom
        }
    }

    private func arrangeChildsOnRows(rows: inout [Double], childsPerRow: inout [Int], childWidths: inout [Double]) -> Bool {
        let childCount: Int = childRenderers?.count ?? 0
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
            let result: RowCalculation = calculateRow(startChildIndex: index, rowWidth: width, childWidths: &childWidths)
            rows.append(result.rowHeight)
            childsPerRow.append(result.childsUsed)
            index += result.childsUsed
        }
        return horizontal
    }

    private func calculateRow(startChildIndex: Int, rowWidth: Double, childWidths: inout [Double]) -> RowCalculation {
        let minProportion: Double = 0.4
        let mySize: Double = Double(weight)
        var index: Int = startChildIndex
        var sizeUsed: Double = 0
        var rowHeight: Double = 0
        let childCount: Int = childRenderers?.count ?? 0
        while index < childCount {
            let childSize: Double = Double(childRenderers![index].weight)
            if childSize == 0 {
                assert(index > startChildIndex)
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
        while index < childCount && childRenderers![index].weight == 0 {
            index += 1
        }
        let childsUsed: Int = index - startChildIndex
        let rowSize: Double = mySize * rowHeight
        for offset: Int in 0..<childsUsed {
            let childSize: Double = Double(childRenderers![startChildIndex + offset].weight)
            let childWidth: Double = childSize / rowSize
            childWidths.append(childWidth)
        }
        return RowCalculation(rowHeight: rowHeight, childsUsed: childsUsed)
    }

    private func createChildRenderers() {
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
                childRenderers![index].refresh(with: childItem)
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
