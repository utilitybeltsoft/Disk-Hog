//
//  disk_hogTests.swift
//  disk_hogTests
//
//

import AppKit
import Foundation
import Testing
@testable import disk_hog

struct DiskItemTests {

    @Test func appendChildSetsParentAndUpdatesSizes() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )

        root.appendChild(child)

        #expect(root.childCount == 1)
        #expect(root.child(at: 0) === child)
        #expect(child.parent === root)
        #expect(root.allocatedSizeValue == 4096)
        #expect(root.logicalSizeValue == 12)
    }

    @Test func sizeValueUsesSelectedPhysicalOrLogicalMode() {
        let item: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12
        )

        #expect(item.sizeValue(usePhysicalSize: true) == 4096)
        #expect(item.sizeValue(usePhysicalSize: false) == 12)
    }

    @Test func recalculatesRecursiveFolderSizesAndSortsLikeDiskInventoryZ() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let smallFile: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/2-small.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let largeFile: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/10-large.bin"),
            allocatedSizeValue: 900,
            logicalSizeValue: 900
        )
        let sameSizeByName: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/1-same.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )

        root.appendChild(smallFile, updateSize: false)
        root.appendChild(largeFile, updateSize: false)
        root.appendChild(sameSizeByName, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)

        #expect(root.allocatedSizeValue == 1100)
        #expect(root.children.map(\.displayName) == ["10-large.bin", "2-small.bin", "1-same.bin"])
    }

    @Test func recalculatingLogicalSizeSortsChildrenByLogicalSize() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let allocatedOnly: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/allocated-only.bin"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 0
        )
        let logicalContent: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/logical-content.bin"),
            allocatedSizeValue: 512,
            logicalSizeValue: 128
        )

        root.appendChild(allocatedOnly, updateSize: false)
        root.appendChild(logicalContent, updateSize: false)
        root.recalculateSize(usePhysicalSize: false)

        #expect(root.logicalSizeValue == 128)
        #expect(root.children.map(\.displayName) == ["logical-content.bin", "allocated-only.bin"])
    }

    @Test func duplicateHardlinkContributesZeroSize() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let duplicate: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/duplicate.dat"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 128,
            isHardlinkDuplicate: true
        )

        root.appendChild(duplicate, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)

        #expect(duplicate.allocatedSizeValue == 0)
        #expect(duplicate.logicalSizeValue == 0)
        #expect(root.allocatedSizeValue == 0)
    }

    @Test func opaquePackageKeepsPrestampedSize() {
        let package: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/App.app"),
            allocatedSizeValue: 12345,
            logicalSizeValue: 6789,
            isDirectory: true,
            isPackage: true
        )

        package.recalculateSize(usePhysicalSize: true)

        #expect(package.allocatedSizeValue == 12345)
        #expect(package.logicalSizeValue == 6789)
    }

    @Test func displayPathIsRelativeToRoot() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/file.txt")
        )

        root.appendChild(folder)
        folder.appendChild(file)

        #expect(root.displayPath == "scan")
        #expect(folder.displayPath == "scan/folder")
        #expect(file.displayPath == "scan/folder/file.txt")
    }

    @Test func childURLDerivesFromParentAndSurvivesRemoval() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )

        root.appendChild(child)

        #expect(child.path == "/scan/folder")
        #expect(child.url.path == "/scan/folder")

        root.removeAllChildren()

        #expect(child.path == "/scan/folder")
        #expect(child.url.path == "/scan/folder")
    }
}

struct TreemapDiskItemDataSourceTests {

    @Test func weightUsesSelectedPhysicalOrLogicalSizeMode() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12
        )

        let physicalDataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: root,
            usePhysicalSize: true
        )
        let logicalDataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: root,
            usePhysicalSize: false
        )

        #expect(physicalDataSource.weight(of: root) == 4096)
        #expect(logicalDataSource.weight(of: root) == 12)
    }

    @Test func kindStatisticsUseSelectedPhysicalOrLogicalSizeMode() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let textFile: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )
        root.appendChild(textFile)

        let physicalStatistics: [TreemapKindStatistic] = TreemapDiskItemDataSource.kindStatistics(
            for: root,
            usePhysicalSize: true
        )
        let logicalStatistics: [TreemapKindStatistic] = TreemapDiskItemDataSource.kindStatistics(
            for: root,
            usePhysicalSize: false
        )

        #expect(physicalStatistics.map(\.size) == [4096])
        #expect(logicalStatistics.map(\.size) == [12])
    }
}

struct TreemapViewRendererTests {

