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

struct SelectionListTableView: NSViewRepresentable {
    @ObservedObject var dataStore: SelectionListDataStore
    let session: ScanSession
    @Binding var selectedItemID: DiskItemID?
    @Binding var selectedItemIDs: Set<DiskItemID>
    @Binding var sortDescriptors: [SelectionListSortDescriptor]
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
        let tableView: SelectionListBatchActionTableView = SelectionListBatchActionTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.pasteboardItemProvider = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.selectedItemForPasteboard()
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
        sizeColumn.title = String(localized: "Size")
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = 92
        sizeColumn.minWidth = 72
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: SelectionListSortKey.size,
            ascending: true
        )
        tableView.addTableColumn(sizeColumn)

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
        context.coordinator.syncSortDescriptors()
        context.coordinator.syncSelectionIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.selectedItemID = $selectedItemID
        context.coordinator.selectedItemIDs = $selectedItemIDs
        context.coordinator.sortDescriptors = $sortDescriptors
        context.coordinator.onSelect = onSelect
        context.coordinator.updateRows(
            dataStore.queryResult.rows,
            rowIndexByID: dataStore.queryResult.rowIndexByID,
            generation: dataStore.resultGeneration
        )
        context.coordinator.syncSortDescriptors()
        context.coordinator.syncSelectionIfNeeded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let session: ScanSession
        var selectedItemID: Binding<DiskItemID?>
        var selectedItemIDs: Binding<Set<DiskItemID>>
        var sortDescriptors: Binding<[SelectionListSortDescriptor]>
        var onSelect: (DiskItem) -> Void
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
                return textCell(
                    ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file),
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
        let item: NSMenuItem = NSMenuItem(
            title: AppCommandRouter.shared.selectionListBatchQueueTitle,
            action: #selector(SelectionListBatchQueueActionTarget.toggle(_:)),
            keyEquivalent: ""
        )
        item.target = batchQueueActionTarget
        item.isEnabled = AppCommandRouter.shared.canToggleSelectionListBatchQueue
        menu.addItem(item)
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(row: SelectionListRow) {
        iconView.image = DiskItemIconCache.shared.icon(for: row.item)
        label.stringValue = row.name
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
