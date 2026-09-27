import AppKit
import Testing
@testable import disk_hog

@MainActor
struct DependencyIsolationTests {
    private func fixture() -> (ScanSource, DiskItem, DiskItem) {
        let source = ScanSource(path: "/dependency-fixture", displayName: "Fixture")
        let item = DiskItem(url: source.url.appendingPathComponent("file"),
                            allocatedSizeValue: 16, logicalSizeValue: 8, isRoot: false)
        let root = DiskItem(url: source.url, allocatedSizeValue: 16, logicalSizeValue: 8,
                            isDirectory: true, children: [item], isRoot: true)
        return (source, root, item)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }

    @Test func commandAndContextMenuUseTheirSuppliedQueueForChecksAndActions() {
        let (source, _, item) = fixture()
        let session = ScanSession(source: source)
        let queue = CleanupQueueStore()
        let otherQueue = CleanupQueueStore()
        let state = ScanWindowCommandState(cleanupQueue: queue)
        let context = ScanWindowCommandContext(session: session,
            selectionCoordinator: ScanWindowSelectionCoordinator(), treemapNavigation: TreemapNavigationState())
        context.updateSelectedItem(item)
        state.activate(context)
        #expect(state.canToggleSelectedItemInCleanupQueue)
        state.toggleSelectedItemInCleanupQueue()
        #expect(queue.isDirectlyQueued(item))
        #expect(otherQueue.items.isEmpty)
        #expect(state.selectedItemCleanupQueueCommandTitle == CleanupQueueMenuPresentation.undoTitle)

        let target = DiskItemContextMenuActionTarget(session: session, cleanupQueue: queue)
        let menu = DiskItemContextMenuBuilder.menu(for: item, actionTarget: target, treeActionsEnabled: true)
        let action = menu.items.first { $0.action == #selector(DiskItemContextMenuActionTarget.trashMenuItem(_:)) }
        #expect(action?.title == CleanupQueueMenuPresentation.undoTitle)
        if let action { target.trashMenuItem(action) }
        #expect(queue.items.isEmpty)
        if let action { target.trashMenuItem(action) }
        #expect(queue.isDirectlyQueued(item))
        state.toggleSelectedItemInCleanupQueue()
        #expect(queue.items.isEmpty)
        #expect(otherQueue.items.isEmpty)
    }

    @Test func batchRouterMutatesOnlyItsInjectedQueue() async throws {
        let (source, root, item) = fixture()
        let worker = DependencyScanWorker(root: root)
        let session = ScanSession(source: source, scanWorker: worker)
        session.startScan()
        try await waitUntil { session.state == .complete }
        defer { session.cancel() }
        let queue = CleanupQueueStore()
        let other = CleanupQueueStore()
        let router = AppCommandRouter(cleanupQueue: queue)
        let otherRouter = AppCommandRouter(cleanupQueue: other)
        router.activateSelectionListBatchQueue(session: session, items: [item])
        otherRouter.activateSelectionListBatchQueue(session: session, items: [item])
        router.toggleSelectionListBatchQueue()
        #expect(queue.isDirectlyQueued(item))
        #expect(other.items.isEmpty)
        #expect(router.selectionListBatchQueueTitle == CleanupQueueMenuPresentation.undoTitle)
        #expect(otherRouter.selectionListBatchQueueTitle == CleanupQueueMenuPresentation.addTitle)
        router.toggleSelectionListBatchQueue()
        #expect(queue.items.isEmpty)
    }

    @Test func preferencesOnlyUpdateTheirRegistryAndDefaultsDomain() throws {
        let suite = "DependencyIsolation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = ScanWindowRegistry()
        let otherRegistry = ScanWindowRegistry()
        let preferences = ScanPreferences(registry: registry, defaults: defaults)
        let (source, _, _) = fixture()
        let session = ScanSession(source: source)
        let other = ScanSession(source: source)
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        registry.register(window, session: session, for: source)
        otherRegistry.register(otherWindow, session: other, for: source)
        defer {
            registry.unregister(window, for: source)
            otherRegistry.unregister(otherWindow, for: source)
        }
        let previous = session.scanSettings.usePhysicalSize
        preferences.setUsesPhysicalSize(!previous)
        #expect(session.scanSettings.usePhysicalSize == !previous)
        #expect(other.scanSettings.usePhysicalSize == previous)
        #expect(defaults.bool(forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize) == !previous)
        preferences.setSharesKindColors(false)
        preferences.setTreemapColorScheme(.diskInventoryZ)
        let reloaded = ScanPreferences(registry: registry, defaults: defaults)
        #expect(reloaded.presentationSettings == ScanPresentationSettings(sharesKindColors: false, colorScheme: .diskInventoryZ))
    }

    @Test func inFlightScanUsesCapturedPreferencesThenReconcilesLatestRequest() async throws {
        let (source, root, _) = fixture()
        let initial = ScanPresentationSettings(sharesKindColors: false, colorScheme: .diskInventoryZ)
        let worker = DependencyScanWorker(root: root, paused: true)
        let session = ScanSession(source: source, presentationSettings: initial, scanWorker: worker)
        session.startScan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await worker.received == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await worker.received == initial)
        session.rebuildPresentationMetrics(sharesKindColors: true, colorScheme: .diskHog)
        await worker.release()
        try await waitUntil {
            session.state == .complete && session.presentationMetrics?.sharesKindColors == true
                && session.presentationMetrics?.colorScheme == .diskHog
        }
        #expect(await worker.received == initial)
        session.cancel()
    }

