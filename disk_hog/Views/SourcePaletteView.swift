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
    @AppStorage(DiskScanSettingsDefaultsKeys.showPackageContents) private var showPackageContents: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.ignoreCreatorCode) private var ignoreCreatorCode: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.showPhysicalFileSize) private var showPhysicalFileSize: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            VStack(spacing: Metrics.tableSpacing) {
                SourceTableHeaderView()

                ScrollView {
                    ZStack(alignment: .top) {
                        SourceBlankClickCatcherView {
                            selectedSourceID = nil
                        }
                        .frame(maxWidth: .infinity, minHeight: Metrics.volumeListHeight)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredSources.enumerated()), id: \.element.id) { index, source in
                                SourceTableRowView(
                                    source: source,
                                    isAlternateRow: index.isMultiple(of: 2) == false,
                                    isSelected: selectedSourceID == source.id
                                )
                                .contentShape(Rectangle())
                                .overlay {
                                    SourceRowClickCatcherView(
                                        onSingleClick: {
                                            selectedSourceID = source.id
                                        },
                                        onDoubleClick: {
                                            openSource(source)
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
                    ScanSettingsPopoverView(
                        showPackageContents: $showPackageContents,
                        ignoreCreatorCode: $ignoreCreatorCode,
                        showPhysicalFileSize: $showPhysicalFileSize
                    )
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
                    scanSelectedVolume()
                } label: {
                    Text("Scan Selected Volume")
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
        .background(SourcePaletteCloseRegistrationView())
        .onAppear {
            updateCommandState()
        }
        .onChange(of: selectedSourceID) {
            updateCommandState()
        }
        .onChange(of: showExternalVolumes) {
            reconcileSelectionWithVisibleSources()
            updateCommandState()
        }
        .onChange(of: showNetworkVolumes) {
            reconcileSelectionWithVisibleSources()
            updateCommandState()
        }
        .onChange(of: showDiskImages) {
            reconcileSelectionWithVisibleSources()
            updateCommandState()
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
        .onReceive(NotificationCenter.default.publisher(for: .sourcePaletteChooseFolderToScan)) { _ in
            chooseFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourcePaletteScanSelectedVolume)) { _ in
            scanSelectedVolume()
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
        let scanSource: ScanSource = source.applyingScanSettings(currentScanSettings)
        if ScanWindowRegistry.shared.activateWindow(for: scanSource) {
            return
        }

        openWindow(value: scanSource)
    }

    private var currentScanSettings: DiskScanSettings {
        DiskScanSettings(
            usePhysicalSize: showPhysicalFileSize,
            lookInsidePackages: showPackageContents,
            ignoreCreatorCode: ignoreCreatorCode
        )
    }

    private func refreshSources() {
        let previousSelectionID: ScanSource.ID? = selectedSourceID
        sources = ScanSourceProvider.mountedVolumes()

        if let previousSelectionID: ScanSource.ID = previousSelectionID,
           filteredSources.contains(where: { source in source.id == previousSelectionID }) {
            selectedSourceID = previousSelectionID
        } else {
            selectedSourceID = nil
        }
    }

    private func reconcileSelectionWithVisibleSources() {
        if let selectedSourceID: ScanSource.ID = selectedSourceID,
           filteredSources.contains(where: { source in source.id == selectedSourceID }) {
            return
        }

        selectedSourceID = nil
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

    private func scanSelectedVolume() {
        guard let selectedSource: ScanSource = selectedSource else {
            return
        }

        openSource(selectedSource)
    }

    private func updateCommandState() {
        SourcePaletteCommandState.shared.canScanSelectedVolume = selectedSource != nil
    }
}

private struct SourceBlankClickCatcherView: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> SourceBlankClickCatcherNSView {
        let view: SourceBlankClickCatcherNSView = SourceBlankClickCatcherNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: SourceBlankClickCatcherNSView, context: Context) {
        nsView.onClick = onClick
    }
}

private final class SourceBlankClickCatcherNSView: NSView {
    var onClick: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

private struct SourceRowClickCatcherView: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> SourceRowClickCatcherNSView {
        let view: SourceRowClickCatcherNSView = SourceRowClickCatcherNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: SourceRowClickCatcherNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class SourceRowClickCatcherNSView: NSView {
    var onSingleClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    private var pendingSingleClick: DispatchWorkItem?

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick()
            return
        }

        pendingSingleClick?.cancel()
        let workItem: DispatchWorkItem = DispatchWorkItem { [weak self] in
            self?.onSingleClick()
            self?.pendingSingleClick = nil
        }
        pendingSingleClick = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }
}

private struct ButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: Metrics.standardFontSize))
            .lineLimit(1)
    }
}

