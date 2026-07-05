import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession
    @State private var selectedItem: DiskItem?

    init(source: ScanSource) {
        _session = StateObject(wrappedValue: ScanSession(source: source))
    }

    var body: some View {
        VStack(spacing: Metrics.windowContentSpacing) {
            VSplitView {
                HSplitView {
                    FilesPaneView(session: session)
                        .environment(\.selectedScanItem, $selectedItem)
                        .frame(minWidth: Metrics.filesPaneMinimumWidth, idealWidth: Metrics.filesPaneIdealWidth)

                    KindsPaneView(session: session)
                        .frame(minWidth: Metrics.kindsPaneMinimumWidth, idealWidth: Metrics.kindsPaneIdealWidth)
                }
                .frame(minHeight: Metrics.topPaneMinimumHeight, idealHeight: Metrics.topPaneIdealHeight)

                TreemapPanelView(session: session)
                    .environment(\.selectedScanItem, $selectedItem)
                    .frame(minWidth: Metrics.treemapMinimumWidth, minHeight: Metrics.treemapMinimumHeight)
            }
            .padding(.horizontal, Metrics.mainSplitHorizontalPadding)
            .padding(.top, Metrics.mainSplitTopPadding)

            ZStatusFieldsView(session: session)
                .environment(\.selectedScanItem, $selectedItem)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ScanWindowRegistrationView(source: session.source))
        .onAppear {
            session.startScan()
        }
        .onChange(of: session.rootItem?.id) {
            selectedItem = session.rootItem
        }
        #if FILE_MATCHING_DIAGNOSTICS
        .onAppear {
            updateScanWindowCommandState()
        }
        .onChange(of: session.rootItem?.id) {
            updateScanWindowCommandState()
        }
        .onChange(of: session.diagnosticsExportState) {
            updateScanWindowCommandState()
        }
        #endif
    }

    #if FILE_MATCHING_DIAGNOSTICS
    private func updateScanWindowCommandState() {
        ScanWindowCommandState.shared.activate(session: session)
    }
    #endif
}

private struct SelectedScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private extension EnvironmentValues {
    var selectedScanItem: Binding<DiskItem?> {
        get { self[SelectedScanItemKey.self] }
        set { self[SelectedScanItemKey.self] = newValue }
    }
}

private struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @State private var expandedItemIDs: Set<ObjectIdentifier> = []

    var body: some View {
        VStack(spacing: 0) {
            TableHeaderRowView {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: Metrics.filesSizeColumnWidth, alignment: .trailing)
            }

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 0) {
                        if let rootItem: DiskItem = session.rootItem {
                            FileTreeRowView(
                                item: rootItem,
                                depth: 0,
                                expandedItemIDs: $expandedItemIDs
                            )
                        } else {
                            FileScanPlaceholderRowsView(session: session)
                        }
                    }
                    .onChange(of: selectedItem.wrappedValue?.id) {
                        guard let item: DiskItem = selectedItem.wrappedValue else {
                            return
                        }

                        expandAncestors(of: item)
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    .onChange(of: session.rootItem?.id) {
                        guard let rootItem: DiskItem = session.rootItem else {
                            expandedItemIDs.removeAll()
                            return
                        }

                        expandedItemIDs.insert(rootItem.id)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func expandAncestors(of item: DiskItem) {
        var ancestor: DiskItem? = item.parent
        while let currentAncestor: DiskItem = ancestor {
            expandedItemIDs.insert(currentAncestor.id)
            ancestor = currentAncestor.parent
        }
    }
}

private struct FileTreeRowView: View {
    let item: DiskItem
    let depth: Int
    @Binding var expandedItemIDs: Set<ObjectIdentifier>
    @Environment(\.selectedScanItem) private var selectedItem

    private var isExpanded: Bool {
        expandedItemIDs.contains(item.id)
    }

    private var isSelected: Bool {
        selectedItem.wrappedValue === item
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.tableColumnSpacing) {
                HStack(spacing: Metrics.outlineDisclosureSpacing) {
                    Color.clear
                        .frame(width: CGFloat(depth) * Metrics.outlineIndentWidth)
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: Metrics.outlineDisclosureIconSize, weight: .medium))
                            .frame(width: Metrics.outlineDisclosureWidth)
                            .opacity(item.isFolder ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isFolder == false)

                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Metrics.outlineIconWidth, height: Metrics.outlineIconWidth)

                    Text(item.displayName)
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(ByteCountFormatter.string(fromByteCount: Int64(item.allocatedSizeValue), countStyle: .file))
                    .monospacedDigit()
                    .frame(width: Metrics.filesSizeColumnWidth, alignment: .trailing)
            }
            .font(.system(size: Metrics.tableFontSize))
            .padding(.horizontal, Metrics.tableHorizontalPadding)
            .frame(height: Metrics.tableRowHeight)
            .background(isSelected ? Color.accentColor.opacity(Metrics.outlineSelectionOpacity) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedItem.wrappedValue = item
            }
            .id(item.id)

            if isExpanded {
                ForEach(item.children) { child in
                    FileTreeRowView(
                        item: child,
                        depth: depth + 1,
                        expandedItemIDs: $expandedItemIDs
                    )
                }
            }
        }
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedItemIDs.remove(item.id)
        } else {
            expandedItemIDs.insert(item.id)
        }
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
    @State private var kindStatistics: [TreemapKindStatistic] = []

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
                LazyVStack(spacing: 0) {
                    ForEach(kindStatistics) { statistic in
                        KindStatisticRowView(statistic: statistic)
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
    }

    private func updateKindStatistics() {
        guard let rootItem: DiskItem = session.rootItem else {
            kindStatistics = []
            return
        }

        kindStatistics = TreemapDiskItemDataSource.kindStatistics(for: rootItem)
    }
}

