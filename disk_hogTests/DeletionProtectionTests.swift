import Foundation
import Testing
@testable import disk_hog

/// Adversarial checks that the wrong files can never reach the trash. No test
/// touches the user's real Trash: filesystem mutation is always injected.
@MainActor
struct DeletionProtectionTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func record(_ url: URL) { lock.withLock { urls.append(url) } }
        var recorded: [URL] { lock.withLock { urls } }
    }

    private static func item(_ path: String, folder: Bool = false, children: [DiskItem] = []) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), allocatedSizeValue: 10, logicalSizeValue: 10,
                 isDirectory: folder, children: children, isRoot: false)
    }

    private static func session(_ path: String = "/tmp/protection-fixture") -> ScanSession {
        ScanSession(source: ScanSource(path: path, displayName: "Protection Fixture"))
    }

    private static func drain(_ store: CleanupQueueStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while store.items.contains(where: { $0.status == .processing }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.items.contains(where: { $0.status == .processing }), "Queue processing timed out")
    }

    // MARK: Protections that exist

    @Test func scanRootAndSyntheticSpaceItemsAreNeverDeletable() {
        let root = DiskItem(url: URL(fileURLWithPath: "/tmp/protection-fixture"), isDirectory: true)
        let free = DiskItem(url: URL(fileURLWithPath: "/tmp/protection-fixture"), itemType: .freeSpace,
                            allocatedSizeValue: 5, logicalSizeValue: 5, isRoot: false)
        let other = DiskItem(url: URL(fileURLWithPath: "/tmp/protection-fixture"), itemType: .otherSpace,
                             allocatedSizeValue: 5, logicalSizeValue: 5, isRoot: false)
        for item in [root, free, other] {
            #expect(!DiskItemDeletionPolicy.canDelete(item))
            let store = CleanupQueueStore(trashItem: { _, _ in })
            #expect(!store.enqueue(item, from: Self.session()))
            #expect(store.items.isEmpty)
        }
    }

    @Test func batchEnqueueDropsProtectedItemsButKeepsOrdinaryOnes() {
        let root = DiskItem(url: URL(fileURLWithPath: "/tmp/protection-fixture"), isDirectory: true)
        let free = DiskItem(url: URL(fileURLWithPath: "/tmp/protection-fixture"), itemType: .freeSpace, isRoot: false)
        let ordinary = Self.item("/tmp/protection-fixture/ok.txt")
        let store = CleanupQueueStore(trashItem: { _, _ in })
        store.enqueue([root, free, ordinary], from: Self.session())
        #expect(store.items.map(\.itemURL) == [ordinary.url.standardizedFileURL])
    }

    @Test func realTrashAndItsContentsAreRefusedUsingTheSystemResolvedTrash() throws {
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false)
        let inTrash = Self.item(trash.appendingPathComponent("old.txt").path)
        #expect(!DiskItemDeletionPolicy.canDelete(inTrash))
        #expect(!DiskItemDeletionPolicy.canDelete(Self.item(trash.path, folder: true)))
        let store = CleanupQueueStore(trashItem: { _, _ in })
        #expect(!store.enqueue(inTrash, from: Self.session()))
        #expect(store.items.isEmpty)
    }

    @Test func sessionDeleteRefusesProtectedItemsWithoutTouchingTheFilesystem() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-protect-\(UUID().uuidString)")
        let scanRoot = base.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data(repeating: 1, count: 8).write(to: scanRoot.appendingPathComponent("a.txt"))

        let recorder = Recorder()
        let session = ScanSession(
            source: ScanSource(path: scanRoot.path, displayName: "fixture"),
            treeWorker: DiskInventoryZScanSessionTreeWorker(performDeletion: { url, _ in recorder.record(url) })
        )
        session.startScan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.state == .scanning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { session.cancel() }
        let root = try #require(session.rootItem)
        session.delete(root, using: .moveToTrash)
        session.delete(root, using: .deletePermanently)
        if let free = session.freeSpaceItem { session.delete(free, using: .deletePermanently) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.recorded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: scanRoot.path))
    }

    @Test func onlySelectedReadyEntriesReachTheTrashAndNeverTheirUnqueuedNeighbours() async throws {
        let recorder = Recorder()
        let store = CleanupQueueStore(trashItem: { url, _ in recorder.record(url) }, reconcileSession: { _, _ in })
        let session = Self.session()
        let a = Self.item("/tmp/protection-fixture/a.txt")
        let b = Self.item("/tmp/protection-fixture/b.txt")
        let c = Self.item("/tmp/protection-fixture/c.txt")
        for i in [a, b, c] { #expect(store.enqueue(i, from: session)) }
        store.setSelected(false, for: try #require(store.items.first { $0.itemURL == b.url.standardizedFileURL }?.id))
        // Sibling with a common prefix must never be treated as covered by a queued folder.
        let folder = Self.item("/tmp/protection-fixture/dir", folder: true)
        let lookalike = Self.item("/tmp/protection-fixture/dir-backup/x.txt")
        #expect(store.enqueue(folder, from: session))
        #expect(!store.contains(lookalike))
        #expect(store.enqueue(lookalike, from: session))
        store.moveSelectedItemsToFinderTrash()
        try await Self.drain(store)
        let trashed = Set(recorder.recorded.map(\.path))
        #expect(trashed == Set([a, c, folder, lookalike].map { $0.url.standardizedFileURL.path }))
        #expect(!trashed.contains(b.path))
    }

    @Test func itemRemovedFromQueueWhileProcessingIsNotTrashed() async throws {
        let recorder = Recorder()
        let store = CleanupQueueStore(trashItem: { url, _ in recorder.record(url) }, reconcileSession: { _, _ in })
        let session = Self.session()
        let first = Self.item("/tmp/protection-fixture/first.txt")
        let second = Self.item("/tmp/protection-fixture/second.txt")
        #expect(store.enqueue(first, from: session))
        #expect(store.enqueue(second, from: session))
        store.moveSelectedItemsToFinderTrash()
        store.remove(second)
        try await Self.drain(store)
        #expect(!recorder.recorded.map(\.path).contains(second.url.standardizedFileURL.path))
    }

    @Test func secondTrashRequestWhileFirstIsInFlightCannotTrashAnythingTwice() async throws {
        let recorder = Recorder()
        let store = CleanupQueueStore(trashItem: { url, _ in recorder.record(url) }, reconcileSession: { _, _ in })
        #expect(store.enqueue(Self.item("/tmp/protection-fixture/once.txt"), from: Self.session()))
        store.moveSelectedItemsToFinderTrash()
        store.moveSelectedItemsToFinderTrash()
        try await Self.drain(store)
        #expect(recorder.recorded.count == 1)
    }

    @Test func symlinkIsQueuedAndTrashedAsTheLinkNeverItsTarget() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-symlink-\(UUID().uuidString)")
        let scanRoot = base.appendingPathComponent("scan")
        let precious = base.appendingPathComponent("precious")
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: precious, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: precious.appendingPathComponent("keep.txt"))
        let link = scanRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: precious)
        defer { try? FileManager.default.removeItem(at: base) }

        let root = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: scanRoot.path, displayName: "fixture"),
            settings: .diskInventoryZDefault).item
        let linkItem = try #require(root.item(atPath: link.path))
        #expect(!linkItem.isFolder)

        let recorder = Recorder()
        let store = CleanupQueueStore(trashItem: { url, _ in recorder.record(url) }, reconcileSession: { _, _ in })
        #expect(store.enqueue(linkItem, from: Self.session(scanRoot.path)))
        store.moveSelectedItemsToFinderTrash()
        try await Self.drain(store)
        #expect(recorder.recorded.map(\.path) == [link.standardizedFileURL.path])
        #expect(FileManager.default.fileExists(atPath: precious.appendingPathComponent("keep.txt").path))
    }

    // MARK: Protected locations and queue identity

    @Test func criticalLocationsShouldBeProtectedFromQueueing() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let critical: [(String, Bool)] = [
            ("/System", true), ("/System/Library", true), ("/Applications", true), ("/Users", true),
            ("/Library", true), ("/usr", true), ("/private", true), (home, true),
            ("\(home)/Library", true), ("\(home)/Documents", true), ("\(home)/Desktop", true),
            (Bundle.main.bundleURL.path, true),
        ]
        for (path, folder) in critical {
            let item = Self.item(path, folder: folder)
            #expect(!DiskItemDeletionPolicy.canDelete(item))
        }
    }

    @Test func runningApplicationBundleShouldBeProtected() {
        let item = Self.item(Bundle.main.bundleURL.path, folder: true)
        #expect(!DiskItemDeletionPolicy.canDelete(item))
    }

    @Test func externalVolumeTrashContentsShouldBeProtected() {
        let item = Self.item("/Volumes/Backup/.Trashes/501/old.txt")
        #expect(!DiskItemDeletionPolicy.canDelete(item))
    }

    @Test func queuedFolderShouldNotSilentlyDropASymlinkThatOnlyResolvesInsideIt() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-linkdrop-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link-into-folder")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: base) }

        let store = CleanupQueueStore(trashItem: { _, _ in })
        let session = Self.session(base.path)
        let linkItem = DiskItem(url: link, allocatedSizeValue: 1, logicalSizeValue: 1,
                                isDirectory: true, isAliasOrSymbolicLink: true, isRoot: false)
        #expect(store.enqueue(linkItem, from: session))
        #expect(store.enqueue(Self.item(folder.path, folder: true), from: session))
        #expect(store.items.contains { $0.itemURL.lastPathComponent == "link-into-folder" })
    }

    @Test func otherUsersAndCustomHomesProtectContainersButAllowOrdinaryContents() {
        let homes = [URL(fileURLWithPath: "/Users/protection-other"),
                     URL(fileURLWithPath: "/Volumes/Homes/custom-user")]
        for home in homes {
            for suffix in ["", "Library", "Documents", "Desktop"] {
                let url = suffix.isEmpty ? home : home.appendingPathComponent(suffix)
                #expect(DiskItemDeletionPolicy.protection(for: url, homeDirectories: homes) == .protectedLocation)
                #expect(DiskItemDeletionPolicy.protection(for: url.appendingPathComponent("ordinary.txt"), homeDirectories: homes) == nil)
            }
            #expect(DiskItemDeletionPolicy.protection(for: home.appendingPathComponent(".Trash/old.txt"), homeDirectories: homes) == .trash)
        }
        // Structural /Users fallback survives an empty account lookup.
        #expect(DiskItemDeletionPolicy.protection(for: homes[0].appendingPathComponent("Desktop"), homeDirectories: []) == .protectedLocation)
        #expect(DiskItemDeletionPolicy.protection(for: homes[1].deletingLastPathComponent(), homeDirectories: homes) != nil)
    }

    @Test func protectedItemsAreRejectedInSingleAndBatchQueues() {
        let session = Self.session()
        let store = CleanupQueueStore(trashItem: { _, _ in })
        let paths = ["/", "/System/Library", "/Applications", "/Users/someone/Desktop",
                     "/Users/someone", "/Volumes/Backup", "/Volumes/Backup/.Trashes/502/old.txt",
                     Bundle.main.bundleURL.path, Bundle.main.bundleURL.deletingLastPathComponent().path]
        let blocked = paths.map { Self.item($0, folder: true) }
        for item in blocked { #expect(!store.enqueue(item, from: session)) }
        let ordinary = Self.item("/tmp/protection-fixture/ordinary.txt")
        store.enqueue(blocked + [ordinary], from: session)
        #expect(store.items.map(\.itemURL) == [ordinary.url.standardizedFileURL])
    }

    @Test func applicationAndVolumeTrashRulesHaveComponentBoundaries() {
        let app = URL(fileURLWithPath: "/tmp/deletion-app-fixture/Disk Hog.app")
        for url in [app, app.appendingPathComponent("Contents/code"), app.deletingLastPathComponent()] {
            #expect(DiskItemDeletionPolicy.protection(for: url, applicationURL: app) == .runningApplication)
        }
        #expect(DiskItemDeletionPolicy.protection(for: URL(fileURLWithPath: app.path + "-backup"), applicationURL: app) == nil)
        let volume = URL(fileURLWithPath: "/tmp/custom-mount")
        #expect(DiskItemDeletionPolicy.protection(for: volume.appendingPathComponent(".Trashes/900/file"), volumeURL: volume) == .trash)
        for path in ["/Volumes/Backup/folder/.Trashes/file", "/Volumes/Backup/.Trashes-backup/file",
                     "/tmp/ordinary/.Trashes/file", "/Applications/Ordinary.app", "/Library/Caches/ordinary"] {
            #expect(DiskItemDeletionPolicy.protection(for: URL(fileURLWithPath: path)) == nil)
        }
    }

    @Test func symlinkQueueCoverageWorksInBothOrdersAndBatches() throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-links-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("folder")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let inside = folder.appendingPathComponent("outward-link")
        try FileManager.default.createSymbolicLink(at: inside, withDestinationURL: base.appendingPathComponent("absent"))
        defer { try? FileManager.default.removeItem(at: base) }
        let linkItem = Self.item(link.path)
        let folderItem = Self.item(folder.path, folder: true)
        let insideItem = Self.item(inside.path)
        for batch in [false, true] {
            for ordered in [[linkItem, insideItem, folderItem], [folderItem, insideItem, linkItem]] {
                let store = CleanupQueueStore(trashItem: { _, _ in })
                let session = Self.session(base.path)
                if batch { store.enqueue(ordered, from: session) }
                else { for item in ordered { _ = store.enqueue(item, from: session) } }
                #expect(Set(store.items.map { $0.itemURL.lastPathComponent }) == ["folder", "link"])
            }
        }
    }

    @Test func parentAliasesShareQueueIdentityWithoutFollowingTheFinalLink() throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-alias-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("folder")
        let alias = base.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = CleanupQueueStore(trashItem: { _, _ in })
        let session = Self.session(base.path)
        let original = Self.item(folder.appendingPathComponent("file").path)
        let alternate = Self.item(alias.appendingPathComponent("file").path)
        #expect(store.enqueue(original, from: session))
        #expect(store.contains(alternate))
        #expect(store.isDirectlyQueued(alternate))
        #expect(!store.enqueue(alternate, from: session))
        store.remove(alternate)
        #expect(store.items.isEmpty)
        // The final link itself remains eligible even when it points at System.
        let systemLink = base.appendingPathComponent("system-link")
        try FileManager.default.createSymbolicLink(at: systemLink, withDestinationURL: URL(fileURLWithPath: "/System"))
        #expect(DiskItemDeletionPolicy.canDelete(Self.item(systemLink.path)))
        #expect(!DiskItemDeletionPolicy.canDelete(Self.item(systemLink.appendingPathComponent("Library").path)))
    }

    @Test func queuedPathIsRevalidatedAfterItsParentBecomesASymlink() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/disk-hog-recheck-\(UUID().uuidString)")
        let parent = base.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let recorder = Recorder()
        let store = CleanupQueueStore(trashItem: { url, _ in recorder.record(url) })
        let session = Self.session(base.path)
        #expect(store.enqueue(Self.item(parent.appendingPathComponent("Library").path, folder: true), from: session))
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: URL(fileURLWithPath: "/System"))
        store.moveSelectedItemsToFinderTrash()
        try await Self.drain(store)
        #expect(recorder.recorded.isEmpty)
        #expect(store.items.first?.status == .protected)
    }

    @Test func workerRejectsProtectedPathsForBothDeletionMethods() async throws {
        let recorder = Recorder()
        let worker = DiskInventoryZScanSessionTreeWorker(performDeletion: { url, _ in recorder.record(url) })
        let root = DiskItem(url: URL(fileURLWithPath: "/"), isDirectory: true)
        for method: DiskItemDeletionMethod in [.moveToTrash, .deletePermanently] {
            do {
                _ = try await worker.delete(item: Self.item("/System/Library", folder: true),
                    deletionMethod: method, currentRoot: root,
                    source: ScanSource(path: "/", displayName: "fixture"), settings: .diskInventoryZDefault, presentation: ScanPresentationSettings())
                Issue.record("Protected deletion should throw")
            } catch is DiskItemDeletionPolicy.Protection { }
        }
        #expect(recorder.recorded.isEmpty)
    }

}
