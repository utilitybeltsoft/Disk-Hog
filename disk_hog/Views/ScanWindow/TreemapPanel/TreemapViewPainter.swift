import AppKit

@MainActor
enum TreemapViewPainter {
    static func drawCachedImage(
        renderer: TreemapViewRenderer?,
        canvasSize: NSSize,
        backingScaleFactor: CGFloat,
        colorSpace: NSColorSpace?,
        destinationRect: NSRect,
        sourceRect: NSRect?,
        fraction: CGFloat
    ) -> Bool {
        guard let imageRep: NSBitmapImageRep = renderer?.cachedImageOrRequestRendering(
            size: canvasSize,
            scale: backingScaleFactor
        ) else {
            return false
        }

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
        return true
    }

    static func drawSelection(renderer: TreemapViewRenderer?, in bounds: NSRect) {
        guard let selectedCellID: TreemapItemRenderer = renderer?.selectedCellID else {
            return
        }

        let rect: NSRect = TreemapSelectionRect.visibleRect(
            for: renderer?.itemRect(by: selectedCellID) ?? .zero,
            in: bounds,
            minimumSide: ScanWindowMetrics.treemapMinimumSelectionSide,
            edgeInset: ScanWindowMetrics.treemapSelectionOuterLineWidth / 2
        )
        guard rect != .zero else {
            return
        }

        if rect.width <= 1 || rect.height <= 1 {
            NSColor.yellow.setFill()
            rect.fill()
        } else if min(rect.width, rect.height) < ScanWindowMetrics.treemapMinimumSelectionSide {
            NSColor.yellow.setStroke()
            strokeContained(in: rect, lineWidth: 1)
        } else {
            NSColor.black.setStroke()
            strokeContained(in: rect, lineWidth: ScanWindowMetrics.treemapSelectionOuterLineWidth)
            NSColor.white.setStroke()
            strokeContained(in: rect, lineWidth: ScanWindowMetrics.treemapSelectionMiddleLineWidth)
            NSColor.yellow.setStroke()
            strokeContained(in: rect, lineWidth: ScanWindowMetrics.treemapSelectionInnerLineWidth)
        }
    }

    static func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
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
