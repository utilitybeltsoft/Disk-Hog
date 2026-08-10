import AppKit

@MainActor
final class TreemapCushionRenderer {
    private nonisolated static let baseBrightness: CGFloat = 1.8
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
            guard let convertedColor: NSColor = colorInRGBSpace.usingColorSpace(.genericRGB) else {
                return
            }
            colorInRGBSpace = convertedColor
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

    func renderCushion(in bitmap: NSBitmapImageRep, backingScaleFactor: CGFloat = 1) {
        renderCushionGeneric(in: bitmap, backingScaleFactor: backingScaleFactor)
    }

    func renderCushionGeneric(in bitmap: NSBitmapImageRep, backingScaleFactor: CGFloat = 1) {
        guard backingScaleFactor.isFinite, backingScaleFactor > 0,
              bitmap.bitsPerSample == 8,
              !bitmap.hasAlpha,
              let pixels: UnsafeMutablePointer<UInt8> = bitmap.bitmapData else {
            return
        }
        let rect: NSRect = self.rect
        let surface: [CGFloat] = self.surface
        let baseColor: NSColor = self.color
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
        let bytesPerRow: Int = bitmap.bytesPerRow
        let yStart: Int = Int((rect.minY * backingScaleFactor).rounded(.down))
        let yEnd: Int = Int((rect.maxY * backingScaleFactor).rounded(.up))
        let xStart: Int = Int((rect.minX * backingScaleFactor).rounded(.down))
        let xEnd: Int = Int((rect.maxX * backingScaleFactor).rounded(.up))
        assert(yStart >= 0 && yEnd <= bitmap.pixelsHigh)
        assert(xStart >= 0 && xEnd <= bitmap.pixelsWide)
        for y: Int in yStart..<yEnd {
            let rowStart: UnsafeMutablePointer<UInt8> = pixels + y * bytesPerRow
            let pointY: Double = (Double(y) + 0.5) / Double(backingScaleFactor)
            let normalY: Double = -(2 * Double(surface[1]) * pointY + Double(surface[3]))
            for x: Int in xStart..<xEnd {
                let pointX: Double = (Double(x) + 0.5) / Double(backingScaleFactor)
                let normalX: Double = -(2 * Double(surface[0]) * pointX + Double(surface[2]))
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

    nonisolated static func normalizeColorRed(_ red: inout CGFloat, green: inout CGFloat, blue: inout CGFloat) {
        TreemapColorNormalization.distributeOverflow(red: &red, green: &green, blue: &blue)
    }

    nonisolated static func normalizeColor(_ color: NSColor) -> NSColor {
        var colorInRGBSpace: NSColor = color
        if colorInRGBSpace.colorSpace != NSColorSpace.genericRGB {
            guard let convertedColor: NSColor = colorInRGBSpace.usingColorSpace(.genericRGB) else {
                return color
            }
            colorInRGBSpace = convertedColor
        }
        var red: CGFloat = colorInRGBSpace.redComponent
        var green: CGFloat = colorInRGBSpace.greenComponent
        var blue: CGFloat = colorInRGBSpace.blueComponent
        let alpha: CGFloat = colorInRGBSpace.alphaComponent
        TreemapColorNormalization.normalize(
            red: &red,
            green: &green,
            blue: &blue,
            baseBrightness: baseBrightness
        )
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
