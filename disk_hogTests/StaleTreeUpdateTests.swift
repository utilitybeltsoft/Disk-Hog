import Foundation
import Testing
@testable import disk_hog

@MainActor
struct StaleTreeUpdateTests {
    @Test(arguments: [false, true], [false, true])
    func staleDerivedWorkCannotOverwriteRefreshOrDeletion(delete: Bool, sizeMode: Bool) async throws {
        let original = Self.root(name: "old.txt", size: 12)
        let updated = Self.root(name: delete ? nil : "new.txt", size: 30)
        let presenter = GatedPresenter(blockSizeMode: sizeMode)
        let treeWorker = GatedTreeWorker(root: updated)
        let session = Self.session(root: original, treeWorker: treeWorker, presenter: presenter)
        defer { presenter.release(); session.cancel() }
        session.startScan()
        try await Self.wait { session.state == .complete }
        if sizeMode { session.updateSizeMode(false) }
        else { session.rebuildPresentationMetrics(sharesKindColors: false, colorScheme: .diskHog) }
        try await Self.wait { presenter.started }

        if delete { session.delete(try #require(session.rootItem?.children.first), using: .moveToTrash) }
        else { session.refresh(try #require(session.rootItem)) }
        await treeWorker.release()
        try await Self.wait { !session.isUpdatingTree }
        #expect(session.rootItem?.item(atPath: "/scan/old.txt") == nil)
        presenter.release()
        try await Self.wait { presenter.returned }
        // Allow the released worker's MainActor completion to be delivered.
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.rootItem?.item(atPath: "/scan/old.txt") == nil)
        #expect(session.rootItem?.children.count == (delete ? 0 : 1))
        #expect(session.scannedByteCount == (delete ? 0 : (sizeMode ? 30 : 60)))
        #expect(session.presentationMetrics?.kindStatistics.reduce(0) { $0 + $1.size } == (delete ? 0 : (sizeMode ? 30 : 60)))
        #expect(session.presentationMetrics?.sharesKindColors == false || sizeMode)
    }

    @Test(arguments: [StaleTreeOutcome.success, .failure, .cancelled])
    func preferencesDuringTreeWorkAreAppliedAfterEveryOutcome(outcome: StaleTreeOutcome) async throws {
        let original = Self.root(name: "old.txt", size: 12)
        let treeWorker = GatedTreeWorker(root: Self.root(name: "new.txt", size: 30), outcome: outcome)
        let session = Self.session(root: original, treeWorker: treeWorker)
        defer { session.cancel() }
        session.startScan()
        try await Self.wait { session.state == .complete }
        session.refresh(try #require(session.rootItem))
        session.updateSizeMode(false)
        session.rebuildPresentationMetrics(sharesKindColors: false, colorScheme: .diskHog)
        await treeWorker.release()
        try await Self.wait {
            !session.isUpdatingTree && session.presentationMetrics?.sharesKindColors == false
                && session.scannedByteCount == (outcome == .success ? 30 : 12)
        }
        #expect(session.scanSettings.usePhysicalSize == false)
        #expect(session.rootItem?.children.first?.name == (outcome == .success ? "new.txt" : "old.txt"))
    }

    private static func root(name: String?, size: UInt64) -> DiskItem {
        let children = name.map { [DiskItem(url: URL(fileURLWithPath: "/scan/\($0)"),
            allocatedSizeValue: size * 2, logicalSizeValue: size, kindName: "Fixture File", isRoot: false)] } ?? []
        return DiskItem(url: URL(fileURLWithPath: "/scan"), allocatedSizeValue: name == nil ? 0 : size * 2,
                        logicalSizeValue: name == nil ? 0 : size, isDirectory: true, children: children)
    }

    private static func session(root: DiskItem, treeWorker: GatedTreeWorker,
                                presenter: any ScanSessionPresenting = DiskInventoryZScanSessionPresentationWorker()) -> ScanSession {
        ScanSession(source: ScanSource(path: "/scan", displayName: "fixture",
            scanSettings: DiskScanSettings(usePhysicalSize: true, lookInsidePackages: true)),
            scanWorker: FixedScanWorker(root: root), treeWorker: treeWorker, presentationWorker: presenter)
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition(), "Timed out waiting for controlled worker completion")
    }
}

private nonisolated func metrics(_ root: DiskItem, physical: Bool, colors: Bool = true) -> TreemapPresentationMetrics {
    TreemapPresentationMetrics(rootItem: root, usePhysicalSize: physical, sharesKindColors: colors, colorScheme: .diskHog)
}

private struct FixedScanWorker: ScanSessionScanning {
    let root: DiskItem
    func scan(source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        ScanSessionScanResult(source: source, rootItem: root, presentationMetrics: metrics(root, physical: true),
                              builtUsingPhysicalSize: true, skippedItems: [])
    }
}

enum StaleTreeOutcome: Sendable { case success, failure, cancelled }
private struct FixtureError: Error {}
private actor GatedTreeWorker: ScanSessionTreeUpdating {
    let root: DiskItem
    let outcome: StaleTreeOutcome
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(root: DiskItem, outcome: StaleTreeOutcome = .success) { self.root = root; self.outcome = outcome }
    func release() { released = true; continuation?.resume(); continuation = nil }
    private func result(source: ScanSource, settings: DiskScanSettings) async throws -> ScanSessionTreeUpdateResult {
        if !released { await withCheckedContinuation { continuation = $0 } }
        switch outcome {
        case .failure: throw FixtureError()
        case .cancelled: throw CancellationError()
        case .success: break
        }
        return ScanSessionTreeUpdateResult(source: source, rootItem: root,
            presentationMetrics: metrics(root, physical: settings.usePhysicalSize), selectionPath: root.path,
            builtUsingPhysicalSize: settings.usePhysicalSize, skippedItems: [], refreshedSubtreePath: root.path)
    }
    func refresh(item: DiskItem, currentRoot: DiskItem, source: ScanSource,
                 settings: DiskScanSettings, presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        try await result(source: source, settings: settings)
    }
    func delete(item: DiskItem, deletionMethod: DiskItemDeletionMethod, currentRoot: DiskItem,
                source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings) async throws -> ScanSessionTreeUpdateResult {
        try await result(source: source, settings: settings)
    }
}

private final class GatedPresenter: ScanSessionPresenting, @unchecked Sendable {
    let blockSizeMode: Bool
    private let condition = NSCondition()
    private var didStart = false
    private var didReturn = false
    private var released = false
    init(blockSizeMode: Bool) { self.blockSizeMode = blockSizeMode }
    var started: Bool { condition.withLock { didStart } }
    var returned: Bool { condition.withLock { didReturn } }
    func release() { condition.withLock { released = true; condition.broadcast() } }
    private func gate(sizeMode: Bool) {
        condition.lock()
        defer { condition.unlock() }
        guard sizeMode == blockSizeMode, !didStart else { return }
        didStart = true
        let deadline = Date().addingTimeInterval(15)
        while !released { if !condition.wait(until: deadline) { break } }
        didReturn = true
    }
    func presentationMetrics(rootItem: DiskItem, usePhysicalSize: Bool, sharesKindColors: Bool,
                             colorScheme: TreemapColorScheme) -> TreemapPresentationMetrics {
        gate(sizeMode: false)
        return metrics(rootItem, physical: usePhysicalSize, colors: sharesKindColors)
    }
    func sizeModeUpdate(rootItem: DiskItem, selectionPath: String, usePhysicalSize: Bool,
                        sharesKindColors: Bool, colorScheme: TreemapColorScheme) -> ScanSessionSizeModeUpdateResult {
        gate(sizeMode: true)
        return DiskInventoryZScanSessionPresentationWorker().sizeModeUpdate(rootItem: rootItem,
            selectionPath: selectionPath, usePhysicalSize: usePhysicalSize,
            sharesKindColors: sharesKindColors, colorScheme: colorScheme)
    }
}
