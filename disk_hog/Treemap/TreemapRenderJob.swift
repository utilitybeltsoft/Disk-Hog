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
        render(request, rasterize: TreemapBitmapRasterizer.render, progress: progress, respectsCancellation: false)!
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
        progress: (@Sendable (Double) -> Void)?,
        respectsCancellation: Bool = true
    ) -> TreemapRenderResult? {
        let planStart = TreemapPerformance.now
        guard let plan = try? TreemapLayoutPlanner.makePlanCheckingCancellation(
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
            progress: progress,
            checkCancellation: {
                if respectsCancellation { try Task.checkCancellation() }
            }
        ) else {
            TreemapPerformance.event("cancelled-during-geometry")
            return nil
        }
        TreemapPerformance.phase("layout-total", since: planStart, count: plan.entries.count)
        let rasterStart = TreemapPerformance.now
        guard !respectsCancellation || !Task.isCancelled,
              let pixels: Data = rasterize(
                plan.cushionSnapshots,
                request.pixelsWide,
                request.pixelsHigh,
                request.scale
        ) else {
            TreemapPerformance.event("cancelled-before-raster-completion")
            return nil
        }
        TreemapPerformance.phase("raster", since: rasterStart, count: plan.cushionSnapshots.count)
        return TreemapRenderResult(request: request, plan: plan, pixels: pixels)
    }
}
