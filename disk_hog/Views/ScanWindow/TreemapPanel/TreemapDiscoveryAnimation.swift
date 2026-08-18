import AppKit

@MainActor
final class TreemapDiscoveryAnimation {
    private var startDate: Date?
    private var startRect: NSRect = .zero
    private var targetRect: NSRect = .zero
    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    func start(
        from startRect: NSRect,
        to targetRect: NSRect,
        requestRedraw: @escaping @MainActor () -> Void
    ) {
        self.startRect = startRect
        self.targetRect = targetRect
        startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.advance(requestRedraw: requestRedraw)
            }
        }
        requestRedraw()
    }

    func draw() {
        guard let startDate else { return }
        let progress: CGFloat = progress(since: startDate)
        let easedProgress: CGFloat = 1 - pow(1 - progress, 3)
        let currentRect: NSRect = interpolatedRect(
            from: startRect,
            to: targetRect,
            progress: easedProgress
        )

        NSColor.yellow.withAlphaComponent(0.8 * (1 - progress)).setStroke()
        let guidePath: NSBezierPath = NSBezierPath()
        for (start, end) in zip(rectCorners(startRect), rectCorners(targetRect)) {
            guidePath.move(to: start)
            guidePath.line(to: end)
        }
        guidePath.lineWidth = 1
        guidePath.stroke()

        NSColor.yellow.withAlphaComponent(0.95).setStroke()
        let focusPath: NSBezierPath = NSBezierPath(rect: currentRect.insetBy(dx: 1, dy: 1))
        focusPath.lineWidth = 2
        focusPath.stroke()
    }

    private func advance(requestRedraw: @escaping @MainActor () -> Void) {
        guard let startDate else { return }
        requestRedraw()
        if progress(since: startDate) == 1 {
            timer?.invalidate()
            timer = nil
            self.startDate = nil
        }
    }

    private func progress(since startDate: Date) -> CGFloat {
        min(CGFloat(Date().timeIntervalSince(startDate) / 1.1), 1)
    }

    private func rectCorners(_ rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY)
        ]
    }

    private func interpolatedRect(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
}
