import AppKit
import Combine
import SwiftUI

struct DiskItemOutlineView: NSViewRepresentable {
    let session: ScanSession
    let rootItem: DiskItem?
    let usePhysicalSize: Bool
    let selectionCoordinator: ScanWindowSelectionCoordinator
    let activePane: Binding<ScanWindowPane?>
    let onActivateItem: (DiskItem, Bool) -> Void
    let onZoomOut: () -> Void
    var cleanupQueue: CleanupQueueStore = .shared

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            usePhysicalSize: usePhysicalSize,
            selectionCoordinator: selectionCoordinator,
            activePane: activePane,
            onActivateItem: onActivateItem,
            onZoomOut: onZoomOut, cleanupQueue: cleanupQueue
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView: DiskItemPasteboardOutlineView = DiskItemPasteboardOutlineView()
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
        nameColumn.title = String(localized: "Name")
        nameColumn.minWidth = ScanWindowMetrics.outlineNameColumnMinimumWidth
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: DiskItemOutlineColumnID.size)
        sizeColumn.title = String(localized: "Size")
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
        outlineView.activateSelectedItem = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.activateSelectedItem()
        }
        outlineView.zoomOut = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.onZoomOut()
        }
        outlineView.pasteboardItemProvider = { [weak contextCoordinator = context.coordinator] in
            contextCoordinator?.selectedItemForPasteboard()
        }
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

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
        context.coordinator.onActivateItem = onActivateItem
        context.coordinator.onZoomOut = onZoomOut
        context.coordinator.updateSizeMode(usePhysicalSize)
        context.coordinator.reloadIfNeeded(rootItem: rootItem)
        context.coordinator.syncSelectionIfNeeded(
            selectionCoordinator.selectedItem,
            ancestorChain: selectionCoordinator.lastKnownAncestorChain
        )
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
        var onActivateItem: (DiskItem, Bool) -> Void
        var onZoomOut: () -> Void
        weak var outlineView: NSOutlineView?
        let contextMenu: NSMenu = NSMenu()
        private let contextMenuActionTarget: DiskItemContextMenuActionTarget
        private var rootItem: DiskItem?
        // NSOutlineView identifies items by Objective-C object identity. DiskItem is
        // a flyweight, so keep one wrapper per packed address for this outline's
        // current snapshot.
        private var canonicalItems: [DiskItemID: DiskItem] = [:]
        private let selectionMutationGate: AppKitSelectionMutationGate = AppKitSelectionMutationGate()
        private var selectionCancellable: AnyCancellable?

        init(
            session: ScanSession,
            usePhysicalSize: Bool,
            selectionCoordinator: ScanWindowSelectionCoordinator,
            activePane: Binding<ScanWindowPane?>,
            onActivateItem: @escaping (DiskItem, Bool) -> Void,
            onZoomOut: @escaping () -> Void, cleanupQueue: CleanupQueueStore? = nil
        ) {
            let cleanupQueue = cleanupQueue ?? .shared
            self.session = session
            self.contextMenuActionTarget = DiskItemContextMenuActionTarget(session: session, cleanupQueue: cleanupQueue)
            self.usePhysicalSize = usePhysicalSize
            self.selectionCoordinator = selectionCoordinator
            self.activePane = activePane
            self.onActivateItem = onActivateItem
            self.onZoomOut = onZoomOut
            super.init()
            contextMenu.delegate = self
        }

        func observeSelection() {
            selectionCancellable = selectionCoordinator.$selectedItem.sink { [weak self] item in
                self?.syncSelectionIfNeeded(item, ancestorChain: self?.selectionCoordinator.lastKnownAncestorChain ?? [])
            }
        }

        func reloadIfNeeded(rootItem: DiskItem?) {
            guard self.rootItem != rootItem else {
                return
            }

            reload(rootItem: rootItem)
        }

        func reload(rootItem: DiskItem?) {
            let expandedPaths: [String] = expandedItemPaths()
            canonicalItems.removeAll(keepingCapacity: true)
            self.rootItem = rootItem.map(canonicalItem)
            outlineView?.reloadData()
            if let rootItem: DiskItem = rootItem {
                outlineView?.expandItem(canonicalItem(rootItem))
                for path: String in expandedPaths {
                    if let expandedItem: DiskItem = rootItem.item(atPath: path) {
                        outlineView?.expandItem(canonicalItem(expandedItem))
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

        func syncSelectionIfNeeded(_ item: DiskItem?, ancestorChain: [DiskItem] = []) {
            guard let outlineView: NSOutlineView = outlineView else {
                return
            }

            guard let item: DiskItem = canonicalItem(matching: item) else {
                selectionMutationGate.perform {
                    outlineView.deselectAll(nil)
                }
                return
            }

            if outlineView.item(atRow: outlineView.selectedRow) as? DiskItem == item {
                return
            }

            expandAncestors(of: item, ancestorChain: ancestorChain)
            let row: Int = outlineView.row(forItem: item)
            guard row >= 0 else {
                selectionMutationGate.perform {
                    outlineView.deselectAll(nil)
                }
                return
            }

            selectionMutationGate.perform {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item: DiskItem = item as? DiskItem else {
                return rootItem == nil ? 0 : 1
            }

            return item.childCount
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item: DiskItem = item as? DiskItem else {
                return canonicalItem(rootItem!)
            }

            return canonicalItem(item.child(at: index))
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
            guard !selectionMutationGate.isApplyingSelection,
                  let outlineView: NSOutlineView = outlineView else {
                return
            }

            activePane.wrappedValue = .files
            selectionCoordinator.setSelectedItem(outlineView.selectedRow >= 0 ? outlineView.item(atRow: outlineView.selectedRow) as? DiskItem : nil)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is DiskItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> NSPasteboardWriting? {
            guard let item: DiskItem = item as? DiskItem,
                  !item.isSpecialItem else {
                return nil
            }
            return DiskItemPasteboardWriter(item: item)
        }

        func outlineView(_ outlineView: NSOutlineView, mouseDownInHeaderOf tableColumn: NSTableColumn) {}

        func selectedItemForPasteboard() -> DiskItem? {
            guard let outlineView,
                  outlineView.selectedRow >= 0 else {
                return nil
            }
            return outlineView.item(atRow: outlineView.selectedRow) as? DiskItem
        }

        @objc func doubleClick(_ sender: Any?) {
            guard let outlineView: NSOutlineView = outlineView,
                  outlineView.clickedRow >= 0,
                  let item: DiskItem = outlineView.item(atRow: outlineView.clickedRow) as? DiskItem else {
                return
            }
            // A file behaves like a plain click here, matching the treemap's
            // double-click convention - no fallback to the parent.
            activate(item, allowingFileFallback: false)
        }

        func activateSelectedItem() {
            guard let outlineView,
                  outlineView.selectedRow >= 0,
                  let item: DiskItem = outlineView.item(atRow: outlineView.selectedRow) as? DiskItem else {
                return
            }
            // Unlike double-click, Return has no other way to act on a selected file -
            // there's nothing left for it to do if it silently no-ops the way double-click
            // does, so it falls back to zooming into the file's parent, matching the
            // toolbar/menu Zoom In command and the treemap's own Return-key handling.
            activate(item, allowingFileFallback: true)
        }

        private func activate(_ item: DiskItem, allowingFileFallback: Bool) {
            if item.isFolder, item.childCount > 0 {
                outlineView?.expandItem(item)
            }
            onActivateItem(item, allowingFileFallback)
        }

        private func expandAncestors(of item: DiskItem, ancestorChain: [DiskItem] = []) {
            guard let rootItem: DiskItem = rootItem else {
                return
            }

            // When the caller already knows the ancestor chain (e.g. a treemap
            // click resolved it via the layout plan's item index), use it directly
            // instead of re-deriving it with a path walk from the root. The chain
            // is only trustworthy against this outline's current tree generation.
            let ancestors: [DiskItem]
            if ancestorChain.isEmpty == false, ancestorChain.allSatisfy({ $0.snapshot === rootItem.snapshot }) {
                ancestors = ancestorChain
            } else {
                ancestors = rootItem.descendantsMatchingAncestorPath(of: item).dropLast()
            }
            let collapsedAncestors: [DiskItem] = ancestors.filter {
                outlineView?.isItemExpanded(canonicalItem($0)) == false
            }
            guard collapsedAncestors.isEmpty == false else {
                return
            }

            outlineView?.beginUpdates()
            for ancestor: DiskItem in ancestors {
                outlineView?.expandItem(canonicalItem(ancestor))
            }
            outlineView?.endUpdates()
        }

        private func canonicalItem(_ item: DiskItem) -> DiskItem {
            if let existingItem: DiskItem = canonicalItems[item.id] {
                return existingItem
            }

            canonicalItems[item.id] = item
            return item
        }

        private func canonicalItem(matching item: DiskItem?) -> DiskItem? {
            guard let item else {
                return nil
            }
            if let existingItem: DiskItem = canonicalItems[item.id] {
                return existingItem
            }
            guard let rootItem else {
                return nil
            }
            if rootItem.snapshot === item.snapshot {
                return canonicalItem(item)
            }
            return rootItem.item(atPath: item.path).map(canonicalItem)
        }

        private func nameCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = DiskItemOutlineCellID.name
            let cell: DiskItemNameCellView = outlineView.reusableView(withIdentifier: identifier, owner: self) { DiskItemNameCellView() }
            cell.configure(item: item)
            return cell
        }

        private func sizeCell(for item: DiskItem, outlineView: NSOutlineView) -> NSTableCellView {
            let identifier: NSUserInterfaceItemIdentifier = DiskItemOutlineCellID.size
            let cell: DiskItemSizeCellView = outlineView.reusableView(withIdentifier: identifier, owner: self) { DiskItemSizeCellView() }
            cell.configure(
                item: item,
                usePhysicalSize: usePhysicalSize,
                isSizeUnknown: session.isAffectedBySkippedContent(item)
            )
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
                selectionMutationGate.perform {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                selectionCoordinator.setSelectedItem(item)
                return item
            }
        }

        return selectionCoordinator.selectedItem
    }
}
