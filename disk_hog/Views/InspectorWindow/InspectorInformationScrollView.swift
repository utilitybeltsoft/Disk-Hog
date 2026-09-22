import AppKit
import SwiftUI

/// Resize the viewport, not the information document or its column layout.
struct InspectorInformationScrollView<Content: View>: NSViewRepresentable {
    static var documentWidth: CGFloat { 680 }
    @ViewBuilder var content: Content

    private var document: AnyView {
        AnyView(content.frame(width: Self.documentWidth, alignment: .leading)
            .padding(10).fixedSize(horizontal: true, vertical: true))
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        // Real, reserved scrollbar tracks: never overlay information or depend
        // on the system's transient overlay-scroller visibility.
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = false
        let host = NSHostingView(rootView: document)
        scroll.documentView = host
        updateDocument(host)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        host.rootView = document
        updateDocument(host)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // The viewport is flexible; the document's fitting height must never
        // become the inspector's minimum height.
        CGSize(width: proposal.width ?? Self.documentWidth + 20, height: proposal.height ?? 360)
    }

    private func updateDocument(_ host: NSHostingView<AnyView>) {
        // Only content updates change the document. Resizing its viewport never
        // feeds a proposed width/height back into SwiftUI's information layout.
        let size = host.fittingSize
        host.setFrameSize(NSSize(width: Self.documentWidth + 20, height: ceil(size.height)))
    }
}
