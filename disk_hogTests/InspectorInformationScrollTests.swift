import AppKit
import SwiftUI
import Testing
@testable import disk_hog

@MainActor
struct InspectorInformationScrollTests {
    @Test func resizingKeepsDocumentWidthAndLeftInsetWithScrollableOverflow() {
        let probe = NSView()
        let host = NSHostingView(rootView: InspectorInformationScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<100) { Text("Information row \($0)") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InformationLayoutProbe(view: probe))
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        for width in [720.0, 1000.0, 700.0] {
            window.setContentSize(NSSize(width: width, height: 360))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            guard let scroll = scrollView(in: host), let document = scroll.documentView else {
                Issue.record("Missing native information scroll document")
                return
            }
            #expect(scroll.hasVerticalScroller && scroll.hasHorizontalScroller)
            #expect(scroll.scrollerStyle == .legacy)
            #expect(document.frame.height > scroll.contentView.bounds.height)
            #expect(scroll.verticalScroller?.isHidden == false)
            #expect(abs(probe.bounds.width - 680) < 1)
            #expect(abs(probe.convert(.zero, to: document).x - 10) < 1)
            #expect(abs(scroll.contentView.bounds.minX) < 1)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(scroll.contentView.bounds.minY > 0)
            if document.frame.width > scroll.contentView.bounds.width {
                #expect(scroll.horizontalScroller?.isHidden == false)
                scroll.contentView.scroll(to: NSPoint(x: 10, y: 150))
                scroll.reflectScrolledClipView(scroll.contentView)
                #expect(scroll.contentView.bounds.minX > 0)
            }
            scroll.contentView.scroll(to: .zero)
        }
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { scrollView(in: $0) }.first
    }
}

private struct InformationLayoutProbe: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
