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
    let itemPath: String
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
    let bounds: TreemapLayoutRect
    let entries: [TreemapLayoutEntry]
    let cushionSnapshots: [TreemapCushionSnapshot]

    private let entryIndexByPath: [String: Int]

    init(
        bounds: TreemapLayoutRect,
        entries: [TreemapLayoutEntry],
        cushionSnapshots: [TreemapCushionSnapshot]
    ) {
        self.bounds = bounds
        self.entries = entries
        self.cushionSnapshots = cushionSnapshots
        entryIndexByPath = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map { ($0.element.itemPath, $0.offset) }
        )
    }

    func entry(forPath path: String) -> TreemapLayoutEntry? {
        guard let index: Int = entryIndexByPath[path] else {
            return nil
        }
        return entries[index]
    }

    /// Resolves overlaps by choosing the smallest painted rectangle, which is
    /// the deepest visible descendant at the pointer location.
    func hitEntry(x: Double, y: Double) -> TreemapLayoutEntry? {
        entries
            .lazy
            .filter { $0.isSpecialItem == false && $0.rect.contains(x: x, y: y) }
            .min { $0.rect.area < $1.rect.area }
    }
}
