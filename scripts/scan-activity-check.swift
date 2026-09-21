import Foundation

@main struct ScanActivityCheck {
    static func main() async throws {
        let activity = ScanActivity.shared
        let first = activity.begin()
        let second = activity.begin()
        activity.stage("packaging", scan: first)
        activity.stage("scanning", scan: second)
        precondition(activity.summary.contains("activeScans=2 "))
        precondition(activity.summary.contains("scanStages=[packaging,scanning]"))
        activity.end(first, outcome: "completed")
        activity.end(second, outcome: "cancelled")
        // A late stage callback must not recreate a completed scan.
        activity.stage("finalizing", scan: second)
        precondition(activity.summary.contains("activeScans=0 "))

        let budget = ScanResourceBudget(maximumConcurrentFilesystemTraversals: 2)
        let permit = try await budget.acquireTraversalPermit()
        precondition(activity.summary.contains("activeTraversalWorkers=1 "))
        await permit.release()
        await permit.release()
        precondition(activity.summary.contains("activeTraversalWorkers=0 "))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let permit = try await budget.acquireTraversalPermit()
                    await Task.yield()
                    await permit.release()
                }
            }
            try await group.waitForAll()
        }
        precondition(activity.summary.contains("activeTraversalWorkers=0 "))
        await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let permit = try await budget.acquireTraversalPermit()
                await permit.release()
                preconditionFailure("Cancelled acquisition succeeded")
            } catch is CancellationError {
                // No permit should have been counted.
            } catch {
                preconditionFailure("Unexpected error: \(error)")
            }
        }.value
        precondition(activity.summary.contains("activeTraversalWorkers=0 "))
        print("PASS: scan stages/lifecycle, permit handoff, idempotent release, cancellation counts")
    }
}
