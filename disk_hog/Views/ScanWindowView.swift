import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession
    @State private var selectedItem: DiskItem?
    @State private var hoveredItem: DiskItem?
    @State private var shouldSkipNextOutlineSelectionSync: Bool = false

    init(source: ScanSource) {
        _session = StateObject(wrappedValue: ScanSession(source: source))
    }

    var body: some View {
        VStack(spacing: Metrics.windowContentSpacing) {
            VSplitView {
                HSplitView {
                    FilesPaneView(session: session)
                        .environment(\.selectedScanItem, $selectedItem)
                        .environment(\.hoveredScanItem, $hoveredItem)
                        .environment(\.skipNextOutlineSelectionSync, $shouldSkipNextOutlineSelectionSync)
                        .frame(minWidth: Metrics.filesPaneMinimumWidth, idealWidth: Metrics.filesPaneIdealWidth)

                    KindsPaneView(session: session)
                        .environment(\.selectedScanItem, $selectedItem)
                        .frame(minWidth: Metrics.kindsPaneMinimumWidth, idealWidth: Metrics.kindsPaneIdealWidth)
                }
                .frame(minHeight: Metrics.topPaneMinimumHeight, idealHeight: Metrics.topPaneIdealHeight)

                TreemapPanelView(session: session)
                    .environment(\.selectedScanItem, $selectedItem)
                    .environment(\.hoveredScanItem, $hoveredItem)
                    .environment(\.skipNextOutlineSelectionSync, $shouldSkipNextOutlineSelectionSync)
                    .frame(minWidth: Metrics.treemapMinimumWidth, minHeight: Metrics.treemapMinimumHeight)
            }
            .padding(.horizontal, Metrics.mainSplitHorizontalPadding)
            .padding(.top, Metrics.mainSplitTopPadding)

            ZStatusFieldsView(session: session)
                .environment(\.selectedScanItem, $selectedItem)
                .environment(\.hoveredScanItem, $hoveredItem)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ScanWindowRegistrationView(source: session.source))
        .onAppear {
            session.startScan()
        }
        .onAppear {
            updateScanWindowCommandState()
        }
        .onChange(of: session.rootItem?.id) {
            selectedItem = session.rootItem
            hoveredItem = nil
            updateScanWindowCommandState()
        }
        .onChange(of: selectedItem?.id) {
            updateScanWindowCommandState()
        }
        #if FILE_MATCHING_DIAGNOSTICS
        .onChange(of: session.diagnosticsExportState) {
            updateScanWindowCommandState()
        }
        #endif
    }

    private func updateScanWindowCommandState() {
        ScanWindowCommandState.shared.activate(session: session)
        ScanWindowCommandState.shared.updateSelectedItem(selectedItem)
        ScanWindowCommandState.shared.updateScanState(from: session)
    }
}

private struct SelectedScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct HoveredScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct SkipNextOutlineSelectionSyncKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

private extension EnvironmentValues {
    var selectedScanItem: Binding<DiskItem?> {
        get { self[SelectedScanItemKey.self] }
        set { self[SelectedScanItemKey.self] = newValue }
    }

    var hoveredScanItem: Binding<DiskItem?> {
        get { self[HoveredScanItemKey.self] }
        set { self[HoveredScanItemKey.self] = newValue }
    }

    var skipNextOutlineSelectionSync: Binding<Bool> {
        get { self[SkipNextOutlineSelectionSyncKey.self] }
        set { self[SkipNextOutlineSelectionSyncKey.self] = newValue }
    }
}

private struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.skipNextOutlineSelectionSync) private var skipNextOutlineSelectionSync

    var body: some View {
        Group {
            if let rootItem: DiskItem = session.rootItem {
                DiskItemOutlineView(
                    rootItem: rootItem,
                    selectedItem: selectedItem,
                    hoveredItem: hoveredItem,
                    skipNextOutlineSelectionSync: skipNextOutlineSelectionSync
                )
            } else {
                FileScanPlaceholderRowsView(session: session)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct DiskItemOutlineView: NSViewRepresentable {
    let rootItem: DiskItem
    let selectedItem: Binding<DiskItem?>
    let hoveredItem: Binding<DiskItem?>
    let skipNextOutlineSelectionSync: Binding<Bool>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedItem: selectedItem,
            hoveredItem: hoveredItem,
            skipNextOutlineSelectionSync: skipNextOutlineSelectionSync
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView: NSOutlineView = NSOutlineView()
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = Metrics.tableRowHeight
        outlineView.indentationPerLevel = Metrics.outlineIndentWidth
        outlineView.allowsMultipleSelection = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .controlBackgroundColor

        let nameColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.name)
        nameColumn.title = "Name"
        nameColumn.minWidth = Metrics.outlineNameColumnMinimumWidth
        nameColumn.resizingMask = .autoresizingMask
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.size)
        sizeColumn.title = "Size"
        sizeColumn.width = Metrics.filesSizeColumnWidth
        sizeColumn.minWidth = Metrics.filesSizeColumnWidth
        sizeColumn.maxWidth = Metrics.filesSizeColumnWidth
        sizeColumn.resizingMask = []
        outlineView.addTableColumn(sizeColumn)

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClick(_:))

        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(rootItem: rootItem)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.selectedItem = selectedItem
        context.coordinator.hoveredItem = hoveredItem
        context.coordinator.skipNextOutlineSelectionSync = skipNextOutlineSelectionSync
        context.coordinator.reloadIfNeeded(rootItem: rootItem)
        context.coordinator.syncSelectionIfNeeded(selectedItem.wrappedValue)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var selectedItem: Binding<DiskItem?>
        var hoveredItem: Binding<DiskItem?>
        var skipNextOutlineSelectionSync: Binding<Bool>
        weak var outlineView: NSOutlineView?
        private var rootItem: DiskItem?
        private var isApplyingSelection: Bool = false

        init(
            selectedItem: Binding<DiskItem?>,
            hoveredItem: Binding<DiskItem?>,
            skipNextOutlineSelectionSync: Binding<Bool>
        ) {
            self.selectedItem = selectedItem
            self.hoveredItem = hoveredItem
            self.skipNextOutlineSelectionSync = skipNextOutlineSelectionSync
        }

        func reloadIfNeeded(rootItem: DiskItem) {
            guard self.rootItem !== rootItem else {
                return
            }

            reload(rootItem: rootItem)
        }

        func reload(rootItem: DiskItem) {
            self.rootItem = rootItem
            outlineView?.reloadData()
            outlineView?.expandItem(rootItem)
        }

        func syncSelectionIfNeeded(_ item: DiskItem?) {
            guard let outlineView: NSOutlineView = outlineView else {
                return
            }

            if skipNextOutlineSelectionSync.wrappedValue {
                skipNextOutlineSelectionSync.wrappedValue = false
                return
            }

            guard let item: DiskItem = item else {
                isApplyingSelection = true
                outlineView.deselectAll(nil)
                isApplyingSelection = false
                return
            }

            if outlineView.item(atRow: outlineView.selectedRow) as? DiskItem === item {
                return
            }

            expandAncestors(of: item)
            let row: Int = outlineView.row(forItem: item)
            guard row >= 0 else {
                isApplyingSelection = true
                outlineView.deselectAll(nil)
                isApplyingSelection = false
                return
            }

            isApplyingSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            isApplyingSelection = false
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item: DiskItem = item as? DiskItem else {
                return rootItem == nil ? 0 : 1
            }

            return item.childCount
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item: DiskItem = item as? DiskItem else {
                return rootItem!
            }

            return item.child(at: index)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item: DiskItem = item as? DiskItem else {
                return false
            }

            return item.childCount > 0
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item: DiskItem = item as? DiskItem,
                  let tableColumn: NSTableColumn = tableColumn else {
                return nil
            }

            if tableColumn.identifier == ColumnID.size {
                return sizeCell(for: item, outlineView: outlineView)
            }

            return nameCell(for: item, outlineView: outlineView)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let outlineView: NSOutlineView = outlineView else {
                return
            }

            selectedItem.wrappedValue = outlineView.selectedRow >= 0 ? outlineView.item(atRow: outlineView.selectedRow) as? DiskItem : nil
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is DiskItem
        }

        func outlineView(_ outlineView: NSOutlineView, mouseDownInHeaderOf tableColumn: NSTableColumn) {}

        @objc func doubleClick(_ sender: Any?) {
            guard let outlineView: NSOutlineView = outlineView,
                  outlineView.clickedRow >= 0,
                  let item: DiskItem = outlineView.item(atRow: outlineView.clickedRow) as? DiskItem,
                  item.childCount > 0 else {
                return
            }

            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }

        private func expandAncestors(of item: DiskItem) {
            var ancestors: [DiskItem] = []
            var ancestor: DiskItem? = item.parent
            while let currentAncestor: DiskItem = ancestor {
                ancestors.append(currentAncestor)
                ancestor = currentAncestor.parent
            }

            for ancestor: DiskItem in ancestors.reversed() {
                outlineView?.expandItem(ancestor)
            }
        }

        private func nameCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = CellID.name
            let cell: DiskItemNameCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemNameCellView ?? DiskItemNameCellView()
            cell.identifier = identifier
            cell.configure(item: item)
            return cell
        }

        private func sizeCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = CellID.size
            let cell: DiskItemSizeCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemSizeCellView ?? DiskItemSizeCellView()
            cell.identifier = identifier
            cell.configure(item: item)
            return cell
        }
    }

    private final class DiskItemNameCellView: NSTableCellView {
        private let iconImageView: NSImageView = NSImageView()
        private let titleTextField: NSTextField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(item: DiskItem) {
            iconImageView.image = NSWorkspace.shared.icon(forFile: item.path)
            titleTextField.stringValue = item.displayName
        }

        private func setup() {
            imageView = iconImageView
            textField = titleTextField
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            titleTextField.translatesAutoresizingMaskIntoConstraints = false
            titleTextField.lineBreakMode = .byTruncatingMiddle
            titleTextField.font = NSFont.systemFont(ofSize: Metrics.tableFontSize)
            addSubview(iconImageView)
            addSubview(titleTextField)
            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.outlineCellHorizontalPadding),
                iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: Metrics.outlineIconWidth),
                iconImageView.heightAnchor.constraint(equalToConstant: Metrics.outlineIconWidth),
                titleTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Metrics.outlineIconTextSpacing),
                titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.outlineCellHorizontalPadding),
                titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    private final class DiskItemSizeCellView: NSTableCellView {
        private let sizeTextField: NSTextField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(item: DiskItem) {
            sizeTextField.stringValue = ByteCountFormatter.string(fromByteCount: Int64(item.allocatedSizeValue), countStyle: .file)
        }

        private func setup() {
            textField = sizeTextField
            sizeTextField.alignment = .right
            sizeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: Metrics.tableFontSize, weight: .regular)
            sizeTextField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sizeTextField)
            NSLayoutConstraint.activate([
                sizeTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.outlineCellHorizontalPadding),
                sizeTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.outlineCellHorizontalPadding),
                sizeTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    private enum ColumnID {
        static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("name")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("size")
    }

    private enum CellID {
        static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("nameCell")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("sizeCell")
    }
}

