import Foundation

nonisolated struct TreemapRenderRequest: Hashable, Sendable {
    let rootItem: DiskItem
    let width: Double
    let height: Double
    let scale: Double
    let usePhysicalSize: Bool
    let orderedKindNames: [String]
    let sharesKindColors: Bool
    let colorScheme: TreemapColorScheme
    let showsFreeSpace: Bool
    let showsOtherSpace: Bool
    let freeSpaceItem: DiskItem?
    let otherSpaceItem: DiskItem?

    var bounds: TreemapLayoutRect {
        TreemapLayoutRect(x: 0, y: 0, width: width, height: height)
    }

    var pixelsWide: Int {
        max(Int((width * scale).rounded(.up)), 1)
    }

    var pixelsHigh: Int {
        max(Int((height * scale).rounded(.up)), 1)
    }
}

nonisolated struct TreemapRenderResult: Sendable {
    let request: TreemapRenderRequest
    let plan: TreemapLayoutPlan
    let pixels: Data
}

nonisolated enum TreemapRenderJob {
    static func render(
        _ request: TreemapRenderRequest,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> TreemapRenderResult {
        render(request, rasterize: TreemapBitmapRasterizer.render, progress: progress)!
    }

    static func renderIfNotCancelled(
        _ request: TreemapRenderRequest,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> TreemapRenderResult? {
        guard Task.isCancelled == false else {
            return nil
        }
        return render(request, rasterize: TreemapBitmapRasterizer.renderIfNotCancelled, progress: progress)
    }

    private static func render(
        _ request: TreemapRenderRequest,
        rasterize: ([TreemapCushionSnapshot], Int, Int, Double) -> Data?,
        progress: (@Sendable (Double) -> Void)?
    ) -> TreemapRenderResult? {
        let planStart: Date = Date()
        let plan: TreemapLayoutPlan = TreemapLayoutPlanner.makePlan(
            rootItem: request.rootItem,
            bounds: request.bounds,
            usePhysicalSize: request.usePhysicalSize,
            colorTable: TreemapPlanColorTable(
                orderedKinds: request.orderedKindNames,
                sharesKindColors: request.sharesKindColors,
                colorScheme: request.colorScheme
            ),
            showsFreeSpace: request.showsFreeSpace,
            showsOtherSpace: request.showsOtherSpace,
            freeSpaceItem: request.freeSpaceItem,
            otherSpaceItem: request.otherSpaceItem,
            progress: progress
        )
        let planElapsed: TimeInterval = Date().timeIntervalSince(planStart)
        let rasterStart: Date = Date()
        guard Task.isCancelled == false,
              let pixels: Data = rasterize(
                plan.cushionSnapshots,
                request.pixelsWide,
                request.pixelsHigh,
                request.scale
        ) else {
            return nil
        }
        let rasterElapsed: TimeInterval = Date().timeIntervalSince(rasterStart)
        NSLog("DIAGHOG renderTiming root=%@ entries=%d snapshots=%d planSeconds=%.3f rasterSeconds=%.3f",
              request.rootItem.path, plan.entries.count, plan.cushionSnapshots.count, planElapsed, rasterElapsed)
        return TreemapRenderResult(request: request, plan: plan, pixels: pixels)
    }
}
