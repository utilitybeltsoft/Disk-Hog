import Foundation

/// A platform-neutral rectangle used while preparing a treemap off the main
/// actor. AppKit conversion happens only when a completed plan is installed.
nonisolated struct TreemapLayoutRect: Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let zero: TreemapLayoutRect = TreemapLayoutRect(x: 0, y: 0, width: 0, height: 0)

    var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    var area: Double {
        max(width, 0) * max(height, 0)
    }

    var midX: Double {
        x + width / 2
    }

    var midY: Double {
        y + height / 2
    }

    func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x && pointX < x + width && pointY >= y && pointY < y + height
    }
}

/// Geometry and identity for one treemap item. `unroundedRect` retains the
/// fractional allocation used to identify items too small to paint.
nonisolated struct TreemapLayoutEntry: Hashable, Sendable {
    let item: DiskItem
    let itemPath: String
    let parentItem: DiskItem?
    let parentPath: String?
    let rect: TreemapLayoutRect
    let unroundedRect: TreemapLayoutRect
    let isSpecialItem: Bool

    var navigationRect: TreemapLayoutRect {
        rect.isEmpty ? unroundedRect : rect
    }
}

/// Immutable output of the off-main treemap preparation pipeline.
///
/// It contains no AppKit objects and can safely cross actors as a single unit.
nonisolated struct TreemapLayoutPlan: Sendable {
    private static let directSiblingNavigationLimit: Int = 256

    let bounds: TreemapLayoutRect
    let entries: [TreemapLayoutEntry]
    let cushionSnapshots: [TreemapCushionSnapshot]

    private let entryIndexByPath: [String: Int]
    private let entryIndexByItem: [DiskItem: Int]
    private let childEntryIndicesByParent: [DiskItem: [Int]]
    private let hitIndex: TreemapLayoutHitIndex?
    private let navigationIndex: TreemapLayoutNavigationIndex?

    init(
        bounds: TreemapLayoutRect,
        entries: [TreemapLayoutEntry],
        cushionSnapshots: [TreemapCushionSnapshot]
    ) {
        self.bounds = bounds
        self.entries = entries
        self.cushionSnapshots = cushionSnapshots
        let identityStart = TreemapPerformance.now
        var entryIndexByPath: [String: Int] = [:]
        var entryIndexByItem: [DiskItem: Int] = [:]
        var childEntryIndicesByParent: [DiskItem: [Int]] = [:]
        var navigableIndices: [Int] = []
        for (index, entry) in entries.enumerated() {
            if entry.itemPath.isEmpty == false {
                entryIndexByPath[entry.itemPath] = index
            }
            entryIndexByItem[entry.item] = index
            if let parentItem: DiskItem = entry.parentItem {
                childEntryIndicesByParent[parentItem, default: []].append(index)
            }
            if entry.isSpecialItem == false && entry.navigationRect.isEmpty == false {
                navigableIndices.append(index)
            }
        }
        self.entryIndexByPath = entryIndexByPath
        self.entryIndexByItem = entryIndexByItem
        self.childEntryIndicesByParent = childEntryIndicesByParent
        TreemapPerformance.phase("identity-index", since: identityStart, count: entries.count)
        let hitStart = TreemapPerformance.now
        self.hitIndex = TreemapLayoutHitIndex(
            entries: entries,
            candidateIndices: navigableIndices,
            bounds: bounds
        )
        TreemapPerformance.phase("hit-index", since: hitStart, count: navigableIndices.count)
        let navigationStart = TreemapPerformance.now
        self.navigationIndex = TreemapLayoutNavigationIndex(
            entries: entries,
            candidateIndices: navigableIndices,
            bounds: bounds
        )
        TreemapPerformance.phase("navigation-index", since: navigationStart, count: navigableIndices.count)
    }

    func entry(forPath path: String) -> TreemapLayoutEntry? {
        guard let index: Int = entryIndexByPath[path] else {
            return nil
        }
        return entries[index]
    }

    func entry(for item: DiskItem) -> TreemapLayoutEntry? {
        guard let index: Int = entryIndexByItem[item] else {
            return nil
        }
        return entries[index]
    }

    /// Root-to-immediate-parent chain for `entry`, resolved via the plan's
    /// item index rather than re-walking the tree from the root.
    func ancestorChain(for entry: TreemapLayoutEntry) -> [DiskItem] {
        var chain: [DiskItem] = []
        var currentParent: DiskItem? = entry.parentItem
        while let parent: DiskItem = currentParent {
            chain.append(parent)
            currentParent = entryIndexByItem[parent].map { entries[$0] }?.parentItem
        }
        return chain.reversed()
    }

    /// `entry(for:)`, degrading to the nearest rendered ancestor when `item`
    /// itself isn't indexed - e.g. a folder's child-count cap can leave items
    /// past the cap with no entry of their own at all.
    func entryOrNearestAncestor(for item: DiskItem) -> TreemapLayoutEntry? {
        entry(for: item) ?? deepestRenderedAncestorEntry(containingPath: item.path)
    }

    func deepestRenderedAncestorEntry(containingPath path: String) -> TreemapLayoutEntry? {
        var candidatePath: String = path
        while candidatePath.isEmpty == false {
            if let index: Int = entryIndexByPath[candidatePath] {
                return entries[index]
            }
            let parentPath: String = (candidatePath as NSString).deletingLastPathComponent
            guard parentPath != candidatePath else {
                break
            }
            candidatePath = parentPath
        }
        return nil
    }

    /// Resolves overlaps by choosing the smallest painted rectangle, which is
    /// the deepest visible descendant at the pointer location.
    func hitEntry(x: Double, y: Double) -> TreemapLayoutEntry? {
        guard let hitIndex: TreemapLayoutHitIndex,
              let index: Int = hitIndex.hitEntryIndex(entries: entries, x: x, y: y) else {
            return nil
        }
        return entries[index]
    }

    func nearestEntry(from item: DiskItem, direction: TreemapNavigationDirection) -> TreemapLayoutEntry? {
        guard let anchorEntry: TreemapLayoutEntry = entryOrNearestAncestor(for: item),
              let selectedIndex: Int = entryIndexByItem[anchorEntry.item] else {
            return nil
        }
        let selectedEntry: TreemapLayoutEntry = entries[selectedIndex]
        let selectedRect: TreemapLayoutRect = selectedEntry.navigationRect
        guard selectedRect.isEmpty == false else {
            return nil
        }

        if let parentItem: DiskItem = selectedEntry.parentItem,
           let siblingIndices: [Int] = childEntryIndicesByParent[parentItem],
           siblingIndices.count <= Self.directSiblingNavigationLimit,
           let siblingCandidate: Int = nearestEntryIndex(
            among: siblingIndices,
            excluding: selectedIndex,
            selectedRect: selectedRect,
            direction: direction
           ) {
            return entries[siblingCandidate]
        }

        guard let candidateIndex: Int = navigationIndex?.nearestEntryIndex(
            from: selectedIndex,
            selectedRect: selectedRect,
            direction: direction
        ) else {
            return nil
        }
        return entries[candidateIndex]
    }

    private func nearestEntryIndex(
        among candidateIndices: [Int],
        excluding selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Int? {
        candidateIndices
            .lazy
            .filter { $0 != selectedIndex && entries[$0].isSpecialItem == false }
            .compactMap { index -> (index: Int, score: Double)? in
                let rect: TreemapLayoutRect = entries[index].navigationRect
                guard rect.isEmpty == false else { return nil }
                guard let score: Double = Self.directionalScore(
                    from: selectedRect,
                    to: rect,
                    direction: direction
                ) else {
                    return nil
                }
                return (index, score)
            }
            .min { $0.score < $1.score }?
            .index
    }

    fileprivate static func directionalScore(
        from selectedRect: TreemapLayoutRect,
        to candidateRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Double? {
        let primaryDistance: Double
        let crossDistance: Double
        switch direction {
        case .left:
            primaryDistance = selectedRect.midX - candidateRect.midX
            crossDistance = abs(selectedRect.midY - candidateRect.midY)
        case .right:
            primaryDistance = candidateRect.midX - selectedRect.midX
            crossDistance = abs(selectedRect.midY - candidateRect.midY)
        case .up:
            primaryDistance = selectedRect.midY - candidateRect.midY
            crossDistance = abs(selectedRect.midX - candidateRect.midX)
        case .down:
            primaryDistance = candidateRect.midY - selectedRect.midY
            crossDistance = abs(selectedRect.midX - candidateRect.midX)
        }
        guard primaryDistance > 0 else {
            return nil
        }
        return primaryDistance + crossDistance * 0.25
    }
}

private nonisolated struct TreemapLayoutHitIndex: Sendable {
    private let bounds: TreemapLayoutRect
    private let gridSide: Int
    private let entryIndicesByCell: [Int: [Int]]

    init?(entries: [TreemapLayoutEntry], candidateIndices: [Int], bounds: TreemapLayoutRect) {
        guard bounds.isEmpty == false, candidateIndices.isEmpty == false else {
            return nil
        }

        self.bounds = bounds
        gridSide = min(256, max(16, Int(Double(candidateIndices.count).squareRoot().rounded(.up))))
        var entryIndicesByCell: [Int: [Int]] = [:]
        entryIndicesByCell.reserveCapacity(min(candidateIndices.count, gridSide * gridSide))

        for index: Int in candidateIndices {
            let rect: TreemapLayoutRect = entries[index].rect
            guard rect.isEmpty == false else { continue }
            let startColumn: Int = Self.bin(
                for: rect.x,
                lower: bounds.x,
                length: bounds.width,
                gridSide: gridSide
            )
            let endColumn: Int = Self.bin(
                for: (rect.x + rect.width).nextDown,
                lower: bounds.x,
                length: bounds.width,
                gridSide: gridSide
            )
            let startRow: Int = Self.bin(
                for: rect.y,
                lower: bounds.y,
                length: bounds.height,
                gridSide: gridSide
            )
            let endRow: Int = Self.bin(
                for: (rect.y + rect.height).nextDown,
                lower: bounds.y,
                length: bounds.height,
                gridSide: gridSide
            )

            for column: Int in min(startColumn, endColumn)...max(startColumn, endColumn) {
                for row: Int in min(startRow, endRow)...max(startRow, endRow) {
                    entryIndicesByCell[column * gridSide + row, default: []].append(index)
                }
            }
        }
        self.entryIndicesByCell = entryIndicesByCell
    }

    func hitEntryIndex(entries: [TreemapLayoutEntry], x: Double, y: Double) -> Int? {
        guard bounds.contains(x: x, y: y) else {
            return nil
        }
        let cellIndex: Int = Self.cellIndex(x: x, y: y, bounds: bounds, gridSide: gridSide)
        return entryIndicesByCell[cellIndex]?
            .lazy
            .filter { entries[$0].rect.contains(x: x, y: y) }
            .min { entries[$0].rect.area < entries[$1].rect.area }
    }

    private static func cellIndex(x: Double, y: Double, bounds: TreemapLayoutRect, gridSide: Int) -> Int {
        bin(for: x, lower: bounds.x, length: bounds.width, gridSide: gridSide) * gridSide
            + bin(for: y, lower: bounds.y, length: bounds.height, gridSide: gridSide)
    }

    private static func bin(for value: Double, lower: Double, length: Double, gridSide: Int) -> Int {
        guard length > 0 else { return 0 }
        let normalized: Double = (value - lower) / length
        return min(max(Int(normalized * Double(gridSide)), 0), gridSide - 1)
    }
}

private nonisolated struct TreemapLayoutNavigationIndex: Sendable {
    private let entries: [TreemapLayoutEntry]
    private let bounds: TreemapLayoutRect
    private let gridSide: Int
    private let entryIndicesByCell: [Int: [Int]]

    init?(entries: [TreemapLayoutEntry], candidateIndices: [Int], bounds: TreemapLayoutRect) {
        guard bounds.isEmpty == false, candidateIndices.isEmpty == false else {
            return nil
        }

        self.entries = entries
        self.bounds = bounds
        gridSide = min(256, max(16, Int(Double(candidateIndices.count).squareRoot().rounded(.up))))
        var entryIndicesByCell: [Int: [Int]] = [:]
        entryIndicesByCell.reserveCapacity(min(candidateIndices.count, gridSide * gridSide))
        for index: Int in candidateIndices {
            let rect: TreemapLayoutRect = entries[index].navigationRect
            guard rect.isEmpty == false else { continue }
            entryIndicesByCell[Self.cellIndex(
                x: rect.midX,
                y: rect.midY,
                bounds: bounds,
                gridSide: gridSide
            ), default: []].append(index)
        }
        self.entryIndicesByCell = entryIndicesByCell
    }

    func nearestEntryIndex(
        from selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Int? {
        let selectedColumn: Int = Self.bin(
            for: selectedRect.midX,
            lower: bounds.x,
            length: bounds.width,
            gridSide: gridSide
        )
        let selectedRow: Int = Self.bin(
            for: selectedRect.midY,
            lower: bounds.y,
            length: bounds.height,
            gridSide: gridSide
        )

        switch direction {
        case .left:
            return nearestInColumns(
                stride(from: selectedColumn, through: 0, by: -1),
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction
            )
        case .right:
            return nearestInColumns(
                selectedColumn..<gridSide,
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction
            )
        case .up:
            return nearestInRows(
                stride(from: selectedRow, through: 0, by: -1),
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction
            )
        case .down:
            return nearestInRows(
                selectedRow..<gridSide,
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction
            )
        }
    }

    private func nearestInColumns<Columns: Sequence>(
        _ columns: Columns,
        selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Int? where Columns.Element == Int {
        for column: Int in columns {
            if let candidate: Int = nearestInColumn(
                column,
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction
            ) {
                return candidate
            }
        }
        return nil
    }

    private func nearestInRows<Rows: Sequence>(
        _ rows: Rows,
        selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Int? where Rows.Element == Int {
        for row: Int in rows {
            var nearest: (index: Int, score: Double)?
            for column: Int in 0..<gridSide {
                updateNearest(
                    in: entryIndicesByCell[column * gridSide + row] ?? [],
                    selectedIndex: selectedIndex,
                    selectedRect: selectedRect,
                    direction: direction,
                    nearest: &nearest
                )
            }
            if let nearest {
                return nearest.index
            }
        }
        return nil
    }

    private func nearestInColumn(
        _ column: Int,
        selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection
    ) -> Int? {
        var nearest: (index: Int, score: Double)?
        for row: Int in 0..<gridSide {
            updateNearest(
                in: entryIndicesByCell[column * gridSide + row] ?? [],
                selectedIndex: selectedIndex,
                selectedRect: selectedRect,
                direction: direction,
                nearest: &nearest
            )
        }
        return nearest?.index
    }

    private func updateNearest(
        in candidateIndices: [Int],
        selectedIndex: Int,
        selectedRect: TreemapLayoutRect,
        direction: TreemapNavigationDirection,
        nearest: inout (index: Int, score: Double)?
    ) {
        for index: Int in candidateIndices where index != selectedIndex && entries[index].isSpecialItem == false {
            let rect: TreemapLayoutRect = entries[index].navigationRect
            guard rect.isEmpty == false,
                  let score: Double = TreemapLayoutPlan.directionalScore(
                    from: selectedRect,
                    to: rect,
                    direction: direction
                  ) else {
                continue
            }
            if nearest == nil || score < nearest!.score {
                nearest = (index, score)
            }
        }
    }

    private static func cellIndex(x: Double, y: Double, bounds: TreemapLayoutRect, gridSide: Int) -> Int {
        bin(for: x, lower: bounds.x, length: bounds.width, gridSide: gridSide) * gridSide
            + bin(for: y, lower: bounds.y, length: bounds.height, gridSide: gridSide)
    }

    private static func bin(for value: Double, lower: Double, length: Double, gridSide: Int) -> Int {
        guard length > 0 else { return 0 }
        let normalized: Double = (value - lower) / length
        return min(max(Int(normalized * Double(gridSide)), 0), gridSide - 1)
    }
}
