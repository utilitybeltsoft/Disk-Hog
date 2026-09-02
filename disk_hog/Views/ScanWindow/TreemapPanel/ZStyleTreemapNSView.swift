import AppKit

final class ZStyleTreemapNSView: NSView {
    var onSelectItem: ((DiskItem, [DiskItem]) -> Void)?
    var onHoverItem: ((DiskItem?) -> Void)?
    var onZoomIn: ((DiskItem) -> Void)?
    var onZoomOut: (() -> Void)?
    var onRenderPendingChange: ((Bool) -> Void)?

    private weak var session: ScanSession?
    private let contextMenuActionTarget: DiskItemContextMenuActionTarget = DiskItemContextMenuActionTarget()
    private let state: TreemapViewState = TreemapViewState()
    private let trackingAreaController: TreemapTrackingAreaController = TreemapTrackingAreaController()
    private let discoveryAnimation: TreemapDiscoveryAnimation = TreemapDiscoveryAnimation()
    private var pendingDiscoveryAnimation: Bool = false
    private var hoveredItem: DiskItem?
    private var hoveredEntry: TreemapLayoutEntry?
    private var lastReportedRenderPending: Bool = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func configure(
        session: ScanSession,
        source: ScanSource,
        rootItem: DiskItem?,
        presentationMetrics: TreemapPresentationMetrics?,
        showsFreeSpace: Bool,
        showsOtherSpace: Bool,
        freeSpaceItem: DiskItem?,
        otherSpaceItem: DiskItem?,
        selectedItem: DiskItem?
    ) {
        self.session = session
        contextMenuActionTarget.session = session
        let rootChanged: Bool = state.rootItem !== rootItem
        if state.configure(
            source: source,
            rootItem: rootItem,
            presentationMetrics: presentationMetrics,
            showsFreeSpace: showsFreeSpace,
            showsOtherSpace: showsOtherSpace,
            freeSpaceItem: freeSpaceItem,
            otherSpaceItem: otherSpaceItem,
            selectedItem: selectedItem
        ) {
            pendingDiscoveryAnimation = true
            needsDisplay = true
        }
        if rootChanged {
            // The hovered entry belongs to the previous root's layout plan
            // (different coordinate space, possibly a different item entirely).
            // AppKit won't redeliver a mouseMoved just because the content
            // changed under a stationary cursor, so drop it now rather than
            // let a stale rectangle linger until the pointer next moves.
            updateHover(item: nil, entry: nil)
        }
        state.onRenderedImageReady = { [weak self] in
            guard let self else { return }
            self.session?.markTreemapRendered(for: self.state.rootItem)
            // The new root's layout plan just became available; resample
            // whatever's currently under the pointer instead of waiting for
            // the next mouse move, so hover reappears the moment it can.
            self.refreshHoverForCurrentMouseLocation()
            self.needsDisplay = true
        }
    }

    private func refreshHoverForCurrentMouseLocation() {
        guard let window else {
            updateHover(item: nil, entry: nil)
            return
        }
        let locationInView: NSPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(locationInView) else {
            updateHover(item: nil, entry: nil)
            return
        }
        let result: TreemapHitResult? = state.hitResult(at: locationInView)
        updateHover(item: result?.item, entry: result?.entry)
    }

    private func reportRenderPending(_ isPending: Bool) {
        guard lastReportedRenderPending != isPending else { return }
        lastReportedRenderPending = isPending
        NSLog("[TreemapRender] badge %@ for root=%@", isPending ? "SHOWN" : "cleared", state.rootItem?.path ?? "nil")
        onRenderPendingChange?(isPending)
    }

