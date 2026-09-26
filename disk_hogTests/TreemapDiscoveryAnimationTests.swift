import AppKit
import Testing
@testable import disk_hog

@MainActor
struct TreemapDiscoveryAnimationTests {
    let bounds = NSRect(x: 0, y: 0, width: 800, height: 400)

    @Test func usesParentWhenItProvidesVisibleMotion() {
        let target = NSRect(x: 100, y: 100, width: 100, height: 100)
        #expect(TreemapDiscoveryAnimation.startRect(target: target, parent: bounds, bounds: bounds) == bounds)
    }

    @Test func identicalOrNearlyIdenticalParentGetsExpandedOutline() {
        let target = NSRect(x: 100, y: 100, width: 200, height: 100)
        for parent in [target, target.insetBy(dx: -2, dy: -2)] {
            #expect(TreemapDiscoveryAnimation.startRect(target: target, parent: parent, bounds: bounds)
                    == target.insetBy(dx: -24, dy: -24))
        }
    }

    @Test func fullPaneUsesStationaryHighlightGeometry() {
        #expect(TreemapDiscoveryAnimation.startRect(target: bounds, parent: bounds, bounds: bounds) == bounds)
        #expect(TreemapDiscoveryAnimation.startRect(target: bounds, parent: nil, bounds: bounds) == bounds)
    }

    @Test func edgeHaloStaysInsidePane() {
        let target = NSRect(x: 0, y: 0, width: 30, height: 30)
        let start = TreemapDiscoveryAnimation.startRect(target: target, parent: nil, bounds: bounds)
        #expect(bounds.contains(start))
        #expect(start.width > target.width)
        #expect(start.height > target.height)
    }
}
