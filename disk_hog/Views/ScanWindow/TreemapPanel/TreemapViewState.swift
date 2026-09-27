import AppKit

enum DiagHogPixelCheck {
    static func nonWhiteFraction(of data: Data) -> Double {
        guard data.isEmpty == false else { return -1 }
        var nonWhite: Int = 0
        var samples: Int = 0
        let stride: Int = max(1, data.count / 3000)
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var i: Int = 0
            while i < buf.count {
                if buf[i] < 250 { nonWhite += 1 }
                samples += 1
                i += stride
            }
        }
        return samples > 0 ? Double(nonWhite) / Double(samples) : -1
    }

    static func nonWhiteFraction(of bitmap: NSBitmapImageRep) -> Double {
        guard let base: UnsafeMutablePointer<UInt8> = bitmap.bitmapData else { return -1 }
        let count: Int = bitmap.bytesPerRow * bitmap.pixelsHigh
        let buf: UnsafeBufferPointer<UInt8> = UnsafeBufferPointer(start: base, count: count)
        var nonWhite: Int = 0
        var samples: Int = 0
        let stride: Int = max(1, count / 3000)
        var i: Int = 0
        while i < count {
            if buf[i] < 250 { nonWhite += 1 }
            samples += 1
            i += stride
        }
        return samples > 0 ? Double(nonWhite) / Double(samples) : -1
    }
}

nonisolated final class TreemapViewStateWeakReference: @unchecked Sendable {
    weak var value: TreemapViewState?

    init(_ value: TreemapViewState) {
        self.value = value
    }
}

/// Small LRU cache of completed renders, keyed by request. Every zoom (in or, especially, back
/// out) used to discard the previous layout entirely and recompute from scratch even when
/// revisiting a level already rendered once this session - on a large, heavily-nested tree that
/// meant re-paying the same tens-of-seconds cost every single time. TreemapRenderRequest already
/// encodes root identity, bounds, and every setting that affects the result, and DiskItem's
/// identity is scoped to its packed snapshot, so a request from a since-rebuilt tree (a rescan,
/// a size-mode change) simply never matches a stale cache entry.
///
/// Evicts by total retained bytes rather than entry count: a Retina or large window's bitmaps
/// can each run tens of MB, so a fixed slot count could still add up to hundreds of MB. Only the
/// bitmap is retained per entry (never the raw rasterized `Data` it was built from - once copied
/// into the bitmap's own backing buffer, that source data serves no further purpose), so the
/// cache never holds two full copies of the same pixels. `removeAll()` is called only on a
/// genuine rescan (a fresh `TreemapPresentationMetrics` instance) - ordinary zoom navigation
/// within the same snapshot leaves the cache alone, since those entries remain perfectly valid
/// and are exactly what makes revisiting a level (including the zoom-out animation's anchor
/// lookup) cheap.
@MainActor
private final class TreemapRenderResultCache {
    private struct Entry {
        let plan: TreemapLayoutPlan
        let bitmap: NSBitmapImageRep
        let byteSize: Int
    }

    private let byteBudget: Int
    private var order: [TreemapRenderRequest] = []
    private var storage: [TreemapRenderRequest: Entry] = [:]
    private var totalBytes: Int = 0

    init(byteBudget: Int = 96 * 1024 * 1024) {
        self.byteBudget = byteBudget
    }

    func entry(for request: TreemapRenderRequest) -> (plan: TreemapLayoutPlan, bitmap: NSBitmapImageRep)? {
        guard let entry: Entry = storage[request] else {
            return nil
        }
        touch(request)
        NSLog("DIAGHOG cacheHit root=%@ nonWhiteFraction=%.3f",
              request.rootItem.path, DiagHogPixelCheck.nonWhiteFraction(of: entry.bitmap))
        return (entry.plan, entry.bitmap)
    }

    func insert(plan: TreemapLayoutPlan, bitmap: NSBitmapImageRep, for request: TreemapRenderRequest) {
        let byteSize: Int = bitmap.bytesPerRow * bitmap.pixelsHigh
        if let existing: Entry = storage[request] {
            totalBytes -= existing.byteSize
        }
        NSLog("DIAGHOG cacheInsert root=%@ nonWhiteFraction=%.3f",
              request.rootItem.path, DiagHogPixelCheck.nonWhiteFraction(of: bitmap))
        storage[request] = Entry(plan: plan, bitmap: bitmap, byteSize: byteSize)
        totalBytes += byteSize
        touch(request)
        evictIfNeeded()
    }

