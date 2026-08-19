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
    static func render(_ request: TreemapRenderRequest) -> TreemapRenderResult {
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
            otherSpaceItem: request.otherSpaceItem
        )
        let pixels: Data = TreemapBitmapRasterizer.render(
            snapshots: plan.cushionSnapshots,
            pixelsWide: request.pixelsWide,
            pixelsHigh: request.pixelsHigh,
            scale: request.scale
        )
        return TreemapRenderResult(request: request, plan: plan, pixels: pixels)
    }
}