    @Test func renderedItemSelectionWorksImmediatelyAfterReload() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )
        root.appendChild(child)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()

        #expect(renderer.selectItem(byRenderedItem: child) == true)
        #expect(renderer.selectedItem === child)
    }

    @Test func emptyFolderCanBeMappedToItsTreemapRectWhenItHasArea() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let emptyFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/empty"),
            isDirectory: true
        )
        root.appendChild(emptyFolder)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 100)

        renderer.reloadData()
        renderer.calcLayout(bounds)

        #expect(renderer.selectItem(byRenderedItem: emptyFolder) == true)
        #expect(renderer.itemRect(by: renderer.selectedCellID) == bounds)
        #expect(renderer.item(by: renderer.cellID(by: NSPoint(x: 100, y: 50), inViewCoordinates: false)!) === emptyFolder)
    }

    @Test func wholeTreemapSelectionRectLeavesRoomForStroke() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 0, y: 0, width: 200, height: 100),
            in: NSRect(x: 0, y: 0, width: 200, height: 100),
            minimumSide: 12,
            edgeInset: 2.5
        )

        #expect(visibleRect == NSRect(x: 2.5, y: 2.5, width: 195, height: 95))
    }

    @Test func zeroSizedSelectionRectExpandsAroundItsPosition() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 150, y: 40, width: 0, height: 0),
            in: NSRect(x: 0, y: 0, width: 200, height: 100),
            minimumSide: 12,
            edgeInset: 2.5
        )

        #expect(visibleRect == NSRect(x: 144, y: 34, width: 12, height: 12))
    }
}

struct DiskInventoryZScannerTests {

    @Test func concurrentScansKeepHardlinkDedupStateIsolated() async throws {
        let firstRootURL: URL = try Self.makeHardlinkFixture(named: "first")
        let secondRootURL: URL = try Self.makeHardlinkFixture(named: "second")
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }

        async let firstScan: DiskItem = DiskInventoryZScanner().scan(
            source: ScanSource(path: firstRootURL.path, displayName: firstRootURL.lastPathComponent)
        )
        async let secondScan: DiskItem = DiskInventoryZScanner().scan(
            source: ScanSource(path: secondRootURL.path, displayName: secondRootURL.lastPathComponent)
        )

        let firstRoot: DiskItem = try await firstScan
        let secondRoot: DiskItem = try await secondScan

