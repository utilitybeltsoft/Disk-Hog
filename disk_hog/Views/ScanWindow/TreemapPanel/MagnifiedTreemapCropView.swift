import AppKit
import SwiftUI

struct MagnifiedTreemapCropView: NSViewRepresentable {
    let sourceView: ZStyleTreemapNSView?
    let sourceRect: NSRect
    let contentRevision: Int
    var selectionRect: NSRect? = nil
    var animationID: DiskItemID? = nil

    func makeNSView(context: Context) -> TreemapCropPreviewNSView {
        TreemapCropPreviewNSView()
    }

    func updateNSView(_ nsView: TreemapCropPreviewNSView, context: Context) {
        nsView.configure(
            sourceView: sourceView,
            sourceRect: sourceRect,
            selectionRect: selectionRect,
            animationID: animationID
        )
        nsView.contentRevision = contentRevision
    }
}

final class TreemapCropPreviewNSView: NSView {
    private weak var sourceView: ZStyleTreemapNSView?
    private var sourceRect: NSRect = .zero
    private var displayedSourceRect: NSRect = .zero
    private var selectionRect: NSRect?
    private var animationID: DiskItemID?
    private var animationStartDate: Date?
    private var animationStartRect: NSRect = .zero
    private var animationTimer: Timer?
    var contentRevision: Int = 0

    override var isFlipped: Bool { true }

    deinit { animationTimer?.invalidate() }

    func configure(
        sourceView: ZStyleTreemapNSView?,
        sourceRect: NSRect,
        selectionRect: NSRect?,
        animationID: DiskItemID?
    ) {
        if animationID == self.animationID, sourceRect.equalTo(self.sourceRect) {
            self.sourceView = sourceView
            self.selectionRect = selectionRect
            needsDisplay = true
            return
        }
        let shouldAnimate: Bool = animationID != nil && animationID != self.animationID
        self.sourceView = sourceView
        self.sourceRect = sourceRect
        self.selectionRect = selectionRect
        self.animationID = animationID
        animationTimer?.invalidate()
        animationTimer = nil
        guard shouldAnimate, let sourceView, sourceView.bounds.isEmpty == false else {
            displayedSourceRect = sourceRect
            needsDisplay = true
            return
        }
        animationStartRect = sourceView.bounds
        displayedSourceRect = animationStartRect
        animationStartDate = Date()
        animationTimer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(advanceAnimation), userInfo: nil, repeats: true)
        needsDisplay = true
    }

    @objc private func advanceAnimation() {
        guard let animationStartDate else { return }
        let progress: CGFloat = min(CGFloat(Date().timeIntervalSince(animationStartDate) / 0.35), 1)
        let easedProgress: CGFloat = 1 - pow(1 - progress, 3)
        displayedSourceRect = interpolatedRect(from: animationStartRect, to: sourceRect, progress: easedProgress)
        needsDisplay = true
        if progress == 1 {
            animationTimer?.invalidate()
            animationTimer = nil
            self.animationStartDate = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let drawnSourceRect: NSRect = displayedSourceRect.isEmpty ? sourceRect : displayedSourceRect
        guard drawnSourceRect.width > 0,
              drawnSourceRect.height > 0,
              let image: NSImage = sourceView?.cachedTreemapImage() else {
            return
        }

        let destinationBounds: NSRect = bounds.insetBy(dx: 1, dy: 1)
        let scale: CGFloat = min(
            destinationBounds.width / drawnSourceRect.width,
            destinationBounds.height / drawnSourceRect.height
        )
        guard scale.isFinite, scale > 0 else { return }

        let destinationSize: NSSize = NSSize(
            width: drawnSourceRect.width * scale,
            height: drawnSourceRect.height * scale
        )
        let destinationRect: NSRect = NSRect(
            x: destinationBounds.midX - destinationSize.width / 2,
            y: destinationBounds.midY - destinationSize.height / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )
        let imageSourceRect: NSRect = NSRect(
            x: drawnSourceRect.minX,
            y: image.size.height - drawnSourceRect.maxY,
            width: drawnSourceRect.width,
            height: drawnSourceRect.height
        )
        image.draw(
            in: destinationRect,
            from: imageSourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        drawSelection(in: destinationRect, sourceRect: drawnSourceRect, scale: scale)
    }

    private func drawSelection(in destinationRect: NSRect, sourceRect: NSRect, scale: CGFloat) {
        guard let selectionRect else { return }
        let visibleRect: NSRect = selectionRect.intersection(sourceRect)
        guard visibleRect.isEmpty == false else { return }
        let previewRect: NSRect = NSRect(
            x: destinationRect.minX + (visibleRect.minX - sourceRect.minX) * scale,
            y: destinationRect.minY + (visibleRect.minY - sourceRect.minY) * scale,
            width: visibleRect.width * scale,
            height: visibleRect.height * scale
        )
        NSColor.yellow.setFill()
        previewRect.fill()
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
