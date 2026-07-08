import AppKit // ✓ Swift-only: Swift/AppKit import replacing NSBitmapImageRep-CreationExtensions.h:9 Cocoa import.

extension NSBitmapImageRep { // ✓ Z: NSBitmapImageRep-CreationExtensions.h:12 @interface NSBitmapImageRep (CreationExtensions).
    nonisolated static func treemapImageRepCompatible(withBounds bounds: NSRect, backingScaleFactor scale: CGFloat, colorSpace: NSColorSpace?) -> NSBitmapImageRep { // ✓ Z: NSBitmapImageRep-CreationExtensions.m:14 + imageRepCompatibleWithView:.
        let viewBounds: NSRect = bounds // ✓ Z: NSBitmapImageRep-CreationExtensions.m:16 NSRect viewBounds = [view bounds].
        let sizePoints: NSSize = viewBounds.size // ✓ Z: NSBitmapImageRep-CreationExtensions.m:17 NSSize sizePoints = viewBounds.size.
        let sizePixel: NSSize = NSSize(width: sizePoints.width * scale, height: sizePoints.height * scale) // ✓ Z: NSBitmapImageRep-CreationExtensions.m:18 NSSize sizePixel = [view convertSizeToBacking:sizePoints].
        var imgRep: NSBitmapImageRep = NSBitmapImageRep(treemapRGBBitmapWithWidth: Int(sizePixel.width), height: Int(sizePixel.height)) // ✓ Z: NSBitmapImageRep-CreationExtensions.m:20-21 initRGBBitmapWithWidth:sizePixel.width height:sizePixel.height.
        imgRep.size = sizePoints // ✓ Z: NSBitmapImageRep-CreationExtensions.m:25 [imgRep setSize:sizePoints].
        if colorSpace != nil { // ✓ Z: NSBitmapImageRep-CreationExtensions.m:28 if ([view window] != nil), with color space supplied by caller.
            let colorSpace: NSColorSpace = colorSpace! // ✓ Z: NSBitmapImageRep-CreationExtensions.m:32 NSColorSpace *colorSpace = [[view window] colorSpace].
            let retaggedImageRep: NSBitmapImageRep? = imgRep.retagging(with: colorSpace) // ✓ Z: NSBitmapImageRep-CreationExtensions.m:35 [imgRep bitmapImageRepByRetaggingWithColorSpace:colorSpace].
            if retaggedImageRep != nil { // ✓ Z: NSBitmapImageRep-CreationExtensions.m:36 if (imgRepWithCorrectCS != nil).
                imgRep = retaggedImageRep! // ✓ Z: NSBitmapImageRep-CreationExtensions.m:37 imgRep = imgRepWithCorrectCS.
            } // ✓ Z: NSBitmapImageRep-CreationExtensions.m:36-38 closes retag success branch.
        } // ✓ Z: NSBitmapImageRep-CreationExtensions.m:28-39 closes color-space branch.
        return imgRep // ✓ Z: NSBitmapImageRep-CreationExtensions.m:41 return imgRep.
    } // ✓ Z: NSBitmapImageRep-CreationExtensions.m:42 closes imageRepCompatibleWithView:.

    nonisolated convenience init(treemapRGBBitmapWithWidth width: Int, height: Int) { // ✓ Z: NSBitmapImageRep-CreationExtensions.m:45 - initRGBBitmapWithWidth:height:.
        self.init( // ✓ Z: NSBitmapImageRep-CreationExtensions.m:47 return [self initWithBitmapDataPlanes:NULL ...].
            bitmapDataPlanes: nil, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:47 NULL lets the class allocate it.
            pixelsWide: max(width, 1), // ✓ Z: NSBitmapImageRep-CreationExtensions.m:48 pixelsWide:width.
            pixelsHigh: max(height, 1), // ✓ Z: NSBitmapImageRep-CreationExtensions.m:49 pixelsHigh:height.
            bitsPerSample: 8, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:50 bitsPerSample:8.
            samplesPerPixel: 3, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:51 samplesPerPixel:3.
            hasAlpha: false, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:52 hasAlpha:NO.
            isPlanar: false, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:53 isPlanar:NO.
            colorSpaceName: .calibratedRGB, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:54 colorSpaceName:NSCalibratedRGBColorSpace.
            bytesPerRow: 0, // ✓ Z: NSBitmapImageRep-CreationExtensions.m:55 bytesPerRow:0.
            bitsPerPixel: 0 // ✓ Z: NSBitmapImageRep-CreationExtensions.m:56 bitsPerPixel:0.
        )! // ✓ Z: NSBitmapImageRep-CreationExtensions.m:56 closes initWithBitmapDataPlanes call.
    } // ✓ Z: NSBitmapImageRep-CreationExtensions.m:57 closes initRGBBitmapWithWidth:height:.

    nonisolated func treemapSuitableImage() -> NSImage { // ✓ Z: NSBitmapImageRep-CreationExtensions.m:61 - suitableImageForView:.
        let size: NSSize = self.size // ✓ Z: NSBitmapImageRep-CreationExtensions.m:63 NSSize size = [self size].
        let image: NSImage = NSImage(size: size) // ✓ Z: NSBitmapImageRep-CreationExtensions.m:64 NSImage *image = [[NSImage alloc] initWithSize:size].
        image.addRepresentation(self) // ✓ Z: NSBitmapImageRep-CreationExtensions.m:66 [image addRepresentation:self].
        return image // ✓ Z: NSBitmapImageRep-CreationExtensions.m:68 return [image autorelease].
    } // ✓ Z: NSBitmapImageRep-CreationExtensions.m:69 closes suitableImageForView:.
} // ✓ Z: NSBitmapImageRep-CreationExtensions.m:71 closes CreationExtensions implementation.
