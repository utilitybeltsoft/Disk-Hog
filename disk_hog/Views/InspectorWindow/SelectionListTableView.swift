import AppKit
import Combine
import SwiftUI

@MainActor
final class SelectionListDataStore: ObservableObject {
    private(set) var rows: [SelectionListRow] = []
    private(set) var rowsByID: [DiskItemID: SelectionListRow] = [:]
    private(set) var queryResult: SelectionListQueryResult = .empty
    @Published private(set) var resultGeneration: Int = 0

    var resultCount: Int {
        queryResult.rows.count
    }

    func reset() {
        rows = []
        rowsByID = [:]
        queryResult = .empty
        resultGeneration += 1
    }

    func install(_ snapshot: SelectionListSnapshot) {
        rows = snapshot.rows
        rowsByID = snapshot.rowsByID
    }

    func publish(_ result: SelectionListQueryResult) {
        queryResult = result
        resultGeneration += 1
    }
}

struct SelectionListTableView: NSViewRepresentable {
    @ObservedObject var dataStore: SelectionListDataStore
    @Binding var selectedItemID: DiskItemID?
    @Binding var sortDescriptors: [SelectionListSortDescriptor]
    let onSelect: (DiskItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedItemID: $selectedItemID,
            sortDescriptors: $sortDescriptors,
            onSelect: onSelect
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView: NSTableView = NSTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.setDraggingSourceOperationMask([], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let nameColumn: NSTableColumn = NSTableColumn(identifier: SelectionListColumnID.name)
        nameColumn.title = "Name"
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
        pathColumn.title = "Path"
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
        sizeColumn.title = "Size"
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
        var selectedItemID: Binding<DiskItemID?>
        var sortDescriptors: Binding<[SelectionListSortDescriptor]>
        var onSelect: (DiskItem) -> Void
        weak var tableView: NSTableView?

        private var rows: [SelectionListRow] = []
        private var rowIndexByID: [DiskItemID: Int] = [:]
        private var resultGeneration: Int?
        private var isApplyingSelection: Bool = false
        private var isApplyingSortDescriptors: Bool = false

        init(
            selectedItemID: Binding<DiskItemID?>,
            sortDescriptors: Binding<[SelectionListSortDescriptor]>,
            onSelect: @escaping (DiskItem) -> Void
        ) {
            self.selectedItemID = selectedItemID
            self.sortDescriptors = sortDescriptors
            self.onSelect = onSelect
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
            guard !isApplyingSelection,
                  let tableView,
                  rows.indices.contains(tableView.selectedRow) else {
                return
            }

            let row: SelectionListRow = rows[tableView.selectedRow]
            selectedItemID.wrappedValue = row.id
            onSelect(row.item)
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard !isApplyingSortDescriptors,
                  let descriptor: NSSortDescriptor = tableView.sortDescriptors.first,
                  let field: SelectionListSortField = Self.sortField(for: descriptor) else {
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

            guard let selectedItemID: DiskItemID = selectedItemID.wrappedValue,
                  let selectedRow: Int = rowIndexByID[selectedItemID] else {
                if tableView.selectedRow >= 0 {
                    isApplyingSelection = true
                    tableView.deselectAll(nil)
                    isApplyingSelection = false
                }
                return
            }

            guard tableView.selectedRow != selectedRow else {
                return
            }

            isApplyingSelection = true
            tableView.selectRowIndexes(
                IndexSet(integer: selectedRow),
                byExtendingSelection: false
            )
            tableView.scrollRowToVisible(selectedRow)
            isApplyingSelection = false
        }

        func syncSortDescriptors() {
            guard let tableView,
                  let descriptor: SelectionListSortDescriptor = sortDescriptors.wrappedValue.first else {
                return
            }

            let currentDescriptor: NSSortDescriptor? = tableView.sortDescriptors.first
            let currentField: SelectionListSortField?
            if let currentDescriptor {
                currentField = Self.sortField(for: currentDescriptor)
            } else {
                currentField = nil
            }
            if currentField == descriptor.field,
               currentDescriptor?.ascending == descriptor.isAscending {
                return
            }

            isApplyingSortDescriptors = true
            tableView.sortDescriptors = [
                NSSortDescriptor(
                    key: Self.sortKey(for: descriptor.field),
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
            let cell: SelectionListNameCellView = tableView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? SelectionListNameCellView ?? SelectionListNameCellView()
            cell.identifier = identifier
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
            let cell: SelectionListTextCellView = tableView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? SelectionListTextCellView ?? SelectionListTextCellView()
            cell.identifier = identifier
            cell.configure(
                string: string,
                alignment: alignment,
                lineBreakMode: lineBreakMode
            )
            return cell
        }

        private static func sortField(
            for descriptor: NSSortDescriptor
        ) -> SelectionListSortField? {
            switch descriptor.key {
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

        private static func sortKey(for field: SelectionListSortField) -> String {
            switch field {
            case .name:
                SelectionListSortKey.name
            case .path:
                SelectionListSortKey.path
            case .size:
                SelectionListSortKey.size
            }
        }
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
        iconView.image = NSWorkspace.shared.icon(forFile: row.item.path)
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
