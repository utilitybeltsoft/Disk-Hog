import AppKit
import Combine
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
        VStack(spacing: Metrics.windowContentSpacing) {
            AppKitSplitView(
                isVertical: false,
                firstMinimumSize: Metrics.topPaneMinimumHeight,
                secondMinimumSize: Metrics.treemapMinimumHeight,
                firstPreferredFraction: Metrics.topPanePreferredFraction
            ) {
                AppKitSplitView(
                    isVertical: true,
                    firstMinimumSize: Metrics.filesPaneMinimumWidth,
                    secondMinimumSize: Metrics.kindsPaneMinimumWidth,
                    firstPreferredFraction: Metrics.filesPanePreferredFraction
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
            .frame(minWidth: Metrics.treemapMinimumWidth, minHeight: Metrics.splitAreaMinimumHeight)
            .padding(.horizontal, Metrics.mainSplitHorizontalPadding)

            ZStatusFieldsView(session: session)
                .environment(\.selectedScanItem, selectedItemBinding)
                .environment(\.hoveredScanItem, $hoveredItem)
        }
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ScanWindowRegistrationView(source: session.source))
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
            selectionCoordinator.setSelectedItem(session.rootItem)
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

@MainActor
private final class ScanWindowSelectionCoordinator: ObservableObject {
    @Published private(set) var selectedItem: DiskItem?

    func setSelectedItem(_ item: DiskItem?) {
        guard selectedItem !== item else {
            return
        }

        selectedItem = item
    }
}

private enum ScanWindowPane {
    case files
    case kinds
    case treemap
}

private struct ScanWindowKeyObservationView: NSViewRepresentable {
    let onDidBecomeKey: @MainActor () -> Void

    func makeNSView(context: Context) -> ScanWindowKeyObservationNSView {
        ScanWindowKeyObservationNSView(onDidBecomeKey: onDidBecomeKey)
    }

    func updateNSView(_ nsView: ScanWindowKeyObservationNSView, context: Context) {
        nsView.onDidBecomeKey = onDidBecomeKey
    }
}

@MainActor
private final class ScanWindowKeyObservationNSView: NSView {
    var onDidBecomeKey: @MainActor () -> Void
    private weak var observedWindow: NSWindow?
    private var didBecomeKeyObserver: NSObjectProtocol?

    init(onDidBecomeKey: @escaping @MainActor () -> Void) {
        self.onDidBecomeKey = onDidBecomeKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let didBecomeKeyObserver: NSObjectProtocol {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowIfNeeded(window)
    }

    private func observeWindowIfNeeded(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }

        if let didBecomeKeyObserver: NSObjectProtocol {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            self.didBecomeKeyObserver = nil
        }

        observedWindow = window

        guard let window: NSWindow = window else {
            return
        }

        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onDidBecomeKey()
        }

        if window.isKeyWindow {
            DispatchQueue.main.async { [weak self, weak window] in
                guard window?.isKeyWindow == true else {
                    return
                }

                self?.onDidBecomeKey()
            }
        }
    }
}

private struct SelectedScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct HoveredScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct ActiveScanWindowPaneKey: EnvironmentKey {
    static let defaultValue: Binding<ScanWindowPane?> = .constant(nil)
}

private extension EnvironmentValues {
    var selectedScanItem: Binding<DiskItem?> {
        get { self[SelectedScanItemKey.self] }
        set { self[SelectedScanItemKey.self] = newValue }
    }

    var hoveredScanItem: Binding<DiskItem?> {
        get { self[HoveredScanItemKey.self] }
        set { self[HoveredScanItemKey.self] = newValue }
    }

    var activeScanWindowPane: Binding<ScanWindowPane?> {
        get { self[ActiveScanWindowPaneKey.self] }
        set { self[ActiveScanWindowPaneKey.self] = newValue }
    }
}

private struct AppKitSplitView<First: View, Second: View>: NSViewRepresentable {
    let isVertical: Bool
    let firstMinimumSize: CGFloat
    let secondMinimumSize: CGFloat
    let firstPreferredFraction: CGFloat
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isVertical: isVertical,
            firstMinimumSize: firstMinimumSize,
            secondMinimumSize: secondMinimumSize,
            firstPreferredFraction: firstPreferredFraction
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView: NSSplitView = NSSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .paneSplitter
        splitView.delegate = context.coordinator
        splitView.autosaveName = nil

        let firstHostingView: NSHostingView<First> = NSHostingView(rootView: first())
        let secondHostingView: NSHostingView<Second> = NSHostingView(rootView: second())
        firstHostingView.translatesAutoresizingMaskIntoConstraints = false
        secondHostingView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(firstHostingView)
        splitView.addArrangedSubview(secondHostingView)
        context.coordinator.firstHostingView = firstHostingView
        context.coordinator.secondHostingView = secondHostingView
        context.coordinator.scheduleDividerPosition(in: splitView)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.firstMinimumSize = firstMinimumSize
        context.coordinator.secondMinimumSize = secondMinimumSize
        context.coordinator.firstPreferredFraction = firstPreferredFraction
        context.coordinator.isVertical = isVertical
        context.coordinator.scheduleDividerPosition(in: splitView)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var isVertical: Bool
        var firstMinimumSize: CGFloat
        var secondMinimumSize: CGFloat
        var firstPreferredFraction: CGFloat
        weak var firstHostingView: NSHostingView<First>?
        weak var secondHostingView: NSHostingView<Second>?
        private var didSetInitialDividerPosition: Bool = false

        init(
            isVertical: Bool,
            firstMinimumSize: CGFloat,
            secondMinimumSize: CGFloat,
            firstPreferredFraction: CGFloat
        ) {
            self.isVertical = isVertical
            self.firstMinimumSize = firstMinimumSize
            self.secondMinimumSize = secondMinimumSize
            self.firstPreferredFraction = firstPreferredFraction
        }

