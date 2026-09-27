import Combine
import Foundation

/// UI-facing session facade. Controllers own asynchronous operation lifetimes;
/// accepted results are published here as coherent value snapshots.
@MainActor
final class ScanSession: ObservableObject {
    @Published private var snapshot: ScanSessionSnapshot
    @Published private var activity: ScanSessionActivity
    @Published private var spaceVisibility = ScanSessionSpaceVisibility()
    @Published private(set) var failure: ScanSessionFailure?
    #if FILE_MATCHING_DIAGNOSTICS
    @Published private(set) var diagnosticsExportState: DiagnosticsExportState = .idle
    #endif

    private var treeOperationRevision: UInt64 = 0
    private var settings: DiskScanSettings
    private let operations: ScanSessionOperationController
    private let presentation: ScanSessionPresentationController

    init(source: ScanSource,
         presentationSettings: ScanPresentationSettings = ScanPresentationSettings(),
         scanWorker: any ScanSessionScanning = DiskInventoryZScanSessionWorker(),
         treeWorker: any ScanSessionTreeUpdating = DiskInventoryZScanSessionTreeWorker(),
         presentationWorker: any ScanSessionPresenting = DiskInventoryZScanSessionPresentationWorker()) {
        snapshot = ScanSessionSnapshot(source: source)
        activity = ScanSessionActivity(currentPath: source.path)
        settings = source.scanSettings ?? .diskInventoryZDefault
        operations = ScanSessionOperationController(scanWorker: scanWorker, treeWorker: treeWorker)
        presentation = ScanSessionPresentationController(worker: presentationWorker, preferences: presentationSettings)
    }

    // Preserve the view/command API while grouping publication by responsibility.
    var source: ScanSource { snapshot.source }
    var state: ScanSessionState { activity.state }
    var startedAt: Date? { activity.startedAt }
    var completedAt: Date? { activity.completedAt }
    var currentPath: String { activity.currentPath }
    var scanStage: DiskScanStage { activity.stage }
    var isUpdatingTree: Bool { activity.isUpdatingTree }
    var isBuildingTreemap: Bool { activity.isBuildingTreemap }
    var treemapPreparationProgress: Double? { activity.treemapProgress }
    var isPackageContentsSettingOutOfSync: Bool { activity.packageContentsOutOfSync }
    var rootItem: DiskItem? { snapshot.root }
    var presentationMetrics: TreemapPresentationMetrics? { snapshot.metrics }
    var preferredSelection: DiskItem? { snapshot.selection }
    var snapshotFreshness: SnapshotFreshness { snapshot.freshness }
    var skippedItems: [ScanSkippedItem] { snapshot.skippedItems }
    var scannedFileCount: Int { rootItem == nil ? activity.fileCount : snapshot.fileCount }
    var scannedFolderCount: Int { rootItem == nil ? activity.folderCount : snapshot.folderCount }
    var scannedByteCount: UInt64 { rootItem == nil ? activity.byteCount : snapshot.byteCount }
    var scannedItemCount: Int { scannedFileCount + scannedFolderCount }
    var scanSettings: DiskScanSettings { settings }
    var freeSpaceItem: DiskItem? { snapshot.space.free }
    var otherSpaceItem: DiskItem? { snapshot.space.other }
    var showsFreeSpace: Bool { spaceVisibility.free }
    var showsOtherSpace: Bool { spaceVisibility.other }
    var hasIncompleteResults: Bool { !skippedItems.isEmpty }
    var canToggleFreeSpace: Bool { rootItem != nil && freeSpaceItem != nil }
    var canToggleOtherSpace: Bool { rootItem != nil && otherSpaceItem != nil }
    var canRefreshSnapshot: Bool {
        state != .scanning && !isUpdatingTree && !isBuildingTreemap && !operations.isBusy
    }

    func isAffectedBySkippedContent(_ item: DiskItem) -> Bool { snapshot.isAffectedBySkippedContent(item) }
    func elapsedTime(referenceDate: Date) -> TimeInterval { activity.elapsedTime(referenceDate: referenceDate) }
    func toggleFreeSpace() { if canToggleFreeSpace { spaceVisibility.free.toggle() } }
    func toggleOtherSpace() { if canToggleOtherSpace { spaceVisibility.other.toggle() } }
    func dismissFailure() { failure = nil }
    func rememberSelection(_ item: DiskItem?) { snapshot.selection = item }
    func startScan() { startScan(preservingFailure: false) }

    /// Always rescan this window's source, regardless of selection or zoom.
    func refreshSnapshot() { if canRefreshSnapshot { startScan() } }

