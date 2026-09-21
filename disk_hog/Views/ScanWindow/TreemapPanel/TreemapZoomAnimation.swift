import AppKit

/// Animates the transition between two treemap bitmaps across a zoom in/out,
/// so the folder being zoomed into (or out of) visibly grows to fill the view
/// (or shrinks back into its place) instead of an instant cut. Mirrors
/// `TreemapDiscoveryAnimation`'s mechanism (a manual `Timer`-driven, eased
/// redraw loop) rather than Core Animation, since that's the one animation
/// pattern already established in this app.
@MainActor
final class TreemapZoomAnimation {
    private static let motionDuration: TimeInterval = 0.32
    private static let crossfadeDuration: TimeInterval = 0.16
    private static let abandonAfter: TimeInterval = 1.5

    private var transition: TreemapZoomTransition?
    private var startDate: Date?
    private var timer: Timer?
    private var requestRedraw: (@MainActor () -> Void)?

    /// True as soon as a transition is being tracked, even before playback has
    /// actually started (a zoom-in waits for the destination bitmap to arrive
    /// before there's anything new to paint). Callers that need to feed in a
    /// just-completed render (`resolvePendingBitmap`) should check this.
    var isActive: Bool { transition != nil }
    /// True only once frames are actually being painted. Callers deciding what
    /// to draw/suppress each frame should check this, not `isActive` - while
    /// still waiting, the ordinary (pre-animation) draw path must keep running
    /// so the old bitmap stays visible, exactly like before this animation
    /// existed; routing to `draw(in:)` during that wait would paint nothing.
    var isPlaying: Bool { startDate != nil }

    deinit {
        timer?.invalidate()
    }

    func start(_ transition: TreemapZoomTransition, requestRedraw: @escaping @MainActor () -> Void) {
        cancel()
        self.transition = transition
        self.requestRedraw = requestRedraw
        NSLog("DIAGHOG zoomAnim start direction=%@ hasToBitmap=%@ pendingAnchorItem=%@",
              transition.direction == .zoomIn ? "zoomIn" : "zoomOut",
              transition.toBitmap == nil ? "no" : "yes",
              transition.pendingAnchorItem?.path ?? "nil")
        if transition.toBitmap != nil {
            beginPlayback()
        } else {
            // Nothing paints differently from today's "stale bitmap keeps showing"
            // yet (the ordinary draw path keeps running throughout, since isPlaying
            // is still false); wait for resolvePendingBitmap(...) or this deadline.
            timer = Timer.scheduledTimer(withTimeInterval: Self.abandonAfter, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.startDate == nil else { return }
                    NSLog("DIAGHOG zoomAnim abandonTimer fired - never got a destination bitmap")
                    let requestRedraw: (@MainActor () -> Void)? = self.requestRedraw
                    self.cancel()
                    // Cancelling alone doesn't repaint anything - without this, a view
                    // that happened to stop receiving any other redraw trigger (mouse
                    // movement, resize, ...) could be left showing whatever the last
                    // painted frame was indefinitely.
                    requestRedraw?()
                }
            }
        }
    }

    /// Called from `onRenderedImageReady` while a transition is still waiting
    /// on data (a zoom-out cache miss, or a zoom-in's crossfade target).
    func resolvePendingBitmap(
        toBitmap: NSBitmapImageRep,
        toBounds: NSRect,
        anchorEntryLookup: (DiskItem) -> NSRect?
    ) {
        guard var transition else {
            return
        }
        if transition.toBitmap == nil {
            transition.toBitmap = toBitmap
            transition.toBounds = toBounds
            if transition.anchorRect == nil, let pendingAnchorItem = transition.pendingAnchorItem {
                transition.anchorRect = anchorEntryLookup(pendingAnchorItem)
            }
            self.transition = transition
        }
        NSLog("DIAGHOG zoomAnim resolvePendingBitmap anchorRect=%@ startDate=%@",
              transition.anchorRect == nil ? "nil" : "set", startDate == nil ? "nil" : "set")
        guard transition.anchorRect != nil else {
            return
        }
        if startDate == nil {
            beginPlayback()
        }
    }

    func cancel() {
        if transition != nil {
            NSLog("DIAGHOG zoomAnim cancel wasPlaying=%@", startDate == nil ? "no" : "yes")
        }
        timer?.invalidate()
        timer = nil
        transition = nil
        startDate = nil
        requestRedraw = nil
    }

    /// Paints the current frame into `bounds`. Self-cancels once finished or
    /// abandoned; callers just check `isActive` before/after.
    func draw(in bounds: NSRect) {
        guard let transition, let startDate else {
            return
        }
        let elapsed: TimeInterval = Date().timeIntervalSince(startDate)
        let motionProgress: CGFloat = min(CGFloat(elapsed / Self.motionDuration), 1)
        let eased: CGFloat = 1 - pow(1 - motionProgress, 3)

        switch transition.direction {
        case .zoomIn:
            let source: NSRect = Self.lerp(transition.fromBounds, transition.anchorRect!, eased)
            TreemapViewPainter.drawRenderedImage(transition.fromBitmap, destinationRect: bounds, sourceRect: source, fraction: 1)
            if let toBitmap = transition.toBitmap, let toBounds = transition.toBounds {
                let crossfade: CGFloat = Self.crossfadeProgress(elapsed: elapsed)
                if crossfade > 0 {
                    TreemapViewPainter.drawRenderedImage(toBitmap, destinationRect: bounds, sourceRect: toBounds, fraction: crossfade)
                }
                if crossfade >= 1 {
                    cancel()
                }
            } else if elapsed > Self.abandonAfter {
                cancel()
            }
        case .zoomOut:
            guard let toBitmap = transition.toBitmap, let toBounds = transition.toBounds else {
                return
            }
            TreemapViewPainter.drawRenderedImage(toBitmap, destinationRect: bounds, sourceRect: toBounds, fraction: 1)
            let destination: NSRect = Self.lerp(bounds, transition.anchorRect!, eased)
            TreemapViewPainter.drawRenderedImage(transition.fromBitmap, destinationRect: destination, sourceRect: transition.fromBounds, fraction: 1 - eased)
            if motionProgress >= 1 {
                cancel()
            }
        }
    }

    private func beginPlayback() {
        startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.isActive else {
                    timer.invalidate()
                    return
                }
                self.requestRedraw?()
            }
        }
        requestRedraw?()
    }

    private static func crossfadeProgress(elapsed: TimeInterval) -> CGFloat {
        let start: TimeInterval = motionDuration - crossfadeDuration
        return CGFloat(min(max((elapsed - start) / crossfadeDuration, 0), 1))
    }

    private static func lerp(_ from: NSRect, _ to: NSRect, _ p: CGFloat) -> NSRect {
        NSRect(
            x: from.minX + (to.minX - from.minX) * p,
            y: from.minY + (to.minY - from.minY) * p,
            width: from.width + (to.width - from.width) * p,
            height: from.height + (to.height - from.height) * p
        )
    }
}
