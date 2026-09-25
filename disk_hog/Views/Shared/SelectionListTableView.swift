import AppKit
import Combine
import SwiftUI

@MainActor
final class SelectionListDataStore: ObservableObject {
    private(set) var rows: [SelectionListRow] = []
    private(set) var rowsByID: [DiskItemID: SelectionListRow] = [:]
    private(set) var queryResult: SelectionListQueryResult = .empty
    @Published private(set) var resultGeneration: Int = 0
    private var builtRootID: DiskItemID?
    private var builtFilter: SelectionListFilter?
    private var builtUsesPhysicalSize: Bool?
    private(set) var isDirty: Bool = true

    var resultCount: Int {
        queryResult.rows.count
    }

    func reset() {
        rows = []
        rowsByID = [:]
        queryResult = .empty
        isDirty = true
        resultGeneration += 1
    }

    func requiresRebuild(
        rootID: DiskItemID,
        filter: SelectionListFilter,
        usesPhysicalSize: Bool
    ) -> Bool {
        rebuildReason(
            rootID: rootID,
            filter: filter,
            usesPhysicalSize: usesPhysicalSize
        ) != nil
    }

    func rebuildReason(
        rootID: DiskItemID,
        filter: SelectionListFilter,
        usesPhysicalSize: Bool
    ) -> String? {
        if isDirty { return "dirty" }
        if builtRootID != rootID { return "scan tree changed" }
        if builtFilter != filter { return "file kind changed" }
        if builtUsesPhysicalSize != usesPhysicalSize { return "size mode changed" }
        return nil
    }

    func beginRebuild(
        rootID: DiskItemID,
        filter: SelectionListFilter,
        usesPhysicalSize: Bool
    ) {
        reset()
        builtRootID = rootID
        builtFilter = filter
        builtUsesPhysicalSize = usesPhysicalSize
    }

    func install(_ snapshot: SelectionListSnapshot) {
        rows = snapshot.rows
        rowsByID = snapshot.rowsByID
    }

    func publish(_ result: SelectionListQueryResult) {
        queryResult = result
        isDirty = false
        resultGeneration += 1
    }
}

enum RankedItemAction: Int, CaseIterable {
    case folderTree, treemap, reveal, information

    var title: String {
        switch self {
        case .folderTree: String(localized: "Show in Folder Tree")
        case .treemap: String(localized: "Show in Treemap")
        case .reveal: String(localized: "Reveal in Finder")
        case .information: String(localized: "Information")
        }
    }
}

