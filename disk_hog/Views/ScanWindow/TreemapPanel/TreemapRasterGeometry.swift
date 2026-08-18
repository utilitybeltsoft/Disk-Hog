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

    static func visibleMarkerRect(for rasterRect: NSRect, in bounds: NSRect, scale: CGFloat) -> NSRect {
        guard rasterRect.isEmpty == false, bounds.isEmpty == false, scale > 0 else { return .zero }
        let minimumSide: CGFloat = 3 / scale
        let width: CGFloat = min(bounds.width, max(rasterRect.width, minimumSide))
        let height: CGFloat = min(bounds.height, max(rasterRect.height, minimumSide))
        let x: CGFloat = min(max(rasterRect.midX - width / 2, bounds.minX), bounds.maxX - width)
        let y: CGFloat = min(max(rasterRect.midY - height / 2, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
