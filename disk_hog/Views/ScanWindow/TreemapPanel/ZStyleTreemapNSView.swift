import AppKit

final class ZStyleTreemapNSView: NSView {
    var onSelectItem: ((DiskItem?) -> Void)?
    var onHoverItem: ((DiskItem?) -> Void)?

    private var source: ScanSource?
    private var rootItem: DiskItem?
    private var presentationMetrics: TreemapPresentationMetrics?
    private var selectedItem: DiskItem?
    private var renderer: TreemapViewRenderer?
    private var rendererDataSource: TreemapDiskItemDataSource?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func configure(source: ScanSource, rootItem: DiskItem?, presentationMetrics: TreemapPresentationMetrics?, selectedItem: DiskItem?) {
        self.source = source

        if self.rootItem !== rootItem || self.presentationMetrics !== presentationMetrics {
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            rebuildRenderer()
        }

        if self.selectedItem !== selectedItem {
            self.selectedItem = selectedItem
            syncSelectionToRenderer()
            needsDisplay = true
        }
    }

    func applySelectedItem(_ selectedItem: DiskItem?) {
        guard self.selectedItem !== selectedItem else {
            return
        }

        self.selectedItem = selectedItem
        syncSelectionToRenderer()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingArea: NSTrackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let trackingArea: NSTrackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rootItem: DiskItem = rootItem else {
            drawPlaceholder(in: dirtyRect)
            return
        }

        guard bounds.width >= ScanWindowMetrics.minimumRenderableTreemapSide,
              bounds.height >= ScanWindowMetrics.minimumRenderableTreemapSide else {
            return
        }

        if inLiveResize {
            if drawCachedImage(in: bounds, sourceRect: nil, fraction: ScanWindowMetrics.treemapLiveResizeImageFraction) == false {
                NSColor.windowBackgroundColor.setFill()
                dirtyRect.fill()
            }
            return
        }

        let viewBounds: NSRect = bounds
        if renderer == nil {
            rebuildRenderer()
        }

        if renderer?.rootCellID?.rect != viewBounds {
            renderer?.calcLayout(viewBounds)
            syncSelectionToRenderer()
            TreemapLayoutDiagnostics.writeBounds(rootItem: rootItem, size: viewBounds.size)
            #if TREEMAP_LAYOUT_DIAGNOSTICS
            if let renderer: TreemapViewRenderer = renderer {
                TreemapLayoutDiagnostics.writeLayout(rootItem: rootItem, size: viewBounds.size, renderer: renderer)
                TreemapLayoutDiagnostics.writeLayoutUsingZBoundsIfAvailable(
                    rootItem: rootItem,
                    minimumRenderableSide: ScanWindowMetrics.minimumRenderableTreemapSide
                )
            }
            #endif
        }

        _ = drawCachedImage(in: dirtyRect, sourceRect: dirtyRect, fraction: 1)
        drawSelection()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        discardTrackingAreas()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateTrackingAreas()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverItem?(hitResult(for: event.locationInWindow)?.item)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverItem?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let result: TreemapHitResult = hitResult(for: event.locationInWindow) else {
            return
        }

        renderer?.selectItem(by: result.cellID)
        selectedItem = result.item
        onSelectItem?(result.item)
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let item: DiskItem? = hitResult(for: event.locationInWindow)?.item ?? selectedItem
        let menu: NSMenu = NSMenu()

        guard let item: DiskItem = item, item.isSpecialItem == false else {
            let noItem: NSMenuItem = NSMenuItem(title: "No Item Selected", action: nil, keyEquivalent: "")
            noItem.isEnabled = false
            menu.addItem(noItem)
            return menu
        }

        menu.addItem(NSMenuItem(title: "Open", action: #selector(openMenuItem(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal in Finder", action: #selector(revealMenuItem(_:)), keyEquivalent: ""))
        menu.items.forEach { menuItem in
            menuItem.target = self
            menuItem.representedObject = item
        }
        return menu
    }

    @objc private func openMenuItem(_ sender: NSMenuItem) {
        guard let item: DiskItem = sender.representedObject as? DiskItem else {
            return
        }

        DiskItemWorkspaceActions.open(item)
    }

    @objc private func revealMenuItem(_ sender: NSMenuItem) {
        guard let item: DiskItem = sender.representedObject as? DiskItem else {
            return
        }

        DiskItemWorkspaceActions.revealInFinder(item)
    }

    private func rebuildRenderer() {
        guard let rootItem: DiskItem = rootItem else {
            renderer = nil
            rendererDataSource = nil
            needsDisplay = true
            return
        }

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: rootItem,
            usePhysicalSize: source?.scanSettings?.usePhysicalSize ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize,
            presentationMetrics: presentationMetrics
        )
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        rendererDataSource = dataSource
        self.renderer = renderer
        syncSelectionToRenderer()
        needsDisplay = true
    }

    private func syncSelectionToRenderer() {
        guard let item: DiskItem = selectedItem,
              let rootItem: DiskItem = rootItem,
              item.pathFromRoot().first === rootItem else {
            renderer?.selectItem(by: nil)
            return
        }

        if renderer?.selectItem(byRenderedItem: item) == false {
            let path: [DiskItem] = item.pathFromRoot()
            renderer?.selectItem(byPathToItem: path)
        }
    }

    private func drawCachedImage(in destinationRect: NSRect, sourceRect: NSRect?, fraction: CGFloat) -> Bool {
        guard let imageRep: NSBitmapImageRep = renderer?.drawInCache(
            size: bounds.size,
            scale: window?.backingScaleFactor ?? 1,
            colorSpace: window?.colorSpace
        ) else {
            return false
        }

        let image: NSImage = imageRep.treemapSuitableImage()
        let imageSize: NSSize = image.size
        let sourceRect: NSRect = sourceRect ?? NSRect(origin: .zero, size: imageSize)
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .copy,
            fraction: fraction,
            respectFlipped: true,
            hints: nil
        )
        return true
    }

