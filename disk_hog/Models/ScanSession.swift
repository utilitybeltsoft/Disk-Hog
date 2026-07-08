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
    @Published private(set) var errorMessage: String?
    #if FILE_MATCHING_DIAGNOSTICS
    @Published private(set) var diagnosticsExportState: DiagnosticsExportState
    #endif

    let source: ScanSource

    private let settings: DiskScanSettings
    private var scanTask: Task<Void, Never>?

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
        guard state == .scanning else {
            return
        }

        scanTask?.cancel()
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
        self.presentationMetrics = presentationMetrics
        self.rootItem = rootItem
        state = .complete
        completedAt = Date()
        scanTask = nil
        currentPath = rootItem.path
        scannedByteCount = rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize)
    }

    private func finishCancellation() {
        state = .cancelled
        completedAt = Date()
        scanTask = nil
    }

    private func finishFailure(_ error: Error) {
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