struct SelectionListTableView: NSViewRepresentable {
    @ObservedObject var dataStore: SelectionListDataStore
    let session: ScanSession
    @Binding var selectedItemID: DiskItemID?
    @Binding var selectedItemIDs: Set<DiskItemID>
    @Binding var sortDescriptors: [SelectionListSortDescriptor]
    var allowsColumnSorting: Bool = true
    var showsKindColumn: Bool = false
    var isVisible: Bool = true
    var onRankedAction: ((RankedItemAction, DiskItem) -> Void)? = nil
    let onSelect: (DiskItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            selectedItemID: $selectedItemID,
            selectedItemIDs: $selectedItemIDs,
            sortDescriptors: $sortDescriptors,
            onSelect: onSelect
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.onRankedAction = onRankedAction
        let tableView: SelectionListBatchActionTableView = SelectionListBatchActionTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.setAccessibilityLabel(allowsColumnSorting
            ? String(localized: "File selection list") : String(localized: "Largest items, size descending"))
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.pasteboardItemProvider = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.selectedItemForPasteboard()
        }
        tableView.activateSelectedItem = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.activateSelectedItem()
        }
        tableView.zoomOut = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.zoomOut()
        }
        tableView.menu = context.coordinator.contextMenu
        tableView.onBecomeFirstResponder = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.activateBatchQueueCommand()
        }
        tableView.onResignFirstResponder = {
            AppCommandRouter.shared.deactivateSelectionListBatchQueue()
        }
        tableView.setDraggingSourceOperationMask([], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let nameColumn: NSTableColumn = NSTableColumn(identifier: SelectionListColumnID.name)
        nameColumn.title = String(localized: "Name")
        nameColumn.width = 220
        nameColumn.minWidth = 120
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: SelectionListSortKey.name,
            ascending: true,
            selector: #selector(NSString.localizedStandardCompare(_:))
        )
        tableView.addTableColumn(nameColumn)
        if showsKindColumn {
            let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rankedKind"))
            kindColumn.title = String(localized: "Kind")
            kindColumn.width = 120
            kindColumn.minWidth = 70
            tableView.addTableColumn(kindColumn)
        }

        let pathColumn: NSTableColumn = NSTableColumn(identifier: SelectionListColumnID.path)
        pathColumn.title = String(localized: "Path")
        pathColumn.width = 360
        pathColumn.minWidth = 160
        pathColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        pathColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: SelectionListSortKey.path,
            ascending: true,
            selector: #selector(NSString.localizedStandardCompare(_:))
        )
        tableView.addTableColumn(pathColumn)

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: SelectionListColumnID.size)
        sizeColumn.title = allowsColumnSorting ? String(localized: "Size")
            : (session.scanSettings.usePhysicalSize ? String(localized: "Size on disk") : String(localized: "Logical size"))
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = 92
        sizeColumn.minWidth = 72
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: SelectionListSortKey.size,
            ascending: true
        )
        tableView.addTableColumn(sizeColumn)
        if !allowsColumnSorting {
            // Ranked lists should expose their primary comparison without scrolling:
            // Name, Size, Kind, Path. Keep the inspector's existing order unchanged.
            tableView.moveColumn(tableView.column(withIdentifier: SelectionListColumnID.size), toColumn: 1)
            for column in tableView.tableColumns { column.sortDescriptorPrototype = nil }
        }

        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        context.coordinator.tableView = tableView
        context.coordinator.updateRows(
            dataStore.queryResult.rows,
            rowIndexByID: dataStore.queryResult.rowIndexByID,
            generation: dataStore.resultGeneration
        )
        if allowsColumnSorting { context.coordinator.syncSortDescriptors() }
        context.coordinator.syncSelectionIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Hidden ranked tabs retain their native scroll position but must not
        // receive keyboard input or expose an invisible accessibility table.
        scrollView.isHidden = !isVisible
        if !allowsColumnSorting {
            context.coordinator.tableView?.tableColumn(withIdentifier: SelectionListColumnID.size)?.title =
                session.scanSettings.usePhysicalSize ? String(localized: "Size on disk") : String(localized: "Logical size")
        }
        context.coordinator.selectedItemID = $selectedItemID
        context.coordinator.selectedItemIDs = $selectedItemIDs
        context.coordinator.sortDescriptors = $sortDescriptors
        context.coordinator.onSelect = onSelect
        context.coordinator.onRankedAction = onRankedAction
        context.coordinator.updateRows(
            dataStore.queryResult.rows,
            rowIndexByID: dataStore.queryResult.rowIndexByID,
            generation: dataStore.resultGeneration
        )
        if allowsColumnSorting { context.coordinator.syncSortDescriptors() }
        context.coordinator.syncSelectionIfNeeded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let session: ScanSession
        var selectedItemID: Binding<DiskItemID?>
        var selectedItemIDs: Binding<Set<DiskItemID>>
        var sortDescriptors: Binding<[SelectionListSortDescriptor]>
        var onSelect: (DiskItem) -> Void
        var onRankedAction: ((RankedItemAction, DiskItem) -> Void)?
        weak var tableView: NSTableView?

        private var rows: [SelectionListRow] = []
        private var rowIndexByID: [DiskItemID: Int] = [:]
        private var resultGeneration: Int?
        private let selectionMutationGate: AppKitSelectionMutationGate = AppKitSelectionMutationGate()
        private var isApplyingSortDescriptors: Bool = false
        let contextMenu: NSMenu = NSMenu()
        private let batchQueueActionTarget: SelectionListBatchQueueActionTarget = SelectionListBatchQueueActionTarget()
        private static let sortBridge: AppKitSortDescriptorBridge<SelectionListSortField> = AppKitSortDescriptorBridge(
            keyForField: { field in
                switch field {
                case .name:
                    SelectionListSortKey.name
                case .path:
                    SelectionListSortKey.path
                case .size:
                    SelectionListSortKey.size
                }
            },
            fieldForKey: { key in
                switch key {
                case SelectionListSortKey.name:
                    .name
                case SelectionListSortKey.path:
                    .path
                case SelectionListSortKey.size:
                    .size
                default:
                    nil
                }
            }
        )

        init(
            session: ScanSession,
            selectedItemID: Binding<DiskItemID?>,
            selectedItemIDs: Binding<Set<DiskItemID>>,
            sortDescriptors: Binding<[SelectionListSortDescriptor]>,
            onSelect: @escaping (DiskItem) -> Void
        ) {
            self.session = session
            self.selectedItemID = selectedItemID
            self.selectedItemIDs = selectedItemIDs
            self.sortDescriptors = sortDescriptors
            self.onSelect = onSelect
            super.init()
            contextMenu.delegate = self
        }

        func updateRows(
            _ rows: [SelectionListRow],
            rowIndexByID: [DiskItemID: Int],
            generation: Int
        ) {
            guard resultGeneration != generation else {
                return
            }

            self.rows = rows
            self.rowIndexByID = rowIndexByID
            resultGeneration = generation
            tableView?.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func selectedItemForPasteboard() -> DiskItem? {
            guard let tableView,
                  rows.indices.contains(tableView.selectedRow) else {
                return nil
            }
            return rows[tableView.selectedRow].item
        }

        // Mirrors DiskItemPasteboardOutlineView's Return-key handling (the Files pane
        // outline "tree"), which this list otherwise lacked entirely - selecting a row
        // here only ever routed into ScanWindowCommandContext via onSelect, so Return
        // did nothing until keyboard focus moved to the outline or the treemap itself.
        func activateSelectedItem() {
            ScanWindowCommandState.shared.zoomIn()
        }

        func zoomOut() {
            ScanWindowCommandState.shared.zoomOut()
        }

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else {
                return nil
            }
            return DiskItemPasteboardWriter(item: rows[row].item)
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn,
                  rows.indices.contains(row) else {
                return nil
            }

            let item: SelectionListRow = rows[row]
            switch tableColumn.identifier {
            case NSUserInterfaceItemIdentifier("rankedKind"):
                return textCell(
                    item.item.resolvedKindName,
                    identifier: NSUserInterfaceItemIdentifier("rankedKindCell"),
                    alignment: .left, lineBreakMode: .byTruncatingTail, tableView: tableView)
            case SelectionListColumnID.name:
                return nameCell(for: item, tableView: tableView)
            case SelectionListColumnID.path:
                return textCell(
                    item.parentPath,
                    identifier: SelectionListCellID.path,
                    alignment: .left,
                    lineBreakMode: .byTruncatingMiddle,
                    tableView: tableView
                )
            default:
                let incomplete = session.isAffectedBySkippedContent(item.item)
                let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file)
                return textCell(
                    incomplete ? (item.size == 0 ? String(localized: "Unknown") : "≥ " + size) : size,
                    identifier: SelectionListCellID.size,
                    alignment: .right,
                    lineBreakMode: .byTruncatingTail,
                    tableView: tableView
                )
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !selectionMutationGate.isApplyingSelection,
                  let tableView else {
                return
            }
            let selectedRows: [SelectionListRow] = tableView.selectedRowIndexes.compactMap { row in
                rows.indices.contains(row) ? rows[row] : nil
            }
            selectedItemIDs.wrappedValue = Set(selectedRows.map(\.id))
            AppCommandRouter.shared.activateSelectionListBatchQueue(
                session: session,
                items: selectedRows.map(\.item)
            )
            let primaryRow: Int = tableView.selectedRow
            guard rows.indices.contains(primaryRow) else {
                selectedItemID.wrappedValue = nil
                return
            }
            let row: SelectionListRow = rows[primaryRow]
            selectedItemID.wrappedValue = row.id
            onSelect(row.item)
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard !isApplyingSortDescriptors,
                  let descriptor: NSSortDescriptor = tableView.sortDescriptors.first,
                  let field: SelectionListSortField = Self.sortBridge.field(for: descriptor) else {
                return
            }

            sortDescriptors.wrappedValue = [
                SelectionListSortDescriptor(
                    field: field,
                    isAscending: descriptor.ascending
                )
            ]
        }

        func syncSelectionIfNeeded() {
            guard let tableView else {
                return
            }

            let selectedRows: IndexSet = IndexSet(
                selectedItemIDs.wrappedValue.compactMap { rowIndexByID[$0] }
            )
            if selectedRows.isEmpty == false {
                guard tableView.selectedRowIndexes != selectedRows else { return }
                selectionMutationGate.perform {
                    tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
                }
                return
            }

            guard let selectedItemID: DiskItemID = selectedItemID.wrappedValue,
                  let selectedRow: Int = rowIndexByID[selectedItemID] else {
                if tableView.selectedRow >= 0 {
                    selectionMutationGate.perform {
                        tableView.deselectAll(nil)
                    }
                }
                return
            }

            guard tableView.selectedRow != selectedRow else {
                return
            }

            selectionMutationGate.perform {
                tableView.selectRowIndexes(
                    IndexSet(integer: selectedRow),
                    byExtendingSelection: false
                )
                tableView.scrollRowToVisible(selectedRow)
            }
        }

        func activateBatchQueueCommand() {
            let selectedRows: [SelectionListRow] = tableView?.selectedRowIndexes.compactMap { row in
                rows.indices.contains(row) ? rows[row] : nil
            } ?? []
            AppCommandRouter.shared.activateSelectionListBatchQueue(
                session: session,
                items: selectedRows.map(\.item)
            )
        }

        func syncSortDescriptors() {
            guard let tableView,
                  let descriptor: SelectionListSortDescriptor = sortDescriptors.wrappedValue.first else {
                return
            }

            let currentDescriptor: NSSortDescriptor? = tableView.sortDescriptors.first
            if Self.sortBridge.descriptor(
                currentDescriptor,
                matches: descriptor.field,
                ascending: descriptor.isAscending
            ) {
                return
            }

            isApplyingSortDescriptors = true
            tableView.sortDescriptors = [
                Self.sortBridge.descriptor(
                    for: descriptor.field,
                    ascending: descriptor.isAscending
                )
            ]
            isApplyingSortDescriptors = false
        }

        private func nameCell(
            for row: SelectionListRow,
            tableView: NSTableView
        ) -> SelectionListNameCellView {
            let identifier: NSUserInterfaceItemIdentifier = SelectionListCellID.name
            let cell: SelectionListNameCellView = tableView.reusableView(withIdentifier: identifier, owner: self) {
                SelectionListNameCellView()
            }
            cell.configure(row: row)
            return cell
        }

        private func textCell(
            _ string: String,
            identifier: NSUserInterfaceItemIdentifier,
            alignment: NSTextAlignment,
            lineBreakMode: NSLineBreakMode,
            tableView: NSTableView
        ) -> SelectionListTextCellView {
            let cell: SelectionListTextCellView = tableView.reusableView(withIdentifier: identifier, owner: self) {
                SelectionListTextCellView()
            }
            cell.configure(
                string: string,
                alignment: alignment,
                lineBreakMode: lineBreakMode
            )
            return cell
        }

    }
}

