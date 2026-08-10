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

struct SourceWindowActionBar: View {
    @Binding var showPackageContents: Bool
    @Binding var showPhysicalFileSize: Bool
    @Binding var shareKindColors: Bool
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
                SourceWindowButtonLabel(title: "Settings", systemImage: "gearshape")
            }
            .frame(height: Metrics.buttonHeight)
            .popover(isPresented: $showsScanSettings) {
                ScanSettingsPopoverView(
                    showPackageContents: $showPackageContents,
                    showPhysicalFileSize: $showPhysicalFileSize,
                    shareKindColors: $shareKindColors
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
                SourceWindowButtonLabel(title: "Choose Folder to Scan", systemImage: "folder")
            }
            .frame(height: Metrics.buttonHeight)
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

private struct SourceWindowButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: Metrics.standardFontSize))
            .lineLimit(1)
    }
}

private struct ScanSettingsPopoverView: View {
    @Binding var showPackageContents: Bool
    @Binding var showPhysicalFileSize: Bool
    @Binding var shareKindColors: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.scanSettingsSpacing) {
            ScanSettingsRowView(
                title: "Show Package Contents",
                description: "Treat application and document packages as folders so their contents appear in the scan.",
                isOn: $showPackageContents
            )
            ScanSettingsRowView(
                title: "Show Physical File Size",
                description: "The physical size is the space that a file occupies on a drive. Many applications show the logical size, which is the size of a file's content.",
                isOn: $showPhysicalFileSize
            )
            ScanSettingsRowView(
                title: "Match File-Kind Colors Across Open Windows",
                description: "Use the same color for a file kind in every scan window. Turn this off to color each window by its own largest kinds.",
                isOn: $shareKindColors
            )
            Text("Package-content changes can rescan open windows. Size and color changes update open windows.")
                .font(.system(size: Metrics.standardFontSize))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.scanSettingsPadding)
        .frame(width: Metrics.scanSettingsWidth, alignment: .leading)
    }
}

private struct ScanSettingsRowView: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
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

private typealias Metrics = SourceWindowMetrics
