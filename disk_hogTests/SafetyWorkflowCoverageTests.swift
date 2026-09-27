import Foundation
import Testing
@testable import disk_hog

@MainActor
struct CleanupQueueSafetyCoverageTests {
    private func waitForCompletion(_ store: CleanupQueueStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.items.contains(where: { $0.status == .processing }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.items.contains { $0.status == .processing })
    }

    @Test(arguments: [CocoaError.Code.fileWriteNoPermission, .fileNoSuchFile, .fileWriteVolumeReadOnly])
    func failedQueueMutationKeepsEntryWithActionableStatus(code: CocoaError.Code) async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let item = try #require(root.item(atPath: fixture.root.appendingPathComponent("victim.txt").path))
        let session = ScanSession(source: fixture.source)
        var refreshes = 0
        let store = CleanupQueueStore(trashItem: { _, _ in throw CocoaError(code) },
                                      refreshSession: { _ in refreshes += 1 })
        #expect(store.enqueue(item, from: session))
        store.moveSelectedItemsToFinderTrash()
        try await waitForCompletion(store)
        let retained = try #require(store.items.first)
        switch code {
        case .fileWriteNoPermission: #expect(retained.status == .inaccessible)
        case .fileNoSuchFile: #expect(retained.status == .missing)
        case .fileWriteVolumeReadOnly: #expect(retained.status == .cannotMoveToTrash)
        default: Issue.record("Unexpected test case")
        }
        #expect(store.items.count == 1)
        #expect(refreshes == 0)
        #expect(FileManager.default.fileExists(atPath: item.path))
        #expect(store.selectedReadyItems.isEmpty)
    }

    @Test func successfulQueueMutationLeavesUnselectedItemAndRefreshesSession() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let victim = try #require(root.item(atPath: fixture.root.appendingPathComponent("victim.txt").path))
        let keep = try #require(root.item(atPath: fixture.root.appendingPathComponent("keep.txt").path))
        let session = ScanSession(source: fixture.source)
        let destination = fixture.base.appendingPathComponent("simulated-trash")
        var refreshed: [ScanSession] = []
        let store = CleanupQueueStore(trashItem: { url, _ in
            try FileManager.default.moveItem(at: url, to: destination)
        }, refreshSession: { refreshed.append($0) })
        #expect(store.enqueue(victim, from: session))
        #expect(store.enqueue(keep, from: session))
        let keepID = try #require(store.items.first { $0.itemURL == keep.url.standardizedFileURL }?.id)
        store.setSelected(false, for: keepID)
        store.moveSelectedItemsToFinderTrash()
        try await waitForCompletion(store)
        #expect(store.items.map(\.id) == [keepID])
        #expect(refreshed.count == 1)
        #expect(refreshed.first === session)
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(!FileManager.default.fileExists(atPath: victim.path))
        #expect(try Data(contentsOf: destination).count == 8)
    }

    @Test func queueRejectsRootAndSuppressesDescendantsOfQueuedFolder() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let folder = fixture.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("child"))
        let root = try await fixture.scan()
        let parent = try #require(root.item(atPath: folder.path))
        let child = try #require(root.item(atPath: folder.appendingPathComponent("child").path))
        let session = ScanSession(source: fixture.source)
        let store = CleanupQueueStore()
        #expect(!store.enqueue(root, from: session))
        #expect(store.enqueue(child, from: session))
        #expect(store.enqueue(parent, from: session))
        #expect(!store.enqueue(child, from: session))
        #expect(store.items.map(\.itemURL) == [parent.url.standardizedFileURL])
        #expect(store.contains(child))
        #expect(!store.isDirectlyQueued(child))
    }
}

/// All mutations are confined to a unique fixture; never use the user's Trash.
private struct SafetyFixture {
    let base: URL
    let root: URL
    var source: ScanSource { ScanSource(path: root.path, displayName: "Safety fixture") }
    var settings: DiskScanSettings { DiskScanSettings(usePhysicalSize: false, lookInsidePackages: true) }

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("disk-hog-safety-\(UUID().uuidString)")
        root = base.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: root.appendingPathComponent("victim.txt"))
        try Data(repeating: 2, count: 16).write(to: root.appendingPathComponent("keep.txt"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: base) }
    func scan() async throws -> DiskItem {
        try await DiskInventoryZScanner().scan(source: source, settings: settings).item
    }
}

