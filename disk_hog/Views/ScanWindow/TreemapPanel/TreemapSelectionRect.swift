import AppKit

nonisolated enum TreemapSelectionRect {
    static func visibleRect(
        for itemRect: NSRect,
        in bounds: NSRect
    ) -> NSRect {
        let clippedRect: NSRect = itemRect.intersection(bounds)
        return clippedRect.isNull ? .zero : clippedRect
    }
}
