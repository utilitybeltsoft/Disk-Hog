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

    static func drawSelection(entry: TreemapLayoutEntry?, in bounds: NSRect, backingScaleFactor: CGFloat) {
        guard let entry else {
            return
        }

        drawSelection(
            selectedRect: entry.rect.nsRect,
            unroundedRect: entry.unroundedRect.nsRect,
            in: bounds,
            backingScaleFactor: backingScaleFactor
        )
    }

    static func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
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