    @Test func realWorkersUseExplicitPresentationSettings() async throws {
        let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("dependency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2, 3]).write(to: url.appendingPathComponent("file"))
        // Preserve /private/tmp: Foundation normalization can rewrite it to /tmp,
        // while filesystem enumeration reports canonical paths.
        let source = ScanSource(path: url.path, displayName: "Fixture")
        let settings = DiskScanSettings.diskInventoryZDefault
        let presentation = ScanPresentationSettings(sharesKindColors: !ScanPreferenceDefaults.sharesKindColors,
            colorScheme: ScanPreferenceDefaults.treemapColorScheme == .diskHog ? .diskInventoryZ : .diskHog)
        let result = try await DiskInventoryZScanSessionWorker().scan(source: source, settings: settings,
            presentation: presentation, progress: { _ in }, stage: { _ in },
            willBuildTreemap: {}, treemapProgress: { _ in })
        #expect(result.presentationMetrics.sharesKindColors == presentation.sharesKindColors)
        #expect(result.presentationMetrics.colorScheme == presentation.colorScheme)
        let worker = DiskInventoryZScanSessionTreeWorker()
        let refreshed = try await worker.refresh(item: result.rootItem, currentRoot: result.rootItem,
            source: source, settings: settings, presentation: presentation)
        #expect(refreshed.presentationMetrics.sharesKindColors == presentation.sharesKindColors)
        #expect(refreshed.presentationMetrics.colorScheme == presentation.colorScheme)
        let item = try #require(refreshed.rootItem.children.first)
        #expect(refreshed.rootItem.descendantsMatchingAncestorPath(of: item).count == 2)
        let deleted = try await worker.delete(item: item, deletionMethod: .deletePermanently,
            currentRoot: refreshed.rootItem, source: source, settings: settings, presentation: presentation)
        #expect(deleted.presentationMetrics.sharesKindColors == presentation.sharesKindColors)
        #expect(deleted.presentationMetrics.colorScheme == presentation.colorScheme)
        #expect(deleted.rootItem.children.isEmpty)
    }
}

private actor DependencyScanWorker: ScanSessionScanning {
    let root: DiskItem
    private var paused: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var received: ScanPresentationSettings?
    init(root: DiskItem, paused: Bool = false) { self.root = root; self.paused = paused }
    func release() { paused = false; continuation?.resume(); continuation = nil }
    func scan(source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        received = presentation
        if paused { await withCheckedContinuation { continuation = $0 } }
        return ScanSessionScanResult(source: source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: presentation.sharesKindColors, colorScheme: presentation.colorScheme),
            builtUsingPhysicalSize: settings.usePhysicalSize, skippedItems: [])
    }
}
