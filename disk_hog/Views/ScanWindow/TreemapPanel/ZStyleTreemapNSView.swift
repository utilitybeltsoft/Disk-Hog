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
            needsDisplay = true
        }
        state.renderer?.onCachedBitmapReady = { [weak self] in
            self?.needsDisplay = true
        }
    }

    func applySelectedItem(_ selectedItem: DiskItem?) {
        if state.applySelectedItem(selectedItem) {
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
            if drawCachedImage(
                destinationRect: bounds,
                sourceRect: nil,
                fraction: ScanWindowMetrics.treemapLiveResizeImageFraction
            ) == false {
                NSColor.windowBackgroundColor.setFill()
                dirtyRect.fill()
            }
            return
        }

        state.prepareLayout(in: bounds)
        _ = drawCachedImage(destinationRect: dirtyRect, sourceRect: dirtyRect, fraction: 1)
        TreemapViewPainter.drawSelection(renderer: state.renderer, in: bounds)
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
        onHoverItem?(hitResult(for: event)?.item)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverItem?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let hitResult: TreemapHitResult = hitResult(for: event) else {
            return
        }
        select(hitResult)
        if event.clickCount == 2 {
            onZoomIn?(hitResult.item)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            if let item: DiskItem = state.selectedItem {
                onZoomIn?(item)
                return
            }
        case 53: // Escape
            onZoomOut?()
            return
        default:
            break
        }
        super.keyDown(with: event)
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
        state.select(hitResult)
        onSelectItem?(hitResult.item)
        needsDisplay = true
    }

    private func drawCachedImage(
        destinationRect: NSRect,
        sourceRect: NSRect?,
        fraction: CGFloat
    ) -> Bool {
        TreemapViewPainter.drawCachedImage(
            renderer: state.renderer,
            canvasSize: bounds.size,
            backingScaleFactor: window?.backingScaleFactor ?? 1,
            colorSpace: window?.colorSpace,
            destinationRect: destinationRect,
            sourceRect: sourceRect,
            fraction: fraction
        )
    }
}
