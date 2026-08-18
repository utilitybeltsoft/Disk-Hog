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
    private var pendingDiscoveryAnimation: Bool = false
    private var discoveryAnimationStartDate: Date?
    private var discoveryAnimationStartRect: NSRect = .zero
    private var discoveryAnimationTarget: NSRect = .zero
    private var discoveryAnimationTimer: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    deinit { discoveryAnimationTimer?.invalidate() }

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
        state.renderer?.onCachedBitmapReady = { [weak self] in
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
        TreemapViewPainter.drawSelection(
            renderer: state.renderer,
            in: bounds,
            backingScaleFactor: window?.backingScaleFactor ?? 1
        )
        startDiscoveryAnimationIfNeeded()
        drawDiscoveryAnimation()
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
        let hitResult: TreemapHitResult? = hitResult(for: event)
        onHoverItem?(hitResult?.item)
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
            return
        }
        switch event.keyCode {
        case 123: // Left Arrow
            selectNeighbor(in: .left)
            return
        case 124: // Right Arrow
            selectNeighbor(in: .right)
            return
        case 125: // Down Arrow
            selectNeighbor(in: .down)
            return
        case 126: // Up Arrow
            selectNeighbor(in: .up)
            return
        case 36, 76: // Return, keypad Enter
            if event.modifierFlags.contains(.shift) {
                onZoomOut?()
                return
            }
            if let item: DiskItem = state.selectedItem {
                onZoomIn?(item)
                return
            }
        case 53: // Escape
            onZoomOut?()
            return
        default:
            return
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            onPreviewSpaceChanged?(false)
            return
        }
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
        let selectionChanged: Bool = state.selectedItem != hitResult.item
        state.select(hitResult)
        pendingDiscoveryAnimation = selectionChanged
        pendingSelectionDiagnostic = SelectionDiagnostic(
            cursorPoint: cursorPoint,
            hitItemPath: hitResult.item.path,
            hitRect: hitResult.cellID.rect
        )
        onSelectItem?(hitResult.item)
        needsDisplay = true
    }

    private func selectNeighbor(in direction: TreemapNavigationDirection) {
        guard let item: DiskItem = state.selectNeighbor(in: direction) else { return }
        onSelectItem?(item)
        needsDisplay = true
    }

    private func logPendingSelectionDiagnostic(dirtyRect: NSRect) {
        guard let diagnostic: SelectionDiagnostic = pendingSelectionDiagnostic else { return }
        defer { pendingSelectionDiagnostic = nil }

        let selectedCellID: TreemapItemRenderer? = state.renderer?.selectedCellID
        let selectedRect: NSRect = state.renderer?.itemRect(by: selectedCellID) ?? .zero
        let outlineRect: NSRect = TreemapSelectionRect.visibleRect(
            for: selectedRect,
            in: bounds
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

    private func startDiscoveryAnimationIfNeeded() {
        guard pendingDiscoveryAnimation else { return }
        pendingDiscoveryAnimation = false
        guard let targetRect: NSRect = discoveryAnimationTargetRect() else { return }
        discoveryAnimationStartRect = TreemapRasterGeometry.discoveryRect(around: targetRect, in: bounds)
        discoveryAnimationTarget = targetRect
        discoveryAnimationStartDate = Date()
        discoveryAnimationTimer?.invalidate()
        discoveryAnimationTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(advanceDiscoveryAnimation),
            userInfo: nil,
            repeats: true
        )
        setNeedsDisplay(bounds)
    }

    private func discoveryAnimationTargetRect() -> NSRect? {
        guard let renderer: TreemapViewRenderer = state.renderer else { return nil }
        let selectedRect: NSRect = renderer.itemRect(by: renderer.selectedCellID)
        let targetRect: NSRect
        if selectedRect.isEmpty {
            targetRect = TreemapRasterGeometry.visibleMarkerRect(
                for: TreemapRasterGeometry.pixelAlignedRect(
                    for: renderer.selectedItemUnroundedRect(),
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

    @objc private func advanceDiscoveryAnimation() {
        guard let discoveryAnimationStartDate else { return }
        let progress: CGFloat = min(CGFloat(Date().timeIntervalSince(discoveryAnimationStartDate) / 1.1), 1)
        setNeedsDisplay(bounds)
        if progress == 1 {
            discoveryAnimationTimer?.invalidate()
            discoveryAnimationTimer = nil
            self.discoveryAnimationStartDate = nil
        }
    }

    private func drawDiscoveryAnimation() {
        guard let discoveryAnimationStartDate else { return }
        let progress: CGFloat = min(CGFloat(Date().timeIntervalSince(discoveryAnimationStartDate) / 1.1), 1)
        let easedProgress: CGFloat = 1 - pow(1 - progress, 3)
        let currentRect: NSRect = interpolatedRect(
            from: discoveryAnimationStartRect,
            to: discoveryAnimationTarget,
            progress: easedProgress
        )
        NSColor.yellow.withAlphaComponent(0.8 * (1 - progress)).setStroke()
        let guidePath: NSBezierPath = NSBezierPath()
        for (start, end) in zip(rectCorners(discoveryAnimationStartRect), rectCorners(discoveryAnimationTarget)) {
            guidePath.move(to: start)
            guidePath.line(to: end)
        }
        guidePath.lineWidth = 1
        guidePath.stroke()

        NSColor.yellow.withAlphaComponent(0.95).setStroke()
        let focusPath: NSBezierPath = NSBezierPath(rect: currentRect.insetBy(dx: 1, dy: 1))
        focusPath.lineWidth = 2
        focusPath.stroke()
    }

    private func rectCorners(_ rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY)
        ]
    }

    private func interpolatedRect(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
}

private struct SelectionDiagnostic {
    let cursorPoint: NSPoint
    let hitItemPath: String
    let hitRect: NSRect
}
