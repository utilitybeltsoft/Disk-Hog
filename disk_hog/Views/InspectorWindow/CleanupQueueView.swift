import AppKit
import SwiftUI

struct CleanupQueueView: View {
    @ObservedObject private var store: CleanupQueueStore = .shared
    @State private var isMoveConfirmationPresented: Bool = false

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
                        ForEach(Array(groupedItems.enumerated()), id: \.element.id) { index, group in
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
                    Text("Estimated reclaimable space can differ from actual free space because of APFS snapshots, clones, and filesystem sharing.")
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
                        isMoveConfirmationPresented = true
                    }
                    .disabled(store.selectedReadyItems.isEmpty)
                }
                .padding(14)
            }
        }
        .confirmationDialog(
            String(localized: "Move Selected to Finder Trash"),
            isPresented: $isMoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Move Selected to Finder Trash"), role: .destructive) {
                store.moveSelectedItemsToFinderTrash()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            VStack(alignment: .leading) {
                Text("Selected for Finder Trash")
                Text("\(selectedReadyItems.count) items")
                Text(selectedReadySizeDescription)
            }
        }
    }

    private var selectedItems: [CleanupQueueItem] {
        store.items.filter(\.isSelected)
    }

    private var selectedReadyItems: [CleanupQueueItem] {
        store.selectedReadyItems
    }

    private var selectedReadySizeDescription: String {
        CleanupQueueSizeFormatting.total(of: selectedReadyItems)
    }

    private var groupedItems: [CleanupQueueVolumeGroup] {
        Dictionary(grouping: store.items, by: \.source)
            .map { CleanupQueueVolumeGroup(source: $0.key, items: $0.value) }
            .sorted {
                let nameOrder: ComparisonResult = $0.volumeName.localizedStandardCompare($1.volumeName)
                return nameOrder == .orderedSame
                    ? $0.source.id < $1.source.id
                    : nameOrder == .orderedAscending
            }
    }
}

private struct CleanupQueueVolumeGroup: Identifiable {
    let source: ScanSource
    let items: [CleanupQueueItem]

    var id: String { source.id }
    var volumeName: String { source.displayName }
}

@MainActor
private struct CleanupQueueRow: View {
    let item: CleanupQueueItem
    @ObservedObject private var store: CleanupQueueStore = .shared
    @State private var icon: NSImage

    init(item: CleanupQueueItem) {
        self.item = item
        _icon = State(initialValue: CleanupQueueRow.resizedIcon(
            DiskItemIconCache.shared.cachedIcon(forFile: item.itemURL.path)
        ))
    }

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

            Image(nsImage: icon)
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

            Text(CleanupQueueSizeFormatting.size(of: item))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(statusTitle)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .task(id: item.itemURL.path) {
            icon = CleanupQueueRow.resizedIcon(
                await DiskItemIconCache.shared.loadIconAsync(forFile: item.itemURL.path)
            )
        }
    }

    private static func resizedIcon(_ image: NSImage?) -> NSImage {
        let base: NSImage = image
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            ?? NSImage()
        let icon: NSImage = (base.copy() as? NSImage) ?? base
        icon.size = NSSize(width: 20, height: 20)
        return icon
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

            CleanupQueueVolumeTotals(items: items)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            ForEach(items) { item in
                CleanupQueueRow(item: item)
            }
        }
    }
}

private struct CleanupQueueVolumeTotals: View {
    let items: [CleanupQueueItem]

    var body: some View {
        HStack {
            Text("Selected for Finder Trash")
                .fontWeight(.semibold)
            Spacer()
            Text("\(selectedItems.count) items")
            Text(CleanupQueueSizeFormatting.total(of: selectedItems))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var selectedItems: [CleanupQueueItem] {
        items.filter(\.isSelected)
    }
}

/// Shows "?" instead of a formatted byte count for a queued item (or a total that
/// includes one) whose real size is unknown - the scanner's placeholder 0 would
/// otherwise misleadingly read as a verified, empty size.
private enum CleanupQueueSizeFormatting {
    static func size(of item: CleanupQueueItem) -> String {
        item.isSizeUnknown
            ? "?"
            : ByteCountFormatter.string(fromByteCount: Int64(item.allocatedSize), countStyle: .file)
    }

    static func total(of items: [CleanupQueueItem]) -> String {
        guard items.allSatisfy({ !$0.isSizeUnknown }) else {
            return "?"
        }
        return ByteCountFormatter.string(
            fromByteCount: Int64(items.reduce(0) { $0 + $1.allocatedSize }),
            countStyle: .file
        )
    }
}
