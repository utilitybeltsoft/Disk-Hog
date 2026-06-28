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
