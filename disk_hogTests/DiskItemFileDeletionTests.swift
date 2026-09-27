import Foundation
import Testing
@testable import disk_hog

struct DiskItemFileDeletionTests {
    @Test(arguments: [DiskItemDeletionMethod.moveToTrash, .deletePermanently])
    func sharedMutationRejectsProtectedLocations(method: DiskItemDeletionMethod) {
        let protectedURL = URL(fileURLWithPath: "/System/nonexistent-deletion-test-\(UUID().uuidString)")
        #expect(throws: DiskItemDeletionPolicy.Protection.self) {
            try DiskItemFileDeletion.perform(at: protectedURL, using: method)
        }
    }

    @Test func queueAdapterPreservesMissingFileError() {
        let source = ScanSource(path: "/private/tmp", displayName: "Fixture")
        let missing = source.url.appendingPathComponent("missing-deletion-\(UUID().uuidString)")
        do {
            try DiskItemFileDeletion.moveToFinderTrash(itemURL: missing, source: source)
            Issue.record("A missing item must not be reported as successfully trashed")
        } catch {
            #expect((error as? CocoaError)?.code == .fileNoSuchFile)
        }
    }
}