private struct ScanSettingsPopoverView: View {
    @Binding var showPackageContents: Bool
    @Binding var ignoreCreatorCode: Bool
    @Binding var showPhysicalFileSize: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.scanSettingsSpacing) {
            ScanSettingsRowView(
                title: "Show Package Contents",
                description: "Treat application and document packages as folders so their contents appear in the scan.",
                isOn: $showPackageContents
            )
            ScanSettingsRowView(
                title: "Ignore Creator Code",
                description: "If set, e.g. PDF files opened by the Finder with Acrobat or Preview are regarded to have the same kind.",
                isOn: $ignoreCreatorCode
            )
            ScanSettingsRowView(
                title: "Show Physical File Size",
                description: "The physical size is the space that a file occupies on a drive. Many applications show the logical size, which is the size of a file's content.",
                isOn: $showPhysicalFileSize
            )
            Text("These settings apply to the next volume or folder you open.")
                .font(.system(size: Metrics.standardFontSize))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.scanSettingsPadding)
        .frame(width: Metrics.scanSettingsWidth, alignment: .leading)
    }
}

private struct ScanSettingsRowView: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.scanSettingsDescriptionSpacing) {
            Toggle(title, isOn: $isOn)
                .font(.system(size: Metrics.standardFontSize))
            Text(description)
                .font(.system(size: Metrics.standardFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Metrics.scanSettingsDescriptionIndent)
        }
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

private struct SourcePaletteCloseRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> SourcePaletteCloseRegistrationNSView {
        SourcePaletteCloseRegistrationNSView()
    }

    func updateNSView(_ nsView: SourcePaletteCloseRegistrationNSView, context: Context) {}
}

private final class SourcePaletteCloseRegistrationNSView: NSView {
    private weak var registeredWindow: NSWindow?
    private weak var previousWindowDelegate: (any NSWindowDelegate)?
    private var closeDelegateProxy: WindowCloseDelegateProxy?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window: NSWindow = window, registeredWindow !== window else {
            return
        }

        restoreWindowDelegate()

        previousWindowDelegate = window.delegate
        let proxy: WindowCloseDelegateProxy = WindowCloseDelegateProxy(forwardingDelegate: previousWindowDelegate) { _ in
            Self.shouldCloseSourcePalette()
        }
        closeDelegateProxy = proxy
        registeredWindow = window
        window.delegate = proxy
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            restoreWindowDelegate()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    private func restoreWindowDelegate() {
        guard let registeredWindow: NSWindow = registeredWindow else {
            return
        }

        if registeredWindow.delegate === closeDelegateProxy {
            registeredWindow.delegate = previousWindowDelegate
        }

        closeDelegateProxy = nil
        previousWindowDelegate = nil
        self.registeredWindow = nil
    }

    private static func shouldCloseSourcePalette() -> Bool {
        let activeScanningSessions: [ScanSession] = ScanWindowRegistry.shared.activeScanningSessions
        guard activeScanningSessions.isEmpty == false else {
            NSApp.terminate(nil)
            return false
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = "Cancel active scans before closing the source window?"
        alert.informativeText = activeScanningSessions.count == 1
            ? "One scan is still running. Disk Hog will keep the source window open after cancelling it."
            : "\(activeScanningSessions.count) scans are still running. Disk Hog will keep the source window open after cancelling them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Active Scans")
        alert.addButton(withTitle: "Keep Scanning")

        if alert.runModal() == .alertFirstButtonReturn {
            ScanWindowRegistry.shared.cancelActiveScans()
        }

        return false
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
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: Metrics.standardFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    static let windowMinimumWidth: CGFloat = 798
    static let windowMinimumHeight: CGFloat = 390
    static let scanSettingsPadding: CGFloat = 14
    static let scanSettingsSpacing: CGFloat = 14
    static let scanSettingsDescriptionSpacing: CGFloat = 2
    static let scanSettingsDescriptionIndent: CGFloat = 18
    static let scanSettingsWidth: CGFloat = 380
}

private typealias Metrics = SourcePaletteMetrics

private enum SourcePaletteDefaults {
    static let showExternalVolumesKey: String = "DIXShowExternalDevices"
    static let showNetworkVolumesKey: String = "DIXShowNetworkDrives"
    static let showDiskImagesKey: String = "DIXShowMountedImages"
}
