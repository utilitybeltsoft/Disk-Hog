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

    /// Immutable after init, so safe to read without hopping onto the actor - callers use
    /// this to size how many tasks are worth having in flight at once (see
    /// `DiskInventoryZScanner`'s bounded task submission), since a task beyond this limit
    /// would just immediately suspend waiting for a permit anyway.
    nonisolated let maximumConcurrentFilesystemTraversals: Int
    private var activeFilesystemTraversals: Int = 0
    private var waitingOrder: [UUID] = []
    private var waitingContinuations: [UUID: CheckedContinuation<ScanResourcePermit, Error>] = [:]

    init(maximumConcurrentFilesystemTraversals: Int) {
        self.maximumConcurrentFilesystemTraversals = max(1, maximumConcurrentFilesystemTraversals)
    }

    func acquireTraversalPermit() async throws -> ScanResourcePermit {
        try Task.checkCancellation()

        if activeFilesystemTraversals < maximumConcurrentFilesystemTraversals {
            activeFilesystemTraversals += 1
            return ScanResourcePermit(budget: self)
        }

        let id: UUID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waitingContinuations[id] = continuation
                waitingOrder.append(id)
            }
        } onCancel: {
            Task { await self.cancelWaiting(id) }
        }
    }

    fileprivate func releaseTraversalPermit() {
        while !waitingOrder.isEmpty {
            let nextID: UUID = waitingOrder.removeFirst()
            guard let continuation: CheckedContinuation<ScanResourcePermit, Error> = waitingContinuations.removeValue(forKey: nextID) else {
                // Already cancelled and resumed via cancelWaiting - try the next waiter.
                continue
            }
            continuation.resume(returning: ScanResourcePermit(budget: self))
            return
        }
        activeFilesystemTraversals = max(activeFilesystemTraversals - 1, 0)
    }

    private func cancelWaiting(_ id: UUID) {
        guard let continuation: CheckedContinuation<ScanResourcePermit, Error> = waitingContinuations.removeValue(forKey: id) else {
            // Already granted a permit via releaseTraversalPermit - nothing to cancel.
            return
        }
        waitingOrder.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }
}
