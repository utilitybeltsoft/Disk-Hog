import Foundation
import Testing
@testable import disk_hog

@MainActor
struct TreemapSelectionOriginTests {
    @Test func ordinarySelectionsDoNotRequestTreeReveal() {
        let coordinator = ScanWindowSelectionCoordinator()
        let item = DiskItem(url: URL(fileURLWithPath: "/fixture/file"))
        coordinator.setSelectedItem(item)
        #expect(coordinator.treemapRevealRequest == 0)
        #expect(coordinator.selectionOrigin == .other)
    }

    @Test func directTreemapSelectionRequestsRevealEvenForSameItem() {
        let coordinator = ScanWindowSelectionCoordinator()
        let item = DiskItem(url: URL(fileURLWithPath: "/fixture/file"))
        coordinator.setSelectedItem(item)
        coordinator.setSelectedItem(item, origin: .treemap)
        #expect(coordinator.treemapRevealRequest == 1)
        #expect(coordinator.selectionOrigin == .treemap)
        coordinator.setSelectedItem(item, origin: .treemap)
        #expect(coordinator.treemapRevealRequest == 2)
        coordinator.setSelectedItem(item) // Zoom synchronization is not another click.
        #expect(coordinator.treemapRevealRequest == 2)
    }

    @Test func syntheticSpaceDoesNotRequestANonexistentTreeRow() {
        let coordinator = ScanWindowSelectionCoordinator()
        let item = DiskItem(url: URL(fileURLWithPath: "/fixture"), itemType: .freeSpace)
        coordinator.setSelectedItem(item, origin: .treemap)
        #expect(coordinator.treemapRevealRequest == 0)
        #expect(coordinator.selectedItem == item)
    }

    @Test func directSelectionCarriesAncestorsAndDoesNotAffectOtherWindows() {
        let coordinator = ScanWindowSelectionCoordinator()
        let other = ScanWindowSelectionCoordinator()
        let parent = DiskItem(url: URL(fileURLWithPath: "/fixture"), isDirectory: true)
        let item = DiskItem(url: URL(fileURLWithPath: "/fixture/file"))
        coordinator.setSelectedItem(item, ancestorChain: [parent], origin: .treemap)
        #expect(coordinator.lastKnownAncestorChain == [parent])
        #expect(other.treemapRevealRequest == 0)
        #expect(other.selectedItem == nil)
    }
}
