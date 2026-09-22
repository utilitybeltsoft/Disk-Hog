import Foundation

/// Caps temporary ranking work across scan windows; retains no result cache.
actor LargestItemsWorkQueue {
    static let shared = LargestItemsWorkQueue()
    private var active = 0
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    private let concurrencyLimit: Int

    init(concurrencyLimit: Int = 2) { self.concurrencyLimit = max(1, concurrencyLimit) }

    func run(root: DiskItem, query: LargestItemsQuery) async throws -> LargestItemsResult {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try LargestItemsPipeline.run(root: root, query: query)
        }
        return try await withTaskCancellationHandler(
            operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if active < concurrencyLimit { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func release() {
        if !waiters.isEmpty { waiters.removeFirst().1.resume() }
        else { active -= 1 }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
}
