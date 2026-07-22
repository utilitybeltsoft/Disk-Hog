import AppKit
import Combine
import SwiftUI

struct DiskItemOutlineView: NSViewRepresentable {
    let session: ScanSession
    let rootItem: DiskItem?
    let usePhysicalSize: Bool
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let activePane: Binding<ScanWindowPane?>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            usePhysicalSize: usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView: NSOutlineView = NSOutlineView()
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = ScanWindowMetrics.tableRowHeight
        outlineView.intercellSpacing = NSSize(width: ScanWindowMetrics.tableIntercellWidth, height: ScanWindowMetrics.tableIntercellHeight)
        outlineView.indentationPerLevel = ScanWindowMetrics.outlineIndentWidth
        outlineView.allowsMultipleSelection = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .controlBackgroundColor

        let nameColumn: NSTableColumn = NSTableColumn(identifier: DiskItemOutlineColumnID.name)
        nameColumn.title = "Name"
        nameColumn.minWidth = ScanWindowMetrics.outlineNameColumnMinimumWidth
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: DiskItemOutlineColumnID.size)
        sizeColumn.title = "Size"
        sizeColumn.headerCell.alignment = .right
        sizeColumn.width = ScanWindowMetrics.filesSizeColumnWidth
        sizeColumn.minWidth = ScanWindowMetrics.filesSizeColumnWidth
        sizeColumn.resizingMask = .userResizingMask
        outlineView.addTableColumn(sizeColumn)

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClick(_:))
        outlineView.menu = context.coordinator.contextMenu

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
        context.coordinator.session = session
        context.coordinator.selectionCoordinator = selectionCoordinator
        context.coordinator.activePane = activePane
        context.coordinator.updateSizeMode(usePhysicalSize)
        context.coordinator.reloadIfNeeded(rootItem: rootItem)
        context.coordinator.syncSelectionIfNeeded(selectionCoordinator.selectedItem)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var session: ScanSession {
            didSet {
                contextMenuActionTarget.session = session
            }
        }
        private var usePhysicalSize: Bool
        var selectionCoordinator: ScanWindowSelectionCoordinator
        var activePane: Binding<ScanWindowPane?>
        weak var outlineView: NSOutlineView?
        let contextMenu: NSMenu = NSMenu()
        private let contextMenuActionTarget: DiskItemContextMenuActionTarget
        private var rootItem: DiskItem?
        private var isApplyingSelection: Bool = false
        private var selectionCancellable: AnyCancellable?

        init(
            session: ScanSession,
            usePhysicalSize: Bool,
            selectionCoordinator: ScanWindowSelectionCoordinator,
            activePane: Binding<ScanWindowPane?>
        ) {
            self.session = session
            self.contextMenuActionTarget = DiskItemContextMenuActionTarget(session: session)
            self.usePhysicalSize = usePhysicalSize
            self.selectionCoordinator = selectionCoordinator
            self.activePane = activePane
            super.init()
            contextMenu.delegate = self
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
            let expandedPaths: [String] = expandedItemPaths()
            self.rootItem = rootItem
            outlineView?.reloadData()
            if let rootItem: DiskItem = rootItem {
                outlineView?.expandItem(rootItem)
                for path: String in expandedPaths {
                    if let expandedItem: DiskItem = rootItem.item(atPath: path) {
                        outlineView?.expandItem(expandedItem)
                    }
                }
            }
        }

        private func expandedItemPaths() -> [String] {
            guard let outlineView: NSOutlineView = outlineView else {
                return []
            }

            return (0..<outlineView.numberOfRows).compactMap { row in
                guard let item: DiskItem = outlineView.item(atRow: row) as? DiskItem,
                      outlineView.isItemExpanded(item) else {
                    return nil
                }
                return item.path
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

            if outlineView.item(atRow: outlineView.selectedRow) as? DiskItem == item {
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

            if tableColumn.identifier == DiskItemOutlineColumnID.size {
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
            guard let rootItem: DiskItem = rootItem else {
                return
            }

            let ancestors: [DiskItem] = rootItem.descendantsMatchingAncestorPath(of: item).dropLast()
            for ancestor: DiskItem in ancestors {
                outlineView?.expandItem(ancestor)
            }
        }

        private func nameCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = DiskItemOutlineCellID.name
            let cell: DiskItemNameCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemNameCellView ?? DiskItemNameCellView()
            cell.identifier = identifier
            cell.configure(item: item)
            return cell
        }

        private func sizeCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = DiskItemOutlineCellID.size
            let cell: DiskItemSizeCellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? DiskItemSizeCellView ?? DiskItemSizeCellView()
            cell.identifier = identifier
            cell.configure(item: item, usePhysicalSize: usePhysicalSize)
            return cell
        }
    }
}

extension DiskItemOutlineView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let item: DiskItem? = rightClickedItem()
        DiskItemContextMenuBuilder.populate(
            menu,
            with: item,
            actionTarget: contextMenuActionTarget,
            treeActionsEnabled: !session.isUpdatingTree
        )
    }

    private func rightClickedItem() -> DiskItem? {
        guard let outlineView: NSOutlineView = outlineView else {
            return selectionCoordinator.selectedItem
        }

        if let event: NSEvent = NSApp.currentEvent {
            let point: NSPoint = outlineView.convert(event.locationInWindow, from: nil)
            let row: Int = outlineView.row(at: point)
            if row >= 0, let item: DiskItem = outlineView.item(atRow: row) as? DiskItem {
                activePane.wrappedValue = .files
                isApplyingSelection = true
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isApplyingSelection = false
                selectionCoordinator.setSelectedItem(item)
                return item
            }
        }

        return selectionCoordinator.selectedItem
    }
}
