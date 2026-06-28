import Combine
import Foundation

@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var state: ScanSessionState
    @Published private(set) var startedAt: Date?
    @Published private(set) var completedAt: Date?
    @Published private(set) var scannedFileCount: Int
    @Published private(set) var scannedFolderCount: Int
    @Published private(set) var scannedByteCount: Int64
    @Published private(set) var currentPath: String

    let source: ScanSource

    init(source: ScanSource) {
        self.source = source
        self.state = .ready
        self.startedAt = nil
        self.completedAt = nil
        self.scannedFileCount = 0
        self.scannedFolderCount = 0
        self.scannedByteCount = 0
        self.currentPath = source.path
    }

    var scannedItemCount: Int {
        scannedFileCount + scannedFolderCount
    }

    func startPlaceholderScan() {
        let now: Date = Date()

        state = .scanning
        startedAt = now
        completedAt = nil
        scannedFileCount = 0
        scannedFolderCount = 0
        scannedByteCount = 0
        currentPath = source.path
    }

    func cancel() {
        guard state == .scanning else {
            return
        }

        state = .cancelled
        completedAt = Date()
    }

    func elapsedTime(referenceDate: Date) -> TimeInterval {
        guard let startedAt: Date = startedAt else {
            return .zero
        }

        let endDate: Date = completedAt ?? referenceDate
        return max(.zero, endDate.timeIntervalSince(startedAt))
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
