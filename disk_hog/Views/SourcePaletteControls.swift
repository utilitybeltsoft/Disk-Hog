import SwiftUI

struct VolumeFilterView: View {
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

struct SourcePaletteActionBar: View {
    @Binding var showPackageContents: Bool
    @Binding var ignoreCreatorCode: Bool
    @Binding var showPhysicalFileSize: Bool
    let canScanSelectedVolume: Bool
    let onRefresh: () -> Void
    let onChooseFolder: () -> Void
    let onScanSelectedVolume: () -> Void
    @State private var showsScanSettings: Bool = false

    var body: some View {
        HStack(spacing: Metrics.buttonSpacing) {
            Button {
                showsScanSettings.toggle()
            } label: {
                SourcePaletteButtonLabel(title: "Settings", systemImage: "gearshape")
            }
            .frame(height: Metrics.buttonHeight)
            .popover(isPresented: $showsScanSettings) {
                ScanSettingsPopoverView(
                    showPackageContents: $showPackageContents,
                    ignoreCreatorCode: $ignoreCreatorCode,
                    showPhysicalFileSize: $showPhysicalFileSize
                )
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: Metrics.standardFontSize))
            }
            .frame(width: Metrics.iconButtonWidth, height: Metrics.buttonHeight)
            .help("Refresh volumes")

            Spacer()

            Button(action: onChooseFolder) {
                SourcePaletteButtonLabel(title: "Choose Folder to Scan", systemImage: "folder")
            }
            .frame(height: Metrics.buttonHeight)
            .keyboardShortcut("o", modifiers: .command)
            .help("Select a folder to scan")

            Button("Scan Selected Volume", action: onScanSelectedVolume)
                .font(.system(size: Metrics.standardFontSize))
                .frame(height: Metrics.buttonHeight)
                .keyboardShortcut(.defaultAction)
                .disabled(!canScanSelectedVolume)
        }
        .font(.system(size: Metrics.standardFontSize))
    }
}

private struct SourcePaletteButtonLabel: View {
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

private typealias Metrics = SourcePaletteMetrics
