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

        NSColor.black.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionOuterLineWidth)
        NSColor.white.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionMiddleLineWidth)
        NSColor.yellow.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionInnerLineWidth)
    }

    static func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }

    private static func stroke(rect: NSRect, lineWidth: CGFloat) {
        let path: NSBezierPath = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }
}
