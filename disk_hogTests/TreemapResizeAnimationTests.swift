import AppKit
import Testing
@testable import disk_hog

@MainActor
struct TreemapResizeAnimationTests {
    private func bitmap() -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                         bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                         isPlanar: false, colorSpaceName: .deviceRGB,
                         bytesPerRow: 0, bitsPerPixel: 0)!
    }

    @Test func reduceMotionSkipsTransitionAndReleasesPriorBitmap() {
        let animation = TreemapResizeAnimation()
        animation.start(from: bitmap(), reduceMotion: false, requestRedraw: {})
        #expect(animation.isActive)
        animation.start(from: bitmap(), reduceMotion: true, requestRedraw: {})
        #expect(!animation.isActive)
    }

    @Test func cancelReleasesOutgoingBitmap() {
        let animation = TreemapResizeAnimation()
        var outgoing: NSBitmapImageRep? = bitmap()
        weak var retainedBitmap = outgoing
        animation.start(from: outgoing!, reduceMotion: false, requestRedraw: {})
        outgoing = nil
        #expect(retainedBitmap != nil)
        animation.cancel()
        #expect(!animation.isActive)
        #expect(retainedBitmap == nil)
    }

    @Test func completionStopsTimerAndReleasesBitmap() async throws {
        let animation = TreemapResizeAnimation()
        var redraws = 0
        animation.start(from: bitmap(), reduceMotion: false) { redraws += 1 }
        try await Task.sleep(for: .milliseconds(350))
        #expect(!animation.isActive)
        #expect(redraws > 0)
        let completedRedraws = redraws
        try await Task.sleep(for: .milliseconds(100))
        #expect(redraws == completedRedraws)
    }
}
