//
//  disk_hogTests.swift
//  disk_hogTests
//
//

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

    @Test func recursiveScanSkipsItemsWhoseResourceValuesCannotBeRead() throws {
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
        let root: DiskItem = try scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )
        let folder: DiskItem? = root.children.first { $0.name == "folder" }

        #expect(folder != nil)
        #expect(folder?.children.map(\.name) == ["readable.txt"])
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

    private static func hardlinkDuplicateCount(in item: DiskItem) -> Int {
        let currentCount: Int = item.isHardlinkDuplicate ? 1 : 0
        return item.children.reduce(currentCount) { count, child in
            count + hardlinkDuplicateCount(in: child)
        }
    }
}