    func removeAll() {
        order.removeAll()
        storage.removeAll()
        totalBytes = 0
    }

    private func touch(_ request: TreemapRenderRequest) {
        if let index: Int = order.firstIndex(of: request) {
            order.remove(at: index)
        }
        order.append(request)
    }

    private func evictIfNeeded() {
        // Always keep at least the just-inserted entry, even if it alone
        // exceeds the budget (e.g. a single very large/high-scale window) -
        // evicting it too would leave nothing to serve on the next request
        // for the exact same bounds.
        while totalBytes > byteBudget, order.count > 1 {
            let oldestRequest: TreemapRenderRequest = order.removeFirst()
            if let removed: Entry = storage.removeValue(forKey: oldestRequest) {
                totalBytes -= removed.byteSize
            }
        }
    }
}

@MainActor
final class TreemapViewState {
    private(set) var source: ScanSource?
    private(set) var rootItem: DiskItem?
    private(set) var selectedItem: DiskItem?
    var onRenderedImageReady: (() -> Void)?
    /// Throttled progress (0...1) for the in-flight render, reported from
    /// TreemapLayoutPlanner's recursive descent. Not called for renders that
    /// complete before the reporting throttle would ever fire.
    var onRenderProgress: ((Double) -> Void)?

    private let render: @Sendable (
        TreemapRenderRequest,
        @escaping @Sendable (Double) -> Void
    ) -> TreemapRenderResult?
    private var presentationMetrics: TreemapPresentationMetrics?
    private(set) var renderedPlan: TreemapLayoutPlan?
    private var lastPreparedBounds: NSRect?
    private var renderedBitmap: NSBitmapImageRep?
    private var completedRenderRequest: TreemapRenderRequest?
    private var pendingRenderRequest: TreemapRenderRequest?
    private var renderTask: Task<Void, Never>?
    private let resultCache: TreemapRenderResultCache = TreemapRenderResultCache()
    private var showsFreeSpace: Bool = false
    private var showsOtherSpace: Bool = false
    private var freeSpaceItem: DiskItem?
    private var otherSpaceItem: DiskItem?
    private var directionalMoveHistory: [(origin: DiskItem, direction: TreemapNavigationDirection)] = []
    private(set) var pendingZoomTransition: TreemapZoomTransition?

    init(
        render: @escaping @Sendable (
            TreemapRenderRequest,
            @escaping @Sendable (Double) -> Void
        ) -> TreemapRenderResult? = { request, progress in
            TreemapRenderJob.renderIfNotCancelled(request, progress: progress)
        }
    ) {
        self.render = render
    }

    func configure(
        source: ScanSource,
        rootItem: DiskItem?,
        presentationMetrics: TreemapPresentationMetrics?,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?,
        selectedItem: DiskItem?
    ) -> Bool {
        self.source = source
        var needsDisplay: Bool = false

        if self.rootItem != rootItem {
            pendingZoomTransition = makeZoomTransition(
                oldRootItem: self.rootItem,
                newRootItem: rootItem,
                isGenuineRescan: self.presentationMetrics !== presentationMetrics
            )
            NSLog("DIAGHOG configure rootChange old=%@ new=%@ transition=%@ toBitmap=%@",
                  self.rootItem?.path ?? "nil", rootItem?.path ?? "nil",
                  pendingZoomTransition == nil ? "nil" : (pendingZoomTransition!.direction == .zoomIn ? "zoomIn" : "zoomOut"),
                  pendingZoomTransition?.toBitmap == nil ? "nil" : "set")
        }

        if self.rootItem != rootItem
            || self.presentationMetrics !== presentationMetrics
            || self.showsFreeSpace != showsFreeSpace
            || self.showsOtherSpace != showsOtherSpace
            || self.freeSpaceItem != freeSpaceItem
            || self.otherSpaceItem != otherSpaceItem {
            let isGenuineRescan: Bool = self.presentationMetrics !== presentationMetrics
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            self.showsFreeSpace = showsFreeSpace
            self.showsOtherSpace = showsOtherSpace
            self.freeSpaceItem = freeSpaceItem
            self.otherSpaceItem = otherSpaceItem
            directionalMoveHistory.removeAll(keepingCapacity: true)
            discardRenderedPlan()
            // Only a genuine rescan (a fresh TreemapPresentationMetrics instance) ever
            // invalidates every cache entry. Ordinary zoom navigation revisits levels
            // within the same snapshot, whose entries are still perfectly valid -
            // clearing them here would force a full re-render on every zoom step,
            // including zooming back out to somewhere already rendered this session.
            if isGenuineRescan {
                resultCache.removeAll()
            }
            needsDisplay = true
        }

        if self.selectedItem != selectedItem {
            directionalMoveHistory.removeAll(keepingCapacity: true)
            self.selectedItem = selectedItem
            needsDisplay = true
        }
        return needsDisplay
    }

