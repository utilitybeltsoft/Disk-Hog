import AppKit
import SwiftUI
import Testing
@testable import disk_hog

private struct RankedWorkflowScanner: ScanSessionScanning {
    let root: DiskItem
    func scan(source: ScanSource, settings: DiskScanSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        ScanSessionScanResult(source: source, rootItem: root,
            presentationMetrics: TreemapPresentationMetrics(rootItem: root, usePhysicalSize: true),
            builtUsingPhysicalSize: true, skippedItems: [])
    }
}

/// Exercise the actual SwiftUI ranking task, AppKit table and selection wiring.
/// No filesystem scan, global queue or installed app is involved.
@MainActor
@Suite(.serialized)
struct RankedViewWorkflowTests {
    private func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    @Test(arguments: LargestItemsCategory.allCases)
    func rankedViewLoadsDescendingRowsAndSynchronizesSelection(category: LargestItemsCategory) async throws {
        let largeFile = DiskItem(url: URL(fileURLWithPath: "/workflow-fixture/large/big.bin"),
                                allocatedSizeValue: 65536, logicalSizeValue: 65536, kindName: "Test")
        let smallFile = DiskItem(url: URL(fileURLWithPath: "/workflow-fixture/small/tiny.bin"),
                                allocatedSizeValue: 4096, logicalSizeValue: 4096, kindName: "Test")
        let largeFolder = DiskItem(url: URL(fileURLWithPath: "/workflow-fixture/large"),
                                  allocatedSizeValue: 65536, logicalSizeValue: 65536,
                                  isDirectory: true, children: [largeFile])
        let smallFolder = DiskItem(url: URL(fileURLWithPath: "/workflow-fixture/small"),
                                  allocatedSizeValue: 4096, logicalSizeValue: 4096,
                                  isDirectory: true, children: [smallFile])
        let root = DiskItem(url: URL(fileURLWithPath: "/workflow-fixture"),
                            allocatedSizeValue: 69632, logicalSizeValue: 69632, isDirectory: true,
                            children: [smallFolder, largeFolder])
        let session = ScanSession(source: ScanSource(path: root.url.path, displayName: "Fixture"),
                                  scanWorker: RankedWorkflowScanner(root: root))
        let selection = ScanWindowSelectionCoordinator()
        let navigation = TreemapNavigationState()
        session.startScan()
        defer { session.cancel() }
        let scanDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.rootItem == nil && ContinuousClock.now < scanDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try #require(session.rootItem)
        navigation.configure(baseRoot: session.rootItem)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var didShowTree = false
        window.contentView = NSHostingView(rootView: LargestItemsView(
            session: session, selectionCoordinator: selection, navigation: navigation,
            category: category, isActive: true, onShowTree: { didShowTree = true }))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        let content = try #require(window.contentView)
        let tableDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while table(in: content)?.numberOfRows != 2 && ContinuousClock.now < tableDeadline {
            content.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let table = try #require(self.table(in: content))
        #expect(table.numberOfRows == 2)
        #expect(table.tableColumns[1].title == "Size on disk")
        // Constructing a parent packs its descendants into that parent's snapshot.
        // Select the session's actual nodes, not the standalone fixture wrappers.
        let scannedRoot = try #require(session.rootItem)
        let rankedFolders = scannedRoot.children.sorted { $0.allocatedSizeValue > $1.allocatedSizeValue }
        let expected = category == .files ? rankedFolders.flatMap(\.children) : rankedFolders
        for (row, item) in expected.enumerated() {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while selection.selectedItem?.id != item.id && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(selection.selectedItem?.id == item.id)
        }
        // An external non-treemap selection must highlight the matching ranked row.
        selection.setSelectedItem(expected[0])
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while table.selectedRow != 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(table.selectedRow == 0)
        let coordinator = try #require(table.delegate as? SelectionListTableView.Coordinator)
        let action = NSMenuItem()
        action.tag = RankedItemAction.folderTree.rawValue
        coordinator.performRankedAction(action)
        #expect(didShowTree)
        #expect(selection.selectedItem?.id == expected[0].id)
        action.tag = RankedItemAction.treemap.rawValue
        coordinator.performRankedAction(action)
        #expect(navigation.zoomRoot?.path == largeFolder.path)
        #expect(navigation.canZoomOut)
        navigation.zoomOut()
        #expect(navigation.zoomRoot?.id == root.id)
    }
}
