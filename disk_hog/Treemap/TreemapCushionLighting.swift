import Foundation

/// The cushion-shading lighting model shared by the two places that rasterize a
/// cushion's surface into pixels: `TreemapBitmapRasterizer` (the live treemap render
/// path) and `TreemapCushionRenderer` (the Kinds pane's per-row color swatch preview).
/// Both need the identical brightness formula for their cushions to look consistent;
/// keeping it in one place means a future tweak to the lighting model only has one
/// spot to change.
nonisolated enum TreemapCushionLighting {
    static let ambient: Double = 0.15
    static let baseBrightness: Double = 1.8

    // A light source at (-1, -1, 10) - upper-left, tilted steeply toward the viewer -
    // normalized once here rather than recomputed by every caller.
    private static let lightLength: Double = (1.0 + 1.0 + 100.0).squareRoot()
    static let lightX: Double = -1 / lightLength
    static let lightY: Double = -1 / lightLength
    static let lightZ: Double = 10 / lightLength

    /// `normalX`/`normalY` are the cushion surface's slope at this point, i.e.
    /// `-(2 * surface[0] * pointX + surface[2])` and the equivalent for Y.
    static func brightness(normalX: Double, normalY: Double) -> Double {
        let cosine: Double = (normalX * lightX + normalY * lightY + lightZ)
            / sqrt(normalX * normalX + normalY * normalY + 1)
        return max(ambient, (1 - ambient) * cosine + ambient) * (2.5 / baseBrightness)
    }
}
