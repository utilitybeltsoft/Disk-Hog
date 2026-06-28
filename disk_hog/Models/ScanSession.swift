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
    @Published private(set) var errorMessage: String?

    let source: ScanSource

    private let settings: DiskScanSettings
    private let scanner: DiskInventoryZScanner
    private var scanTask: Task<Void, Never>?

    init(source: ScanSource) {
        self.source = source
        self.settings = .diskInventoryZDefault
        self.scanner = DiskInventoryZScanner()
        self.state = .ready
        self.startedAt = nil
        self.completedAt = nil
        self.scannedFileCount = 0
        self.scannedFolderCount = 0
        self.scannedByteCount = 0
        self.currentPath = source.path
        self.rootItem = nil
        self.errorMessage = nil
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
        errorMessage = nil

        let source: ScanSource = source
        let settings: DiskScanSettings = settings
        let scanner: DiskInventoryZScanner = scanner

        scanTask = Task.detached(priority: .userInitiated) {
            do {
                let rootItem: DiskItem = try scanner.scan(
                    source: source,
                    settings: settings
                ) { progress in
                    Task { @MainActor in
                        self.applyProgress(progress)
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    self.finishScan(rootItem: rootItem)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.finishCancellation()
                }
            } catch {
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

    func writeTreemapInputDiagnostics() throws -> URL {
        guard let rootItem: DiskItem = rootItem else {
            throw CocoaError(.fileNoSuchFile)
        }

        try TreemapInputDiagnostics.writeJSONLinesReport(
            root: rootItem,
            settings: settings
        )
        return TreemapInputDiagnostics.defaultOutputURL
    }

    private func applyProgress(_ progress: DiskScanProgress) {
        guard state == .scanning else {
            return
        }

        scannedFileCount = progress.scannedFileCount
        scannedFolderCount = progress.scannedFolderCount
        scannedByteCount = progress.scannedByteCount
        currentPath = progress.currentPath
    }

    private func finishScan(rootItem: DiskItem) {
        self.rootItem = rootItem
        state = .complete
        completedAt = Date()
        scanTask = nil
        currentPath = rootItem.path
        scannedByteCount = rootItem.allocatedSizeValue
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
        errorMessage = String(describing: error)
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
