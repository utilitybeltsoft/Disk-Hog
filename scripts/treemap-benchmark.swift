import Foundation

// Compile with the production DiskItems and Treemap sources (see PERFORMANCE.md).
// Synthetic input avoids scanning or logging the user's filesystem.
@main struct TreemapBenchmark {
    static func main() {
        let count = Int(CommandLine.arguments.dropFirst().first ?? "100000") ?? 100_000
        precondition(count > 0)
        let builder = DiskItemBuilder(url: URL(fileURLWithPath: "/benchmark"), isDirectory: true)
        for index in 0..<count {
            let child = builder.makeChild(
                url: URL(fileURLWithPath: "/benchmark/file-\(index)"),
                allocatedSizeValue: UInt64(count - index),
                logicalSizeValue: UInt64(count - index),
                kindName: "Data"
            )
            builder.appendChild(child)
        }
        let root = builder.freeze()
        for width in [900.0, 1_000.0] {
            let request = TreemapRenderRequest(
                rootItem: root, width: width, height: 600, scale: 1,
                usePhysicalSize: true, orderedKindNames: ["Data"],
                sharesKindColors: false, colorScheme: .diskHog,
                showsFreeSpace: false, showsOtherSpace: false,
                freeSpaceItem: nil, otherSpaceItem: nil
            )
            TreemapPerformance.$renderID.withValue("benchmark-\(Int(width))") {
                TreemapPerformance.started(request, reason: "benchmark")
                let start = TreemapPerformance.now
                let result = TreemapRenderJob.render(request)
                print("width=\(width) items=\(count) entries=\(result.plan.entries.count) seconds=\(TreemapPerformance.now - start)")
            }
        }
    }
}
