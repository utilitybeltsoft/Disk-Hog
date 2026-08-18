import AppKit

/// A layout-scoped spatial index for directional treemap navigation.
///
/// The renderer tree is expensive to walk for every key event.  This index is
/// rebuilt when layout changes and limits each arrow-key lookup to one nearby
/// grid column or row instead of every rendered leaf.
@MainActor
final class TreemapDirectionalNavigationIndex {
    private let bounds: NSRect
    private let gridSide: Int
    private let renderersByCell: [Int: [TreemapItemRenderer]]

    init?(renderers: [TreemapItemRenderer], bounds: NSRect) {
        guard bounds.isEmpty == false, renderers.isEmpty == false else { return nil }

        self.bounds = bounds
        gridSide = min(256, max(16, Int(Double(renderers.count).squareRoot().rounded(.up))))
        var renderersByCell: [Int: [TreemapItemRenderer]] = [:]
        renderersByCell.reserveCapacity(min(renderers.count, gridSide * gridSide))
        for renderer: TreemapItemRenderer in renderers {
            let rect: NSRect = renderer.navigationRect
            guard rect.isEmpty == false else { continue }
            renderersByCell[Self.cellIndex(
                x: rect.midX,
                y: rect.midY,
                bounds: bounds,
                gridSide: gridSide
            ), default: []].append(renderer)
        }
        self.renderersByCell = renderersByCell
    }

    func nearestNeighbor(
        from selectedRenderer: TreemapItemRenderer,
        selectedRect: NSRect,
        direction: TreemapNavigationDirection
    ) -> TreemapItemRenderer? {
        let selectedCenter: NSPoint = NSPoint(x: selectedRect.midX, y: selectedRect.midY)
        let selectedColumn: Int = Self.bin(
            for: selectedCenter.x,
            lower: bounds.minX,
            length: bounds.width,
            gridSide: gridSide
        )
        let selectedRow: Int = Self.bin(
            for: selectedCenter.y,
            lower: bounds.minY,
            length: bounds.height,
            gridSide: gridSide
        )

        switch direction {
        case .left:
            return nearestInColumns(
                stride(from: selectedColumn, through: 0, by: -1),
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction
            )
        case .right:
            return nearestInColumns(
                selectedColumn..<gridSide,
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction
            )
        case .up:
            return nearestInRows(
                stride(from: selectedRow, through: 0, by: -1),
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction
            )
        case .down:
            return nearestInRows(
                selectedRow..<gridSide,
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction
            )
        }
    }

    private func nearestInColumns<Columns: Sequence>(
        _ columns: Columns,
        selectedRenderer: TreemapItemRenderer,
        selectedCenter: NSPoint,
        direction: TreemapNavigationDirection
    ) -> TreemapItemRenderer? where Columns.Element == Int {
        for column: Int in columns {
            if let candidate: TreemapItemRenderer = nearestInColumn(
                column,
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction
            ) {
                return candidate
            }
        }
        return nil
    }

    private func nearestInRows<Rows: Sequence>(
        _ rows: Rows,
        selectedRenderer: TreemapItemRenderer,
        selectedCenter: NSPoint,
        direction: TreemapNavigationDirection
    ) -> TreemapItemRenderer? where Rows.Element == Int {
        for row: Int in rows {
            var nearest: (renderer: TreemapItemRenderer, score: CGFloat)?
            for column: Int in 0..<gridSide {
                updateNearest(
                    in: renderersByCell[column * gridSide + row] ?? [],
                    selectedRenderer: selectedRenderer,
                    selectedCenter: selectedCenter,
                    direction: direction,
                    nearest: &nearest
                )
            }
            if let nearest {
                return nearest.renderer
            }
        }
        return nil
    }

    private func nearestInColumn(
        _ column: Int,
        selectedRenderer: TreemapItemRenderer,
        selectedCenter: NSPoint,
        direction: TreemapNavigationDirection
    ) -> TreemapItemRenderer? {
        var nearest: (renderer: TreemapItemRenderer, score: CGFloat)?
        for row: Int in 0..<gridSide {
            updateNearest(
                in: renderersByCell[column * gridSide + row] ?? [],
                selectedRenderer: selectedRenderer,
                selectedCenter: selectedCenter,
                direction: direction,
                nearest: &nearest
            )
        }
        return nearest?.renderer
    }

    private func updateNearest(
        in renderers: [TreemapItemRenderer],
        selectedRenderer: TreemapItemRenderer,
        selectedCenter: NSPoint,
        direction: TreemapNavigationDirection,
        nearest: inout (renderer: TreemapItemRenderer, score: CGFloat)?
    ) {
        for renderer: TreemapItemRenderer in renderers where renderer !== selectedRenderer && renderer.item.isSpecialItem == false {
            let rect: NSRect = renderer.navigationRect
            guard rect.isEmpty == false else { continue }
            let center: NSPoint = NSPoint(x: rect.midX, y: rect.midY)
            let primaryDistance: CGFloat
            let crossDistance: CGFloat
            switch direction {
            case .left:
                primaryDistance = selectedCenter.x - center.x
                crossDistance = abs(selectedCenter.y - center.y)
            case .right:
                primaryDistance = center.x - selectedCenter.x
                crossDistance = abs(selectedCenter.y - center.y)
            case .up:
                primaryDistance = selectedCenter.y - center.y
                crossDistance = abs(selectedCenter.x - center.x)
            case .down:
                primaryDistance = center.y - selectedCenter.y
                crossDistance = abs(selectedCenter.x - center.x)
            }
            guard primaryDistance > 0 else { continue }
            let score: CGFloat = primaryDistance + crossDistance * 0.25
            if nearest == nil || score < nearest!.score {
                nearest = (renderer, score)
            }
        }
    }

    private static func cellIndex(x: CGFloat, y: CGFloat, bounds: NSRect, gridSide: Int) -> Int {
        bin(for: x, lower: bounds.minX, length: bounds.width, gridSide: gridSide) * gridSide
            + bin(for: y, lower: bounds.minY, length: bounds.height, gridSide: gridSide)
    }

    private static func bin(for value: CGFloat, lower: CGFloat, length: CGFloat, gridSide: Int) -> Int {
        guard length > 0 else { return 0 }
        let normalized: CGFloat = (value - lower) / length
        return min(max(Int(normalized * CGFloat(gridSide)), 0), gridSide - 1)
    }
}
