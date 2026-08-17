import AppKit
import SwiftUI

struct MagnifiedTreemapCropView: NSViewRepresentable {
    let sourceView: ZStyleTreemapNSView?
    let sourceRect: NSRect
    let contentRevision: Int

    func makeNSView(context: Context) -> TreemapCropPreviewNSView {
        TreemapCropPreviewNSView()
    }

    func updateNSView(_ nsView: TreemapCropPreviewNSView, context: Context) {
        nsView.sourceView = sourceView
        nsView.sourceRect = sourceRect
        nsView.contentRevision = contentRevision
        nsView.needsDisplay = true
    }
}

final class TreemapCropPreviewNSView: NSView {
    weak var sourceView: ZStyleTreemapNSView?
    var sourceRect: NSRect = .zero
    var contentRevision: Int = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard sourceRect.width > 0,
              sourceRect.height > 0,
              let image: NSImage = sourceView?.cachedTreemapImage() else {
            return
        }

        let destinationBounds: NSRect = bounds.insetBy(dx: 1, dy: 1)
        let scale: CGFloat = min(
            destinationBounds.width / sourceRect.width,
            destinationBounds.height / sourceRect.height
        )
        guard scale.isFinite, scale > 0 else { return }

        let destinationSize: NSSize = NSSize(
            width: sourceRect.width * scale,
            height: sourceRect.height * scale
        )
        let destinationRect: NSRect = NSRect(
            x: destinationBounds.midX - destinationSize.width / 2,
            y: destinationBounds.midY - destinationSize.height / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )
        let imageSourceRect: NSRect = NSRect(
            x: sourceRect.minX,
            y: image.size.height - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )
        image.draw(
            in: destinationRect,
            from: imageSourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
}
