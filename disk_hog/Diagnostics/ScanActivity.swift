import Foundation
import OSLog

/// Diagnostic bookkeeping only; never used to schedule or gate work.
/// One short lock protects counts shared by independent scan and render tasks.
nonisolated final class ScanActivity: @unchecked Sendable {
    static let shared = ScanActivity()
    private let lock = NSLock()
    private var scans: [UUID: String] = [:]
    private var traversals = 0
    private let logger = Logger(subsystem: "software.utilitybelt.diskhog", category: "ScanPerformance")

    var summary: String {
        lock.withLock { summaryLocked() }
    }

    private func summaryLocked() -> String {
        let stages = scans.values.sorted().joined(separator: ",")
        return "activeScans=\(scans.count) activeTraversalWorkers=\(traversals) scanStages=[\(stages)]"
    }

    func begin() -> UUID {
        let id = UUID()
        let activity = lock.withLock {
            scans[id] = "starting"
            return summaryLocked()
        }
        logger.notice("scan=\(id.uuidString, privacy: .public) started \(activity, privacy: .public)")
        return id
    }

    func stage(_ stage: String, scan id: UUID) {
        let activity: String? = lock.withLock {
            guard let previous = scans[id], previous != stage else { return nil }
            scans[id] = stage
            return summaryLocked()
        }
        if let activity {
            logger.notice("scan=\(id.uuidString, privacy: .public) stage=\(stage, privacy: .public) \(activity, privacy: .public)")
        }
    }

    func end(_ id: UUID, outcome: String) {
        let activity = lock.withLock {
            scans.removeValue(forKey: id)
            return summaryLocked()
        }
        logger.notice("scan=\(id.uuidString, privacy: .public) ended outcome=\(outcome, privacy: .public) \(activity, privacy: .public)")
    }

    // Record permits in use, not waiting tasks or a claim that each worker is on CPU.
    // Avoid emitting a log for every tiny subtree in unusually wide directories.
    func traversalStarted() { lock.withLock { traversals += 1 } }
    func traversalEnded() { lock.withLock { traversals -= 1 } }
}