@MainActor
struct DeletionSafetyCoverageTests {
    @Test(arguments: [CocoaError.Code.fileWriteNoPermission, .fileWriteVolumeReadOnly, .fileNoSuchFile],
          [DiskItemDeletionMethod.moveToTrash, .deletePermanently])
    func failedMutationPreservesFileAndSnapshot(code: CocoaError.Code, method: DiskItemDeletionMethod) async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let victim = try #require(root.item(atPath: fixture.root.appendingPathComponent("victim.txt").path))
        let worker = DiskInventoryZScanSessionTreeWorker(performDeletion: { _, _ in throw CocoaError(code) })
        do {
            _ = try await worker.delete(item: victim, deletionMethod: method, currentRoot: root,
                                        source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings())
            Issue.record("A failed filesystem mutation must not produce a successful tree update.")
        } catch let error as CocoaError {
            #expect(error.code == code)
        }
        #expect(try Data(contentsOf: victim.url) == Data(repeating: 1, count: 8))
        #expect(root.item(atPath: victim.path)?.logicalSizeValue == 8)
        #expect(root.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
    }

    @Test func trashMoveReconcilesAfterCancellationAndPreservesSibling() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let victim = try #require(root.item(atPath: fixture.root.appendingPathComponent("victim.txt").path))
        let trashDestination = fixture.base.appendingPathComponent("simulated-trash.txt")
        let worker = DiskInventoryZScanSessionTreeWorker(performDeletion: { url, method in
            guard case .moveToTrash = method else {
                throw CocoaError(.featureUnsupported)
            }
            try FileManager.default.moveItem(at: url, to: trashDestination)
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let result = try await Task {
            try await worker.delete(item: victim, deletionMethod: .moveToTrash, currentRoot: root,
                                    source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings())
        }.value
        #expect(!FileManager.default.fileExists(atPath: victim.path))
        #expect(try Data(contentsOf: trashDestination).count == 8)
        #expect(result.rootItem.item(atPath: victim.path) == nil)
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
        #expect(result.selectionPath == fixture.root.path)
        #expect(result.rootItem.logicalSizeValue == root.logicalSizeValue - 8)
        #expect(result.refreshedSubtreePath == victim.path)
        #expect(result.skippedItems.isEmpty)
    }

    @Test func cancelledTrashRequestNeverCallsMutation() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let victim = try #require(root.item(atPath: fixture.root.appendingPathComponent("victim.txt").path))
        let marker = fixture.base.appendingPathComponent("mutation-was-called")
        let worker = DiskInventoryZScanSessionTreeWorker(performDeletion: { _, _ in
            try Data().write(to: marker)
        })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.delete(item: victim, deletionMethod: .moveToTrash, currentRoot: root,
                                           source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test func refreshOfVanishedNestedItemRescansNearestSurvivingAncestor() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let folder = fixture.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("gone.txt")
        try Data(repeating: 3, count: 7).write(to: file)
        let root = try await fixture.scan()
        let oldItem = try #require(root.item(atPath: file.path))
        try FileManager.default.removeItem(at: folder)
        let result = try await DiskInventoryZScanSessionTreeWorker().refresh(
            item: oldItem, currentRoot: root, source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings())
        #expect(result.refreshedSubtreePath == fixture.root.path)
        #expect(result.rootItem.item(atPath: file.path) == nil)
        #expect(result.rootItem.item(atPath: folder.path) == nil)
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
    }

    @Test func subtreeRefreshUpdatesBytesWithoutDroppingOtherBranches() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let root = try await fixture.scan()
        let file = fixture.root.appendingPathComponent("victim.txt")
        let oldItem = try #require(root.item(atPath: file.path))
        try Data(repeating: 4, count: 37).write(to: file)
        #expect(root.descendantsMatchingAncestorPath(of: oldItem).count == 2)
        let result = try await DiskInventoryZScanSessionTreeWorker().refresh(
            item: oldItem, currentRoot: root, source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings())
        #expect(result.refreshedSubtreePath == file.path)
        #expect(result.rootItem.item(atPath: file.path)?.logicalSizeValue == 37)
        #expect(result.rootItem.logicalSizeValue == root.logicalSizeValue + 29)
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
        #expect(root.item(atPath: file.path)?.logicalSizeValue == 8)
    }

    @Test func trashProtectionResolvesSymlinksAndDotComponents() throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let trash = fixture.base.appendingPathComponent("trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let alias = fixture.base.appendingPathComponent("trash-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: trash)
        let file = trash.appendingPathComponent("protected.txt")
        try Data().write(to: file)
        #expect(DiskItemDeletionPolicy.contains(alias.appendingPathComponent("protected.txt"), in: trash))
        #expect(DiskItemDeletionPolicy.contains(trash.appendingPathComponent("../trash/protected.txt"), in: trash))
        #expect(!DiskItemDeletionPolicy.contains(fixture.base.appendingPathComponent("trash-other/file"), in: trash))
    }

    @Test func localFileUsesTrashRatherThanPermanentDeletion() throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let method = try DiskItemDeletionPolicy.deletionMethod(for: fixture.root.appendingPathComponent("victim.txt"))
        guard case .moveToTrash = method else {
            Issue.record("Local files must use recoverable trash, not permanent deletion.")
            return
        }
    }
}

