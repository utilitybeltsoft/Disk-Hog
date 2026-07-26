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
    @Published private(set) var rootItem: DiskItem?
    @Published private(set) var presentationMetrics: TreemapPresentationMetrics?
    @Published private(set) var preferredSelection: DiskItem?
    @Published private(set) var showsFreeSpace: Bool
    @Published private(set) var showsOtherSpace: Bool
    @Published private(set) var freeSpaceItem: DiskItem?
    @Published private(set) var otherSpaceItem: DiskItem?
    @Published private(set) var isUpdatingTree: Bool
    @Published private(set) var isBuildingTreemap: Bool
    @Published private(set) var errorMessage: String?
    #if FILE_MATCHING_DIAGNOSTICS
    @Published private(set) var diagnosticsExportState: DiagnosticsExportState
    #endif

    let source: ScanSource

    private let settings: DiskScanSettings
    private var scanTask: Task<Void, Never>?
    private var treeUpdateTask: Task<Void, Never>?

    init(source: ScanSource) {
        self.source = source
        self.settings = source.scanSettings ?? .diskInventoryZDefault
        self.state = .ready
        self.startedAt = nil
        self.completedAt = nil
        self.scannedFileCount = 0
        self.scannedFolderCount = 0
        self.scannedByteCount = 0
        self.currentPath = source.path
        self.rootItem = nil
        self.presentationMetrics = nil
        self.preferredSelection = nil
        self.showsFreeSpace = false
        self.showsOtherSpace = false
        self.freeSpaceItem = nil
        self.otherSpaceItem = nil
        self.isUpdatingTree = false
        self.isBuildingTreemap = false
        self.errorMessage = nil
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
        guard state != .scanning else {
            return
        }

        let now: Date = Date()

        state = .scanning
        startedAt = now
        completedAt = nil
        scannedFileCount = 0
        scannedFolderCount = 0
        scannedByteCount = 0
        currentPath = source.path
        rootItem = nil
        presentationMetrics = nil
        preferredSelection = nil
        showsFreeSpace = false
        showsOtherSpace = false
        freeSpaceItem = nil
        otherSpaceItem = nil
        isUpdatingTree = false
        isBuildingTreemap = false
        errorMessage = nil

        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let progressStream: AsyncStream<DiskScanProgress>
        let progressContinuation: AsyncStream<DiskScanProgress>.Continuation

        (progressStream, progressContinuation) = AsyncStream.makeStream(of: DiskScanProgress.self)

        let progressTask: Task<Void, Never> = Task { [weak self] in
            for await progress: DiskScanProgress in progressStream {
                self?.applyProgress(progress)
            }
        }

        scanTask = Task.detached(priority: .userInitiated) {
            do {
                let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
                let rootItem: DiskItem = try await scanner.scan(
                    source: source,
                    settings: settings
                ) { progress in
                    progressContinuation.yield(progress)
                }

                progressContinuation.finish()
                await progressTask.value
                try Task.checkCancellation()
                await MainActor.run {
                    self.isBuildingTreemap = true
                }
                let presentationMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
                    rootItem: rootItem,
                    usePhysicalSize: settings.usePhysicalSize
                )
                try Task.checkCancellation()

                await MainActor.run {
                    self.finishScan(rootItem: rootItem, presentationMetrics: presentationMetrics)
                }
            } catch is CancellationError {
                progressContinuation.finish()
                await progressTask.value
                await MainActor.run {
                    self.finishCancellation()
                }
            } catch {
                progressContinuation.finish()
                await progressTask.value
                await MainActor.run {
                    self.finishFailure(error)
                }
            }
        }
    }

    func cancel() {
        if state == .scanning {
            scanTask?.cancel()
        }
        treeUpdateTask?.cancel()
    }

    func refresh(_ item: DiskItem) {
        guard state == .complete,
              !isUpdatingTree,
              !item.isSpecialItem,
              let currentRoot: DiskItem = rootItem,
              currentRoot.item(atPath: item.path) != nil else {
            return
        }

        beginTreeUpdate()
        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let requestedSelectionPath: String = item.path

        treeUpdateTask = Task.detached(priority: .userInitiated) {
            do {
                let refreshPath: String = Self.nearestExistingPath(from: item.path, stoppingAt: currentRoot.path)
                let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
                let updatedRoot: DiskItem
                if refreshPath == currentRoot.path {
                    updatedRoot = try await scanner.scan(source: source, settings: settings)
                } else {
                    let refreshedItem: DiskItem = try await scanner.scanItem(
                        at: URL(fileURLWithPath: refreshPath),
                        from: source,
                        settings: settings
                    )
                    guard let replacementRoot: DiskItem = currentRoot.replacingSubtree(
                        atPath: refreshPath,
                        with: refreshedItem,
                        usePhysicalSize: settings.usePhysicalSize
                    ) else {
                        throw DiskScannerError.traversalInconsistency("The refreshed item was no longer present in the scan tree.")
                    }
                    updatedRoot = replacementRoot
                }

                let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
                    rootItem: updatedRoot,
                    usePhysicalSize: settings.usePhysicalSize
                )
                await MainActor.run {
                    self.finishTreeUpdate(
                        rootItem: updatedRoot,
                        presentationMetrics: metrics,
                        selectionPath: requestedSelectionPath
                    )
                }
            } catch is CancellationError {
                await MainActor.run { self.finishTreeUpdateCancellation() }
            } catch {
                await MainActor.run { self.finishTreeUpdateFailure(error) }
            }
        }
    }

    func moveToTrash(_ item: DiskItem) {
        guard state == .complete,
              !isUpdatingTree,
              !item.isSpecialItem,
              !item.isRoot,
              let currentRoot: DiskItem = rootItem,
              currentRoot.item(atPath: item.path) != nil else {
            return
        }

        beginTreeUpdate()
        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let parentPath: String = item.url.deletingLastPathComponent().path

        treeUpdateTask = Task.detached(priority: .userInitiated) {
            do {
                let rootURL: URL = try source.resolvedURL()
                let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
                defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }

                let values: URLResourceValues = try item.url.resourceValues(forKeys: [.volumeIsLocalKey])
                if values.volumeIsLocal == false {
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                }
                try Task.checkCancellation()

                guard let updatedRoot: DiskItem = currentRoot.removingSubtree(
                    atPath: item.path,
                    usePhysicalSize: settings.usePhysicalSize
                ) else {
                    throw DiskScannerError.traversalInconsistency("The trashed item was no longer present in the scan tree.")
                }
                let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
                    rootItem: updatedRoot,
                    usePhysicalSize: settings.usePhysicalSize
                )
                await MainActor.run {
                    self.finishTreeUpdate(
                        rootItem: updatedRoot,
                        presentationMetrics: metrics,
                        selectionPath: parentPath
                    )
                }
            } catch is CancellationError {
                await MainActor.run { self.finishTreeUpdateCancellation() }
            } catch {
                await MainActor.run { self.finishTreeUpdateFailure(error) }
            }
        }
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

        Task.detached(priority: .utility) {
            do {
                let outputURL: URL = try TreemapInputDiagnostics.writeJSONLinesReport(
                    root: rootItem,
                    settings: settings
                )
                await MainActor.run {
                    let pasteboard: NSPasteboard = .general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([outputURL as NSURL])
                    pasteboard.setString(outputURL.path, forType: .string)
                    self.diagnosticsExportState = .written(outputURL.path)
                }
            } catch {
                await MainActor.run {
                    self.diagnosticsExportState = .failed(String(describing: error))
                    NSSound.beep()
                }
            }
        }
    }
    #endif

    private func applyProgress(_ progress: DiskScanProgress) {
        guard state == .scanning else {
            return
        }

        scannedFileCount = progress.scannedFileCount
        scannedFolderCount = progress.scannedFolderCount
        scannedByteCount = progress.scannedByteCount
        currentPath = progress.currentPath
    }

    private func finishScan(rootItem: DiskItem, presentationMetrics: TreemapPresentationMetrics) {
        isBuildingTreemap = false
        self.presentationMetrics = presentationMetrics
        updateSpaceItems(for: rootItem)
        preferredSelection = rootItem
        self.rootItem = rootItem
        state = .complete
        completedAt = Date()
        scanTask = nil
        currentPath = rootItem.path
        scannedByteCount = rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
    }

    private func beginTreeUpdate() {
        isUpdatingTree = true
        errorMessage = nil
    }

    private func finishTreeUpdate(
        rootItem: DiskItem,
        presentationMetrics: TreemapPresentationMetrics,
        selectionPath: String
    ) {
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
        treeUpdateTask = nil
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

    private func finishTreeUpdateCancellation() {
        isUpdatingTree = false
        treeUpdateTask = nil
    }

    private func finishTreeUpdateFailure(_ error: Error) {
        isUpdatingTree = false
        treeUpdateTask = nil
        errorMessage = error.localizedDescription
    }

    nonisolated private static func nearestExistingPath(from path: String, stoppingAt rootPath: String) -> String {
        var candidateURL: URL = URL(fileURLWithPath: path).standardizedFileURL
        let standardizedRootPath: String = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        while !FileManager.default.fileExists(atPath: candidateURL.path) {
            guard candidateURL.path != standardizedRootPath else {
                return standardizedRootPath
            }
            let parentURL: URL = candidateURL.deletingLastPathComponent()
            guard parentURL.path != candidateURL.path else {
                return standardizedRootPath
            }
            candidateURL = parentURL
        }
        return candidateURL.path
    }

    private func finishCancellation() {
        isBuildingTreemap = false
        state = .cancelled
        completedAt = Date()
        scanTask = nil
    }

    private func finishFailure(_ error: Error) {
        isBuildingTreemap = false
        state = .failed
        completedAt = Date()
        scanTask = nil
        errorMessage = error.localizedDescription
    }
}

enum ScanSessionState: Hashable {
    case ready
    case scanning
    case complete
    case cancelled
    case failed

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .scanning:
            return "Scanning"
        case .complete:
            return "Complete"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

#if FILE_MATCHING_DIAGNOSTICS
enum DiagnosticsExportState: Hashable {
    case idle
    case writing(String)
    case written(String)
    case failed(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .writing(let path):
            return "Writing diagnostics: \(path)"
        case .written(let path):
            return "Diagnostics written: \(path)"
        case .failed(let message):
            return "Diagnostics failed: \(message)"
        }
    }

    var isWriting: Bool {
        if case .writing = self {
            return true
        }

        return false
    }
}
#endif