private struct FileScanPlaceholderRowsView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.placeholderSpacing) {
            Text(session.state.title)
                .font(.system(size: Metrics.tableFontSize))
            Text(session.currentPath)
                .font(.system(size: Metrics.tableFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(Metrics.placeholderPathLineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let errorMessage: String = session.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Metrics.tableFontSize))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(Metrics.placeholderPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KindsPaneView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @State private var kindStatistics: [TreemapKindStatistic] = []
    @State private var selectedKindName: String?
    @State private var shouldScrollToSelectedKind: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            TableHeaderRowView {
                Text("Color")
                    .frame(width: Metrics.kindColorColumnWidth, alignment: .leading)
                Text("Kind")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: Metrics.kindSizeColumnWidth, alignment: .trailing)
                Text("Files")
                    .frame(width: Metrics.kindFilesColumnWidth, alignment: .trailing)
            }

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 0) {
                        ForEach(kindStatistics) { statistic in
                            KindStatisticRowView(
                                statistic: statistic,
                                isSelected: statistic.kindName == selectedKindName
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                shouldScrollToSelectedKind = false
                                selectedKindName = statistic.kindName
                            }
                            .id(statistic.kindName)
                        }
                    }
                    .onChange(of: selectedKindName) {
                        guard let selectedKindName: String else {
                            return
                        }

                        guard shouldScrollToSelectedKind else {
                            return
                        }

                        proxy.scrollTo(selectedKindName, anchor: .center)
                        shouldScrollToSelectedKind = false
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            updateKindStatistics()
        }
        .onChange(of: session.rootItem?.id) {
            updateKindStatistics()
        }
        .onChange(of: selectedItem.wrappedValue?.id) {
            updateSelectedKindName()
        }
    }

    private func updateKindStatistics() {
        guard let rootItem: DiskItem = session.rootItem else {
            kindStatistics = []
            return
        }

        kindStatistics = TreemapDiskItemDataSource.kindStatistics(for: rootItem)
        updateSelectedKindName()
    }

    private func updateSelectedKindName() {
        guard let item: DiskItem = selectedItem.wrappedValue,
              !item.isFolder,
              let kindName: String = item.kindName,
              kindStatistics.contains(where: { $0.kindName == kindName }) else {
            shouldScrollToSelectedKind = false
            selectedKindName = nil
            return
        }

        shouldScrollToSelectedKind = true
        selectedKindName = kindName
    }
}

