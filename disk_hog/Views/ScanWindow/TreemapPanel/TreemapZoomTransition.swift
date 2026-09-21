import AppKit

/// A one-shot description of a zoom navigation just detected by
/// `TreemapViewState.configure(...)`, consumed once by `ZStyleTreemapNSView`
/// (mirrors the existing `consumeSelectionAfterZoom()` pattern in
/// `TreemapNavigationState`).
struct TreemapZoomTransition {
    enum Direction: Equatable {
        case zoomIn
        case zoomOut
    }

    let direction: Direction
    let fromBitmap: NSBitmapImageRep
    let fromBounds: NSRect
    /// For `.zoomIn`: the new (child) root's rect within the old plan.
    /// For `.zoomOut`: the old (child) root's rect within the new plan.
    /// Nil only for a `.zoomOut` whose destination wasn't already cached.
    var anchorRect: NSRect?
    /// Populated once the destination is known - immediately for a cache hit,
    /// or later via `TreemapZoomAnimation.resolvePendingBitmap(...)`.
    var toBitmap: NSBitmapImageRep?
    var toBounds: NSRect?
    /// Set only when `anchorRect`/`toBitmap` start nil: which item's rect to
    /// look up once its render completes.
    let pendingAnchorItem: DiskItem?
}
