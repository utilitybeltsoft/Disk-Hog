import AppKit
import SwiftUI

struct KindStatisticTableView: NSViewRepresentable {
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
        tableView.rowHeight = ScanWindowMetrics.tableRowHeight
        tableView.intercellSpacing = NSSize(width: ScanWindowMetrics.tableIntercellWidth, height: ScanWindowMetrics.tableIntercellHeight)
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.backgroundColor = .controlBackgroundColor
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let colorColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.color)
        colorColumn.title = "Color"
        colorColumn.width = ScanWindowMetrics.kindColorColumnWidth
        colorColumn.minWidth = ScanWindowMetrics.kindColorColumnMinimumWidth
        colorColumn.resizingMask = .userResizingMask
        tableView.addTableColumn(colorColumn)

        let kindColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.kind)
        kindColumn.title = "Kind"
        kindColumn.minWidth = ScanWindowMetrics.kindNameColumnMinimumWidth
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
        sizeColumn.width = ScanWindowMetrics.kindSizeColumnWidth
        sizeColumn.minWidth = ScanWindowMetrics.kindSizeColumnWidth
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: KindSortKey.size,
            ascending: true
        )
        tableView.addTableColumn(sizeColumn)

        let filesColumn: NSTableColumn = NSTableColumn(identifier: KindColumnID.files)
        filesColumn.title = "Files"
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
}