    /// One-shot consume, mirroring `TreemapNavigationState.consumeSelectionAfterZoom()`.
    func consumeZoomTransition() -> TreemapZoomTransition? {
        defer { pendingZoomTransition = nil }
        return pendingZoomTransition
    }

    /// Computed synchronously, before any state below is mutated, since this is the
    /// only moment `renderedPlan` still reflects the *old* root - a few lines later
    /// `discardRenderedPlan()` clears it. Every zoom trigger in the app (double-click,
    /// keyboard, toolbar, breadcrumb, menu commands, Files-pane outline, and indirect
    /// selection-driven zoom-out) funnels through this one function via SwiftUI's
    /// `updateNSView`, so this is the single place that can see both the old and new
    /// root together.
    private func makeZoomTransition(
        oldRootItem: DiskItem?,
        newRootItem: DiskItem?,
        isGenuineRescan: Bool
    ) -> TreemapZoomTransition? {
        guard isGenuineRescan == false,
              let oldRootItem, let newRootItem,
              let renderedBitmap, let renderedPlan else {
            return nil
        }
        let fromBounds: NSRect = renderedPlan.bounds.nsRect

        // Zoom in: the destination is a folder currently visible within the old plan.
        if let entry: TreemapLayoutEntry = renderedPlan.entry(for: newRootItem),
           entry.navigationRect.isEmpty == false {
            return TreemapZoomTransition(
                direction: .zoomIn,
                fromBitmap: renderedBitmap,
                fromBounds: fromBounds,
                anchorRect: entry.navigationRect.nsRect,
                toBitmap: nil,
                toBounds: nil,
                pendingAnchorItem: nil
            )
        }

        // Zoom out: only when the new root is a genuine ancestor of the old one -
        // covers zoomOut(), zoom(toPathIndex:), and revealSelection()'s indirect
        // zoom-out identically, since all three just present a different rootItem
        // to this same function. A rescan's refreshed root shares its old path
        // string too, but that's already excluded above by isGenuineRescan.
        guard Self.isAncestorPath(newRootItem.path, of: oldRootItem.path),
              let completedRenderRequest else {
            return nil // divergent jump (e.g. Files-pane double-click into an
                        // unrelated branch) - no coherent relationship, cut as today.
        }
        let prospectiveRequest = TreemapRenderRequest(
            rootItem: newRootItem,
            width: completedRenderRequest.width,
            height: completedRenderRequest.height,
            scale: completedRenderRequest.scale,
            usePhysicalSize: completedRenderRequest.usePhysicalSize,
            orderedKindNames: completedRenderRequest.orderedKindNames,
            sharesKindColors: completedRenderRequest.sharesKindColors,
            colorScheme: completedRenderRequest.colorScheme,
            showsFreeSpace: completedRenderRequest.showsFreeSpace,
            showsOtherSpace: completedRenderRequest.showsOtherSpace,
            freeSpaceItem: completedRenderRequest.freeSpaceItem,
            otherSpaceItem: completedRenderRequest.otherSpaceItem
        )
        if let cached = resultCache.entry(for: prospectiveRequest),
           let anchorEntry: TreemapLayoutEntry = cached.plan.entry(for: oldRootItem),
           anchorEntry.navigationRect.isEmpty == false {
            return TreemapZoomTransition(
                direction: .zoomOut,
                fromBitmap: renderedBitmap,
                fromBounds: fromBounds,
                anchorRect: anchorEntry.navigationRect.nsRect,
                toBitmap: cached.bitmap,
                toBounds: cached.plan.bounds.nsRect,
                pendingAnchorItem: nil
            )
        }
        return TreemapZoomTransition(
            direction: .zoomOut,
            fromBitmap: renderedBitmap,
            fromBounds: fromBounds,
            anchorRect: nil,
            toBitmap: nil,
            toBounds: nil,
            pendingAnchorItem: oldRootItem
        )
    }

