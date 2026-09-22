import AppKit

/// Retains only the outgoing bitmap, never another layout or per-item animation.
@MainActor
final class TreemapResizeAnimation {
    static let duration: TimeInterval = 0.18
    private var bitmap: NSBitmapImageRep?
    private var startedAt: TimeInterval = 0
    private var timer: Timer?
    var isActive: Bool { bitmap != nil }

    deinit { timer?.invalidate() }

    func start(from bitmap: NSBitmapImageRep, reduceMotion: Bool,
               requestRedraw: @escaping @MainActor () -> Void) {
        cancel()
        guard !reduceMotion else { return }
        self.bitmap = bitmap
        startedAt = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ||
                    ProcessInfo.processInfo.systemUptime - self.startedAt >= Self.duration {
                    self.cancel()
                }
                requestRedraw()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        bitmap = nil
    }

    /// The new bitmap is already underneath. Fade the old one away over it.
    func draw(in bounds: NSRect) {
        guard let bitmap else { return }
        let progress = min(max((ProcessInfo.processInfo.systemUptime - startedAt) / Self.duration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        TreemapViewPainter.drawRenderedImage(bitmap, destinationRect: bounds,
                                            sourceRect: nil, fraction: CGFloat(1 - eased))
    }
}
