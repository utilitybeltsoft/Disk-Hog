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
}
