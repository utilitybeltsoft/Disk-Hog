import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession

    init(source: ScanSource) {
        _session = StateObject(wrappedValue: ScanSession(source: source))
    }

    var body: some View {
        VStack(spacing: Metrics.outerSpacing) {
            ScanToolbarView(session: session)

            Divider()

            HSplitView {
                OutlinePlaceholderView()
                    .frame(minWidth: Metrics.sidebarMinimumWidth, idealWidth: Metrics.sidebarIdealWidth)

                TreemapPlaceholderView(source: session.source)
                    .frame(minWidth: Metrics.treemapMinimumWidth, minHeight: Metrics.treemapMinimumHeight)

                InspectorPlaceholderView(session: session)
                    .frame(minWidth: Metrics.inspectorMinimumWidth, idealWidth: Metrics.inspectorIdealWidth)
            }
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ScanToolbarView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack(spacing: Metrics.toolbarSpacing) {
            VStack(alignment: .leading, spacing: Metrics.toolbarTextSpacing) {
                Text(session.source.displayName)
                    .font(.headline)
                    .lineLimit(Metrics.singleLineLimit)
                Text(session.source.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(Metrics.singleLineLimit)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            TimelineView(.periodic(from: Date(), by: Metrics.timerRefreshInterval)) { context in
                Text("Elapsed \(DurationFormatter.scanDuration(session.elapsedTime(referenceDate: context.date)))")
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: Metrics.elapsedWidth, alignment: .leading)
            }

            Text(session.state.title)
                .font(.callout.weight(.medium))
                .frame(width: Metrics.stateWidth, alignment: .leading)

            Button {
                if session.state == .scanning {
                    session.cancel()
                } else {
                    session.startPlaceholderScan()
                }
            } label: {
                Label(session.state == .scanning ? "Cancel" : "Start Scan", systemImage: session.state == .scanning ? "xmark.circle" : "play.circle")
            }
            .keyboardShortcut(".", modifiers: .command)
        }
        .padding(.horizontal, Metrics.toolbarHorizontalPadding)
        .padding(.vertical, Metrics.toolbarVerticalPadding)
    }
}

private struct OutlinePlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.placeholderSpacing) {
            Label("Files", systemImage: "list.bullet.indent")
                .font(.headline)
            Text("The DiskItem outline will appear after the Z-style scanner is implemented.")
                .foregroundStyle(.secondary)
        }
        .padding(Metrics.placeholderPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct TreemapPlaceholderView: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct InspectorPlaceholderView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.placeholderSpacing) {
            Label("Inspector", systemImage: "info.circle")
                .font(.headline)
            Text("Selected item details will be loaded lazily.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Items: \(session.scannedItemCount)")
            Text("Files: \(session.scannedFileCount)")
            Text("Folders: \(session.scannedFolderCount)")
        }
        .padding(Metrics.placeholderPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private enum ScanWindowMetrics {
    static let outerSpacing: CGFloat = 0
    static let toolbarSpacing: CGFloat = 14
    static let toolbarTextSpacing: CGFloat = 2
    static let toolbarHorizontalPadding: CGFloat = 14
    static let toolbarVerticalPadding: CGFloat = 10
    static let timerRefreshInterval: TimeInterval = 1
    static let elapsedWidth: CGFloat = 104
    static let stateWidth: CGFloat = 74
    static let sidebarMinimumWidth: CGFloat = 250
    static let sidebarIdealWidth: CGFloat = 300
    static let treemapMinimumWidth: CGFloat = 620
    static let treemapMinimumHeight: CGFloat = 460
    static let inspectorMinimumWidth: CGFloat = 260
    static let inspectorIdealWidth: CGFloat = 300
    static let windowMinimumWidth: CGFloat = 1180
    static let windowMinimumHeight: CGFloat = 720
    static let placeholderSpacing: CGFloat = 10
    static let placeholderPadding: CGFloat = 16
    static let treemapIconSize: CGFloat = 48
    static let singleLineLimit: Int = 1
}

private typealias Metrics = ScanWindowMetrics
