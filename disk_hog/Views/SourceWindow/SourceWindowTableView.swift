import AppKit
import SwiftUI

struct SourceTableView: View {
    let sources: [ScanSource]
    let selectedSourceID: ScanSource.ID?
    let onSelect: (ScanSource.ID?) -> Void
    let onOpen: (ScanSource) -> Void

    var body: some View {
        VStack(spacing: Metrics.tableSpacing) {
            SourceTableHeaderView()

            ScrollView {
                ZStack(alignment: .top) {
                    SourceBlankClickCatcherView {
                        onSelect(nil)
                    }
                    .frame(maxWidth: .infinity, minHeight: Metrics.volumeListHeight)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                            SourceTableRowView(
                                source: source,
                                isAlternateRow: index.isMultiple(of: 2) == false,
                                isSelected: selectedSourceID == source.id
                            )
                            .contentShape(Rectangle())
                            .overlay {
                                SourceRowClickCatcherView(
                                    onSingleClick: { onSelect(source.id) },
                                    onDoubleClick: {
                                        if source.canScan {
                                            onOpen(source)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.listCornerRadius))
            .frame(height: Metrics.volumeListHeight)
        }
    }
}

private struct SourceTableHeaderView: View {
    var body: some View {
        SourceTableColumns {
            Text("Volume")
                .frame(minWidth: Metrics.volumeColumnMinimumWidth, maxWidth: .infinity, alignment: .leading)
            Text("Capacity")
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
            Text("Used")
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
            Text("Free")
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
            Text("Free %")
                .frame(width: Metrics.percentColumnWidth, alignment: .trailing)
            Text("Usage")
                .frame(width: Metrics.usageColumnWidth, alignment: .leading)
        }
        .font(.system(size: Metrics.standardFontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.tableHorizontalPadding)
    }
}

@MainActor
private struct SourceTableRowView: View {
    let source: ScanSource
    let isAlternateRow: Bool
    let isSelected: Bool

    @State private var icon: NSImage

    init(source: ScanSource, isAlternateRow: Bool, isSelected: Bool) {
        self.source = source
        self.isAlternateRow = isAlternateRow
        self.isSelected = isSelected
        _icon = State(initialValue: SourceVolumeMetadata.resizedIcon(
            DiskItemIconCache.shared.cachedIcon(forFile: source.path)
        ))
    }

    var body: some View {
        SourceTableColumns {
            HStack(spacing: Metrics.sourceRowSpacing) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.sourceIconWidth)
                    .opacity(source.canScan ? 1 : 0.55)
                VStack(alignment: .leading, spacing: Metrics.sourceTextSpacing) {
                    HStack(spacing: 4) {
                        Text(source.displayName)
                            .font(.system(size: Metrics.standardFontSize))
                            .lineLimit(1)
                        if source.canScan == false {
                            Image(systemName: "lock.fill")
                                .font(.system(size: Metrics.standardFontSize - 1))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(metadata.subtitle)
                        .font(.system(size: Metrics.standardFontSize))
                        .foregroundStyle(source.canScan ? .secondary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: Metrics.volumeColumnMinimumWidth, maxWidth: .infinity, alignment: .leading)

            CapacityText(value: source.totalCapacity)
            CapacityText(value: metadata.usedCapacity)
            CapacityText(value: source.availableCapacity)

            Text(metadata.formattedFreePercent)
                .font(.system(size: Metrics.standardFontSize, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.percentColumnWidth, alignment: .trailing)

            VolumeUsageBarView(usedFraction: metadata.usedFraction)
                .frame(width: Metrics.usageColumnWidth)
        }
        .frame(height: Metrics.sourceRowHeight)
        .padding(.horizontal, Metrics.tableHorizontalPadding)
        .background(rowBackground)
        .help(source.canScan ? "" : metadata.accessHelp)
        .task(id: source.path) {
            icon = SourceVolumeMetadata.resizedIcon(
                await DiskItemIconCache.shared.loadIconAsync(forFile: source.path)
            )
        }
    }

    private var metadata: SourceVolumeMetadata {
        SourceVolumeMetadata(source: source)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(Metrics.selectionOpacity)
        }

        return isAlternateRow ? Color(nsColor: .alternatingContentBackgroundColors[1]) : Color(nsColor: .textBackgroundColor)
    }
}

private struct CapacityText: View {
    let value: UInt64?

    var body: some View {
        Text(SourceVolumeMetadata.formattedBytes(value))
            .font(.system(size: Metrics.standardFontSize, design: .monospaced))
            .monospacedDigit()
            .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
    }
}

private struct VolumeUsageBarView: View {
    let usedFraction: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * usedFraction)
            }
        }
        .frame(height: Metrics.usageBarHeight)
        .accessibilityLabel("\(Int((usedFraction * 100).rounded())) percent used")
    }
}

private struct SourceTableColumns<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Metrics.sourceColumnSpacing) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SourceVolumeMetadata {
    let source: ScanSource

    var subtitle: String {
        if let scanDisabledReason: String = source.scanDisabledReason {
            return scanDisabledReason
        }

        guard let volumeFormat: String = source.volumeFormat, !volumeFormat.isEmpty else {
            return source.path
        }

        return "\(volumeFormat) - \(source.path)"
    }

    var accessHelp: String {
        "Enable Disk Hog in System Settings > Privacy & Security > Full Disk Access, then relaunch Disk Hog."
    }

    /// The icon cache's instance is shared with other consumers (the outline, the
    /// selection list) that expect a different fixed size, so this resizes a copy
    /// rather than mutating the shared image in place. `image` is nil on a genuine
    /// cache miss (no synchronous fetch attempted, to avoid blocking the caller on
    /// a slow volume - a spun-down external drive, a network share), in which case
    /// this falls back to a generic placeholder pending the real icon.
    static func resizedIcon(_ image: NSImage?) -> NSImage {
        let base: NSImage = image
            ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
            ?? NSImage()
        let icon: NSImage = (base.copy() as? NSImage) ?? base
        icon.size = NSSize(width: Metrics.sourceIconWidth, height: Metrics.sourceIconWidth)
        return icon
    }

    var usedCapacity: UInt64? {
        guard let totalCapacity: UInt64 = source.totalCapacity,
              let availableCapacity: UInt64 = source.availableCapacity else {
            return nil
        }

        return totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }

    var usedFraction: CGFloat {
        guard let totalCapacity: UInt64 = source.totalCapacity,
              let usedCapacity,
              totalCapacity > 0 else {
            return 0
        }

        return CGFloat(usedCapacity) / CGFloat(totalCapacity)
    }

    var formattedFreePercent: String {
        guard let totalCapacity: UInt64 = source.totalCapacity,
              let availableCapacity: UInt64 = source.availableCapacity,
              totalCapacity > 0 else {
            return "--"
        }

        let freeFraction: Double = Double(availableCapacity) / Double(totalCapacity)
        return "\(Int((freeFraction * 100).rounded()))%"
    }

    static func formattedBytes(_ bytes: UInt64?) -> String {
        guard let bytes else {
            return "--"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private typealias Metrics = SourceWindowMetrics