private struct KindStatisticRowView: View {
    let statistic: TreemapKindStatistic

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
    @State private var renderedImage: NSImage?
    @State private var renderedRootID: ObjectIdentifier?
    @State private var renderedSize: CGSize = .zero
    @State private var renderer: TreemapViewRenderer?
    @State private var rendererDataSource: TreemapDiskItemDataSource?
    @State private var selectedItemRect: NSRect = .zero

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
                            y: proxy.size.height - selectedItemRect.midY
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
        let rendererPoint: NSPoint = NSPoint(x: location.x, y: size.height - location.y)
        guard let cellID: TreemapCellID = renderer?.cellID(by: rendererPoint, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID) as? DiskItem,
              !item.isSpecialItem else {
            return
        }

        selectedItem.wrappedValue = item
        selectedItemRect = renderer?.itemRect(by: cellID) ?? .zero
    }

    private func updateSelectedRect() {
        guard let item: DiskItem = selectedItem.wrappedValue,
              let rootItem: DiskItem = session.rootItem,
              itemIsInTree(item, root: rootItem) else {
            selectedItemRect = .zero
            return
        }

        let path: [AnyObject] = item.pathFromRoot().map { $0 as AnyObject }
        renderer?.selectItem(byPathToItem: path)
        selectedItemRect = renderer?.itemRect(byPathToItem: path) ?? .zero
    }

    private func itemIsInTree(_ item: DiskItem, root: DiskItem) -> Bool {
        item.pathFromRoot().first === root
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
        if let selectedItem: DiskItem = selectedItem.wrappedValue {
            if selectedItem.isRoot {
                return selectedItem.displayName
            }

            return "\(selectedItem.displayName) (\(selectedItem.displayFolderName))"
        }

        return session.currentPath
    }

    private func statusSize(referenceDate: Date) -> String {
        if let selectedItem: DiskItem = selectedItem.wrappedValue {
            let size: String = ByteCountFormatter.string(fromByteCount: Int64(selectedItem.allocatedSizeValue), countStyle: .file)
            guard !selectedItem.isFolder, let kindName: String = selectedItem.kindName else {
                return size
            }

            return "\(kindName), \(size)"
        }

        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = ByteCountFormatter.string(fromByteCount: Int64(session.scannedByteCount), countStyle: .file)
        return "\(session.state.title) - \(session.scannedItemCount) items - \(scannedSize) - elapsed \(elapsedTime)"
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
    static let outlineIndentWidth: CGFloat = 16
    static let outlineDisclosureSpacing: CGFloat = 2
    static let outlineDisclosureWidth: CGFloat = 12
    static let outlineDisclosureIconSize: CGFloat = 9
    static let outlineIconWidth: CGFloat = 16
    static let outlineSelectionOpacity: CGFloat = 0.22
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
