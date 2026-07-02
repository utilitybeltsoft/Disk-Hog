import AppKit
import SwiftUI

struct SourcePaletteView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var sources: [ScanSource] = ScanSourceProvider.mountedVolumes()
    @State private var selectedSourceID: ScanSource.ID?
    @State private var showExternalVolumes: Bool = true
    @State private var showNetworkVolumes: Bool = true
    @State private var showDiskImages: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            Text("Choose a disk or folder to scan.")
                .font(.headline)
                .padding(.horizontal, Metrics.windowPadding)
                .padding(.top, Metrics.windowPadding)

            VolumeFilterView(
                showExternalVolumes: $showExternalVolumes,
                showNetworkVolumes: $showNetworkVolumes,
                showDiskImages: $showDiskImages
            )
            .padding(.horizontal, Metrics.windowPadding)

            VStack(spacing: Metrics.tableSpacing) {
                SourceTableHeaderView()

                List(selection: $selectedSourceID) {
                    ForEach(filteredSources) { source in
                        SourceTableRowView(source: source)
                            .tag(source.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSourceID = source.id
                            }
                            .onTapGesture(count: Metrics.doubleClickCount) {
                                openSource(source)
                            }
                    }
                }
                .alternatingRowBackgrounds()
            }
            .frame(minHeight: Metrics.volumeListMinimumHeight)
            .padding(.horizontal, Metrics.windowPadding)

            HStack(spacing: Metrics.buttonSpacing) {
                Button {
                    if let selectedSource: ScanSource = selectedSource {
                        openSource(selectedSource)
                    }
                } label: {
                    Label("Scan", systemImage: "play.circle")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedSource == nil)

                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder...", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    refreshSources()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()
            }
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.bottom, Metrics.windowPadding)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .onAppear {
            seedSelectionIfNeeded()
        }
        .onChange(of: showExternalVolumes) {
            reconcileSelectionWithVisibleSources()
        }
        .onChange(of: showNetworkVolumes) {
            reconcileSelectionWithVisibleSources()
        }
        .onChange(of: showDiskImages) {
            reconcileSelectionWithVisibleSources()
        }
    }

    private var filteredSources: [ScanSource] {
        sources.filter { source in
            switch source.volumeKind {
            case .internalVolume:
                return true
            case .externalVolume:
                return showExternalVolumes
            case .networkVolume:
                return showNetworkVolumes
            case .diskImage:
                return showDiskImages
            case .folder:
                return true
            }
        }
    }

    private var selectedSource: ScanSource? {
        guard let selectedSourceID: ScanSource.ID = selectedSourceID else {
            return nil
        }

        return filteredSources.first { source in
            source.id == selectedSourceID
        }
    }

    private func openSource(_ source: ScanSource) {
        openWindow(value: source)
    }

    private func refreshSources() {
        let previousSelectionID: ScanSource.ID? = selectedSourceID
        sources = ScanSourceProvider.mountedVolumes()

        if let previousSelectionID: ScanSource.ID = previousSelectionID,
           filteredSources.contains(where: { source in source.id == previousSelectionID }) {
            selectedSourceID = previousSelectionID
        } else {
            selectedSourceID = filteredSources.first?.id
        }
    }

    private func seedSelectionIfNeeded() {
        if selectedSourceID == nil {
            selectedSourceID = filteredSources.first?.id
        }
    }

    private func reconcileSelectionWithVisibleSources() {
        if let selectedSourceID: ScanSource.ID = selectedSourceID,
           filteredSources.contains(where: { source in source.id == selectedSourceID }) {
            return
        }

        selectedSourceID = filteredSources.first?.id
    }

    private func chooseFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"

        guard panel.runModal() == .OK, let url: URL = panel.url else {
            return
        }

        let bookmarkData: Data? = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let source: ScanSource = ScanSourceProvider.scanSource(for: url, bookmarkData: bookmarkData)
        openSource(source)
    }
}

private struct VolumeFilterView: View {
    @Binding var showExternalVolumes: Bool
    @Binding var showNetworkVolumes: Bool
    @Binding var showDiskImages: Bool

