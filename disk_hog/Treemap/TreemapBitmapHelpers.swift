import AppKit

extension NSBitmapImageRep {
    nonisolated static func treemapImageRepCompatible(withBounds bounds: NSRect, backingScaleFactor scale: CGFloat, colorSpace: NSColorSpace?) -> NSBitmapImageRep? {
        guard scale.isFinite, scale > 0 else {
            return nil
        }
        let viewBounds: NSRect = bounds
        let sizePoints: NSSize = viewBounds.size
        let sizePixel: NSSize = NSSize(width: sizePoints.width * scale, height: sizePoints.height * scale)
        guard sizePixel.width.isFinite, sizePixel.height.isFinite,
              sizePixel.width <= CGFloat(Int.max), sizePixel.height <= CGFloat(Int.max),
              let imageRep: NSBitmapImageRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(Int(sizePixel.width.rounded(.up)), 1),
                pixelsHigh: max(Int(sizePixel.height.rounded(.up)), 1),
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            return nil
        }
        var imgRep: NSBitmapImageRep = imageRep
        imgRep.size = sizePoints
        if let colorSpace, let retaggedImageRep: NSBitmapImageRep = imgRep.retagging(with: colorSpace) {
            imgRep = retaggedImageRep
        }
        return imgRep
    }

    nonisolated func treemapSuitableImage() -> NSImage {
        let size: NSSize = self.size
        let image: NSImage = NSImage(size: size)
        image.addRepresentation(self)
        return image
    }
}
