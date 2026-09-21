import AppKit
import Testing
@testable import disk_hog

@MainActor
struct BreadcrumbLayoutTests {
    @Test func currentFolderRemainsFullyVisibleAtNarrowWidths() {
        let scroll = BreadcrumbNSScrollView(frame: NSRect(x: 0, y: 0, width: 233, height: 38))
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.borderType = .noBorder
        scroll.documentView = NSView()
        var selection: Int?
        let coordinator = BreadcrumbScrollView.Coordinator { selection = $0 }
        coordinator.scrollView = scroll
        let items = ["ext-hd", "TV episodes", "Hill Street Blues - Season 1"].map {
            DiskItem(url: URL(fileURLWithPath: "/\($0)"), isDirectory: true)
        }
        coordinator.rebuildIfNeeded(zoomPath: items)
        scroll.layoutSubtreeIfNeeded()
        let buttons = scroll.documentView!.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.count == 3)
        for button in buttons {
            #expect(button.frame.width >= button.attributedTitle.size().width + 8)
        }
        let current = buttons.last!
        #expect(scroll.contentView.bounds.contains(current.frame))

        scroll.setFrameSize(NSSize(width: 190, height: 38))
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.contains(current.frame))

        scroll.contentView.scroll(to: .zero)
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.minX == 0)
        current.performClick(nil)
        #expect(selection == 2)

        coordinator.rebuildIfNeeded(zoomPath: Array(items.prefix(1)))
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.minX == 0)
    }
}
