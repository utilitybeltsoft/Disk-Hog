import AppKit

nonisolated enum TreemapSelectionRect {
    static func visibleRect(
        for itemRect: NSRect,
        in bounds: NSRect,
        minimumSide: CGFloat,
        edgeInset: CGFloat
    ) -> NSRect {
        _ = minimumSide
        _ = edgeInset
        return itemRect.intersection(bounds)
    }
}