    var body: some View {
        HStack(spacing: Metrics.filterSpacing) {
            Text("Show")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("External", isOn: $showExternalVolumes)
            Toggle("Network", isOn: $showNetworkVolumes)
            Toggle("Disk Images", isOn: $showDiskImages)

            Spacer()
        }
        .toggleStyle(.checkbox)
    }
}

private struct SourceTableHeaderView: View {
    var body: some View {
        HStack(spacing: Metrics.sourceColumnSpacing) {
            Text("Volume")
                .frame(minWidth: Metrics.volumeColumnMinimumWidth, maxWidth: .infinity, alignment: .leading)
            Text("Capacity")
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
            Text("Available")
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
            Text("Usage")
                .frame(width: Metrics.usageColumnWidth, alignment: .leading)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.tableHorizontalPadding)
    }
}

private struct SourceTableRowView: View {
    let source: ScanSource

    var body: some View {
        HStack(spacing: Metrics.sourceColumnSpacing) {
            HStack(spacing: Metrics.sourceRowSpacing) {
                Image(systemName: iconName)
                    .frame(width: Metrics.sourceIconWidth)
                VStack(alignment: .leading, spacing: Metrics.sourceTextSpacing) {
                    Text(source.displayName)
                        .font(.body)
                        .lineLimit(Metrics.singleLineLimit)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: Metrics.volumeColumnMinimumWidth, maxWidth: .infinity, alignment: .leading)

            Text(formattedBytes(source.totalCapacity))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)

            Text(formattedBytes(source.availableCapacity))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)

            VolumeUsageBarView(totalCapacity: source.totalCapacity, availableCapacity: source.availableCapacity)
                .frame(width: Metrics.usageColumnWidth)
        }
        .padding(.vertical, Metrics.sourceRowVerticalPadding)
    }

    private var subtitle: String {
        if let volumeFormat: String = source.volumeFormat, !volumeFormat.isEmpty {
            return "\(volumeFormat) - \(source.path)"
        }

        return source.path
    }

    private var iconName: String {
        switch source.volumeKind {
        case .internalVolume:
            return "internaldrive"
        case .externalVolume:
            return "externaldrive"
        case .networkVolume:
            return "network"
        case .diskImage:
            return "opticaldiscdrive"
        case .folder:
            return "folder"
        }
    }

    private func formattedBytes(_ bytes: UInt64?) -> String {
        guard let bytes: UInt64 = bytes else {
            return "--"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct VolumeUsageBarView: View {
    let totalCapacity: UInt64?
    let availableCapacity: UInt64?

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
        .accessibilityLabel(usageAccessibilityLabel)
    }

    private var usedFraction: CGFloat {
        guard let totalCapacity: UInt64 = totalCapacity,
              let availableCapacity: UInt64 = availableCapacity,
              totalCapacity > 0 else {
            return 0
        }

        let usedCapacity: UInt64 = totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
        return CGFloat(usedCapacity) / CGFloat(totalCapacity)
    }

    private var usageAccessibilityLabel: String {
        "\(Int((usedFraction * 100).rounded())) percent used"
    }
}

private enum SourcePaletteMetrics {
    static let outerSpacing: CGFloat = 16
    static let tableSpacing: CGFloat = 4
    static let sourceRowSpacing: CGFloat = 10
    static let sourceColumnSpacing: CGFloat = 16
    static let sourceTextSpacing: CGFloat = 2
    static let sourceIconWidth: CGFloat = 22
    static let sourceRowVerticalPadding: CGFloat = 5
    static let tableHorizontalPadding: CGFloat = 8
    static let volumeColumnMinimumWidth: CGFloat = 210
    static let sizeColumnWidth: CGFloat = 96
    static let usageColumnWidth: CGFloat = 118
    static let usageBarHeight: CGFloat = 8
    static let filterSpacing: CGFloat = 12
    static let buttonSpacing: CGFloat = 10
    static let volumeListMinimumHeight: CGFloat = 220
    static let windowPadding: CGFloat = 20
    static let windowMinimumWidth: CGFloat = 680
    static let windowMinimumHeight: CGFloat = 420
    static let singleLineLimit: Int = 1
    static let doubleClickCount: Int = 2
}

private typealias Metrics = SourcePaletteMetrics
