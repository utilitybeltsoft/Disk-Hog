import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession
    @StateObject private var selectionCoordinator: ScanWindowSelectionCoordinator
    @StateObject private var inspectorContext: InspectorWindowContext
    @StateObject private var commandContext: ScanWindowCommandContext
    @StateObject private var treemapNavigation: TreemapNavigationState
    @ObservedObject private var scanPreferences: ScanPreferences = .shared
    @State private var hoveredItem: DiskItem?
    @State private var activePane: ScanWindowPane?

    init(session: ScanSession) {
        let selectionCoordinator: ScanWindowSelectionCoordinator = ScanWindowSelectionCoordinator()
        let treemapNavigation: TreemapNavigationState = TreemapNavigationState()
        _session = StateObject(wrappedValue: session)
        _selectionCoordinator = StateObject(wrappedValue: selectionCoordinator)
        _inspectorContext = StateObject(
            wrappedValue: InspectorWindowContext(
                session: session,
                selectionCoordinator: selectionCoordinator
            )
        )
        _commandContext = StateObject(
            wrappedValue: ScanWindowCommandContext(
                session: session,
                selectionCoordinator: selectionCoordinator,
                treemapNavigation: treemapNavigation
            )
        )
        _treemapNavigation = StateObject(wrappedValue: treemapNavigation)
    }

    var body: some View {
        VStack(spacing: ScanWindowMetrics.windowContentSpacing) {
            if session.isPackageContentsSettingOutOfSync {
                packageContentsWarning
            }

            AppKitSplitView(
                isVertical: false,
                firstMinimumSize: ScanWindowMetrics.topPaneMinimumHeight,
                secondMinimumSize: ScanWindowMetrics.treemapMinimumHeight,
                firstPreferredFraction: ScanWindowMetrics.topPanePreferredFraction
            ) {
                AppKitSplitView(
                    isVertical: true,
                    firstMinimumSize: ScanWindowMetrics.filesPaneMinimumWidth,
                    secondMinimumSize: ScanWindowMetrics.kindsPaneMinimumWidth,
                    firstPreferredFraction: ScanWindowMetrics.filesPanePreferredFraction
                ) {
                    FilesPaneView(
                        session: session,
                        selectionCoordinator: selectionCoordinator,
                        navigation: treemapNavigation
                    )
                        .environment(\.activeScanWindowPane, $activePane)
                } second: {
                    KindsPaneView(
                        session: session,
                        selectedFilter: $inspectorContext.selectionListFilter,
                        onShowSelectionList: showSelectionList
                    )
                        .environment(\.selectedScanItem, selectedItemBinding)
                        .environment(\.activeScanWindowPane, $activePane)
                }
            } second: {
                TreemapPanelView(
                    session: session,
                    selectionCoordinator: selectionCoordinator,
                    navigation: treemapNavigation
                )
                    .environment(\.hoveredScanItem, $hoveredItem)
                    .environment(\.activeScanWindowPane, $activePane)
            }
            .frame(minWidth: ScanWindowMetrics.treemapMinimumWidth, minHeight: ScanWindowMetrics.splitAreaMinimumHeight)
            .padding(.horizontal, ScanWindowMetrics.mainSplitHorizontalPadding)

            ZStatusFieldsView(session: session)
                .environment(\.selectedScanItem, selectedItemBinding)
                .environment(\.hoveredScanItem, $hoveredItem)
        }
        .frame(minWidth: ScanWindowMetrics.windowMinimumWidth, minHeight: ScanWindowMetrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ScanWindowKeyObservationView {
            activateScanWindowContext()
        })
        .onAppear {
            treemapNavigation.configure(baseRoot: session.rootItem)
            session.startScan()
            activateScanWindowContext()
            InspectorWindowController.shared.automaticallyShowDiskUsageIfNeeded(for: inspectorContext)
        }
        .onDisappear {
            session.cancel()
            commandContext.deactivate()
            ScanWindowCommandState.shared.deactivate(if: commandContext)
            InspectorWindowController.shared.deactivate(if: inspectorContext)
        }
        .onChange(of: session.rootItem?.id) {
            treemapNavigation.configure(baseRoot: session.rootItem)
            selectionCoordinator.setSelectedItem(session.preferredSelection ?? session.rootItem)
            hoveredItem = nil
            updateScanWindowCommandState()
        }
        .onChange(of: selectionCoordinator.selectedItem?.id) {
            session.rememberSelection(selectionCoordinator.selectedItem)
            treemapNavigation.revealSelection(selectionCoordinator.selectedItem)
            updateScanWindowCommandState()
        }
        .onChange(of: treemapNavigation.zoomPath.map(\.id)) {
            if let item: DiskItem = treemapNavigation.consumeSelectionAfterZoom() {
                selectionCoordinator.setSelectedItem(item)
            }
            updateScanWindowCommandState()
        }
        .onChange(of: hoveredItem?.id) {
            treemapNavigation.updatePreviewRoot(from: hoveredItem)
        }
        .alert(item: ScanSessionFailureAlertBinding.binding(for: session)) { failureAlert in
            Alert(
                title: Text(failureAlert.title),
                message: Text(failureAlert.message),
                dismissButton: .default(Text(failureAlert.dismissButtonTitle))
            )
        }
        #if FILE_MATCHING_DIAGNOSTICS
        .onChange(of: session.diagnosticsExportState) {
            updateScanWindowCommandState()
        }
        #endif
    }

    private func updateScanWindowCommandState() {
        commandContext.updateSelectedItem(selectionCoordinator.selectedItem)
        commandContext.updateScanState()
    }

    private var selectedItemBinding: Binding<DiskItem?> {
        Binding {
            selectionCoordinator.selectedItem
        } set: { newSelectedItem in
            selectionCoordinator.setSelectedItem(newSelectedItem)
        }
    }

    private func activateScanWindowContext() {
        commandContext.updateSelectedItem(selectionCoordinator.selectedItem)
        commandContext.updateScanState()
        ScanWindowCommandState.shared.activate(commandContext)
        InspectorWindowController.shared.activate(inspectorContext)
    }

    private func showSelectionList(_ filter: SelectionListFilter) {
        InspectorWindowController.shared.showSelectionList(filter: filter, from: session)
    }

    private var packageContentsWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(
                session.scanSettings.lookInsidePackages
                    ? "Out of sync: this scan shows package contents; the current setting hides them."
                    : "Out of sync: this scan hides package contents; the current setting shows them."
            )
            Spacer()
            Button {
                scanPreferences.rescanForPackageContentsPreference(session)
            } label: {
                Label("Rescan This Window", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .font(.system(size: ScanWindowMetrics.statusFieldFontSize))
        .padding(.horizontal, ScanWindowMetrics.mainSplitHorizontalPadding)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