        func scheduleDividerPosition(in splitView: NSSplitView) {
            guard !didSetInitialDividerPosition else {
                return
            }

            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self: Coordinator = self,
                      let splitView: NSSplitView = splitView,
                      !self.didSetInitialDividerPosition else {
                    return
                }

                let availableSize: CGFloat = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
                guard availableSize > self.firstMinimumSize + self.secondMinimumSize else {
                    return
                }

                let proposedPosition: CGFloat = availableSize * self.firstPreferredFraction
                let minimumPosition: CGFloat = self.firstMinimumSize
                let maximumPosition: CGFloat = availableSize - self.secondMinimumSize
                let position: CGFloat = min(max(proposedPosition, minimumPosition), maximumPosition)
                splitView.setPosition(position, ofDividerAt: 0)
                self.didSetInitialDividerPosition = true
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            firstMinimumSize
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let availableSize: CGFloat = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            return max(firstMinimumSize, availableSize - secondMinimumSize)
        }
    }
}

private struct FilesPaneView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        DiskItemOutlineView(
            rootItem: session.rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .files)
        }
    }
}

private struct DiskItemOutlineView: NSViewRepresentable {
    let rootItem: DiskItem?
    let usePhysicalSize: Bool
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let activePane: Binding<ScanWindowPane?>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            usePhysicalSize: usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView: NSOutlineView = NSOutlineView()
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = Metrics.tableRowHeight
        outlineView.intercellSpacing = NSSize(width: Metrics.tableIntercellWidth, height: Metrics.tableIntercellHeight)
        outlineView.indentationPerLevel = Metrics.outlineIndentWidth
        outlineView.allowsMultipleSelection = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .controlBackgroundColor

        let nameColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.name)
        nameColumn.title = "Name"
        nameColumn.minWidth = Metrics.outlineNameColumnMinimumWidth
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.size)
        sizeColumn.title = "Size"
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = Metrics.filesSizeColumnWidth
        sizeColumn.minWidth = Metrics.filesSizeColumnWidth
        sizeColumn.resizingMask = .userResizingMask
        outlineView.addTableColumn(sizeColumn)

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClick(_:))

        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(rootItem: rootItem)
        context.coordinator.observeSelection()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.selectionCoordinator = selectionCoordinator
        context.coordinator.activePane = activePane
        context.coordinator.updateSizeMode(usePhysicalSize)
        context.coordinator.reloadIfNeeded(rootItem: rootItem)
        context.coordinator.syncSelectionIfNeeded(selectionCoordinator.selectedItem)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private var usePhysicalSize: Bool
        var selectionCoordinator: ScanWindowSelectionCoordinator
        var activePane: Binding<ScanWindowPane?>
        weak var outlineView: NSOutlineView?
        private var rootItem: DiskItem?
        private var isApplyingSelection: Bool = false
        private var selectionCancellable: AnyCancellable?

        init(
            usePhysicalSize: Bool,
            selectionCoordinator: ScanWindowSelectionCoordinator,
            activePane: Binding<ScanWindowPane?>
        ) {
            self.usePhysicalSize = usePhysicalSize
            self.selectionCoordinator = selectionCoordinator
            self.activePane = activePane
        }

        func observeSelection() {
            selectionCancellable = selectionCoordinator.$selectedItem.sink { [weak self] item in
                self?.syncSelectionIfNeeded(item)
            }
        }

        func reloadIfNeeded(rootItem: DiskItem?) {
            guard self.rootItem !== rootItem else {
                return
            }

            reload(rootItem: rootItem)
        }

        func reload(rootItem: DiskItem?) {
            self.rootItem = rootItem
            outlineView?.reloadData()
            if let rootItem: DiskItem = rootItem {
                outlineView?.expandItem(rootItem)
            }
        }

        func updateSizeMode(_ usePhysicalSize: Bool) {
            guard self.usePhysicalSize != usePhysicalSize else {
                return
            }

            self.usePhysicalSize = usePhysicalSize
            outlineView?.reloadData()
        }

        func syncSelectionIfNeeded(_ item: DiskItem?) {
            guard let outlineView: NSOutlineView = outlineView else {
                return
            }

            guard let item: DiskItem = item else {
                isApplyingSelection = true
                outlineView.deselectAll(nil)
                isApplyingSelection = false
                return
            }

            if outlineView.item(atRow: outlineView.selectedRow) as? DiskItem === item {
                return
            }

            expandAncestors(of: item)
            let row: Int = outlineView.row(forItem: item)
            guard row >= 0 else {
                isApplyingSelection = true
                outlineView.deselectAll(nil)
                isApplyingSelection = false
                return
            }

            isApplyingSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            isApplyingSelection = false
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item: DiskItem = item as? DiskItem else {
                return rootItem == nil ? 0 : 1
            }

            return item.childCount
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item: DiskItem = item as? DiskItem else {
                return rootItem!
            }

            return item.child(at: index)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item: DiskItem = item as? DiskItem else {
                return false
            }

            return item.childCount > 0
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item: DiskItem = item as? DiskItem,
                  let tableColumn: NSTableColumn = tableColumn else {
                return nil
            }

            if tableColumn.identifier == ColumnID.size {
                return sizeCell(for: item, outlineView: outlineView)
            }

            return nameCell(for: item, outlineView: outlineView)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let outlineView: NSOutlineView = outlineView else {
                return
            }

            activePane.wrappedValue = .files
            selectionCoordinator.setSelectedItem(outlineView.selectedRow >= 0 ? outlineView.item(atRow: outlineView.selectedRow) as? DiskItem : nil)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is DiskItem
        }

        func outlineView(_ outlineView: NSOutlineView, mouseDownInHeaderOf tableColumn: NSTableColumn) {}

        @objc func doubleClick(_ sender: Any?) {
            guard let outlineView: NSOutlineView = outlineView,
                  outlineView.clickedRow >= 0,
                  let item: DiskItem = outlineView.item(atRow: outlineView.clickedRow) as? DiskItem,
                  item.childCount > 0 else {
                return
            }

            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }

        private func expandAncestors(of item: DiskItem) {
            var ancestors: [DiskItem] = []
            var ancestor: DiskItem? = item.parent
            while let currentAncestor: DiskItem = ancestor {
                ancestors.append(currentAncestor)
                ancestor = currentAncestor.parent
            }

            for ancestor: DiskItem in ancestors.reversed() {
                outlineView?.expandItem(ancestor)
            }
        }

        private func nameCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = CellID.name
            let cell: DiskItemNameCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemNameCellView ?? DiskItemNameCellView()
            cell.identifier = identifier
            cell.configure(item: item)
            return cell
        }

        private func sizeCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = CellID.size
            let cell: DiskItemSizeCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemSizeCellView ?? DiskItemSizeCellView()
            cell.identifier = identifier
            cell.configure(item: item, usePhysicalSize: usePhysicalSize)
            return cell
        }
    }

    private final class DiskItemNameCellView: NSTableCellView {
        private let iconImageView: NSImageView = NSImageView()
        private let titleTextField: NSTextField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(item: DiskItem) {
            iconImageView.image = NSWorkspace.shared.icon(forFile: item.path)
            titleTextField.stringValue = item.displayName
        }

        private func setup() {
            imageView = iconImageView
            textField = titleTextField
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            titleTextField.translatesAutoresizingMaskIntoConstraints = false
            titleTextField.lineBreakMode = .byClipping
            titleTextField.font = NSFont.systemFont(ofSize: Metrics.tableFontSize)
            addSubview(iconImageView)
            addSubview(titleTextField)
            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.outlineCellHorizontalPadding),
                iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: Metrics.outlineIconWidth),
                iconImageView.heightAnchor.constraint(equalToConstant: Metrics.outlineIconWidth),
                titleTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Metrics.outlineIconTextSpacing),
                titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.outlineCellHorizontalPadding),
                titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    private final class DiskItemSizeCellView: NSTableCellView {
        private let sizeTextField: NSTextField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(item: DiskItem, usePhysicalSize: Bool) {
            sizeTextField.stringValue = ByteCountFormatter.string(fromByteCount: Int64(item.sizeValue(usePhysicalSize: usePhysicalSize)), countStyle: .file)
        }

        private func setup() {
            textField = sizeTextField
            sizeTextField.alignment = .right
            sizeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: Metrics.tableFontSize, weight: .regular)
            sizeTextField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sizeTextField)
            NSLayoutConstraint.activate([
                sizeTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.outlineCellHorizontalPadding),
                sizeTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.outlineCellHorizontalPadding),
                sizeTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    fileprivate enum ColumnID {
        static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("name")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("size")
    }

    private enum CellID {
        static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("nameCell")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("sizeCell")
    }
}

