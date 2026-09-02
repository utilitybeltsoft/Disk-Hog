import AppKit

@MainActor
enum TreemapViewPainter {
    static func drawRenderedImage(
        _ imageRep: NSBitmapImageRep,
        destinationRect: NSRect,
        sourceRect: NSRect?,
        fraction: CGFloat
    ) {
        let image: NSImage = imageRep.treemapSuitableImage()
        let sourceRect: NSRect = sourceRect ?? NSRect(origin: .zero, size: image.size)
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .copy,
            fraction: fraction,
            respectFlipped: true,
            hints: nil
        )
    }

    static func drawSelection(renderer: TreemapViewRenderer?, in bounds: NSRect, backingScaleFactor: CGFloat) {
        guard let selectedCellID: TreemapItemRenderer = renderer?.selectedCellID else {
            return
        }

        let selectedRect: NSRect = renderer?.itemRect(by: selectedCellID) ?? .zero
        drawSelection(
            selectedRect: selectedRect,
            unroundedRect: renderer?.selectedItemUnroundedRect() ?? .zero,
            in: bounds,
            backingScaleFactor: backingScaleFactor
        )
    }

    static func drawSelection(
        entry: TreemapLayoutEntry?,
        parentEntry: TreemapLayoutEntry? = nil,
        in bounds: NSRect,
        backingScaleFactor: CGFloat
    ) {
        guard let entry else {
            return
        }

        if let parentEntry, parentEntry.item != entry.item {
            drawParentContext(rect: parentEntry.rect.nsRect, color: .yellow, in: bounds)
        }

        drawSelection(
            selectedRect: entry.rect.nsRect,
            unroundedRect: entry.unroundedRect.nsRect,
            in: bounds,
            backingScaleFactor: backingScaleFactor
        )
    }

    /// A lighter, non-animated marker for the item under the pointer. Kept
    /// visually distinct from `drawSelection` (black+white vs. the
    /// selection's black+white+yellow) so hover and selection never look
    /// like the same rectangle relocating.
    static func drawHover(
        entry: TreemapLayoutEntry,
        parentEntry: TreemapLayoutEntry?,
        in bounds: NSRect,
        backingScaleFactor: CGFloat
    ) {
        let selectedRect: NSRect = entry.rect.nsRect
        let unroundedRect: NSRect = entry.unroundedRect.nsRect
        let sourceRect: NSRect
        if selectedRect.isEmpty {
            sourceRect = TreemapRasterGeometry.pixelAlignedRect(
                for: unroundedRect,
                scale: backingScaleFactor
            ).intersection(bounds)
        } else {
            sourceRect = TreemapSelectionRect.visibleRect(for: selectedRect, in: bounds)
        }
        guard sourceRect.isEmpty == false else {
            return
        }

        let isSmall: Bool = min(sourceRect.width, sourceRect.height) < ScanWindowMetrics.treemapMinimumSelectionSide
        // Only draw hover's parent context when the hovered item is too small
        // to place on its own; unlike selection (a single, deliberate, stable
        // overlay), hover changes on every pointer move, so an unconditional
        // parent rectangle would constantly compete with the selection's.
        if isSmall, let parentEntry, parentEntry.item != entry.item {
            drawParentContext(rect: parentEntry.rect.nsRect, color: .white, in: bounds)
        }

        let markerRect: NSRect = isSmall
            ? TreemapRasterGeometry.visibleMarkerRect(for: sourceRect, in: bounds, scale: backingScaleFactor)
            : sourceRect

        NSColor.black.setStroke()
        strokeContained(in: markerRect, lineWidth: ScanWindowMetrics.treemapHoverOuterLineWidth)
        NSColor.white.setStroke()
        strokeContained(in: markerRect, lineWidth: ScanWindowMetrics.treemapHoverInnerLineWidth)
    }

    static func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }

    private static func drawParentContext(rect: NSRect, color: NSColor, in bounds: NSRect) {
        let visibleRect: NSRect = rect.intersection(bounds)
        guard visibleRect.isEmpty == false else {
            return
        }
        color.withAlphaComponent(0.7).setStroke()
        let path: NSBezierPath = NSBezierPath(rect: visibleRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = ScanWindowMetrics.treemapParentContextLineWidth
        path.setLineDash(
            [ScanWindowMetrics.treemapParentContextDashLength, ScanWindowMetrics.treemapParentContextDashGap],
            count: 2,
            phase: 0
        )
        path.stroke()
    }

    private static func drawSelection(
        selectedRect: NSRect,
        unroundedRect: NSRect,
        in bounds: NSRect,
        backingScaleFactor: CGFloat
    ) {
        let sourceRect: NSRect
        if selectedRect.isEmpty {
            sourceRect = TreemapRasterGeometry.pixelAlignedRect(
                for: unroundedRect,
                scale: backingScaleFactor
            ).intersection(bounds)
        } else {
            sourceRect = TreemapSelectionRect.visibleRect(for: selectedRect, in: bounds)
        }
        guard sourceRect.isEmpty == false else {
            return
        }

        // Below the minimum border size, a plain fill/stroke of the item's own
        // (possibly sub-pixel) rect can be visually imperceptible. Enlarge to a
        // guaranteed-visible marker instead of drawing the raw rect, for both the
        // fully-collapsed case (selectedRect.isEmpty) and the merely-tiny case.
        if min(sourceRect.width, sourceRect.height) < ScanWindowMetrics.treemapMinimumSelectionSide {
            NSColor.yellow.setFill()
            TreemapRasterGeometry.visibleMarkerRect(
                for: sourceRect,
                in: bounds,
                scale: backingScaleFactor
            ).fill()
            return
        }

        NSColor.black.setStroke()
        strokeContained(in: sourceRect, lineWidth: ScanWindowMetrics.treemapSelectionOuterLineWidth)
        NSColor.white.setStroke()
        strokeContained(in: sourceRect, lineWidth: ScanWindowMetrics.treemapSelectionMiddleLineWidth)
        NSColor.yellow.setStroke()
        strokeContained(in: sourceRect, lineWidth: ScanWindowMetrics.treemapSelectionInnerLineWidth)
    }

    private static func strokeContained(in rect: NSRect, lineWidth: CGFloat) {
        let inset: CGFloat = lineWidth / 2
        let strokedRect: NSRect = rect.insetBy(dx: inset, dy: inset)
        guard strokedRect.width >= 0, strokedRect.height >= 0 else { return }
        let path: NSBezierPath = NSBezierPath(rect: strokedRect)
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private extension TreemapLayoutRect {
    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}
