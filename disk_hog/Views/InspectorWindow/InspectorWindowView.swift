import AppKit
import SwiftUI

struct InspectorWindowView: View {
    @ObservedObject var controller: InspectorWindowController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(InspectorWindowTab.allCases) { tab in
                    Button {
                        controller.selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .fixedSize()
                    }
                    .buttonStyle(
                        InspectorTabButtonStyle(isSelected: controller.selectedTab == tab)
                    )
                }
            }
            .padding(15)
            .fixedSize(horizontal: true, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: InspectorTabBarWidthKey.self, value: proxy.size.width)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if controller.selectedTab == .cleanupQueue {
                CleanupQueueView()
            } else if let context: InspectorWindowContext = controller.activeContext {
                InspectorWindowContentView(
                    context: context,
                    selectedTab: controller.selectedTab
                )
                .id(ObjectIdentifier(context))
            } else if let source: ScanSource = controller.activeSource {
                SourceInspectorWindowContentView(
                    source: source,
                    selectedTab: controller.selectedTab
                )
                .id(source.id)
            } else {
                ContentUnavailableView(
                    controller.selectedTab.inactiveTitle,
                    systemImage: controller.selectedTab.inactiveSystemImage,
                    description: Text(controller.selectedTab.inactiveDescription)
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onPreferenceChange(InspectorTabBarWidthKey.self) { width in
            controller.updateTabBarWidth(width)
        }
    }
}

