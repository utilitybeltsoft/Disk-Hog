import AppKit
import SwiftUI

struct SourceWindowView: View {
    var commandState: ScanWindowCommandState = .shared
    @ObservedObject var access: FullDiskAccessSetupModel
    @StateObject private var viewModel: SourceWindowViewModel
    @AppStorage(SourceWindowPreferences.showExternalVolumesKey) private var showExternalVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showNetworkVolumesKey) private var showNetworkVolumes: Bool = false
    @AppStorage(SourceWindowPreferences.showDiskImagesKey) private var showDiskImages: Bool = false
    @ObservedObject private var scanPreferences: ScanPreferences = .shared

    init(commandState: ScanWindowCommandState? = nil, access: FullDiskAccessSetupModel) {
        self.commandState = commandState ?? .shared
        self.access = access
        _viewModel = StateObject(wrappedValue: SourceWindowViewModel(
            canRefresh: { access.allowsSourceDiscovery }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            if access.hasChecked && access.status != .available {
                HStack {
                    Text(access.status == .protectedAccessDenied
                         ? String(localized: "Limited access: some folders may be skipped.")
                         : String(localized: "Protected-folder access could not be verified."))
                    Spacer()
                    Button("Full Disk Access…", action: access.showGuidance)
                }
                .padding(.horizontal, Metrics.windowPadding)
                .padding(.top, Metrics.windowPadding)
            }
            SourceTableView(
                sources: viewModel.filteredSources,
                selectedSourceID: viewModel.selectedSourceID,
                isLoading: viewModel.isLoading,
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
                canScanSelectedVolume: !access.blocksScanning && viewModel.selectedSource?.canScan == true,
                onRefresh: refreshSources,
                onChooseFolder: chooseFolder,
                onScanSelectedVolume: scanSelectedVolume
            )
            .disabled(access.blocksScanning)
            .padding(.horizontal, Metrics.windowPadding)
            .padding(.bottom, Metrics.windowPadding)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(ScanWindowKeyObservationView {
            commandState.deactivate()
            InspectorWindowController.shared.activate(source: viewModel.selectedSource)
        })
        .onAppear { refreshSources() }
        .task(id: access.allowsFolderChooserWarmup) {
            guard access.allowsFolderChooserWarmup else { return }
            // Let setup close and the source window settle before warming AppKit.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, access.allowsFolderChooserWarmup else { return }
            SourceFolderChooser.prepareAfterLaunch()
        }
        .onChange(of: access.allowsSourceDiscovery) {
            if access.allowsSourceDiscovery { refreshSources() }
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
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshSources()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            refreshSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceWindowAccessDidChange)) { _ in
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
        guard !access.blocksScanning else { access.showGuidance(); return }
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
        guard !access.blocksScanning else { access.showGuidance(); return }
        guard source.canScan else {
            return
        }

        let scanSource: ScanSource = source.applyingScanSettings(currentScanSettings)
        ScanWindowControllerRegistry.shared.show(source: scanSource)
    }
}

private typealias Metrics = SourceWindowMetrics