    private func startScan(preservingFailure: Bool) {
        guard state != .scanning, !operations.isBusy else { return }
        operations.startScan(source: source, settings: settings, presentation: presentation.preferences, willStart: {
            treeOperationRevision &+= 1
            presentation.invalidate()
            activity.beginScan(path: source.path, now: Date())
            spaceVisibility = ScanSessionSpaceVisibility()
            if !preservingFailure { failure = nil }
            var next = snapshot
            next.clearForScan()
            publish(next, treeChanged: true)
        }, receive: { [weak self] in self?.receive($0) })
    }

    func cancel() {
        operations.cancel()
        presentation.invalidate()
    }

    func markTreemapRendered(for rootItem: DiskItem?) {
        guard isBuildingTreemap, self.rootItem == rootItem else { return }
        activity.isBuildingTreemap = false
        activity.treemapProgress = nil
        activity.completedAt = Date()
    }

    func updatePackageContentsSynchronization(with showPackageContents: Bool) {
        activity.packageContentsOutOfSync = settings.lookInsidePackages != showPackageContents
    }

    func rescanForPackageContentsPreference(_ showPackageContents: Bool) {
        let needed = settings.lookInsidePackages != showPackageContents || isPackageContentsSettingOutOfSync
        settings.lookInsidePackages = showPackageContents
        activity.packageContentsOutOfSync = false
        guard needed else { return }
        if !operations.requestRescan(cancelActive: true) { startScan() }
    }

    /// Captured before queue mutation; an overlapping scan/update forces fallback.
    var cleanupBaseline: ScanSessionCleanupBaseline? {
        guard state == .complete, !operations.isBusy, !isUpdatingTree, let rootItem else { return nil }
        return ScanSessionCleanupBaseline(rootID: rootItem.id, operationRevision: treeOperationRevision)
    }

    func reconcileAfterCleanup(_ batch: ScanSessionCleanupBatch) {
        guard !batch.paths.isEmpty else { return }
        guard !operations.requestRescan(cancelActive: false) else { return }
        guard let baseline = batch.baseline, cleanupBaseline == baseline,
              let rootItem else {
            startScan(preservingFailure: true)
            return
        }
        operations.reconcileCleanup(paths: batch.paths, root: rootItem, source: source,
            selectionPath: preferredSelection?.path ?? rootItem.path,
            settings: settings, presentation: presentation.preferences, willStart: {
                treeOperationRevision &+= 1
                presentation.invalidate()
                activity.isUpdatingTree = true
            }, receive: { [weak self] in self?.receive($0) })
    }

    func refresh(_ item: DiskItem) {
        guard !item.isSpecialItem else { return }
        updateTree(item, deletionMethod: nil)
    }

    func delete(_ item: DiskItem, using deletionMethod: DiskItemDeletionMethod) {
        guard DiskItemDeletionPolicy.canDelete(item) else { return }
        updateTree(item, deletionMethod: deletionMethod)
    }

    private func updateTree(_ item: DiskItem, deletionMethod: DiskItemDeletionMethod?) {
        guard state == .complete, !isUpdatingTree, !operations.isBusy,
              let rootItem, rootItem.item(atPath: item.path) != nil else { return }
        operations.update(item: item, root: rootItem, deletionMethod: deletionMethod,
                          source: source, settings: settings, presentation: presentation.preferences, willStart: {
            treeOperationRevision &+= 1
            presentation.invalidate()
            activity.isUpdatingTree = true
            failure = nil
        }, receive: { [weak self] in self?.receive($0) })
    }

    func rebuildPresentationMetrics(sharesKindColors: Bool, colorScheme: TreemapColorScheme) {
        presentation.setPreferences(sharesKindColors: sharesKindColors, colorScheme: colorScheme)
        reconcilePresentation(forceColors: true)
    }

    func updateSizeMode(_ usePhysicalSize: Bool) {
        let needed = settings.usePhysicalSize != usePhysicalSize
        settings.usePhysicalSize = usePhysicalSize
        if needed { reconcilePresentation(forceSize: true) }
    }

    private func reconcilePresentation(forceSize: Bool = false, forceColors: Bool = false) {
        guard state == .complete, !isUpdatingTree else { return }
        presentation.reconcile(snapshot: snapshot, usePhysicalSize: settings.usePhysicalSize,
                               forceSize: forceSize, forceColors: forceColors) { [weak self] in self?.receive($0) }
    }

