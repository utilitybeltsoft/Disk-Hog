import Foundation
import Testing
@testable import disk_hog

@MainActor
struct QueueRefreshDeferralTests {
    @Test(arguments: QueueBusyOperation.allCases, QueueBusyOutcome.allCases)
    func successfulQueueDeletionRefreshesAfterBusyWork(operation: QueueBusyOperation,
                                                       outcome: QueueBusyOutcome) async throws {
        let worker = QueueRefreshFixtureWorker(busyOperation: operation, outcome: outcome)
        let session = ScanSession(source: ScanSource(path: "/queue-refresh-fixture", displayName: "fixture"),
                                  scanWorker: worker, treeWorker: worker)
        // Exercise the production refresh callback, injecting only filesystem mutation.
        let store = CleanupQueueStore(trashItem: { _, _ in })
        defer { session.cancel() }
        session.startScan()
        try await Self.wait { session.state == .complete }
        let root = try #require(session.rootItem)
        let queued = try #require(root.children.first)
        #expect(store.enqueue(queued, from: session))
        let secondStore = CleanupQueueStore(trashItem: { _, _ in })
        #expect(secondStore.enqueue(try #require(root.children.last), from: session))
        switch operation {
        case .scan: session.startScan()
        case .refresh: session.refresh(root)
        case .delete: session.delete(try #require(root.children.last), using: .moveToTrash)
        }
        // The actor records entry before waiting on its continuation.
        try await Self.waitAsync { await worker.isWaiting }
        store.moveSelectedItemsToFinderTrash()
        try await Self.wait { store.items.isEmpty }
        // Separate queue completions exercise the real callback and must
        // coalesce into one follow-up scan while the session stays busy.
        secondStore.moveSelectedItemsToFinderTrash()
        try await Self.wait { secondStore.items.isEmpty }
        #expect(await worker.scanCalls == (operation == .scan ? 2 : 1))
        await worker.release()
        try await Self.wait {
            session.state == .complete && !session.isUpdatingTree && session.rootItem?.children.isEmpty == true
        }
        #expect(session.scannedByteCount == 0)
        #expect(session.rootItem?.item(atPath: queued.path) == nil)
        #expect(await worker.scanCalls == (operation == .scan ? 3 : 2))
    }

    @Test func idleQueueDeletionStillRefreshesImmediately() async throws {
        let worker = QueueRefreshFixtureWorker(busyOperation: .refresh, outcome: .success)
        await worker.release()
        let session = ScanSession(source: ScanSource(path: "/queue-refresh-fixture", displayName: "fixture"),
                                  scanWorker: worker, treeWorker: worker)
        let store = CleanupQueueStore(trashItem: { _, _ in })
        defer { session.cancel() }
        session.startScan()
        try await Self.wait { session.state == .complete }
        #expect(store.enqueue(try #require(session.rootItem?.children.first), from: session))
        store.moveSelectedItemsToFinderTrash()
        try await Self.wait { store.items.isEmpty && !session.isUpdatingTree && session.rootItem?.children.isEmpty == true }
        #expect(await worker.scanCalls == 1)
        #expect(await worker.treeCalls == 1)
    }

    private static func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(predicate(), "Timed out waiting for queue/session completion")
    }

    private static func waitAsync(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !(await predicate()) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await predicate(), "Timed out waiting for controlled worker")
    }
}

enum QueueBusyOperation: CaseIterable, Sendable { case scan, refresh, delete }
enum QueueBusyOutcome: CaseIterable, Sendable { case success, failure, cancelled }
private struct QueueFixtureError: Error {}

private actor QueueRefreshFixtureWorker: ScanSessionScanning, ScanSessionTreeUpdating {
    let busyOperation: QueueBusyOperation
    let outcome: QueueBusyOutcome
    private(set) var scanCalls = 0
    private(set) var treeCalls = 0
    private(set) var isWaiting = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(busyOperation: QueueBusyOperation, outcome: QueueBusyOutcome) {
        self.busyOperation = busyOperation
        self.outcome = outcome
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
    private func pause() async throws {
        isWaiting = true
        if !released { await withCheckedContinuation { continuation = $0 } }
        switch outcome {
        case .success: break
        case .failure: throw QueueFixtureError()
        case .cancelled: throw CancellationError()
        }
    }
    private func root(empty: Bool) -> DiskItem {
        let children = empty ? [] : ["queued.txt", "other.txt"].map {
            DiskItem(url: URL(fileURLWithPath: "/queue-refresh-fixture/\($0)"),
                     allocatedSizeValue: 10, logicalSizeValue: 10, isRoot: false)
        }
        return DiskItem(url: URL(fileURLWithPath: "/queue-refresh-fixture"),
                        allocatedSizeValue: empty ? 0 : 20, logicalSizeValue: empty ? 0 : 20,
                        isDirectory: true, children: children)
    }
    func scan(source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        scanCalls += 1
        let busyScan = busyOperation == .scan && scanCalls == 2
        // This snapshot predates queue deletion, even if it publishes afterward.
        let root = root(empty: scanCalls > 1 && !busyScan)
        if busyScan { try await pause() }
        return ScanSessionScanResult(source: source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: settings.usePhysicalSize),
            builtUsingPhysicalSize: settings.usePhysicalSize, skippedItems: [])
    }
    private func update(source: ScanSource, settings: DiskScanSettings) async throws -> ScanSessionTreeUpdateResult {
        treeCalls += 1
        let root = root(empty: released)
        try await pause()
        return ScanSessionTreeUpdateResult(source: source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: settings.usePhysicalSize),
            selectionPath: root.path, builtUsingPhysicalSize: settings.usePhysicalSize,
            skippedItems: [], refreshedSubtreePath: root.path)
    }
    func refresh(item: DiskItem, currentRoot: DiskItem, source: ScanSource,
                 settings: DiskScanSettings, presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        try await update(source: source, settings: settings)
    }
    func delete(item: DiskItem, deletionMethod: DiskItemDeletionMethod, currentRoot: DiskItem,
                source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        try await update(source: source, settings: settings)
    }
}