    private static func isAncestorPath(_ ancestorPath: String, of path: String) -> Bool {
        FilePathContainment.contains(path, in: ancestorPath)
    }

    func applySelectedItem(_ selectedItem: DiskItem?) -> Bool {
        guard self.selectedItem != selectedItem else {
            return false
        }

        directionalMoveHistory.removeAll(keepingCapacity: true)
        self.selectedItem = selectedItem
        return true
    }

    func select(_ hitResult: TreemapHitResult) {
        directionalMoveHistory.removeAll(keepingCapacity: true)
        selectedItem = hitResult.item
    }

    func selectNeighbor(in direction: TreemapNavigationDirection) -> DiskItem? {
        if let lastMove: (origin: DiskItem, direction: TreemapNavigationDirection) = directionalMoveHistory.last,
           direction == lastMove.direction.opposite {
            if renderedPlan?.entryOrNearestAncestor(for: lastMove.origin) != nil {
                _ = directionalMoveHistory.popLast()
                selectedItem = lastMove.origin
                return lastMove.origin
            } else {
                directionalMoveHistory.removeAll(keepingCapacity: true)
            }
        }
        guard let origin: DiskItem = selectedItem,
              let item: DiskItem = renderedPlan?.nearestEntry(from: origin, direction: direction)?.item else {
            return nil
        }
        selectedItem = item
        directionalMoveHistory.append((origin: origin, direction: direction))
        return item
    }

    func hitResult(at point: NSPoint) -> TreemapHitResult? {
        guard let entry: TreemapLayoutEntry = renderedPlan?.hitEntry(x: Double(point.x), y: Double(point.y)) else {
            return nil
        }
        return TreemapHitResult(item: entry.item, entry: entry)
    }

    func renderedImage(in bounds: NSRect, scale: CGFloat, allowRendering: Bool = true) -> NSBitmapImageRep? {
        // Live resize stretches the last completed image. Do not create/cancel
        // layout jobs for every intermediate size; render once dragging ends.
        guard allowRendering else { return renderedBitmap }
        guard let request: TreemapRenderRequest = renderRequest(for: bounds, scale: scale) else {
            return nil
        }
        if completedRenderRequest == request {
            return renderedBitmap
        }
        if let cached: NSBitmapImageRep = applyCachedResultIfAvailable(for: request) {
            return cached
        }
        if pendingRenderRequest != request {
            NSLog("DIAGHOG renderedImage MISS root=%@ w=%.1f h=%.1f (completed:%@ pending:%@) staleFallbackSizeMatch=%@",
                  request.rootItem.path, request.width, request.height,
                  completedRenderRequest == nil ? "nil" : "w=\(completedRenderRequest!.width) h=\(completedRenderRequest!.height) root=\(completedRenderRequest!.rootItem.path)",
                  pendingRenderRequest == nil ? "nil" : "w=\(pendingRenderRequest!.width) h=\(pendingRenderRequest!.height) root=\(pendingRenderRequest!.rootItem.path)",
                  (completedRenderRequest?.width == request.width && completedRenderRequest?.height == request.height) ? "yes" : "no")
            startRender(for: request)
        }
        if let completedRenderRequest,
           completedRenderRequest.width == request.width,
           completedRenderRequest.height == request.height,
           let renderedBitmap {
            return renderedBitmap
        }
        return nil
    }

    /// True once the visible bitmap belongs to a root other than the one
    /// currently configured (or there's no bitmap at all yet) — i.e. a
    /// zoom/root change is still waiting on its background re-render.
    /// `renderedImage(in:scale:)` deliberately keeps showing the previous
    /// root's bitmap while that happens, so callers that want to surface
    /// this as a "recalculating" indicator can't tell from the image alone.
    var isShowingStaleRoot: Bool {
        guard let rootItem else { return false }
        guard let completedRenderRequest else { return true }
        return completedRenderRequest.rootItem != rootItem
    }

    func selectedEntry() -> TreemapLayoutEntry? {
        guard let selectedItem else {
            return nil
        }
        return renderedPlan?.entryOrNearestAncestor(for: selectedItem)
    }

    /// Root-to-parent chain for `item`, resolved via the rendered plan's item
    /// index when available. Empty when the plan doesn't (yet) have an entry
    /// for `item`, in which case callers should fall back to a path-based walk.
    func ancestorChain(for item: DiskItem) -> [DiskItem] {
        guard let renderedPlan, let entry: TreemapLayoutEntry = renderedPlan.entry(for: item) else {
            return []
        }
        return renderedPlan.ancestorChain(for: entry)
    }

