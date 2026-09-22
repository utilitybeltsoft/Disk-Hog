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
    let onShowTree: () -> Void
    @StateObject private var dataStore = SelectionListDataStore()
    @State private var searchText = ""
    @State private var searchScope: SelectionListSearchScope = .all
    @State private var scopedItem: DiskItem?
    @State private var depth: LargestItemsDepth = .descendants
    @State private var limit = LargestItemsQuery.initialLimit
    @State private var selectedID: DiskItemID?
    @State private var selectedIDs: Set<DiskItemID> = []
    @State private var isLoading = false
    @State private var matchingCount = 0
    @State private var errorMessage: String?
    @State private var generation = 0

    private var scopeRoot: DiskItem? {
        guard let root = session.rootItem else { return nil }
        if let scopedItem, scopedItem.snapshot === root.snapshot { return scopedItem }
        return root
    }

    private var query: LargestItemsQuery {
        LargestItemsQuery(category: category, depth: depth,
                          usesPhysicalSize: session.scanSettings.usePhysicalSize,
                          // The preference can change before a replacement scan.
                          lookInsidePackages: session.isPackageContentsSettingOutOfSync
                            ? !session.scanSettings.lookInsidePackages : session.scanSettings.lookInsidePackages,
                          searchText: searchText, searchScope: searchScope, limit: limit)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(scopedItem == nil ? "Entire scan" : "Folder scope")
                    .fontWeight(.semibold)
                Spacer()
                Menu("Scope") {
                    Button("Entire scan") { scopedItem = nil; depth = .descendants; limit = 1_000 }
                    Button("Current treemap folder") {
                        scopedItem = navigation.zoomRoot
                        depth = .descendants
                        limit = 1_000
                    }
                    .disabled(navigation.zoomRoot == nil)
                }
                Picker("Depth", selection: $depth) {
                    Text("All descendants").tag(LargestItemsDepth.descendants)
                    Text("Immediate children").tag(LargestItemsDepth.immediateChildren)
                }
                .labelsHidden()
                .fixedSize()
            }
            Text(scopeRoot?.path ?? session.source.path)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(scopeRoot?.path ?? session.source.path)
            HStack {
                TextField("Search ranked items", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Search in", selection: $searchScope) {
                    ForEach(SelectionListSearchScope.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                .accessibilityLabel("Search field")
            }
            HStack {
                Text(session.scanSettings.usePhysicalSize ? "Size on disk · largest first" : "Logical size · largest first")
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Text(isLoading ? "Ranking…" : "\(dataStore.resultCount) of \(matchingCount) matches")
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
                    allowsColumnSorting: false, showsKindColumn: true
                ) { item in
                    selectionCoordinator.setSelectedItem(item)
                }
                .disabled(isLoading)
                if !isLoading && dataStore.resultCount == 0 {
                    Text(session.rootItem == nil ? "Pending scan completion" : (errorMessage ?? "No matching items"))
                        .foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            HStack {
                Menu("Selected Item") {
                    Button("Show in Folder Tree") { onShowTree() }
                    Button("Show in Treemap") {
                        navigation.zoom(into: selectedItem, allowingFileFallback: true)
                    }
                    Button("Reveal in Finder") {
                        if let selectedItem { DiskItemWorkspaceActions.revealInFinder(selectedItem) }
                    }
                    Button("Information") {
                        if let selectedItem {
                            InspectorWindowController.shared.showInformation(for: selectedItem, from: session)
                        }
                    }
                    Divider()
                    Button("Explore this folder") {
                        scopedItem = selectedItem
                        depth = .immediateChildren
                        limit = LargestItemsQuery.initialLimit
                    }
                    .disabled(selectedItem?.isFolder != true || (selectedItem?.isPackage == true && !query.lookInsidePackages))
                }
                .disabled(selectedItem == nil || isLoading)
                if dataStore.resultCount < matchingCount && limit < LargestItemsQuery.maximumLimit {
                    Button("Show More") { limit = min(limit + 1_000, LargestItemsQuery.maximumLimit) }
                        .disabled(isLoading)
                }
                if matchingCount > LargestItemsQuery.maximumLimit && limit == LargestItemsQuery.maximumLimit {
                    Text("Showing the largest 10,000. Narrow the scope or search for more.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .padding(8)
        .task(id: LargestItemsTaskID(rootID: scopeRoot?.id, query: query)) {
            await rebuild()
        }
        .onChange(of: session.rootItem?.id) {
            scopedItem = nil
            selectedIDs = []
            limit = LargestItemsQuery.initialLimit
        }
        .onChange(of: selectionCoordinator.selectedItem?.id) { synchronizeSelection() }
        .onDisappear {
            generation += 1
            dataStore.reset()
        }
    }

    private var selectedItem: DiskItem? {
        selectedID.flatMap { dataStore.rowsByID[$0]?.item }
    }

    private func synchronizeSelection() {
        let id = selectionCoordinator.selectedItem?.id
        selectedID = id.flatMap { dataStore.rowsByID[$0]?.id }
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
            if !query.searchText.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
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
            synchronizeSelection()
        } catch is CancellationError {
            // Superseded queries never publish or clear a newer query's state.
        } catch {
            if generation == expectedGeneration { errorMessage = error.localizedDescription }
        }
    }
}
