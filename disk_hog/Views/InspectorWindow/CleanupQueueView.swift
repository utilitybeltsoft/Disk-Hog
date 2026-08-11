import AppKit
import SwiftUI

struct CleanupQueueView: View {
    @ObservedObject private var store: CleanupQueueStore = .shared

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "Cleanup Queue Is Empty",
                    systemImage: "trash",
                    description: Text("Add files or folders from a scan window to review them before moving them to Finder Trash."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(groupedItems.enumerated()), id: \.element.volumeName) { index, group in
                            CleanupQueueVolumeSection(
                                volumeName: group.volumeName,
                                items: group.items,
                                showsTopSeparator: index > 0
                            )
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Space reclaimed is an estimate. APFS snapshots, clones, and filesystem sharing can affect the actual free space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)

                Divider()

                HStack {
                    Button("Remove Selected from Queue") {
                        store.remove(ids: Set(selectedItems.map(\.id)))
                    }
                    .disabled(selectedItems.isEmpty)

                    Button("Remove All from Queue", role: .destructive) {
                        store.removeAll()
                    }

                    Spacer()

                    Button("Move Selected to Finder Trash") {
                        store.moveSelectedItemsToFinderTrash()
                    }
                    .disabled(store.selectedReadyItems.isEmpty)
                }
                .padding(14)
            }
        }
    }

    private var selectedItems: [CleanupQueueItem] {
        store.items.filter(\.isSelected)
    }

    private var groupedItems: [(volumeName: String, items: [CleanupQueueItem])] {
        Dictionary(grouping: store.items, by: \.volumeName)
            .map { (volumeName: $0.key, items: $0.value) }
            .sorted { $0.volumeName.localizedStandardCompare($1.volumeName) == .orderedAscending }
    }
}

private struct CleanupQueueRow: View {
    let item: CleanupQueueItem
    @ObservedObject private var store: CleanupQueueStore = .shared

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { item.isSelected },
                    set: { store.setSelected($0, for: item.id) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.itemURL.path))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(item.parentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(ByteCountFormatter.string(fromByteCount: Int64(item.allocatedSize), countStyle: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(statusTitle)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var statusTitle: String {
        switch item.status {
        case .ready: String(localized: "Ready")
        case .missing: String(localized: "Missing")
        case .inaccessible: String(localized: "Unavailable")
        case .cannotMoveToTrash: String(localized: "Cannot Move to Finder Trash")
        case .processing: String(localized: "Moving")
        case .failed: String(localized: "Failed")
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready: .secondary
        case .processing: .accentColor
        case .missing, .inaccessible, .cannotMoveToTrash, .failed: .red
        }
    }
}

private struct CleanupQueueVolumeSection: View {
    let volumeName: String
    let items: [CleanupQueueItem]
    let showsTopSeparator: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsTopSeparator {
                Divider()
                    .padding(.top, 10)
            }

            Text(volumeName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, showsTopSeparator ? 8 : 12)
                .padding(.bottom, 4)

            ForEach(items) { item in
                CleanupQueueRow(item: item)
            }

            CleanupQueueVolumeTotals(items: items)
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 10)
        }
    }
}

private struct CleanupQueueVolumeTotals: View {
    let items: [CleanupQueueItem]

    var body: some View {
        HStack(spacing: 12) {
            CleanupQueueTotal(label: "Queued", items: items, compact: true)
            Divider()
                .frame(height: 14)
            CleanupQueueTotal(label: "Selected", items: items.filter(\.isSelected), compact: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CleanupQueueTotal: View {
    let label: LocalizedStringKey
    let items: [CleanupQueueItem]
    var compact: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.semibold)
            if !compact {
                Spacer()
            }
            Text("\(items.count) items")
            Text(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))
                .monospacedDigit()
        }
    }

    private var totalBytes: UInt64 {
        items.reduce(0) { $0 + $1.allocatedSize }
    }
}
