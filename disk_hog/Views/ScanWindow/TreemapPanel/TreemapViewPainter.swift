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
        guard let imageRep: NSBitmapImageRep = renderer?.drawInCache(
            size: canvasSize,
            scale: backingScaleFactor,
            colorSpace: colorSpace
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

    static func drawPlaceholder(source: ScanSource?, in bounds: NSRect, dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard let source: ScanSource = source else {
            return
        }

        let paragraphStyle: NSMutableParagraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: ScanWindowMetrics.placeholderTitleFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let pathAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: ScanWindowMetrics.placeholderPathFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        let titleRect: NSRect = NSRect(
            x: bounds.minX + ScanWindowMetrics.placeholderPadding,
            y: bounds.midY - ScanWindowMetrics.placeholderTitleYOffset,
            width: bounds.width - ScanWindowMetrics.placeholderPadding * 2,
            height: ScanWindowMetrics.placeholderLineHeight
        )
        let pathRect: NSRect = NSRect(
            x: bounds.minX + ScanWindowMetrics.placeholderPadding,
            y: titleRect.maxY + ScanWindowMetrics.placeholderSpacing,
            width: bounds.width - ScanWindowMetrics.placeholderPadding * 2,
            height: ScanWindowMetrics.placeholderLineHeight
        )
        NSString(string: "Treemap").draw(in: titleRect, withAttributes: titleAttributes)
        NSString(string: source.path).draw(in: pathRect, withAttributes: pathAttributes)
    }

    private static func stroke(rect: NSRect, lineWidth: CGFloat) {
        let path: NSBezierPath = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }
}