    private func drawSelection() {
        guard let selectedCellID: TreemapItemRenderer = renderer?.selectedCellID else {
            return
        }

        let rect: NSRect = TreemapSelectionRect.visibleRect(
            for: renderer?.itemRect(by: selectedCellID) ?? .zero,
            in: bounds,
            minimumSide: ScanWindowMetrics.treemapMinimumSelectionSide,
            edgeInset: ScanWindowMetrics.treemapSelectionOuterLineWidth / 2
        )
        guard rect != .zero else {
            return
        }

        NSColor.black.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionOuterLineWidth)
        NSColor.white.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionMiddleLineWidth)
        NSColor.yellow.setStroke()
        stroke(rect: rect, lineWidth: ScanWindowMetrics.treemapSelectionInnerLineWidth)
    }

    private func stroke(rect: NSRect, lineWidth: CGFloat) {
        let path: NSBezierPath = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func hitResult(for windowLocation: NSPoint) -> TreemapHitResult? {
        let point: NSPoint = convert(windowLocation, from: nil)
        guard let cellID: TreemapItemRenderer = renderer?.cellID(by: point, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID),
              !item.isSpecialItem else {
            return nil
        }

        return TreemapHitResult(item: item, cellID: cellID)
    }

    private func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard let source: ScanSource = source else {
            return
        }

        let paragraphStyle: NSMutableParagraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: ScanWindowMetrics.placeholderTitleFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let pathAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: ScanWindowMetrics.placeholderPathFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect: NSRect = NSRect(x: bounds.minX + ScanWindowMetrics.placeholderPadding, y: bounds.midY - ScanWindowMetrics.placeholderTitleYOffset, width: bounds.width - ScanWindowMetrics.placeholderPadding * 2, height: ScanWindowMetrics.placeholderLineHeight)
        let pathRect: NSRect = NSRect(x: bounds.minX + ScanWindowMetrics.placeholderPadding, y: titleRect.maxY + ScanWindowMetrics.placeholderSpacing, width: bounds.width - ScanWindowMetrics.placeholderPadding * 2, height: ScanWindowMetrics.placeholderLineHeight)
        NSString(string: "Treemap").draw(in: titleRect, withAttributes: titleAttributes)
        NSString(string: source.path).draw(in: pathRect, withAttributes: pathAttributes)
    }

    private func discardTrackingAreas() {
        if let trackingArea: NSTrackingArea = trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }

}

private struct TreemapHitResult {
    let item: DiskItem
    let cellID: TreemapItemRenderer
}
