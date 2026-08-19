import Foundation

/// Produces treemap geometry without AppKit renderer objects. The planner is
/// deliberately value-only so callers can run it in a detached task.
nonisolated enum TreemapLayoutPlanner {
    static func makePlan(
        rootItem: DiskItem,
        bounds: TreemapLayoutRect,
        usePhysicalSize: Bool,
        colorTable: TreemapPlanColorTable,
        showsFreeSpace: Bool = false,
        showsOtherSpace: Bool = false,
        freeSpaceItem: DiskItem? = nil,
        otherSpaceItem: DiskItem? = nil
    ) -> TreemapLayoutPlan {
        var entries: [TreemapLayoutEntry] = []
        var snapshots: [TreemapCushionSnapshot] = []
        appendEntry(
            for: rootItem,
            parentItem: nil,
            parentPath: nil,
            rect: integral(bounds),
            unroundedRect: bounds,
            usePhysicalSize: usePhysicalSize,
            colorTable: colorTable,
            rootItem: rootItem,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            parentSurface: nil,
            heightFactor: 0.5,
            entries: &entries,
            snapshots: &snapshots
        )
        return TreemapLayoutPlan(bounds: bounds, entries: entries, cushionSnapshots: snapshots)
    }

    private static func appendEntry(
        for item: DiskItem,
        parentItem: DiskItem?,
        parentPath: String?,
        rect: TreemapLayoutRect,
        unroundedRect: TreemapLayoutRect,
        usePhysicalSize: Bool,
        colorTable: TreemapPlanColorTable,
        rootItem: DiskItem,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?,
        parentSurface: [Double]?,
        heightFactor: Double,
        entries: inout [TreemapLayoutEntry],
        snapshots: inout [TreemapCushionSnapshot]
    ) {
        entries.append(TreemapLayoutEntry(
            item: item,
            itemPath: item.path,
            parentItem: parentItem,
            parentPath: parentPath,
            rect: rect,
            unroundedRect: unroundedRect,
            isSpecialItem: item.isSpecialItem
        ))
        guard rect.width >= 1, rect.height >= 1 else {
            return
        }

        var surface: [Double] = parentSurface ?? [0, 0, 0, 0]
        if parentSurface != nil {
            let h4: Double = 4 * heightFactor
            surface[2] += (h4 / rect.width) * (rect.x + rect.x + rect.width)
            surface[0] -= h4 / rect.width
            surface[3] += (h4 / rect.height) * (rect.y + rect.y + rect.height)
            surface[1] -= h4 / rect.height
        }
        guard item.isFolder, item.isPackage == false else {
            let color: TreemapRawColor = colorTable.color(for: item)
            snapshots.append(TreemapCushionSnapshot(x: rect.x, y: rect.y, width: rect.width, height: rect.height, surface: surface, red: color.red, green: color.green, blue: color.blue))
            return
        }

        let children: [DiskItem] = children(
            of: item,
            rootItem: rootItem,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem
        )
        guard children.isEmpty == false else { return }
        let childRects: [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] = layoutChildren(
            children,
            parentWeight: weight(
                of: item,
                rootItem: rootItem,
                usePhysicalSize: usePhysicalSize,
                showsFreeSpace: showsFreeSpace,
                showsOtherSpace: showsOtherSpace,
                freeSpaceItem: freeSpaceItem,
                otherSpaceItem: otherSpaceItem
            ),
            rect: rect,
            usePhysicalSize: usePhysicalSize
        )
        for (child, childRect) in zip(children, childRects) {
            appendEntry(
                for: child,
                parentItem: item,
                parentPath: item.path,
                rect: childRect.rect,
                unroundedRect: childRect.unroundedRect,
                usePhysicalSize: usePhysicalSize,
                colorTable: colorTable,
                rootItem: rootItem,
                showsFreeSpace: showsFreeSpace,
                showsOtherSpace: showsOtherSpace,
                freeSpaceItem: freeSpaceItem,
                otherSpaceItem: otherSpaceItem,
                parentSurface: surface,
                heightFactor: heightFactor * 0.9,
                entries: &entries,
                snapshots: &snapshots
            )
        }
    }

    private static func layoutChildren(
        _ children: [DiskItem],
        parentWeight: UInt64,
        rect: TreemapLayoutRect,
        usePhysicalSize: Bool
    ) -> [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] {
        let horizontal: Bool = rect.width >= rect.height
        let primaryLength: Double = horizontal ? rect.width : rect.height
        let secondaryLength: Double = horizontal ? rect.height : rect.width
        let aspectWidth: Double = secondaryLength > 0 ? primaryLength / secondaryLength : 1
        let weights: [Double] = children.map { Double($0.sizeValue(usePhysicalSize: usePhysicalSize)) }
        let effectiveWeights: [Double] = parentWeight == 0
            ? Array(repeating: 1, count: children.count)
            : weights
        let totalWeight: Double = parentWeight == 0 ? Double(children.count) : Double(parentWeight)
        var rowCounts: [Int] = []
        var rowHeights: [Double] = []
        var childWidths: [Double] = []
        var start: Int = 0

        while start < children.count {
            if effectiveWeights[start] == 0 {
                rowCounts.append(1)
                rowHeights.append(0)
                childWidths.append(1)
                start += 1
                continue
            }

            var end: Int = start
            var usedWeight: Double = 0
            var rowHeight: Double = 0
            while end < children.count, effectiveWeights[end] > 0 {
                usedWeight += effectiveWeights[end]
                let proposedHeight: Double = usedWeight / totalWeight
                let proposedWidth: Double = effectiveWeights[end] / totalWeight * aspectWidth / proposedHeight
                if end > start, proposedWidth / proposedHeight < 0.4 {
                    usedWeight -= effectiveWeights[end]
                    break
                }
                rowHeight = proposedHeight
                end += 1
            }
            let count: Int = max(end - start, 1)
            rowCounts.append(count)
            rowHeights.append(rowHeight)
            let rowWeight: Double = max(usedWeight, 1)
            for index: Int in start..<(start + count) {
                childWidths.append(effectiveWeights[index] / rowWeight)
            }
            start += count
        }

        var result: [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] = []
        var childIndex: Int = 0
        var roundedSecondaryStart: Double = horizontal ? rect.y : rect.x
        var unroundedSecondaryStart: Double = roundedSecondaryStart
        let roundedSecondaryEnd: Double = horizontal ? rect.y + rect.height : rect.x + rect.width
        for row: Int in rowCounts.indices {
            let unroundedSecondaryEnd: Double = row == rowCounts.indices.last
                ? roundedSecondaryEnd
                : unroundedSecondaryStart + rowHeights[row] * secondaryLength
            let roundedSecondaryEndForRow: Double = row == rowCounts.indices.last
                ? roundedSecondaryEnd
                : (roundedSecondaryStart + (rowHeights[row] * secondaryLength).rounded()).rounded()
            var roundedPrimaryStart: Double = horizontal ? rect.x : rect.y
            var unroundedPrimaryStart: Double = roundedPrimaryStart
            let roundedPrimaryEnd: Double = horizontal ? rect.x + rect.width : rect.y + rect.height
            for column: Int in 0..<rowCounts[row] {
                let unroundedPrimaryEnd: Double = column == rowCounts[row] - 1
                    ? roundedPrimaryEnd
                    : unroundedPrimaryStart + childWidths[childIndex] * primaryLength
                let roundedPrimaryEndForChild: Double = column == rowCounts[row] - 1
                    ? roundedPrimaryEnd
                    : (roundedPrimaryStart + (childWidths[childIndex] * primaryLength).rounded()).rounded()
                let unroundedRect: TreemapLayoutRect = horizontal
                    ? TreemapLayoutRect(x: unroundedPrimaryStart, y: unroundedSecondaryStart, width: unroundedPrimaryEnd - unroundedPrimaryStart, height: unroundedSecondaryEnd - unroundedSecondaryStart)
                    : TreemapLayoutRect(x: unroundedSecondaryStart, y: unroundedPrimaryStart, width: unroundedSecondaryEnd - unroundedSecondaryStart, height: unroundedPrimaryEnd - unroundedPrimaryStart)
                let roundedRect: TreemapLayoutRect = horizontal
                    ? TreemapLayoutRect(x: roundedPrimaryStart, y: roundedSecondaryStart, width: roundedPrimaryEndForChild - roundedPrimaryStart, height: roundedSecondaryEndForRow - roundedSecondaryStart)
                    : TreemapLayoutRect(x: roundedSecondaryStart, y: roundedPrimaryStart, width: roundedSecondaryEndForRow - roundedSecondaryStart, height: roundedPrimaryEndForChild - roundedPrimaryStart)
                result.append((roundedRect, unroundedRect))
                roundedPrimaryStart = roundedPrimaryEndForChild
                unroundedPrimaryStart = unroundedPrimaryEnd
                childIndex += 1
            }
            roundedSecondaryStart = roundedSecondaryEndForRow
            unroundedSecondaryStart = unroundedSecondaryEnd
        }
        return result
    }

    private static func children(
        of item: DiskItem,
        rootItem: DiskItem,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?
    ) -> [DiskItem] {
        var children: [DiskItem] = item.children
        if item == rootItem {
            if showsOtherSpace, let otherSpaceItem {
                children.append(otherSpaceItem)
            }
            if showsFreeSpace, let freeSpaceItem {
                children.append(freeSpaceItem)
            }
        }
        return children
    }

    private static func weight(
        of item: DiskItem,
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?
    ) -> UInt64 {
        var size: UInt64 = item.sizeValue(usePhysicalSize: usePhysicalSize)
        if item == rootItem {
            if showsFreeSpace, let freeSpaceItem {
                size += freeSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)
            }
            if showsOtherSpace, let otherSpaceItem {
                size += otherSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)
            }
        }
        return size
    }

    private static func integral(_ rect: TreemapLayoutRect) -> TreemapLayoutRect {
        TreemapLayoutRect(
            x: rect.x.rounded(),
            y: rect.y.rounded(),
            width: rect.width.rounded(),
            height: rect.height.rounded()
        )
    }
}
