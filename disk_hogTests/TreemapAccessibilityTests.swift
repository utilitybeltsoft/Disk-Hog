import AppKit
import Testing
@testable import disk_hog

@MainActor
struct TreemapAccessibilityTests {
    @Test func selectionAndActionsTrackTheCurrentItem() throws {
        let view = ZStyleTreemapNSView()
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .group)
        #expect(view.accessibilityLabel() == String(localized: "Treemap"))
        #expect(!view.accessibilityPerformPress())
        let item = DiskItem(url: URL(fileURLWithPath: "/fixture/report"), allocatedSizeValue: 4096)
        view.applySelectedItem(item)
        let value = try #require(view.accessibilityValue() as? String)
        #expect(value.contains("report"))
        #expect(value.contains("/fixture/report"))
        #expect(value.contains(ByteCountFormatter.string(fromByteCount: 4096, countStyle: .file)))
        var zoomedItem: DiskItem?
        view.onZoomIn = { item, _ in zoomedItem = item }
        #expect(view.accessibilityPerformPress())
        #expect(zoomedItem == item)
        var wentBack = false
        view.onZoomOut = { wentBack = true }
        let actions = try #require(view.accessibilityCustomActions())
        let left = try #require(actions.first { $0.name == String(localized: "Select left item") })
        #expect(left.handler?() == false) // No rendered layout to navigate yet.
        let back = try #require(actions.first { $0.name == String(localized: "Back") })
        #expect(back.handler?() == true)
        #expect(wentBack)
        view.applySelectedItem(nil)
        #expect(view.accessibilityValue() as? String == String(localized: "No selection"))
        #expect(!view.accessibilityPerformPress())
        #expect(!view.accessibilityPerformShowMenu())
    }
}
