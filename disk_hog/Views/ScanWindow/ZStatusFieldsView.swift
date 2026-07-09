import SwiftUI

struct ZStatusFieldsView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem

    var body: some View {
        TimelineView(.periodic(from: Date(), by: ScanWindowMetrics.timerRefreshInterval)) { context in
            HStack(alignment: .top, spacing: ScanWindowMetrics.statusFieldControlSpacing) {
                VStack(alignment: .leading, spacing: ScanWindowMetrics.statusFieldSpacing) {
                    Text(selectedStatusLine)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let hoverStatusLine: String = hoverStatusLine {
                        Text(hoverStatusLine)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text(progressSummary(referenceDate: context.date))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    scanTotalsView(referenceDate: context.date)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if session.state == .scanning {
                    Button {
                        session.cancel()
                    } label: {
                        Label("Cancel Scan", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                    .help("Cancel Scan")
                }
            }
            .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
            .padding(.horizontal, ScanWindowMetrics.statusFieldHorizontalPadding)
            .padding(.bottom, ScanWindowMetrics.statusFieldBottomPadding)
            .frame(height: ScanWindowMetrics.statusFieldHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedStatusLine: String {
        if let selectedItem: DiskItem = selectedItem.wrappedValue {
            return statusLine(prefix: "Selected", item: selectedItem)
        }

        return session.currentPath
    }

    private var hoverStatusLine: String? {
        if let hoveredItem: DiskItem = hoveredItem.wrappedValue {
            return statusLine(prefix: "Hovering on", item: hoveredItem)
        }

        return nil
    }

    private func statusLine(prefix: String, item: DiskItem) -> String {
        let size: String = ByteCountFormatter.string(
            fromByteCount: Int64(item.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize)),
            countStyle: .file
        )
        if let kindName: String = item.kindName, !kindName.isEmpty {
            return "\(prefix): \(item.path), \(kindName), \(size)"
        }

        return "\(prefix): \(item.path), \(size)"
    }

    private func progressSummary(referenceDate: Date) -> String {
        switch session.state {
        case .complete:
            if let completedAt: Date = session.completedAt {
                return "Scan complete at \(Self.dateTimeFormatter.string(from: completedAt))"
            }

            return "Scan complete"
        case .ready, .scanning, .cancelled, .failed:
            return session.state.title
        }
    }

    private func scanTotalsView(referenceDate: Date) -> some View {
        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = ByteCountFormatter.string(fromByteCount: Int64(session.scannedByteCount), countStyle: .file)
        return HStack(spacing: ScanWindowMetrics.statusProgressColumnSpacing) {
            progressColumn(
                "\(session.scannedItemCount) items",
                width: ScanWindowMetrics.statusProgressItemColumnWidth
            )
            progressColumn(
                "\(session.scannedFolderCount) folders",
                width: ScanWindowMetrics.statusProgressFolderColumnWidth
            )
            progressColumn(
                "\(session.scannedFileCount) files",
                width: ScanWindowMetrics.statusProgressFileColumnWidth
            )
            progressColumn(
                scannedSize,
                width: ScanWindowMetrics.statusProgressSizeColumnWidth
            )
            progressColumn(
                "elapsed \(elapsedTime)",
                width: ScanWindowMetrics.statusProgressElapsedColumnWidth
            )
        }
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize, design: .monospaced))
        .lineLimit(1)
        .textSelection(.enabled)
    }

    private func progressColumn(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(width: width, alignment: .trailing)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
