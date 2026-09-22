import Foundation
import Testing
@testable import disk_hog

struct LargestItemsTests {
    @Test func opaquePackagesAreFilesAndExpandedPackagesAreFolders() {
        let package = DiskItem(url: URL(fileURLWithPath: "/Fixture.app", isDirectory: true),
                               isDirectory: true, isPackage: true)
        #expect(LargestItemsCategory.files.includes(package, lookInsidePackages: false))
        #expect(!LargestItemsCategory.folders.includes(package, lookInsidePackages: false))
        #expect(!LargestItemsCategory.files.includes(package, lookInsidePackages: true))
        #expect(LargestItemsCategory.folders.includes(package, lookInsidePackages: true))
    }

    @Test func specialItemsAreNeverRanked() {
        let item = DiskItem(url: URL(fileURLWithPath: "/unused", isDirectory: false), itemType: .freeSpace)
        for category in LargestItemsCategory.allCases {
            #expect(!category.includes(item, lookInsidePackages: false))
        }
    }

    @Test func limitsAreExplicitlyBounded() {
        var query = LargestItemsQuery()
        query.limit = Int.max
        #expect(query.boundedLimit == 10_000)
        query.limit = 0
        #expect(query.boundedLimit == 1)
    }

    @Test func searchRunsBeforeLimitAndFolderTotalsExcludeScopeRoot() throws {
        let root = DiskItemBuilder(url: URL(fileURLWithPath: "/root", isDirectory: true), isDirectory: true)
        let folder = root.makeChild(url: URL(fileURLWithPath: "/root/folder", isDirectory: true), isDirectory: true)
        folder.appendChild(folder.makeChild(url: URL(fileURLWithPath: "/root/folder/small", isDirectory: false),
                                            allocatedSizeValue: 5, logicalSizeValue: 50))
        root.appendChild(folder)
        root.appendChild(root.makeChild(url: URL(fileURLWithPath: "/root/big", isDirectory: false),
                                       allocatedSizeValue: 100, logicalSizeValue: 10))
        let snapshot = root.freeze()
        var query = LargestItemsQuery()
        query.limit = 1
        #expect(try LargestItemsPipeline.run(root: snapshot, query: query).rows.first?.name == "big")
        query.usesPhysicalSize = false
        #expect(try LargestItemsPipeline.run(root: snapshot, query: query).rows.first?.name == "small")
        query.searchText = "small"
        #expect(try LargestItemsPipeline.run(root: snapshot, query: query).matchingCount == 1)
        query.searchText = ""
        query.category = .folders
        let result = try LargestItemsPipeline.run(root: snapshot, query: query)
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.size == 50)
        #expect(result.rows.first?.id != snapshot.id)
    }

    @Test func packagesAndLinksDoNotLeakDescendantsIntoOpaqueQueries() throws {
        let root = DiskItemBuilder(url: URL(fileURLWithPath: "/root", isDirectory: true), isDirectory: true)
        let package = root.makeChild(url: URL(fileURLWithPath: "/root/app", isDirectory: true),
                                    isDirectory: true, isPackage: true)
        package.appendChild(package.makeChild(url: URL(fileURLWithPath: "/root/app/data", isDirectory: false),
                                              allocatedSizeValue: 50, logicalSizeValue: 50))
        root.appendChild(package)
        let alias = root.makeChild(url: URL(fileURLWithPath: "/root/link", isDirectory: false),
                                  isDirectory: true, isAliasOrSymbolicLink: true)
        alias.appendChild(alias.makeChild(url: URL(fileURLWithPath: "/root/link/hidden", isDirectory: false)))
        root.appendChild(alias)
        let snapshot = root.freeze()
        var query = LargestItemsQuery()
        #expect(try LargestItemsPipeline.run(root: snapshot, query: query).rows.map(\.name).sorted() == ["app", "link"])
        query.lookInsidePackages = true
        #expect(try LargestItemsPipeline.run(root: snapshot, query: query).rows.map(\.name).sorted() == ["data", "link"])
    }
}