private struct KindsPaneView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.activeScanWindowPane) private var activePane
    @State private var kindStatistics: [TreemapKindStatistic] = []
    @State private var selectedKindName: String?

    var body: some View {
        KindStatisticTableView(
            statistics: kindStatistics,
            selectedKindName: $selectedKindName,
            activePane: activePane
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PaneBorderView(isActive: activePane.wrappedValue == .kinds)
        }
        .onAppear {
            updateKindStatistics()
        }
        .onChange(of: session.rootItem?.id) {
            updateKindStatistics()
        }
        .onChange(of: selectedItem.wrappedValue?.id) {
            updateSelectedKindName()
        }
    }

    private func updateKindStatistics() {
        guard let rootItem: DiskItem = session.rootItem else {
            kindStatistics = []
            return
        }

        kindStatistics = session.presentationMetrics?.kindStatistics ?? TreemapDiskItemDataSource.kindStatistics(
            for: rootItem,
            usePhysicalSize: session.scanSettings.usePhysicalSize
        )
        updateSelectedKindName()
    }

    private func updateSelectedKindName() {
        guard let item: DiskItem = selectedItem.wrappedValue,
              !item.isFolder,
              let kindName: String = item.kindName,
              kindStatistics.contains(where: { $0.kindName == kindName }) else {
            selectedKindName = nil
            return
        }

        selectedKindName = kindName
    }
}