private struct KindStatisticRowView: View {
    let statistic: TreemapKindStatistic
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Metrics.tableColumnSpacing) {
            RoundedRectangle(cornerRadius: Metrics.kindSwatchCornerRadius)
                .fill(Color(nsColor: statistic.color))
                .frame(width: Metrics.kindSwatchWidth, height: Metrics.kindSwatchHeight)
                .frame(width: Metrics.kindColorColumnWidth, alignment: .leading)
            Text(statistic.kindName)
                .lineLimit(Metrics.singleLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteCountFormatter.string(fromByteCount: Int64(statistic.size), countStyle: .file))
                .monospacedDigit()
                .frame(width: Metrics.kindSizeColumnWidth, alignment: .trailing)
            Text("\(statistic.fileCount)")
                .monospacedDigit()
                .frame(width: Metrics.kindFilesColumnWidth, alignment: .trailing)
        }
        .font(.system(size: Metrics.tableFontSize))
        .padding(.horizontal, Metrics.tableHorizontalPadding)
        .frame(height: Metrics.tableRowHeight)
        .background(isSelected ? Color.accentColor.opacity(Metrics.tableSelectionOpacity) : Color.clear)
    }
}

private struct TableHeaderRowView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Metrics.tableColumnSpacing) {
            content()
        }
        .font(.system(size: Metrics.tableHeaderFontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.tableHorizontalPadding)
        .frame(height: Metrics.tableHeaderHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.skipNextOutlineSelectionSync) private var skipNextOutlineSelectionSync
    @State private var renderedImage: NSImage?
    @State private var renderedRootID: ObjectIdentifier?
    @State private var renderedSize: CGSize = .zero
    @State private var renderer: TreemapViewRenderer?
    @State private var rendererDataSource: TreemapDiskItemDataSource?
    @State private var selectedItemRect: NSRect = .zero
    @State private var selectedItemWasSetFromTreemap: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .textBackgroundColor)

                if let renderedImage {
                    Image(nsImage: renderedImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TreemapPlaceholderContent(source: session.source)
                }

                if selectedItemRect != .zero {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: Metrics.treemapSelectionLineWidth)
                        .frame(width: selectedItemRect.width, height: selectedItemRect.height)
                        .position(
                            x: selectedItemRect.midX,
                            y: selectedItemRect.midY
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectTreemapItem(at: value.location, size: proxy.size)
                    }
            )
            .contextMenu {
                DiskItemContextMenu(item: hoveredItem.wrappedValue ?? selectedItem.wrappedValue)
            }
            .onAppear {
                renderIfNeeded(for: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                renderIfNeeded(for: newSize)
            }
            .onChange(of: session.rootItem?.id) { _, _ in
                renderedImage = nil
                renderedRootID = nil
                renderer = nil
                rendererDataSource = nil
                renderIfNeeded(for: proxy.size)
            }
            .onChange(of: selectedItem.wrappedValue?.id) {
                updateSelectedRect()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func renderIfNeeded(for size: CGSize) {
        guard let rootItem: DiskItem = session.rootItem else {
            renderedImage = nil
            renderedRootID = nil
            renderedSize = .zero
            renderer = nil
            rendererDataSource = nil
            selectedItemRect = .zero
            return
        }

        guard size.width >= Metrics.minimumRenderableTreemapSide,
              size.height >= Metrics.minimumRenderableTreemapSide else {
            return
        }

        if renderedRootID == rootItem.id && renderedSize == size && renderedImage != nil {
            return
        }

        renderedRootID = rootItem.id
        renderedSize = size
        let renderedTreemap: RenderedTreemap? = Self.renderTreemap(rootItem: rootItem, size: size)
        renderedImage = renderedTreemap?.image
        renderer = renderedTreemap?.renderer
        rendererDataSource = renderedTreemap?.dataSource
        updateSelectedRect()
    }

    private static func renderTreemap(rootItem: DiskItem, size: CGSize) -> RenderedTreemap? {
        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: rootItem)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(
            rootItem: dataSource.root,
            dataSource: dataSource,
            delegate: dataSource
        )
        let bounds: NSRect = NSRect(origin: .zero, size: size)
        renderer.reloadData()
        renderer.calcLayout(bounds)
        guard let image: NSImage = renderer.drawInCache(size: size)?.treemapSuitableImage() else {
            return nil
        }

        return RenderedTreemap(image: image, renderer: renderer, dataSource: dataSource)
    }

    private func selectTreemapItem(at location: CGPoint, size: CGSize) {
        guard let result: TreemapHitResult = treemapHitResult(at: location, size: size) else {
            return
        }

        renderer?.selectItem(by: result.cellID)
        selectedItemWasSetFromTreemap = true
        skipNextOutlineSelectionSync.wrappedValue = true
        selectedItem.wrappedValue = result.item
        selectedItemRect = renderer?.itemRect(by: renderer?.selectedCellID) ?? .zero
    }

    private func treemapHitResult(at location: CGPoint, size: CGSize) -> TreemapHitResult? {
        let rendererPoint: NSPoint = NSPoint(x: location.x, y: location.y)
        guard let cellID: TreemapCellID = renderer?.cellID(by: rendererPoint, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID) as? DiskItem,
              !item.isSpecialItem else {
            return nil
        }

        return TreemapHitResult(item: item, cellID: cellID)
    }

    private func updateSelectedRect() {
        if selectedItemWasSetFromTreemap {
            selectedItemWasSetFromTreemap = false
            return
        }

        guard let item: DiskItem = selectedItem.wrappedValue,
              let rootItem: DiskItem = session.rootItem,
              itemIsInTree(item, root: rootItem) else {
            selectedItemRect = .zero
            return
        }

        let path: [AnyObject] = item.pathFromRoot().map { $0 as AnyObject }
        renderer?.selectItem(byPathToItem: path)
        selectedItemRect = renderer?.itemRect(by: renderer?.selectedCellID) ?? .zero
    }

    private func itemIsInTree(_ item: DiskItem, root: DiskItem) -> Bool {
        item.pathFromRoot().first === root
    }
}

