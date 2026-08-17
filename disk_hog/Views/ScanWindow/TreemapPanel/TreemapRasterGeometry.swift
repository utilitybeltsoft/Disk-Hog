import AppKit

enum TreemapRasterGeometry {
    static func pixelAlignedRect(for rect: NSRect, scale: CGFloat) -> NSRect {
        guard rect.isEmpty == false, scale > 0 else { return .zero }
        let minX: CGFloat = floor(rect.minX * scale) / scale
        let minY: CGFloat = floor(rect.minY * scale) / scale
        let maxX: CGFloat = ceil(rect.maxX * scale) / scale
        let maxY: CGFloat = ceil(rect.maxY * scale) / scale
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func contextRect(around selection: NSRect, in bounds: NSRect, padding: CGFloat) -> NSRect {
        guard selection.isEmpty == false, bounds.isEmpty == false else { return .zero }
        let width: CGFloat = min(bounds.width, selection.width + padding * 2)
        let height: CGFloat = min(bounds.height, selection.height + padding * 2)
        let x: CGFloat = min(max(selection.midX - width / 2, bounds.minX), bounds.maxX - width)
        let y: CGFloat = min(max(selection.midY - height / 2, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
