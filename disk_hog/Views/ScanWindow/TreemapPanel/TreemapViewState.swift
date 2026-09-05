import AppKit

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
/// a size-mode change) simply never matches a stale cache entry - no explicit invalidation needed,
/// stale entries just age out via LRU eviction.
@MainActor
private final class TreemapRenderResultCache {
    private struct Entry {
        let result: TreemapRenderResult
        let bitmap: NSBitmapImageRep
    }

    private let capacity: Int
    private var order: [TreemapRenderRequest] = []
    private var storage: [TreemapRenderRequest: Entry] = [:]

    init(capacity: Int = 10) {
        self.capacity = capacity
    }

    func entry(for request: TreemapRenderRequest) -> (result: TreemapRenderResult, bitmap: NSBitmapImageRep)? {
        guard let entry: Entry = storage[request] else {
            return nil
        }
        touch(request)
        return (entry.result, entry.bitmap)
    }

    func insert(_ result: TreemapRenderResult, bitmap: NSBitmapImageRep) {
        storage[result.request] = Entry(result: result, bitmap: bitmap)
        touch(result.request)
        while order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
    }

    private func touch(_ request: TreemapRenderRequest) {
        if let index: Int = order.firstIndex(of: request) {
            order.remove(at: index)
        }
        order.append(request)
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

        if self.rootItem != rootItem
            || self.presentationMetrics !== presentationMetrics
            || self.showsFreeSpace != showsFreeSpace
            || self.showsOtherSpace != showsOtherSpace
            || self.freeSpaceItem != freeSpaceItem
            || self.otherSpaceItem != otherSpaceItem {
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            self.showsFreeSpace = showsFreeSpace
            self.showsOtherSpace = showsOtherSpace
            self.freeSpaceItem = freeSpaceItem
            self.otherSpaceItem = otherSpaceItem
            directionalMoveHistory.removeAll(keepingCapacity: true)
            discardRenderedPlan()
            needsDisplay = true
        }

        if self.selectedItem != selectedItem {
            directionalMoveHistory.removeAll(keepingCapacity: true)
            self.selectedItem = selectedItem
            needsDisplay = true
        }
        return needsDisplay
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

    func renderedImage(in bounds: NSRect, scale: CGFloat) -> NSBitmapImageRep? {
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
        renderTask?.cancel()
        pendingRenderRequest = request
        let stateReference: TreemapViewStateWeakReference = TreemapViewStateWeakReference(self)
        renderTask = Task.detached(priority: .userInitiated) { [render] in
            let reportProgress: @Sendable (Double) -> Void = { fraction in
                Task { @MainActor in
                    stateReference.value?.updateRenderProgress(fraction, for: request)
                }
            }
            guard let result: TreemapRenderResult = render(request, reportProgress),
                  !Task.isCancelled else {
                await MainActor.run {
                    stateReference.value?.finishRenderWithoutResult(for: request)
                }
                return
            }
            await MainActor.run {
                stateReference.value?.installRenderResult(result)
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
        renderedPlan = cached.result.plan
        renderedBitmap = cached.bitmap
        completedRenderRequest = cached.result.request
        onRenderedImageReady?()
        return cached.bitmap
    }

    private func installRenderResult(_ result: TreemapRenderResult) {
        guard pendingRenderRequest == result.request else {
            return
        }
        guard let bitmap: NSBitmapImageRep = bitmap(from: result) else {
            pendingRenderRequest = nil
            renderTask = nil
            return
        }
        renderedPlan = result.plan
        renderedBitmap = bitmap
        completedRenderRequest = result.request
        pendingRenderRequest = nil
        renderTask = nil
        resultCache.insert(result, bitmap: bitmap)
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