extension SelectionListTableView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        activateBatchQueueCommand()
        menu.removeAllItems()
        menu.autoenablesItems = false
        if onRankedAction != nil, tableView?.selectedRowIndexes.count == 1 {
            for action in RankedItemAction.allCases {
                let item = NSMenuItem(title: action.title, action: #selector(performRankedAction(_:)), keyEquivalent: "")
                item.tag = action.rawValue
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let item: NSMenuItem = NSMenuItem(
            title: AppCommandRouter.shared.selectionListBatchQueueTitle,
            action: #selector(SelectionListBatchQueueActionTarget.toggle(_:)),
            keyEquivalent: ""
        )
        item.target = batchQueueActionTarget
        item.isEnabled = AppCommandRouter.shared.canToggleSelectionListBatchQueue
        menu.addItem(item)
    }

    @objc func performRankedAction(_ sender: NSMenuItem) {
        guard tableView?.selectedRowIndexes.count == 1,
              let item = selectedItemForPasteboard(),
              let action = RankedItemAction(rawValue: sender.tag) else { return }
        onRankedAction?(action, item)
    }
}

@MainActor
private final class SelectionListBatchQueueActionTarget: NSObject {
    @objc func toggle(_ sender: NSMenuItem) {
        AppCommandRouter.shared.toggleSelectionListBatchQueue()
    }
}

private final class SelectionListBatchActionTableView: DiskItemPasteboardTableView {
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        guard clicked >= 0 else { return nil }
        window?.makeFirstResponder(self)
        // Keep an existing multi-selection when right-clicking within it.
        if !selectedRowIndexes.contains(clicked) {
            selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 109, event.modifierFlags.intersection([.shift, .control, .option, .command]) == .shift {
            _ = accessibilityPerformShowMenu()
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard !isHiddenOrHasHiddenAncestor, selectedRow >= 0, selectedRow < numberOfRows,
              let menu else { return false }
        scrollRowToVisible(selectedRow)
        menu.update()
        let rowRect = rect(ofRow: selectedRow)
        menu.popUp(positioning: nil, at: NSPoint(x: visibleRect.minX + 16, y: rowRect.midY), in: self)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder: Bool = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onBecomeFirstResponder?()
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder: Bool = super.resignFirstResponder()
        if didResignFirstResponder {
            onResignFirstResponder?()
        }
        return didResignFirstResponder
    }
}

private final class SelectionListNameCellView: NSTableCellView {
    private let iconView: NSImageView = NSImageView()
    private let label: NSTextField = NSTextField(labelWithString: "")
    private var iconLoadTask: Task<Void, Never>?
    private var currentIconPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(row: SelectionListRow) {
        let path: String = row.item.path
        currentIconPath = path
        iconLoadTask?.cancel()
        // This view is reused across rows during scroll, so a synchronous, cache-miss-
        // blocking fetch here (a spun-down external drive, a network share) would stall
        // scrolling itself - the most scroll-sensitive spot in the app for that bug.
        // Seed from a non-blocking cache peek, then resolve the real icon asynchronously,
        // reapplying it only if this cell hasn't since been recycled for a different row.
        iconView.image = DiskItemIconCache.shared.cachedIcon(forFile: path)
        iconLoadTask = Task { @MainActor [weak self] in
            let icon: NSImage = await DiskItemIconCache.shared.loadIconAsync(forFile: path)
            guard let self, !Task.isCancelled, self.currentIconPath == path else {
                return
            }
            self.iconView.image = icon
        }
        label.stringValue = row.name
        toolTip = row.fullPath
    }

    private func setup() {
        imageView = iconView
        textField = label
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class SelectionListTextCellView: NSTableCellView {
    private let label: NSTextField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        string: String,
        alignment: NSTextAlignment,
        lineBreakMode: NSLineBreakMode
    ) {
        label.stringValue = string
        label.alignment = alignment
        label.lineBreakMode = lineBreakMode
    }

    private func setup() {
        textField = label
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private enum SelectionListColumnID {
    static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionName")
    static let path: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionPath")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionSize")
}

private enum SelectionListCellID {
    static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionNameCell")
    static let path: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionPathCell")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("selectionSizeCell")
}

private enum SelectionListSortKey {
    static let name: String = "name"
    static let path: String = "path"
    static let size: String = "size"
}
