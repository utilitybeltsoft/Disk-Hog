import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession
    @StateObject private var selectionCoordinator: ScanWindowSelectionCoordinator
    @StateObject private var inspectorContext: InspectorPaletteContext
    @State private var hoveredItem: DiskItem?
    @State private var activePane: ScanWindowPane?

    init(source: ScanSource) {
        let session: ScanSession = ScanSession(source: source)
        let selectionCoordinator: ScanWindowSelectionCoordinator = ScanWindowSelectionCoordinator()
        _session = StateObject(wrappedValue: session)
        _selectionCoordinator = StateObject(wrappedValue: selectionCoordinator)
        _inspectorContext = StateObject(
            wrappedValue: InspectorPaletteContext(
                session: session,
                selectionCoordinator: selectionCoordinator
            )
        )
    }

    var body: some View {
        VStack(spacing: ScanWindowMetrics.windowContentSpacing) {
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
                        selectionCoordinator: selectionCoordinator
                    )
                        .environment(\.activeScanWindowPane, $activePane)
                } second: {
                    KindsPaneView(
                        session: session,
                        onShowSelectionList: showSelectionList
                    )
                        .environment(\.selectedScanItem, selectedItemBinding)
                        .environment(\.activeScanWindowPane, $activePane)
                }
            } second: {
                TreemapPanelView(
                    session: session,
                    selectionCoordinator: selectionCoordinator
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
        .background(ScanWindowRegistrationView(session: session, source: session.source))
        .background(ScanWindowKeyObservationView {
            activateScanWindowCommandState()
        })
        .onAppear {
            session.startScan()
            activateScanWindowContext()
            InspectorPaletteController.shared.automaticallyShowDiskUsageIfNeeded(for: inspectorContext)
        }
        .onDisappear {
            session.cancel()
            InspectorPaletteController.shared.deactivate(if: inspectorContext)
        }
        .onChange(of: session.rootItem?.id) {
            selectionCoordinator.setSelectedItem(session.preferredSelection ?? session.rootItem)
            hoveredItem = nil
            updateScanWindowCommandState()
        }
        .onChange(of: selectionCoordinator.selectedItem?.id) {
            updateScanWindowCommandState()
        }
        #if FILE_MATCHING_DIAGNOSTICS
        .onChange(of: session.diagnosticsExportState) {
            updateScanWindowCommandState()
        }
        #endif
    }

    private func activateScanWindowCommandState() {
        ScanWindowCommandState.shared.activate(session: session, selectedItem: selectionCoordinator.selectedItem)
        InspectorPaletteController.shared.activate(inspectorContext)
    }

    private func updateScanWindowCommandState() {
        ScanWindowCommandState.shared.updateSelectedItem(selectionCoordinator.selectedItem, from: session)
        ScanWindowCommandState.shared.updateScanState(from: session)
    }

    private var selectedItemBinding: Binding<DiskItem?> {
        Binding {
            selectionCoordinator.selectedItem
        } set: { newSelectedItem in
            selectionCoordinator.setSelectedItem(newSelectedItem)
        }
    }

    private func activateScanWindowContext() {
        ScanWindowCommandState.shared.activate(session: session, selectedItem: selectionCoordinator.selectedItem)
        InspectorPaletteController.shared.activate(inspectorContext)
    }

    private func showSelectionList(_ filter: SelectionListFilter) {
        InspectorPaletteController.shared.showSelectionList(filter: filter, from: session)
    }
}
