import AppKit

extension NSBitmapImageRep {
    nonisolated static func treemapImageRepCompatible(withBounds bounds: NSRect, backingScaleFactor scale: CGFloat, colorSpace: NSColorSpace?) -> NSBitmapImageRep {
        let viewBounds: NSRect = bounds
        let sizePoints: NSSize = viewBounds.size
        let sizePixel: NSSize = NSSize(width: sizePoints.width * scale, height: sizePoints.height * scale)
        var imgRep: NSBitmapImageRep = NSBitmapImageRep(
            treemapRGBBitmapWithWidth: Int(sizePixel.width.rounded(.up)),
            height: Int(sizePixel.height.rounded(.up))
        )
        imgRep.size = sizePoints
        if colorSpace != nil {
            let colorSpace: NSColorSpace = colorSpace!
            let retaggedImageRep: NSBitmapImageRep? = imgRep.retagging(with: colorSpace)
            if retaggedImageRep != nil {
                imgRep = retaggedImageRep!
            }
        }
        return imgRep
    }

    nonisolated convenience init(treemapRGBBitmapWithWidth width: Int, height: Int) {
        self.init(
            bitmapDataPlanes: nil,
            pixelsWide: max(width, 1),
            pixelsHigh: max(height, 1),
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
    }

    nonisolated func treemapSuitableImage() -> NSImage {
        let size: NSSize = self.size
        let image: NSImage = NSImage(size: size)
        image.addRepresentation(self)
        return image
    }
}
