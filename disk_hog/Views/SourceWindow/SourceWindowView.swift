import AppKit
import SwiftUI

struct SourceWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: SourceWindowViewModel = SourceWindowViewModel()
    @AppStorage(SourceWindowPreferences.showExternalVolumesKey) private var showExternalVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showNetworkVolumesKey) private var showNetworkVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showDiskImagesKey) private var showDiskImages: Bool = false
    @ObservedObject private var packageContentsPreference: PackageContentsPreferenceCoordinator = .shared
    @ObservedObject private var kindColorPreference: KindColorPreferenceCoordinator = .shared
    @AppStorage(DiskScanSettingsDefaultsKeys.ignoreCreatorCode) private var ignoreCreatorCode: Bool = false
    @AppStorage(DiskScanSettingsDefaultsKeys.showPhysicalFileSize) private var showPhysicalFileSize: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            SourceTableView(
                sources: viewModel.filteredSources,
                selectedSourceID: viewModel.selectedSourceID,
                onSelect: selectSource,
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
                showPackageContents: Binding(
                    get: { packageContentsPreference.showPackageContents },
                    set: { packageContentsPreference.requestChange(to: $0) }
                ),
                ignoreCreatorCode: $ignoreCreatorCode,
                showPhysicalFileSize: $showPhysicalFileSize,
                shareKindColors: Binding(
                    get: { kindColorPreference.sharesColors },
                    set: { kindColorPreference.setSharesColors($0) }
                ),
                canScanSelectedVolume: viewModel.selectedSource?.canScan == true,
                onRefresh: refreshSources,
                onChooseFolder: chooseFolder,
                onScanSelectedVolume: scanSelectedVolume
            )
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.bottom, Metrics.windowPadding)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(SourceWindowCloseRegistrationView())
        .background(ScanWindowKeyObservationView {
            ScanWindowCommandState.shared.deactivate()
            InspectorWindowController.shared.activate(source: viewModel.selectedSource)
        })
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
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            refreshSources()
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
            lookInsidePackages: packageContentsPreference.showPackageContents,
            ignoreCreatorCode: ignoreCreatorCode
        )
    }

    private func applyVolumeFilter() {
        let filter: SourceVolumeFilter = SourceVolumeFilter(
            includesExternalVolumes: showExternalVolumes,
            includesNetworkVolumes: showNetworkVolumes,
            includesDiskImages: showDiskImages
        )
        DispatchQueue.main.async {
            viewModel.setFilter(filter)
            InspectorWindowController.shared.activate(source: viewModel.selectedSource)
        }
    }

    private func selectSource(_ sourceID: ScanSource.ID?) {
        viewModel.select(sourceID)
        InspectorWindowController.shared.activate(source: viewModel.selectedSource)
    }

    private func refreshSources() {
        viewModel.refresh()
        InspectorWindowController.shared.activate(source: viewModel.selectedSource)
    }

    private func chooseFolder() {
        SourceFolderChooser.chooseSource { source in
            guard let source else {
                return
            }

            openSource(source)
        }
    }

    private func scanSelectedVolume() {
        guard let selectedSource: ScanSource = viewModel.selectedSource else {
            return
        }

        openSource(selectedSource)
    }

    private func openSource(_ source: ScanSource) {
        guard source.canScan else {
            return
        }

        let scanSource: ScanSource = source.applyingScanSettings(currentScanSettings)
        if ScanWindowRegistry.shared.activateWindow(for: scanSource) {
            return
        }

        openWindow(value: scanSource)
    }
}

private typealias Metrics = SourceWindowMetrics
