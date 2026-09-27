import AppKit
import SwiftUI

/// Full-width path segments in a horizontally scrollable document. The document
/// is sized independently of the viewport, and the current folder is revealed
/// after the viewport has received its final layout size.
struct BreadcrumbScrollView: NSViewRepresentable {
    let zoomPath: [DiskItem]
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> BreadcrumbNSScrollView {
        let scrollView = BreadcrumbNSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        scrollView.documentView = NSView()
        context.coordinator.scrollView = scrollView
        context.coordinator.rebuildIfNeeded(zoomPath: zoomPath)
        return scrollView
    }

    func updateNSView(_ nsView: BreadcrumbNSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.rebuildIfNeeded(zoomPath: zoomPath)
    }

    // Reports an exact intrinsic height back to SwiftUI instead of letting it guess -
    // the very first SwiftUI-only attempt at this row ballooned to fill all available
    // height because nothing constrained it. Width stays flexible (fills whatever's
    // proposed); height is fixed to the button row plus the always-reserved scroller
    // track, so the row never resizes depending on path length or scroller state.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BreadcrumbNSScrollView, context: Context) -> CGSize? {
        let contentHeight: CGFloat = max(nsView.documentView?.frame.height ?? 0, ScanWindowMetrics.tableRowHeight)
        let scrollerHeight: CGFloat = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        return CGSize(width: proposal.width ?? contentHeight, height: contentHeight + scrollerHeight)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        weak var scrollView: BreadcrumbNSScrollView?
        private var lastPathIDs: [DiskItemID] = []

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        func rebuildIfNeeded(zoomPath: [DiskItem]) {
            let newIDs: [DiskItemID] = zoomPath.map(\.id)
            guard newIDs != lastPathIDs else { return }
            lastPathIDs = newIDs

            guard let scrollView, let documentView = scrollView.documentView else { return }
            documentView.subviews.forEach { $0.removeFromSuperview() }
            var nextX: CGFloat = 0
            let rowHeight: CGFloat = ScanWindowMetrics.tableRowHeight

            for (index, item) in zoomPath.enumerated() {
                if index > 0 {
                    let chevron: NSImageView = NSImageView(
                        image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage()
                    )
                    chevron.symbolConfiguration = .init(pointSize: ScanWindowMetrics.statusFieldFontSize - 1, weight: .regular)
                    chevron.setAccessibilityElement(false)
                    chevron.contentTintColor = .secondaryLabelColor
                    chevron.frame = NSRect(x: nextX, y: 0, width: 8, height: rowHeight)
                    documentView.addSubview(chevron)
                    nextX += 12
                }
                let button: NSButton = NSButton(title: item.displayName, target: self, action: #selector(segmentClicked(_:)))
                button.tag = index
                button.isBordered = false
                button.focusRingType = .default
                button.setAccessibilityHelp(item.path)
                button.setAccessibilityValue(index == zoomPath.indices.last ? String(localized: "Current folder") : nil)
                button.lineBreakMode = .byClipping
                button.font = NSFont.systemFont(ofSize: ScanWindowMetrics.statusFieldFontSize)
                button.toolTip = item.path
                button.attributedTitle = NSAttributedString(
                    string: item.displayName,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: ScanWindowMetrics.statusFieldFontSize),
                        .foregroundColor: index == zoomPath.indices.last ? NSColor.labelColor : NSColor.secondaryLabelColor
                    ]
                )
                // Measure the full title explicitly. Stack fitting/compression must
                // never decide how much of a folder name belongs in the document.
                let width = ceil(max(button.cell?.cellSize.width ?? 0, button.attributedTitle.size().width + 8))
                button.frame = NSRect(x: nextX, y: 0, width: width, height: rowHeight)
                documentView.addSubview(button)
                nextX += width + 4
            }

            documentView.setFrameSize(NSSize(width: max(0, nextX - 4), height: rowHeight))
            scrollView.revealCurrentFolder()
        }

        @objc private func segmentClicked(_ sender: NSButton) {
            onSelect(sender.tag)
        }
    }
}

final class BreadcrumbNSScrollView: NSScrollView {
    private var needsReveal = false
    private var lastViewportSize: NSSize = .zero

    func revealCurrentFolder() {
        needsReveal = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let viewportSize = contentView.bounds.size
        guard needsReveal || viewportSize != lastViewportSize else { return }
        needsReveal = false
        lastViewportSize = viewportSize
        let maxX = max(0, (documentView?.frame.width ?? 0) - viewportSize.width)
        contentView.scroll(to: NSPoint(x: maxX, y: 0))
        reflectScrolledClipView(contentView)
    }
}
