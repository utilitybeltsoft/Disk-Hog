import AppKit

final class ZStyleTreemapNSView: NSView {
    var onSelectItem: ((DiskItem?) -> Void)?
    var onHoverItem: ((DiskItem?) -> Void)?
    var onZoomIn: ((DiskItem) -> Void)?
    var onZoomOut: (() -> Void)?

    private weak var session: ScanSession?
    private let contextMenuActionTarget: DiskItemContextMenuActionTarget = DiskItemContextMenuActionTarget()
    private let state: TreemapViewState = TreemapViewState()
    private let trackingAreaController: TreemapTrackingAreaController = TreemapTrackingAreaController()
    private let discoveryAnimation: TreemapDiscoveryAnimation = TreemapDiscoveryAnimation()
    private var pendingDiscoveryAnimation: Bool = false

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
        state.onRenderedImageReady = { [weak self] in
            self?.needsDisplay = true
        }
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
            return
        }

        let drawableRect: NSRect = dirtyRect.intersection(bounds)
        guard drawableRect.isEmpty == false else {
            return
        }
        if drawRenderedImage(destinationRect: drawableRect, sourceRect: drawableRect, fraction: 1) == false {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }
        TreemapViewPainter.drawSelection(
            entry: state.selectedEntry(),
            in: bounds,
            backingScaleFactor: window?.backingScaleFactor ?? 1
        )
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
        onHoverItem?(hitResult?.item)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverItem?(nil)
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
        onSelectItem?(hitResult.item)
        needsDisplay = true
    }

    private func selectNeighbor(in direction: TreemapNavigationDirection) {
        guard let item: DiskItem = state.selectNeighbor(in: direction) else { return }
        onSelectItem?(item)
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
        guard let targetRect: NSRect = discoveryAnimationTargetRect() else { return }
        discoveryAnimation.start(
            from: TreemapRasterGeometry.discoveryRect(around: targetRect, in: bounds),
            to: targetRect
        ) { [weak self] in
            guard let self else { return }
            self.setNeedsDisplay(self.bounds)
        }
    }

    private func discoveryAnimationTargetRect() -> NSRect? {
        guard let entry: TreemapLayoutEntry = state.selectedEntry() else { return nil }
        let selectedRect: NSRect = NSRect(
            x: entry.rect.x,
            y: entry.rect.y,
            width: entry.rect.width,
            height: entry.rect.height
        )
        let targetRect: NSRect
        if selectedRect.isEmpty {
            targetRect = TreemapRasterGeometry.visibleMarkerRect(
                for: TreemapRasterGeometry.pixelAlignedRect(
                    for: NSRect(
                        x: entry.unroundedRect.x,
                        y: entry.unroundedRect.y,
                        width: entry.unroundedRect.width,
                        height: entry.unroundedRect.height
                    ),
                    scale: window?.backingScaleFactor ?? 1
                ).intersection(bounds),
                in: bounds,
                scale: window?.backingScaleFactor ?? 1
            )
        } else {
            targetRect = TreemapSelectionRect.visibleRect(
                for: selectedRect,
                in: bounds
            )
        }
        guard targetRect.isEmpty == false, min(targetRect.width, targetRect.height) <= 12 else {
            return nil
        }
        return targetRect
    }

}
