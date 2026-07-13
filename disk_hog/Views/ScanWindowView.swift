import SwiftUI

struct ScanWindowView: View {
    @StateObject private var session: ScanSession
    @StateObject private var selectionCoordinator: ScanWindowSelectionCoordinator = ScanWindowSelectionCoordinator()
    @State private var hoveredItem: DiskItem?
    @State private var activePane: ScanWindowPane?

    init(source: ScanSource) {
        _session = StateObject(wrappedValue: ScanSession(source: source))
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
                    KindsPaneView(session: session)
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
        }
        .onDisappear {
            session.cancel()
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
}
