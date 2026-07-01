import AppKit // ✓ Swift-only: Swift/AppKit import replacing TMVCushionRenderer.h:9 Foundation import plus NSColor/NSBitmapImageRep use from Cocoa.

nonisolated final class TreemapCushionRenderer: @unchecked Sendable { // ✓ Z: TMVCushionRenderer.h:18 declares TMVCushionRenderer object.
    private static let baseBrightness: CGFloat = 1.8 // ✓ Z: TMVCushionRenderer.h:16 defines BASE_BRIGHTNESS 1.8f.
    private static let maxRGBValue: CGFloat = 1.0 // ✓ Z: TMVCushionRenderer.m:15 defines MAX_RGB_VALUE 1.0f.
    private static let defaultCushionColor: NSColor = TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0, green: 0, blue: 0.9, alpha: 1)) // ✓ Z: TMVCushionRenderer.m:33-38 initializes g_defaultCushionColor.

    private(set) var rect: NSRect // ✓ Z: TMVCushionRenderer.h:20 stores NSRect _rect.
    private(set) var color: NSColor // ✓ Z: TMVCushionRenderer.h:21 stores NSColor *_color.
    private var surface: [CGFloat] // ✓ Z: TMVCushionRenderer.h:22 stores CGFloat _surface[4].

    init() { // ✓ Z: TMVCushionRenderer.m:52 - (id) init.
        self.color = Self.defaultCushionColor // ✓ Z: TMVCushionRenderer.m:56-57 retains g_defaultCushionColor into _color.
        self.surface = [0, 0, 0, 0] // ✓ Z: TMVCushionRenderer.m:59 memset(_surface, 0, sizeof(_surface)).
        self.rect = .zero // ✓ Z: TMVCushionRenderer.m:61 _rect = NSZeroRect.
    } // ✓ Z: TMVCushionRenderer.m:64 closes init.

    convenience init(rect: NSRect) { // ✓ Z: TMVCushionRenderer.m:66 - (id) initWithRect:.
        self.init() // ✓ Z: TMVCushionRenderer.m:68 [self init].
        self.rect = rect // ✓ Z: TMVCushionRenderer.m:70 _rect = rect.
    } // ✓ Z: TMVCushionRenderer.m:73 closes initWithRect:.

    func setRect(_ rect: NSRect) { // ✓ Z: TMVCushionRenderer.m:87 - (void) setRect:.
        self.rect = rect // ✓ Z: TMVCushionRenderer.m:89 _rect = rect.
    } // ✓ Z: TMVCushionRenderer.m:90 closes setRect:.

    func setColor(_ newColor: NSColor) { // ✓ Z: TMVCushionRenderer.m:97 - (void) setColor:.
        var colorInRGBSpace: NSColor = newColor // ✓ Swift-only: Swift local variable replacing Objective-C reassignment of newColor.
        if colorInRGBSpace.colorSpace != NSColorSpace.genericRGB { // ✓ Z: TMVCushionRenderer.m:99-100 checks generic RGB color space.
            colorInRGBSpace = colorInRGBSpace.usingColorSpace(.genericRGB)! // ✓ Z: TMVCushionRenderer.m:101 converts colorUsingColorSpace: genericRGBColorSpace.
        } // ✓ Z: TMVCushionRenderer.m:100-101 closes RGB conversion branch.
        self.color = colorInRGBSpace // ✓ Z: TMVCushionRenderer.m:103-106 retains newColor, releases old color, assigns _color.
    } // ✓ Z: TMVCushionRenderer.m:107 closes setColor:.

    func surfaceValues() -> [CGFloat] { // ✓ Z: TMVCushionRenderer.m:109 - (CGFloat*) surface.
        surface // ✓ Z: TMVCushionRenderer.m:111 return _surface.
    } // ✓ Z: TMVCushionRenderer.m:112 closes surface.

    func setSurface(_ newSurface: [CGFloat]) { // ✓ Z: TMVCushionRenderer.m:114 - (void) setSurface:.
        precondition(newSurface.count == 4) // ✓ Swift-only: Swift array count guard replacing fixed-size CGFloat[4] type safety.
        surface = newSurface // ✓ Z: TMVCushionRenderer.m:116 memcpy(_surface, newsurface, sizeof(_surface)).
    } // ✓ Z: TMVCushionRenderer.m:117 closes setSurface:.

    func addRidgeByHeightFactor(_ heightFactor: CGFloat) { // ✓ Z: TMVCushionRenderer.m:120 - (void) addRidgeByHeightFactor:.
        let h4: CGFloat = 4 * heightFactor // ✓ Z: TMVCushionRenderer.m:140 CGFloat h4= 4 * heightFactor.
        let wf: CGFloat = h4 / rect.width // ✓ Z: TMVCushionRenderer.m:142 CGFloat wf= h4 / NSWidth(_rect).
        surface[2] += wf * (rect.maxX + rect.minX) // ✓ Z: TMVCushionRenderer.m:143 _surface[2]+= wf * (NSMaxX(_rect) + NSMinX(_rect)).
        surface[0] -= wf // ✓ Z: TMVCushionRenderer.m:144 _surface[0]-= wf.
        let hf: CGFloat = h4 / rect.height // ✓ Z: TMVCushionRenderer.m:146 CGFloat hf= h4 / NSHeight(_rect).
        surface[3] += hf * (rect.maxY + rect.minY) // ✓ Z: TMVCushionRenderer.m:147 _surface[3]+= hf * (NSMaxY(_rect) + NSMinY(_rect)).
        surface[1] -= hf // ✓ Z: TMVCushionRenderer.m:148 _surface[1]-= hf.
    } // ✓ Z: TMVCushionRenderer.m:149 closes addRidgeByHeightFactor:.

    func renderCushion(in bitmap: NSBitmapImageRep) { // ✓ Z: TMVCushionRenderer.m:151 - (void) renderCushionInBitmap:.
        renderCushionGeneric(in: bitmap) // ✓ Z: TMVCushionRenderer.m:153-155 dispatches to g_renderFunction, generic on non-PPC.
    } // ✓ Z: TMVCushionRenderer.m:156 closes renderCushionInBitmap:.

    func renderCushionGeneric(in bitmap: NSBitmapImageRep) { // ✓ Z: TMVCushionRenderer.m:158 - (void) renderCushionInBitmapGeneric:.
        let rect: NSRect = self.rect // ✓ Z: TMVCushionRenderer.m:160 NSRect rect = [self rect].
        let surface: [CGFloat] = self.surface // ✓ Z: TMVCushionRenderer.m:161 const CGFloat *surface = [self surface].
        let baseColor: NSColor = self.color // ✓ Z: TMVCushionRenderer.m:162 NSColor *baseColor = [self color].
        assert(rect.maxY <= CGFloat(bitmap.pixelsHigh)) // ✓ Z: TMVCushionRenderer.m:166 asserts rect does not exceed bitmap height.
        assert(rect.maxX <= CGFloat(bitmap.pixelsWide)) // ✓ Z: TMVCushionRenderer.m:167 asserts rect does not exceed bitmap width.
        assert(bitmap.bitsPerSample == 8) // ✓ Z: TMVCushionRenderer.m:168 asserts 8 bits per RGB component.
        assert(!bitmap.hasAlpha) // ✓ Z: TMVCushionRenderer.m:169 asserts bitmap has no alpha component.
        let ambientLight: Double = 0.15 // ✓ Z: TMVCushionRenderer.m:172 const double Ia = 0.15.
        let lightX: Double = -1 // ✓ Z: TMVCushionRenderer.m:175 static const double lx = -1.
        let lightY: Double = -1 // ✓ Z: TMVCushionRenderer.m:176 static const double ly = -1.
        let lightZ: Double = 10 // ✓ Z: TMVCushionRenderer.m:177 static const double lz = 10.
        let brightnessLight: Double = 1 - ambientLight // ✓ Z: TMVCushionRenderer.m:180 const double Is = 1 - Ia.
        let lightLength: Double = sqrt(lightX * lightX + lightY * lightY + lightZ * lightZ) // ✓ Z: TMVCushionRenderer.m:182 const double len = sqrt(lx*lx + ly*ly + lz*lz).
        let normalizedLightX: Double = lightX / lightLength // ✓ Z: TMVCushionRenderer.m:183 const double Lx = lx / len.
        let normalizedLightY: Double = lightX / lightLength // ✓ Z: TMVCushionRenderer.m:184 const double Ly = lx / len.
        let normalizedLightZ: Double = lightZ / lightLength // ✓ Z: TMVCushionRenderer.m:185 const double Lz = lz / len.
        let baseRed: CGFloat = baseColor.redComponent // ✓ Z: TMVCushionRenderer.m:187 const CGFloat colR = [baseColor redComponent].
        let baseGreen: CGFloat = baseColor.greenComponent // ✓ Z: TMVCushionRenderer.m:188 const CGFloat colG = [baseColor greenComponent].
        let baseBlue: CGFloat = baseColor.blueComponent // ✓ Z: TMVCushionRenderer.m:189 const CGFloat colB = [baseColor blueComponent].
        let pixels: UnsafeMutablePointer<UInt8> = bitmap.bitmapData! // ✓ Z: TMVCushionRenderer.m:191 unsigned char *pixels = [bitmap bitmapData].
        let bytesPerRow: Int = bitmap.bytesPerRow // ✓ Z: TMVCushionRenderer.m:192 NSInteger bytesPerRow = [bitmap bytesPerRow].
        let yStart: Int = Int(rect.minY) // ✓ Z: TMVCushionRenderer.m:195 int yStart = NSMinY(rect).
        let yEnd: Int = Int(rect.maxY) // ✓ Z: TMVCushionRenderer.m:196 int yEnd = NSMaxY(rect).
        let xStart: Int = Int(rect.minX) // ✓ Z: TMVCushionRenderer.m:197 int xStart = NSMinX(rect).
        let xEnd: Int = Int(rect.maxX) // ✓ Z: TMVCushionRenderer.m:198 int xEnd = NSMaxX(rect).
        for y: Int in yStart..<yEnd { // ✓ Z: TMVCushionRenderer.m:200 for (iy = yStart; iy < yEnd; iy++).
            let rowStart: UnsafeMutablePointer<UInt8> = pixels + y * bytesPerRow // ✓ Z: TMVCushionRenderer.m:202 unsigned char *rowStart = pixels + iy * bytesPerRow.
            let normalY: Double = -(2 * Double(surface[1]) * (Double(y) + 0.5) + Double(surface[3])) // ✓ Z: TMVCushionRenderer.m:203 const double ny = -(2 * surface[1] * (iy + 0.5) + surface[3]).
            for x: Int in xStart..<xEnd { // ✓ Z: TMVCushionRenderer.m:205 for (ix = xStart; ix < xEnd; ix++).
                let normalX: Double = -(2 * Double(surface[0]) * (Double(x) + 0.5) + Double(surface[2])) // ✓ Z: TMVCushionRenderer.m:207 const double nx = -(2 * surface[0] * (ix + 0.5) + surface[2]).
                let cosine: Double = (normalX * normalizedLightX + normalY * normalizedLightY + normalizedLightZ) / sqrt(normalX * normalX + normalY * normalY + 1.0) // ✓ Z: TMVCushionRenderer.m:209 double cosa = (nx*Lx + ny*Ly + Lz) / sqrt(nx*nx + ny*ny + 1.0).
                var brightness: Double = brightnessLight * cosine // ✓ Z: TMVCushionRenderer.m:211 double brightness = Is * cosa.
                brightness = brightness < 0 ? ambientLight : (brightness + ambientLight) // ✓ Z: TMVCushionRenderer.m:212 brightness = brightness < 0 ? Ia : (brightness + Ia).
                assert(brightness <= 1.0) // ✓ Z: TMVCushionRenderer.m:214 NSAssert(brightness <= 1.0, ...).
                brightness *= 2.5 / Double(Self.baseBrightness) // ✓ Z: TMVCushionRenderer.m:216 brightness *= 2.5 / BASE_BRIGHTNESS.
                var red: CGFloat = baseRed * CGFloat(brightness) // ✓ Z: TMVCushionRenderer.m:218 CGFloat red = colR * brightness.
                var green: CGFloat = baseGreen * CGFloat(brightness) // ✓ Z: TMVCushionRenderer.m:219 CGFloat green = colG * brightness.
                var blue: CGFloat = baseBlue * CGFloat(brightness) // ✓ Z: TMVCushionRenderer.m:220 CGFloat blue = colB * brightness.
                Self.normalizeColorRed(&red, green: &green, blue: &blue) // ✓ Z: TMVCushionRenderer.m:222 [TMVCushionRenderer normalizeColorRed:&red green:&green blue:&blue].
                let pixel: UnsafeMutablePointer<UInt8> = rowStart + (x * 3) // ✓ Z: TMVCushionRenderer.m:235 unsigned char *pixel = rowStart + (ix*3).
                pixel[0] = UInt8(red * 255) // ✓ Z: TMVCushionRenderer.m:237 *pixel = (unsigned char)(red * 255).
                pixel[1] = UInt8(green * 255) // ✓ Z: TMVCushionRenderer.m:238 pixel[1] = (unsigned char)(green * 255).
                pixel[2] = UInt8(blue * 255) // ✓ Z: TMVCushionRenderer.m:239 pixel[2] = (unsigned char)(blue * 255).
            } // ✓ Z: TMVCushionRenderer.m:240 closes x loop.
        } // ✓ Z: TMVCushionRenderer.m:241 closes y loop.
    } // ✓ Z: TMVCushionRenderer.m:242 closes renderCushionInBitmapGeneric:.

    static func normalizeColorRed(_ red: inout CGFloat, green: inout CGFloat, blue: inout CGFloat) { // ✓ Z: TMVCushionRenderer.m:439 + normalizeColorRed:green:blue:.
        if red > maxRGBValue { // ✓ Z: TMVCushionRenderer.m:444 if (*red > MAX_RGB_VALUE).
            distributeRGB1(&red, toRGB2: &green, toRGB3: &blue) // ✓ Z: TMVCushionRenderer.m:446 distributeRGB1:red toRGB2:green toRGB3:blue.
        } else if green > maxRGBValue { // ✓ Z: TMVCushionRenderer.m:448 else if (*green > MAX_RGB_VALUE).
            distributeRGB1(&green, toRGB2: &red, toRGB3: &blue) // ✓ Z: TMVCushionRenderer.m:450 distributeRGB1:green toRGB2:red toRGB3:blue.
        } else if blue > maxRGBValue { // ✓ Z: TMVCushionRenderer.m:452 else if (*blue > MAX_RGB_VALUE).
            distributeRGB1(&blue, toRGB2: &red, toRGB3: &green) // ✓ Z: TMVCushionRenderer.m:454 distributeRGB1:blue toRGB2:red toRGB3:green.
        } // ✓ Z: TMVCushionRenderer.m:455 closes RGB overflow branch.
    } // ✓ Z: TMVCushionRenderer.m:456 closes normalizeColorRed:green:blue:.

    static func normalizeColor(_ color: NSColor) -> NSColor { // ✓ Z: TMVCushionRenderer.m:458 + normalizeColor:.
        var colorInRGBSpace: NSColor = color // ✓ Swift-only: Swift local variable replacing Objective-C reassignment of color parameter.
        if colorInRGBSpace.colorSpace != NSColorSpace.genericRGB { // ✓ Z: TMVCushionRenderer.m:460-461 checks generic RGB color space.
            colorInRGBSpace = colorInRGBSpace.usingColorSpace(.genericRGB)! // ✓ Z: TMVCushionRenderer.m:462 colorUsingColorSpace:genericRGBColorSpace.
        } // ✓ Z: TMVCushionRenderer.m:461-462 closes RGB conversion branch.
        var red: CGFloat = colorInRGBSpace.redComponent // ✓ Z: TMVCushionRenderer.m:464 CGFloat red = [color redComponent].
        var green: CGFloat = colorInRGBSpace.greenComponent // ✓ Z: TMVCushionRenderer.m:465 CGFloat green = [color greenComponent].
        var blue: CGFloat = colorInRGBSpace.blueComponent // ✓ Z: TMVCushionRenderer.m:466 CGFloat blue = [color blueComponent].
        let alpha: CGFloat = colorInRGBSpace.alphaComponent // ✓ Z: TMVCushionRenderer.m:468 CGFloat alpha = [color alphaComponent].
        let componentSum: CGFloat = red + green + blue // ✓ Z: TMVCushionRenderer.m:470 CGFloat componentSum = red + green + blue.
        let factor: CGFloat = componentSum != 0.0 ? (baseBrightness / componentSum) : 1 // ✓ Z: TMVCushionRenderer.m:471 CGFloat f = componentSum != 0.0 ? BASE_BRIGHTNESS / componentSum : 1.
        red *= factor // ✓ Z: TMVCushionRenderer.m:472 red *= f.
        green *= factor // ✓ Z: TMVCushionRenderer.m:473 green *= f.
        blue *= factor // ✓ Z: TMVCushionRenderer.m:474 blue *= f.
        normalizeColorRed(&red, green: &green, blue: &blue) // ✓ Z: TMVCushionRenderer.m:476 normalizeColorRed:&red green:&green blue:&blue.
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha) // ✓ Z: TMVCushionRenderer.m:478 colorWithCalibratedRed:green:blue:alpha:.
    } // ✓ Z: TMVCushionRenderer.m:479 closes normalizeColor:.

    private static func distributeRGB1(_ first: inout CGFloat, toRGB2 second: inout CGFloat, toRGB3 third: inout CGFloat) { // ✓ Z: TMVCushionRenderer.m:488 + distributeRGB1:toRGB2:toRGB3:.
        var h: CGFloat = (first - maxRGBValue) / 2.0 // ✓ Z: TMVCushionRenderer.m:490 CGFloat h = (*first - MAX_RGB_VALUE) / 2.0f.
        first = maxRGBValue // ✓ Z: TMVCushionRenderer.m:491 *first = MAX_RGB_VALUE.
        second += h // ✓ Z: TMVCushionRenderer.m:492 *second += h.
        third += h // ✓ Z: TMVCushionRenderer.m:493 *third += h.
        if second > maxRGBValue { // ✓ Z: TMVCushionRenderer.m:495 if (*second > MAX_RGB_VALUE).
            h = second - maxRGBValue // ✓ Z: TMVCushionRenderer.m:497 h = *second - MAX_RGB_VALUE.
            second = maxRGBValue // ✓ Z: TMVCushionRenderer.m:498 *second = MAX_RGB_VALUE.
            third += h // ✓ Z: TMVCushionRenderer.m:499 *third += h.
            assert(third <= maxRGBValue) // ✓ Z: TMVCushionRenderer.m:500 NSAssert(*third <= MAX_RGB_VALUE, ...).
        } else if third > maxRGBValue { // ✓ Z: TMVCushionRenderer.m:502 else if (*third > MAX_RGB_VALUE).
            h = third - maxRGBValue // ✓ Z: TMVCushionRenderer.m:504 h = *third - MAX_RGB_VALUE.
            third = maxRGBValue // ✓ Z: TMVCushionRenderer.m:505 *third = MAX_RGB_VALUE.
            second += h // ✓ Z: TMVCushionRenderer.m:506 *second += h.
            assert(second <= maxRGBValue) // ✓ Z: TMVCushionRenderer.m:507 NSAssert(*second <= MAX_RGB_VALUE, ...).
        } // ✓ Z: TMVCushionRenderer.m:508 closes overflow redistribution branch.
    } // ✓ Z: TMVCushionRenderer.m:509 closes distributeRGB1:toRGB2:toRGB3:.
} // ✓ Z: TMVCushionRenderer.m:511 closes TMVCushionRenderer(Private) implementation.
