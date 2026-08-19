#if FILE_MATCHING_DIAGNOSTICS
import AppKit
#endif
import Combine
import Foundation

@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var state: ScanSessionState
    @Published private(set) var startedAt: Date?
    @Published private(set) var completedAt: Date?
    @Published private(set) var scannedFileCount: Int
    @Published private(set) var scannedFolderCount: Int
    @Published private(set) var scannedByteCount: UInt64
    @Published private(set) var currentPath: String
    @Published private(set) var scanStage: DiskScanStage
    @Published private(set) var rootItem: DiskItem? {
        didSet {
            NotificationCenter.default.post(name: .scanSessionTreeDidChange, object: self)
        }
    }
    @Published private(set) var presentationMetrics: TreemapPresentationMetrics?
    @Published private(set) var preferredSelection: DiskItem?
    @Published private(set) var showsFreeSpace: Bool
    @Published private(set) var showsOtherSpace: Bool
    @Published private(set) var freeSpaceItem: DiskItem?
    @Published private(set) var otherSpaceItem: DiskItem?
    @Published private(set) var isUpdatingTree: Bool
    @Published private(set) var isBuildingTreemap: Bool
    @Published private(set) var treemapPreparationProgress: Double?
    @Published private(set) var isPackageContentsSettingOutOfSync: Bool
    @Published private(set) var failure: ScanSessionFailure?
    #if FILE_MATCHING_DIAGNOSTICS
    @Published private(set) var diagnosticsExportState: DiagnosticsExportState
    #endif

    private(set) var source: ScanSource

    private var settings: DiskScanSettings
    private let scanWorker: any ScanSessionScanning
    private let treeWorker: any ScanSessionTreeUpdating
    private let presentationWorker: any ScanSessionPresenting
    private let taskCoordinator: ScanSessionTaskCoordinator = ScanSessionTaskCoordinator()
    private var rescanCoordinator: ScanSessionRescanCoordinator = ScanSessionRescanCoordinator()

    init(
        source: ScanSource,
        scanWorker: any ScanSessionScanning = DiskInventoryZScanSessionWorker(),
        treeWorker: any ScanSessionTreeUpdating = DiskInventoryZScanSessionTreeWorker(),
        presentationWorker: any ScanSessionPresenting = DiskInventoryZScanSessionPresentationWorker()
    ) {
        self.source = source
        self.settings = source.scanSettings ?? .diskInventoryZDefault
        self.scanWorker = scanWorker
        self.treeWorker = treeWorker
        self.presentationWorker = presentationWorker
        self.state = .ready
        self.startedAt = nil
        self.completedAt = nil
        self.scannedFileCount = 0
        self.scannedFolderCount = 0
        self.scannedByteCount = 0
        self.currentPath = source.path
        self.scanStage = .enumeratingRootItems
        self.rootItem = nil
        self.presentationMetrics = nil
        self.preferredSelection = nil
        self.showsFreeSpace = false
        self.showsOtherSpace = false
        self.freeSpaceItem = nil
        self.otherSpaceItem = nil
        self.isUpdatingTree = false
        self.isBuildingTreemap = false
        self.treemapPreparationProgress = nil
        self.isPackageContentsSettingOutOfSync = false
        self.failure = nil
        #if FILE_MATCHING_DIAGNOSTICS
        self.diagnosticsExportState = .idle
        #endif
    }

    var scannedItemCount: Int {
        scannedFileCount + scannedFolderCount
    }

    var scanSettings: DiskScanSettings {
        settings
    }

    var canToggleFreeSpace: Bool {
        rootItem != nil && freeSpaceItem != nil
    }

    var canToggleOtherSpace: Bool {
        rootItem != nil && otherSpaceItem != nil
    }

    func toggleFreeSpace() {
        guard canToggleFreeSpace else {
            return
        }
        showsFreeSpace.toggle()
    }

    func toggleOtherSpace() {
        guard canToggleOtherSpace else {
            return
        }
        showsOtherSpace.toggle()
    }

    func startScan() {
        startScan(preservingFailure: false)
    }

    func dismissFailure() {
        failure = nil
    }

    private func startScan(preservingFailure: Bool) {
        guard state != .scanning,
              rescanCoordinator.activeOperation == nil else {
            return
        }

        let operation: ScanSessionWorkOperation = rescanCoordinator.beginScan()

        taskCoordinator.cancel(.presentationUpdate)
        taskCoordinator.cancel(.sizeModeUpdate)

        let now: Date = Date()

        state = .scanning
        startedAt = now
        completedAt = nil
        scannedFileCount = 0
        scannedFolderCount = 0
        scannedByteCount = 0
        currentPath = source.path
        scanStage = .enumeratingRootItems
        rootItem = nil
        presentationMetrics = nil
        preferredSelection = nil
        showsFreeSpace = false
        showsOtherSpace = false
        freeSpaceItem = nil
        otherSpaceItem = nil
        isUpdatingTree = false
        isBuildingTreemap = false
        treemapPreparationProgress = nil
        if !preservingFailure {
            failure = nil
        }

        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let scanWorker: any ScanSessionScanning = scanWorker
        let sessionReference: ScanSessionWeakReference = ScanSessionWeakReference(self)
        _ = taskCoordinator.start(.scan, operationID: operation.id) { _ in Task.detached(priority: .userInitiated) { [sessionReference] in
            do {
                let result: ScanSessionScanResult = try await scanWorker.scan(
                    source: source,
                    settings: settings,
                    progress: { progress in
                        await MainActor.run {
                            sessionReference.value?.applyProgress(progress, for: operation)
                        }
                    },
                    stage: { stage in
                        await MainActor.run {
                            sessionReference.value?.applyScanStage(stage, for: operation)
                        }
                    },
                    willBuildTreemap: {
                        await MainActor.run {
                            sessionReference.value?.beginTreemapPreparation(for: operation)
                        }
                    },
                    treemapProgress: { progress in
                        await MainActor.run {
                            sessionReference.value?.applyTreemapPreparationProgress(progress, for: operation)
                        }
                    }
                )

                await MainActor.run {
                    sessionReference.value?.source = result.source
                    sessionReference.value?.finishScan(
                        rootItem: result.rootItem,
                        presentationMetrics: result.presentationMetrics,
                        builtUsingPhysicalSize: result.builtUsingPhysicalSize,
                        operation: operation
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    sessionReference.value?.finishCancellation(for: operation)
                }
            } catch {
                await MainActor.run {
                    sessionReference.value?.finishFailure(error, for: operation)
                }
            }
        } }
    }

    func cancel() {
        if state == .scanning {
            taskCoordinator.cancel(.scan)
        }
        taskCoordinator.cancel(.treeUpdate)
        taskCoordinator.cancel(.presentationUpdate)
        taskCoordinator.cancel(.sizeModeUpdate)
    }

    func markTreemapRendered(for rootItem: DiskItem?) {
        guard isBuildingTreemap,
              self.rootItem === rootItem else {
            return
        }

        isBuildingTreemap = false
        treemapPreparationProgress = nil
    }

    func updatePackageContentsSynchronization(with showPackageContents: Bool) {
        isPackageContentsSettingOutOfSync = settings.lookInsidePackages != showPackageContents
    }

    func rememberSelection(_ item: DiskItem?) {
        preferredSelection = item
    }

    func rescanForPackageContentsPreference(_ showPackageContents: Bool) {
        let needsRescan: Bool = settings.lookInsidePackages != showPackageContents
            || isPackageContentsSettingOutOfSync
        settings.lookInsidePackages = showPackageContents
        isPackageContentsSettingOutOfSync = false

        guard needsRescan else {
            return
        }

        guard let activeOperation: ScanSessionWorkOperation = rescanCoordinator.requestRescan() else {
            startScan()
            return
        }

        switch activeOperation {
        case .scan:
            taskCoordinator.cancel(.scan)
        case .treeUpdate:
            taskCoordinator.cancel(.treeUpdate)
        }
    }

    func refresh(_ item: DiskItem) {
        guard state == .complete,
              !isUpdatingTree,
              !item.isSpecialItem,
              let currentRoot: DiskItem = rootItem,
              currentRoot.item(atPath: item.path) != nil else {
            return
        }

        let operation: ScanSessionWorkOperation = beginTreeUpdate()
        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let treeWorker: any ScanSessionTreeUpdating = treeWorker
        let sessionReference: ScanSessionWeakReference = ScanSessionWeakReference(self)

        _ = taskCoordinator.start(.treeUpdate, operationID: operation.id) { _ in Task.detached(priority: .userInitiated) { [sessionReference] in
            do {
                let result: ScanSessionTreeUpdateResult = try await treeWorker.refresh(
                    item: item,
                    currentRoot: currentRoot,
                    source: source,
                    settings: settings
                )
                await MainActor.run {
                    sessionReference.value?.source = result.source
                    sessionReference.value?.finishTreeUpdate(
                        rootItem: result.rootItem,
                        presentationMetrics: result.presentationMetrics,
                        selectionPath: result.selectionPath,
                        builtUsingPhysicalSize: result.builtUsingPhysicalSize,
                        operation: operation
                    )
                }
            } catch is CancellationError {
                await MainActor.run { sessionReference.value?.finishTreeUpdateCancellation(for: operation) }
            } catch {
                await MainActor.run {
                    sessionReference.value?.finishTreeUpdateFailure(
                        error,
                        operation: .refresh(itemName: item.displayName),
                        workOperation: operation
                    )
                }
            }
        } }
    }

    func delete(_ item: DiskItem, using deletionMethod: DiskItemDeletionMethod) {
        guard state == .complete,
              !isUpdatingTree,
              DiskItemDeletionPolicy.canDelete(item),
              let currentRoot: DiskItem = rootItem,
              currentRoot.item(atPath: item.path) != nil else {
            return
        }

        let operation: ScanSessionWorkOperation = beginTreeUpdate()
        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let treeWorker: any ScanSessionTreeUpdating = treeWorker
        let sessionReference: ScanSessionWeakReference = ScanSessionWeakReference(self)

        _ = taskCoordinator.start(.treeUpdate, operationID: operation.id) { _ in Task.detached(priority: .userInitiated) { [sessionReference] in
            do {
                let result: ScanSessionTreeUpdateResult = try await treeWorker.delete(
                    item: item,
                    deletionMethod: deletionMethod,
                    currentRoot: currentRoot,
                    source: source,
                    settings: settings
                )
                await MainActor.run {
                    sessionReference.value?.source = result.source
                    sessionReference.value?.finishTreeUpdate(
                        rootItem: result.rootItem,
                        presentationMetrics: result.presentationMetrics,
                        selectionPath: result.selectionPath,
                        builtUsingPhysicalSize: result.builtUsingPhysicalSize,
                        operation: operation
                    )
                }
            } catch is CancellationError {
                await MainActor.run { sessionReference.value?.finishTreeUpdateCancellation(for: operation) }
            } catch {
                await MainActor.run {
                    sessionReference.value?.finishTreeUpdateFailure(
                        error,
                        operation: .deletion(
                            itemName: item.displayName,
                            method: deletionMethod
                        ),
                        workOperation: operation
                    )
                }
            }
        } }
    }

    func rebuildPresentationMetrics(
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) {
        guard state == .complete,
              let rootItem: DiskItem else {
            return
        }

        let usePhysicalSize: Bool = settings.usePhysicalSize
        let presentationWorker: any ScanSessionPresenting = presentationWorker
        _ = taskCoordinator.start(.presentationUpdate) { [weak self] updateID in Task.detached(priority: .userInitiated) {
            let metrics: TreemapPresentationMetrics = presentationWorker.presentationMetrics(
                rootItem: rootItem,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: sharesKindColors,
                colorScheme: colorScheme
            )
            guard !Task.isCancelled else {
                await MainActor.run { [weak self] in
                    self?.finishPresentationUpdate(id: updateID, metrics: nil)
                }
                return
            }
            await MainActor.run { [weak self] in
                self?.finishPresentationUpdate(id: updateID, metrics: metrics)
            }
        } }
    }

    func updateSizeMode(_ usePhysicalSize: Bool) {
        let needsRebuild: Bool = settings.usePhysicalSize != usePhysicalSize
        settings.usePhysicalSize = usePhysicalSize

        guard needsRebuild,
              state == .complete,
              !isUpdatingTree,
              let rootItem: DiskItem else {
            return
        }

        rebuildForSizeMode(rootItem: rootItem, usePhysicalSize: usePhysicalSize)
    }

    func elapsedTime(referenceDate: Date) -> TimeInterval {
        guard let startedAt: Date = startedAt else {
            return .zero
        }

        let endDate: Date = completedAt ?? referenceDate
        return max(.zero, endDate.timeIntervalSince(startedAt))
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func exportTreemapInputDiagnostics() {
        guard let rootItem: DiskItem = rootItem else {
            diagnosticsExportState = .failed("No completed scan tree is available.")
            return
        }

        let settings: DiskScanSettings = settings
        diagnosticsExportState = .writing(TreemapInputDiagnostics.defaultOutputURL.path)

        Task.detached(priority: .utility) { [weak self] in
            do {
                let outputURL: URL = try TreemapInputDiagnostics.writeJSONLinesReport(
                    root: rootItem,
                    settings: settings
                )
                await MainActor.run { [weak self] in
                    let pasteboard: NSPasteboard = .general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([outputURL as NSURL])
                    pasteboard.setString(outputURL.path, forType: .string)
                    self?.diagnosticsExportState = .written(outputURL.path)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.diagnosticsExportState = .failed(String(describing: error))
                }
            }
        }
    }
    #endif

    private func applyProgress(_ progress: DiskScanProgress, for operation: ScanSessionWorkOperation) {
        guard state == .scanning,
              rescanCoordinator.activeOperation == operation else {
            return
        }

        scannedFileCount = progress.scannedFileCount
        scannedFolderCount = progress.scannedFolderCount
        scannedByteCount = progress.scannedByteCount
        currentPath = progress.currentPath
    }

    private func applyScanStage(_ stage: DiskScanStage, for operation: ScanSessionWorkOperation) {
        guard state == .scanning,
              rescanCoordinator.activeOperation == operation else {
            return
        }

        scanStage = stage
    }

    private func finishScan(
        rootItem: DiskItem,
        presentationMetrics: TreemapPresentationMetrics,
        builtUsingPhysicalSize: Bool,
        operation: ScanSessionWorkOperation
    ) {
        guard taskCoordinator.finish(.scan, operationID: operation.id),
              rescanCoordinator.finish(operation) else {
            return
        }
        isBuildingTreemap = true
        treemapPreparationProgress = 1
        self.presentationMetrics = presentationMetrics
        updateSpaceItems(for: rootItem)
        preferredSelection = rootItem
        self.rootItem = rootItem
        state = .complete
        completedAt = Date()
        currentPath = rootItem.path
        scannedByteCount = rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
        if builtUsingPhysicalSize != settings.usePhysicalSize {
            rebuildForSizeMode(rootItem: rootItem, usePhysicalSize: settings.usePhysicalSize)
        }
        startPendingRescanIfNeeded()
    }

    private func beginTreeUpdate() -> ScanSessionWorkOperation {
        let operation: ScanSessionWorkOperation = rescanCoordinator.beginTreeUpdate()
        isUpdatingTree = true
        failure = nil
        return operation
    }

    private func finishPresentationUpdate(id: UUID, metrics: TreemapPresentationMetrics?) {
        guard taskCoordinator.finish(.presentationUpdate, operationID: id),
              state == .complete else {
            return
        }
        if let metrics {
            presentationMetrics = metrics
        }
    }

    private func finishTreeUpdate(
        rootItem: DiskItem,
        presentationMetrics: TreemapPresentationMetrics,
        selectionPath: String,
        builtUsingPhysicalSize: Bool,
        operation: ScanSessionWorkOperation
    ) {
        guard taskCoordinator.finish(.treeUpdate, operationID: operation.id),
              rescanCoordinator.finish(operation) else {
            return
        }
        let counts: (files: Int, folders: Int) = rootItem.scanCounts(includeSelf: false)
        preferredSelection = rootItem.item(atPath: selectionPath, allowAncestors: true) ?? rootItem
        self.presentationMetrics = presentationMetrics
        updateSpaceItems(for: rootItem)
        self.rootItem = rootItem
        scannedFileCount = counts.files
        scannedFolderCount = counts.folders
        scannedByteCount = rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
        currentPath = preferredSelection?.path ?? rootItem.path
        isUpdatingTree = false
        if builtUsingPhysicalSize != settings.usePhysicalSize {
            rebuildForSizeMode(rootItem: rootItem, usePhysicalSize: settings.usePhysicalSize)
        }
        startPendingRescanIfNeeded()
    }

    private func rebuildForSizeMode(rootItem: DiskItem, usePhysicalSize: Bool) {
        let selectionPath: String = preferredSelection?.path ?? rootItem.path
        let presentationWorker: any ScanSessionPresenting = presentationWorker
        _ = taskCoordinator.start(.sizeModeUpdate) { [weak self] updateID in Task.detached(priority: .userInitiated) {
            let result: ScanSessionSizeModeUpdateResult = presentationWorker.sizeModeUpdate(
                rootItem: rootItem,
                selectionPath: selectionPath,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: ScanPreferenceDefaults.sharesKindColors,
                colorScheme: ScanPreferenceDefaults.treemapColorScheme
            )
            guard !Task.isCancelled else {
                await MainActor.run { [weak self] in
                    self?.finishSizeModeUpdate(id: updateID, result: nil)
                }
                return
            }
            await MainActor.run { [weak self] in
                self?.finishSizeModeUpdate(id: updateID, result: result)
            }
        } }
    }

    private func finishSizeModeUpdate(
        id: UUID,
        result: ScanSessionSizeModeUpdateResult?
    ) {
        guard taskCoordinator.finish(.sizeModeUpdate, operationID: id),
              state == .complete,
              let result,
              settings.usePhysicalSize == result.usePhysicalSize else {
            return
        }
        preferredSelection = result.rootItem.item(
            atPath: result.selectionPath,
            allowAncestors: true
        ) ?? result.rootItem
        presentationMetrics = result.presentationMetrics
        updateSpaceItems(for: result.rootItem)
        rootItem = result.rootItem
        scannedByteCount = result.rootItem.sizeValue(usePhysicalSize: result.usePhysicalSize)
        currentPath = preferredSelection?.path ?? result.rootItem.path
    }

    private func updateSpaceItems(for rootItem: DiskItem) {
        guard source.bookmarkData == nil,
              let totalCapacity: UInt64 = source.totalCapacity,
              let availableCapacity: UInt64 = source.availableCapacity,
              totalCapacity >= availableCapacity else {
            freeSpaceItem = nil
            otherSpaceItem = nil
            showsFreeSpace = false
            showsOtherSpace = false
            return
        }

        let scannedSize: UInt64 = rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
        let usedCapacity: UInt64 = totalCapacity - availableCapacity
        let otherSpaceSize: UInt64 = usedCapacity > scannedSize ? usedCapacity - scannedSize : 0

        freeSpaceItem = DiskItem(
            url: source.url,
            itemType: .freeSpace,
            allocatedSizeValue: availableCapacity,
            logicalSizeValue: availableCapacity
        )
        otherSpaceItem = DiskItem(
            url: source.url,
            itemType: .otherSpace,
            allocatedSizeValue: otherSpaceSize,
            logicalSizeValue: otherSpaceSize
        )
    }

    private func finishTreeUpdateCancellation(for operation: ScanSessionWorkOperation) {
        guard taskCoordinator.finish(.treeUpdate, operationID: operation.id),
              rescanCoordinator.finish(operation) else {
            return
        }
        isUpdatingTree = false
        startPendingRescanIfNeeded()
    }

    private func finishTreeUpdateFailure(
        _ error: Error,
        operation: ScanSessionOperation,
        workOperation: ScanSessionWorkOperation
    ) {
        guard taskCoordinator.finish(.treeUpdate, operationID: workOperation.id),
              rescanCoordinator.finish(workOperation) else {
            return
        }
        isUpdatingTree = false
        failure = ScanSessionFailure(error: error, operation: operation)
        startPendingRescanIfNeeded()
    }

    private func finishCancellation(for operation: ScanSessionWorkOperation) {
        guard taskCoordinator.finish(.scan, operationID: operation.id),
              rescanCoordinator.finish(operation) else {
            return
        }
        isBuildingTreemap = false
        treemapPreparationProgress = nil
        state = .cancelled
        completedAt = Date()
        startPendingRescanIfNeeded()
    }

    private func finishFailure(_ error: Error, for operation: ScanSessionWorkOperation) {
        guard taskCoordinator.finish(.scan, operationID: operation.id),
              rescanCoordinator.finish(operation) else {
            return
        }
        isBuildingTreemap = false
        treemapPreparationProgress = nil
        state = .failed
        completedAt = Date()
        failure = ScanSessionFailure(
            error: error,
            operation: .scan(itemName: source.displayName)
        )
        startPendingRescanIfNeeded()
    }

    private func beginTreemapPreparation(for operation: ScanSessionWorkOperation) {
        guard rescanCoordinator.activeOperation == operation else {
            return
        }
        isBuildingTreemap = true
        treemapPreparationProgress = 0
    }

    private func applyTreemapPreparationProgress(
        _ progress: Double,
        for operation: ScanSessionWorkOperation
    ) {
        guard isBuildingTreemap,
              rescanCoordinator.activeOperation == operation else {
            return
        }
        treemapPreparationProgress = min(max(progress, 0), 1)
    }

    private func startPendingRescanIfNeeded() {
        guard rescanCoordinator.consumePendingRescan() else {
            return
        }
        startScan(preservingFailure: true)
    }
}
