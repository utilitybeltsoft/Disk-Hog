import Foundation
import Testing
@testable import disk_hog

@MainActor
struct ScanSessionSnapshotTests {
    @Test func spaceProjectionClampsAndRejectsInvalidCapacity() {
        let volume = ScanSource(path: "/fixture", displayName: "fixture", isVolumeRoot: true,
                                totalCapacity: 100, availableCapacity: 40)
        let space = ScanSessionSpaceItems(source: volume, scannedSize: 30)
        #expect(space.free?.allocatedSizeValue == 40)
        #expect(space.other?.allocatedSizeValue == 30)
        #expect(ScanSessionSpaceItems(source: volume, scannedSize: 90).other?.allocatedSizeValue == 0)
        let invalid = ScanSource(path: "/fixture", displayName: "fixture", isVolumeRoot: true,
                                 totalCapacity: 10, availableCapacity: 40)
        #expect(ScanSessionSpaceItems(source: invalid, scannedSize: 0).free == nil)
        let folder = ScanSource(path: "/fixture", displayName: "fixture", isVolumeRoot: false,
                                totalCapacity: 100, availableCapacity: 40)
        #expect(ScanSessionSpaceItems(source: folder, scannedSize: 0).free == nil)
    }

    @Test func subtreeMergePreservesSiblingWithSharedPrefix() {
        let inside = ScanSkippedItem(path: "/scan/a/inside", reason: "old")
        let sibling = ScanSkippedItem(path: "/scan/a-backup/file", reason: "keep")
        let replacement = ScanSkippedItem(path: "/scan/a/new", reason: "new")
        #expect(ScanSessionSnapshot.mergingSkippedItems([inside, sibling], replacingSubtreeAt: "/scan/a",
                                                       with: [replacement]) == [sibling, replacement])
    }

    @Test func sizeChangesAndClearingPreserveAcquisitionHistory() {
        let source = ScanSource(path: "/fixture", displayName: "fixture")
        let root = DiskItem(url: source.url, allocatedSizeValue: 20, logicalSizeValue: 10, isDirectory: true)
        let metrics = TreemapPresentationMetrics(rootItem: root, usePhysicalSize: true)
        var snapshot = ScanSessionSnapshot(source: source)
        snapshot.acceptScan(ScanSessionScanResult(source: source, rootItem: root, presentationMetrics: metrics,
            builtUsingPhysicalSize: true, skippedItems: []), files: 1, folders: 2, usePhysicalSize: true,
            startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2))
        let freshness = snapshot.freshness
        snapshot.acceptSizeMode(ScanSessionSizeModeUpdateResult(rootItem: root, presentationMetrics: metrics,
                                                               selectionPath: root.path, usePhysicalSize: false))
        #expect(snapshot.byteCount == 10)
        #expect(snapshot.freshness == freshness)
        snapshot.clearForScan()
        #expect(snapshot.root == nil)
        #expect(snapshot.metrics == nil)
        #expect(snapshot.freshness == freshness)
    }
}
