import AppKit

final class ZStyleTreemapNSView: NSView {
    var onSelectItem: ((DiskItem?) -> Void)?
    var onHoverItem: ((DiskItem?) -> Void)?
    var onZoomIn: ((DiskItem) -> Void)?
    var onZoomOut: (() -> Void)?
    var onPreviewSpaceChanged: ((Bool) -> Void)?
    var isInteractionEnabled: Bool = true

    private weak var session: ScanSession?
    private let contextMenuActionTarget: DiskItemContextMenuActionTarget = DiskItemContextMenuActionTarget()
    private let state: TreemapViewState = TreemapViewState()
    private let trackingAreaController: TreemapTrackingAreaController = TreemapTrackingAreaController()
    private var pendingSelectionDiagnostic: SelectionDiagnostic?

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
        let drawableRect: NSRect = dirtyRect.intersection(bounds)
        guard drawableRect.isEmpty == false else {
            return
        }
        _ = drawCachedImage(destinationRect: drawableRect, sourceRect: drawableRect, fraction: 1)
        TreemapViewPainter.drawSelection(renderer: state.renderer, in: bounds)
        logPendingSelectionDiagnostic(dirtyRect: dirtyRect)
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
        guard isInteractionEnabled else { return }
        onHoverItem?(hitResult(for: event)?.item)
    }

    override func mouseExited(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        onHoverItem?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        window?.makeFirstResponder(self)
        let point: NSPoint = convert(event.locationInWindow, from: nil)
        guard let hitResult: TreemapHitResult = state.hitResult(at: point) else {
            return
        }
        select(hitResult, cursorPoint: point)
        if event.clickCount == 2 {
            onZoomIn?(hitResult.item)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.isARepeat == false {
            onPreviewSpaceChanged?(true)
            return
        }
        guard isInteractionEnabled else {
            super.keyDown(with: event)
            return
        }
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

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            onPreviewSpaceChanged?(false)
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        onPreviewSpaceChanged?(false)
        return super.resignFirstResponder()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isInteractionEnabled else { return nil }
        let hitResult: TreemapHitResult? = hitResult(for: event)
        if let hitResult: TreemapHitResult = hitResult {
            select(hitResult, cursorPoint: convert(event.locationInWindow, from: nil))
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

    private func select(_ hitResult: TreemapHitResult, cursorPoint: NSPoint) {
        state.select(hitResult)
        pendingSelectionDiagnostic = SelectionDiagnostic(
            cursorPoint: cursorPoint,
            hitItemPath: hitResult.item.path,
            hitRect: hitResult.cellID.rect
        )
        onSelectItem?(hitResult.item)
        needsDisplay = true
    }

    private func logPendingSelectionDiagnostic(dirtyRect: NSRect) {
        guard let diagnostic: SelectionDiagnostic = pendingSelectionDiagnostic else { return }
        defer { pendingSelectionDiagnostic = nil }

        let selectedCellID: TreemapItemRenderer? = state.renderer?.selectedCellID
        let selectedRect: NSRect = state.renderer?.itemRect(by: selectedCellID) ?? .zero
        let outlineRect: NSRect = TreemapSelectionRect.visibleRect(
            for: selectedRect,
            in: bounds,
            minimumSide: ScanWindowMetrics.treemapMinimumSelectionSide,
            edgeInset: ScanWindowMetrics.treemapSelectionOuterLineWidth / 2
        )
        let selectedPath: String = selectedCellID?.item.path ?? "<none>"
        NSLog(
            """
            Treemap selection diagnostic
              cursor point: \(NSStringFromPoint(diagnostic.cursorPoint))
              hit item: \(diagnostic.hitItemPath)
              hit rect: \(NSStringFromRect(diagnostic.hitRect))
              selected item: \(selectedPath)
              selected rect: \(NSStringFromRect(selectedRect))
              outline rect: \(NSStringFromRect(outlineRect))
              view bounds: \(NSStringFromRect(bounds))
              view frame: \(NSStringFromRect(frame))
              visible rect: \(NSStringFromRect(visibleRect))
              dirty rect: \(NSStringFromRect(dirtyRect))
              bounds in window: \(NSStringFromRect(convert(bounds, to: nil)))
              bitmap: \(state.renderer?.bitmapDiagnosticsDescription ?? "no renderer")
            """
        )
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

private struct SelectionDiagnostic {
    let cursorPoint: NSPoint
    let hitItemPath: String
    let hitRect: NSRect
}