        #expect(Self.hardlinkDuplicateCount(in: firstRoot) == 1)
        #expect(Self.hardlinkDuplicateCount(in: secondRoot) == 1)
    }

    @Test func parallelTopLevelScanDeduplicatesHardlinksAcrossSubtrees() async throws {
        let rootURL: URL = try Self.makeCrossTopLevelHardlinkFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )

        #expect(Self.hardlinkDuplicateCount(in: root) == 1)
    }

    @Test func scanProgressBytesDoNotMoveBackwards() async throws {
        let rootURL: URL = try Self.makeCrossTopLevelHardlinkFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let progressRecorder: ProgressRecorder = ProgressRecorder()

        _ = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        ) { progress in
            await progressRecorder.record(progress)
        }

        let byteCounts: [UInt64] = await progressRecorder.byteCounts
        #expect(zip(byteCounts, byteCounts.dropFirst()).allSatisfy { previous, next in
            previous <= next
        })
    }

    @Test func scanCancellationStopsConcurrentSubtreeWork() async throws {
        let rootURL: URL = try Self.makeCancellationFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let resourceValueReadCounter: LockedCounter = LockedCounter()
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            resourceValueReadCounter.increment()
            Thread.sleep(forTimeInterval: 0.002)
            return try url.resourceValues(forKeys: keys)
        }

        let scanTask: Task<DiskItem, Error> = Task {
            try await scanner.scan(
                source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
            )
        }

        while resourceValueReadCounter.value == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }

        scanTask.cancel()

        do {
            _ = try await scanTask.value
            Issue.record("Expected scan cancellation to throw CancellationError.")
        } catch is CancellationError {
            #expect(true)
        }
    }

    @Test func recursiveScanSkipsItemsWhoseResourceValuesCannotBeRead() async throws {
        let rootURL: URL = try Self.makeUnreadableResourceValueFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            if url.lastPathComponent == "vanished.dat" {
                throw CocoaError(.fileNoSuchFile)
            }

            return try url.resourceValues(forKeys: keys)
        }
        let root: DiskItem = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )
        let folder: DiskItem? = root.children.first { $0.name == "folder" }

        #expect(folder != nil)
        #expect(folder?.children.map(\.name) == ["readable.txt"])
    }

    @Test func topLevelScanSkipsItemsWhoseResourceValuesCannotBeRead() async throws {
        let rootURL: URL = try Self.makeUnreadableTopLevelResourceValueFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            if url.lastPathComponent == "vanished.dat" {
                throw CocoaError(.fileNoSuchFile)
            }

            return try url.resourceValues(forKeys: keys)
        }
        let root: DiskItem = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )

        #expect(root.children.map(\.name) == ["readable.txt"])
    }

    @Test func topLevelScanSortsChildrenByLogicalSizeWhenConfigured() async throws {
        let rootURL: URL = try Self.makeLogicalSortFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            settings: DiskScanSettings(
                usePhysicalSize: false,
                lookInsidePackages: false,
                ignoreCreatorCode: false
            )
        )

        #expect(root.children.map(\.name) == ["sparse-logical-large.bin", "dense-allocated.bin"])
    }

    @Test func opaquePackageKeepsSeparateAllocatedAndLogicalSizes() async throws {
        let rootURL: URL = try Self.makeOpaquePackageFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            settings: DiskScanSettings(
                usePhysicalSize: false,
                lookInsidePackages: false,
                ignoreCreatorCode: true
            )
        )
        let package: DiskItem? = root.children.first { $0.name == "Example.app" }

        #expect(package != nil)
        #expect(package?.logicalSizeValue == 17)
        #expect(package?.allocatedSizeValue != package?.logicalSizeValue)
    }

    private static func makeHardlinkFixture(named name: String) throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-\(name)-\(UUID().uuidString)", isDirectory: true)
        let folderURL: URL = rootURL.appendingPathComponent("folder", isDirectory: true)
        let originalURL: URL = folderURL.appendingPathComponent("original.dat")
        let linkedURL: URL = folderURL.appendingPathComponent("linked.dat")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 4096).write(to: originalURL)
        try FileManager.default.linkItem(at: originalURL, to: linkedURL)

        return rootURL
    }

    private static func makeCrossTopLevelHardlinkFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-cross-top-hardlinks-\(UUID().uuidString)", isDirectory: true)
        let firstFolderURL: URL = rootURL.appendingPathComponent("first", isDirectory: true)
        let secondFolderURL: URL = rootURL.appendingPathComponent("second", isDirectory: true)
        let originalURL: URL = firstFolderURL.appendingPathComponent("shared.dat")
        let linkedURL: URL = secondFolderURL.appendingPathComponent("shared-link.dat")

        try FileManager.default.createDirectory(at: firstFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolderURL, withIntermediateDirectories: true)
        try Data(repeating: 0x48, count: 4096).write(to: originalURL)
        try FileManager.default.linkItem(at: originalURL, to: linkedURL)

        return rootURL
    }

    private static func makeCancellationFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-cancellation-\(UUID().uuidString)", isDirectory: true)

        for folderIndex: Int in 0..<8 {
            let folderURL: URL = rootURL.appendingPathComponent("folder-\(folderIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for fileIndex: Int in 0..<80 {
                try Data(repeating: UInt8(fileIndex % 255), count: 128)
                    .write(to: folderURL.appendingPathComponent("file-\(fileIndex).dat"))
            }
        }

        return rootURL
    }

    private static func makeUnreadableResourceValueFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-unreadable-values-\(UUID().uuidString)", isDirectory: true)
        let folderURL: URL = rootURL.appendingPathComponent("folder", isDirectory: true)
        let readableURL: URL = folderURL.appendingPathComponent("readable.txt")
        let vanishedURL: URL = folderURL.appendingPathComponent("vanished.dat")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "readable".write(to: readableURL, atomically: true, encoding: .utf8)
        try Data(repeating: 0x7A, count: 128).write(to: vanishedURL)

        return rootURL
    }

    private static func makeUnreadableTopLevelResourceValueFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-unreadable-top-level-values-\(UUID().uuidString)", isDirectory: true)
        let readableURL: URL = rootURL.appendingPathComponent("readable.txt")
        let vanishedURL: URL = rootURL.appendingPathComponent("vanished.dat")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "readable".write(to: readableURL, atomically: true, encoding: .utf8)
        try Data(repeating: 0x7A, count: 128).write(to: vanishedURL)

        return rootURL
    }

    private static func makeLogicalSortFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-logical-sort-\(UUID().uuidString)", isDirectory: true)
        let denseAllocatedURL: URL = rootURL.appendingPathComponent("dense-allocated.bin")
        let sparseLogicalLargeURL: URL = rootURL.appendingPathComponent("sparse-logical-large.bin")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: denseAllocatedURL)
        FileManager.default.createFile(atPath: sparseLogicalLargeURL.path, contents: nil)
        let sparseFileHandle: FileHandle = try FileHandle(forWritingTo: sparseLogicalLargeURL)
        try sparseFileHandle.truncate(atOffset: 1_048_576)
        try sparseFileHandle.close()

        return rootURL
    }

    private static func makeOpaquePackageFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-opaque-package-\(UUID().uuidString)", isDirectory: true)
        let contentsURL: URL = rootURL
            .appendingPathComponent("Example.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL: URL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Data(repeating: 0x49, count: 5).write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x50, count: 12).write(to: resourcesURL.appendingPathComponent("payload.txt"))

        return rootURL
    }

    private static func hardlinkDuplicateCount(in item: DiskItem) -> Int {
        let currentCount: Int = item.isHardlinkDuplicate ? 1 : 0
        return item.children.reduce(currentCount) { count, child in
            count + hardlinkDuplicateCount(in: child)
        }
    }
}

private actor ProgressRecorder {
    private(set) var byteCounts: [UInt64] = []

    func record(_ progress: DiskScanProgress) {
        byteCounts.append(progress.scannedByteCount)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var count: Int = 0

    var value: Int {
        lock.withLock {
            count
        }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
