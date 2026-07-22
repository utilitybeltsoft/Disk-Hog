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
            return session.isBuildingTreemap ? "Building treemap" : session.state.title
        }
    }

    private func scanTotalsView(referenceDate: Date) -> some View {
        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = Self.byteCountFormatter.string(
            fromByteCount: Int64(clamping: session.scannedByteCount)
        )
        return HStack(spacing: ScanWindowMetrics.statusProgressColumnSpacing) {
            countColumn(
                session.scannedItemCount,
                label: "items",
                width: ScanWindowMetrics.statusProgressItemColumnWidth
            )
            countColumn(
                session.scannedFolderCount,
                label: "folders",
                width: ScanWindowMetrics.statusProgressFolderColumnWidth
            )
            countColumn(
                session.scannedFileCount,
                label: "files",
                width: ScanWindowMetrics.statusProgressFileColumnWidth
            )
            progressColumn(
                scannedSize,
                width: ScanWindowMetrics.statusProgressSizeColumnWidth
            )
            progressColumn(
                "elapsed time \(elapsedTime)",
                width: ScanWindowMetrics.statusProgressElapsedColumnWidth
            )
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .textSelection(.enabled)
    }

    private func countColumn(_ count: Int, label: String, width: CGFloat) -> some View {
        HStack(spacing: ScanWindowMetrics.statusProgressLabelSpacing) {
            Text(Self.integerFormatter.string(from: NSNumber(value: count)) ?? String(count))
                .frame(width: ScanWindowMetrics.statusProgressNumberWidth, alignment: .trailing)
            Text(label)
        }
        .frame(width: width, alignment: .leading)
    }

    private func progressColumn(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(minWidth: width, alignment: .leading)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter: NumberFormatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesCount = true
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()
}
