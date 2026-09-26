import SwiftUI

private struct LargestItemsTaskID: Hashable {
    let rootID: DiskItemID?
    let query: LargestItemsQuery
}

struct LargestItemsView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var selectionCoordinator: ScanWindowSelectionCoordinator
    @ObservedObject var navigation: TreemapNavigationState
    let category: LargestItemsCategory
    let isActive: Bool
    let onShowTree: () -> Void
    @StateObject private var dataStore = SelectionListDataStore()
    @State private var selectedID: DiskItemID?
    @State private var selectedIDs: Set<DiskItemID> = []
    @State private var isLoading = false
    @State private var matchingCount = 0
    @State private var errorMessage: String?
    @State private var generation = 0

    private var scopeRoot: DiskItem? {
        session.rootItem
    }

    private var query: LargestItemsQuery {
        LargestItemsQuery(category: category,
                          usesPhysicalSize: session.scanSettings.usePhysicalSize,
                          // The preference can change before a replacement scan.
                          lookInsidePackages: session.isPackageContentsSettingOutOfSync
                            ? !session.scanSettings.lookInsidePackages : session.scanSettings.lookInsidePackages)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(session.scanSettings.usePhysicalSize ? "Size on disk · largest first" : "Logical size · largest first")
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Text(isLoading ? "Ranking…" : resultSummary)
                    .monospacedDigit()
            }
            if category == .folders {
                Text("Folder sizes include contents. Parent and child totals overlap.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.hasIncompleteResults {
                Text("Incomplete scan: ≥ marks a lower bound; Unknown means unmeasured. See Scan Issues.")
                    .foregroundStyle(.orange)
            }
            ZStack {
                SelectionListTableView(
                    dataStore: dataStore, session: session,
                    selectedItemID: $selectedID, selectedItemIDs: $selectedIDs,
                    sortDescriptors: .constant([SelectionListSortDescriptor(field: .size, isAscending: false)]),
                    allowsColumnSorting: false, showsKindColumn: true, isVisible: isActive,
                    onRankedAction: { action, item in
                        guard isActive, !isLoading else { return }
                        selectionCoordinator.setSelectedItem(item)
                        switch action {
                        case .folderTree: onShowTree()
                        case .treemap: navigation.zoom(into: item, allowingFileFallback: true)
                        case .reveal: DiskItemWorkspaceActions.revealInFinder(item)
                        case .information: InspectorWindowController.shared.showInformation(for: item, from: session)
                        }
                    }
                ) { item in
                    if isActive { selectionCoordinator.setSelectedItem(item) }
                }
                .disabled(isLoading)
                if session.rootItem != nil && !isLoading && dataStore.resultCount == 0 {
                    Text(errorMessage ?? "No items")
                        .foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .padding(8)
        .overlay {
            if session.rootItem == nil {
                ScanPanePlaceholderView(
                    title: category == .files ? "Largest Files" : "Largest Folders",
                    message: "Pending scan completion"
                )
                .padding(ScanWindowMetrics.inactivePaneBorderWidth)
            }
        }
        .task(id: LargestItemsTaskID(rootID: scopeRoot?.id, query: query)) {
            await rebuild()
        }
        .onChange(of: session.rootItem?.id) {
            selectedIDs = []
        }
        .onChange(of: selectionCoordinator.selectedItem?.id) {
            if isActive { synchronizeSelection() }
        }
        .onChange(of: isActive) {
            if isActive, let selectedItem {
                selectionCoordinator.setSelectedItem(selectedItem)
            }
        }
        .onDisappear {
            generation += 1
            dataStore.reset()
        }
    }

    private var resultSummary: String {
        let noun = category == .files ? "files" : "folders"
        if dataStore.resultCount < matchingCount {
            return "Largest \(dataStore.resultCount.formatted()) of \(matchingCount.formatted()) \(noun)"
        }
        return "\(matchingCount.formatted()) \(noun)"
    }

    private var selectedItem: DiskItem? {
        selectedID.flatMap { dataStore.rowsByID[$0]?.item }
    }

    private func synchronizeSelection() {
        let id = selectionCoordinator.selectedItem?.id
        selectedID = id.flatMap { dataStore.rowsByID[$0]?.id }
        // Preserve a table-originated multi-selection, but do not let it mask
        // a new selection coming from the treemap or another visible pane.
        if let selectedID {
            if !selectedIDs.contains(selectedID) { selectedIDs = [selectedID] }
        } else {
            selectedIDs = []
        }
    }

    @MainActor private func rebuild() async {
        generation += 1
        let expectedGeneration = generation
        let query = query
        let expectedRootID = scopeRoot?.id
        dataStore.reset()
        selectedIDs = []
        matchingCount = 0
        errorMessage = nil
        guard let root = scopeRoot else { isLoading = false; return }
        isLoading = true
        defer { if generation == expectedGeneration { isLoading = false } }
        do {
            try Task.checkCancellation()
            let result = try await LargestItemsWorkQueue.shared.run(root: root, query: query)
            guard !Task.isCancelled, generation == expectedGeneration,
                  scopeRoot?.id == expectedRootID, self.query == query else { return }
            let rows = result.rows
            dataStore.install(SelectionListSnapshot(
                rows: rows, rowsByID: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })))
            dataStore.publish(SelectionListQueryResult(
                rows: rows, rowIndexByID: Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })))
            matchingCount = result.matchingCount
            if isActive { synchronizeSelection() }
        } catch is CancellationError {
            // Superseded queries never publish or clear a newer query's state.
        } catch {
            if generation == expectedGeneration { errorMessage = error.localizedDescription }
        }
    }
}
