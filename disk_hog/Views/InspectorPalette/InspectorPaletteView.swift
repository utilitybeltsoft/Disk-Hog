import AppKit
import SwiftUI

struct InspectorPaletteView: View {
    @ObservedObject var controller: InspectorPaletteController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(InspectorPaletteTab.allCases) { tab in
                    Button {
                        controller.selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(controller.selectedTab == tab ? .accentColor : nil)
                }
                Spacer()
            }
            .padding(12)

            Divider()

            if let context: InspectorPaletteContext = controller.activeContext {
                InspectorPaletteContentView(
                    context: context,
                    selectedTab: controller.selectedTab
                )
                .id(ObjectIdentifier(context))
            } else {
                ContentUnavailableView(
                    "No Scan Window Active",
                    systemImage: "macwindow",
                    description: Text("Select a scan window to inspect its contents.")
                )
            }
        }
        .frame(
            minWidth: controller.selectedTab.layout.minimumContentSize.width,
            minHeight: controller.selectedTab.layout.minimumContentSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct InspectorPaletteContentView: View {
    @ObservedObject var context: InspectorPaletteContext
    let selectedTab: InspectorPaletteTab

    var body: some View {
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
                SelectionListView(
                    session: context.session,
                    selectionCoordinator: context.selectionCoordinator,
                    selectionFilter: $context.selectionListFilter
                )
            }
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
            VStack(spacing: 18) {
                DiskUsagePie(usage: usage)
                    .frame(minWidth: 220, minHeight: 220)
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    DiskUsageLegendRow(
                        color: .accentColor,
                        label: "Scanned",
                        bytes: usage.scannedBytes,
                        totalBytes: usage.totalBytes
                    )
                    DiskUsageLegendRow(
                        color: Color(nsColor: .systemGray),
                        label: "Other used",
                        bytes: usage.otherUsedBytes,
                        totalBytes: usage.totalBytes
                    )
                    DiskUsageLegendRow(
                        color: Color(nsColor: .tertiaryLabelColor),
                        label: "Free",
                        bytes: usage.freeBytes,
                        totalBytes: usage.totalBytes
                    )
                }
                .padding(.horizontal, 20)

                Text("Other used includes space outside the scan tree, such as protected files, snapshots, and sibling system volumes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        } else {
            ContentUnavailableView(
                "Disk Usage Unavailable",
                systemImage: "chart.pie",
                description: Text("Capacity information is not available for this volume.")
            )
        }
    }
}

private struct DiskUsage {
    let totalBytes: UInt64
    let scannedBytes: UInt64
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
            session.rootItem?.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize) ?? 0,
            usedBytes
        )
        return DiskUsage(
            totalBytes: totalBytes,
            scannedBytes: scannedBytes,
            otherUsedBytes: usedBytes - scannedBytes,
            freeBytes: min(freeBytes, totalBytes)
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
                        from: fraction(usage.scannedBytes + usage.otherUsedBytes),
                        to: 1
                    )
                    .stroke(
                        Color(nsColor: .tertiaryLabelColor),
                        style: StrokeStyle(lineWidth: diameter / 2, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: fraction(usage.scannedBytes))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: diameter / 2, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(
                        from: fraction(usage.scannedBytes),
                        to: fraction(usage.scannedBytes + usage.otherUsedBytes)
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
    let label: String
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
    @State private var rows: [SelectionListRow] = []
    @State private var selectedItemID: DiskItemID?
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var searchScope: SelectionListSearchScope = .all
    @State private var sortOrder: [KeyPathComparator<SelectionListRow>] = [
        KeyPathComparator(\.size, order: .reverse)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(selectionFilter?.title ?? "No file kind selected")
                        .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(visibleRows.count) files")
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

                    TextField("Case-insensitive search", text: $searchText)
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
            } else if isLoading {
                ProgressView("Building selection list")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(visibleRows, selection: $selectedItemID, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { row in
                        HStack(spacing: 5) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: row.item.path))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(row.name)
                                .lineLimit(1)
                        }
                    }
                    TableColumn("Path", value: \.parentPath) { row in
                        Text(row.parentPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Size", value: \.size) { row in
                        Text(byteString(row.size))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 72, ideal: 86)
                }
                .font(.system(size: NSFont.smallSystemFontSize))
                .onChange(of: selectedItemID) {
                    guard let selectedItemID,
                          let item: DiskItem = rows.first(where: { $0.id == selectedItemID })?.item else {
                        return
                    }
                    selectionCoordinator.setSelectedItem(item)
                }
                .onChange(of: selectionCoordinator.selectedItem?.id) {
                    let selectedItem: DiskItem? = selectionCoordinator.selectedItem
                    selectedItemID = rows.contains(where: { $0.id == selectedItem?.id }) ? selectedItem?.id : nil
                }
            }
        }
        .task(id: SelectionListTaskID(rootID: session.rootItem?.id, filter: selectionFilter)) {
            guard let rootItem: DiskItem = session.rootItem,
                  let selectionFilter else {
                rows = []
                return
            }

            isLoading = true
            let usePhysicalSize: Bool = session.scanSettings.usePhysicalSize
            rows = await Task.detached(priority: .userInitiated) {
                let items: [DiskItem]
                switch selectionFilter {
                case .all:
                    items = rootItem.allFiles()
                case .kind(let kindName):
                    items = rootItem.files(ofKind: kindName)
                }
                return items.map { item in
                    SelectionListRow(
                        item: item,
                        size: item.sizeValue(usePhysicalSize: usePhysicalSize)
                    )
                }
            }.value
            isLoading = false
            let selectedItem: DiskItem? = selectionCoordinator.selectedItem
            selectedItemID = rows.contains(where: { $0.id == selectedItem?.id }) ? selectedItem?.id : nil
        }
    }

    private var visibleRows: [SelectionListRow] {
        let filteredRows: [SelectionListRow]
        if searchText.isEmpty {
            filteredRows = rows
        } else {
            filteredRows = rows.filter { $0.matches(searchText, in: searchScope) }
        }
        return filteredRows.sorted(using: sortOrder)
    }
}

nonisolated enum SelectionListSearchScope: String, CaseIterable, Identifiable {
    case all
    case name
    case kind
    case path

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All fields"
        case .name: "Name"
        case .kind: "Kind"
        case .path: "Path"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .all: "name, kind, and path"
        case .name: "file name"
        case .kind: "file kind"
        case .path: "file path"
        }
    }

    var helpText: String {
        "Performs a case-insensitive substring search in \(accessibilityTitle)."
    }
}

private struct SelectionListTaskID: Hashable {
    let rootID: DiskItemID?
    let filter: SelectionListFilter?
}

private struct SelectionListRow: Identifiable {
    let item: DiskItem
    let size: UInt64

    var id: DiskItemID { item.id }
    var name: String { item.displayName }
    var kindName: String { item.kindName ?? "" }
    var parentPath: String { item.url.deletingLastPathComponent().path }
    var fullPath: String { item.path }

    func matches(_ searchText: String, in scope: SelectionListSearchScope) -> Bool {
        switch scope {
        case .all:
            name.localizedCaseInsensitiveContains(searchText)
                || kindName.localizedCaseInsensitiveContains(searchText)
                || fullPath.localizedCaseInsensitiveContains(searchText)
        case .name:
            name.localizedCaseInsensitiveContains(searchText)
        case .kind:
            kindName.localizedCaseInsensitiveContains(searchText)
        case .path:
            fullPath.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private func byteString(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
