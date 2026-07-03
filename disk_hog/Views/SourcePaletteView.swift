import AppKit
import SwiftUI

struct SourcePaletteView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var sources: [ScanSource] = ScanSourceProvider.mountedVolumes()
    @State private var selectedSourceID: ScanSource.ID?
    @State private var showsScanSettings: Bool = false
    @AppStorage(SourcePaletteDefaults.showExternalVolumesKey) private var showExternalVolumes: Bool = false
    @AppStorage(SourcePaletteDefaults.showNetworkVolumesKey) private var showNetworkVolumes: Bool = false
    @AppStorage(SourcePaletteDefaults.showDiskImagesKey) private var showDiskImages: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            VStack(spacing: Metrics.tableSpacing) {
                SourceTableHeaderView()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredSources.enumerated()), id: \.element.id) { index, source in
                            SourceTableRowView(
                                source: source,
                                isAlternateRow: index.isMultiple(of: Metrics.alternateRowModulo) == false,
                                isSelected: selectedSourceID == source.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSourceID = source.id
                            }
                            .onTapGesture(count: Metrics.doubleClickCount) {
                                openSource(source)
                            }
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.listCornerRadius))
                .frame(height: Metrics.volumeListHeight)
            }
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.top, Metrics.windowPadding)

            VolumeFilterView(
                showExternalVolumes: $showExternalVolumes,
                showNetworkVolumes: $showNetworkVolumes,
                showDiskImages: $showDiskImages
            )
            .padding(.horizontal, Metrics.windowPadding)

            HStack(spacing: Metrics.buttonSpacing) {
                Button {
                    showsScanSettings.toggle()
                } label: {
                    ButtonLabel(title: "Settings", systemImage: "gearshape")
                }
                .frame(height: Metrics.buttonHeight)
                .popover(isPresented: $showsScanSettings) {
                    ScanSettingsPlaceholderView()
                }

                Button {
                    refreshSources()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: Metrics.standardFontSize))
                }
                .frame(width: Metrics.iconButtonWidth, height: Metrics.buttonHeight)
                .help("Refresh volumes")

                Spacer()

                Button {
                    chooseFolder()
                } label: {
                    ButtonLabel(title: "Choose Folder to Scan", systemImage: "folder")
                }
                .frame(height: Metrics.buttonHeight)
                .keyboardShortcut("o", modifiers: .command)
                .help("Select a folder to scan")

                Button {
                    if let selectedSource: ScanSource = selectedSource {
                        openSource(selectedSource)
                    }
                } label: {
                    Text("Scan Volume")
                        .font(.system(size: Metrics.standardFontSize))
                }
                .frame(height: Metrics.buttonHeight)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedSource == nil)
            }
            .font(.system(size: Metrics.standardFontSize))
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
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            refreshSources()
        }
    }

    private var filteredSources: [ScanSource] {
        let visibleSources: [ScanSource] = sources.filter { source in
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

        return visibleSources.sorted { first, second in
            if first.volumeKind.sortRank != second.volumeKind.sortRank {
                return first.volumeKind.sortRank < second.volumeKind.sortRank
            }

            return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
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

private struct ButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: Metrics.standardFontSize))
            .lineLimit(Metrics.singleLineLimit)
    }
}

private struct ScanSettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.scanSettingsSpacing) {
            Text("Scan Settings")
                .font(.system(size: Metrics.standardFontSize, weight: .semibold))
            Text("Settings applied to the next scan will live here.")
                .font(.system(size: Metrics.standardFontSize))
                .foregroundStyle(.secondary)
        }
        .padding(Metrics.scanSettingsPadding)
        .frame(width: Metrics.scanSettingsWidth, alignment: .leading)
    }
}

private struct VolumeFilterView: View {
    @Binding var showExternalVolumes: Bool
    @Binding var showNetworkVolumes: Bool
    @Binding var showDiskImages: Bool

