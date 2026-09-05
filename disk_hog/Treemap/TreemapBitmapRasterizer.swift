import Foundation

nonisolated struct TreemapCushionSnapshot: Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let surface: [Double]
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated enum TreemapBitmapRasterizer {
    static func render(
        snapshots: [TreemapCushionSnapshot],
        pixelsWide: Int,
        pixelsHigh: Int,
        scale: Double
    ) -> Data {
        render(
            snapshots: snapshots,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            scale: scale,
            isCancelled: { false }
        )!
    }

    static func renderIfNotCancelled(
        snapshots: [TreemapCushionSnapshot],
        pixelsWide: Int,
        pixelsHigh: Int,
        scale: Double
    ) -> Data? {
        render(
            snapshots: snapshots,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            scale: scale,
            isCancelled: { Task.isCancelled }
        )
    }

    private static func render(
        snapshots: [TreemapCushionSnapshot],
        pixelsWide: Int,
        pixelsHigh: Int,
        scale: Double,
        isCancelled: () -> Bool
    ) -> Data? {
        var pixels: Data = Data(count: pixelsWide * pixelsHigh * 3)
        var completed: Bool = true
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let pixels: UnsafeMutablePointer<UInt8> = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                completed = false
                return
            }
            for snapshot: TreemapCushionSnapshot in snapshots {
                guard isCancelled() == false,
                      render(snapshot, pixels: pixels, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, scale: scale, isCancelled: isCancelled) else {
                    completed = false
                    return
                }
            }
        }
        return completed ? pixels : nil
    }

    private static func render(
        _ snapshot: TreemapCushionSnapshot,
        pixels: UnsafeMutablePointer<UInt8>,
        pixelsWide: Int,
        pixelsHigh: Int,
        scale: Double,
        isCancelled: () -> Bool
    ) -> Bool {
        guard snapshot.width > 0, snapshot.height > 0, snapshot.surface.count == 4 else { return true }
        let xStart: Int = max(0, min(pixelsWide, Int((snapshot.x * scale).rounded(.down))))
        let xEnd: Int = max(xStart, min(pixelsWide, Int(((snapshot.x + snapshot.width) * scale).rounded(.up))))
        let yStart: Int = max(0, min(pixelsHigh, Int((snapshot.y * scale).rounded(.down))))
        let yEnd: Int = max(yStart, min(pixelsHigh, Int(((snapshot.y + snapshot.height) * scale).rounded(.up))))
        guard xStart < xEnd, yStart < yEnd else { return true }

        for y: Int in yStart..<yEnd {
            if y.isMultiple(of: 64), isCancelled() {
                return false
            }
            let pointY: Double = (Double(y) + 0.5) / scale
            let normalY: Double = -(2 * snapshot.surface[1] * pointY + snapshot.surface[3])
            for x: Int in xStart..<xEnd {
                let pointX: Double = (Double(x) + 0.5) / scale
                let normalX: Double = -(2 * snapshot.surface[0] * pointX + snapshot.surface[2])
                let brightness: Double = TreemapCushionLighting.brightness(normalX: normalX, normalY: normalY)
                let offset: Int = (y * pixelsWide + x) * 3
                var red: Double = snapshot.red * brightness
                var green: Double = snapshot.green * brightness
                var blue: Double = snapshot.blue * brightness
                TreemapColorNormalization.distributeOverflow(
                    red: &red,
                    green: &green,
                    blue: &blue
                )
                pixels[offset] = TreemapColorNormalization.byte(from: red)
                pixels[offset + 1] = TreemapColorNormalization.byte(from: green)
                pixels[offset + 2] = TreemapColorNormalization.byte(from: blue)
            }
        }
        return true
    }
}
