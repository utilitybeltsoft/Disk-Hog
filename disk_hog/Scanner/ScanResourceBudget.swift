import Foundation

nonisolated final class ScanResourcePermit: @unchecked Sendable {
    private let budget: ScanResourceBudget
    private let lock: NSLock = NSLock()
    private var isReleased: Bool = false

    init(budget: ScanResourceBudget) {
        self.budget = budget
    }

    func release() async {
        guard markReleased() else {
            return
        }

        await budget.releaseTraversalPermit()
    }

    deinit {
        guard markReleased() else {
            return
        }

        Task { [budget] in
            await budget.releaseTraversalPermit()
        }
    }

    private func markReleased() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isReleased else {
            return false
        }
        isReleased = true
        return true
    }
}

actor ScanResourceBudget {
    static let shared: ScanResourceBudget = ScanResourceBudget(
        maximumConcurrentFilesystemTraversals: ScanResourceBudget.defaultTraversalLimit
    )

    private static let defaultTraversalLimit: Int = max(
        4,
        min(8, ProcessInfo.processInfo.activeProcessorCount)
    )

    private let maximumConcurrentFilesystemTraversals: Int
    private var activeFilesystemTraversals: Int = 0
    private var waitingContinuations: [CheckedContinuation<ScanResourcePermit, Never>] = []

    init(maximumConcurrentFilesystemTraversals: Int) {
        self.maximumConcurrentFilesystemTraversals = max(1, maximumConcurrentFilesystemTraversals)
    }

    func acquireTraversalPermit() async -> ScanResourcePermit {
        if activeFilesystemTraversals < maximumConcurrentFilesystemTraversals {
            activeFilesystemTraversals += 1
            return ScanResourcePermit(budget: self)
        }

        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    fileprivate func releaseTraversalPermit() {
        if waitingContinuations.isEmpty {
            activeFilesystemTraversals = max(activeFilesystemTraversals - 1, 0)
            return
        }

        let continuation: CheckedContinuation<ScanResourcePermit, Never> = waitingContinuations.removeFirst()
        continuation.resume(returning: ScanResourcePermit(budget: self))
    }
}
