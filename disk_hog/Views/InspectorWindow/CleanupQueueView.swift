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
                List {
                    ForEach(groupedItems, id: \.volumeName) { group in
                        Section(group.volumeName) {
                            ForEach(group.items) { item in
                                CleanupQueueRow(item: item)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    CleanupQueueTotal(label: "Queued", items: store.items)
                    CleanupQueueTotal(label: "Selected", items: selectedItems)
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

                    Button("Move Selected to Finder Trash") {}
                        .disabled(true)
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
        }
        .padding(.vertical, 2)
    }
}

private struct CleanupQueueTotal: View {
    let label: LocalizedStringKey
    let items: [CleanupQueueItem]

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.semibold)
            Spacer()
            Text("\(items.count) items")
            Text(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))
                .monospacedDigit()
        }
    }

    private var totalBytes: UInt64 {
        items.reduce(0) { $0 + $1.allocatedSize }
    }
}
