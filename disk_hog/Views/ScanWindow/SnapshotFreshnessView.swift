import SwiftUI

struct SnapshotFreshnessView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status).fixedSize(horizontal: false, vertical: true)
                Text("Not updated automatically")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(details)
            .accessibilityElement(children: .combine)
            .accessibilityHint(details)
            Button {
                session.refreshSnapshot()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .fixedSize()
            .disabled(!session.canRefreshSnapshot)
            .help("Rescan this window’s entire folder or volume, regardless of selection or zoom. Current results are cleared while scanning.")
        }
        .controlSize(.small)
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
        .padding(.horizontal, ScanWindowMetrics.mainSplitHorizontalPadding)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var status: String {
        let whole = session.snapshotFreshness.wholeScan
        if session.state == .scanning {
            return whole == nil ? String(localized: "Scanning…") : String(localized: "Refreshing…")
        }
        let prior: String = whole.map { String(localized: "Last scanned: \(date($0.finishedAt))") }
            ?? String(localized: "No completed scan")
        if session.state == .cancelled { return String(localized: "Scan cancelled · \(prior)") }
        if session.state == .failed { return String(localized: "Scan failed · \(prior)") }
        if session.isUpdatingTree { return String(localized: "Updating scan data… · \(prior)") }
        if session.failure != nil { return String(localized: "Last operation failed · \(prior)") }
        if session.snapshotFreshness.latestPartialRefresh != nil {
            return String(localized: "\(prior) · Some items refreshed later")
        }
        return prior
    }

    private var details: String {
        var lines = [String(localized: "Disk Hog displays a snapshot, not a live view of the disk.")]
        if let scan = session.snapshotFreshness.wholeScan {
            lines.append(String(localized: "Whole scan: \(date(scan.startedAt)) – \(date(scan.finishedAt))."))
            if scan.hasSkippedItems { lines.append(String(localized: "That scan had skipped items.")) }
        }
        if let partial = session.snapshotFreshness.latestPartialRefresh {
            lines.append(String(localized: "Latest partial refresh: \(partial.path)"))
            lines.append("\(date(partial.acquisition.startedAt)) – \(date(partial.acquisition.finishedAt))")
            if partial.acquisition.hasSkippedItems { lines.append(String(localized: "That refresh had skipped items.")) }
        }
        if session.rootItem == nil, session.snapshotFreshness.wholeScan != nil {
            lines.append(String(localized: "The previous results are no longer displayed; the timestamp describes the last completed scan."))
        }
        lines.append(String(localized: "Files are read over the scan interval, not all at one instant. Changes made afterward are not monitored."))
        return lines.joined(separator: "\n")
    }

    private func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .standard)
    }
}
