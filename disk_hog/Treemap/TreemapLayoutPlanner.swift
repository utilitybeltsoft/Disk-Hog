import Foundation

/// Diagnostic counters plus throttled progress reporting for TreemapLayoutPlanner.makePlan's
/// recursive descent. A reference type purely so appendEntry doesn't need to thread several more
/// inout parameters through every recursive call.
private final class TreemapLayoutDiagnosticStats {
    var maxDepth: Int = 0
    var recursedFolderCount: Int = 0
    var maxChildCountAtAnyFolder: Int = 0
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
        var entries: [TreemapLayoutEntry] = []
        var snapshots: [TreemapCushionSnapshot] = []
        let totalFolders: Int = rootItem.scanCounts(includeSelf: false).folders
        let stats: TreemapLayoutDiagnosticStats = TreemapLayoutDiagnosticStats(
            totalFolders: totalFolders,
            progress: progress
        )
        let descendStart: Date = Date()
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
            depth: 0,
            stats: stats,
            entries: &entries,
            snapshots: &snapshots
        )
        NSLog(
            "[TreemapRender] appendEntry descent took %.3fs, entries=%d, maxDepth=%d, recursedFolders=%d, maxChildCountAtAnyFolder=%d",
            Date().timeIntervalSince(descendStart), entries.count, stats.maxDepth, stats.recursedFolderCount, stats.maxChildCountAtAnyFolder
        )
        let indexStart: Date = Date()
        let plan: TreemapLayoutPlan = TreemapLayoutPlan(bounds: bounds, entries: entries, cushionSnapshots: snapshots)
        NSLog("[TreemapRender] TreemapLayoutPlan index build took %.3fs", Date().timeIntervalSince(indexStart))
        return plan
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
        depth: Int,
        stats: TreemapLayoutDiagnosticStats,
        entries: inout [TreemapLayoutEntry],
        snapshots: inout [TreemapCushionSnapshot]
    ) {
        stats.maxDepth = max(stats.maxDepth, depth)
        stats.entriesProcessed += 1
        stats.reportProgressIfDue()
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

        let children: [DiskItem] = children(
            of: item,
            rootItem: rootItem,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem
        )
        guard children.isEmpty == false else { return }
        stats.recursedFolderCount += 1
        stats.maxChildCountAtAnyFolder = max(stats.maxChildCountAtAnyFolder, children.count)
        let (layoutItems, explicitWeights): ([DiskItem], [Double]?) = cappedForLayout(
            children,
            rect: rect,
            usePhysicalSize: usePhysicalSize
        )
        let childRects: [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] = layoutChildren(
            layoutItems,
            weights: explicitWeights,
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
        for (child, childRect) in zip(layoutItems, childRects) {
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
                depth: depth + 1,
                stats: stats,
                entries: &entries,
                snapshots: &snapshots
            )
        }
    }

    /// A rect can only ever show as many distinguishable regions as it has pixels. Measured on a
    /// real scan: one folder with 636,120 direct children, contributing the overwhelming majority
    /// of a >300s render, almost all of it wasted on individually laying out children whose
    /// resulting rect could never be more than a fraction of a pixel. Children are already sorted
    /// by descending size (DiskItemBuilderOrdering), so once count wildly exceeds what the rect
    /// could show, keep the largest ones individually and fold the long, necessarily-invisible
    /// tail into one representative entry sized to their combined weight - same total area as
    /// laying them out individually would have covered, at a fraction of the cost.
    private static func cappedForLayout(
        _ children: [DiskItem],
        rect: TreemapLayoutRect,
        usePhysicalSize: Bool
    ) -> (items: [DiskItem], weights: [Double]?) {
        // Additive, not multiplicative: a x4 multiplier looked like a reasonable safety margin
        // for small rects, but for a large one (a dominant folder spanning a big share of the
        // canvas, e.g. ~100,000px) it inflates the cap right back up toward the original
        // problem size, barely capping anything in exactly the case this exists to fix.
        let pixelBudget: Int = max(Int(rect.width.rounded(.up)), 1) * max(Int(rect.height.rounded(.up)), 1)
        let cap: Int = max(pixelBudget + 256, 64)
        guard children.count > cap else {
            return (children, nil)
        }
        let kept: ArraySlice<DiskItem> = children.prefix(cap - 1)
        let tail: ArraySlice<DiskItem> = children[kept.endIndex...]
        guard let representative: DiskItem = tail.first else {
            return (children, nil)
        }
        let keptWeights: [Double] = kept.map { Double($0.sizeValue(usePhysicalSize: usePhysicalSize)) }
        let tailWeight: Double = tail.reduce(0) { $0 + Double($1.sizeValue(usePhysicalSize: usePhysicalSize)) }
        return (Array(kept) + [representative], keptWeights + [tailWeight])
    }

    private static func layoutChildren(
        _ children: [DiskItem],
        weights explicitWeights: [Double]? = nil,
        parentWeight: UInt64,
        rect: TreemapLayoutRect,
        usePhysicalSize: Bool
    ) -> [(rect: TreemapLayoutRect, unroundedRect: TreemapLayoutRect)] {
        let horizontal: Bool = rect.width >= rect.height
        let primaryLength: Double = horizontal ? rect.width : rect.height
        let secondaryLength: Double = horizontal ? rect.height : rect.width
        let aspectWidth: Double = secondaryLength > 0 ? primaryLength / secondaryLength : 1
        let weights: [Double] = explicitWeights ?? children.map { Double($0.sizeValue(usePhysicalSize: usePhysicalSize)) }
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
        // Zero-weight children each form their own singleton row (see above) and, since children
        // are sorted by descending size, any such rows are always trailing. The "give the exact
        // remainder to the last row" rule below exists purely to absorb floating-point rounding
        // error - it must land on the last row that actually carries weight, not the literal last
        // row, or a trailing zero-weight row inherits the entire leftover area instead of a
        // zero-size sliver.
        let lastNonZeroRowIndex: Int = rowHeights.lastIndex(where: { $0 > 0 }) ?? rowCounts.indices.last ?? 0
        for row: Int in rowCounts.indices {
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
