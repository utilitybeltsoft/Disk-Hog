import Foundation
import Testing
@testable import disk_hog

@MainActor
struct CleanupLocalReconciliationTests {
    private func fixture() -> (ScanSource, DiskItem, [ScanSkippedItem]) {
        let source = ScanSource(path: "/private/tmp/cleanup-local-fixture", displayName: "Fixture",
                                isVolumeRoot: true, totalCapacity: 1000, availableCapacity: 100)
        func file(_ path: String, bytes: UInt64) -> DiskItem {
            DiskItem(url: source.url.appendingPathComponent(path), allocatedSizeValue: bytes * 2,
                     logicalSizeValue: bytes, kindName: "Fixture", isRoot: false)
        }
        let folder = DiskItem(url: source.url.appendingPathComponent("folder"),
            allocatedSizeValue: 20, logicalSizeValue: 10, isDirectory: true,
            children: [file("folder/child", bytes: 10)], isRoot: false)
        let root = DiskItem(url: source.url, allocatedSizeValue: 120, logicalSizeValue: 60,
            isDirectory: true, children: [folder, file("failed", bytes: 20), file("keep", bytes: 30)])
        return (source, root, [ScanSkippedItem(path: folder.path + "/unknown", reason: "fixture"),
                              ScanSkippedItem(path: source.path + "/folder-backup/unknown", reason: "keep")])
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(predicate(), "Timed out waiting for cleanup")
    }
    private func waitForCleanup(_ worker: CleanupTestWorker) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await worker.cleanupCalls == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await worker.cleanupCalls == 1)
    }

    @Test func partialBatchPublishesOnceAndPreservesFreshnessAndFreeSpace() async throws {
        let (source, root, skipped) = fixture()
        let worker = CleanupTestWorker(root: root, skipped: skipped)
        let session = ScanSession(source: source, scanWorker: worker, treeWorker: worker)
        session.startScan()
        try await wait { session.state == .complete }
        defer { session.cancel() }
        let freshness = session.snapshotFreshness
        let folder = try #require(root.item(atPath: source.path + "/folder"))
        let failed = try #require(root.item(atPath: source.path + "/failed"))
        let keep = try #require(root.item(atPath: source.path + "/keep"))
        session.rememberSelection(try #require(folder.children.first))
        let store = CleanupQueueStore(trashItem: { url, _ in
            if url.lastPathComponent == "failed" { throw CocoaError(.fileWriteNoPermission) }
        })
        store.enqueue([folder, failed, keep], from: session)
        var publications = 0
        let observer = NotificationCenter.default.addObserver(forName: .scanSessionTreeDidChange,
            object: session, queue: nil) { _ in MainActor.assumeIsolated { publications += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.moveSelectedItemsToFinderTrash()
        try await wait { store.items.count == 1 && store.items.first?.status == .inaccessible
            && !session.isUpdatingTree && session.rootItem?.children.count == 1 }
        let updated = try #require(session.rootItem)
        #expect(updated.children.first?.path == failed.path)
        #expect(session.preferredSelection?.path == root.path)
        #expect(session.scannedFileCount == 1)
        #expect(session.scannedFolderCount == 0)
        #expect(updated.allocatedSizeValue == 40)
        #expect(updated.logicalSizeValue == 20)
        #expect(session.scannedByteCount == updated.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize))
        #expect(session.skippedItems == [skipped[1]])
        #expect(session.snapshotFreshness == freshness)
        #expect(session.freeSpaceItem?.allocatedSizeValue == 100)
        #expect(publications == 1)
        #expect(await worker.cleanupCalls == 1)
        #expect(await worker.lastPaths.sorted() == [folder.path, keep.path].sorted())
        #expect(await worker.scanCalls == 1)
        #expect(await worker.treeCalls == 0)
        #expect(session.presentationMetrics?.kindStatistics.first { $0.kindName == "Fixture" }?.fileCount == 1)
    }

    @Test func cleanupSurvivesCancellationAndReconcilesLatestPreferencesAndSelection() async throws {
        let (source, root, skipped) = fixture()
        let worker = CleanupTestWorker(root: root, skipped: skipped, pauseCleanup: true)
        let session = ScanSession(source: source, scanWorker: worker, treeWorker: worker)
        session.startScan()
        try await wait { session.state == .complete }
        defer { session.cancel() }
        let store = CleanupQueueStore(trashItem: { _, _ in })
        let folder = try #require(root.item(atPath: source.path + "/folder"))
        store.enqueue(folder, from: session)
        store.moveSelectedItemsToFinderTrash()
        try await waitForCleanup(worker)
        let keep = try #require(root.item(atPath: source.path + "/keep"))
        session.rememberSelection(keep)
        session.updateSizeMode(false)
        session.rebuildPresentationMetrics(sharesKindColors: false, colorScheme: .diskInventoryZ)
        session.cancel()
        await worker.release()
        try await wait { !session.isUpdatingTree && session.rootItem?.item(atPath: folder.path) == nil
            && session.presentationMetrics?.sharesKindColors == false
            && session.presentationMetrics?.colorScheme == .diskInventoryZ }
        #expect(session.preferredSelection?.path == keep.path)
        #expect(session.scannedByteCount == 50)
        #expect(await worker.scanCalls == 1)
        #expect(await worker.treeCalls == 0)
    }

    @Test func changedBaselineFallsBackEvenWhenFailedRefreshRetainsSameRoot() async throws {
        let (source, root, skipped) = fixture()
        let worker = CleanupTestWorker(root: root, skipped: skipped)
        let session = ScanSession(source: source, scanWorker: worker, treeWorker: worker)
        session.startScan()
        try await wait { session.state == .complete }
        _ = try #require(session.cleanupBaseline)
        let gate = CleanupTrashGate()
        defer { gate.release(); session.cancel() }
        let store = CleanupQueueStore(trashItem: { _, _ in gate.wait() })
        store.enqueue(try #require(root.item(atPath: source.path + "/keep")), from: session)
        store.moveSelectedItemsToFinderTrash()
        try await wait { gate.started }
        session.refresh(root)
        try await wait { !session.isUpdatingTree && session.failure != nil }
        #expect(session.rootItem == root)
        gate.release()
        try await wait { store.items.isEmpty && session.state == .complete && session.rootItem?.children.isEmpty == true }
        #expect(await worker.scanCalls == 2)
        #expect(await worker.cleanupCalls == 0)
        session.cancel()
    }

    @Test func failedLocalEditFallsBackToRescan() async throws {
        let (source, root, skipped) = fixture()
        let worker = CleanupTestWorker(root: root, skipped: skipped, failCleanup: true)
        let session = ScanSession(source: source, scanWorker: worker, treeWorker: worker)
        session.startScan()
        try await wait { session.state == .complete }
        let store = CleanupQueueStore(trashItem: { _, _ in })
        store.enqueue(try #require(root.children.first), from: session)
        store.moveSelectedItemsToFinderTrash()
        try await wait { store.items.isEmpty && session.state == .complete && session.rootItem?.children.isEmpty == true }
        #expect(await worker.scanCalls == 2)
        #expect(await worker.cleanupCalls == 1)
        session.cancel()
    }

    @Test func actualFilesystemMoveUsesOriginalTreePathWithoutRescanning() async throws {
        let base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("cleanup-local-\(UUID().uuidString)")
        let directory = base.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let victimURL = directory.appendingPathComponent("victim")
        let keepURL = directory.appendingPathComponent("keep")
        let destination = base.appendingPathComponent("simulated-trash")
        try Data([1, 2]).write(to: victimURL)
        try Data([3, 4, 5]).write(to: keepURL)
        let source = ScanSource(path: directory.path, displayName: "Fixture")
        let root = try await DiskInventoryZScanner().scan(source: source, settings: .diskInventoryZDefault).item
        let worker = CleanupTestWorker(root: root, skipped: [])
        let session = ScanSession(source: source, scanWorker: worker, treeWorker: worker)
        session.startScan()
        try await wait { session.state == .complete }
        defer { session.cancel() }
        let victim = try #require(root.item(atPath: victimURL.path))
        let store = CleanupQueueStore(trashItem: { url, _ in
            try FileManager.default.moveItem(at: url, to: destination)
        })
        #expect(store.enqueue(victim, from: session))
        #expect(store.items.first?.treePath == victim.path)
        store.moveSelectedItemsToFinderTrash()
        try await wait { store.items.isEmpty && !session.isUpdatingTree
            && session.rootItem?.item(atPath: victim.path) == nil }
        #expect(session.rootItem?.item(atPath: keepURL.path)?.logicalSizeValue == 3)
        #expect(try Data(contentsOf: destination) == Data([1, 2]))
        #expect(await worker.scanCalls == 1)
        #expect(await worker.treeCalls == 0)
    }

    @Test func queueReconcilesEachOriginatingSessionOnce() async throws {
        let (source, root, skipped) = fixture()
        let secondSource = ScanSource(path: "/private/tmp/cleanup-second-fixture", displayName: "Second")
        let secondFile = DiskItem(url: secondSource.url.appendingPathComponent("file"),
                                  allocatedSizeValue: 5, logicalSizeValue: 5, isRoot: false)
        let secondRoot = DiskItem(url: secondSource.url, allocatedSizeValue: 5, logicalSizeValue: 5,
                                  isDirectory: true, children: [secondFile])
        let firstWorker = CleanupTestWorker(root: root, skipped: skipped)
        let secondWorker = CleanupTestWorker(root: secondRoot, skipped: [])
        let first = ScanSession(source: source, scanWorker: firstWorker, treeWorker: firstWorker)
        let second = ScanSession(source: secondSource, scanWorker: secondWorker, treeWorker: secondWorker)
        first.startScan(); second.startScan()
        defer { first.cancel(); second.cancel() }
        try await wait { first.state == .complete && second.state == .complete }
        let store = CleanupQueueStore(trashItem: { _, _ in })
        store.enqueue(root.children, from: first)
        store.enqueue(secondFile, from: second)
        store.moveSelectedItemsToFinderTrash()
        try await wait { store.items.isEmpty && !first.isUpdatingTree && !second.isUpdatingTree
            && first.rootItem?.children.isEmpty == true && second.rootItem?.children.isEmpty == true }
        #expect(await firstWorker.cleanupCalls == 1)
        #expect(await secondWorker.cleanupCalls == 1)
        #expect(await firstWorker.scanCalls == 1)
        #expect(await secondWorker.scanCalls == 1)
        #expect(await firstWorker.treeCalls == 0)
        #expect(await secondWorker.treeCalls == 0)
    }

    @Test func batchRemovalHandlesDuplicateNestedAndMissingPathsWithoutChangingInput() throws {
        let (source, root, _) = fixture()
        let folderPath = source.path + "/folder"
        let result = try #require(DiskItemTreeEditor.removingSubtrees(from: root,
            atPaths: [folderPath + "/child", folderPath, folderPath, source.path + "/absent"], usePhysicalSize: true))
        #expect(result.children.count == 2)
        #expect(result.allocatedSizeValue == 100)
        #expect(result.logicalSizeValue == 50)
        #expect(root.children.count == 3)
        #expect(root.allocatedSizeValue == 120)
        #expect(DiskItemTreeEditor.removingSubtrees(from: root, atPaths: [root.path], usePhysicalSize: true) == nil)
        #expect(DiskItemTreeEditor.removingSubtrees(from: root, atPaths: [root.path + "-other/file"], usePhysicalSize: true) == nil)
    }
}

private actor CleanupTestWorker: ScanSessionScanning, ScanSessionTreeUpdating {
    let root: DiskItem
    let skipped: [ScanSkippedItem]
    var pauseCleanup: Bool
    let failCleanup: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var scanCalls = 0
    private(set) var treeCalls = 0
    private(set) var cleanupCalls = 0
    private(set) var lastPaths: [String] = []
    init(root: DiskItem, skipped: [ScanSkippedItem], pauseCleanup: Bool = false, failCleanup: Bool = false) {
        self.root = root; self.skipped = skipped; self.pauseCleanup = pauseCleanup; self.failCleanup = failCleanup
    }
    func release() { pauseCleanup = false; continuation?.resume(); continuation = nil }
    func scan(source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        scanCalls += 1
        let result = scanCalls == 1 ? root : DiskItem(url: root.url, isDirectory: true)
        return ScanSessionScanResult(source: source, rootItem: result,
            presentationMetrics: TreemapPresentationMetrics(rootItem: result, usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: presentation.sharesKindColors, colorScheme: presentation.colorScheme),
            builtUsingPhysicalSize: settings.usePhysicalSize, skippedItems: scanCalls == 1 ? skipped : [])
    }
    func refresh(item: DiskItem, currentRoot: DiskItem, source: ScanSource, settings: DiskScanSettings,
                 presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        treeCalls += 1
        throw CocoaError(.fileReadNoPermission)
    }
    func delete(item: DiskItem, deletionMethod: DiskItemDeletionMethod, currentRoot: DiskItem,
                source: ScanSource, settings: DiskScanSettings,
                presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        treeCalls += 1
        throw CocoaError(.fileReadNoPermission)
    }
    func reconcileCleanup(paths: [String], currentRoot: DiskItem, source: ScanSource, selectionPath: String,
                          settings: DiskScanSettings, presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        cleanupCalls += 1
        lastPaths = paths
        if pauseCleanup { await withCheckedContinuation { continuation = $0 } }
        if failCleanup { throw CancellationError() }
        return try await DiskInventoryZScanSessionTreeWorker().reconcileCleanup(paths: paths, currentRoot: currentRoot,
            source: source, selectionPath: selectionPath, settings: settings, presentation: presentation)
    }
}

private nonisolated final class CleanupTrashGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didStart = false
    private var released = false
    var started: Bool {
        condition.lock()
        defer { condition.unlock() }
        return didStart
    }
    func wait() {
        condition.lock()
        defer { condition.unlock() }
        didStart = true
        while !released { condition.wait() }
    }
    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
