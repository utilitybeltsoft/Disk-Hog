import AppKit
import SwiftUI

/// An AppKit-backed replacement for a SwiftUI `ScrollView` breadcrumb trail. Three
/// SwiftUI-only attempts at this (a hand-rolled offset/drag row, then toggling the
/// native `ScrollView` indicator) each broke something different - a `GeometryReader`
/// ballooning the row's height, an offset/frame interaction overlapping the toolbar
/// buttons to its left, and finally `ScrollView`'s indicator only reserving space when
/// it's actually needed, making the row's height jump depending on path length. A real
/// `NSScrollView` sidesteps all of that: `scrollerStyle = .legacy` always reserves the
/// scroller's track (just inactive/undraggable when nothing overflows), and scrolling
/// is done directly against the clip view instead of `ScrollViewReader`'s anchor-based
/// `scrollTo`, which was landing short of the true end.
struct BreadcrumbScrollView: NSViewRepresentable {
    let zoomPath: [DiskItem]
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let stackView: NSStackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = true

        scrollView.documentView = stackView
        context.coordinator.stackView = stackView
        context.coordinator.scrollView = scrollView
        context.coordinator.rebuildIfNeeded(zoomPath: zoomPath, animated: false)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.rebuildIfNeeded(zoomPath: zoomPath, animated: true)
    }

    // Reports an exact intrinsic height back to SwiftUI instead of letting it guess -
    // the very first SwiftUI-only attempt at this row ballooned to fill all available
    // height because nothing constrained it. Width stays flexible (fills whatever's
    // proposed); height is fixed to the button row plus the always-reserved scroller
    // track, so the row never resizes depending on path length or scroller state.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let contentHeight: CGFloat = context.coordinator.stackView?.fittingSize.height ?? ScanWindowMetrics.tableRowHeight
        let scrollerHeight: CGFloat = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        return CGSize(width: proposal.width ?? contentHeight, height: contentHeight + scrollerHeight)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        weak var stackView: NSStackView?
        weak var scrollView: NSScrollView?
        private var lastPathIDs: [DiskItemID] = []

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        func rebuildIfNeeded(zoomPath: [DiskItem], animated: Bool) {
            let newIDs: [DiskItemID] = zoomPath.map(\.id)
            guard newIDs != lastPathIDs else { return }
            lastPathIDs = newIDs

            guard let stackView else { return }
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            for (index, item) in zoomPath.enumerated() {
                if index > 0 {
                    let chevron: NSImageView = NSImageView(
                        image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage()
                    )
                    chevron.symbolConfiguration = .init(pointSize: ScanWindowMetrics.statusFieldFontSize - 1, weight: .regular)
                    chevron.contentTintColor = .secondaryLabelColor
                    stackView.addArrangedSubview(chevron)
                }
                let button: NSButton = NSButton(title: item.displayName, target: self, action: #selector(segmentClicked(_:)))
                button.tag = index
                button.isBordered = false
                button.focusRingType = .none
                button.attributedTitle = NSAttributedString(
                    string: item.displayName,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: ScanWindowMetrics.statusFieldFontSize),
                        .foregroundColor: index == zoomPath.indices.last ? NSColor.labelColor : NSColor.secondaryLabelColor
                    ]
                )
                stackView.addArrangedSubview(button)
            }

            stackView.frame.size = stackView.fittingSize
            scrollToEnd(animated: animated)
        }

        private func scrollToEnd(animated: Bool) {
            guard let stackView, let scrollView else { return }
            let maxX: CGFloat = max(0, stackView.frame.width - scrollView.contentView.bounds.width)
            let destination: NSPoint = NSPoint(x: maxX, y: 0)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.allowsImplicitAnimation = true
                    scrollView.contentView.animator().setBoundsOrigin(destination)
                } completionHandler: { [weak scrollView] in
                    guard let scrollView else { return }
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(destination)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        @objc private func segmentClicked(_ sender: NSButton) {
            onSelect(sender.tag)
        }
    }
}
