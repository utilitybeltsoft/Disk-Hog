import SwiftUI

struct ZStatusFieldsView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem

    var body: some View {
        ZStatusTimelineView(
            isTicking: statusNeedsPeriodicUpdates,
            content: statusBody(referenceDate:)
        )
    }

    private var statusNeedsPeriodicUpdates: Bool {
        ZStatusTimelinePolicy.isTicking(
            state: session.state,
            isBuildingTreemap: session.isBuildingTreemap
        )
    }

    private func statusBody(referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: ScanWindowMetrics.statusFieldControlSpacing) {
            VStack(alignment: .leading, spacing: ScanWindowMetrics.statusFieldSpacing) {
                Text(selectedStatusLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(secondaryStatusLine ?? String(localized: "Hovering on:"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(secondaryStatusLine == nil ? 0 : 1)
                    .accessibilityHidden(secondaryStatusLine == nil)
                    .textSelection(.enabled)
                Text(progressSummary(referenceDate: referenceDate))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                scanTotalsView(referenceDate: referenceDate)
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

    private var selectedStatusLine: String {
        if let selectedItem: DiskItem = selectedItem.wrappedValue {
            return statusLine(prefix: String(localized: "Selected"), item: selectedItem)
        }

        return session.currentPath
    }

    private var hoverStatusLine: String? {
        if let hoveredItem: DiskItem = hoveredItem.wrappedValue {
            return statusLine(prefix: String(localized: "Hovering on"), item: hoveredItem)
        }

        return nil
    }

    private var secondaryStatusLine: String? {
        if let hoverStatusLine {
            return hoverStatusLine
        }

        guard let selectedItem: DiskItem = selectedItem.wrappedValue,
              selectedItem.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize) == 0 else {
            return nil
        }

        if session.isAffectedBySkippedContent(selectedItem) {
            return String(localized: "Not shown in treemap: this item's size could not be determined because of insufficient permissions.")
        }

        if session.scanSettings.usePhysicalSize {
            return String(localized: "Not shown in treemap: this item's physical file size is 0 bytes.")
        }
        return String(localized: "Not shown in treemap: this item's logical file size is 0 bytes.")
    }

    private func statusLine(prefix: String, item: DiskItem) -> String {
        let size: String = formattedSize(for: item)
        if let kindName: String = item.kindName, !kindName.isEmpty {
            return String(localized: "\(prefix): \(item.path), \(kindName), \(size)")
        }

        return String(localized: "\(prefix): \(item.path), \(size)")
    }

    /// Shows "?" rather than a formatted byte count when the item's true size is
    /// unknown (scanning it or something inside it failed) - "0 bytes" would
    /// misleadingly claim a verified, empty size instead.
    private func formattedSize(for item: DiskItem) -> String {
        if session.isAffectedBySkippedContent(item) {
            return "?"
        }
        return ByteCountFormatter.string(
            fromByteCount: Int64(item.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize)),
            countStyle: .file
        )
    }

    private func progressSummary(referenceDate: Date) -> String {
        if session.isBuildingTreemap {
            return preparingTreemapStatus(referenceDate: referenceDate)
        }

        switch session.state {
        case .complete:
            if let completedAt: Date = session.completedAt {
                return String(localized: "Scan complete at \(Self.dateTimeFormatter.string(from: completedAt))")
            }

            return String(localized: "Scan complete")
        case .failed:
            return session.failure?.statusMessage ?? String(localized: "Scan failed")
        case .ready, .scanning, .cancelled:
            if session.state == .scanning, case .packagingScanResults = session.scanStage {
                return scanStatus
            }
            return session.state == .scanning
                ? animatedActivityStatus(scanStatus, referenceDate: referenceDate)
                : scanStatus
        }
    }

    private var scanStatus: String {
        guard session.state == .scanning else {
            return session.state.title
        }

        switch session.scanStage {
        case .enumeratingRootItems:
            return String(localized: "Enumerating root items…")
        case .scanningFiles:
            return String(localized: "Scanning files…")
        case .packagingScanResults(let percent):
            return String(localized: "Packaging scan results: \(percent)%")
        case .finalizingScan:
            return String(localized: "Finalizing scan…")
        }
    }

    private func preparingTreemapStatus(referenceDate: Date) -> String {
        if let progress: Double = session.treemapPreparationProgress {
            let percentage: Int = Int((progress * 100).rounded(.down))
            return String(localized: "Preparing treemap: \(percentage)%")
        }

        return animatedActivityStatus(String(localized: "Rendering treemap…"), referenceDate: referenceDate)
    }

    /// Reuse the status timeline's one-second tick for indeterminate activity.
    /// This indicates that the UI is responsive; it does not measure worker progress.
    private func animatedActivityStatus(_ status: String, referenceDate: Date) -> String {
        let dotCount: Int = Int(floor(referenceDate.timeIntervalSince1970).truncatingRemainder(dividingBy: 3)) + 1
        let label: String = status.hasSuffix("…") ? String(status.dropLast()) : status
        return label + String(repeating: ".", count: dotCount)
    }

    private func scanTotalsView(referenceDate: Date) -> some View {
        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = Self.byteCountFormatter.string(
            fromByteCount: Int64(clamping: session.scannedByteCount)
        )
        return HStack(spacing: ScanWindowMetrics.statusProgressColumnSpacing) {
            countField(
                String(localized: "items"),
                count: session.scannedItemCount,
                width: ScanWindowMetrics.statusProgressItemColumnWidth
            )
            countField(
                String(localized: "folders"),
                count: session.scannedFolderCount,
                width: ScanWindowMetrics.statusProgressFolderColumnWidth
            )
            countField(
                String(localized: "files"),
                count: session.scannedFileCount,
                width: ScanWindowMetrics.statusProgressFileColumnWidth
            )
            progressColumn(
                scannedSize,
                width: ScanWindowMetrics.statusProgressSizeColumnWidth
            )
            progressColumn(
                String(localized: "elapsed time \(elapsedTime)"),
                width: ScanWindowMetrics.statusProgressElapsedColumnWidth
            )
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .textSelection(.enabled)
    }

    private func countField(_ label: String, count: Int, width: CGFloat) -> some View {
        let formattedCount: String = Self.integerFormatter.string(from: NSNumber(value: count)) ?? String(count)
        return Text(String(localized: "\(label): \(formattedCount)"))
            .monospacedDigit()
            .frame(minWidth: width, alignment: .leading)
    }

    private func progressColumn(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
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

enum ZStatusTimelinePolicy {
    static func isTicking(state: ScanSessionState, isBuildingTreemap: Bool) -> Bool {
        state == .scanning || isBuildingTreemap
    }
}

struct ZStatusTimelineView<Content: View>: View {
    let isTicking: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isTicking {
            TimelineView(.periodic(from: Date(), by: ScanWindowMetrics.timerRefreshInterval)) { context in
                content(context.date)
            }
        } else {
            content(Date())
        }
    }
}
