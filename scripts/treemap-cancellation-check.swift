import Foundation

// Compile with the same production sources as treemap-benchmark.swift.
@main struct TreemapCancellationCheck {
    static func main() async throws {
        let builder = DiskItemBuilder(url: URL(fileURLWithPath: "/cancellation-test"), isDirectory: true)
        for index in 0..<10_000 {
            builder.appendChild(builder.makeChild(
                url: URL(fileURLWithPath: "/cancellation-test/file-\(index)"),
                allocatedSizeValue: UInt64(10_000 - index),
                logicalSizeValue: UInt64(10_000 - index), kindName: "Data"
            ))
        }
        let root = builder.freeze()
        let colors = TreemapPlanColorTable(orderedKinds: ["Data"], sharesKindColors: false, colorScheme: .diskHog)
        // Exercise both ordinary child materialization and pixel-budget aggregation.
        for size in [20.0, 600.0] {
            let bounds = TreemapLayoutRect(x: 0, y: 0, width: size, height: size)
            let expected = TreemapLayoutPlanner.makePlan(
                rootItem: root, bounds: bounds, usePhysicalSize: true, colorTable: colors
            )
            var checks = 0
            let actual = TreemapLayoutPlanner.makePlanCheckingCancellation(
                rootItem: root, bounds: bounds, usePhysicalSize: true, colorTable: colors,
                checkCancellation: { checks += 1 }
            )
            precondition(actual.entries.count == expected.entries.count)
            for (a, b) in zip(actual.entries, expected.entries) {
                precondition(a.rect == b.rect && a.itemPath == b.itemPath)
            }
            for stopAt in Set([1, 3, 10, checks / 2, checks]) {
                var visited = 0
                do {
                    _ = try TreemapLayoutPlanner.makePlanCheckingCancellation(
                        rootItem: root, bounds: bounds, usePhysicalSize: true, colorTable: colors,
                        checkCancellation: {
                            visited += 1
                            if visited == stopAt { throw CancellationError() }
                        }
                    )
                    preconditionFailure("Cancellation returned a partial plan")
                } catch is CancellationError {
                    precondition(visited == stopAt)
                }
            }
        }
        let request = TreemapRenderRequest(
            rootItem: root, width: 600, height: 600, scale: 1,
            usePhysicalSize: true, orderedKindNames: ["Data"], sharesKindColors: false,
            colorScheme: .diskHog, showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil
        )
        await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            precondition(TreemapRenderJob.renderIfNotCancelled(request) == nil)
            // The unconditional API must still return a complete result.
            precondition(!TreemapRenderJob.render(request).plan.entries.isEmpty)
        }.value
        print("PASS: geometry equivalence, cancellation checkpoints, cancelled render APIs")
    }
}
