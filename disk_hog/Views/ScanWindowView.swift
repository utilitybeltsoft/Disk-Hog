import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession

    init(source: ScanSource) {
        _session = StateObject(wrappedValue: ScanSession(source: source))
    }

    var body: some View {
        VStack(spacing: Metrics.windowContentSpacing) {
            VSplitView {
                HSplitView {
                    FilesPaneView(session: session)
                        .frame(minWidth: Metrics.filesPaneMinimumWidth, idealWidth: Metrics.filesPaneIdealWidth)

                    KindsPaneView(session: session)
                        .frame(minWidth: Metrics.kindsPaneMinimumWidth, idealWidth: Metrics.kindsPaneIdealWidth)
                }
                .frame(minHeight: Metrics.topPaneMinimumHeight, idealHeight: Metrics.topPaneIdealHeight)

                TreemapPanelView(session: session)
                    .frame(minWidth: Metrics.treemapMinimumWidth, minHeight: Metrics.treemapMinimumHeight)
            }
            .padding(.horizontal, Metrics.mainSplitHorizontalPadding)
            .padding(.top, Metrics.mainSplitTopPadding)

            ZStatusFieldsView(session: session)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ScanWindowRegistrationView(source: session.source))
        .onAppear {
            session.startScan()
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

private struct FilesPaneView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        VStack(spacing: 0) {
            TableHeaderRowView {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: Metrics.filesSizeColumnWidth, alignment: .trailing)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let rootItem: DiskItem = session.rootItem {
                        ForEach(rootItem.children) { child in
                            FileRowView(item: child)
                        }
                    } else {
                        FileScanPlaceholderRowsView(session: session)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct FileRowView: View {
    let item: DiskItem

    var body: some View {
        HStack(spacing: Metrics.tableColumnSpacing) {
            Text(item.displayName)
                .lineLimit(Metrics.singleLineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.allocatedSizeValue), countStyle: .file))
                .monospacedDigit()
                .frame(width: Metrics.filesSizeColumnWidth, alignment: .trailing)
        }
        .font(.system(size: Metrics.tableFontSize))
        .padding(.horizontal, Metrics.tableHorizontalPadding)
        .frame(height: Metrics.tableRowHeight)
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
    }

    private var kindStatistics: [KindStatistic] {
        guard let rootItem: DiskItem = session.rootItem else {
            return []
        }

        var statisticsByKind: [String: KindStatisticAccumulator] = [:]
        Self.collectKindStatistics(from: rootItem, into: &statisticsByKind)
        return statisticsByKind.map { key, accumulator in
            KindStatistic(kindName: key, size: accumulator.size, fileCount: accumulator.fileCount)
        }
        .sorted { first, second in
            if first.size != second.size {
                return first.size > second.size
            }

            return first.kindName.localizedStandardCompare(second.kindName) == .orderedAscending
        }
    }

    private static func collectKindStatistics(from item: DiskItem, into statisticsByKind: inout [String: KindStatisticAccumulator]) {
        if item.childCount > 0 {
            for child: DiskItem in item.children {
                collectKindStatistics(from: child, into: &statisticsByKind)
            }
            return
        }

        let kindName: String = item.kindName ?? (item.isFolder ? "folder" : "")
        guard !kindName.isEmpty else {
            return
        }

        var accumulator: KindStatisticAccumulator = statisticsByKind[kindName] ?? KindStatisticAccumulator()
        accumulator.size += item.allocatedSizeValue
        accumulator.fileCount += 1
        statisticsByKind[kindName] = accumulator
    }
}

private struct KindStatistic: Identifiable {
    let kindName: String
    let size: UInt64
    let fileCount: Int

    var id: String {
        kindName
    }
}

private struct KindStatisticAccumulator {
    var size: UInt64 = 0
    var fileCount: Int = 0
}

private struct KindStatisticRowView: View {
    let statistic: KindStatistic

    var body: some View {
        HStack(spacing: Metrics.tableColumnSpacing) {
            RoundedRectangle(cornerRadius: Metrics.kindSwatchCornerRadius)
                .fill(Color(nsColor: .systemBlue))
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
    @State private var renderedImage: NSImage?
    @State private var renderedRootID: ObjectIdentifier?
    @State private var renderedSize: CGSize = .zero

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
                renderIfNeeded(for: proxy.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func renderIfNeeded(for size: CGSize) {
        guard let rootItem: DiskItem = session.rootItem else {
            renderedImage = nil
            renderedRootID = nil
            renderedSize = .zero
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
        renderedImage = Self.renderImage(rootItem: rootItem, size: size)
    }

    private static func renderImage(rootItem: DiskItem, size: CGSize) -> NSImage? {
        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: rootItem)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(
            rootItem: dataSource.root,
            dataSource: dataSource,
            delegate: dataSource
        )
        let bounds: NSRect = NSRect(origin: .zero, size: size)
        renderer.reloadData()
        renderer.calcLayout(bounds)
        return renderer.drawInCache(size: size)?.treemapSuitableImage()
    }
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
        if let rootItem: DiskItem = session.rootItem {
            return rootItem.displayName
        }

        return session.currentPath
    }

    private func statusSize(referenceDate: Date) -> String {
        if let rootItem: DiskItem = session.rootItem {
            return ByteCountFormatter.string(fromByteCount: Int64(rootItem.allocatedSizeValue), countStyle: .file)
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
    static let singleLineLimit: Int = 1
    static let statusFieldSpacing: CGFloat = 2
    static let statusFieldFontSize: CGFloat = 11
    static let statusFieldHorizontalPadding: CGFloat = 17
    static let statusFieldBottomPadding: CGFloat = 12
}

private typealias Metrics = ScanWindowMetrics
