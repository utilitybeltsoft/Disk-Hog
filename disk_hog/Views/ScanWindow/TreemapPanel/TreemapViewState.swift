import AppKit

nonisolated final class TreemapViewStateWeakReference: @unchecked Sendable {
    weak var value: TreemapViewState?

    init(_ value: TreemapViewState) {
        self.value = value
    }
}

@MainActor
final class TreemapViewState {
    private(set) var source: ScanSource?
    private(set) var rootItem: DiskItem?
    private(set) var selectedItem: DiskItem?
    private(set) var renderer: TreemapViewRenderer?
    var onRenderedImageReady: (() -> Void)?

    private var presentationMetrics: TreemapPresentationMetrics?
    private var rendererDataSource: TreemapDiskItemDataSource?
    private var renderedPlan: TreemapLayoutPlan?
    private var renderedBitmap: NSBitmapImageRep?
    private var completedRenderRequest: TreemapRenderRequest?
    private var pendingRenderRequest: TreemapRenderRequest?
    private var showsFreeSpace: Bool = false
    private var showsOtherSpace: Bool = false
    private var freeSpaceItem: DiskItem?
    private var otherSpaceItem: DiskItem?
    private var directionalMoveHistory: [(origin: DiskItem, direction: TreemapNavigationDirection)] = []

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

        if self.rootItem !== rootItem
            || self.presentationMetrics !== presentationMetrics
            || self.showsFreeSpace != showsFreeSpace
            || self.showsOtherSpace != showsOtherSpace
            || self.freeSpaceItem !== freeSpaceItem
            || self.otherSpaceItem !== otherSpaceItem {
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            self.showsFreeSpace = showsFreeSpace
            self.showsOtherSpace = showsOtherSpace
            self.freeSpaceItem = freeSpaceItem
            self.otherSpaceItem = otherSpaceItem
            directionalMoveHistory.removeAll(keepingCapacity: true)
            discardRenderedPlan()
            rebuildRenderer()
            needsDisplay = true
        }

        if self.selectedItem !== selectedItem {
            directionalMoveHistory.removeAll(keepingCapacity: true)
            self.selectedItem = selectedItem
            if renderedPlan == nil {
                syncSelectionToRenderer()
            }
            needsDisplay = true
        }
        return needsDisplay
    }

    func applySelectedItem(_ selectedItem: DiskItem?) -> Bool {
        guard self.selectedItem !== selectedItem else {
            return false
        }

        directionalMoveHistory.removeAll(keepingCapacity: true)
        self.selectedItem = selectedItem
        if renderedPlan == nil {
            syncSelectionToRenderer()
        }
        return true
    }

    func select(_ hitResult: TreemapHitResult) {
        directionalMoveHistory.removeAll(keepingCapacity: true)
        if let cellID: TreemapItemRenderer = hitResult.cellID {
            renderer?.selectItem(by: cellID)
        }
        selectedItem = hitResult.item
    }

    func selectNeighbor(in direction: TreemapNavigationDirection) -> DiskItem? {
        if let lastMove: (origin: DiskItem, direction: TreemapNavigationDirection) = directionalMoveHistory.last,
           direction == lastMove.direction.opposite {
            if renderedPlan?.entry(for: lastMove.origin) != nil {
                _ = directionalMoveHistory.popLast()
                selectedItem = lastMove.origin
                return lastMove.origin
            } else if renderer?.selectItem(byRenderedItem: lastMove.origin) == true {
                _ = directionalMoveHistory.popLast()
                selectedItem = lastMove.origin
                return lastMove.origin
            } else {
                directionalMoveHistory.removeAll(keepingCapacity: true)
            }
        }
        guard let origin: DiskItem = selectedItem else { return nil }
        if let item: DiskItem = renderedPlan?.nearestEntry(from: origin, direction: direction)?.item {
            selectedItem = item
            directionalMoveHistory.append((origin: origin, direction: direction))
            return item
        }
        let item: DiskItem? = renderer?.selectNeighbor(in: direction)
        guard let item else { return nil }
        selectedItem = item
        directionalMoveHistory.append((origin: origin, direction: direction))
        return item
    }

    func hitResult(at point: NSPoint) -> TreemapHitResult? {
        if let entry: TreemapLayoutEntry = renderedPlan?.hitEntry(x: Double(point.x), y: Double(point.y)) {
            return TreemapHitResult(item: entry.item, cellID: nil, entry: entry)
        }
        guard let cellID: TreemapItemRenderer = renderer?.cellID(by: point, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID),
              !item.isSpecialItem else {
            return nil
        }
        return TreemapHitResult(item: item, cellID: cellID, entry: nil)
    }

    func renderedImage(in bounds: NSRect, scale: CGFloat) -> NSBitmapImageRep? {
        guard let request: TreemapRenderRequest = renderRequest(for: bounds, scale: scale) else {
            return nil
        }
        if completedRenderRequest == request {
            return renderedBitmap
        }
        if pendingRenderRequest != request {
            startRender(for: request)
        }
        return nil
    }

    func selectedEntry() -> TreemapLayoutEntry? {
        guard let selectedItem else {
            return nil
        }
        return renderedPlan?.entry(for: selectedItem)
    }

    func prepareLayout(in bounds: NSRect) {
        guard let rootItem: DiskItem = rootItem else {
            return
        }
        if renderer == nil {
            rebuildRenderer()
        }
        guard renderer?.rootCellID?.rect != bounds else {
            return
        }

        renderer?.calcLayout(bounds)
        syncSelectionToRenderer()
        if let renderer: TreemapViewRenderer = renderer {
            TreemapLayoutDiagnostics.recordLayoutChange(
                rootItem: rootItem,
                size: bounds.size,
                renderer: renderer,
                minimumRenderableSide: ScanWindowMetrics.minimumRenderableTreemapSide
            )
        }
    }

    private func rebuildRenderer() {
        guard let rootItem: DiskItem = rootItem else {
            renderer = nil
            rendererDataSource = nil
            return
        }

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: rootItem,
            usePhysicalSize: source?.scanSettings?.usePhysicalSize
                ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize,
            showFreeSpace: showsFreeSpace,
            showOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            presentationMetrics: presentationMetrics
        )
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        rendererDataSource = dataSource
        self.renderer = renderer
        syncSelectionToRenderer()
    }

    private func syncSelectionToRenderer() {
        guard let item: DiskItem = selectedItem,
              let rootItem: DiskItem = rootItem else {
            renderer?.selectItem(by: nil)
            return
        }

        let selectionPath: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item)
        guard selectionPath.isEmpty == false else {
            renderer?.selectItem(by: nil)
            return
        }

        _ = renderer?.selectRenderedItem(byPathToItem: selectionPath)
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
        pendingRenderRequest = request
        let stateReference: TreemapViewStateWeakReference = TreemapViewStateWeakReference(self)
        Task.detached(priority: .userInitiated) {
            let result: TreemapRenderResult = TreemapRenderJob.render(request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                stateReference.value?.installRenderResult(result)
            }
        }
    }

    private func installRenderResult(_ result: TreemapRenderResult) {
        guard pendingRenderRequest == result.request else {
            return
        }
        guard let bitmap: NSBitmapImageRep = bitmap(from: result) else {
            pendingRenderRequest = nil
            return
        }
        renderedPlan = result.plan
        renderedBitmap = bitmap
        completedRenderRequest = result.request
        pendingRenderRequest = nil
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
        renderedBitmap = nil
        completedRenderRequest = nil
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
    let cellID: TreemapItemRenderer?
    let entry: TreemapLayoutEntry?
}
