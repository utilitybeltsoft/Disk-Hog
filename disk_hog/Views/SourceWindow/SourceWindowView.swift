import AppKit
import SwiftUI

struct SourceWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: SourceWindowViewModel = SourceWindowViewModel()
    @AppStorage(SourceWindowPreferences.showExternalVolumesKey) private var showExternalVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showNetworkVolumesKey) private var showNetworkVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showDiskImagesKey) private var showDiskImages: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.showPackageContents) private var showPackageContents: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.ignoreCreatorCode) private var ignoreCreatorCode: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.showPhysicalFileSize) private var showPhysicalFileSize: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            SourceTableView(
                sources: viewModel.filteredSources,
                selectedSourceID: viewModel.selectedSourceID,
                onSelect: viewModel.select,
                onOpen: openSource
            )
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.top, Metrics.windowPadding)

            VolumeFilterView(
                showExternalVolumes: $showExternalVolumes,
                showNetworkVolumes: $showNetworkVolumes,
                showDiskImages: $showDiskImages
            )
            .padding(.horizontal, Metrics.windowPadding)

            SourceWindowActionBar(
                showPackageContents: $showPackageContents,
                ignoreCreatorCode: $ignoreCreatorCode,
                showPhysicalFileSize: $showPhysicalFileSize,
                canScanSelectedVolume: viewModel.selectedSource != nil,
                onRefresh: viewModel.refresh,
                onChooseFolder: chooseFolder,
                onScanSelectedVolume: scanSelectedVolume
            )
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.bottom, Metrics.windowPadding)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(SourceWindowCloseRegistrationView())
        .background(ScanWindowKeyObservationView {
            InspectorPaletteController.shared.deactivate()
        })
        .onAppear {
            applyVolumeFilter()
        }
        .onChange(of: showExternalVolumes) {
            applyVolumeFilter()
        }
        .onChange(of: showNetworkVolumes) {
            applyVolumeFilter()
        }
        .onChange(of: showDiskImages) {
            applyVolumeFilter()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            viewModel.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            viewModel.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceWindowChooseFolderToScan)) { _ in
            chooseFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceWindowScanSelectedVolume)) { _ in
            scanSelectedVolume()
        }
    }

    private var currentScanSettings: DiskScanSettings {
        DiskScanSettings(
            usePhysicalSize: showPhysicalFileSize,
            lookInsidePackages: showPackageContents,
            ignoreCreatorCode: ignoreCreatorCode
        )
    }

    private func applyVolumeFilter() {
        viewModel.filter = SourceVolumeFilter(
            includesExternalVolumes: showExternalVolumes,
            includesNetworkVolumes: showNetworkVolumes,
            includesDiskImages: showDiskImages
        )
    }

    private func chooseFolder() {
        guard let source: ScanSource = SourceFolderChooser.chooseSource() else {
            return
        }

        openSource(source)
    }

    private func scanSelectedVolume() {
        guard let selectedSource: ScanSource = viewModel.selectedSource else {
            return
        }

        openSource(selectedSource)
    }

    private func openSource(_ source: ScanSource) {
        let scanSource: ScanSource = source.applyingScanSettings(currentScanSettings)
        if ScanWindowRegistry.shared.activateWindow(for: scanSource) {
            return
        }

        openWindow(value: scanSource)
    }
}

private typealias Metrics = SourceWindowMetrics
