import Foundation
import Testing
@testable import disk_hog

@MainActor
struct TrashDirectoryCacheTests {
    @Test func transientFailureIsRetriedAndOnlySuccessIsCached() {
        let cache = NSCache<NSString, NSURL>()
        let item = URL(fileURLWithPath: "/trash-cache-fixture/item")
        let resolved = URL(fileURLWithPath: "/trash-cache-fixture/resolved-trash")
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        var attempts = 0
        let resolver: (URL) throws -> URL = { url in
            #expect(url == item)
            attempts += 1
            if attempts == 1 { throw CocoaError(.fileReadUnknown) }
            return resolved
        }

        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == fallback)
        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == resolved)
        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == resolved)
        #expect(attempts == 2)
    }

    @Test func failedForcedRefreshDoesNotLeaveFallbackOrOldValueCached() {
        let cache = NSCache<NSString, NSURL>()
        let item = URL(fileURLWithPath: "/trash-cache-fixture/item")
        let original = URL(fileURLWithPath: "/trash-cache-fixture/old-trash")
        let updated = URL(fileURLWithPath: "/trash-cache-fixture/new-trash")
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        var attempts = 0
        let resolver: (URL) throws -> URL = { _ in
            attempts += 1
            if attempts == 2 { throw CocoaError(.fileReadUnknown) }
            return attempts == 1 ? original : updated
        }

        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == original)
        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, refresh: true, cache: cache, resolve: resolver) == fallback)
        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == updated)
        #expect(DiskItemDeletionPolicy.trashDirectory(for: item, cache: cache, resolve: resolver) == updated)
        #expect(attempts == 3)
    }
}