    func entry(for item: DiskItem) -> TreemapLayoutEntry? {
        renderedPlan?.entry(for: item)
    }

    /// The rendered entry for `entry`'s immediate parent, when the plan has
    /// one. Nil when `entry` is the plan's root (no parent) or its parent
    /// isn't part of the current zoomed-in tree.
    func parentEntry(of entry: TreemapLayoutEntry?) -> TreemapLayoutEntry? {
        guard let entry, let parentItem: DiskItem = entry.parentItem else {
            return nil
        }
        return renderedPlan?.entry(for: parentItem)
    }

    func prepareLayout(in bounds: NSRect) {
        guard rootItem != nil else {
            return
        }
        guard lastPreparedBounds != bounds || renderedPlan == nil else {
            return
        }

        preparePlan(in: bounds)
    }

    private func preparePlan(in bounds: NSRect) {
        lastPreparedBounds = bounds
        guard let request: TreemapRenderRequest = renderRequest(for: bounds, scale: 1) else {
            renderedPlan = nil
            renderedBitmap = nil
            completedRenderRequest = nil
            cancelPendingRender()
            return
        }
        renderedPlan = TreemapLayoutPlanner.makePlan(
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
        cancelPendingRender()
        completedRenderRequest = nil
        renderedBitmap = nil
    }

    private func renderRequest(for bounds: NSRect, scale: CGFloat) -> TreemapRenderRequest? {
        guard let rootItem: DiskItem = rootItem,
              bounds.width >= ScanWindowMetrics.minimumRenderableTreemapSide,
              bounds.height >= ScanWindowMetrics.minimumRenderableTreemapSide else {
            return nil
        }
        let metrics: TreemapPresentationMetrics? = presentationMetrics
        return TreemapRenderRequest(
            rootItem: rootItem,
            width: Double(bounds.width),
            height: Double(bounds.height),
            scale: Double(scale),
            usePhysicalSize: source?.scanSettings?.usePhysicalSize
                ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize,
            orderedKindNames: metrics?.orderedKindNames ?? [],
            sharesKindColors: metrics?.sharesKindColors ?? ScanPreferenceDefaults.sharesKindColors,
            colorScheme: metrics?.colorScheme ?? ScanPreferenceDefaults.treemapColorScheme,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem
        )
    }

    private func startRender(for request: TreemapRenderRequest) {
        NSLog("DIAGHOG startRender root=%@ w=%.1f h=%.1f scale=%.2f cancellingPrior=%@ priorRoot=%@",
              request.rootItem.path, request.width, request.height, request.scale,
              renderTask == nil ? "no" : "yes",
              pendingRenderRequest?.rootItem.path ?? "nil")
        renderTask?.cancel()
        pendingRenderRequest = request
        let renderID = UUID().uuidString
        let requestedAt = TreemapPerformance.now
        let reason: String = completedRenderRequest == nil ? "initial"
            : completedRenderRequest?.rootItem != request.rootItem ? "root-change"
            : completedRenderRequest?.width != request.width || completedRenderRequest?.height != request.height ? "resize"
            : "appearance-change"
        let stateReference: TreemapViewStateWeakReference = TreemapViewStateWeakReference(self)
        renderTask = Task.detached(priority: .userInitiated) { [render] in
            await TreemapPerformance.$renderID.withValue(renderID) {
                TreemapPerformance.started(request, reason: reason)
                TreemapPerformance.phase("worker-queue", since: requestedAt)
                let reportProgress: @Sendable (Double) -> Void = { fraction in
                    Task { @MainActor in
                        stateReference.value?.updateRenderProgress(fraction, for: request)
                    }
                }
                guard let result: TreemapRenderResult = render(request, reportProgress),
                      !Task.isCancelled else {
                    TreemapPerformance.event("cancelled-or-no-result")
                    await MainActor.run {
                        stateReference.value?.finishRenderWithoutResult(for: request)
                    }
                    return
                }
                let renderedAt = TreemapPerformance.now
                await MainActor.run {
                    TreemapPerformance.phase("main-queue", since: renderedAt)
                    let installStart = TreemapPerformance.now
                    stateReference.value?.installRenderResult(result)
                    TreemapPerformance.phase("install", since: installStart)
                    TreemapPerformance.phase("request-total", since: requestedAt)
                }
            }
        }
    }

    private func updateRenderProgress(_ fraction: Double, for request: TreemapRenderRequest) {
        guard pendingRenderRequest == request else {
            return
        }
        onRenderProgress?(fraction)
    }

    private func finishRenderWithoutResult(for request: TreemapRenderRequest) {
        NSLog("DIAGHOG finishRenderWithoutResult root=%@ stillCurrent=%@",
              request.rootItem.path, pendingRenderRequest == request ? "yes" : "no")
        guard pendingRenderRequest == request else {
            return
        }
        pendingRenderRequest = nil
        renderTask = nil
    }

    /// Serves an already-completed render for `request` from cache, if one exists, without
    /// re-running the layout/rasterization pipeline at all. Bypasses the pendingRenderRequest
    /// guard installRenderResult uses (this path never went through startRender), but is
    /// otherwise the same install: updates renderedPlan/renderedBitmap/completedRenderRequest and
    /// fires onRenderedImageReady so dependents (hover resample, "recalculating" badge) react the
    /// same way they would to a freshly-computed render.
    private func applyCachedResultIfAvailable(for request: TreemapRenderRequest) -> NSBitmapImageRep? {
        guard let cached = resultCache.entry(for: request) else {
            return nil
        }
        TreemapPerformance.event("cache-hit")
        renderedPlan = cached.plan
        renderedBitmap = cached.bitmap
        completedRenderRequest = request
        onRenderedImageReady?()
        return cached.bitmap
    }

    private func installRenderResult(_ result: TreemapRenderResult) {
        NSLog("DIAGHOG installRenderResult root=%@ stillCurrent=%@ rawNonWhiteFraction=%.3f entryCount=%d",
              result.request.rootItem.path, pendingRenderRequest == result.request ? "yes" : "no",
              DiagHogPixelCheck.nonWhiteFraction(of: result.pixels), result.plan.entries.count)
        guard pendingRenderRequest == result.request else {
            TreemapPerformance.event("stale-result-discarded")
            return
        }
        guard let bitmap: NSBitmapImageRep = bitmap(from: result) else {
            pendingRenderRequest = nil
            renderTask = nil
            return
        }
        NSLog("DIAGHOG installRenderResult convertedBitmapNonWhiteFraction=%.3f",
              DiagHogPixelCheck.nonWhiteFraction(of: bitmap))
        renderedPlan = result.plan
        renderedBitmap = bitmap
        completedRenderRequest = result.request
        pendingRenderRequest = nil
        renderTask = nil
        resultCache.insert(plan: result.plan, bitmap: bitmap, for: result.request)
        onRenderedImageReady?()
    }

    private func bitmap(from result: TreemapRenderResult) -> NSBitmapImageRep? {
        guard let bitmap: NSBitmapImageRep = NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: NSRect(
                x: 0,
                y: 0,
                width: CGFloat(result.request.width),
                height: CGFloat(result.request.height)
            ),
            backingScaleFactor: CGFloat(result.request.scale),
            colorSpace: nil
        ),
              bitmap.pixelsWide == result.request.pixelsWide,
              bitmap.pixelsHigh == result.request.pixelsHigh,
              let destination: UnsafeMutablePointer<UInt8> = bitmap.bitmapData else {
            return nil
        }
        result.pixels.withUnsafeBytes { source in
            guard let sourceAddress: UnsafeRawPointer = source.baseAddress else { return }
            let sourceBytesPerRow: Int = result.request.pixelsWide * 3
            guard source.count == sourceBytesPerRow * result.request.pixelsHigh else { return }
            for row: Int in 0..<result.request.pixelsHigh {
                memcpy(
                    destination.advanced(by: row * bitmap.bytesPerRow),
                    sourceAddress.advanced(by: row * sourceBytesPerRow),
                    sourceBytesPerRow
                )
            }
        }
        return bitmap
    }

    private func discardRenderedPlan() {
        renderedPlan = nil
        cancelPendingRender()
    }

    private func cancelPendingRender() {
        renderTask?.cancel()
        renderTask = nil
        pendingRenderRequest = nil
    }
}

private extension TreemapNavigationDirection {
    var opposite: TreemapNavigationDirection {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }
}

struct TreemapHitResult {
    let item: DiskItem
    let entry: TreemapLayoutEntry?
}
