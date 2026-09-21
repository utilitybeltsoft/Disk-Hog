import AppKit
import SwiftUI

struct ScanIssuesView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        if session.skippedItems.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.skippedItems) { skippedItem in
                            ScanIssueRow(skippedItem: skippedItem)
                            Divider()
                        }
                    }
                }
                Divider()
                HStack {
                    Text("\(session.skippedItems.count) items could not be scanned. Totals shown elsewhere may be understated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch session.state {
        case .ready:
            ContentUnavailableView(
                "Scan Not Started",
                systemImage: "clock",
                description: Text("Scan issues will be available after this scan finishes.")
            )
        case .scanning:
            ContentUnavailableView(
                "Scan in Progress",
                systemImage: "magnifyingglass",
                description: Text("Scan issues will be available after this scan finishes. An empty list does not yet mean every item was scanned successfully.")
            )
        case .cancelled:
            ContentUnavailableView(
                "Scan Cancelled",
                systemImage: "xmark.circle",
                description: Text("This scan did not finish, so a complete scan issues report is unavailable.")
            )
        case .failed:
            ContentUnavailableView(
                "Scan Failed",
                systemImage: "exclamationmark.triangle",
                description: Text("This scan failed before a complete scan issues report was available.")
            )
        case .complete:
            ContentUnavailableView(
                "No Scan Issues",
                systemImage: "checkmark.circle",
                description: Text("Every item Disk Hog could reach was scanned successfully.")
            )
        }
    }
}

private struct ScanIssueRow: View {
    let skippedItem: ScanSkippedItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(skippedItem.path)
                    .font(.system(size: NSFont.smallSystemFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(skippedItem.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