private actor ScanEvents {
    var stages: [DiskScanStage] = []
    var prepared = false
    func stage(_ value: DiskScanStage) { stages.append(value) }
    func preparing() { prepared = true }
}

@MainActor
struct RealScanWorkerCoverageTests {

    @Test func rescanReplacesPartialSnapshotAndRankingAfterPermissionsRecover() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let locked = fixture.root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let recovered = locked.appendingPathComponent("recovered.bin")
        try Data(repeating: 7, count: 65536).write(to: recovered)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let session = ScanSession(source: fixture.source)
        defer { session.cancel() }
        func finishScan() async throws {
            session.startScan()
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while session.state == .scanning && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(session.state == .complete)
        }
        try await finishScan()
        let oldRoot = try #require(session.rootItem)
        let oldAcquisition = try #require(session.snapshotFreshness.wholeScan)
        #expect(session.hasIncompleteResults)
        #expect(oldRoot.item(atPath: recovered.path) == nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        try await finishScan()
        let root = try #require(session.rootItem)
        #expect(root.id != oldRoot.id)
        #expect(session.skippedItems.isEmpty)
        #expect(!session.hasIncompleteResults)
        #expect(!session.isAffectedBySkippedContent(root))
        #expect(root.item(atPath: recovered.path)?.logicalSizeValue == 65536)
        #expect(oldRoot.item(atPath: recovered.path) == nil, "Re-scan must not mutate the previous snapshot.")
        let acquisition = try #require(session.snapshotFreshness.wholeScan)
        #expect(!acquisition.hasSkippedItems)
        #expect(acquisition.startedAt >= oldAcquisition.finishedAt)
        let ranked = try LargestItemsPipeline.run(root: root, query: LargestItemsQuery())
        #expect(ranked.rows.first?.item.path == recovered.path)
        #expect(try Data(contentsOf: recovered).count == 65536)
    }

    @Test func partialScanPublishesLowerBoundsAndUnknownQueueSize() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let locked = fixture.root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 1024).write(to: locked.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }

        let session = ScanSession(source: fixture.source)
        session.startScan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.state == .scanning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { session.cancel() }
        #expect(session.state == .complete)
        let root = try #require(session.rootItem)
        let unreadable = try #require(root.item(atPath: locked.path))
        let readable = try #require(root.item(atPath: fixture.root.appendingPathComponent("keep.txt").path))
        #expect(session.isAffectedBySkippedContent(root))
        #expect(session.isAffectedBySkippedContent(unreadable))
        #expect(!session.isAffectedBySkippedContent(readable))
        #expect(ScanItemSizePresentation.text(bytes: root.logicalSizeValue, isIncomplete: true).hasPrefix("≥ "))
        #expect(ScanItemSizePresentation.text(bytes: unreadable.logicalSizeValue, isIncomplete: true) == String(localized: "Unknown"))
        let store = CleanupQueueStore()
        #expect(store.enqueue(unreadable, from: session))
        #expect(store.items.first?.isSizeUnknown == true)
        let acquisition = try #require(session.snapshotFreshness.wholeScan)
        #expect(acquisition.hasSkippedItems)
        #expect(acquisition.finishedAt >= acquisition.startedAt)
    }
    private func scan(_ fixture: SafetyFixture, events: ScanEvents) async throws -> ScanSessionScanResult {
        try await DiskInventoryZScanSessionWorker().scan(
            source: fixture.source, settings: fixture.settings, presentation: ScanPresentationSettings(), progress: { _ in },
            stage: { await events.stage($0) },
            willBuildTreemap: { await events.preparing() },
            treemapProgress: { _ in })
    }

    @Test func realWorkerPublishesMeasuredFilesAndPresentation() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let events = ScanEvents()
        let result = try await scan(fixture, events: events)
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("victim.txt").path)?.logicalSizeValue == 8)
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
        #expect(result.skippedItems.isEmpty)
        #expect(!result.builtUsingPhysicalSize)
        #expect(result.presentationMetrics.kindStatistics.reduce(0) { $0 + $1.size } == 24)
        #expect(await events.prepared)
        #expect(await events.stages.contains(.enumeratingRootItems))
        #expect(await events.stages.contains(.finalizingScan))
    }

    @Test func unreadableDirectoryIsReportedWhileReadableSiblingSurvives() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let locked = fixture.root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 1024).write(to: locked.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let result = try await scan(fixture, events: ScanEvents())
        #expect(result.skippedItems.contains { $0.path == locked.path })
        #expect(result.skippedItems.allSatisfy { !$0.reason.isEmpty })
        #expect(result.rootItem.item(atPath: fixture.root.appendingPathComponent("keep.txt").path)?.logicalSizeValue == 16)
        #expect(result.rootItem.item(atPath: locked.appendingPathComponent("hidden.txt").path) == nil)
    }

    @Test func alreadyCancelledScanCannotPublishCompletedResult() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        let events = ScanEvents()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scan(fixture, events: events)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await events.prepared == false)
    }

    @Test func vanishedRootFailsRatherThanReportingAnEmptySuccessfulScan() async throws {
        let fixture = try SafetyFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.root)
        let events = ScanEvents()
        await #expect(throws: (any Error).self) { try await scan(fixture, events: events) }
        #expect(await events.prepared == false)
    }

    @Test func sizeModeChangePreservesSelectionAndUsesCorrectTotals() {
        let dense = DiskItem(url: URL(fileURLWithPath: "/fixture/dense"), allocatedSizeValue: 8192, logicalSizeValue: 10, kindName: "Test")
        let sparse = DiskItem(url: URL(fileURLWithPath: "/fixture/sparse"), allocatedSizeValue: 4096, logicalSizeValue: 10000, kindName: "Test")
        let root = DiskItem(url: URL(fileURLWithPath: "/fixture"), isDirectory: true, children: [dense, sparse])
        let worker = DiskInventoryZScanSessionPresentationWorker()
        let result = worker.sizeModeUpdate(rootItem: root, selectionPath: sparse.path,
                                          usePhysicalSize: false, sharesKindColors: false, colorScheme: .diskHog)
        #expect(result.selectionPath == sparse.path)
        #expect(!result.usePhysicalSize)
        #expect(result.rootItem.children.first?.path == sparse.path)
        #expect(result.rootItem.children.map(\.path).sorted() == [dense.path, sparse.path].sorted())
        #expect(result.presentationMetrics.kindStatistics.reduce(0) { $0 + $1.size } == 10010)
    }
}