    /// Operation identity has already been checked by the controller. Source and
    /// bookmark updates are accepted inside the same boundary as their snapshot.
    private func receive(_ event: ScanSessionOperationEvent) {
        switch event {
        case .progress(let progress): activity.apply(progress)
        case .stage(let stage): activity.stage = stage
        case .preparingTreemap:
            activity.isBuildingTreemap = true
            activity.treemapProgress = 0
        case .treemapProgress(let progress):
            if isBuildingTreemap { activity.treemapProgress = min(max(progress, 0), 1) }
        case .scanFinished(let result):
            finishScan(result)
            startPendingRescanIfNeeded()
        case .cleanupFinished(let result, let inputRoot):
            activity.isUpdatingTree = false
            // The operation gate prevents concurrent tree writers. Keep the input
            // identity check as a final guard against publishing an older tree.
            if case .success(let update) = result, rootItem == inputRoot {
                finishTree(.success(update), operation: .refresh(itemName: source.displayName), refreshStartedAt: nil, preserveSelection: true)
                startPendingRescanIfNeeded()
            } else {
                // Filesystem mutation already succeeded. A failed/cancelled local
                // edit must be followed by reconciliation, never silently dropped.
                _ = operations.consumePendingRescan()
                startScan(preservingFailure: true)
            }
        case .treeFinished(let result, let operation, let refreshStartedAt):
            finishTree(result, operation: operation, refreshStartedAt: refreshStartedAt)
            startPendingRescanIfNeeded()
        }
    }

    private func finishScan(_ result: Result<ScanSessionScanResult, Error>) {
        switch result {
        case .success(let result):
            var next = snapshot
            next.acceptScan(result, files: activity.fileCount, folders: activity.folderCount,
                            usePhysicalSize: settings.usePhysicalSize,
                            startedAt: startedAt ?? Date(), finishedAt: Date())
            activity.state = .complete
            activity.isBuildingTreemap = true
            activity.treemapProgress = nil
            activity.currentPath = result.rootItem.path
            publish(next, treeChanged: true)
            reconcilePresentation()
        case .failure(let error):
            activity.isBuildingTreemap = false
            activity.treemapProgress = nil
            activity.completedAt = Date()
            activity.state = error is CancellationError ? .cancelled : .failed
            if !(error is CancellationError) {
                failure = ScanSessionFailure(error: error, operation: .scan(itemName: source.displayName))
            }
        }
    }

    private func finishTree(_ result: Result<ScanSessionTreeUpdateResult, Error>,
                            operation: ScanSessionOperation, refreshStartedAt: Date?, preserveSelection: Bool = false) {
        activity.isUpdatingTree = false
        switch result {
        case .success(let result):
            var next = snapshot
            next.acceptTree(result, usePhysicalSize: settings.usePhysicalSize,
                            refreshStartedAt: refreshStartedAt, finishedAt: Date(), preserveSelection: preserveSelection)
            activity.currentPath = next.selection?.path ?? result.rootItem.path
            publish(next, treeChanged: true)
        case .failure(let error):
            if !(error is CancellationError) { failure = ScanSessionFailure(error: error, operation: operation) }
        }
        reconcilePresentation()
    }

    private func receive(_ update: ScanSessionPresentationUpdate) {
        guard state == .complete, !isUpdatingTree else { return }
        switch update {
        case .metrics(let metrics, let inputRoot):
            guard rootItem == inputRoot else { return }
            snapshot.metrics = metrics
        case .sizeMode(let result, let inputRoot):
            guard rootItem == inputRoot, settings.usePhysicalSize == result.usePhysicalSize else { return }
            var next = snapshot
            next.acceptSizeMode(result)
            activity.currentPath = next.selection?.path ?? result.rootItem.path
            publish(next, treeChanged: true)
            reconcilePresentation()
        }
    }

    /// A tree notification observes the completed snapshot, counts, source,
    /// freshness, and activity. Presentation-only updates do not announce a tree.
    private func publish(_ next: ScanSessionSnapshot, treeChanged: Bool) {
        if treeChanged { presentation.invalidate() }
        if next.space.free == nil { spaceVisibility = ScanSessionSpaceVisibility() }
        snapshot = next
        if treeChanged { NotificationCenter.default.post(name: .scanSessionTreeDidChange, object: self) }
    }

    private func startPendingRescanIfNeeded() {
        if operations.consumePendingRescan() { startScan(preservingFailure: true) }
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func exportTreemapInputDiagnostics() {
        guard let rootItem else {
            diagnosticsExportState = .failed("No completed scan tree is available.")
            return
        }
        diagnosticsExportState = .writing(TreemapInputDiagnostics.defaultOutputURL.path)
        ScanSessionDiagnostics.export(root: rootItem, settings: settings) { [weak self] in
            self?.diagnosticsExportState = $0
        }
    }
    #endif
}
