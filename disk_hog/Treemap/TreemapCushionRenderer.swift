import AppKit

nonisolated final class TreemapCushionRenderer: @unchecked Sendable {
    private static let baseBrightness: CGFloat = 1.8
    private static let maxRGBValue: CGFloat = 1.0
    private static let defaultCushionColor: NSColor = TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0, green: 0, blue: 0.9, alpha: 1))

    private(set) var rect: NSRect
    private(set) var color: NSColor
    private var surface: [CGFloat]

    init() {
        self.color = Self.defaultCushionColor
        self.surface = [0, 0, 0, 0]
        self.rect = .zero
    }

    convenience init(rect: NSRect) {
        self.init()
        self.rect = rect
    }

    func setRect(_ rect: NSRect) {
        self.rect = rect
    }

    func setColor(_ newColor: NSColor) {
        var colorInRGBSpace: NSColor = newColor
        if colorInRGBSpace.colorSpace != NSColorSpace.genericRGB {
            colorInRGBSpace = colorInRGBSpace.usingColorSpace(.genericRGB)!
        }
        self.color = colorInRGBSpace
    }

    func surfaceValues() -> [CGFloat] {
        surface
    }

    func setSurface(_ newSurface: [CGFloat]) {
        precondition(newSurface.count == 4)
        surface = newSurface
    }

    func addRidgeByHeightFactor(_ heightFactor: CGFloat) {
        let h4: CGFloat = 4 * heightFactor
        let wf: CGFloat = h4 / rect.width
        surface[2] += wf * (rect.maxX + rect.minX)
        surface[0] -= wf
        let hf: CGFloat = h4 / rect.height
        surface[3] += hf * (rect.maxY + rect.minY)
        surface[1] -= hf
    }

    func renderCushion(in bitmap: NSBitmapImageRep) {
        renderCushionGeneric(in: bitmap)
    }

    func renderCushionGeneric(in bitmap: NSBitmapImageRep) {
        let rect: NSRect = self.rect
        let surface: [CGFloat] = self.surface
        let baseColor: NSColor = self.color
        assert(rect.maxY <= CGFloat(bitmap.pixelsHigh))
        assert(rect.maxX <= CGFloat(bitmap.pixelsWide))
        assert(bitmap.bitsPerSample == 8)
        assert(!bitmap.hasAlpha)
        let ambientLight: Double = 0.15
        let lightX: Double = -1
        let lightY: Double = -1
        let lightZ: Double = 10
        let brightnessLight: Double = 1 - ambientLight
        let lightLength: Double = sqrt(lightX * lightX + lightY * lightY + lightZ * lightZ)
        let normalizedLightX: Double = lightX / lightLength
        let normalizedLightY: Double = lightY / lightLength
        let normalizedLightZ: Double = lightZ / lightLength
        let baseRed: CGFloat = baseColor.redComponent
        let baseGreen: CGFloat = baseColor.greenComponent
        let baseBlue: CGFloat = baseColor.blueComponent
        let pixels: UnsafeMutablePointer<UInt8> = bitmap.bitmapData!
        let bytesPerRow: Int = bitmap.bytesPerRow
        let yStart: Int = Int(rect.minY)
        let yEnd: Int = Int(rect.maxY)
        let xStart: Int = Int(rect.minX)
        let xEnd: Int = Int(rect.maxX)
        for y: Int in yStart..<yEnd {
            let rowStart: UnsafeMutablePointer<UInt8> = pixels + y * bytesPerRow
            let normalY: Double = -(2 * Double(surface[1]) * (Double(y) + 0.5) + Double(surface[3]))
            for x: Int in xStart..<xEnd {
                let normalX: Double = -(2 * Double(surface[0]) * (Double(x) + 0.5) + Double(surface[2]))
                let cosine: Double = (normalX * normalizedLightX + normalY * normalizedLightY + normalizedLightZ) / sqrt(normalX * normalX + normalY * normalY + 1.0)
                var brightness: Double = brightnessLight * cosine
                brightness = brightness < 0 ? ambientLight : (brightness + ambientLight)
                assert(brightness <= 1.0)
                brightness *= 2.5 / Double(Self.baseBrightness)
                var red: CGFloat = baseRed * CGFloat(brightness)
                var green: CGFloat = baseGreen * CGFloat(brightness)
                var blue: CGFloat = baseBlue * CGFloat(brightness)
                Self.normalizeColorRed(&red, green: &green, blue: &blue)
                let pixel: UnsafeMutablePointer<UInt8> = rowStart + (x * 3)
                pixel[0] = UInt8(red * 255)
                pixel[1] = UInt8(green * 255)
                pixel[2] = UInt8(blue * 255)
            }
        }
    }

    static func normalizeColorRed(_ red: inout CGFloat, green: inout CGFloat, blue: inout CGFloat) {
        if red > maxRGBValue {
            distributeRGB1(&red, toRGB2: &green, toRGB3: &blue)
        } else if green > maxRGBValue {
            distributeRGB1(&green, toRGB2: &red, toRGB3: &blue)
        } else if blue > maxRGBValue {
            distributeRGB1(&blue, toRGB2: &red, toRGB3: &green)
        }
    }

    static func normalizeColor(_ color: NSColor) -> NSColor {
        var colorInRGBSpace: NSColor = color
        if colorInRGBSpace.colorSpace != NSColorSpace.genericRGB {
            colorInRGBSpace = colorInRGBSpace.usingColorSpace(.genericRGB)!
        }
        var red: CGFloat = colorInRGBSpace.redComponent
        var green: CGFloat = colorInRGBSpace.greenComponent
        var blue: CGFloat = colorInRGBSpace.blueComponent
        let alpha: CGFloat = colorInRGBSpace.alphaComponent
        let componentSum: CGFloat = red + green + blue
        let factor: CGFloat = componentSum != 0.0 ? (baseBrightness / componentSum) : 1
        red *= factor
        green *= factor
        blue *= factor
        normalizeColorRed(&red, green: &green, blue: &blue)
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func distributeRGB1(_ first: inout CGFloat, toRGB2 second: inout CGFloat, toRGB3 third: inout CGFloat) {
        var h: CGFloat = (first - maxRGBValue) / 2.0
        first = maxRGBValue
        second += h
        third += h
        if second > maxRGBValue {
            h = second - maxRGBValue
            second = maxRGBValue
            third += h
            assert(third <= maxRGBValue)
        } else if third > maxRGBValue {
            h = third - maxRGBValue
            third = maxRGBValue
            second += h
            assert(second <= maxRGBValue)
        }
    }
}
