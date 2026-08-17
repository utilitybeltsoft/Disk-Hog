import AppKit
import SwiftUI

struct MagnifiedTreemapCropView: NSViewRepresentable {
    let sourceView: ZStyleTreemapNSView?
    let sourceRect: NSRect
    let contentRevision: Int
    var selectionRect: NSRect? = nil

    func makeNSView(context: Context) -> TreemapCropPreviewNSView {
        TreemapCropPreviewNSView()
    }

    func updateNSView(_ nsView: TreemapCropPreviewNSView, context: Context) {
        nsView.configure(
            sourceView: sourceView,
            sourceRect: sourceRect,
            selectionRect: selectionRect
        )
        nsView.contentRevision = contentRevision
    }
}

final class TreemapCropPreviewNSView: NSView {
    private weak var sourceView: ZStyleTreemapNSView?
    private var sourceRect: NSRect = .zero
    private var selectionRect: NSRect?
    var contentRevision: Int = 0

    override var isFlipped: Bool { true }

    func configure(
        sourceView: ZStyleTreemapNSView?,
        sourceRect: NSRect,
        selectionRect: NSRect?
    ) {
        self.sourceView = sourceView
        self.sourceRect = sourceRect
        self.selectionRect = selectionRect
        needsDisplay = true
    }

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
        drawSelection(in: destinationRect, sourceRect: sourceRect, scale: scale)
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
}
