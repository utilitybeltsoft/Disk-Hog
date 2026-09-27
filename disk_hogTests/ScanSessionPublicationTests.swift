import Combine
import Foundation
import Testing
@testable import disk_hog

@MainActor
struct ScanSessionPublicationTests {
    @Test func treeNotificationsObserveCompleteSnapshots() async throws {
        let worker = PublicationWorker()
        let initialSource = ScanSource(path: worker.source.path, displayName: "Original source", isVolumeRoot: true,
                                       totalCapacity: 100, availableCapacity: 40, scanSettings: worker.source.scanSettings)
        let session = ScanSession(source: initialSource, scanWorker: worker, treeWorker: worker)
        var publications = 0
        var firstFreshness: SnapshotFreshness?
        let subscription = NotificationCenter.default.publisher(for: .scanSessionTreeDidChange).sink { note in
            guard let sender = note.object as? ScanSession, sender === session, let root = session.rootItem else { return }
            publications += 1
            #expect(session.state == .complete)
            #expect(!session.isUpdatingTree)
            #expect(session.presentationMetrics != nil)
            #expect(session.scannedFileCount == root.children.count)
            #expect(session.scannedByteCount == root.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize))
            #expect(session.preferredSelection == root)
            #expect(session.source.displayName == "Accepted source")
            #expect(session.snapshotFreshness.wholeScan != nil)
            #expect(session.freeSpaceItem?.allocatedSizeValue == 40)
            if let firstFreshness { #expect(session.snapshotFreshness == firstFreshness) }
            else { firstFreshness = session.snapshotFreshness }
        }
        defer { subscription.cancel(); session.cancel() }
        session.startScan()
        try await Self.wait { publications == 1 }
        session.delete(try #require(session.rootItem?.children.first), using: .moveToTrash)
        try await Self.wait { publications == 2 }
        session.updateSizeMode(false)
        try await Self.wait { publications == 3 }
        #expect(session.scannedByteCount == 10)
    }

    @Test func inFlightWorkerDoesNotKeepSessionAlive() async throws {
        let worker = RetentionScanWorker()
        var session: ScanSession? = ScanSession(source: ScanSource(path: "/publication", displayName: "fixture"),
                                                scanWorker: worker)
        let weakSession = ScanSessionWeakReference(try #require(session))
        session?.startScan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await worker.started) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await worker.started)
        session = nil
        #expect(weakSession.value == nil)
        await worker.release()
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition(), "Timed out waiting for a snapshot publication")
    }
}

private struct PublicationWorker: ScanSessionScanning, ScanSessionTreeUpdating {
    let source = ScanSource(path: "/publication", displayName: "Accepted source", isVolumeRoot: true,
                            totalCapacity: 100, availableCapacity: 40,
                            scanSettings: DiskScanSettings(usePhysicalSize: true, lookInsidePackages: true))
    private func root(afterDeletion: Bool) -> DiskItem {
        let names = afterDeletion ? ["b.txt"] : ["a.txt", "b.txt"]
        return DiskItem(url: source.url, allocatedSizeValue: UInt64(names.count * 20),
                        logicalSizeValue: UInt64(names.count * 10), isDirectory: true,
                        children: names.map { DiskItem(url: source.url.appendingPathComponent($0),
                            allocatedSizeValue: 20, logicalSizeValue: 10, kindName: "Fixture", isRoot: false) })
    }
    func scan(source: ScanSource, settings: DiskScanSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        let root = root(afterDeletion: false)
        await progress(DiskScanProgress(scannedFileCount: 2, scannedFolderCount: 0,
                                        scannedByteCount: 40, currentPath: root.path))
        return ScanSessionScanResult(source: self.source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: true),
            builtUsingPhysicalSize: true, skippedItems: [])
    }
    func refresh(item: DiskItem, currentRoot: DiskItem, source: ScanSource,
                 settings: DiskScanSettings) async throws -> ScanSessionTreeUpdateResult {
        result()
    }
    func delete(item: DiskItem, deletionMethod: DiskItemDeletionMethod, currentRoot: DiskItem,
                source: ScanSource, settings: DiskScanSettings) async throws -> ScanSessionTreeUpdateResult {
        result()
    }
    private func result() -> ScanSessionTreeUpdateResult {
        let root = root(afterDeletion: true)
        return ScanSessionTreeUpdateResult(source: source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: true),
            selectionPath: root.path, builtUsingPhysicalSize: true, skippedItems: [], refreshedSubtreePath: root.path)
    }
}

private actor RetentionScanWorker: ScanSessionScanning {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func release() { continuation?.resume(); continuation = nil }
    func scan(source: ScanSource, settings: DiskScanSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        started = true
        await withCheckedContinuation { continuation = $0 }
        throw CancellationError()
    }
}
