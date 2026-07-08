import AppKit
import Combine
import SwiftUI

struct FilesPaneView: View {
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
        outlineView.rowHeight = ScanWindowMetrics.tableRowHeight
        outlineView.intercellSpacing = NSSize(width: ScanWindowMetrics.tableIntercellWidth, height: ScanWindowMetrics.tableIntercellHeight)
        outlineView.indentationPerLevel = ScanWindowMetrics.outlineIndentWidth
        outlineView.allowsMultipleSelection = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .controlBackgroundColor

        let nameColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.name)
        nameColumn.title = "Name"
        nameColumn.minWidth = ScanWindowMetrics.outlineNameColumnMinimumWidth
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn: NSTableColumn = NSTableColumn(identifier: ColumnID.size)
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
            titleTextField.font = NSFont.systemFont(ofSize: ScanWindowMetrics.tableFontSize)
            addSubview(iconImageView)
            addSubview(titleTextField)
            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScanWindowMetrics.outlineCellHorizontalPadding),
                iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: ScanWindowMetrics.outlineIconWidth),
                iconImageView.heightAnchor.constraint(equalToConstant: ScanWindowMetrics.outlineIconWidth),
                titleTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: ScanWindowMetrics.outlineIconTextSpacing),
                titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScanWindowMetrics.outlineCellHorizontalPadding),
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
            sizeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: ScanWindowMetrics.tableFontSize, weight: .regular)
            sizeTextField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sizeTextField)
            NSLayoutConstraint.activate([
                sizeTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScanWindowMetrics.outlineCellHorizontalPadding),
                sizeTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScanWindowMetrics.outlineCellHorizontalPadding),
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
