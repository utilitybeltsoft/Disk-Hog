import AppKit
import SwiftUI

struct SourceWindowView: View {
    @StateObject private var viewModel: SourceWindowViewModel = SourceWindowViewModel()
    @AppStorage(SourceWindowPreferences.showExternalVolumesKey) private var showExternalVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showNetworkVolumesKey) private var showNetworkVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showDiskImagesKey) private var showDiskImages: Bool = false
    @ObservedObject private var scanPreferences: ScanPreferences = .shared

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
                    get: { scanPreferences.showPackageContents },
                    set: { scanPreferences.requestShowPackageContentsChange(to: $0) }
                ),
                showPhysicalFileSize: Binding(
                    get: { scanPreferences.usesPhysicalSize },
                    set: { scanPreferences.setUsesPhysicalSize($0) }
                ),
                shareKindColors: Binding(
                    get: { scanPreferences.sharesKindColors },
                    set: { scanPreferences.setSharesKindColors($0) }
                ),
                treemapColorScheme: Binding(
                    get: { scanPreferences.treemapColorScheme },
                    set: { scanPreferences.setTreemapColorScheme($0) }
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
            usePhysicalSize: scanPreferences.usesPhysicalSize,
            lookInsidePackages: scanPreferences.showPackageContents
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
        let refreshTask: Task<Void, Never> = viewModel.refresh()
        Task { @MainActor in
            await refreshTask.value
            InspectorWindowController.shared.activate(source: viewModel.selectedSource)
        }
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
        ScanWindowControllerRegistry.shared.show(source: scanSource)
    }
}

private typealias Metrics = SourceWindowMetrics
