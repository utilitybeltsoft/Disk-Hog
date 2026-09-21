import Foundation

/// Diagnostic counters plus throttled progress reporting for TreemapLayoutPlanner.makePlan's
/// recursive descent. A reference type purely so appendEntry doesn't need to thread several more
/// inout parameters through every recursive call.
private nonisolated final class TreemapLayoutDiagnosticStats {
    var recursedFolderCount: Int = 0
    var entriesProcessed: Int = 0

    private let totalFolders: Int
    private let progress: (@Sendable (Double) -> Void)?
    private var lastReportedAt: Date = .distantPast

    init(totalFolders: Int, progress: (@Sendable (Double) -> Void)?) {
        self.totalFolders = totalFolders
        self.progress = progress
    }

    /// The reported fraction is folder-count-based (recursedFolderCount / totalFolders), not
    /// byte-weighted, since the measured bottleneck is folder-traversal work. But gating the
    /// clock check on recursedFolderCount alone left a blind spot: a single folder with tens of
    /// thousands of file children burns real time laying them out without incrementing that
    /// counter at all (files never recurse), so the clock could go unchecked for the entire
    /// burst. Gate on entriesProcessed instead - incremented for every item, file or folder -
    /// so the throttle is actually checked at a steady rate regardless of what kind of work is
    /// currently dominating. totalFolders is scoped to whatever root is currently rendering (via
    /// DiskItem.scanCounts), so the reported fraction is correct for both the initial full-disk
    /// render and every zoomed-in re-render.
    func reportProgressIfDue() {
        guard totalFolders > 0, let progress, entriesProcessed.isMultiple(of: 200) else {
            return
        }
        let now: Date = Date()
        guard now.timeIntervalSince(lastReportedAt) >= 0.1 else {
            return
        }
        lastReportedAt = now
        // Pruned/aggregated folders are never individually recursed into, so this count never
        // reaches totalFolders even at completion - cap it short and let the actual completion
        // signal (not this) be what visibly finishes the indicator.
        progress(min(Double(recursedFolderCount) / Double(totalFolders), 0.99))
    }
}

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
        otherSpaceItem: DiskItem? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> TreemapLayoutPlan {
        // The synchronous API deliberately ignores task cancellation.
        makePlanCheckingCancellation(
            rootItem: rootItem, bounds: bounds, usePhysicalSize: usePhysicalSize,
            colorTable: colorTable, showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace, freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem, progress: progress, checkCancellation: {}
        )
    }

    static func makePlanCheckingCancellation(
        rootItem: DiskItem,
        bounds: TreemapLayoutRect,
        usePhysicalSize: Bool,
        colorTable: TreemapPlanColorTable,
        showsFreeSpace: Bool = false,
        showsOtherSpace: Bool = false,
        freeSpaceItem: DiskItem? = nil,
        otherSpaceItem: DiskItem? = nil,
        progress: (@Sendable (Double) -> Void)? = nil,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) rethrows -> TreemapLayoutPlan {
        try checkCancellation()
        let geometryStart = TreemapPerformance.now
        var entries: [TreemapLayoutEntry] = []
        var snapshots: [TreemapCushionSnapshot] = []
        let totalFolders: Int = rootItem.scanCounts(includeSelf: false).folders
        let stats: TreemapLayoutDiagnosticStats = TreemapLayoutDiagnosticStats(
            totalFolders: totalFolders,
            progress: progress
        )
        try appendEntry(
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
            stats: stats,
            checkCancellation: checkCancellation,
            entries: &entries,
            snapshots: &snapshots
        )
        TreemapPerformance.phase("geometry", since: geometryStart, count: entries.count)
        try checkCancellation()
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
        stats: TreemapLayoutDiagnosticStats,
        checkCancellation: () throws -> Void,
        entries: inout [TreemapLayoutEntry],
        snapshots: inout [TreemapCushionSnapshot]
    ) rethrows {
        try checkCancellation()
        stats.entriesProcessed += 1
        stats.reportProgressIfDue()
        let isVisible: Bool = rect.width >= 1 && rect.height >= 1
        // item.path decodes a string from the packed buffer on every access (see DiskItem) -
        // skip it for entries too small to ever be shown, which given the pixel-budget cap
        // above is the large majority. TreemapLayoutPlan only indexes non-empty itemPaths
        // (matching how special items already opt out), and the one thing that index is for -
        // deepestRenderedAncestorEntry - walks upward from an external path looking for
        // whichever ancestor is indexed; it never needs this exact (invisible) entry's own
        // path, only some larger, visible ancestor's, which keeps its real path regardless.
        entries.append(TreemapLayoutEntry(
            item: item,
            itemPath: isVisible ? item.path : "",
            parentItem: parentItem,
            parentPath: parentPath,
            rect: rect,
            unroundedRect: unroundedRect,
            isSpecialItem: item.isSpecialItem
        ))
        guard isVisible else {
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
        // A folder's children can only ever partition its own unrounded (pre-pixel-snapped)
        // area. Once that area itself is under one real pixel wide or tall, no descendant can
        // legitimately claim a full pixel either, no matter how layout subdivides it further -
        // pixel-snapping alone can still round such a folder's own rect up to a nominal 1px,
        // which previously let recursion continue for many more levels than anything visible
        // could justify. Render it as a single aggregate region instead, same as a package.
        let canSubdivide: Bool = item.isFolder
            && item.isPackage == false
            && unroundedRect.width >= 1
            && unroundedRect.height >= 1
        guard canSubdivide else {
            let color: TreemapRawColor = colorTable.color(for: item)
            snapshots.append(TreemapCushionSnapshot(x: rect.x, y: rect.y, width: rect.width, height: rect.height, surface: surface, red: color.red, green: color.green, blue: color.blue))
            return
        }

        let folderWeight: UInt64 = weight(
            of: item,
            rootItem: rootItem,
            usePhysicalSize: usePhysicalSize,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem
        )
        let (layoutItems, explicitWeights): ([DiskItem], [Double]?) = try layoutChildrenAndWeights(
            for: item,
            rootItem: rootItem,
            rect: rect,
            usePhysicalSize: usePhysicalSize,
            folderWeight: folderWeight,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            checkCancellation: checkCancellation
        )
        guard layoutItems.isEmpty == false else { return }
        stats.recursedFolderCount += 1
        let childRects: [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] = try layoutChildren(
            layoutItems,
            weights: explicitWeights,
            parentWeight: folderWeight,
            rect: rect,
            usePhysicalSize: usePhysicalSize,
            checkCancellation: checkCancellation
        )
        // item.path decodes a string from the packed buffer on every access (see DiskItem) - hoist
        // it once rather than recomputing it, identically, on every one of this folder's
        // (potentially hundreds of thousands of) children below.
        let itemPath: String = item.path
        for (child, childRect) in zip(layoutItems, childRects) {
            try appendEntry(
                for: child,
                parentItem: item,
                parentPath: itemPath,
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
                stats: stats,
                checkCancellation: checkCancellation,
                entries: &entries,
                snapshots: &snapshots
            )
        }
    }

    /// A rect can only ever show as many distinguishable regions as it has pixels. Measured on a
    /// real scan: one folder with 636,120 direct children, contributing the overwhelming majority
    /// of a >300s render. Simply capping how many got individually laid out wasn't enough on its
    /// own: DiskItem.children unconditionally materializes every child as its own heap-allocated
    /// object, and summing an excluded tail's weight by iterating over it costs just as much as
    /// laying them out would have - both scale with the real child count regardless of the cap.
    ///
    /// Children are already sorted by descending size (DiskItemBuilderOrdering), so once the real
    /// count wildly exceeds the pixel budget, fetch only the kept ones directly by index - the
    /// tail is never materialized at all - and derive its combined weight by subtracting from the
    /// folder's already-known total weight instead of summing it.
    private static func layoutChildrenAndWeights(
        for item: DiskItem,
        rootItem: DiskItem,
        rect: TreemapLayoutRect,
        usePhysicalSize: Bool,
        folderWeight: UInt64,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?,
        checkCancellation: () throws -> Void
    ) rethrows -> (items: [DiskItem], weights: [Double]?) {
        let realChildCount: Int = item.childCount
        // Additive, not multiplicative: a x4 multiplier looked like a reasonable safety margin
        // for small rects, but for a large one (a dominant folder spanning a big share of the
        // canvas, e.g. ~100,000px) it inflates the cap right back up toward the original
        // problem size, barely capping anything in exactly the case this exists to fix.
        let pixelBudget: Int = max(Int(rect.width.rounded(.up)), 1) * max(Int(rect.height.rounded(.up)), 1)
        let cap: Int = max(pixelBudget + 256, 64)

        var items: [DiskItem]
        var weights: [Double]?
        if realChildCount > cap {
            var kept: [DiskItem] = []
            kept.reserveCapacity(cap - 1)
            var keptWeights: [Double] = []
            keptWeights.reserveCapacity(cap - 1)
            var keptWeightSum: UInt64 = 0
            for index: Int in 0..<(cap - 1) {
                if index.isMultiple(of: 256) { try checkCancellation() }
                let child: DiskItem = item.child(at: index)
                let childWeight: UInt64 = child.sizeValue(usePhysicalSize: usePhysicalSize)
                kept.append(child)
                keptWeights.append(Double(childWeight))
                keptWeightSum += childWeight
            }
            let representative: DiskItem = item.child(at: cap - 1)
            let tailWeight: Double = Double(folderWeight > keptWeightSum ? folderWeight - keptWeightSum : 0)
            items = kept + [representative]
            weights = keptWeights + [tailWeight]
        } else {
            items = []
            items.reserveCapacity(realChildCount)
            for index in 0..<realChildCount {
                if index.isMultiple(of: 256) { try checkCancellation() }
                items.append(item.child(at: index))
            }
            weights = nil
        }

        if item == rootItem {
            if showsOtherSpace, let otherSpaceItem {
                items.append(otherSpaceItem)
                weights?.append(Double(otherSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)))
            }
            if showsFreeSpace, let freeSpaceItem {
                items.append(freeSpaceItem)
                weights?.append(Double(freeSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)))
            }
        }
        return (items, weights)
    }

    private static func layoutChildren(
        _ children: [DiskItem],
        weights explicitWeights: [Double]? = nil,
        parentWeight: UInt64,
        rect: TreemapLayoutRect,
        usePhysicalSize: Bool,
        checkCancellation: () throws -> Void
    ) rethrows -> [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] {
        let horizontal: Bool = rect.width >= rect.height
        let primaryLength: Double = horizontal ? rect.width : rect.height
        let secondaryLength: Double = horizontal ? rect.height : rect.width
        let aspectWidth: Double = secondaryLength > 0 ? primaryLength / secondaryLength : 1
        let weights: [Double]
        if let explicitWeights {
            weights = explicitWeights
        } else {
            weights = try children.enumerated().map { index, child in
                if index.isMultiple(of: 256) { try checkCancellation() }
                return Double(child.sizeValue(usePhysicalSize: usePhysicalSize))
            }
        }
        let effectiveWeights: [Double] = parentWeight == 0
            ? Array(repeating: 1, count: children.count)
            : weights
        let totalWeight: Double = parentWeight == 0 ? Double(children.count) : Double(parentWeight)
        var rowCounts: [Int] = []
        var rowHeights: [Double] = []
        var childWidths: [Double] = []
        var start: Int = 0

        while start < children.count {
            try checkCancellation()
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
                if end.isMultiple(of: 256) { try checkCancellation() }
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
                if index.isMultiple(of: 256) { try checkCancellation() }
                childWidths.append(effectiveWeights[index] / rowWeight)
            }
            start += count
        }

        var result: [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] = []
        var childIndex: Int = 0
        var roundedSecondaryStart: Double = horizontal ? rect.y : rect.x
        var unroundedSecondaryStart: Double = roundedSecondaryStart
        let roundedSecondaryEnd: Double = horizontal ? rect.y + rect.height : rect.x + rect.width
        // Zero-weight children each form their own singleton row (see above) and, since children
        // are sorted by descending size, any such rows are always trailing. The "give the exact
        // remainder to the last row" rule below exists purely to absorb floating-point rounding
        // error - it must land on the last row that actually carries weight, not the literal last
        // row, or a trailing zero-weight row inherits the entire leftover area instead of a
        // zero-size sliver.
        let lastNonZeroRowIndex: Int = rowHeights.lastIndex(where: { $0 > 0 }) ?? rowCounts.indices.last ?? 0
        for row: Int in rowCounts.indices {
            try checkCancellation()
            let isLastWeightedRow: Bool = row == lastNonZeroRowIndex
            let unroundedSecondaryEnd: Double = isLastWeightedRow
                ? roundedSecondaryEnd
                : unroundedSecondaryStart + rowHeights[row] * secondaryLength
            let roundedSecondaryEndForRow: Double = isLastWeightedRow
                ? roundedSecondaryEnd
                : (roundedSecondaryStart + (rowHeights[row] * secondaryLength).rounded()).rounded()
            var roundedPrimaryStart: Double = horizontal ? rect.x : rect.y
            var unroundedPrimaryStart: Double = roundedPrimaryStart
            let roundedPrimaryEnd: Double = horizontal ? rect.x + rect.width : rect.y + rect.height
            for column: Int in 0..<rowCounts[row] {
                if column.isMultiple(of: 256) { try checkCancellation() }
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
