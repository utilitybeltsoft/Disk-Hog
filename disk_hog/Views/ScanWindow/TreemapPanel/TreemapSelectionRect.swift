import AppKit

nonisolated enum TreemapSelectionRect {
    static func visibleRect(
        for itemRect: NSRect,
        in bounds: NSRect,
        minimumSide: CGFloat,
        edgeInset: CGFloat
    ) -> NSRect {
        guard !bounds.isEmpty else {
            return .zero
        }

        let safeBounds: NSRect = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        guard !safeBounds.isEmpty else {
            return .zero
        }

        let anchorX: CGFloat = itemRect.width > 0 ? itemRect.midX : itemRect.minX
        let anchorY: CGFloat = itemRect.height > 0 ? itemRect.midY : itemRect.minY
        let targetWidth: CGFloat = itemRect.width > 0 ? max(itemRect.width, minimumSide) : minimumSide
        let targetHeight: CGFloat = itemRect.height > 0 ? max(itemRect.height, minimumSide) : minimumSide
        let visibleWidth: CGFloat = min(targetWidth, safeBounds.width)
        let visibleHeight: CGFloat = min(targetHeight, safeBounds.height)
        let visibleOriginX: CGFloat = min(max(anchorX - visibleWidth / 2, safeBounds.minX), safeBounds.maxX - visibleWidth)
        let visibleOriginY: CGFloat = min(max(anchorY - visibleHeight / 2, safeBounds.minY), safeBounds.maxY - visibleHeight)
        return NSRect(x: visibleOriginX, y: visibleOriginY, width: visibleWidth, height: visibleHeight)
    }
}
