import AppKit
import Testing
@testable import disk_hog

@MainActor
struct InspectorWindowSizingTests {
    @Test func undersizedRestoredWindowIsExpandedWithoutMovingTopEdge() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let top = window.frame.maxY
        InspectorWindowSizing.applyMinimum(NSSize(width: 700, height: 360), to: window)
        #expect(window.contentLayoutRect.width >= 700)
        #expect(window.contentLayoutRect.height >= 360)
        #expect(window.frame.maxY == top)
        #expect(InspectorWindowSizing.clamped(NSSize(width: 1, height: 1), minimum: window.minSize) == window.minSize)
    }
}
