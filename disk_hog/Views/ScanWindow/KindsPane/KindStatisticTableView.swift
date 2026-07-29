import AppKit
import SwiftUI

private struct KindStatisticRow {
    let filter: SelectionListFilter
    let kindName: String
    let size: UInt64
    let fileCount: Int
    let color: NSColor?
}

struct KindStatisticTableView: NSViewRepresentable {
    let statistics: [TreemapKindStatistic]
    let selectedFilter: Binding<SelectionListFilter?>
    let activePane: Binding<ScanWindowPane?>
    let onShowSelectionList: (SelectionListFilter) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            statistics: statistics,
            selectedFilter: selectedFilter,
            activePane: activePane,
            onShowSelectionList: onShowSelectionList
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView: NSTableView = NSTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = ScanWindowMetrics.tableRowHeight
        tableView.intercellSpacing = NSSize(width: ScanWindowMetrics.tableIntercellWidth, height: ScanWindowMetrics.tableIntercellHeight)
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.backgroundColor = .controlBackgroundColor
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        let menu: NSMenu = NSMenu()
        let showSelectionListItem: NSMenuItem = NSMenuItem(
            title: "Show Files in Selection List",
            action: #selector(Coordinator.showSelectionList(_:)),
            keyEquivalent: ""
        )
        showSelectionListItem.target = context.coordinator
        menu.addItem(showSelectionListItem)
        menu.delegate = context.coordinator
        tableView.menu = menu

        let colorColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.color)
        colorColumn.title = String(localized: "Color")
        colorColumn.width = ScanWindowMetrics.kindColorColumnWidth
        colorColumn.minWidth = ScanWindowMetrics.kindColorColumnMinimumWidth
        colorColumn.resizingMask = .userResizingMask
        tableView.addTableColumn(colorColumn)

        let kindColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.kind)
        kindColumn.title = String(localized: "Kind")
        kindColumn.minWidth = ScanWindowMetrics.kindNameColumnMinimumWidth
        kindColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.kindName,
            ascending: true,
            selector: #selector(NSString.localizedStandardCompare(_:))
        )
        tableView.addTableColumn(kindColumn)

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.size)
        sizeColumn.title = String(localized: "Size")
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = ScanWindowMetrics.kindSizeColumnWidth
        sizeColumn.minWidth = ScanWindowMetrics.kindSizeColumnWidth
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.size,
            ascending: true
        )
        tableView.addTableColumn(sizeColumn)

        let filesColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.files)
        filesColumn.title = String(localized: "Files")
        filesColumn.headerCell.alignment = .right
        filesColumn.width = ScanWindowMetrics.kindFilesColumnWidth
        filesColumn.minWidth = ScanWindowMetrics.kindFilesColumnWidth
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
        context.coordinator.selectedFilter = selectedFilter
        context.coordinator.activePane = activePane
        context.coordinator.onShowSelectionList = onShowSelectionList
        context.coordinator.applySortDescriptors(context.coordinator.tableView?.sortDescriptors ?? [])
        context.coordinator.tableView?.reloadData()
        context.coordinator.syncSelectionIfNeeded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var statistics: [TreemapKindStatistic]
        var selectedFilter: Binding<SelectionListFilter?>
        var activePane: Binding<ScanWindowPane?>
        var onShowSelectionList: (SelectionListFilter) -> Void
        weak var tableView: NSTableView?
        private var sortedRows: [KindStatisticRow] = []
        private var isApplyingSelection: Bool = false
        fileprivate var isSelectingContextMenuRow: Bool = false

        init(
            statistics: [TreemapKindStatistic],
            selectedFilter: Binding<SelectionListFilter?>,
            activePane: Binding<ScanWindowPane?>,
            onShowSelectionList: @escaping (SelectionListFilter) -> Void
        ) {
            self.statistics = statistics
            self.selectedFilter = selectedFilter
            self.activePane = activePane
            self.onShowSelectionList = onShowSelectionList
            self.sortedRows = Self.makeRows(from: statistics)
        }

        @objc func showSelectionList(_ sender: Any?) {
            guard let tableView: NSTableView = tableView,
                  tableView.selectedRow >= 0,
                  sortedRows.indices.contains(tableView.selectedRow) else {
                return
            }

            let filter: SelectionListFilter = sortedRows[tableView.selectedRow].filter
            selectedFilter.wrappedValue = filter
            onShowSelectionList(filter)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            sortedRows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn: NSTableColumn = tableColumn,
                  sortedRows.indices.contains(row) else {
                return nil
            }

            let statistic: KindStatisticRow = sortedRows[row]
            switch tableColumn.identifier {
            case KindColumnID.color:
                guard statistic.color != nil else {
                    return NSView()
                }
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
                  sortedRows.indices.contains(tableView.selectedRow) else {
                selectedFilter.wrappedValue = nil
                return
            }

            let filter: SelectionListFilter = sortedRows[tableView.selectedRow].filter
            selectedFilter.wrappedValue = filter
            if !isSelectingContextMenuRow {
                onShowSelectionList(filter)
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            applySortDescriptors(tableView.sortDescriptors)
            tableView.reloadData()
            syncSelectionIfNeeded(scrollToSelection: false)
            if !sortedRows.isEmpty {
                tableView.scrollRowToVisible(0)
            }
        }

        func syncSelectionIfNeeded(scrollToSelection: Bool = true) {
            guard let tableView: NSTableView = tableView else {
                return
            }

            guard let selectedFilter: SelectionListFilter = selectedFilter.wrappedValue,
                  let selectedRow: Int = sortedRows.firstIndex(where: { statistic in
                      statistic.filter == selectedFilter
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
                sortedRows = Self.makeRows(from: statistics)
                return
            }

            let ascending: Bool = sortDescriptor.ascending
            let kindRows: [KindStatisticRow] = Self.makeRows(from: statistics).dropFirst().sorted { leftStatistic, rightStatistic in
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
            sortedRows = [Self.allKindsRow(from: statistics)] + kindRows
        }

        private func colorCell(for statistic: KindStatisticRow, tableView: NSTableView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = KindCellID.color
            let cell: KindColorCellView = tableView.makeView(withIdentifier: identifier, owner: self) as? KindColorCellView ?? KindColorCellView()
            cell.identifier = identifier
            cell.configure(color: statistic.color ?? .clear)
            return cell
        }

        private static func makeRows(from statistics: [TreemapKindStatistic]) -> [KindStatisticRow] {
            [allKindsRow(from: statistics)] + statistics.map { statistic in
                KindStatisticRow(
                    filter: .kind(statistic.kindName),
                    kindName: statistic.kindName,
                    size: statistic.size,
                    fileCount: statistic.fileCount,
                    color: statistic.color
                )
            }
        }

        private static func allKindsRow(from statistics: [TreemapKindStatistic]) -> KindStatisticRow {
            KindStatisticRow(
                filter: .all,
                kindName: String(localized: "All"),
                size: statistics.reduce(0) { $0 + $1.size },
                fileCount: statistics.reduce(0) { $0 + $1.fileCount },
                color: nil
            )
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
}

extension KindStatisticTableView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let tableView: NSTableView = tableView,
              let event: NSEvent = NSApp.currentEvent else {
            return
        }

        let row: Int = tableView.row(at: tableView.convert(event.locationInWindow, from: nil))
        if row >= 0 {
            isSelectingContextMenuRow = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSelectingContextMenuRow = false
        }
        menu.items.first?.isEnabled = row >= 0
    }
}