    var body: some View {
        HStack(spacing: Metrics.filterSpacing) {
            Text("Show")
                .font(.system(size: Metrics.standardFontSize))
                .foregroundStyle(.secondary)

            Toggle("External Devices", isOn: $showExternalVolumes)
                .font(.system(size: Metrics.standardFontSize))
            Toggle("Mounted Images", isOn: $showDiskImages)
                .font(.system(size: Metrics.standardFontSize))
            Toggle("Network Drives", isOn: $showNetworkVolumes)
                .font(.system(size: Metrics.standardFontSize))

            Spacer()
        }
        .toggleStyle(.switch)
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

private struct SourceTableRowView: View {
    let source: ScanSource
    let isAlternateRow: Bool
    let isSelected: Bool

    var body: some View {
        SourceTableColumns {
            HStack(spacing: Metrics.sourceRowSpacing) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.sourceIconWidth)
                VStack(alignment: .leading, spacing: Metrics.sourceTextSpacing) {
                    Text(source.displayName)
                        .font(.system(size: Metrics.standardFontSize))
                        .lineLimit(Metrics.singleLineLimit)
                    Text(subtitle)
                        .font(.system(size: Metrics.standardFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: Metrics.volumeColumnMinimumWidth, maxWidth: .infinity, alignment: .leading)

            Text(formattedBytes(source.totalCapacity))
                .font(.system(size: Metrics.standardFontSize, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)

            Text(formattedBytes(usedCapacity))
                .font(.system(size: Metrics.standardFontSize, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)

            Text(formattedBytes(source.availableCapacity))
                .font(.system(size: Metrics.standardFontSize, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)

            Text(formattedPercent(freeFraction))
                .font(.system(size: Metrics.standardFontSize, design: .monospaced))
                .monospacedDigit()
                .frame(width: Metrics.percentColumnWidth, alignment: .trailing)

            VolumeUsageBarView(totalCapacity: source.totalCapacity, availableCapacity: source.availableCapacity)
                .frame(width: Metrics.usageColumnWidth)
        }
        .frame(height: Metrics.sourceRowHeight)
        .padding(.horizontal, Metrics.tableHorizontalPadding)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(Metrics.selectionOpacity)
        }

        return isAlternateRow ? Color(nsColor: .alternatingContentBackgroundColors[1]) : Color(nsColor: .textBackgroundColor)
    }

    private var subtitle: String {
        if let volumeFormat: String = source.volumeFormat, !volumeFormat.isEmpty {
            return "\(volumeFormat) - \(source.path)"
        }

        return source.path
    }

    private var icon: NSImage {
        let icon: NSImage = NSWorkspace.shared.icon(forFile: source.path)
        icon.size = NSSize(width: Metrics.sourceIconWidth, height: Metrics.sourceIconWidth)
        return icon
    }

    private var usedCapacity: UInt64? {
        guard let totalCapacity: UInt64 = source.totalCapacity,
              let availableCapacity: UInt64 = source.availableCapacity else {
            return nil
        }

        return totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }

    private var freeFraction: Double? {
        guard let totalCapacity: UInt64 = source.totalCapacity,
              let availableCapacity: UInt64 = source.availableCapacity,
              totalCapacity > 0 else {
            return nil
        }

        return Double(availableCapacity) / Double(totalCapacity)
    }

    private func formattedBytes(_ bytes: UInt64?) -> String {
        guard let bytes: UInt64 = bytes else {
            return "--"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formattedPercent(_ fraction: Double?) -> String {
        guard let fraction: Double = fraction else {
            return "--"
        }

        return "\(Int((fraction * 100).rounded()))%"
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

private struct SourceTableColumns<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Metrics.sourceColumnSpacing) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private extension ScanSourceVolumeKind {
    var sortRank: Int {
        switch self {
        case .internalVolume:
            return 0
        case .externalVolume:
            return 1
        case .diskImage:
            return 2
        case .networkVolume:
            return 3
        case .folder:
            return 4
        }
    }
}

enum SourcePaletteMetrics {
    static let outerSpacing: CGFloat = 12
    static let tableSpacing: CGFloat = 4
    static let standardFontSize: CGFloat = 11
    static let sourceRowSpacing: CGFloat = 8
    static let sourceColumnSpacing: CGFloat = 16
    static let sourceTextSpacing: CGFloat = 2
    static let sourceIconWidth: CGFloat = 28
    static let sourceRowHeight: CGFloat = 42
    static let tableHorizontalPadding: CGFloat = 8
    static let volumeColumnMinimumWidth: CGFloat = 210
    static let sizeColumnWidth: CGFloat = 88
    static let percentColumnWidth: CGFloat = 52
    static let usageColumnWidth: CGFloat = 96
    static let alternateRowModulo: Int = 2
    static let selectionOpacity: CGFloat = 0.22
    static let listCornerRadius: CGFloat = 4
    static let usageBarHeight: CGFloat = 8
    static let filterSpacing: CGFloat = 18
    static let buttonSpacing: CGFloat = 10
    static let buttonHeight: CGFloat = 30
    static let iconButtonWidth: CGFloat = 30
    static let visibleVolumeRowCount: CGFloat = 6
    static let volumeListHeight: CGFloat = sourceRowHeight * visibleVolumeRowCount
    static let windowPadding: CGFloat = 12
    static let windowMinimumWidth: CGFloat = 760
    static let windowMinimumHeight: CGFloat = 320
    static let scanSettingsPadding: CGFloat = 14
    static let scanSettingsSpacing: CGFloat = 6
    static let scanSettingsWidth: CGFloat = 260
    static let singleLineLimit: Int = 1
    static let doubleClickCount: Int = 2
}

private typealias Metrics = SourcePaletteMetrics

private enum SourcePaletteDefaults {
    static let showExternalVolumesKey: String = "DIXShowExternalDevices"
    static let showNetworkVolumesKey: String = "DIXShowNetworkDrives"
    static let showDiskImagesKey: String = "DIXShowMountedImages"
}