private struct KindStatisticTableView: NSViewRepresentable {
    let statistics: [TreemapKindStatistic]
    let selectedKindName: Binding<String?>
    let activePane: Binding<ScanWindowPane?>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            statistics: statistics,
            selectedKindName: selectedKindName,
            activePane: activePane
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView: NSTableView = NSTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = Metrics.tableRowHeight
        tableView.intercellSpacing = NSSize(width: Metrics.tableIntercellWidth, height: Metrics.tableIntercellHeight)
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.backgroundColor = .controlBackgroundColor
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let colorColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.color)
        colorColumn.title = "Color"
        colorColumn.width = Metrics.kindColorColumnWidth
        colorColumn.minWidth = Metrics.kindColorColumnMinimumWidth
        colorColumn.resizingMask = .userResizingMask
        tableView.addTableColumn(colorColumn)

        let kindColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.kind)
        kindColumn.title = "Kind"
        kindColumn.minWidth = Metrics.kindNameColumnMinimumWidth
        kindColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.kindName,
            ascending: true,
            selector: #selector(NSString.localizedStandardCompare(_:))
        )
        tableView.addTableColumn(kindColumn)

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.size)
        sizeColumn.title = "Size"
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = Metrics.kindSizeColumnWidth
        sizeColumn.minWidth = Metrics.kindSizeColumnWidth
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.size,
            ascending: true
        )
        tableView.addTableColumn(sizeColumn)

        let filesColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.files)
        filesColumn.title = "Files"
        filesColumn.headerCell.alignment = .right
        filesColumn.width = Metrics.kindFilesColumnWidth
        filesColumn.minWidth = Metrics.kindFilesColumnWidth
        filesColumn.resizingMask = .userResizingMask
        filesColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.fileCount,
            ascending: true
        )
        tableView.addTableColumn(filesColumn)
        tableView.sortDescriptors = [
            NSSortDescriptor(key: KindSortKey.size, ascending: false)
        ]

        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.applySortDescriptors(tableView.sortDescriptors)
        context.coordinator.syncSelectionIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.statistics = statistics
        context.coordinator.selectedKindName = selectedKindName
        context.coordinator.activePane = activePane
        context.coordinator.applySortDescriptors(context.coordinator.tableView?.sortDescriptors ?? [])
        context.coordinator.tableView?.reloadData()
        context.coordinator.syncSelectionIfNeeded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var statistics: [TreemapKindStatistic]
        var selectedKindName: Binding<String?>
        var activePane: Binding<ScanWindowPane?>
        weak var tableView: NSTableView?
        private var sortedStatistics: [TreemapKindStatistic] = []
        private var isApplyingSelection: Bool = false

        init(
            statistics: [TreemapKindStatistic],
            selectedKindName: Binding<String?>,
            activePane: Binding<ScanWindowPane?>
        ) {
            self.statistics = statistics
            self.selectedKindName = selectedKindName
            self.activePane = activePane
            self.sortedStatistics = statistics
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            sortedStatistics.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn: NSTableColumn = tableColumn,
                  sortedStatistics.indices.contains(row) else {
                return nil
            }

            let statistic: TreemapKindStatistic = sortedStatistics[row]
            switch tableColumn.identifier {
            case KindColumnID.color:
                return colorCell(for: statistic, tableView: tableView)
            case KindColumnID.size:
                return textCell(
                    string: ByteCountFormatter.string(fromByteCount: Int64(statistic.size), countStyle: .file),
                    alignment: .right,
                    identifier: KindCellID.size,
                    tableView: tableView
                )
            case KindColumnID.files:
                return textCell(
                    string: "\(statistic.fileCount)",
                    alignment: .right,
                    identifier: KindCellID.files,
                    tableView: tableView
                )
            default:
                return textCell(
                    string: statistic.kindName,
                    alignment: .left,
                    identifier: KindCellID.kind,
                    tableView: tableView
                )
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView: NSTableView = tableView else {
                return
            }

            activePane.wrappedValue = .kinds
            guard tableView.selectedRow >= 0,
                  sortedStatistics.indices.contains(tableView.selectedRow) else {
                selectedKindName.wrappedValue = nil
                return
            }

            selectedKindName.wrappedValue = sortedStatistics[tableView.selectedRow].kindName
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            applySortDescriptors(tableView.sortDescriptors)
            tableView.reloadData()
            syncSelectionIfNeeded(scrollToSelection: false)
            if !sortedStatistics.isEmpty {
                tableView.scrollRowToVisible(0)
            }
        }

        func syncSelectionIfNeeded(scrollToSelection: Bool = true) {
            guard let tableView: NSTableView = tableView else {
                return
            }

            guard let selectedKindName: String = selectedKindName.wrappedValue,
                  let selectedRow: Int = sortedStatistics.firstIndex(where: { statistic in
                      statistic.kindName == selectedKindName
                  }) else {
                isApplyingSelection = true
                tableView.deselectAll(nil)
                isApplyingSelection = false
                return
            }

            if tableView.selectedRow == selectedRow {
                return
            }

            isApplyingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            if scrollToSelection {
                tableView.scrollRowToVisible(selectedRow)
            }
            isApplyingSelection = false
        }

        func applySortDescriptors(_ sortDescriptors: [NSSortDescriptor]) {
            guard let sortDescriptor: NSSortDescriptor = sortDescriptors.first,
                  let key: String = sortDescriptor.key else {
                sortedStatistics = statistics
                return
            }

            let ascending: Bool = sortDescriptor.ascending
            sortedStatistics = statistics.sorted { leftStatistic, rightStatistic in
                switch key {
                case KindSortKey.kindName:
                    let comparison: ComparisonResult = leftStatistic.kindName.localizedStandardCompare(rightStatistic.kindName)
                    return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                case KindSortKey.fileCount:
                    return ascending ? leftStatistic.fileCount < rightStatistic.fileCount : leftStatistic.fileCount > rightStatistic.fileCount
                default:
                    return ascending ? leftStatistic.size < rightStatistic.size : leftStatistic.size > rightStatistic.size
                }
            }
        }

        private func colorCell(for statistic: TreemapKindStatistic, tableView: NSTableView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = KindCellID.color
            let cell: KindColorCellView = tableView.makeView(withIdentifier: identifier, owner: self) as? KindColorCellView ?? KindColorCellView()
            cell.identifier = identifier
            cell.configure(color: statistic.color)
            return cell
        }

        private func textCell(
            string: String,
            alignment: NSTextAlignment,
            identifier: NSUserInterfaceItemIdentifier,
            tableView: NSTableView
        ) -> NSTableCellView {
            let cell: KindTextCellView = tableView.makeView(withIdentifier: identifier, owner: self) as? KindTextCellView ?? KindTextCellView()
            cell.identifier = identifier
            cell.configure(string: string, alignment: alignment)
            return cell
        }
    }

    private final class KindColorCellView: NSTableCellView {
        private let swatchView: NSImageView = NSImageView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(color: NSColor) {
            swatchView.image = Self.swatchImage(color: color)
        }

        private func setup() {
            imageView = swatchView
            swatchView.translatesAutoresizingMaskIntoConstraints = false
            swatchView.imageScaling = .scaleAxesIndependently
            addSubview(swatchView)
            NSLayoutConstraint.activate([
                swatchView.leadingAnchor.constraint(equalTo: leadingAnchor),
                swatchView.trailingAnchor.constraint(equalTo: trailingAnchor),
                swatchView.topAnchor.constraint(equalTo: topAnchor),
                swatchView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        private static func swatchImage(color: NSColor) -> NSImage {
            let imageSize: NSSize = NSSize(
                width: Metrics.kindColorColumnWidth,
                height: Metrics.tableRowHeight
            )
            let bitmap: NSBitmapImageRep = NSBitmapImageRep(
                treemapRGBBitmapWithWidth: Int(imageSize.width),
                height: Int(imageSize.height)
            )
            let renderer: TreemapCushionRenderer = TreemapCushionRenderer(
                rect: NSRect(origin: .zero, size: imageSize)
            )
            renderer.setColor(color)
            renderer.addRidgeByHeightFactor(Metrics.kindSwatchCushionRidgeHeightFactor)
            renderer.renderCushion(in: bitmap)
            bitmap.size = imageSize
            return bitmap.treemapSuitableImage()
        }
    }

    private final class KindTextCellView: NSTableCellView {
        private let text: NSTextField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(string: String, alignment: NSTextAlignment) {
            text.stringValue = string
            text.alignment = alignment
        }

        private func setup() {
            textField = text
            text.font = NSFont.systemFont(ofSize: Metrics.tableFontSize)
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.tableCellHorizontalPadding),
                text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.tableCellHorizontalPadding),
                text.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    private enum KindColumnID {
        static let color: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("color")
        static let kind: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kind")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("size")
        static let files: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("files")
    }

    private enum KindCellID {
        static let color: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindColorCell")
        static let kind: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindTextCell")
        static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindSizeCell")
        static let files: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindFilesCell")
    }

    private enum KindSortKey {
        static let kindName: String = "kindName"
        static let size: String = "size"
        static let fileCount: String = "fileCount"
    }
}

private struct PaneBorderView: View {
    let isActive: Bool

    var body: some View {
        Rectangle()
            .stroke(
                isActive ? Color(nsColor: .systemBlue) : Color(nsColor: .gridColor),
                lineWidth: isActive ? Metrics.activePaneBorderWidth : Metrics.inactivePaneBorderWidth
            )
            .allowsHitTesting(false)
    }
}

private struct TreemapPanelView: View {
    @ObservedObject var session: ScanSession
    let selectionCoordinator: ScanWindowSelectionCoordinator
    @Environment(\.hoveredScanItem) private var hoveredItem
    @Environment(\.activeScanWindowPane) private var activePane

    var body: some View {
        ZStack {
            AppKitTreemapView(
                source: session.source,
                rootItem: session.rootItem,
                presentationMetrics: session.presentationMetrics,
                selectionCoordinator: selectionCoordinator,
                hoveredItem: hoveredItem,
                activePane: activePane
            )
            .overlay {
                PaneBorderView(isActive: activePane.wrappedValue == .treemap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppKitTreemapView: NSViewRepresentable {
    let source: ScanSource
    let rootItem: DiskItem?
    let presentationMetrics: TreemapPresentationMetrics?
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let hoveredItem: Binding<DiskItem?>
    let activePane: Binding<ScanWindowPane?>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectionCoordinator: selectionCoordinator,
            hoveredItem: hoveredItem,
            activePane: activePane
        )
    }

    func makeNSView(context: Context) -> ZStyleTreemapNSView {
        let view: ZStyleTreemapNSView = ZStyleTreemapNSView()
        view.onSelectItem = { item in
            context.coordinator.activePane.wrappedValue = .treemap
            context.coordinator.selectionCoordinator.setSelectedItem(item)
        }
        view.onHoverItem = { item in
            context.coordinator.hoveredItem.wrappedValue = item
        }
        context.coordinator.view = view
        context.coordinator.observeSelection()
        view.configure(source: source, rootItem: rootItem, presentationMetrics: presentationMetrics, selectedItem: selectionCoordinator.selectedItem)
        return view
    }

    func updateNSView(_ nsView: ZStyleTreemapNSView, context: Context) {
        context.coordinator.selectionCoordinator = selectionCoordinator
        context.coordinator.hoveredItem = hoveredItem
        context.coordinator.activePane = activePane
        nsView.configure(source: source, rootItem: rootItem, presentationMetrics: presentationMetrics, selectedItem: selectionCoordinator.selectedItem)
    }

    final class Coordinator {
        var selectionCoordinator: ScanWindowSelectionCoordinator
        var hoveredItem: Binding<DiskItem?>
        var activePane: Binding<ScanWindowPane?>
        weak var view: ZStyleTreemapNSView?
        private var selectionCancellable: AnyCancellable?

        init(
            selectionCoordinator: ScanWindowSelectionCoordinator,
            hoveredItem: Binding<DiskItem?>,
            activePane: Binding<ScanWindowPane?>
        ) {
            self.selectionCoordinator = selectionCoordinator
            self.hoveredItem = hoveredItem
            self.activePane = activePane
        }

        func observeSelection() {
            selectionCancellable = selectionCoordinator.$selectedItem.sink { [weak self] item in
                self?.view?.applySelectedItem(item)
            }
        }
    }
}

private final class ZStyleTreemapNSView: NSView {
    var onSelectItem: ((DiskItem?) -> Void)?
    var onHoverItem: ((DiskItem?) -> Void)?

    private var source: ScanSource?
    private var rootItem: DiskItem?
    private var presentationMetrics: TreemapPresentationMetrics?
    private var selectedItem: DiskItem?
    private var renderer: TreemapViewRenderer?
    private var rendererDataSource: TreemapDiskItemDataSource?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func configure(source: ScanSource, rootItem: DiskItem?, presentationMetrics: TreemapPresentationMetrics?, selectedItem: DiskItem?) {
        self.source = source

        if self.rootItem !== rootItem || self.presentationMetrics !== presentationMetrics {
            self.rootItem = rootItem
            self.presentationMetrics = presentationMetrics
            rebuildRenderer()
        }

        if self.selectedItem !== selectedItem {
            self.selectedItem = selectedItem
            syncSelectionToRenderer()
            needsDisplay = true
        }
    }

    func applySelectedItem(_ selectedItem: DiskItem?) {
        guard self.selectedItem !== selectedItem else {
            return
        }

        self.selectedItem = selectedItem
        syncSelectionToRenderer()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingArea: NSTrackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let trackingArea: NSTrackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rootItem: DiskItem = rootItem else {
            drawPlaceholder(in: dirtyRect)
            return
        }

        guard bounds.width >= Metrics.minimumRenderableTreemapSide,
              bounds.height >= Metrics.minimumRenderableTreemapSide else {
            return
        }

        if inLiveResize {
            if drawCachedImage(in: bounds, sourceRect: nil, fraction: Metrics.treemapLiveResizeImageFraction) == false {
                NSColor.windowBackgroundColor.setFill()
                dirtyRect.fill()
            }
            return
        }

        let viewBounds: NSRect = bounds
        if renderer == nil {
            rebuildRenderer()
        }

        if renderer?.rootCellID?.rect != viewBounds {
            renderer?.calcLayout(viewBounds)
            syncSelectionToRenderer()
            Self.writeTreemapBoundsDiagnostics(rootItem: rootItem, size: viewBounds.size)
            #if TREEMAP_LAYOUT_DIAGNOSTICS
            if let renderer: TreemapViewRenderer = renderer {
                Self.writeTreemapLayoutDiagnostics(rootItem: rootItem, size: viewBounds.size, renderer: renderer)
                Self.writeTreemapLayoutDiagnosticsUsingZBoundsIfAvailable(rootItem: rootItem)
            }
            #endif
        }

        _ = drawCachedImage(in: dirtyRect, sourceRect: dirtyRect, fraction: 1)
        drawSelection()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        discardTrackingAreas()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateTrackingAreas()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverItem?(hitResult(for: event.locationInWindow)?.item)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverItem?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let result: TreemapHitResult = hitResult(for: event.locationInWindow) else {
            return
        }

        renderer?.selectItem(by: result.cellID)
        selectedItem = result.item
        onSelectItem?(result.item)
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let item: DiskItem? = hitResult(for: event.locationInWindow)?.item ?? selectedItem
        let menu: NSMenu = NSMenu()

        guard let item: DiskItem = item, item.isSpecialItem == false else {
            let noItem: NSMenuItem = NSMenuItem(title: "No Item Selected", action: nil, keyEquivalent: "")
            noItem.isEnabled = false
            menu.addItem(noItem)
            return menu
        }

        menu.addItem(NSMenuItem(title: "Open", action: #selector(openMenuItem(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal in Finder", action: #selector(revealMenuItem(_:)), keyEquivalent: ""))
        menu.items.forEach { menuItem in
            menuItem.target = self
            menuItem.representedObject = item
        }
        return menu
    }

    @objc private func openMenuItem(_ sender: NSMenuItem) {
        guard let item: DiskItem = sender.representedObject as? DiskItem else {
            return
        }

        DiskItemWorkspaceActions.open(item)
    }

    @objc private func revealMenuItem(_ sender: NSMenuItem) {
        guard let item: DiskItem = sender.representedObject as? DiskItem else {
            return
        }

        DiskItemWorkspaceActions.revealInFinder(item)
    }

    private func rebuildRenderer() {
        guard let rootItem: DiskItem = rootItem else {
            renderer = nil
            rendererDataSource = nil
            needsDisplay = true
            return
        }

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: rootItem,
            usePhysicalSize: source?.scanSettings?.usePhysicalSize ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize,
            presentationMetrics: presentationMetrics
        )
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        rendererDataSource = dataSource
        self.renderer = renderer
        syncSelectionToRenderer()
        needsDisplay = true
    }

    private func syncSelectionToRenderer() {
        guard let item: DiskItem = selectedItem,
              let rootItem: DiskItem = rootItem,
              item.pathFromRoot().first === rootItem else {
            renderer?.selectItem(by: nil)
            return
        }

        if renderer?.selectItem(byRenderedItem: item) == false {
            let path: [DiskItem] = item.pathFromRoot()
            renderer?.selectItem(byPathToItem: path)
        }
    }

    private func drawCachedImage(in destinationRect: NSRect, sourceRect: NSRect?, fraction: CGFloat) -> Bool {
        guard let imageRep: NSBitmapImageRep = renderer?.drawInCache(
            size: bounds.size,
            scale: window?.backingScaleFactor ?? 1,
            colorSpace: window?.colorSpace
        ) else {
            return false
        }

        let image: NSImage = imageRep.treemapSuitableImage()
        let imageSize: NSSize = image.size
        let sourceRect: NSRect = sourceRect ?? NSRect(origin: .zero, size: imageSize)
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .copy,
            fraction: fraction,
            respectFlipped: true,
            hints: nil
        )
        return true
    }

    private func drawSelection() {
        guard let selectedCellID: TreemapItemRenderer = renderer?.selectedCellID else {
            return
        }

        let rect: NSRect = visibleSelectionRect(for: renderer?.itemRect(by: selectedCellID) ?? .zero)
        guard rect != .zero else {
            return
        }

        NSColor.black.setStroke()
        stroke(rect: rect, lineWidth: Metrics.treemapSelectionOuterLineWidth)
        NSColor.white.setStroke()
        stroke(rect: rect, lineWidth: Metrics.treemapSelectionMiddleLineWidth)
        NSColor.yellow.setStroke()
        stroke(rect: rect, lineWidth: Metrics.treemapSelectionInnerLineWidth)
    }

    private func stroke(rect: NSRect, lineWidth: CGFloat) {
        let path: NSBezierPath = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func visibleSelectionRect(for rect: NSRect) -> NSRect {
        let visibleWidth: CGFloat = min(max(rect.width, Metrics.treemapMinimumSelectionSide), bounds.width)
        let visibleHeight: CGFloat = min(max(rect.height, Metrics.treemapMinimumSelectionSide), bounds.height)
        let visibleOriginX: CGFloat = min(max(rect.midX - visibleWidth / 2, bounds.minX), bounds.maxX - visibleWidth)
        let visibleOriginY: CGFloat = min(max(rect.midY - visibleHeight / 2, bounds.minY), bounds.maxY - visibleHeight)
        return NSRect(x: visibleOriginX, y: visibleOriginY, width: visibleWidth, height: visibleHeight)
    }

    private func hitResult(for windowLocation: NSPoint) -> TreemapHitResult? {
        let point: NSPoint = convert(windowLocation, from: nil)
        guard let cellID: TreemapItemRenderer = renderer?.cellID(by: point, inViewCoordinates: false),
              let item: DiskItem = renderer?.item(by: cellID),
              !item.isSpecialItem else {
            return nil
        }

        return TreemapHitResult(item: item, cellID: cellID)
    }

    private func drawPlaceholder(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard let source: ScanSource = source else {
            return
        }

        let paragraphStyle: NSMutableParagraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Metrics.placeholderTitleFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let pathAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Metrics.placeholderPathFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect: NSRect = NSRect(x: bounds.minX + Metrics.placeholderPadding, y: bounds.midY - Metrics.placeholderTitleYOffset, width: bounds.width - Metrics.placeholderPadding * 2, height: Metrics.placeholderLineHeight)
        let pathRect: NSRect = NSRect(x: bounds.minX + Metrics.placeholderPadding, y: titleRect.maxY + Metrics.placeholderSpacing, width: bounds.width - Metrics.placeholderPadding * 2, height: Metrics.placeholderLineHeight)
        NSString(string: "Treemap").draw(in: titleRect, withAttributes: titleAttributes)
        NSString(string: source.path).draw(in: pathRect, withAttributes: pathAttributes)
    }

    private func discardTrackingAreas() {
        if let trackingArea: NSTrackingArea = trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }

    private static func writeTreemapBoundsDiagnostics(rootItem: DiskItem, size: CGSize) {
        #if TREEMAP_LAYOUT_DIAGNOSTICS
        let diagnostics: [String: Any] = [
            "app": "Disk Hog",
            "recordType": "treemap-bounds",
            "rootDisplayName": rootItem.displayName,
            "rootPath": rootItem.path,
            "pointX": 0,
            "pointY": 0,
            "pointWidth": Double(size.width),
            "pointHeight": Double(size.height),
            "layoutX": 0,
            "layoutY": 0,
            "layoutWidth": Double(size.width),
            "layoutHeight": Double(size.height),
            "pointAspect": size.height == 0 ? 0 : Double(size.width / size.height),
            "layoutAspect": size.height == 0 ? 0 : Double(size.width / size.height),
            "timestamp": Date().timeIntervalSince1970
        ]
        let outputURL: URL = URL(fileURLWithPath: "/tmp/diskhog-treemap-bounds.json")

        do {
            let data: Data = try JSONSerialization.data(
                withJSONObject: diagnostics,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: outputURL, options: .atomic)
        } catch {
            NSLog("Disk Hog treemap bounds diagnostics failed: \(String(describing: error))")
        }
        #endif
    }

    private static func writeTreemapLayoutDiagnostics(rootItem: DiskItem, size: CGSize, renderer: TreemapViewRenderer) {
        let outputURL: URL = URL(fileURLWithPath: "/tmp/diskhog-treemap-layout.jsonl")
        writeTreemapLayoutDiagnostics(rootItem: rootItem, size: size, renderer: renderer, outputURL: outputURL)
    }

    private static func writeTreemapLayoutDiagnostics(rootItem: DiskItem, size: CGSize, renderer: TreemapViewRenderer, outputURL: URL) {
        var lines: [String] = []
        let metadata: [String: Any] = [
            "app": "Disk Hog",
            "recordType": "metadata",
            "rootDisplayName": rootItem.displayName,
            "rootPath": rootItem.path,
            "layoutWidth": Double(size.width),
            "layoutHeight": Double(size.height),
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            lines.append(try jsonLine(for: metadata))
            for row: [String: Any] in renderer.layoutDiagnosticsRows() {
                lines.append(try jsonLine(for: row))
            }
            try lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Disk Hog treemap layout diagnostics failed: \(String(describing: error))")
        }
    }

    private static func writeTreemapLayoutDiagnosticsUsingZBoundsIfAvailable(rootItem: DiskItem) {
        let zBoundsURL: URL = URL(fileURLWithPath: "/tmp/disk-inventory-z-treemap-bounds.json")
        guard let data: Data = try? Data(contentsOf: zBoundsURL),
              let object: Any = try? JSONSerialization.jsonObject(with: data),
              let diagnostics: [String: Any] = object as? [String: Any],
              let width: Double = numericValue(from: diagnostics["layoutWidth"]),
              let height: Double = numericValue(from: diagnostics["layoutHeight"]),
              width >= Metrics.minimumRenderableTreemapSide,
              height >= Metrics.minimumRenderableTreemapSide else {
            return
        }

        let size: CGSize = CGSize(width: width, height: height)
        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: rootItem)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        renderer.calcLayout(NSRect(origin: .zero, size: size))
        writeTreemapLayoutDiagnostics(
            rootItem: rootItem,
            size: size,
            renderer: renderer,
            outputURL: URL(fileURLWithPath: "/tmp/diskhog-treemap-layout-zbounds.jsonl")
        )
    }

    private static func numericValue(from value: Any?) -> Double? {
        if let doubleValue: Double = value as? Double {
            return doubleValue
        }

        if let intValue: Int = value as? Int {
            return Double(intValue)
        }

        if let numberValue: NSNumber = value as? NSNumber {
            return numberValue.doubleValue
        }

        return nil
    }

    private static func jsonLine(for dictionary: [String: Any]) throws -> String {
        let data: Data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct TreemapHitResult {
    let item: DiskItem
    let cellID: TreemapItemRenderer
}

private struct ZStatusFieldsView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.selectedScanItem) private var selectedItem
    @Environment(\.hoveredScanItem) private var hoveredItem

    var body: some View {
        TimelineView(.periodic(from: Date(), by: Metrics.timerRefreshInterval)) { context in
            HStack(alignment: .top, spacing: Metrics.statusFieldControlSpacing) {
                VStack(alignment: .leading, spacing: Metrics.statusFieldSpacing) {
                    Text(selectedStatusLine)
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let hoverStatusLine: String = hoverStatusLine {
                        Text(hoverStatusLine)
                            .lineLimit(Metrics.singleLineLimit)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text(progressSummary(referenceDate: context.date))
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(scanTotalsSummary(referenceDate: context.date))
                        .lineLimit(Metrics.singleLineLimit)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if session.state == .scanning {
                    Button {
                        session.cancel()
                    } label: {
                        Label("Cancel Scan", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                    .help("Cancel Scan")
                }
            }
            .font(.system(size: Metrics.statusFieldFontSize))
            .padding(.horizontal, Metrics.statusFieldHorizontalPadding)
            .padding(.bottom, Metrics.statusFieldBottomPadding)
            .frame(height: Metrics.statusFieldHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedStatusLine: String {
        if let selectedItem: DiskItem = selectedItem.wrappedValue {
            return statusLine(prefix: "Selected", item: selectedItem)
        }

        return session.currentPath
    }

    private var hoverStatusLine: String? {
        if let hoveredItem: DiskItem = hoveredItem.wrappedValue {
            return statusLine(prefix: "Hovering on", item: hoveredItem)
        }

        return nil
    }

    private func statusLine(prefix: String, item: DiskItem) -> String {
        let size: String = ByteCountFormatter.string(
            fromByteCount: Int64(item.sizeValue(usePhysicalSize: session.scanSettings.usePhysicalSize)),
            countStyle: .file
        )
        if let kindName: String = item.kindName, !kindName.isEmpty {
            return "\(prefix): \(item.path), \(kindName), \(size)"
        }

        return "\(prefix): \(item.path), \(size)"
    }

    private func progressSummary(referenceDate: Date) -> String {
        switch session.state {
        case .complete:
            if let completedAt: Date = session.completedAt {
                return "Scan complete at \(Self.dateTimeFormatter.string(from: completedAt))"
            }

            return "Scan complete"
        case .ready, .scanning, .cancelled, .failed:
            return session.state.title
        }
    }

    private func scanTotalsSummary(referenceDate: Date) -> String {
        let elapsedTime: String = DurationFormatter.scanDuration(session.elapsedTime(referenceDate: referenceDate))
        let scannedSize: String = ByteCountFormatter.string(fromByteCount: Int64(session.scannedByteCount), countStyle: .file)
        return "\(session.scannedItemCount) items - \(session.scannedFolderCount) folders - \(session.scannedFileCount) files - \(scannedSize) - elapsed \(elapsedTime)"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum ScanWindowMetrics {
    static let windowContentSpacing: CGFloat = 4
    static let timerRefreshInterval: TimeInterval = 1
    static let filesPaneMinimumWidth: CGFloat = 480
    static let filesPanePreferredFraction: CGFloat = 590.0 / 980.0
    static let kindsPaneMinimumWidth: CGFloat = 240
    static let topPaneMinimumHeight: CGFloat = 240
    static let topPanePreferredFraction: CGFloat = 460.0 / 930.0
    static let treemapMinimumWidth: CGFloat = 817
    static let treemapMinimumHeight: CGFloat = 300
    static let splitAreaMinimumHeight: CGFloat = 930
    static let windowMinimumWidth: CGFloat = ScanWindowGeometry.minimumWidth
    static let windowMinimumHeight: CGFloat = ScanWindowGeometry.minimumHeight
    static let mainSplitHorizontalPadding: CGFloat = 10
    static let tableRowHeight: CGFloat = 20
    static let tableCellHorizontalPadding: CGFloat = 3
    static let tableIntercellWidth: CGFloat = 3
    static let tableIntercellHeight: CGFloat = 2
    static let tableFontSize: CGFloat = 12
    static let filesSizeColumnWidth: CGFloat = 76
    static let outlineNameColumnMinimumWidth: CGFloat = 180
    static let outlineIndentWidth: CGFloat = 16
    static let outlineIconWidth: CGFloat = 16
    static let outlineCellHorizontalPadding: CGFloat = 3
    static let outlineIconTextSpacing: CGFloat = 4
    static let kindColorColumnWidth: CGFloat = 35
    static let kindColorColumnMinimumWidth: CGFloat = 20
    static let kindNameColumnMinimumWidth: CGFloat = 51
    static let kindSizeColumnWidth: CGFloat = 72
    static let kindFilesColumnWidth: CGFloat = 50
    static let kindSwatchCushionRidgeHeightFactor: CGFloat = 0.5
    static let inactivePaneBorderWidth: CGFloat = 1
    static let activePaneBorderWidth: CGFloat = 2
    static let progressHeaderHorizontalPadding: CGFloat = 17
    static let progressHeaderVerticalPadding: CGFloat = 5
    static let progressHeaderLineSpacing: CGFloat = 2
    static let placeholderSpacing: CGFloat = 10
    static let placeholderPadding: CGFloat = 16
    static let placeholderPathLineLimit: Int = 3
    static let placeholderTitleFontSize: CGFloat = 22
    static let placeholderPathFontSize: CGFloat = 13
    static let placeholderTitleYOffset: CGFloat = 18
    static let placeholderLineHeight: CGFloat = 24
    static let treemapIconSize: CGFloat = 48
    static let minimumRenderableTreemapSide: CGFloat = 2
    static let treemapMinimumSelectionSide: CGFloat = 12
    static let treemapLiveResizeImageFraction: CGFloat = 0.6
    static let treemapSelectionOuterLineWidth: CGFloat = 5
    static let treemapSelectionMiddleLineWidth: CGFloat = 3
    static let treemapSelectionInnerLineWidth: CGFloat = 1
    static let singleLineLimit: Int = 1
    static let statusFieldSpacing: CGFloat = 2
    static let statusFieldControlSpacing: CGFloat = 8
    static let statusFieldFontSize: CGFloat = 11
    static let statusFieldHeight: CGFloat = 88
    static let statusFieldHorizontalPadding: CGFloat = 17
    static let statusFieldBottomPadding: CGFloat = 12
}

private typealias Metrics = ScanWindowMetrics