private struct InspectorTabBarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct InspectorTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(
                size: NSFont.smallSystemFontSize,
                weight: .regular
            ))
            .foregroundStyle(
                Color(nsColor: isSelected ? .selectedControlTextColor : .controlTextColor)
            )
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: isSelected ? .selectedControlColor : .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isSelected ? Color.clear : Color(nsColor: .separatorColor),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SourceInspectorWindowContentView: View {
    let source: ScanSource
    let selectedTab: InspectorWindowTab

    var body: some View {
        Group {
            switch selectedTab {
            case .diskUsage:
                SourceDiskUsageView(source: source)
            case .information:
                VolumeInformationView(source: source)
            case .selectionList:
                ContentUnavailableView(
                    "Scan Window Required",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Complete a scan before viewing a file selection list.")
                )
            case .cleanupQueue:
                CleanupQueueView()
            case .scanIssues:
                ContentUnavailableView(
                    "Scan Window Required",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Complete a scan to see items that could not be scanned.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectorWindowContentView: View {
    @ObservedObject var context: InspectorWindowContext
    let selectedTab: InspectorWindowTab

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case .information:
                    FileInformationView(
                        session: context.session,
                        selectionCoordinator: context.selectionCoordinator
                    )
                case .diskUsage:
                    DiskUsageView(session: context.session)
                case .selectionList:
                    Color.clear
                case .cleanupQueue:
                    CleanupQueueView()
                case .scanIssues:
                    ScanIssuesView(session: context.session)
                }
            }

            SelectionListView(
                session: context.session,
                selectionCoordinator: context.selectionCoordinator,
                selectionFilter: $context.selectionListFilter,
                dataStore: context.selectionListDataStore
            )
            .opacity(selectedTab == .selectionList ? 1 : 0)
            .allowsHitTesting(selectedTab == .selectionList)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiskUsageView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        if session.source.volumeKind == .folder {
            ContentUnavailableView(
                "Volume Scan Required",
                systemImage: "chart.pie",
                description: Text("Disk-wide usage is shown when an entire mounted volume is scanned.")
            )
        } else if let usage: DiskUsage = DiskUsage.make(for: session) {
            DiskUsageContent(
                usage: usage,
                primaryLabel: "Scanned",
                showsOtherUsed: true,
                isScanning: session.state == .scanning
            )
        } else {
            ContentUnavailableView(
                "Disk Usage Unavailable",
                systemImage: "chart.pie",
                description: Text("Capacity information is not available for this volume.")
            )
        }
    }
}

private struct SourceDiskUsageView: View {
    let source: ScanSource

    var body: some View {
        if let usage: DiskUsage = DiskUsage.make(for: source) {
            DiskUsageContent(
                usage: usage,
                primaryLabel: "Used",
                showsOtherUsed: false,
                isScanning: false
            )
        } else {
            ContentUnavailableView(
                "Disk Usage Unavailable",
                systemImage: "chart.pie",
                description: Text("Capacity information is not available for this volume.")
            )
        }
    }
}

enum DiskUsageLayoutMetrics {
    static let pieDiameter: CGFloat = 200
    static let bottomPadding: CGFloat = 20
}

private struct DiskUsageContent: View {
    let usage: DiskUsage
    let primaryLabel: LocalizedStringKey
    let showsOtherUsed: Bool
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 18) {
            DiskUsagePie(usage: usage)
                .frame(
                    width: DiskUsageLayoutMetrics.pieDiameter,
                    height: DiskUsageLayoutMetrics.pieDiameter
                )
                .padding(.top, 12)

            VStack(spacing: 10) {
                DiskUsageLegendRow(
                    color: .accentColor,
                    label: isScanning ? "Scanned so far" : primaryLabel,
                    bytes: usage.primaryUsedBytes,
                    totalBytes: usage.totalBytes
                )
                if showsOtherUsed {
                    DiskUsageLegendRow(
                        color: Color(nsColor: .systemGray),
                        label: isScanning ? "Remaining used" : "Other used",
                        bytes: usage.otherUsedBytes,
                        totalBytes: usage.totalBytes
                    )
                }
                DiskUsageLegendRow(
                    color: Color(nsColor: .tertiaryLabelColor),
                    label: "Free",
                    bytes: usage.freeBytes,
                    totalBytes: usage.totalBytes
                )
            }
            .padding(.horizontal, 20)

            if showsOtherUsed {
                Text(otherUsedExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, DiskUsageLayoutMetrics.bottomPadding)
    }

    private var otherUsedExplanation: String {
        if isScanning {
            return String(localized: "Remaining used includes files not yet added to the scan tree and space outside it. The value is recalculated as scanning progresses.")
        }
        return String(localized: "Other used includes space outside the completed scan tree, such as protected files, snapshots, and sibling system volumes.")
    }
}

struct DiskUsage {
    let totalBytes: UInt64
    let primaryUsedBytes: UInt64
    let otherUsedBytes: UInt64
    let freeBytes: UInt64

    static func make(for session: ScanSession) -> DiskUsage? {
        let fileSystemAttributes: [FileAttributeKey: Any]? = try? FileManager.default.attributesOfFileSystem(
            forPath: session.source.path
        )
        let totalBytes: UInt64? = (fileSystemAttributes?[.systemSize] as? NSNumber)?.uint64Value
            ?? session.source.totalCapacity
        let freeBytes: UInt64? = (fileSystemAttributes?[.systemFreeSize] as? NSNumber)?.uint64Value
            ?? session.source.availableCapacity

        guard let totalBytes,
              let freeBytes,
              totalBytes > 0 else {
            return nil
        }

        let usedBytes: UInt64 = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        let scannedBytes: UInt64 = min(
            session.scannedByteCount,
            usedBytes
        )
        return DiskUsage(
            totalBytes: totalBytes,
            primaryUsedBytes: scannedBytes,
            otherUsedBytes: usedBytes - scannedBytes,
            freeBytes: min(freeBytes, totalBytes)
        )
    }

    static func make(for source: ScanSource) -> DiskUsage? {
        let fileSystemAttributes: [FileAttributeKey: Any]? = try? FileManager.default.attributesOfFileSystem(
            forPath: source.path
        )
        let totalBytes: UInt64? = (fileSystemAttributes?[.systemSize] as? NSNumber)?.uint64Value
            ?? source.totalCapacity
        let freeBytes: UInt64? = (fileSystemAttributes?[.systemFreeSize] as? NSNumber)?.uint64Value
            ?? source.availableCapacity

        guard let totalBytes,
              let freeBytes,
              totalBytes > 0 else {
            return nil
        }

        let boundedFreeBytes: UInt64 = min(freeBytes, totalBytes)
        return DiskUsage(
            totalBytes: totalBytes,
            primaryUsedBytes: totalBytes - boundedFreeBytes,
            otherUsedBytes: 0,
            freeBytes: boundedFreeBytes
        )
    }
}

private struct DiskUsagePie: View {
    let usage: DiskUsage

    var body: some View {
        GeometryReader { proxy in
            let diameter: CGFloat = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .trim(
                        from: fraction(usage.primaryUsedBytes + usage.otherUsedBytes),
                        to: 1
                    )
                    .stroke(
                        Color(nsColor: .tertiaryLabelColor),
                        style: StrokeStyle(lineWidth: diameter / 2, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: fraction(usage.primaryUsedBytes))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: diameter / 2, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(
                        from: fraction(usage.primaryUsedBytes),
                        to: fraction(usage.primaryUsedBytes + usage.otherUsedBytes)
                    )
                    .stroke(
                        Color(nsColor: .systemGray),
                        style: StrokeStyle(lineWidth: diameter / 2, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter / 2, height: diameter / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Disk usage")
        .accessibilityValue("\(percentage(usage.totalBytes - usage.freeBytes)) used")
    }

    private func fraction(_ bytes: UInt64) -> CGFloat {
        CGFloat(Double(bytes) / Double(usage.totalBytes))
    }

    private func percentage(_ bytes: UInt64) -> String {
        (Double(bytes) / Double(usage.totalBytes)).formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct DiskUsageLegendRow: View {
    let color: Color
    let label: LocalizedStringKey
    let bytes: UInt64
    let totalBytes: UInt64

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
            Spacer()
            Text(byteString(bytes))
                .monospacedDigit()
            Text(percentString)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var percentString: String {
        guard totalBytes > 0 else { return "0%" }
        return (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct SelectionListView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var selectionCoordinator: ScanWindowSelectionCoordinator
    @Binding var selectionFilter: SelectionListFilter?
    @ObservedObject var dataStore: SelectionListDataStore
    @State private var rowsGeneration: Int = 0
    @State private var selectedItemID: DiskItemID?
    @State private var selectedItemIDs: Set<DiskItemID> = []
    @State private var isLoading: Bool = false
    @State private var isQuerying: Bool = false
    @State private var hasCompletedInitialQuery: Bool = false
    @State private var searchText: String = ""
    @State private var searchScope: SelectionListSearchScope = .all
    @State private var sortDescriptors: [SelectionListSortDescriptor] = [
        SelectionListSortDescriptor(field: .size, isAscending: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(
                        selectionFilter?.title
                            ?? String(localized: "No file kind selected")
                    )
                        .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(selectionStatus)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    Text("Search in:")
                        .foregroundStyle(.secondary)
                    Picker("Search in", selection: $searchScope) {
                        ForEach(SelectionListSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()

                    TextField("Case-insensitive search", text: searchTextBinding)
                        .accessibilityLabel("Case-insensitive \(searchScope.accessibilityTitle) search")
                        .help(searchScope.helpText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .font(.system(size: NSFont.smallSystemFontSize))

            Divider()

            if selectionFilter == nil {
                ContentUnavailableView(
                    "No File Kind Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Select a row in the file-kind pane.")
                )
                .padding(.top, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if isBuildingInitialList {
                ProgressView("Building list...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    SelectionListTableView(
                        dataStore: dataStore,
                        session: session,
                        selectedItemID: $selectedItemID,
                        selectedItemIDs: $selectedItemIDs,
                        sortDescriptors: $sortDescriptors
                    ) { item in
                        selectionCoordinator.setSelectedItem(item)
                    }
                    .opacity(isUpdatingVisibleList ? 0 : 1)
                    .allowsHitTesting(!isUpdatingVisibleList)

                    if isUpdatingVisibleList {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onChange(of: selectionCoordinator.selectedItem?.id) {
                    let selectedItem: DiskItem? = selectionCoordinator.selectedItem
                    selectedItemID = selectedItem.flatMap { dataStore.rowsByID[$0.id] }?.id
                }
            }
        }
        .task(id: SelectionListTaskID(rootID: session.rootItem?.id, filter: selectionFilter)) {
            guard let rootItem: DiskItem = session.rootItem,
                  let selectionFilter else {
                isLoading = false
                isQuerying = false
                hasCompletedInitialQuery = false
                return
            }

            let usesPhysicalSize: Bool = session.scanSettings.usePhysicalSize
            let rebuildReason: String? = dataStore.rebuildReason(
                rootID: rootItem.id,
                filter: selectionFilter,
                usesPhysicalSize: usesPhysicalSize
            )
            guard let rebuildReason else {
                isLoading = false
                isQuerying = false
                hasCompletedInitialQuery = true
                let selectedItem: DiskItem? = selectionCoordinator.selectedItem
                selectedItemID = selectedItem.flatMap { dataStore.rowsByID[$0.id] }?.id
                return
            }

            #if DEBUG
            print("Selection List rebuild: \(rebuildReason)")
            #endif

            isLoading = true
            hasCompletedInitialQuery = false
            dataStore.beginRebuild(
                rootID: rootItem.id,
                filter: selectionFilter,
                usesPhysicalSize: usesPhysicalSize
            )
            rowsGeneration += 1
            let worker = Task.detached(priority: .utility) {
                try SelectionListPipeline.makeSnapshot(
                    rootItem: rootItem,
                    filter: selectionFilter,
                    usePhysicalSize: usesPhysicalSize
                )
            }
            let snapshot: SelectionListSnapshot
            do {
                snapshot = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() }
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dataStore.install(snapshot)
            rowsGeneration += 1
            isLoading = false
            let selectedItem: DiskItem? = selectionCoordinator.selectedItem
            selectedItemID = selectedItem.flatMap { snapshot.rowsByID[$0.id] }?.id
        }
        .task(
            id: SelectionListQueryTaskID(
                rowsGeneration: rowsGeneration,
                searchText: searchText,
                searchScope: searchScope,
                sortDescriptors: sortDescriptors
            )
        ) {
            guard let rootItem: DiskItem = session.rootItem,
                  let selectionFilter,
                  !isLoading else {
                return
            }
            let sourceRows: [SelectionListRow] = dataStore.rows
            let sourceGeneration: Int = rowsGeneration
            let query: String = searchText
            let scope: SelectionListSearchScope = searchScope
            let descriptors: [SelectionListSortDescriptor] = sortDescriptors
            if !hasCompletedInitialQuery, !dataStore.requiresRebuild(
                rootID: rootItem.id,
                filter: selectionFilter,
                usesPhysicalSize: session.scanSettings.usePhysicalSize
            ) {
                return
            }
            isQuerying = true

            if !query.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }

            let worker = Task.detached(priority: .utility) {
                try SelectionListPipeline.visibleRows(
                    from: sourceRows,
                    searchText: query,
                    scope: scope,
                    sortDescriptors: descriptors
                )
            }
            let result: SelectionListQueryResult
            do {
                result = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() }
                )
            } catch {
                return
            }
            guard !Task.isCancelled, rowsGeneration == sourceGeneration else { return }
            dataStore.publish(result)
            isQuerying = false
            hasCompletedInitialQuery = true
        }
    }

    private var selectionStatus: String {
        if isBuildingInitialList {
            return String(localized: "Building...")
        }
        if isUpdatingVisibleList {
            return String(localized: "Searching...")
        }
        return String(localized: "\(dataStore.resultCount) files")
    }

    private var isBuildingInitialList: Bool {
        selectionFilter != nil
            && !hasCompletedInitialQuery
            && (isLoading || isQuerying)
    }

    private var isUpdatingVisibleList: Bool {
        selectionFilter != nil
            && hasCompletedInitialQuery
            && isQuerying
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            searchText
        } set: { newValue in
            guard searchText != newValue else {
                return
            }
            searchText = newValue
            if hasCompletedInitialQuery {
                isQuerying = true
            }
        }
    }
}

private struct SelectionListTaskID: Hashable {
    let rootID: DiskItemID?
    let filter: SelectionListFilter?
}

private struct SelectionListQueryTaskID: Hashable {
    let rowsGeneration: Int
    let searchText: String
    let searchScope: SelectionListSearchScope
    let sortDescriptors: [SelectionListSortDescriptor]
}

private func byteString(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