private struct TreemapHitResult {
    let item: DiskItem
    let cellID: TreemapCellID
}

private struct DiskItemContextMenu: View {
    let item: DiskItem?

    var body: some View {
        if let item: DiskItem = item, item.isSpecialItem == false {
            Button("Open") {
                NSWorkspace.shared.open(item.url)
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        } else {
            Button("No Item Selected") {}
                .disabled(true)
        }
    }
}

private struct RenderedTreemap {
    let image: NSImage
    let renderer: TreemapViewRenderer
    let dataSource: TreemapDiskItemDataSource
}

private struct TreemapPlaceholderContent: View {
    let source: ScanSource

    var body: some View {
        VStack(spacing: Metrics.placeholderSpacing) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: Metrics.treemapIconSize))
                .foregroundStyle(.secondary)
            Text("Treemap")
                .font(.title2.weight(.semibold))
            Text(source.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(Metrics.singleLineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(Metrics.placeholderPadding)
    }
}

private struct ZStatusFieldsView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem

    var body: some View {
        TimelineView(.periodic(from: Date(), by: Metrics.timerRefreshInterval)) { context in
            VStack(alignment: .leading, spacing: Metrics.statusFieldSpacing) {
                Text(statusName(referenceDate: context.date))
                    .lineLimit(Metrics.singleLineLimit)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(statusSize(referenceDate: context.date))
                    .lineLimit(Metrics.singleLineLimit)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.system(size: Metrics.statusFieldFontSize))
            .padding(.horizontal, Metrics.statusFieldHorizontalPadding)
            .padding(.bottom, Metrics.statusFieldBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusName(referenceDate: Date) -> String {
        if let statusItem: DiskItem = statusItem {
            if statusItem.isRoot {
                return statusItem.displayName
            }

            return "\(statusItem.displayName) (\(statusItem.displayFolderName))"
        }

        return session.currentPath
    }

    private func statusSize(referenceDate: Date) -> String {
        if let statusItem: DiskItem = statusItem {
            let size: String = ByteCountFormatter.string(fromByteCount: Int64(statusItem.allocatedSizeValue), countStyle: .file)
            guard !statusItem.isFolder, let kindName: String = statusItem.kindName else {
                return size
            }

            return "\(kindName), \(size)"
        }

        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = ByteCountFormatter.string(fromByteCount: Int64(session.scannedByteCount), countStyle: .file)
        return "\(session.state.title) - \(session.scannedItemCount) items - \(scannedSize) - elapsed \(elapsedTime)"
    }

    private var statusItem: DiskItem? {
        hoveredItem.wrappedValue ?? selectedItem.wrappedValue
    }
}

private enum ScanWindowMetrics {
    static let windowContentSpacing: CGFloat = 4
    static let timerRefreshInterval: TimeInterval = 1
    static let filesPaneMinimumWidth: CGFloat = 360
    static let filesPaneIdealWidth: CGFloat = 590
    static let kindsPaneMinimumWidth: CGFloat = 280
    static let kindsPaneIdealWidth: CGFloat = 380
    static let topPaneMinimumHeight: CGFloat = 160
    static let topPaneIdealHeight: CGFloat = 240
    static let treemapMinimumWidth: CGFloat = 760
    static let treemapMinimumHeight: CGFloat = 360
    static let windowMinimumWidth: CGFloat = 1000
    static let windowMinimumHeight: CGFloat = 700
    static let mainSplitHorizontalPadding: CGFloat = 10
    static let mainSplitTopPadding: CGFloat = 24
    static let tableHeaderHeight: CGFloat = 25
    static let tableRowHeight: CGFloat = 20
    static let tableHorizontalPadding: CGFloat = 6
    static let tableColumnSpacing: CGFloat = 8
    static let tableHeaderFontSize: CGFloat = 11
    static let tableFontSize: CGFloat = 12
    static let filesSizeColumnWidth: CGFloat = 76
    static let outlineNameColumnMinimumWidth: CGFloat = 180
    static let outlineIndentWidth: CGFloat = 16
    static let outlineDisclosureSpacing: CGFloat = 2
    static let outlineDisclosureWidth: CGFloat = 12
    static let outlineDisclosureIconSize: CGFloat = 9
    static let outlineIconWidth: CGFloat = 16
    static let outlineCellHorizontalPadding: CGFloat = 3
    static let outlineIconTextSpacing: CGFloat = 4
    static let outlineSelectionOpacity: CGFloat = 0.22
    static let tableSelectionOpacity: CGFloat = 0.22
    static let kindColorColumnWidth: CGFloat = 35
    static let kindSizeColumnWidth: CGFloat = 72
    static let kindFilesColumnWidth: CGFloat = 50
    static let kindSwatchWidth: CGFloat = 22
    static let kindSwatchHeight: CGFloat = 10
    static let kindSwatchCornerRadius: CGFloat = 1
    static let placeholderSpacing: CGFloat = 10
    static let placeholderPadding: CGFloat = 16
    static let placeholderPathLineLimit: Int = 3
    static let treemapIconSize: CGFloat = 48
    static let minimumRenderableTreemapSide: CGFloat = 2
    static let treemapSelectionLineWidth: CGFloat = 2
    static let singleLineLimit: Int = 1
    static let statusFieldSpacing: CGFloat = 2
    static let statusFieldFontSize: CGFloat = 11
    static let statusFieldHorizontalPadding: CGFloat = 17
    static let statusFieldBottomPadding: CGFloat = 12
}

private typealias Metrics = ScanWindowMetrics