    func applySelectedItem(_ selectedItem: DiskItem?) {
        if state.applySelectedItem(selectedItem) {
            pendingDiscoveryAnimation = true
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        trackingAreaController.update(on: self)
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard state.rootItem != nil else {
            TreemapViewPainter.drawPlaceholder(in: dirtyRect)
            return
        }
        guard bounds.width >= ScanWindowMetrics.minimumRenderableTreemapSide,
              bounds.height >= ScanWindowMetrics.minimumRenderableTreemapSide else {
            return
        }

        if inLiveResize {
            if drawRenderedImage(
                destinationRect: bounds,
                sourceRect: nil,
                fraction: ScanWindowMetrics.treemapLiveResizeImageFraction
            ) == false {
                NSColor.windowBackgroundColor.setFill()
                dirtyRect.fill()
            }
            // Live resize already shows the previous bitmap at reduced opacity;
            // a "recalculating" badge would just flicker throughout the drag.
            return
        }

        let drawableRect: NSRect = dirtyRect.intersection(bounds)
        guard drawableRect.isEmpty == false else {
            return
        }
        if drawRenderedImage(destinationRect: drawableRect, sourceRect: drawableRect, fraction: 1) == false {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            reportRenderPending(true)
            return
        }
        reportRenderPending(state.isShowingStaleRoot)
        let scale: CGFloat = window?.backingScaleFactor ?? 1
        let selectedEntry: TreemapLayoutEntry? = state.selectedEntry()
        TreemapViewPainter.drawSelection(
            entry: selectedEntry,
            parentEntry: state.parentEntry(of: selectedEntry),
            in: bounds,
            backingScaleFactor: scale
        )
        if let hoveredEntry, hoveredItem != state.selectedItem {
            TreemapViewPainter.drawHover(
                entry: hoveredEntry,
                parentEntry: state.parentEntry(of: hoveredEntry),
                in: bounds,
                backingScaleFactor: scale
            )
        }
        startDiscoveryAnimationIfNeeded()
        discoveryAnimation.draw()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        trackingAreaController.discard(from: self)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateTrackingAreas()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let hitResult: TreemapHitResult? = hitResult(for: event)
        updateHover(item: hitResult?.item, entry: hitResult?.entry)
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(item: nil, entry: nil)
    }

    private func updateHover(item: DiskItem?, entry: TreemapLayoutEntry?) {
        guard hoveredItem != item else { return }
        hoveredItem = item
        hoveredEntry = entry
        onHoverItem?(item)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point: NSPoint = convert(event.locationInWindow, from: nil)
        guard let hitResult: TreemapHitResult = state.hitResult(at: point) else {
            return
        }
        select(hitResult)
        if event.clickCount == 2 {
            onZoomIn?(hitResult.item)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case AppKitKeyCode.space:
            return
        case AppKitKeyCode.leftArrow:
            selectNeighbor(in: .left)
            return
        case AppKitKeyCode.rightArrow:
            selectNeighbor(in: .right)
            return
        case AppKitKeyCode.downArrow:
            selectNeighbor(in: .down)
            return
        case AppKitKeyCode.upArrow:
            selectNeighbor(in: .up)
            return
        case AppKitKeyCode.returnKey, AppKitKeyCode.keypadEnter:
            if event.modifierFlags.contains(.shift) {
                onZoomOut?()
                return
            }
            if let item: DiskItem = state.selectedItem {
                onZoomIn?(item)
                return
            }
        case AppKitKeyCode.escape:
            onZoomOut?()
            return
        default:
            return
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let hitResult: TreemapHitResult? = hitResult(for: event)
        if let hitResult: TreemapHitResult = hitResult {
            select(hitResult)
        }

        return DiskItemContextMenuBuilder.menu(
            for: hitResult?.item ?? state.selectedItem,
            actionTarget: contextMenuActionTarget,
            treeActionsEnabled: session?.isUpdatingTree == false
        )
    }

    private func hitResult(for event: NSEvent) -> TreemapHitResult? {
        state.hitResult(at: convert(event.locationInWindow, from: nil))
    }

    private func select(_ hitResult: TreemapHitResult) {
        let selectionChanged: Bool = state.selectedItem != hitResult.item
        state.select(hitResult)
        pendingDiscoveryAnimation = selectionChanged
        onSelectItem?(hitResult.item, state.ancestorChain(for: hitResult.item))
        needsDisplay = true
    }

    private func selectNeighbor(in direction: TreemapNavigationDirection) {
        guard let item: DiskItem = state.selectNeighbor(in: direction) else { return }
        onSelectItem?(item, state.ancestorChain(for: item))
        needsDisplay = true
    }

    private func drawRenderedImage(
        destinationRect: NSRect,
        sourceRect: NSRect?,
        fraction: CGFloat
    ) -> Bool {
        guard let imageRep: NSBitmapImageRep = state.renderedImage(
            in: bounds,
            scale: window?.backingScaleFactor ?? 1
        ) else {
            return false
        }
        TreemapViewPainter.drawRenderedImage(
            imageRep,
            destinationRect: destinationRect,
            sourceRect: sourceRect,
            fraction: fraction
        )
        return true
    }

    private func startDiscoveryAnimationIfNeeded() {
        guard pendingDiscoveryAnimation else { return }
        pendingDiscoveryAnimation = false
        guard let entry: TreemapLayoutEntry = state.selectedEntry(),
              let targetRect: NSRect = discoveryAnimationTargetRect(for: entry) else { return }
        discoveryAnimation.start(
            from: discoveryStartRect(for: targetRect, parentEntry: state.parentEntry(of: entry)),
            to: targetRect
        ) { [weak self] in
            guard let self else { return }
            self.setNeedsDisplay(self.bounds)
        }
    }

    /// Prefers the selected item's actual containing folder as the pulse's
    /// origin, so the animation reads as "here's where it lives" rather than
    /// starting from an arbitrary spot. Falls back to a synthetic halo around
    /// the target when there's no usable parent (e.g. the current zoom root).
    private func discoveryStartRect(for targetRect: NSRect, parentEntry: TreemapLayoutEntry?) -> NSRect {
        if let parentEntry {
            let parentRect: NSRect = NSRect(
                x: parentEntry.rect.x,
                y: parentEntry.rect.y,
                width: parentEntry.rect.width,
                height: parentEntry.rect.height
            )
            let visibleParentRect: NSRect = TreemapSelectionRect.visibleRect(for: parentRect, in: bounds)
            if visibleParentRect.isEmpty == false {
                return visibleParentRect
            }
        }
        return TreemapRasterGeometry.discoveryRect(around: targetRect, in: bounds)
    }

    private func discoveryAnimationTargetRect(for entry: TreemapLayoutEntry) -> NSRect? {
        let scale: CGFloat = window?.backingScaleFactor ?? 1
        let selectedRect: NSRect = NSRect(
            x: entry.rect.x,
            y: entry.rect.y,
            width: entry.rect.width,
            height: entry.rect.height
        )
        let sourceRect: NSRect
        if selectedRect.isEmpty {
            sourceRect = TreemapRasterGeometry.pixelAlignedRect(
                for: NSRect(
                    x: entry.unroundedRect.x,
                    y: entry.unroundedRect.y,
                    width: entry.unroundedRect.width,
                    height: entry.unroundedRect.height
                ),
                scale: scale
            ).intersection(bounds)
        } else {
            sourceRect = TreemapSelectionRect.visibleRect(
                for: selectedRect,
                in: bounds
            )
        }
        guard sourceRect.isEmpty == false,
              min(sourceRect.width, sourceRect.height) <= ScanWindowMetrics.treemapMinimumSelectionSide else {
            return nil
        }
        // Always enlarge to a guaranteed-visible marker, not just for the
        // fully-collapsed case: a merely-tiny rect degenerates the animation's
        // inset stroke and corner guide lines into near-zero-size geometry.
        let targetRect: NSRect = TreemapRasterGeometry.visibleMarkerRect(
            for: sourceRect,
            in: bounds,
            scale: scale
        )
        guard targetRect.isEmpty == false else { return nil }
        return targetRect
    }

}
