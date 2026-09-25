//
//  disk_hogTests.swift
//  disk_hogTests
//
//

import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import disk_hog

struct ScanPackagingProgressTests {
    @Test func grandTotalIncludesPreviouslyPackedItemsAndWeightsByItemCount() async {
        let (updates, continuation) = AsyncStream<Int>.makeStream()
        let progress = ScanPackagingProgress(subtreeCount: 2, continuation: continuation)
        progress.finishTraversal(itemCount: 100)
        progress.advance(by: 400)
        // Nothing may be published before the second subtree fixes the total.
        progress.finishTraversal(itemCount: 300)
        progress.advance(by: 400)
        progress.advance(by: 800)
        continuation.finish()
        var percentages: [Int] = []
        for await percent in updates { percentages.append(percent) }
        #expect(percentages == [25, 50, 100])
    }

    @Test func packingReportsAllFourPassesIncludingTheFinalPartialBatch() {
        let builder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        for index in 0..<1_100 {
            let child = builder.makeChild(url: URL(fileURLWithPath: "/scan/\(index)"), allocatedSizeValue: 1)
            builder.appendChild(child)
        }
        var batches: [Int] = []
        let chunk = builder.packedChunk(isRoot: true) { batches.append($0) }
        #expect(batches == [4_096, 308])
        #expect(chunk.records.count == 1_101)
        #expect(chunk.records.first?.fileCount == 1_100)
    }
}

@MainActor
struct DiskItemIconCacheTests {
    @Test func reusesLoadedIconsForTheSamePath() {
        var loadedPaths: [String] = []
        let expectedPath: String = "/scan/file.txt"
        let cache: DiskItemIconCache = DiskItemIconCache(loadIcon: { path in
            loadedPaths.append(path)
            return NSImage(size: NSSize(width: 16, height: 16))
        })

        let firstIcon: NSImage = cache.icon(forFile: expectedPath)
        let secondIcon: NSImage = cache.icon(forFile: expectedPath)

        #expect(firstIcon === secondIcon)
        #expect(loadedPaths == [expectedPath])
    }
}

@MainActor
struct KeyboardRoutingTests {
    @Test func fileListReturnAndShiftReturnInvokeOnlyTheirExplicitActions() throws {
        let outlineView: DiskItemPasteboardOutlineView = DiskItemPasteboardOutlineView()
        var activationCount: Int = 0
        var zoomOutCount: Int = 0
        outlineView.activateSelectedItem = { activationCount += 1 }
        outlineView.zoomOut = { zoomOutCount += 1 }

        outlineView.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )))
        outlineView.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 76
        )))

        #expect(activationCount == 1)
        #expect(zoomOutCount == 1)
    }

    @Test func treemapShiftReturnAndEscapeRequestZoomOut() throws {
        let treemap: ZStyleTreemapNSView = ZStyleTreemapNSView()
        var zoomOutCount: Int = 0
        treemap.onZoomOut = { zoomOutCount += 1 }

        treemap.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )))
        treemap.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )))

        #expect(zoomOutCount == 2)
    }

    @Test func treemapSpaceDoesNotBlockSubsequentZoomKeyboardCommands() throws {
        let treemap: ZStyleTreemapNSView = ZStyleTreemapNSView()
        var zoomOutCount: Int = 0
        treemap.onZoomOut = { zoomOutCount += 1 }

        treemap.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )))
        treemap.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: true,
            keyCode: 49
        )))
        treemap.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )))

        #expect(zoomOutCount == 1)
    }
}

@MainActor
struct TreemapNavigationStateTests {
    @Test func zoomingBuildsBreadcrumbsAndReturnsToTheParent() {
        let file: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/file"))
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()

        navigation.configure(baseRoot: root)
        #expect(navigation.canZoom(into: root.children[0]))

        navigation.zoom(into: root.children[0])
        #expect(navigation.zoomRoot?.path == "/scan/folder")
        #expect(navigation.zoomPath.map(\.path) == ["/scan", "/scan/folder"])

        navigation.zoomOut()
        #expect(navigation.zoomRoot?.path == "/scan")
    }

    @Test func directFileNeverZooms() {
        let file: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/file"))
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)

        let fileInTree: DiskItem = root.children[0].children[0]
        #expect(navigation.canZoom(into: fileInTree) == false)
        navigation.zoom(into: fileInTree)

        #expect(navigation.zoomRoot?.path == "/scan")
        #expect(navigation.canZoomOut == false)
        #expect(navigation.consumeSelectionAfterZoom() == nil)
    }

    @Test func fileFallbackZoomsToTheParentButSelectsTheFileItself() {
        let file: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/file"))
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)

        let fileInTree: DiskItem = root.children[0].children[0]
        #expect(navigation.canZoom(into: fileInTree, allowingFileFallback: true))
        navigation.zoom(into: fileInTree, allowingFileFallback: true)

        #expect(navigation.zoomRoot?.path == "/scan/folder")
        #expect(navigation.canZoomOut)
        #expect(navigation.consumeSelectionAfterZoom()?.path == "/scan/folder/file")
    }

    @Test func directFileAtTheCurrentRootDoesNotOfferADeadEndZoom() {
        let file: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/file"))
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [file]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)

        #expect(navigation.canZoom(into: root.children[0], allowingFileFallback: true) == false)
        navigation.zoom(into: root.children[0], allowingFileFallback: true)
        #expect(navigation.zoomRoot?.path == "/scan")
        #expect(navigation.canZoomOut == false)
    }

    @Test func externalSelectionLeavesTheCurrentZoomAtItsSharedAncestor() {
        let nestedFile: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/nested/file"))
        let nestedFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/nested"),
            isDirectory: true,
            children: [nestedFile]
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [nestedFolder]
        )
        let sibling: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/sibling"))
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder, sibling]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)
        navigation.zoom(into: root.children[0])
        navigation.zoom(into: root.children[0].children[0])

        navigation.revealSelection(root.children[1])

        #expect(navigation.zoomRoot?.path == "/scan")
        #expect(navigation.zoomPath.map(\.path) == ["/scan"])
        #expect(navigation.consumeSelectionAfterZoom() == nil)
    }

    @Test func externalSelectionInADeeplyNestedBranchZoomsAllTheWayToItsOwnParent() {
        let deepFile: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/otherFolder/sub/deepFile"))
        let subFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/otherFolder/sub"),
            isDirectory: true,
            children: [deepFile]
        )
        let otherFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/otherFolder"),
            isDirectory: true,
            children: [subFolder]
        )
        let nestedFile: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/nested/file"))
        let nestedFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/nested"),
            isDirectory: true,
            children: [nestedFile]
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [nestedFolder]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder, otherFolder]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)
        navigation.zoom(into: root.children[0])
        navigation.zoom(into: root.children[0].children[0])

        let target: DiskItem = root.children[1].children[0].children[0]
        navigation.revealSelection(target)

        // The nearest ancestor shared with the old zoom path is just "/scan" - landing
        // there would leave deepFile still out of view. It should land on deepFile's own
        // parent ("/scan/otherFolder/sub") instead.
        #expect(navigation.zoomRoot?.path == "/scan/otherFolder/sub")
        #expect(navigation.zoomPath.map(\.path) == ["/scan", "/scan/otherFolder", "/scan/otherFolder/sub"])
        #expect(navigation.consumeSelectionAfterZoom() == nil)
    }

    @Test func zoomOutPublishesItsNewRootOnlyOnceForListSynchronization() {
        let file: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/folder/file"))
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let navigation: TreemapNavigationState = TreemapNavigationState()
        navigation.configure(baseRoot: root)
        navigation.zoom(into: root.children[0])
        _ = navigation.consumeSelectionAfterZoom()

        navigation.zoomOut()

        #expect(navigation.consumeSelectionAfterZoom()?.path == "/scan")
        #expect(navigation.consumeSelectionAfterZoom() == nil)
    }
}

struct ScanSessionFailureTests {
    @Test func givesPermissionRecoveryAdvice() {
        let failure: ScanSessionFailure = ScanSessionFailure(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            operation: .deletion(itemName: "Locked File", method: .moveToTrash)
        )

        #expect(failure.title.contains("Locked File"))
        #expect(failure.message.contains("permission"))
        #expect(failure.recoverySuggestion.contains("permissions"))
    }

    @Test func givesReadOnlyVolumeRecoveryAdvice() {
        let failure: ScanSessionFailure = ScanSessionFailure(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS)),
            operation: .deletion(itemName: "Archive", method: .deletePermanently)
        )

        #expect(failure.message.contains("read-only"))
        #expect(failure.recoverySuggestion.contains("writable volume"))
    }

    @Test func givesMissingItemRecoveryAdvice() {
        let failure: ScanSessionFailure = ScanSessionFailure(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT)),
            operation: .refresh(itemName: "Missing Folder")
        )

        #expect(failure.message.contains("no longer available"))
        #expect(failure.recoverySuggestion.contains("Refresh"))
    }

    @Test func preservesUnknownSystemDetail() {
        let failure: ScanSessionFailure = ScanSessionFailure(
            error: NSError(
                domain: "TestFailure",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The test operation failed."]
            ),
            operation: .scan(itemName: "Test Volume")
        )

        #expect(failure.message == "The test operation failed.")
        #expect(failure.recoverySuggestion.contains("Try again"))
    }

    @Test func createsUserFacingAlertPresentation() {
        let failure: ScanSessionFailure = ScanSessionFailure(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            operation: .deletion(itemName: "Locked File", method: .moveToTrash)
        )

        let presentation: ScanSessionFailureAlertPresentation = ScanSessionFailureAlertPresentation(
            failure: failure
        )

        #expect(presentation.id == failure.id)
        #expect(presentation.title.contains("Locked File"))
        #expect(presentation.message.contains("permission"))
        #expect(presentation.message.contains("permissions"))
        #expect(presentation.dismissButtonTitle == "OK")
    }
}

@MainActor
struct CleanupQueueStoreTests {
    @Test func rejectsRootItemsAndDuplicateEntries() {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in }
        let session: ScanSession = Self.session()
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture"),
            isDirectory: true
        )
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/file.txt"),
            allocatedSizeValue: 42,
            logicalSizeValue: 42,
            isRoot: false
        )

        #expect(store.enqueue(root, from: session) == false)
        #expect(store.enqueue(file, from: session))
        #expect(store.enqueue(file, from: session) == false)
        #expect(store.items.map(\.itemURL) == [file.url.standardizedFileURL])
    }

    @Test func enqueuingAFolderRemovesItsPreviouslyQueuedDescendants() {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in }
        let session: ScanSession = Self.session()
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/folder/child.txt"),
            allocatedSizeValue: 20,
            logicalSizeValue: 20,
            isRoot: false
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/folder"),
            isDirectory: true,
            children: [child],
            isRoot: false
        )

        #expect(store.enqueue(child, from: session))
        #expect(store.enqueue(folder, from: session))

        #expect(store.items.count == 1)
        #expect(store.items.first?.itemURL == folder.url.standardizedFileURL)
    }

    @Test func batchQueueingKeepsOnlyTheHighestSelectedAncestor() {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in }
        let session: ScanSession = Self.session()
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/folder/child.txt"),
            allocatedSizeValue: 20,
            logicalSizeValue: 20,
            isRoot: false
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/folder"),
            isDirectory: true,
            children: [child],
            isRoot: false
        )

        store.enqueue([child, folder], from: session)

        #expect(store.items.count == 1)
        #expect(store.items.first?.itemURL == folder.url.standardizedFileURL)
    }

    @Test func successfulTrashExecutionUsesTheInjectedExecutorAndRemovesTheQueueItem() async throws {
        let invocationCount: LockedCounter = LockedCounter()
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            invocationCount.increment()
        }
        let session: ScanSession = Self.session()
        let file: DiskItem = Self.file(named: "successful.txt")
        #expect(store.enqueue(file, from: session))

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { store.items.isEmpty }

        #expect(invocationCount.value == 1)
    }

    @Test func batchTrashRequestsOneRefreshForEachAffectedSession() async throws {
        let invocationCount: LockedCounter = LockedCounter()
        var refreshCount: Int = 0
        let store: CleanupQueueStore = CleanupQueueStore(
            trashItem: { _, _ in invocationCount.increment() },
            refreshSession: { _ in refreshCount += 1 }
        )
        let session: ScanSession = Self.session()
        #expect(store.enqueue(Self.file(named: "first.txt"), from: session))
        #expect(store.enqueue(Self.file(named: "second.txt"), from: session))

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { store.items.isEmpty && refreshCount == 1 }

        #expect(invocationCount.value == 2)
        #expect(refreshCount == 1)
    }

    @Test func queueEntriesDoNotKeepClosedScanSessionsAlive() {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in }
        weak var queuedSession: ScanSession?

        do {
            let session: ScanSession = Self.session()
            queuedSession = session
            #expect(store.enqueue(Self.file(named: "retained.txt"), from: session))
        }

        #expect(store.items.count == 1)
        #expect(queuedSession == nil)
    }

    @Test func missingTrashTargetRemainsQueuedWithAMissingStatus() async throws {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            throw CocoaError(.fileNoSuchFile)
        }
        let session: ScanSession = Self.session()
        let file: DiskItem = Self.file(named: "missing.txt")
        #expect(store.enqueue(file, from: session))

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { store.items.first?.status == .missing }

        #expect(store.items.count == 1)
        #expect(store.items.first?.status == .missing)
    }

    @Test func permissionFailureRemainsQueuedWithAnInaccessibleStatus() async throws {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        let session: ScanSession = Self.session()
        let file: DiskItem = Self.file(named: "protected.txt")
        #expect(store.enqueue(file, from: session))

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { store.items.first?.status == .inaccessible }

        #expect(store.items.count == 1)
        #expect(store.items.first?.status == .inaccessible)
    }

    @Test func readOnlyVolumeFailureRemainsQueuedWithACannotMoveToTrashStatus() async throws {
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            throw CocoaError(.fileWriteVolumeReadOnly)
        }
        let session: ScanSession = Self.session()
        #expect(store.enqueue(Self.file(named: "read-only.txt"), from: session))

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { store.items.first?.status == .cannotMoveToTrash }

        #expect(store.items.count == 1)
        #expect(store.items.first?.status == .cannotMoveToTrash)
    }

    @Test func removingAnItemBeforeTheTrashTaskRunsPreventsItsExecution() async throws {
        let invocationCount: LockedCounter = LockedCounter()
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            invocationCount.increment()
        }
        let session: ScanSession = Self.session()
        #expect(store.enqueue(Self.file(named: "removed-before-processing.txt"), from: session))
        let id: CleanupQueueItem.ID = try #require(store.items.first?.id)

        store.moveSelectedItemsToFinderTrash()
        store.remove(ids: [id])
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(invocationCount.value == 0)
        #expect(store.items.isEmpty)
    }

    @Test func removingALaterItemWhileBatchTrashIsRunningPreventsItsExecution() async throws {
        let invocationCount: LockedCounter = LockedCounter()
        let store: CleanupQueueStore = CleanupQueueStore { itemURL, _ in
            invocationCount.increment()
            if itemURL.lastPathComponent == "first.txt" {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let session: ScanSession = Self.session()
        #expect(store.enqueue(Self.file(named: "first.txt"), from: session))
        #expect(store.enqueue(Self.file(named: "second.txt"), from: session))
        let secondID: CleanupQueueItem.ID = try #require(store.items.last?.id)

        store.moveSelectedItemsToFinderTrash()
        try await Self.waitUntil { invocationCount.value == 1 }
        store.remove(ids: [secondID])
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(invocationCount.value == 1)
        #expect(store.items.isEmpty)
    }

    @Test func deselectedItemsAreNeverSentToTheTrashExecutor() async throws {
        let invocationCount: LockedCounter = LockedCounter()
        let store: CleanupQueueStore = CleanupQueueStore { _, _ in
            invocationCount.increment()
        }
        let session: ScanSession = Self.session()
        let file: DiskItem = Self.file(named: "deselected.txt")
        #expect(store.enqueue(file, from: session))
        let id: CleanupQueueItem.ID = try #require(store.items.first?.id)
        store.setSelected(false, for: id)

        store.moveSelectedItemsToFinderTrash()
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(invocationCount.value == 0)
        #expect(store.items.first?.status == .ready)
    }

    private static func session() -> ScanSession {
        ScanSession(source: ScanSource(path: "/tmp/cleanup-fixture", displayName: "Cleanup Fixture"))
    }

    private static func file(named name: String) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: "/tmp/cleanup-fixture/\(name)"),
            allocatedSizeValue: 42,
            logicalSizeValue: 42,
            isRoot: false
        )
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let attempts: Int = Int(timeoutNanoseconds / 10_000_000)
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }
}

struct ScanSourceBookmarkTests {
    @Test func refreshesBookmarkDataWhenResolutionIsStale() throws {
        let originalBookmark: Data = Data([1])
        let refreshedBookmark: Data = Data([2])
        let url: URL = URL(fileURLWithPath: "/scan")

        let resolution: ScanSourceBookmarkResolution = try ScanSource.bookmarkResolution(
            for: originalBookmark,
            resolving: { _ in (url, true) },
            creating: { _ in refreshedBookmark }
        )

        #expect(resolution.url == url)
        #expect(resolution.refreshedBookmarkData == refreshedBookmark)
    }

    @Test func leavesCurrentBookmarkDataUnchanged() throws {
        let originalBookmark: Data = Data([1])
        var didCreateBookmark: Bool = false

        let resolution: ScanSourceBookmarkResolution = try ScanSource.bookmarkResolution(
            for: originalBookmark,
            resolving: { _ in (URL(fileURLWithPath: "/scan"), false) },
            creating: { _ in
                didCreateBookmark = true
                return Data([2])
            }
        )

        #expect(resolution.refreshedBookmarkData == nil)
        #expect(didCreateBookmark == false)
    }
}

@MainActor
struct AppCommandRouterTests {
    @Test func selectionListBatchQueueContextActivatesAndDeactivates() {
        let router: AppCommandRouter = AppCommandRouter()
        let session: ScanSession = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"))
        let item: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/file.txt"))

        router.activateSelectionListBatchQueue(session: session, items: [item])

        #expect(router.isSelectionListBatchQueueActive)
        #expect(router.canToggleSelectionListBatchQueue == false)
        #expect(router.selectionListBatchQueueTitle == "Add to Cleanup Queue")

        router.deactivateSelectionListBatchQueue()

        #expect(router.isSelectionListBatchQueueActive == false)
        #expect(router.canToggleSelectionListBatchQueue == false)
    }

    @Test func selectionListContextDoesNotKeepItsScanSessionAlive() {
        let router: AppCommandRouter = AppCommandRouter()
        weak var sessionReference: ScanSession?

        do {
            let session: ScanSession = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"))
            sessionReference = session
            router.activateSelectionListBatchQueue(
                session: session,
                items: [DiskItem(url: URL(fileURLWithPath: "/scan/file.txt"))]
            )
        }

        #expect(sessionReference == nil)
        #expect(router.canToggleSelectionListBatchQueue == false)
    }
}

@MainActor
struct ScanWindowCommandStateSelectionTests {
    @Test func retainsCommandTargetWhenSelectionReplacesAnEqualFlyweight() {
        let commandState: ScanWindowCommandState = ScanWindowCommandState()
        let session: ScanSession = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"))
        let coordinator: ScanWindowSelectionCoordinator = ScanWindowSelectionCoordinator()
        let commandContext: ScanWindowCommandContext = ScanWindowCommandContext(
            session: session,
            selectionCoordinator: coordinator,
            treemapNavigation: TreemapNavigationState()
        )
        var firstSelection: DiskItem? = DiskItem(
            url: URL(fileURLWithPath: "/scan/report.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        )
        weak let weakFirstSelection: DiskItem? = firstSelection

        commandContext.updateSelectedItem(firstSelection)
        commandState.activate(commandContext)

        let replacement: DiskItem = DiskItem(
            snapshot: firstSelection!.snapshot,
            address: firstSelection!.address
        )
        coordinator.setSelectedItem(replacement)
        commandContext.updateSelectedItem(replacement)
        firstSelection = nil

        #expect(weakFirstSelection == nil)
        #expect(commandState.commandSelectedItem?.id == replacement.id)
        #expect(commandState.canOpenSelectedItem)
        #expect(commandState.canRevealSelectedItem)
    }

    @Test func routesMenuEnablementThroughActiveWindowContext() {
        let commandState: ScanWindowCommandState = ScanWindowCommandState()
        let firstSession: ScanSession = ScanSession(source: ScanSource(path: "/first", displayName: "first"))
        let secondSession: ScanSession = ScanSession(source: ScanSource(path: "/second", displayName: "second"))
        let firstContext: ScanWindowCommandContext = ScanWindowCommandContext(
            session: firstSession,
            selectionCoordinator: ScanWindowSelectionCoordinator(),
            treemapNavigation: TreemapNavigationState()
        )
        let secondContext: ScanWindowCommandContext = ScanWindowCommandContext(
            session: secondSession,
            selectionCoordinator: ScanWindowSelectionCoordinator(),
            treemapNavigation: TreemapNavigationState()
        )
        let firstItem: DiskItem = DiskItem(url: URL(fileURLWithPath: "/first/file.txt"))
        let secondItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/second/free"),
            itemType: .freeSpace
        )

        firstContext.updateSelectedItem(firstItem)
        secondContext.updateSelectedItem(secondItem)

        commandState.activate(firstContext)
        #expect(commandState.commandSelectedItem?.path == "/first/file.txt")
        #expect(commandState.canOpenSelectedItem)

        commandState.activate(secondContext)
        #expect(commandState.commandSelectedItem?.itemType == .freeSpace)
        #expect(commandState.canOpenSelectedItem == false)

        firstContext.updateSelectedItem(firstItem)
        #expect(commandState.commandSelectedItem?.itemType == .freeSpace)
        #expect(commandState.canOpenSelectedItem == false)
    }
}

@MainActor
struct DiskItemOutlineIdentityTests {
    @Test func returnsCanonicalItemsAndFindsTheirRows() throws {
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [child]
        )
        let session: ScanSession = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"))
        let coordinator: DiskItemOutlineView.Coordinator = DiskItemOutlineView.Coordinator(
            session: session,
            usePhysicalSize: true,
            selectionCoordinator: ScanWindowSelectionCoordinator(),
            activePane: Binding<ScanWindowPane?>.constant(nil),
            onActivateItem: { _, _ in },
            onZoomOut: {}
        )
        let outlineView: NSOutlineView = NSOutlineView()
        let column: NSTableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = coordinator
        coordinator.outlineView = outlineView
        coordinator.reload(rootItem: root)

        let suppliedRoot: DiskItem = try #require(
            coordinator.outlineView(outlineView, child: 0, ofItem: nil) as? DiskItem
        )
        outlineView.expandItem(suppliedRoot)
        let firstChild: DiskItem = try #require(
            coordinator.outlineView(outlineView, child: 0, ofItem: suppliedRoot) as? DiskItem
        )
        let secondChild: DiskItem = try #require(
            coordinator.outlineView(outlineView, child: 0, ofItem: suppliedRoot) as? DiskItem
        )

        #expect(firstChild === secondChild)
        #expect(outlineView.row(forItem: firstChild) >= 0)
    }

    @Test func syncSelectionFindsEqualFlyweightFromAnotherPane() throws {
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/file.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let coordinator: DiskItemOutlineView.Coordinator = DiskItemOutlineView.Coordinator(
            session: ScanSession(source: ScanSource(path: "/scan", displayName: "scan")),
            usePhysicalSize: true,
            selectionCoordinator: ScanWindowSelectionCoordinator(),
            activePane: Binding<ScanWindowPane?>.constant(nil),
            onActivateItem: { _, _ in },
            onZoomOut: {}
        )
        let outlineView: NSOutlineView = NSOutlineView()
        let column: NSTableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = coordinator
        coordinator.outlineView = outlineView
        coordinator.reload(rootItem: root)
        let suppliedRoot: DiskItem = try #require(outlineView.item(atRow: 0) as? DiskItem)
        let suppliedFolder: DiskItem = try #require(
            coordinator.outlineView(outlineView, child: 0, ofItem: suppliedRoot) as? DiskItem
        )
        let equalButDistinctFile: DiskItem = DiskItem(
            snapshot: file.snapshot,
            address: file.address
        )

        coordinator.syncSelectionIfNeeded(equalButDistinctFile)

        #expect(outlineView.isItemExpanded(suppliedFolder))
        #expect(outlineView.selectedRow >= 0)
        let selectedItem: DiskItem = try #require(outlineView.item(atRow: outlineView.selectedRow) as? DiskItem)
        #expect(selectedItem.path == "/scan/folder/file.txt")
        #expect(selectedItem !== equalButDistinctFile)
    }
}

@MainActor
struct ApplicationStateRestorationTests {
    @Test func applicationDoesNotSaveOrRestoreWindowState() {
        let delegate: DiskHogApplicationDelegate = DiskHogApplicationDelegate()

        #expect(delegate.applicationShouldSaveApplicationState(NSApp) == false)
        #expect(delegate.applicationShouldRestoreApplicationState(NSApp) == false)
    }

    @Test func scanWindowIsMarkedNonRestorableWhenRegistered() {
        let source: ScanSource = ScanSource(path: "/scan", displayName: "scan")
        let controller: ScanWindowController = ScanWindowController(
            source: source,
            session: ScanSession(
                source: source,
                scanWorker: ImmediateScanWorker(result: .success(
                    ScanSessionWorkerIntegrationTests.scanResult(
                        rootItem: ScanSessionWorkerIntegrationTests.rootItem(fileSize: 1)
                    )
                ))
            )
        )
        guard let window: NSWindow = controller.window else {
            Issue.record("The scan window controller did not create a window.")
            return
        }

        #expect(!window.isRestorable)
        controller.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: window)
        )
    }
}

@MainActor
struct ScanWindowControllerTests {
    @Test func registersAndUnregistersItsOwnedWindow() {
        let source: ScanSource = ScanSource(path: "/scan", displayName: "Scan")
        let controller: ScanWindowController = ScanWindowController(
            source: source,
            session: ScanSession(
                source: source,
                scanWorker: ImmediateScanWorker(result: .success(
                    ScanSessionWorkerIntegrationTests.scanResult(
                        rootItem: ScanSessionWorkerIntegrationTests.rootItem(fileSize: 1)
                    )
                ))
            )
        )
        guard let window: NSWindow = controller.window else {
            Issue.record("The scan window controller did not create a window.")
            return
        }

        #expect(ScanWindowRegistry.shared.window(for: source) === window)
        #expect(window.title == "Scan — /scan")

        controller.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: window)
        )

        #expect(ScanWindowRegistry.shared.window(for: source) == nil)
    }
}

struct ScanSessionRescanCoordinatorTests {
    @Test func coalescesRepeatedRescanRequestsIntoOneReplacement() {
        var coordinator: ScanSessionRescanCoordinator = ScanSessionRescanCoordinator()
        let operation: ScanSessionWorkOperation = coordinator.beginScan()

        #expect(coordinator.requestRescan() == operation)
        #expect(coordinator.requestRescan() == operation)
        let didFinish: Bool = coordinator.finish(operation)
        let didConsumePendingRescan: Bool = coordinator.consumePendingRescan()
        let didConsumeSecondPendingRescan: Bool = coordinator.consumePendingRescan()

        #expect(didFinish)
        #expect(didConsumePendingRescan)
        #expect(didConsumeSecondPendingRescan == false)
    }

    @Test func acceptsOnlyTheCurrentOperationCompletion() {
        var coordinator: ScanSessionRescanCoordinator = ScanSessionRescanCoordinator()
        let firstOperation: ScanSessionWorkOperation = coordinator.beginTreeUpdate()

        let didFinishFirstOperation: Bool = coordinator.finish(firstOperation)
        let replacementOperation: ScanSessionWorkOperation = coordinator.beginScan()

        #expect(didFinishFirstOperation)
        let didFinishStaleOperation: Bool = coordinator.finish(firstOperation)
        #expect(didFinishStaleOperation == false)
        #expect(coordinator.activeOperation == replacementOperation)
    }

    @Test func preservesPendingRescanThroughAnyTerminalOperation() {
        var scanCoordinator: ScanSessionRescanCoordinator = ScanSessionRescanCoordinator()
        let scanOperation: ScanSessionWorkOperation = scanCoordinator.beginScan()
        _ = scanCoordinator.requestRescan()
        let didFinishScan: Bool = scanCoordinator.finish(scanOperation)
        let didConsumeScanRescan: Bool = scanCoordinator.consumePendingRescan()
        #expect(didFinishScan)
        #expect(didConsumeScanRescan)

        var treeCoordinator: ScanSessionRescanCoordinator = ScanSessionRescanCoordinator()
        let treeOperation: ScanSessionWorkOperation = treeCoordinator.beginTreeUpdate()
        _ = treeCoordinator.requestRescan()
        let didFinishTreeUpdate: Bool = treeCoordinator.finish(treeOperation)
        let didConsumeTreeRescan: Bool = treeCoordinator.consumePendingRescan()
        #expect(didFinishTreeUpdate)
        #expect(didConsumeTreeRescan)
    }
}

@MainActor
struct ScanSessionTaskCoordinatorTests {
    @Test func replacementMakesOnlyTheNewestOperationCurrent() {
        let coordinator: ScanSessionTaskCoordinator = ScanSessionTaskCoordinator()
        let firstID: UUID = coordinator.start(.scan) { _ in Task {} }
        let secondID: UUID = coordinator.start(.scan) { _ in Task {} }

        #expect(coordinator.isCurrent(.scan, operationID: firstID) == false)
        #expect(coordinator.isCurrent(.scan, operationID: secondID))
        #expect(coordinator.finish(.scan, operationID: firstID) == false)
        #expect(coordinator.finish(.scan, operationID: secondID))
    }
}

@MainActor
struct ScanSessionWorkerIntegrationTests {
    @Test func bookmarkedVolumeRetainsSpaceAccounting() async throws {
        let root = Self.rootItem(fileSize: 12)
        let source = ScanSource(path: "/scan", displayName: "Volume", bookmarkData: Data([1]),
                                isVolumeRoot: true, totalCapacity: 100, availableCapacity: 50,
                                isInternalVolume: true)
        let session = ScanSession(source: source,
            scanWorker: ImmediateScanWorker(result: .success(ScanSessionScanResult(
                source: source, rootItem: root, presentationMetrics: Self.metrics(rootItem: root),
                builtUsingPhysicalSize: true, skippedItems: []))))
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.freeSpaceItem?.allocatedSizeValue == 50)
        #expect(session.otherSpaceItem?.allocatedSizeValue == 38)
    }

    @Test func cancelledWholeRefreshPreservesHistoricalFreshness() async throws {
        let root = Self.rootItem(fileSize: 12)
        let worker = FreshnessCancellationWorker(result: Self.scanResult(rootItem: root))
        let session = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"), scanWorker: worker)
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        session.markTreemapRendered(for: session.rootItem)
        let original = session.snapshotFreshness
        session.refreshSnapshot()
        session.refreshSnapshot() // A second click cannot queue another operation.
        session.cancel()
        try await Self.waitUntil(observing: session) { session.state == .cancelled }
        #expect(session.snapshotFreshness == original)
        #expect(session.rootItem == nil)
        #expect(session.canRefreshSnapshot)
    }

    @Test func freshnessPrecedesRenderingAndRefreshIsWindowLocal() async throws {
        let root = Self.rootItem(fileSize: 12)
        let session = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"),
                                  scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: root))))
        let other = ScanSession(source: ScanSource(path: "/other", displayName: "other"))
        session.refreshSnapshot()
        #expect(!session.canRefreshSnapshot)
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let freshness = session.snapshotFreshness
        #expect(freshness.wholeScan != nil)
        #expect(session.completedAt == nil)
        #expect(!session.canRefreshSnapshot)
        session.markTreemapRendered(for: session.rootItem)
        #expect(session.snapshotFreshness == freshness)
        #expect(session.canRefreshSnapshot)
        #expect(other.snapshotFreshness.wholeScan == nil)
    }

    @Test func partialRefreshDoesNotAdvanceWholeScanFreshness() async throws {
        let root = Self.rootItem(fileSize: 12)
        let updated = Self.rootItem(fileSize: 24)
        let session = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: root))),
            treeWorker: ImmediateTreeWorker(refreshResult: .success(Self.treeResult(
                rootItem: updated, selectionPath: "/scan/file.txt"))))
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let original = session.snapshotFreshness.wholeScan
        session.refresh(try #require(session.rootItem?.item(atPath: "/scan/file.txt")))
        try await Self.waitUntil(observing: session) { !session.isUpdatingTree }
        #expect(session.snapshotFreshness.wholeScan == original)
        #expect(session.snapshotFreshness.latestPartialRefresh?.path == "/scan/file.txt")
    }

    @Test func failedRefreshDoesNotAdvanceFreshness() async throws {
        let root = Self.rootItem(fileSize: 12)
        let session = ScanSession(source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: root))),
            treeWorker: ImmediateTreeWorker(refreshResult: .failure(.failed("refresh failed"))))
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let original = session.snapshotFreshness
        session.refresh(try #require(session.rootItem))
        try await Self.waitUntil(observing: session) { !session.isUpdatingTree }
        #expect(session.failure != nil)
        #expect(session.snapshotFreshness == original)
    }

    @Test func completesScanFromInjectedWorker() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem)))
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.rootItem?.path == "/scan")
        #expect(session.scannedFileCount == 1)
        #expect(session.scannedFolderCount == 1)
        #expect(session.scannedByteCount == 12)
        #expect(session.currentPath == "/scan")
        #expect(session.presentationMetrics != nil)
    }

    @Test func surfacesSkippedItemsFromInjectedWorker() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let skippedItems: [ScanSkippedItem] = [
            ScanSkippedItem(path: "/scan/locked", reason: "Permission denied")
        ]
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(
                result: .success(Self.scanResult(rootItem: rootItem, skippedItems: skippedItems))
            )
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.hasIncompleteResults)
        #expect(session.skippedItems == skippedItems)
    }

    @Test func scanRemainsInTreemapPreparationUntilFirstRenderedImageArrives() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem)))
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.rootItem === rootItem)
        #expect(session.isBuildingTreemap)
        #expect(session.treemapPreparationProgress == nil)
        #expect(session.completedAt == nil)

        session.markTreemapRendered(for: Self.rootItem(fileSize: 12))

        #expect(session.isBuildingTreemap)
        #expect(session.completedAt == nil)

        session.markTreemapRendered(for: rootItem)

        #expect(session.isBuildingTreemap == false)
        #expect(session.treemapPreparationProgress == nil)
        #expect(session.completedAt != nil)
    }

    @Test func elapsedTimeKeepsAdvancingUntilTreemapRenderCompletes() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem)))
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .complete }
        let startedAt: Date = try #require(session.startedAt)
        #expect(session.completedAt == nil)
        #expect(session.elapsedTime(referenceDate: startedAt.addingTimeInterval(10)) >= 10)

        session.markTreemapRendered(for: rootItem)
        let completedAt: Date = try #require(session.completedAt)

        #expect(session.elapsedTime(referenceDate: completedAt.addingTimeInterval(10)) < 10)
    }

    @Test func reportsScanFailureFromInjectedWorker() async throws {
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .failure(.failed("scan failed")))
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .failed }
        #expect(session.failure?.message == "scan failed")
        #expect(session.failure?.title.contains("scan") == true)
    }

    @Test func scanFailureReachesUserFacingAlertBindingAndDismisses() async throws {
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .failure(.failed("scan failed")))
        )

        session.startScan()

        try await Self.waitUntil(observing: session) { session.state == .failed }
        let alertBinding: Binding<ScanSessionFailureAlertPresentation?> =
            ScanSessionFailureAlertBinding.binding(for: session)
        let alertPresentation: ScanSessionFailureAlertPresentation = try #require(alertBinding.wrappedValue)
        #expect(alertPresentation.title.contains("scan"))
        #expect(alertPresentation.message.contains("scan failed"))
        #expect(alertPresentation.dismissButtonTitle == "OK")

        alertBinding.wrappedValue = nil

        #expect(session.failure == nil)
    }

    @Test func refreshesTreeFromInjectedWorker() async throws {
        let originalRoot: DiskItem = Self.rootItem(fileSize: 12)
        let refreshedRoot: DiskItem = Self.rootItem(fileSize: 24)
        let treeWorker: ImmediateTreeWorker = ImmediateTreeWorker(
            refreshResult: .success(Self.treeResult(rootItem: refreshedRoot, selectionPath: "/scan/file.txt"))
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: originalRoot))),
            treeWorker: treeWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let item: DiskItem = try #require(session.rootItem?.item(atPath: "/scan/file.txt"))

        session.refresh(item)

        try await Self.waitUntil(observing: session) { session.isUpdatingTree == false && session.scannedByteCount == 24 }
        #expect(session.rootItem?.item(atPath: "/scan/file.txt")?.allocatedSizeValue == 24)
        #expect(session.preferredSelection?.path == "/scan/file.txt")
        #expect(session.failure == nil)
    }

    @Test func refreshClearsStaleSkippedItemsUnderRefreshedSubtreeOnly() async throws {
        let originalRoot: DiskItem = Self.rootItem(fileSize: 12)
        let refreshedRoot: DiskItem = Self.rootItem(fileSize: 24)
        let initialSkippedItems: [ScanSkippedItem] = [
            ScanSkippedItem(path: "/scan/sub/locked.dat", reason: "Permission denied"),
            ScanSkippedItem(path: "/scan/other/locked.dat", reason: "Permission denied")
        ]
        let treeWorker: ImmediateTreeWorker = ImmediateTreeWorker(
            refreshResult: .success(Self.treeResult(
                rootItem: refreshedRoot,
                selectionPath: "/scan/file.txt",
                skippedItems: [],
                refreshedSubtreePath: "/scan/sub"
            ))
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(
                result: .success(Self.scanResult(rootItem: originalRoot, skippedItems: initialSkippedItems))
            ),
            treeWorker: treeWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.skippedItems.count == 2)
        let item: DiskItem = try #require(session.rootItem?.item(atPath: "/scan/file.txt"))

        session.refresh(item)

        try await Self.waitUntil(observing: session) { session.isUpdatingTree == false && session.scannedByteCount == 24 }
        #expect(session.skippedItems.map(\.path) == ["/scan/other/locked.dat"])
    }

    @Test func reportsTreeFailureWithoutDroppingCompletedScan() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let treeWorker: ImmediateTreeWorker = ImmediateTreeWorker(
            refreshResult: .failure(.failed("refresh failed"))
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem))),
            treeWorker: treeWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let item: DiskItem = try #require(session.rootItem?.item(atPath: "/scan/file.txt"))

        session.refresh(item)

        try await Self.waitUntil(observing: session) { session.isUpdatingTree == false && session.failure != nil }
        #expect(session.state == .complete)
        #expect(session.rootItem?.path == "/scan")
        #expect(session.failure?.message == "refresh failed")
        #expect(session.failure?.title.contains("file.txt") == true)
    }

    @Test func deletesTreeItemFromInjectedWorker() async throws {
        let originalRoot: DiskItem = Self.rootItem(fileSize: 12)
        let deletedRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 0,
            logicalSizeValue: 0,
            isDirectory: true,
            children: []
        )
        let treeWorker: ImmediateTreeWorker = ImmediateTreeWorker(
            refreshResult: .failure(.failed("unused refresh")),
            deleteResult: .success(Self.treeResult(rootItem: deletedRoot, selectionPath: "/scan"))
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: originalRoot))),
            treeWorker: treeWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let item: DiskItem = try #require(session.rootItem?.item(atPath: "/scan/file.txt"))

        session.delete(item, using: .moveToTrash)

        try await Self.waitUntil(observing: session) { session.isUpdatingTree == false && session.scannedFileCount == 0 }
        #expect(session.rootItem?.item(atPath: "/scan/file.txt") == nil)
        #expect(session.preferredSelection?.path == "/scan")
        #expect(session.failure == nil)
    }

    @Test func reportsDeleteFailureWithoutDroppingCompletedScan() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let treeWorker: ImmediateTreeWorker = ImmediateTreeWorker(
            refreshResult: .failure(.failed("unused refresh")),
            deleteResult: .failure(.failed("delete failed"))
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem))),
            treeWorker: treeWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let item: DiskItem = try #require(session.rootItem?.item(atPath: "/scan/file.txt"))

        session.delete(item, using: .moveToTrash)

        try await Self.waitUntil(observing: session) { session.isUpdatingTree == false && session.failure != nil }
        #expect(session.state == .complete)
        #expect(session.rootItem?.item(atPath: "/scan/file.txt") != nil)
        #expect(session.failure?.message == "delete failed")
        #expect(session.failure?.title.contains("file.txt") == true)
    }

    @Test func pendingRescanRestartsAfterCancelledScanReportsFailure() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let scanWorker: PendingRescanScanWorker = PendingRescanScanWorker(
            firstErrorAfterCancellation: .failed("interrupted scan failed"),
            restartResult: Self.scanResult(rootItem: rootItem)
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: scanWorker
        )

        session.startScan()
        session.rescanForPackageContentsPreference(!session.scanSettings.lookInsidePackages)

        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(await scanWorker.callCount() == 2)
        #expect(session.rootItem?.path == "/scan")
        #expect(session.failure?.message == "interrupted scan failed")
    }

    @Test func rebuildsPresentationMetricsFromInjectedWorker() async throws {
        let rootItem: DiskItem = Self.rootItem(fileSize: 12)
        let presentationWorker: ImmediatePresentationWorker = ImmediatePresentationWorker(
            sizeModeRootItem: rootItem
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan"),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: rootItem))),
            presentationWorker: presentationWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }
        let originalMetricsID: ObjectIdentifier? = session.presentationMetrics.map(ObjectIdentifier.init)

        session.rebuildPresentationMetrics(sharesKindColors: false, colorScheme: .diskHog)

        try await Self.waitUntil(observing: session) {
            session.presentationMetrics.map(ObjectIdentifier.init) != originalMetricsID
        }
        #expect(session.presentationMetrics != nil)
        #expect(session.state == .complete)
    }

    @Test func updatesSizeModeFromInjectedPresentationWorker() async throws {
        let originalRoot: DiskItem = Self.rootItem(fileSize: 12)
        let logicalRoot: DiskItem = Self.rootItem(allocatedSize: 12, logicalSize: 5)
        let presentationWorker: ImmediatePresentationWorker = ImmediatePresentationWorker(
            sizeModeRootItem: logicalRoot
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(
                path: "/scan",
                displayName: "scan",
                scanSettings: DiskScanSettings(
                    usePhysicalSize: true,
                    lookInsidePackages: true
                )
            ),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: originalRoot))),
            presentationWorker: presentationWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }

        session.updateSizeMode(false)

        try await Self.waitUntil(observing: session) { session.scannedByteCount == 5 }
        #expect(session.rootItem?.sizeValue(usePhysicalSize: false) == 5)
        #expect(session.preferredSelection?.path == "/scan")
        #expect(session.state == .complete)
    }

    @Test func ignoresStaleSizeModeRebuildResult() async throws {
        let physicalRoot: DiskItem = Self.rootItem(allocatedSize: 12, logicalSize: 5)
        let logicalRoot: DiskItem = Self.rootItem(allocatedSize: 12, logicalSize: 5)
        let updateRecorder: SizeModeUpdateRecorder = SizeModeUpdateRecorder()
        let presentationWorker: DelayedSizeModePresentationWorker = DelayedSizeModePresentationWorker(
            physicalRootItem: physicalRoot,
            logicalRootItem: logicalRoot,
            updateRecorder: updateRecorder
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(
                path: "/scan",
                displayName: "scan",
                scanSettings: DiskScanSettings(
                    usePhysicalSize: true,
                    lookInsidePackages: true
                )
            ),
            scanWorker: ImmediateScanWorker(result: .success(Self.scanResult(rootItem: physicalRoot))),
            presentationWorker: presentationWorker
        )
        session.startScan()
        try await Self.waitUntil(observing: session) { session.state == .complete }

        session.updateSizeMode(false)
        session.updateSizeMode(true)

        try await Self.waitUntil(observing: session) { session.scannedByteCount == 12 }
        try await updateRecorder.waitUntilLogicalUpdateCount(isAtLeast: 1)
        #expect(session.scanSettings.usePhysicalSize)
        #expect(session.scannedByteCount == 12)
        #expect(session.rootItem?.sizeValue(usePhysicalSize: true) == 12)
    }

    @Test func staleSizeModeRebuildCannotRestoreOldTreeDuringPendingRescan() async throws {
        let oldRoot: DiskItem = Self.rootItem(allocatedSize: 12, logicalSize: 5)
        let staleLogicalRoot: DiskItem = Self.rootItem(allocatedSize: 12, logicalSize: 99)
        let newRoot: DiskItem = Self.rootItem(allocatedSize: 30, logicalSize: 30)
        let scanWorker: PendingRescanStaleSizeModeScanWorker = PendingRescanStaleSizeModeScanWorker(
            firstRootItem: oldRoot,
            secondRootItem: newRoot
        )
        let presentationWorker: DelayedSizeModePresentationWorker = DelayedSizeModePresentationWorker(
            physicalRootItem: oldRoot,
            logicalRootItem: staleLogicalRoot
        )
        let session: ScanSession = ScanSession(
            source: ScanSource(
                path: "/scan",
                displayName: "scan",
                scanSettings: DiskScanSettings(
                    usePhysicalSize: false,
                    lookInsidePackages: true
                )
            ),
            scanWorker: scanWorker,
            presentationWorker: presentationWorker
        )

        session.startScan()
        try await scanWorker.waitUntilCallCount(isAtLeast: 1)
        session.rescanForPackageContentsPreference(false)

        try await scanWorker.waitUntilCallCount(isAtLeast: 2)

        #expect(await scanWorker.callCount() == 2)
        #expect(session.state == .scanning)
        #expect(session.rootItem == nil)
        #expect(session.scannedByteCount == 0)

        try await Self.waitUntil(observing: session) { session.state == .complete }
        #expect(session.rootItem?.allocatedSizeValue == 30)
        #expect(session.scannedByteCount == 30)
    }

    @Test func scanWorkerCallCountWaitTimesOutCleanly() async throws {
        let worker: PendingRescanStaleSizeModeScanWorker = PendingRescanStaleSizeModeScanWorker(
            firstRootItem: Self.rootItem(fileSize: 12),
            secondRootItem: Self.rootItem(fileSize: 30)
        )

        do {
            try await worker.waitUntilCallCount(
                isAtLeast: 1,
                timeoutNanoseconds: 1_000_000
            )
            Issue.record("Expected call-count wait to time out.")
        } catch is ScanSessionWorkerWaitTimeout {
            return
        }
    }

    static func rootItem(fileSize: UInt64) -> DiskItem {
        rootItem(allocatedSize: fileSize, logicalSize: fileSize)
    }

    private static func rootItem(allocatedSize: UInt64, logicalSize: UInt64) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: allocatedSize,
            logicalSizeValue: logicalSize,
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/file.txt"),
                    allocatedSizeValue: allocatedSize,
                    logicalSizeValue: logicalSize
                )
            ]
        )
    }

    static func scanResult(
        rootItem: DiskItem,
        skippedItems: [ScanSkippedItem] = []
    ) -> ScanSessionScanResult {
        ScanSessionScanResult(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: rootItem,
            presentationMetrics: metrics(rootItem: rootItem),
            builtUsingPhysicalSize: true,
            skippedItems: skippedItems
        )
    }

    private static func treeResult(
        rootItem: DiskItem,
        selectionPath: String,
        skippedItems: [ScanSkippedItem] = [],
        refreshedSubtreePath: String? = nil
    ) -> ScanSessionTreeUpdateResult {
        ScanSessionTreeUpdateResult(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: rootItem,
            presentationMetrics: metrics(rootItem: rootItem),
            selectionPath: selectionPath,
            builtUsingPhysicalSize: true,
            skippedItems: skippedItems,
            refreshedSubtreePath: refreshedSubtreePath ?? selectionPath
        )
    }

    private static func metrics(rootItem: DiskItem) -> TreemapPresentationMetrics {
        TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: true,
            sharesKindColors: ScanPreferenceDefaults.sharesKindColors
        )
    }

    private struct ScanSessionWaitTimeout: Error {}

    private final class ScanSessionWaiter {
        private var didResume: Bool = false
        private let continuation: CheckedContinuation<Void, Error>

        var cancellable: AnyCancellable?
        var timeoutTask: Task<Void, Never>?

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func succeed() {
            finish(with: .success(()))
        }

        func fail(_ error: Error) {
            finish(with: .failure(error))
        }

        private func finish(with result: Result<Void, Error>) {
            guard !didResume else { return }
            didResume = true
            cancellable?.cancel()
            timeoutTask?.cancel()
            continuation.resume(with: result)
        }
    }

    private static func waitUntil(
        observing session: ScanSession,
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        guard !condition() else { return }

        do {
            try await withCheckedThrowingContinuation { continuation in
                let waiter: ScanSessionWaiter = ScanSessionWaiter(continuation: continuation)
                waiter.cancellable = session.objectWillChange.sink {
                    Task { @MainActor in
                        await Task.yield()
                        if condition() {
                            waiter.succeed()
                        }
                    }
                }
                waiter.timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    await MainActor.run {
                        waiter.fail(ScanSessionWaitTimeout())
                    }
                }
            }
        } catch let error as ScanSessionWaitTimeout {
            Issue.record("Timed out waiting for ScanSession state change after \(timeoutNanoseconds / 1_000_000_000) seconds.")
            throw error
        }
    }
}

@MainActor
struct ScanSessionPackageContentsSynchronizationTests {
    @Test func reportsWhetherExistingResultsMatchCurrentPreference() {
        let source: ScanSource = ScanSource(
            path: "/scan",
            displayName: "scan",
            scanSettings: DiskScanSettings(
                usePhysicalSize: true,
                lookInsidePackages: false
            )
        )
        let session: ScanSession = ScanSession(source: source)

        session.updatePackageContentsSynchronization(with: true)
        #expect(session.isPackageContentsSettingOutOfSync)

        session.updatePackageContentsSynchronization(with: false)
        #expect(session.isPackageContentsSettingOutOfSync == false)
    }
}

private enum TestScanSessionError: LocalizedError, Sendable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private struct ImmediateScanWorker: ScanSessionScanning {
    let result: Result<ScanSessionScanResult, TestScanSessionError>

    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        await progress(DiskScanProgress(
            scannedFileCount: 1,
            scannedFolderCount: 1,
            scannedByteCount: 12,
            currentPath: source.path
        ))
        await willBuildTreemap()
        await treemapProgress(1)
        return try result.get()
    }
}

private actor FreshnessCancellationWorker: ScanSessionScanning {
    let result: ScanSessionScanResult
    private var calls = 0
    init(result: ScanSessionScanResult) { self.result = result }

    func scan(source: ScanSource, settings: DiskScanSettings,
              progress: @escaping DiskInventoryZScanner.ProgressHandler,
              stage: @escaping @Sendable (DiskScanStage) async -> Void,
              willBuildTreemap: @escaping @Sendable () async -> Void,
              treemapProgress: @escaping @Sendable (Double) async -> Void) async throws -> ScanSessionScanResult {
        calls += 1
        if calls > 1 { try await Task.sleep(for: .seconds(60)) }
        try Task.checkCancellation()
        return result
    }
}

private struct ImmediateTreeWorker: ScanSessionTreeUpdating {
    let refreshResult: Result<ScanSessionTreeUpdateResult, TestScanSessionError>
    let deleteResult: Result<ScanSessionTreeUpdateResult, TestScanSessionError>

    init(
        refreshResult: Result<ScanSessionTreeUpdateResult, TestScanSessionError>,
        deleteResult: Result<ScanSessionTreeUpdateResult, TestScanSessionError>? = nil
    ) {
        self.refreshResult = refreshResult
        self.deleteResult = deleteResult ?? refreshResult
    }

    func refresh(
        item: DiskItem,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult {
        try refreshResult.get()
    }

    func delete(
        item: DiskItem,
        deletionMethod: DiskItemDeletionMethod,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult {
        try deleteResult.get()
    }
}

private struct ImmediatePresentationWorker: ScanSessionPresenting {
    let sizeModeRootItem: DiskItem

    func presentationMetrics(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> TreemapPresentationMetrics {
        TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: usePhysicalSize,
            sharesKindColors: sharesKindColors,
            colorScheme: colorScheme
        )
    }

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> ScanSessionSizeModeUpdateResult {
        ScanSessionSizeModeUpdateResult(
            rootItem: sizeModeRootItem,
            presentationMetrics: presentationMetrics(
                rootItem: sizeModeRootItem,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: sharesKindColors,
                colorScheme: colorScheme
            ),
            selectionPath: selectionPath,
            usePhysicalSize: usePhysicalSize
        )
    }
}

private actor PendingRescanScanWorkerState {
    private var count: Int = 0

    func nextCallNumber() -> Int {
        count += 1
        return count
    }

    func callCount() -> Int {
        count
    }
}

private final class PendingRescanScanWorker: ScanSessionScanning, @unchecked Sendable {
    private let state: PendingRescanScanWorkerState = PendingRescanScanWorkerState()
    private let firstErrorAfterCancellation: TestScanSessionError
    private let restartResult: ScanSessionScanResult

    init(
        firstErrorAfterCancellation: TestScanSessionError,
        restartResult: ScanSessionScanResult
    ) {
        self.firstErrorAfterCancellation = firstErrorAfterCancellation
        self.restartResult = restartResult
    }

    func callCount() async -> Int {
        await state.callCount()
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        let callNumber: Int = await state.nextCallNumber()
        guard callNumber == 1 else {
            await progress(DiskScanProgress(
                scannedFileCount: 1,
                scannedFolderCount: 1,
                scannedByteCount: 12,
                currentPath: source.path
            ))
            await willBuildTreemap()
            await treemapProgress(1)
            return restartResult
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        throw firstErrorAfterCancellation
    }
}

private struct ScanSessionWorkerWaitTimeout: Error {}

private final class SizeModeUpdateRecorder: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock: NSLock = NSLock()
    private var logicalUpdateCount: Int = 0
    private var waiters: [Waiter] = []

    func record(usePhysicalSize: Bool) {
        guard !usePhysicalSize else {
            return
        }

        let satisfiedWaiters: [Waiter]
        lock.lock()
        logicalUpdateCount += 1
        satisfiedWaiters = waiters.filter { logicalUpdateCount >= $0.minimumCount }
        waiters.removeAll { logicalUpdateCount >= $0.minimumCount }
        lock.unlock()

        for waiter in satisfiedWaiters {
            waiter.continuation.resume()
        }
    }

    func waitUntilLogicalUpdateCount(
        isAtLeast minimumCount: Int,
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws {
        guard hasLogicalUpdateCount(atLeast: minimumCount) == false else {
            return
        }

        let waiterID: UUID = UUID()
        var timeoutTask: Task<Void, Never>?
        try await withCheckedThrowingContinuation { continuation in
            guard addWaiterIfNeeded(
                id: waiterID,
                minimumCount: minimumCount,
                continuation: continuation
            ) else {
                continuation.resume()
                return
            }

            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self.failWaiter(id: waiterID, error: ScanSessionWorkerWaitTimeout())
            }
        }
        timeoutTask?.cancel()
    }

    private func hasLogicalUpdateCount(atLeast minimumCount: Int) -> Bool {
        lock.lock()
        let hasMinimumCount: Bool = logicalUpdateCount >= minimumCount
        lock.unlock()
        return hasMinimumCount
    }

    private func addWaiterIfNeeded(
        id: UUID,
        minimumCount: Int,
        continuation: CheckedContinuation<Void, Error>
    ) -> Bool {
        lock.lock()
        guard logicalUpdateCount < minimumCount else {
            lock.unlock()
            return false
        }
        waiters.append(Waiter(
            id: id,
            minimumCount: minimumCount,
            continuation: continuation
        ))
        lock.unlock()
        return true
    }

    private func failWaiter(id: UUID, error: Error) {
        let waiter: Waiter?
        lock.lock()
        if let index: Array<Waiter>.Index = waiters.firstIndex(where: { $0.id == id }) {
            waiter = waiters.remove(at: index)
        } else {
            waiter = nil
        }
        lock.unlock()

        waiter?.continuation.resume(throwing: error)
    }
}

private actor PendingRescanStaleSizeModeScanWorkerState {
    private struct CallCountWaiter {
        let id: UUID
        let minimumCallCount: Int
        let continuation: CheckedContinuation<Void, Error>
    }

    private var count: Int = 0
    private var waiters: [CallCountWaiter] = []

    func nextCallNumber() -> Int {
        count += 1
        resumeSatisfiedWaiters()
        return count
    }

    func callCount() -> Int {
        count
    }

    func waitUntilCallCount(
        isAtLeast minimumCallCount: Int,
        timeoutNanoseconds: UInt64
    ) async throws {
        guard count < minimumCallCount else {
            return
        }

        let waiterID: UUID = UUID()
        var timeoutTask: Task<Void, Never>?
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(CallCountWaiter(
                id: waiterID,
                minimumCallCount: minimumCallCount,
                continuation: continuation
            ))
            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self.failWaiter(id: waiterID, error: ScanSessionWorkerWaitTimeout())
            }
        }
        timeoutTask?.cancel()
    }

    private func resumeSatisfiedWaiters() {
        var remainingWaiters: [CallCountWaiter] = []
        for waiter in waiters {
            if count >= waiter.minimumCallCount {
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        waiters = remainingWaiters
    }

    private func failWaiter(id: UUID, error: Error) {
        guard let index: Array<CallCountWaiter>.Index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter: CallCountWaiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: error)
    }
}

private final class PendingRescanStaleSizeModeScanWorker: ScanSessionScanning, @unchecked Sendable {
    private let state: PendingRescanStaleSizeModeScanWorkerState = PendingRescanStaleSizeModeScanWorkerState()
    private let firstRootItem: DiskItem
    private let secondRootItem: DiskItem

    init(firstRootItem: DiskItem, secondRootItem: DiskItem) {
        self.firstRootItem = firstRootItem
        self.secondRootItem = secondRootItem
    }

    func callCount() async -> Int {
        await state.callCount()
    }

    func waitUntilCallCount(
        isAtLeast minimumCallCount: Int,
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws {
        try await state.waitUntilCallCount(
            isAtLeast: minimumCallCount,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        let callNumber: Int = await state.nextCallNumber()
        let rootItem: DiskItem
        let builtUsingPhysicalSize: Bool

        if callNumber == 1 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            rootItem = firstRootItem
            builtUsingPhysicalSize = true
        } else {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            rootItem = secondRootItem
            builtUsingPhysicalSize = settings.usePhysicalSize
        }

        await willBuildTreemap()
        await treemapProgress(1)
        return ScanSessionScanResult(
            source: source,
            rootItem: rootItem,
            presentationMetrics: TreemapPresentationMetrics(
                rootItem: rootItem,
                usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: ScanPreferenceDefaults.sharesKindColors
            ),
            builtUsingPhysicalSize: builtUsingPhysicalSize,
            skippedItems: []
        )
    }
}

private struct DelayedSizeModePresentationWorker: ScanSessionPresenting {
    let physicalRootItem: DiskItem
    let logicalRootItem: DiskItem
    var updateRecorder: SizeModeUpdateRecorder?

    func presentationMetrics(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> TreemapPresentationMetrics {
        TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: usePhysicalSize,
            sharesKindColors: sharesKindColors,
            colorScheme: colorScheme
        )
    }

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> ScanSessionSizeModeUpdateResult {
        if !usePhysicalSize {
            usleep(150_000)
        }
        let resultRootItem: DiskItem = usePhysicalSize ? physicalRootItem : logicalRootItem
        updateRecorder?.record(usePhysicalSize: usePhysicalSize)
        return ScanSessionSizeModeUpdateResult(
            rootItem: resultRootItem,
            presentationMetrics: presentationMetrics(
                rootItem: resultRootItem,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: sharesKindColors,
                colorScheme: colorScheme
            ),
            selectionPath: selectionPath,
            usePhysicalSize: usePhysicalSize
        )
    }
}

@MainActor
struct SourceWindowViewModelTests {
    @Test func permissionDeniedVolumeCannotBeScanned() {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Backup",
            displayName: "Backup",
            scanDisabledReason: "Full Disk Access required"
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [source],
            filter: SourceVolumeFilter(
                includesExternalVolumes: true,
                includesNetworkVolumes: true,
                includesDiskImages: true
            )
        )
        AppCommandRouter.shared.canScanSelectedVolume = true

        viewModel.select(source.id)

        #expect(viewModel.selectedSource == source)
        #expect(source.canScan == false)
        #expect(AppCommandRouter.shared.canScanSelectedVolume == false)
    }

    @Test func deactivatingUnchangedCommandStateDoesNotPublish() {
        let commandState: ScanWindowCommandState = ScanWindowCommandState()
        var changeCount: Int = 0
        let cancellable: AnyCancellable = commandState.objectWillChange.sink {
            changeCount += 1
        }

        commandState.deactivate()

        #expect(changeCount == 0)
        _ = cancellable
    }

    @Test func changingFilterPublishesOnceWithoutChangingSelectionOrCommandState() {
        let internalSource: ScanSource = ScanSource(
            path: "/",
            displayName: "Internal",
            isLocalVolume: true,
            isInternalVolume: true
        )
        let externalSource: ScanSource = ScanSource(
            path: "/Volumes/External",
            displayName: "External",
            isLocalVolume: true,
            isRemovableVolume: true,
            isInternalVolume: false
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [internalSource, externalSource]
        )
        AppCommandRouter.shared.canScanSelectedVolume = false
        var viewModelChangeCount: Int = 0
        var commandStateChangeCount: Int = 0
        let viewModelCancellable: AnyCancellable = viewModel.objectWillChange.sink {
            viewModelChangeCount += 1
        }
        let commandStateCancellable: AnyCancellable = AppCommandRouter.shared.objectWillChange.sink {
            commandStateChangeCount += 1
        }

        viewModel.setFilter(SourceVolumeFilter(
            includesExternalVolumes: true,
            includesNetworkVolumes: true,
            includesDiskImages: true
        ))
        viewModel.select(nil)

        #expect(viewModel.filteredSources.count == 2)
        #expect(viewModelChangeCount == 1)
        #expect(commandStateChangeCount == 0)
        _ = (viewModelCancellable, commandStateCancellable)
    }

    @Test func settingAnUnchangedFilterDoesNotPublish() {
        let filter: SourceVolumeFilter = SourceVolumeFilter(
            includesExternalVolumes: true,
            includesNetworkVolumes: true,
            includesDiskImages: true
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [],
            filter: filter
        )
        var changeCount: Int = 0
        let cancellable: AnyCancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        viewModel.setFilter(filter)

        #expect(changeCount == 0)
        _ = cancellable
    }

    @Test func asyncRefreshIgnoresStaleResults() async {
        let loader: ControllableSourceLoader = ControllableSourceLoader()
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [],
            filter: SourceVolumeFilter(
                includesExternalVolumes: true,
                includesNetworkVolumes: true,
                includesDiskImages: true
            ),
            sourceLoader: {
                await loader.load()
            }
        )
        let staleTask: Task<Void, Never> = viewModel.refresh()
        let latestTask: Task<Void, Never> = viewModel.refresh()

        await loader.waitForPendingLoadCount(2)
        await loader.finishLoad(
            id: 2,
            with: [
                ScanSource(path: "/Volumes/New", displayName: "New", isLocalVolume: true)
            ]
        )
        await latestTask.value
        await loader.finishLoad(
            id: 1,
            with: [
                ScanSource(path: "/Volumes/Old", displayName: "Old", isLocalVolume: true)
            ]
        )
        await staleTask.value

        #expect(viewModel.sources.map(\.displayName) == ["New"])
    }
}

struct ZStatusFieldsViewTests {
    @Test(
        "Status timeline only ticks while scan UI has live progress",
        arguments: [
            (ScanSessionState.ready, false, false),
            (.scanning, false, true),
            (.complete, false, false),
            (.cancelled, false, false),
            (.failed, false, false),
            (.complete, true, true)
        ]
    )
    func statusTimelineTickingPolicy(
        state: ScanSessionState,
        isBuildingTreemap: Bool,
        expected: Bool
    ) {
        #expect(
            ZStatusTimelinePolicy.isTicking(
                state: state,
                isBuildingTreemap: isBuildingTreemap
            ) == expected
        )
    }
}

@MainActor
struct InspectorWindowLayoutTests {
    @Test func informationTabUsesPreferredSize() {
        #expect(InspectorWindowTab.information.layout.preferredContentSize.width == 720)
        #expect(InspectorWindowTab.information.layout.preferredContentSize.height == 720)
    }

    @Test func sourceInformationUsesFullInformationSizeWithoutScanContext() {
        let coordinator = InspectorWindowLayoutCoordinator()
        let slot = coordinator.slot(for: .information, context: nil, hasSource: true)
        #expect(slot == .information)
        #expect(coordinator.preferredContentSize(for: slot, on: nil) == NSSize(width: 720, height: 720))
    }

    @Test func allTabsShareTheSameWindowMinimum() {
        let controller = InspectorWindowController.shared
        let originalTab = controller.selectedTab
        defer { controller.selectedTab = originalTab }
        let minimum = controller.currentLayout.minimumContentSize
        for tab in InspectorWindowTab.allCases {
            controller.selectedTab = tab
            #expect(controller.currentLayout.minimumContentSize == minimum)
        }
    }

    @Test func diskUsageTabUsesPreferredHeight() {
        #expect(InspectorWindowTab.diskUsage.layout.preferredContentSize.height == 420)
        #expect(InspectorWindowTab.diskUsage.layout.minimumContentSize.height == 400)
        #expect(InspectorWindowLayout.compactDiskUsage.preferredContentSize.height == 350)
        #expect(DiskUsageLayoutMetrics.pieDiameter == 200)
        #expect(DiskUsageLayoutMetrics.bottomPadding == 20)
    }

    @Test func diskUsageLayoutUsesASeparateSlotForVolumeScans() {
        let layoutCoordinator: InspectorWindowLayoutCoordinator = InspectorWindowLayoutCoordinator()
        let source: ScanSource = ScanSource(
            path: "/Volumes/Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )
        let session: ScanSession = ScanSession(source: source)
        let context: InspectorWindowContext = InspectorWindowContext(
            session: session,
            selectionCoordinator: ScanWindowSelectionCoordinator()
        )

        #expect(layoutCoordinator.slot(for: .diskUsage, context: nil) == .compactDiskUsage)
        #expect(layoutCoordinator.slot(for: .diskUsage, context: context) == .fullDiskUsage)
    }

    @Test func emptyTabsShareOneSizeInsteadOfEachTabsOwnContentSize() {
        let layoutCoordinator: InspectorWindowLayoutCoordinator = InspectorWindowLayoutCoordinator()
        let source: ScanSource = ScanSource(path: "/scan", displayName: "scan")
        let session: ScanSession = ScanSession(source: source)
        let context: InspectorWindowContext = InspectorWindowContext(
            session: session,
            selectionCoordinator: ScanWindowSelectionCoordinator()
        )

        for tab: InspectorWindowTab in [.information, .selectionList, .scanIssues] {
            #expect(layoutCoordinator.slot(for: tab, context: nil) == .empty)
            #expect(layoutCoordinator.slot(for: tab, context: context) != .empty)
        }
        #expect(layoutCoordinator.layout(for: .empty).preferredContentSize == InspectorWindowLayout.compactDiskUsage.preferredContentSize)
    }

    @Test func tabBarWidthFitsAllFiveTabLabelsWithoutTruncating() {
        // Regression coverage for a real truncation bug: this constant must be
        // widened whenever a tab is added, not left at whatever fit the previous
        // tab count.
        #expect(InspectorWindowTab.allCases.count == 5)
        #expect(InspectorWindowLayout.minimumTabBarWidth == 700)
    }

    @Test func inactiveDiskUsagePaneRequestsVolumeSelection() {
        #expect(InspectorWindowTab.diskUsage.inactiveTitle == "No Volume Selected")
        #expect(InspectorWindowTab.diskUsage.inactiveDescription.contains("volume scan window"))
    }

    @Test func inspectorAutosaveNameBumpsLegacyFrameDefaults() {
        #expect(InspectorWindowController.frameAutosaveName == "DiskHogInspectorWindowV5")
    }

    @Test func formatsInspectorTitlesFromTheActiveSource() {
        let source: ScanSource = ScanSource(path: "/Volumes/Test", displayName: "Test Volume")

        #expect(
            InspectorWindowTitleFormatter.title(context: nil, source: source)
                == "Inspector - Test Volume — /Volumes/Test"
        )
        #expect(InspectorWindowTitleFormatter.title(context: nil, source: nil) == "Inspector")
    }

    @Test func inspectorTitleUsesActiveContextsFullFolderPath() {
        let source = ScanSource(path: "/Volumes/Test/Photos", displayName: "Test Volume")
        let context = InspectorWindowContext(
            session: ScanSession(source: source),
            selectionCoordinator: ScanWindowSelectionCoordinator()
        )
        let fallback = ScanSource(path: "/Volumes/Test/Archive", displayName: "Test Volume")
        #expect(InspectorWindowTitleFormatter.title(context: context, source: fallback)
            == "Inspector - Test Volume — /Volumes/Test/Photos")
        #expect(InspectorWindowTitleFormatter.title(context: nil, source: fallback)
            == "Inspector - Test Volume — /Volumes/Test/Archive")
    }

    @Test func scanItemContextMenuIncludesInspectorCommand() {
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8,
            kindName: "Plain Text"
        ).freeze()
        let actionTarget: DiskItemContextMenuActionTarget = DiskItemContextMenuActionTarget()
        let menu: NSMenu = DiskItemContextMenuBuilder.menu(
            for: item,
            actionTarget: actionTarget,
            treeActionsEnabled: true
        )

        let inspectorItem: NSMenuItem? = menu.item(withTitle: "Show Inspector")
        #expect(inspectorItem?.action == #selector(DiskItemContextMenuActionTarget.showInspectorMenuItem(_:)))
        #expect(inspectorItem?.target === actionTarget)
    }

    @Test func moveToTrashIsDisabledForTrashAndDescendants() throws {
        let trashURL: URL = URL(fileURLWithPath: "/Users/test/.Trash")
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/Users/test"),
            isDirectory: true
        )
        rootBuilder.appendChild(DiskItemBuilder(
            url: trashURL,
            isDirectory: true
        ))
        rootBuilder.appendChild(DiskItemBuilder(
            url: trashURL.appendingPathComponent("folder/file.txt")
        ))
        rootBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        ))
        let rootItem: DiskItem = rootBuilder.freeze()
        let trashItem: DiskItem = try #require(rootItem.item(atPath: trashURL.path))
        let descendant: DiskItem = try #require(rootItem.item(atPath: trashURL.appendingPathComponent("folder/file.txt").path))
        let ordinaryItem: DiskItem = try #require(rootItem.item(atPath: "/Users/test/Documents/file.txt"))

        #expect(!DiskItemDeletionPolicy.canDelete(trashItem, trashDirectoryURL: trashURL))
        #expect(!DiskItemDeletionPolicy.canDelete(descendant, trashDirectoryURL: trashURL))
        #expect(DiskItemDeletionPolicy.canDelete(ordinaryItem, trashDirectoryURL: trashURL))
    }

    @Test func trashContainmentUsesPathComponents() {
        let trashURL: URL = URL(fileURLWithPath: "/Users/test/.Trash")
        let similarlyNamedDirectory: URL = URL(fileURLWithPath: "/Users/test/.Trash-Archive/file.txt")

        #expect(!DiskItemDeletionPolicy.contains(similarlyNamedDirectory, in: trashURL))
    }

    @Test func showingItemInformationSelectsInformationTab() {
        let controller: InspectorWindowController = .shared
        controller.selectedTab = .selectionList
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        ).freeze()

        controller.showInformation(for: item, from: nil)

        #expect(controller.selectedTab == .information)
    }

    @Test func selectedSourceBecomesInspectorVolumeContext() {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )
        let controller: InspectorWindowController = .shared
        controller.deactivate()
        var changeCount: Int = 0
        let cancellable: AnyCancellable = controller.objectWillChange.sink {
            changeCount += 1
        }

        controller.activate(source: nil)
        controller.activate(source: source)
        controller.activate(source: source)

        #expect(controller.activeContext == nil)
        #expect(controller.activeSource == source)
        #expect(changeCount == 1)
        controller.deactivate()
        _ = cancellable
    }

    @Test func inspectorControllerRoutesVolumeContextsToTheFullDiskUsageLayout() {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )
        let session: ScanSession = ScanSession(source: source)
        let context: InspectorWindowContext = InspectorWindowContext(
            session: session,
            selectionCoordinator: ScanWindowSelectionCoordinator()
        )
        let controller: InspectorWindowController = .shared
        controller.activate(context)
        controller.selectedTab = .diskUsage

        #expect(
            controller.currentLayout.preferredContentSize
                == InspectorWindowTab.diskUsage.layout.preferredContentSize
        )

        controller.selectedTab = .information
        controller.deactivate(if: context)
    }

    @Test func sourceDiskUsageUsesVolumeCapacityWithoutScanResults() throws {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Nonexistent-Disk-Hog-Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )

        let usage: DiskUsage = try #require(DiskUsage.make(for: source))

        #expect(usage.totalBytes == 1_000)
        #expect(usage.primaryUsedBytes == 750)
        #expect(usage.otherUsedBytes == 0)
        #expect(usage.freeBytes == 250)
    }

    @Test func allKindsSelectionUpdatesInspectorContext() {
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan")
        )
        let context: InspectorWindowContext = InspectorWindowContext(
            session: session,
            selectionCoordinator: ScanWindowSelectionCoordinator()
        )
        var activePane: ScanWindowPane?
        var shownFilter: SelectionListFilter?
        let coordinator: KindStatisticTableView.Coordinator = KindStatisticTableView.Coordinator(
            statistics: [],
            selectedFilter: Binding(
                get: { context.selectionListFilter },
                set: { context.selectionListFilter = $0 }
            ),
            activePane: Binding(
                get: { activePane },
                set: { activePane = $0 }
            ),
            onShowSelectionList: { shownFilter = $0 }
        )
        let tableView: NSTableView = NSTableView()
        tableView.dataSource = coordinator
        coordinator.tableView = tableView
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification)
        )

        #expect(context.selectionListFilter == .all)
        #expect(shownFilter == .all)
        #expect(activePane == .kinds)
    }

    @Test func informationContextMenuIncludesOnlyInformationCommands() {
        let coordinator: InformationContextMenuCoordinator = InformationContextMenuCoordinator()
        let menu: NSMenu = coordinator.makeContextMenu()

        #expect(menu.items.map(\.title) == ["Copy Information", "Reveal in Finder"])
    }

    @Test func multilineInformationRowsAreNotCollapsed() {
        #expect(FileInformationRow("Attribute", "11 bytes\nactual value").isMultiline)
        #expect(!FileInformationRow("Attribute", "11 bytes").isMultiline)
    }
}

struct DiskItemPasteboardWriterTests {
    @Test func publishesFinderCompatibleFileRepresentations() throws {
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/Users/test/Documents/report.txt")
        ).freeze()
        let writer: DiskItemPasteboardWriter = DiskItemPasteboardWriter(item: item)
        let pasteboard: NSPasteboard = NSPasteboard(
            name: NSPasteboard.Name("DiskItemPasteboardWriterTests")
        )

        #expect(writer.write(to: pasteboard))
        #expect(pasteboard.types?.contains(.fileURL) == true)
        #expect(pasteboard.types?.contains(.URL) == true)
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.string(forType: .fileURL) == item.url.absoluteString)
        #expect(pasteboard.string(forType: .string) == item.path)
    }

    @Test @MainActor func focusedFileViewSupportsCopyAndServices() throws {
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/Users/test/Documents/report.txt")
        ).freeze()
        let view: DiskItemPasteboardTableView = DiskItemPasteboardTableView()
        view.pasteboardItemProvider = { item }
        let pasteboard: NSPasteboard = NSPasteboard(
            name: NSPasteboard.Name("DiskItemPasteboardServicesTests")
        )

        let requestor: Any? = view.validRequestor(forSendType: .fileURL, returnType: nil)
        #expect(requestor as? DiskItemPasteboardTableView === view)
        #expect(view.validRequestor(forSendType: .fileURL, returnType: .string) == nil)
        #expect(view.writeSelection(to: pasteboard, types: [.fileURL]))
        #expect(pasteboard.string(forType: .fileURL) == item.url.absoluteString)
    }
}

struct ScanSourceAccessTests {
    @Test func permissionFailureDisablesLocalVolumeScan() {
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Backup"),
            isLocalVolume: true,
            directoryContents: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        #expect(reason == "Full Disk Access required")
    }

    @Test func permissionFailureDoesNotPreflightNetworkVolume() {
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Network"),
            isLocalVolume: false,
            directoryContents: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        #expect(reason == nil)
    }

    @Test func protectedFolderFailureDisablesBootVolumeScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { $0 == protectedURL }
        ) { url in
            if url == protectedURL {
                throw CocoaError(.fileReadNoPermission)
            }
            return []
        }

        #expect(reason == "Full Disk Access required")
    }

    @Test func accessibleProtectedFoldersAllowBootVolumeScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { $0 == protectedURL }
        ) { _ in
            []
        }

        #expect(reason == nil)
    }

    @Test func protectedFolderOnAnotherVolumeDoesNotDisableScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        var inspectedProtectedFolder: Bool = false
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Backup"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { _ in true }
        ) { url in
            if url == protectedURL {
                inspectedProtectedFolder = true
                throw CocoaError(.fileReadNoPermission)
            }
            return []
        }

        #expect(reason == nil)
        #expect(inspectedProtectedFolder == false)
    }
}

@MainActor
struct ApplicationWindowPlacementServiceTests {
    @Test func movesNewWindowIntoAvailableSpaceWithoutMovingExistingWindow() {
        let visibleFrame: NSRect = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let sourceFrame: NSRect = NSRect(x: 800, y: 250, width: 300, height: 400)
        let scanFrame: NSRect = NSRect(x: 500, y: 180, width: 700, height: 600)

        let plan: ManagedWindowPlacementPlan = ApplicationWindowPlacementService.placementPlan(
            targetFrame: scanFrame,
            obstacleFrames: [sourceFrame],
            visibleFrame: visibleFrame
        )

        #expect(plan.targetFrame.intersects(sourceFrame) == false)
        #expect(visibleFrame.contains(plan.targetFrame))
    }

    @Test func leavesExistingWindowsAloneWhenOverlapCannotBeAvoided() {
        let visibleFrame: NSRect = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let sourceFrame: NSRect = NSRect(x: 300, y: 100, width: 300, height: 500)
        let scanFrame: NSRect = NSRect(x: 100, y: 100, width: 600, height: 500)

        let plan: ManagedWindowPlacementPlan = ApplicationWindowPlacementService.placementPlan(
            targetFrame: scanFrame,
            obstacleFrames: [sourceFrame],
            visibleFrame: visibleFrame
        )

        #expect(plan.targetFrame.intersects(sourceFrame))
        #expect(visibleFrame.contains(plan.targetFrame))
    }
}

struct DiskItemTests {

    @Test func builderCopiesAreReferencesToTheSameNode() {
        let builder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 1
        )
        let sameBuilder: DiskItemBuilder = builder

        sameBuilder.allocatedSizeValue = 2

        #expect(builder === sameBuilder)
        #expect(builder.allocatedSizeValue == 2)
    }

    @Test func builderFreezePreservesChildAncestryAndUpdatesSizes() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let childBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )

        rootBuilder.appendChild(childBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let child: DiskItem = root.child(at: 0)

        #expect(root.childCount == 1)
        #expect(root.child(at: 0) == child)
        #expect(root.descendantsMatchingAncestorPath(of: child) == [root, child])
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

    @Test func filesOfKindFindsNestedFilesAndExcludesFoldersAndOtherKinds() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            kindName: "Plain Text",
            isDirectory: true
        )
        folder.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/folder/nested.txt"),
                kindName: "Plain Text"
            )
        )
        root.appendChild(folder)
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/top.txt"),
                kindName: "Plain Text"
            )
        )
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/image.png"),
                kindName: "PNG image"
            )
        )

        let frozenRoot: DiskItem = root.freeze()
        let matches: [DiskItem] = frozenRoot.files(ofKind: "Plain Text")
        let allFiles: [DiskItem] = frozenRoot.allFiles()

        #expect(Set(matches.map(\.path)) == ["/scan/folder/nested.txt", "/scan/top.txt"])
        #expect(Set(allFiles.map(\.path)) == [
            "/scan/folder/nested.txt",
            "/scan/top.txt",
            "/scan/image.png"
        ])
    }

    @Test func fileInformationIncludesSecurityAndFileSystemSections() throws {
        let temporaryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("metadata".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let item: DiskItem = DiskItemBuilder(
            url: temporaryURL,
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        ).freeze()
        let snapshot: FileInformationSnapshot = FileInformationSnapshot.load(
            item: item,
            usePhysicalSize: true
        )
        let sectionTitles: Set<String> = Set(snapshot.sections.map(\.title))

        #expect(sectionTitles.contains("Identity"))
        #expect(sectionTitles.contains("Ownership and Access"))
        #expect(sectionTitles.contains("File System"))
        #expect(sectionTitles.contains("Extended Attributes"))
        #expect(!sectionTitles.contains("Volume"))

        let copiedText: String = snapshot.plainText(
            itemName: item.displayName,
            kindDescription: "File"
        )
        #expect(copiedText.hasPrefix("\(item.displayName)\nFile\n\nIdentity\n"))
        #expect(copiedText.contains("Path: \(temporaryURL.path)"))
        #expect(copiedText.contains("\n\nOwnership and Access\n"))
        #expect(copiedText.contains("\n\nFile System\n"))
    }

    @Test func volumeInformationIncludesCapacityAndOmitsScanOnlySizes() throws {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Nonexistent-Disk-Hog-Information-Test",
            displayName: "Test Volume",
            volumeFormat: "APFS",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: true,
            isDiskImageVolume: false
        )

        let snapshot: FileInformationSnapshot = FileInformationSnapshot.load(source: source)
        let volumeSection: FileInformationSection = try #require(
            snapshot.sections.first(where: { $0.title == "Volume" })
        )
        let rowsByLabel: [String: String] = Dictionary(
            uniqueKeysWithValues: volumeSection.rows.map { ($0.label, $0.value) }
        )

        #expect(snapshot.sections.contains(where: { $0.title == "Identity" }))
        #expect(snapshot.sections.contains(where: { $0.title == "Ownership and Access" }))
        #expect(snapshot.sections.contains(where: { $0.title == "Extended Attributes" }))
        #expect(snapshot.sections.contains(where: { $0.title == "Sizes" }) == false)
        #expect(rowsByLabel["Mount point"] == "/Volumes/Nonexistent-Disk-Hog-Information-Test")
        #expect(rowsByLabel["Format"]?.contains("APFS") == true)
        #expect(rowsByLabel["Scan availability"] == "Available")
    }

    @Test func descendantsMatchingAncestorPathRejectsSiblingPathPrefixes() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )
        let siblingWithPrefixBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder-other"),
            isDirectory: true
        )

        folderBuilder.appendChild(DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder/file.txt")))
        rootBuilder.appendChild(folderBuilder)
        rootBuilder.appendChild(siblingWithPrefixBuilder)

        let root: DiskItem = rootBuilder.freeze()
        let folder: DiskItem = root.child(at: 0)
        let file: DiskItem = folder.child(at: 0)
        let siblingWithPrefix: DiskItem = root.child(at: 1)

        #expect(folder.descendantsMatchingAncestorPath(of: file) == [folder, file])
        #expect(folder.descendantsMatchingAncestorPath(of: siblingWithPrefix).isEmpty)
    }

    @Test func recalculatesRecursiveFolderSizesAndSortsLargestFirstThenNameAscending() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let smallFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/2-small.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let largeFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/10-large.bin"),
            allocatedSizeValue: 900,
            logicalSizeValue: 900
        )
        let sameSizeByName: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/1-same.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )

        root.appendChild(smallFile, updateSize: false)
        root.appendChild(largeFile, updateSize: false)
        root.appendChild(sameSizeByName, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)
        let frozenRoot: DiskItem = root.freeze()

        #expect(frozenRoot.allocatedSizeValue == 1100)
        #expect(frozenRoot.children.map(\.displayName) == ["10-large.bin", "1-same.bin", "2-small.bin"])
    }

    @Test func builderAndTopLevelOrderingShareAscendingNumericCaseInsensitiveTieBreaks() {
        let first: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/File 10.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let second: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file 2.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )

        #expect(DiskItemBuilderOrdering.areInOrder(second, first, usePhysicalSize: true))
        #expect(DiskItemBuilderOrdering.areInOrder(
            firstName: second.name,
            firstAllocatedSize: second.allocatedSizeValue,
            firstLogicalSize: second.logicalSizeValue,
            firstIsSpecialItem: second.isSpecialItem,
            secondName: first.name,
            secondAllocatedSize: first.allocatedSizeValue,
            secondLogicalSize: first.logicalSizeValue,
            secondIsSpecialItem: first.isSpecialItem,
            usePhysicalSize: true
        ))
    }

    @Test func recalculatingLogicalSizeSortsChildrenByLogicalSize() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let allocatedOnly: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/allocated-only.bin"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 0
        )
        let logicalContent: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/logical-content.bin"),
            allocatedSizeValue: 512,
            logicalSizeValue: 128
        )

        root.appendChild(allocatedOnly, updateSize: false)
        root.appendChild(logicalContent, updateSize: false)
        root.recalculateSize(usePhysicalSize: false)
        let frozenRoot: DiskItem = root.freeze()

        #expect(frozenRoot.logicalSizeValue == 128)
        #expect(frozenRoot.children.map(\.displayName) == ["logical-content.bin", "allocated-only.bin"])
    }

    @Test func duplicateHardlinkContributesZeroSize() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let duplicate: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/duplicate.dat"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 128,
            isHardlinkDuplicate: true
        )

        root.appendChild(duplicate, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)
        let frozenRoot: DiskItem = root.freeze()
        let frozenDuplicate: DiskItem = frozenRoot.child(at: 0)

        #expect(frozenDuplicate.allocatedSizeValue == 0)
        #expect(frozenDuplicate.logicalSizeValue == 0)
        #expect(frozenRoot.allocatedSizeValue == 0)
    }

    @Test func opaquePackageKeepsPrestampedSize() {
        let package: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/App.app"),
            isDirectory: true,
            isPackage: true
        )
        package.setOpaquePackageSize(allocated: 12345, logical: 6789)

        package.recalculateSize(usePhysicalSize: true)
        let frozenPackage: DiskItem = package.freeze()

        #expect(frozenPackage.allocatedSizeValue == 12345)
        #expect(frozenPackage.logicalSizeValue == 6789)
    }

    @Test func addingChildToOpaquePackageUsesChildDerivedSize() {
        let package: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/App.app"),
            isDirectory: true,
            isPackage: true
        )
        package.setOpaquePackageSize(allocated: 12345, logical: 6789)
        package.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/App.app/Contents/file"),
                allocatedSizeValue: 4096,
                logicalSizeValue: 128
            ),
            updateSize: false
        )

        package.recalculateSize(usePhysicalSize: true)

        #expect(package.allocatedSizeValue == 4096)
        #expect(package.logicalSizeValue == 128)
    }

    @Test func childURLIsStoredAfterFreeze() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let childBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )

        rootBuilder.appendChild(childBuilder)
        let child: DiskItem = rootBuilder.freeze().child(at: 0)

        #expect(child.path == "/scan/folder")
        #expect(child.url.path == "/scan/folder")
    }

    @Test func replacingSubtreeRebuildsAncestorsAndRestoresItemsByPath() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/old.txt"),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        ))
        rootBuilder.appendChild(folderBuilder)
        let root: DiskItem = rootBuilder.freeze()

        let replacementBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        replacementBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/new.txt"),
            allocatedSizeValue: 25,
            logicalSizeValue: 25
        ))
        let replacement: DiskItem = replacementBuilder.freeze(isRoot: false)
        let updatedRoot: DiskItem? = DiskItemTreeEditor.replacingSubtree(
            in: root,
            atPath: "/scan/folder",
            with: replacement,
            usePhysicalSize: true
        )

        #expect(updatedRoot?.isRoot == true)
        #expect(updatedRoot?.allocatedSizeValue == 25)
        #expect(updatedRoot?.item(atPath: "/scan/folder/new.txt")?.name == "new.txt")
        #expect(updatedRoot?.item(atPath: "/scan/folder/old.txt") == nil)
    }

    @Test func removingSubtreeRecalculatesSizeAndAllowsAncestorFallback() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/file.txt"),
            allocatedSizeValue: 40,
            logicalSizeValue: 20
        ))
        rootBuilder.appendChild(folderBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let updatedRoot: DiskItem? = DiskItemTreeEditor.removingSubtree(
            from: root,
            atPath: "/scan/folder/file.txt",
            usePhysicalSize: true
        )

        #expect(updatedRoot?.allocatedSizeValue == 0)
        #expect(updatedRoot?.item(atPath: "/scan/folder/file.txt") == nil)
        #expect(updatedRoot?.item(atPath: "/scan/folder/file.txt", allowAncestors: true)?.path == "/scan/folder")
    }

    @Test func removingSubtreeReusesUntouchedPackedSubtrees() throws {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/delete.txt"),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        ))
        let untouchedBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/untouched"), isDirectory: true)
        untouchedBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/untouched/file.txt"),
            allocatedSizeValue: 30,
            logicalSizeValue: 30
        ))
        rootBuilder.appendChild(folderBuilder)
        rootBuilder.appendChild(untouchedBuilder)
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let updatedRoot: DiskItem = try #require(DiskItemTreeEditor.removingSubtree(
            from: root,
            atPath: "/scan/folder/delete.txt",
            usePhysicalSize: true
        ))
        let untouched: DiskItem = try #require(updatedRoot.item(atPath: "/scan/untouched/file.txt"))

        #expect(updatedRoot.snapshot.chunks[0] === root.snapshot.chunks[0])
        #expect(untouched.address.chunkIndex == 0)
        #expect(updatedRoot.allocatedSizeValue == 30)
    }

    @Test func repeatedSubtreeEditsPreservePreviousPathOverrides() throws {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/delete-first.txt"),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        ))
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/delete-second.txt"),
            allocatedSizeValue: 20,
            logicalSizeValue: 20
        ))
        rootBuilder.appendChild(folderBuilder)
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let firstEdit: DiskItem = try #require(DiskItemTreeEditor.removingSubtree(
            from: root,
            atPath: "/scan/folder/delete-first.txt",
            usePhysicalSize: true
        ))
        let secondEdit: DiskItem = try #require(DiskItemTreeEditor.removingSubtree(
            from: firstEdit,
            atPath: "/scan/folder/delete-second.txt",
            usePhysicalSize: true
        ))

        #expect(secondEdit.item(atPath: "/scan/folder/delete-first.txt") == nil)
        #expect(secondEdit.item(atPath: "/scan/folder/delete-second.txt") == nil)
        #expect(secondEdit.allocatedSizeValue == 0)
    }

    @Test func replacingDeepSubtreeUsesIterativeEditor() throws {
        var currentPath: String = "/scan"
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: currentPath),
            isDirectory: true
        )
        var parentBuilder: DiskItemBuilder = rootBuilder
        for depth: Int in 0..<500 {
            currentPath += "/\(depth)"
            let childBuilder: DiskItemBuilder = parentBuilder.makeChild(
                url: URL(fileURLWithPath: currentPath),
                isDirectory: true
            )
            parentBuilder.appendChild(childBuilder, updateSize: false)
            parentBuilder = childBuilder
        }
        let oldFilePath: String = currentPath + "/old.txt"
        parentBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: oldFilePath),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        ))
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let replacement: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: currentPath + "/new.txt"),
            allocatedSizeValue: 25,
            logicalSizeValue: 25
        ).freeze(isRoot: false)
        let updatedRoot: DiskItem = try #require(DiskItemTreeEditor.replacingSubtree(
            in: root,
            atPath: oldFilePath,
            with: replacement,
            usePhysicalSize: true
        ))

        #expect(updatedRoot.allocatedSizeValue == 25)
        #expect(updatedRoot.item(atPath: oldFilePath) == nil)
        #expect(updatedRoot.item(atPath: currentPath + "/new.txt")?.allocatedSizeValue == 25)
    }

    @Test func removingOneItemFromLargeFlatTreeRebuildsOnlyTheEditedPath() throws {
        let itemCount: Int = 100_000
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        for index: Int in 0..<itemCount {
            rootBuilder.appendChild(
                DiskItemBuilder(
                    url: URL(fileURLWithPath: "/scan/file-\(index).bin"),
                    allocatedSizeValue: 1,
                    logicalSizeValue: 1,
                    kindName: "Binary"
                ),
                updateSize: false
            )
        }
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let updatedRoot: DiskItem = try #require(DiskItemTreeEditor.removingSubtree(
            from: root,
            atPath: "/scan/file-50000.bin",
            usePhysicalSize: true
        ))

        #expect(updatedRoot.childCount == itemCount - 1)
        #expect(updatedRoot.allocatedSizeValue == UInt64(itemCount - 1))
        #expect(updatedRoot.item(atPath: "/scan/file-50000.bin") == nil)
        #expect(updatedRoot.item(atPath: "/scan/file-49999.bin")?.address.chunkIndex == 0)
        #expect(updatedRoot.item(atPath: "/scan/file-50001.bin")?.address.chunkIndex == 0)
        #expect(updatedRoot.snapshot.chunks.count == root.snapshot.chunks.count + 1)
    }
}

struct SelectionListPipelineTests {
    @Test func snapshotIncludesAllFilesAndBuildsSelectionIndex() throws {
        let root: DiskItem = selectionListRoot()

        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: root,
            filter: .all,
            usePhysicalSize: true
        )

        #expect(Set(snapshot.rows.map(\.fullPath)) == [
            "/scan/Notes/Read Me.TXT",
            "/scan/Notes/todo.md",
            "/scan/photo.png"
        ])
        #expect(snapshot.rowsByID.count == snapshot.rows.count)
        #expect(snapshot.rows.allSatisfy { snapshot.rowsByID[$0.id]?.item == $0.item })
    }

    @Test func snapshotFiltersByKindAndUsesRequestedSize() throws {
        let root: DiskItem = selectionListRoot()

        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: root,
            filter: .kind("Plain Text"),
            usePhysicalSize: false
        )

        #expect(snapshot.rows.map(\.name) == ["Read Me.TXT"])
        #expect(snapshot.rows.first?.size == 12)
    }

    @Test func querySearchesCaseInsensitivelyInTheSelectedScope() throws {
        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: selectionListRoot(),
            filter: .all,
            usePhysicalSize: true
        )
        let descriptors: [SelectionListSortDescriptor] = [
            SelectionListSortDescriptor(field: .name, isAscending: true)
        ]

        let nameMatches: SelectionListQueryResult = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "read me",
            scope: .name,
            sortDescriptors: descriptors
        )
        let pathMatches: SelectionListQueryResult = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "NOTES",
            scope: .path,
            sortDescriptors: descriptors
        )
        let kindMatches: SelectionListQueryResult = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "markdown",
            scope: .all,
            sortDescriptors: descriptors
        )

        #expect(nameMatches.rows.map(\.name) == ["Read Me.TXT"])
        #expect(pathMatches.rows.map(\.name) == ["Read Me.TXT", "todo.md"])
        #expect(kindMatches.rows.map(\.name) == ["todo.md"])
        #expect(pathMatches.rows.enumerated().allSatisfy {
            pathMatches.rowIndexByID[$0.element.id] == $0.offset
        })
    }

    @Test func queryUsesRequestedSortOrder() throws {
        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: selectionListRoot(),
            filter: .all,
            usePhysicalSize: true
        )

        let ascendingNames: SelectionListQueryResult = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "",
            scope: .all,
            sortDescriptors: [SelectionListSortDescriptor(field: .name, isAscending: true)]
        )
        let descendingSizes: SelectionListQueryResult = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "",
            scope: .all,
            sortDescriptors: [SelectionListSortDescriptor(field: .size, isAscending: false)]
        )

        #expect(ascendingNames.rows.map(\.name) == ["photo.png", "Read Me.TXT", "todo.md"])
        #expect(descendingSizes.rows.map(\.size) == [12_288, 8_192, 4_096])
    }

    @Test func canceledQueryStopsBeforePublishingResults() async {
        let row: SelectionListRow = SelectionListRow(
            item: DiskItem(
                url: URL(fileURLWithPath: "/scan/file.txt"),
                displayName: "file.txt",
                allocatedSizeValue: 4_096,
                logicalSizeValue: 4,
                kindName: "Plain Text"
            ),
            size: 4_096
        )
        let worker = Task.detached {
            try SelectionListPipeline.visibleRows(
                from: Array(repeating: row, count: 10_000),
                searchText: "file",
                scope: .all,
                sortDescriptors: [SelectionListSortDescriptor(field: .size, isAscending: false)]
            )
        }

        worker.cancel()

        await #expect(throws: CancellationError.self) {
            try await worker.value
        }
    }

    private func selectionListRoot() -> DiskItem {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let notes: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/Notes"),
            isDirectory: true
        )
        notes.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/Notes/Read Me.TXT"),
                displayName: "Read Me.TXT",
                allocatedSizeValue: 4_096,
                logicalSizeValue: 12,
                kindName: "Plain Text"
            )
        )
        notes.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/Notes/todo.md"),
                allocatedSizeValue: 8_192,
                logicalSizeValue: 24,
                kindName: "Markdown document"
            )
        )
        root.appendChild(notes)
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/photo.png"),
                allocatedSizeValue: 12_288,
                logicalSizeValue: 36,
                kindName: "PNG image"
            )
        )
        return root.freeze()
    }
}

@MainActor
struct SelectionListTableViewTests {
    @Test func completedListIsRebuiltOnlyWhenItsInputsChange() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let filter: SelectionListFilter = .kind("PNG image")
        let dataStore: SelectionListDataStore = SelectionListDataStore()

        dataStore.beginRebuild(rootID: root.id, filter: filter, usesPhysicalSize: true)
        #expect(dataStore.requiresRebuild(rootID: root.id, filter: filter, usesPhysicalSize: true))

        dataStore.publish(.empty)

        #expect(dataStore.requiresRebuild(rootID: root.id, filter: filter, usesPhysicalSize: true) == false)
        #expect(dataStore.requiresRebuild(rootID: root.id, filter: filter, usesPhysicalSize: false))
        #expect(dataStore.requiresRebuild(rootID: root.id, filter: .all, usesPhysicalSize: true))
    }

    @Test func unchangedResultGenerationDoesNotReloadRows() {
        let session: ScanSession = ScanSession(
            source: ScanSource(path: "/scan", displayName: "scan")
        )
        var selectedItemID: DiskItemID?
        var selectedItemIDs: Set<DiskItemID> = []
        var sortDescriptors: [SelectionListSortDescriptor] = [
            SelectionListSortDescriptor(field: .size, isAscending: false)
        ]
        let coordinator: SelectionListTableView.Coordinator = SelectionListTableView.Coordinator(
            session: session,
            selectedItemID: Binding(
                get: { selectedItemID },
                set: { selectedItemID = $0 }
            ),
            selectedItemIDs: Binding(
                get: { selectedItemIDs },
                set: { selectedItemIDs = $0 }
            ),
            sortDescriptors: Binding(
                get: { sortDescriptors },
                set: { sortDescriptors = $0 }
            ),
            onSelect: { _ in }
        )
        let row: SelectionListRow = SelectionListRow(
            item: DiskItem(
                url: URL(fileURLWithPath: "/scan/file.txt"),
                displayName: "file.txt",
                allocatedSizeValue: 4_096
            ),
            size: 4_096
        )
        let tableView: NSTableView = NSTableView()

        coordinator.updateRows([row], rowIndexByID: [row.id: 0], generation: 1)
        coordinator.updateRows([], rowIndexByID: [:], generation: 1)

        #expect(coordinator.numberOfRows(in: tableView) == 1)

        coordinator.updateRows([], rowIndexByID: [:], generation: 2)

        #expect(coordinator.numberOfRows(in: tableView) == 0)
    }
}

@MainActor
struct KindStatisticTableViewTests {
    @Test func unchangedStatisticsDoNotReloadRows() {
        var selectedFilter: SelectionListFilter?
        var showSelectionListCount: Int = 0
        let statistics: [TreemapKindStatistic] = [
            TreemapKindStatistic(
                kindName: "Plain Text",
                size: 4_096,
                fileCount: 1,
                color: .red
            )
        ]
        let coordinator: KindStatisticTableView.Coordinator = KindStatisticTableView.Coordinator(
            statistics: statistics,
            selectedFilter: Binding(
                get: { selectedFilter },
                set: { selectedFilter = $0 }
            ),
            activePane: .constant(nil),
            onShowSelectionList: { _ in showSelectionListCount += 1 }
        )
        let tableView: ReloadCountingTableView = ReloadCountingTableView()
        coordinator.tableView = tableView

        coordinator.updateStatisticsIfNeeded(statistics)

        #expect(tableView.reloadCount == 0)
        #expect(coordinator.numberOfRows(in: tableView) == 2)

        coordinator.updateStatisticsIfNeeded([
            TreemapKindStatistic(
                kindName: "Plain Text",
                size: 8_192,
                fileCount: 2,
                color: .red
            )
        ])

        #expect(tableView.reloadCount == 1)
        #expect(coordinator.numberOfRows(in: tableView) == 2)
        #expect(showSelectionListCount == 0)
    }

    @Test func unchangedSortGenerationDoesNotReloadRowsOnSwiftUIUpdate() {
        var selectedFilter: SelectionListFilter?
        let statistics: [TreemapKindStatistic] = [
            TreemapKindStatistic(
                kindName: "Plain Text",
                size: 4_096,
                fileCount: 1,
                color: .red
            ),
            TreemapKindStatistic(
                kindName: "PNG image",
                size: 8_192,
                fileCount: 1,
                color: .blue
            )
        ]
        let coordinator: KindStatisticTableView.Coordinator = KindStatisticTableView.Coordinator(
            statistics: statistics,
            selectedFilter: Binding(
                get: { selectedFilter },
                set: { selectedFilter = $0 }
            ),
            activePane: .constant(nil),
            onShowSelectionList: { _ in }
        )
        let tableView: ReloadCountingTableView = ReloadCountingTableView()
        tableView.sortDescriptors = [
            NSSortDescriptor(
                key: "kindName",
                ascending: true,
                selector: #selector(NSString.localizedStandardCompare(_:))
            )
        ]
        coordinator.tableView = tableView

        coordinator.tableView(tableView, sortDescriptorsDidChange: [])
        coordinator.updateStatisticsIfNeeded(statistics)

        #expect(tableView.reloadCount == 1)
        #expect(coordinator.numberOfRows(in: tableView) == 3)
    }

    @Test func selectedFileChoosesMatchingKindFilter() {
        let item: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/readme.txt"),
            kindName: "Plain Text"
        )

        #expect(
            KindsPaneView.selectedFilter(
                for: item,
                statistics: [
                    TreemapKindStatistic(
                        kindName: "Plain Text",
                        size: 4_096,
                        fileCount: 1,
                        color: .red
                    )
                ]
            ) == .kind("Plain Text")
        )
    }

    @Test func selectedPackageChoosesMatchingKindFilter() {
        let item: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/App.app"),
            kindName: "application",
            isDirectory: true,
            isPackage: true
        )

        #expect(
            KindsPaneView.selectedFilter(
                for: item,
                statistics: [
                    TreemapKindStatistic(
                        kindName: "application",
                        size: 4_096,
                        fileCount: 1,
                        color: .orange
                    )
                ]
            ) == .kind("application")
        )
    }

    @Test func selectedItemWithoutRepresentedKindClearsKindFilter() {
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )
        let unknownKind: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/archive.bin"),
            kindName: "Binary"
        )
        let statistics: [TreemapKindStatistic] = [
            TreemapKindStatistic(
                kindName: "Plain Text",
                size: 4_096,
                fileCount: 1,
                color: .red
            )
        ]

        #expect(KindsPaneView.selectedFilter(for: folder, statistics: statistics) == nil)
        #expect(KindsPaneView.selectedFilter(for: unknownKind, statistics: statistics) == nil)
        #expect(KindsPaneView.selectedFilter(for: nil, statistics: statistics) == nil)
    }
}

private final class ReloadCountingTableView: NSTableView {
    private(set) var reloadCount: Int = 0

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }
}

private actor ControllableSourceLoader {
    private var nextID: Int = 0
    private var continuations: [Int: CheckedContinuation<[ScanSource], Never>] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func load() async -> [ScanSource] {
        await withCheckedContinuation { continuation in
            nextID += 1
            continuations[nextID] = continuation
            resumeSatisfiedWaiters()
        }
    }

    func waitForPendingLoadCount(_ count: Int) async {
        guard continuations.count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func finishLoad(id: Int, with sources: [ScanSource]) {
        continuations.removeValue(forKey: id)?.resume(returning: sources)
    }

    private func resumeSatisfiedWaiters() {
        var remainingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if continuations.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        waiters = remainingWaiters
    }
}

struct TreemapKindAggregationTests {

    @Test func kindAggregationHandlesDeepDirectoryTreesIteratively() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        var parentBuilder: DiskItemBuilder = rootBuilder
        var parentURL: URL = URL(fileURLWithPath: "/scan")
        for depth: Int in 0..<5_000 {
            parentURL = parentURL.appendingPathComponent("depth-\(depth)")
            let childBuilder: DiskItemBuilder = parentBuilder.makeChild(
                url: parentURL,
                isDirectory: true
            )
            parentBuilder.appendChild(childBuilder, updateSize: false)
            parentBuilder = childBuilder
        }
        parentBuilder.appendChild(
            parentBuilder.makeChild(
                url: parentURL.appendingPathComponent("deep-file.bin"),
                allocatedSizeValue: 42,
                logicalSizeValue: 42,
                kindName: "Deep File"
            ),
            updateSize: false
        )
        rootBuilder.recalculateSize(usePhysicalSize: true)

        let aggregates: [String: TreemapKindAggregate] = TreemapKindCatalog.aggregates(
            from: rootBuilder.freeze(),
            usePhysicalSize: true,
            folderKindName: "Folder"
        )

        #expect(aggregates["Deep File"]?.fileCount == 1)
        #expect(aggregates["Deep File"]?.size == 42)
    }

    @Test func kindAggregationHandlesLargeFlatTrees() {
        let itemCount: Int = 100_000
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        for index: Int in 0..<itemCount {
            let kindName: String = index.isMultiple(of: 2) ? "Even Binary" : "Odd Binary"
            rootBuilder.appendChild(
                DiskItemBuilder(
                    url: URL(fileURLWithPath: "/scan/file-\(index).bin"),
                    allocatedSizeValue: 1,
                    logicalSizeValue: 1,
                    kindName: kindName
                ),
                updateSize: false
            )
        }
        rootBuilder.recalculateSize(usePhysicalSize: true)

        let aggregates: [String: TreemapKindAggregate] = TreemapKindCatalog.aggregates(
            from: rootBuilder.freeze(),
            usePhysicalSize: true,
            folderKindName: "Folder"
        )

        #expect(aggregates["Even Binary"]?.fileCount == itemCount / 2)
        #expect(aggregates["Odd Binary"]?.fileCount == itemCount / 2)
        #expect(aggregates["Even Binary"]?.size == UInt64(itemCount / 2))
        #expect(aggregates["Odd Binary"]?.size == UInt64(itemCount / 2))
    }

    @Test func sizeModeReordersExistingTreeWithoutChangingItsMeasurements() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        rootBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/physical"),
            allocatedSizeValue: 8_192,
            logicalSizeValue: 10
        ))
        rootBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/logical"),
            allocatedSizeValue: 4_096,
            logicalSizeValue: 20_000
        ))
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let physicalRoot: DiskItem = rootBuilder.freeze()

        let logicalRoot: DiskItem = DiskItemTreeEditor.reordered(physicalRoot, usePhysicalSize: false)

        #expect(physicalRoot.child(at: 0).name == "physical")
        #expect(logicalRoot.child(at: 0).name == "logical")
        #expect(logicalRoot.allocatedSizeValue == physicalRoot.allocatedSizeValue)
        #expect(logicalRoot.logicalSizeValue == physicalRoot.logicalSizeValue)
    }

    @Test func presentationMetricsReportMeasuredTraversalProgress() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        rootBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4_096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        ))
        let recorder: TreemapProgressRecorder = TreemapProgressRecorder()

        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: rootBuilder.freeze(),
            usePhysicalSize: true
        ) {
            recorder.record($0)
        }
        let progressValues: [Double] = recorder.values

        #expect(progressValues.first == 0)
        #expect(progressValues.last == 1)
        #expect(zip(progressValues, progressValues.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        #expect(metrics.kindStatistics.first?.kindName == "Plain Text")
    }

    @Test func layoutPlanRetainsFractionalGeometryAndResolvesDeepestHit() {
        let rootItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100,
            isDirectory: true
        )
        let childItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let root: TreemapLayoutEntry = TreemapLayoutEntry(
            item: rootItem,
            itemPath: "/scan",
            parentItem: nil,
            parentPath: nil,
            rect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            unroundedRect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            isSpecialItem: false
        )
        let child: TreemapLayoutEntry = TreemapLayoutEntry(
            item: childItem,
            itemPath: "/scan/child",
            parentItem: rootItem,
            parentPath: "/scan",
            rect: TreemapLayoutRect(x: 20, y: 20, width: 10, height: 10),
            unroundedRect: TreemapLayoutRect(x: 20.25, y: 20.5, width: 9.5, height: 9.25),
            isSpecialItem: false
        )
        let plan: TreemapLayoutPlan = TreemapLayoutPlan(
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            entries: [root, child],
            cushionSnapshots: []
        )

        #expect(plan.entry(forPath: "/scan/child")?.unroundedRect == child.unroundedRect)
        #expect(plan.entry(for: childItem)?.item === childItem)
        #expect(plan.hitEntry(x: 25, y: 25)?.itemPath == "/scan/child")
        #expect(plan.hitEntry(x: 80, y: 80)?.itemPath == "/scan")
    }

    @Test func layoutPlanResolvesDeepestRenderedAncestorForCollapsedDescendant() {
        let rootItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100,
            isDirectory: true
        )
        let collapsedFolder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/tiny"),
            allocatedSizeValue: 1,
            logicalSizeValue: 1,
            isDirectory: true
        )
        let hiddenDescendant: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/tiny/deep/folder"),
            allocatedSizeValue: 1,
            logicalSizeValue: 1,
            isDirectory: true
        )
        let root: TreemapLayoutEntry = TreemapLayoutEntry(
            item: rootItem,
            itemPath: "/scan",
            parentItem: nil,
            parentPath: nil,
            rect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            unroundedRect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            isSpecialItem: false
        )
        let tiny: TreemapLayoutEntry = TreemapLayoutEntry(
            item: collapsedFolder,
            itemPath: "/scan/tiny",
            parentItem: rootItem,
            parentPath: "/scan",
            rect: .zero,
            unroundedRect: TreemapLayoutRect(x: 40.25, y: 80.75, width: 0.2, height: 0.3),
            isSpecialItem: false
        )
        let plan: TreemapLayoutPlan = TreemapLayoutPlan(
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            entries: [root, tiny],
            cushionSnapshots: []
        )

        #expect(plan.entry(for: hiddenDescendant) == nil)
        #expect(plan.deepestRenderedAncestorEntry(containingPath: hiddenDescendant.path)?.item === collapsedFolder)
    }

    @Test func layoutPlanHitTestingFindsLargeEntriesAwayFromTheirCenter() {
        let rootItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100,
            isDirectory: true
        )
        let childItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        )
        let root: TreemapLayoutEntry = TreemapLayoutEntry(
            item: rootItem,
            itemPath: "/scan",
            parentItem: nil,
            parentPath: nil,
            rect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            unroundedRect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            isSpecialItem: false
        )
        let child: TreemapLayoutEntry = TreemapLayoutEntry(
            item: childItem,
            itemPath: "/scan/child",
            parentItem: rootItem,
            parentPath: "/scan",
            rect: TreemapLayoutRect(x: 90, y: 90, width: 5, height: 5),
            unroundedRect: TreemapLayoutRect(x: 90, y: 90, width: 5, height: 5),
            isSpecialItem: false
        )
        let plan: TreemapLayoutPlan = TreemapLayoutPlan(
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            entries: [root, child],
            cushionSnapshots: []
        )

        #expect(plan.hitEntry(x: 95, y: 5)?.itemPath == "/scan")
        #expect(plan.hitEntry(x: 92, y: 92)?.itemPath == "/scan/child")
    }

    @Test func layoutPlanNavigatesBetweenSiblingItemsWithoutRenderers() throws {
        let leftItem: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/left"), allocatedSizeValue: 1, logicalSizeValue: 1)
        let rightItem: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan/right"), allocatedSizeValue: 1, logicalSizeValue: 1)
        let rootItem: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 2,
            logicalSizeValue: 2,
            isDirectory: true,
            children: [leftItem, rightItem]
        )
        let plan: TreemapLayoutPlan = TreemapLayoutPlan(
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            entries: [
                TreemapLayoutEntry(
                    item: rootItem,
                    itemPath: "/scan",
                    parentItem: nil,
                    parentPath: nil,
                    rect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
                    unroundedRect: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
                    isSpecialItem: false
                ),
                TreemapLayoutEntry(
                    item: leftItem,
                    itemPath: "/scan/left",
                    parentItem: rootItem,
                    parentPath: "/scan",
                    rect: TreemapLayoutRect(x: 0, y: 0, width: 50, height: 100),
                    unroundedRect: TreemapLayoutRect(x: 0, y: 0, width: 50, height: 100),
                    isSpecialItem: false
                ),
                TreemapLayoutEntry(
                    item: rightItem,
                    itemPath: "/scan/right",
                    parentItem: rootItem,
                    parentPath: "/scan",
                    rect: TreemapLayoutRect(x: 50, y: 0, width: 50, height: 100),
                    unroundedRect: TreemapLayoutRect(x: 50, y: 0, width: 50, height: 100),
                    isSpecialItem: false
                ),
            ],
            cushionSnapshots: []
        )

        #expect(try #require(plan.nearestEntry(from: leftItem, direction: .right)).item === rightItem)
        #expect(try #require(plan.nearestEntry(from: rightItem, direction: .left)).item === leftItem)
        #expect(plan.nearestEntry(from: leftItem, direction: .left) == nil)
    }

    @Test func layoutPlannerKeepsZeroSizeItemsInThePlanWithoutGivingThemArea() throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100,
            isDirectory: true,
            children: [
                DiskItem(url: URL(fileURLWithPath: "/scan/file"), allocatedSizeValue: 100, logicalSizeValue: 100),
                DiskItem(url: URL(fileURLWithPath: "/scan/empty"), allocatedSizeValue: 0, logicalSizeValue: 0),
            ]
        )

        let plan: TreemapLayoutPlan = TreemapLayoutPlanner.makePlan(
            rootItem: root,
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            usePhysicalSize: true,
            colorTable: TreemapPlanColorTable(
                orderedKinds: [],
                sharesKindColors: false,
                colorScheme: .diskHog
            )
        )

        // Zero-size items are still given a real (zero-area) entry in the plan, findable by
        // item identity - but entries too small to ever be shown skip decoding their own path
        // (a real cost on trees with hundreds of thousands of such entries), so they are no
        // longer indexed by path the way a visible entry is.
        let emptyItem: DiskItem = try #require(root.item(atPath: "/scan/empty"))
        #expect(plan.entry(forPath: "/scan/file")?.rect.area == 10_000)
        #expect(plan.entry(for: emptyItem)?.rect.area == 0)
        #expect(plan.entry(for: emptyItem) != nil)
        #expect(plan.cushionSnapshots.count == 1)
    }

    @Test func renderJobBuildsPlanAndPixelsWithoutRendererObjects() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100,
            isDirectory: true,
            children: [
                DiskItem(url: URL(fileURLWithPath: "/scan/file"), allocatedSizeValue: 100, logicalSizeValue: 100),
            ]
        )
        let freeSpace: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            itemType: .freeSpace,
            allocatedSizeValue: 50,
            logicalSizeValue: 50
        )
        let request: TreemapRenderRequest = TreemapRenderRequest(
            rootItem: root,
            width: 20,
            height: 10,
            scale: 2,
            usePhysicalSize: true,
            orderedKindNames: [],
            sharesKindColors: false,
            colorScheme: .diskHog,
            showsFreeSpace: true,
            showsOtherSpace: false,
            freeSpaceItem: freeSpace,
            otherSpaceItem: nil
        )

        let result: TreemapRenderResult = TreemapRenderJob.render(request)

        #expect(result.plan.entry(for: root) != nil)
        #expect(result.plan.entry(for: freeSpace) != nil)
        #expect(result.plan.cushionSnapshots.count == 2)
        #expect(result.pixels.count == request.pixelsWide * request.pixelsHigh * 3)
    }

    @Test func sharedKindColorsRemainStableAcrossDifferentRankings() {
        let firstTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: ["Plain Text", "Image"],
            sharesKindColors: true
        )
        let secondTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: ["Image", "Plain Text"],
            sharesKindColors: true
        )

        #expect(colorComponents(firstTable.colorForKind("Plain Text")) == colorComponents(secondTable.colorForKind("Plain Text")))
        #expect(colorComponents(firstTable.colorForKind("Image")) == colorComponents(secondTable.colorForKind("Image")))
    }

    @Test func sharedKindColorIndexesAreStableAndBounded() {
        let kindName: String = "Plain Text"

        let firstIndex: Int = SharedKindColorRegistry.colorIndex(for: kindName)
        let laterIndex: Int = SharedKindColorRegistry.colorIndex(for: kindName)

        #expect(firstIndex == laterIndex)
        #expect((0..<TreemapPalettePlan.sharedColorCount).contains(firstIndex))
    }

    @Test func generatedKindColorsRemainDistinctPastCuratedPalette() {
        let generatedColors: [TreemapRawColor] = (30..<90).map { index in
            TreemapPalettePlan.rawColor(at: index)
        }
        let distinctColorKeys: Set<String> = Set(generatedColors.map(colorKey))
        let grayscaleColors: [TreemapRawColor] = generatedColors.filter { color in
            color.red == color.green && color.green == color.blue
        }

        #expect(distinctColorKeys.count == generatedColors.count)
        #expect(grayscaleColors.isEmpty)
    }

    @Test func diskInventoryZColorsUseItsGrayFallbackAfterCuratedPalette() {
        let firstFallback: TreemapRawColor = TreemapPalettePlan.rawColor(
            at: 30,
            colorScheme: .diskInventoryZ
        )
        let laterFallback: TreemapRawColor = TreemapPalettePlan.rawColor(
            at: 60,
            colorScheme: .diskInventoryZ
        )

        #expect(firstFallback.red == 0.9)
        #expect(firstFallback.red == firstFallback.green)
        #expect(firstFallback.green == firstFallback.blue)
        #expect(laterFallback.red == 0.9)
    }

    @Test func sharedKindColorRegistryCanUseGeneratedPaletteSlots() {
        let sampledIndexes: Set<Int> = Set((0..<1_000).map { index in
            SharedKindColorRegistry.colorIndex(for: "Kind \(index)")
        })

        #expect(sampledIndexes.contains { $0 >= 30 })
    }

    @Test func independentKindColorsFollowEachWindowsRanking() {
        let firstTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: ["Plain Text", "Image"]
        )
        let secondTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: ["Image", "Plain Text"]
        )

        #expect(colorComponents(firstTable.colorForKind("Plain Text")) != colorComponents(secondTable.colorForKind("Plain Text")))
    }

    @Test func layoutPlannerIncludesVisibleVolumeSpaceItemsInRootAreaAllocation() throws {
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.dat"),
            allocatedSizeValue: 40,
            logicalSizeValue: 40,
            isRoot: false
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 40,
            logicalSizeValue: 40,
            isDirectory: true,
            children: [file]
        )
        let freeSpace: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            itemType: .freeSpace,
            allocatedSizeValue: 50,
            logicalSizeValue: 50
        )
        let otherSpace: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            itemType: .otherSpace,
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        )

        let plan: TreemapLayoutPlan = TreemapLayoutPlanner.makePlan(
            rootItem: root,
            bounds: TreemapLayoutRect(x: 0, y: 0, width: 100, height: 100),
            usePhysicalSize: true,
            colorTable: TreemapPlanColorTable(
                orderedKinds: [],
                sharesKindColors: false,
                colorScheme: .diskHog
            ),
            showsFreeSpace: true,
            showsOtherSpace: true,
            freeSpaceItem: freeSpace,
            otherSpaceItem: otherSpace
        )

        // Root weight (100 total: 40 file + 50 free + 10 other) is fully allocated
        // across its three children's areas on a 100x100 (10,000-area) bounds - free
        // and other space are included in the root's weight, not just appended as
        // zero-area decoration.
        // `file` is looked up via root's own copy (nesting it into `children:` at
        // construction copies it into root's packed snapshot under a new identity),
        // matching the pattern used elsewhere in this file for the same reason.
        let fileEntry: TreemapLayoutEntry = try #require(plan.entry(for: root.children[0]))
        let freeSpaceEntry: TreemapLayoutEntry = try #require(plan.entry(for: freeSpace))
        let otherSpaceEntry: TreemapLayoutEntry = try #require(plan.entry(for: otherSpace))
        #expect(fileEntry.rect.area == 4_000)
        #expect(freeSpaceEntry.rect.area == 5_000)
        #expect(otherSpaceEntry.rect.area == 1_000)
    }

    private func colorComponents(_ color: NSColor) -> [CGFloat] {
        guard let rgbColor: NSColor = color.usingColorSpace(.genericRGB) else {
            return []
        }
        return [
            rgbColor.redComponent,
            rgbColor.greenComponent,
            rgbColor.blueComponent,
            rgbColor.alphaComponent
        ]
    }

    private func colorKey(_ color: TreemapRawColor) -> String {
        [
            color.red,
            color.green,
            color.blue,
            color.alpha
        ]
            .map { String(format: "%.6f", $0) }
            .joined(separator: ",")
    }
}

private final class TreemapProgressRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var storedValues: [Double] = []

    var values: [Double] {
        lock.withLock { storedValues }
    }

    func record(_ progress: Double) {
        lock.withLock {
            storedValues.append(progress)
        }
    }
}

@MainActor
struct TreemapSelectionRectTests {

    @Test func wholeTreemapSelectionRectMatchesTheSelectedItem() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 0, y: 0, width: 200, height: 100),
            in: NSRect(x: 0, y: 0, width: 200, height: 100)
        )

        #expect(visibleRect == NSRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func smallSelectionRectDoesNotExpandIntoNeighboringTiles() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 476, y: 129, width: 5, height: 13),
            in: NSRect(x: 0, y: 0, width: 536, height: 368)
        )

        #expect(visibleRect == NSRect(x: 476, y: 129, width: 5, height: 13))
    }

    @Test func selectionRectFullyOutsideTheTreemapIsZeroRatherThanNull() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 600, y: 400, width: 5, height: 13),
            in: NSRect(x: 0, y: 0, width: 536, height: 368)
        )

        #expect(visibleRect == .zero)
        #expect(visibleRect.isNull == false)
    }
}

@MainActor
struct TreemapViewStateTests {

    @Test func externalFileListSelectionResolvesToTheRenderedTreemapItem() throws {
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/file.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let folder: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [file]
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [folder]
        )
        let selectedFile: DiskItem = root.children[0].children[0]
        let state: TreemapViewState = TreemapViewState()

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: selectedFile
        )
        state.prepareLayout(in: NSRect(x: 0, y: 0, width: 536, height: 368))

        let entry: TreemapLayoutEntry = try #require(state.selectedEntry())
        #expect(entry.item.path == "/scan/folder/file.txt")
        #expect(entry.rect.isEmpty == false)
    }

    @Test func selectionOutsideTheZoomedTreemapClearsTheRenderedSelection() throws {
        let visibleFile: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder/visible.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let zoomRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true,
            children: [visibleFile]
        )
        let outsideSelection: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/elsewhere.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let state: TreemapViewState = TreemapViewState()

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: zoomRoot,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: outsideSelection
        )
        state.prepareLayout(in: NSRect(x: 0, y: 0, width: 536, height: 368))

        #expect(state.selectedEntry() == nil)
    }

    @Test func oppositeArrowMovesBacktrackAcrossMultipleSteps() throws {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        for (name, size) in [("large.bin", 600), ("medium.bin", 300), ("small.bin", 100)] {
            rootBuilder.appendChild(DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/\(name)"),
                allocatedSizeValue: UInt64(size),
                logicalSizeValue: UInt64(size)
            ), updateSize: false)
        }
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()
        let originalItem: DiskItem = root.children[0]
        let state: TreemapViewState = TreemapViewState()

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: originalItem
        )
        // A wide, short bounds strongly favors a single horizontal row regardless of the
        // exact weight split (splitting into multiple rows would only worsen the aspect
        // ratio), so all three siblings land side by side left-to-right - the layout this
        // test needs to exercise two genuine, unambiguous rightward hops.
        state.prepareLayout(in: NSRect(x: 0, y: 0, width: 300, height: 60))

        let firstForwardItem: DiskItem = try #require(state.selectNeighbor(in: .right))
        let secondForwardItem: DiskItem = try #require(state.selectNeighbor(in: .right))
        let firstRestoredItem: DiskItem = try #require(state.selectNeighbor(in: .left))
        let secondRestoredItem: DiskItem = try #require(state.selectNeighbor(in: .left))

        #expect(secondForwardItem !== firstForwardItem)
        #expect(firstRestoredItem === firstForwardItem)
        #expect(secondRestoredItem === originalItem)
        #expect(state.selectedItem === originalItem)
    }

    @Test func largeSiblingGroupUsesIndexedDirectionalNavigation() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        for index: Int in 0..<300 {
            rootBuilder.appendChild(DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/file-\(index)"),
                allocatedSizeValue: 1,
                logicalSizeValue: 1
            ), updateSize: false)
        }
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()
        let state: TreemapViewState = TreemapViewState()

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: root.children[0]
        )
        state.prepareLayout(in: NSRect(x: 0, y: 0, width: 600, height: 400))

        #expect(state.selectNeighbor(in: .right) != nil)
    }

    @Test func supersededRenderJobIsCancelled() throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/file.bin"),
                    allocatedSizeValue: 100,
                    logicalSizeValue: 100
                )
            ]
        )
        let firstRenderStarted: DispatchSemaphore = DispatchSemaphore(value: 0)
        let firstRenderCancelled: DispatchSemaphore = DispatchSemaphore(value: 0)
        let render: @Sendable (TreemapRenderRequest, @escaping @Sendable (Double) -> Void) -> TreemapRenderResult? = { request, _ in
            if request.width == 100 {
                firstRenderStarted.signal()
                while Task.isCancelled == false {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                firstRenderCancelled.signal()
                return nil
            }
            return TreemapRenderJob.render(request)
        }
        let state: TreemapViewState = TreemapViewState(render: render)

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: nil
        )

        #expect(state.renderedImage(in: NSRect(x: 0, y: 0, width: 100, height: 100), scale: 1) == nil)
        #expect(firstRenderStarted.wait(timeout: .now() + 1) == .success)
        #expect(state.renderedImage(in: NSRect(x: 0, y: 0, width: 101, height: 100), scale: 1) == nil)
        #expect(firstRenderCancelled.wait(timeout: .now() + 1) == .success)
    }

    @Test func renderJobWithoutResultClearsPendingRequestSoTheViewCanRetry() async throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/file.bin"),
                    allocatedSizeValue: 100,
                    logicalSizeValue: 100
                )
            ]
        )
        let renderAttemptCount: LockedCounter = LockedCounter()
        let render: @Sendable (TreemapRenderRequest, @escaping @Sendable (Double) -> Void) -> TreemapRenderResult? = { request, _ in
            renderAttemptCount.increment()
            if renderAttemptCount.value == 1 {
                return nil
            }
            return TreemapRenderJob.render(request)
        }
        let state: TreemapViewState = TreemapViewState(render: render)

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: nil
        )

        let bounds: NSRect = NSRect(x: 0, y: 0, width: 100, height: 100)
        #expect(state.renderedImage(in: bounds, scale: 1) == nil)
        try await Self.waitUntil { renderAttemptCount.value >= 1 }

        var renderedImage: NSBitmapImageRep?
        for _ in 0..<100 {
            renderedImage = state.renderedImage(in: bounds, scale: 1)
            if renderedImage != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(renderAttemptCount.value >= 2)
        #expect(renderedImage != nil)
    }

    @Test func previousTreemapBitmapRemainsVisibleWhileNewRootRenders() async throws {
        let firstRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/first"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/first/file.bin"),
                    allocatedSizeValue: 100,
                    logicalSizeValue: 100
                )
            ]
        )
        let secondRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/second"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/second/file.bin"),
                    allocatedSizeValue: 100,
                    logicalSizeValue: 100
                )
            ]
        )
        let secondRenderStartCount: LockedCounter = LockedCounter()
        let render: @Sendable (TreemapRenderRequest, @escaping @Sendable (Double) -> Void) -> TreemapRenderResult? = { request, _ in
            if request.rootItem === secondRoot {
                secondRenderStartCount.increment()
                Thread.sleep(forTimeInterval: 0.05)
                return nil
            }
            return TreemapRenderJob.render(request)
        }
        let state: TreemapViewState = TreemapViewState(render: render)
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 100, height: 100)

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: firstRoot,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: nil
        )

        #expect(state.renderedImage(in: bounds, scale: 1) == nil)
        var firstBitmap: NSBitmapImageRep?
        for _ in 0..<100 {
            firstBitmap = state.renderedImage(in: bounds, scale: 1)
            if firstBitmap != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let visibleBitmap: NSBitmapImageRep = try #require(firstBitmap)

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: secondRoot,
            presentationMetrics: nil,
            showsFreeSpace: false,
            showsOtherSpace: false,
            freeSpaceItem: nil,
            otherSpaceItem: nil,
            selectedItem: nil
        )

        #expect(state.renderedImage(in: bounds, scale: 1) === visibleBitmap)
        try await Self.waitUntil { secondRenderStartCount.value >= 1 }
    }

    @Test func zoomingBackToAPreviouslyRenderedLevelReusesTheCache() async throws {
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let root: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan"), isDirectory: true, children: [child])
        let rootRenderCount: LockedCounter = LockedCounter()
        let render: @Sendable (TreemapRenderRequest, @escaping @Sendable (Double) -> Void) -> TreemapRenderResult? = { request, _ in
            if request.rootItem == root {
                rootRenderCount.increment()
            }
            return TreemapRenderJob.renderIfNotCancelled(request)
        }
        let state: TreemapViewState = TreemapViewState(render: render)
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root,
            usePhysicalSize: true,
            sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(rootRenderCount.value == 1)

        // Zoom into child, then immediately back out to root - the same
        // presentationMetrics instance throughout, so this is ordinary navigation
        // within the same snapshot, not a rescan.
        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: child, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        #expect(state.renderedImage(in: bounds, scale: 1) != nil)
        #expect(rootRenderCount.value == 1) // still 1 - served from resultCache, not re-rendered
    }

    @Test func rescanStillClearsTheRenderCache() async throws {
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let root: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan"), isDirectory: true, children: [child])
        // A rescan always produces a genuinely new DiskItem/snapshot for the same
        // path, never the literal same object - a fresh instance here (rather than
        // reusing `root`) matches that.
        let refreshedRoot: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan"), isDirectory: true, children: [child])
        let rootRenderCount: LockedCounter = LockedCounter()
        let render: @Sendable (TreemapRenderRequest, @escaping @Sendable (Double) -> Void) -> TreemapRenderResult? = { request, _ in
            if request.rootItem.path == "/scan" {
                rootRenderCount.increment()
            }
            return TreemapRenderJob.renderIfNotCancelled(request)
        }
        let state: TreemapViewState = TreemapViewState(render: render)
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let firstMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )
        let secondMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: refreshedRoot, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: firstMetrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(rootRenderCount.value == 1)

        // A different TreemapPresentationMetrics instance (paired with a fresh
        // DiskItem for the same path) signals a genuine rescan.
        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: refreshedRoot, presentationMetrics: secondMetrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        // `renderedImage` deliberately keeps returning the old (root's) bitmap as a
        // "stale root" fallback while refreshedRoot's own render is still pending
        // (same width/height, so that fallback applies) - a plain non-nil check
        // would pass immediately, before refreshedRoot's own render - and the
        // second render count - actually happens. `isShowingStaleRoot` becoming
        // false is the real completion signal.
        for _ in 0..<100 {
            _ = state.renderedImage(in: bounds, scale: 1)
            if state.isShowingStaleRoot == false { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(rootRenderCount.value == 2) // re-rendered - the cache was correctly cleared
    }

    @Test func zoomInDetectsATransitionAnchoredAtTheChildsRectInTheOldPlan() async throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/child"),
                    isDirectory: true,
                    children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
                )
            ]
        )
        // DiskItem(url:children:) re-packs each child into the parent's own new
        // snapshot, so the child actually present within `root`'s tree - the one any
        // lookup or zoom target must use - is `root.children[0]`, not a standalone
        // reference to whatever was passed into that initializer.
        let childInRoot: DiskItem = root.children[0]
        let state: TreemapViewState = TreemapViewState(render: { request, _ in TreemapRenderJob.renderIfNotCancelled(request) })
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let rootEntryForChild: TreemapLayoutEntry = try #require(state.entry(for: childInRoot))

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: childInRoot, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        let transition: TreemapZoomTransition = try #require(state.pendingZoomTransition)
        #expect(transition.direction == .zoomIn)
        #expect(transition.anchorRect == rootEntryForChild.navigationRect.nsRect)
    }

    @Test func zoomOutReusesTheCachedParentAndProducesAnAnchoredTransition() async throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [
                DiskItem(
                    url: URL(fileURLWithPath: "/scan/child"),
                    isDirectory: true,
                    children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
                )
            ]
        )
        let childInRoot: DiskItem = root.children[0]
        let state: TreemapViewState = TreemapViewState(render: { request, _ in TreemapRenderJob.renderIfNotCancelled(request) })
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let rootEntryForChild: TreemapLayoutEntry = try #require(state.entry(for: childInRoot))

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: childInRoot, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        // Same bounds as root's render, so `renderedImage` would otherwise return
        // root's still-stale bitmap as a fallback before childInRoot's own render
        // (and its plan/bitmap installation) actually completes.
        for _ in 0..<100 {
            _ = state.renderedImage(in: bounds, scale: 1)
            if state.isShowingStaleRoot == false { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        let transition: TreemapZoomTransition = try #require(state.pendingZoomTransition)
        #expect(transition.direction == .zoomOut)
        #expect(transition.toBitmap != nil)
        #expect(transition.anchorRect == rootEntryForChild.navigationRect.nsRect)
    }

    @Test func zoomOutDefersWhenTheParentIsNotCachedAtTheCurrentBounds() async throws {
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let root: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan"), isDirectory: true, children: [child])
        let state: TreemapViewState = TreemapViewState(render: { request, _ in TreemapRenderJob.renderIfNotCancelled(request) })
        let smallBounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let largeBounds: NSRect = NSRect(x: 0, y: 0, width: 300, height: 300)
        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            // root is only ever cached at smallBounds.
            if state.renderedImage(in: smallBounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: child, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            // child completes at a different bounds, so the reconstructed
            // "prospective" root request below won't match root's cached entry.
            if state.renderedImage(in: largeBounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        let transition: TreemapZoomTransition = try #require(state.pendingZoomTransition)
        #expect(transition.direction == .zoomOut)
        #expect(transition.toBitmap == nil)
        #expect(transition.pendingAnchorItem == child)
    }

    @Test func divergentRootJumpProducesNoTransition() async throws {
        let child: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/child"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/child/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let root: DiskItem = DiskItem(url: URL(fileURLWithPath: "/scan"), isDirectory: true, children: [child])
        let unrelatedRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/elsewhere"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/elsewhere/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let state: TreemapViewState = TreemapViewState(render: { request, _ in TreemapRenderJob.renderIfNotCancelled(request) })
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        _ = state.configure(
            source: ScanSource(path: "/elsewhere", displayName: "elsewhere"),
            rootItem: unrelatedRoot, presentationMetrics: metrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        #expect(state.pendingZoomTransition == nil)
    }

    @Test func rescanNeverProducesATransitionEvenWhenRootItemChanges() async throws {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/file.bin"), allocatedSizeValue: 100, logicalSizeValue: 100)]
        )
        let refreshedRoot: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true,
            children: [DiskItem(url: URL(fileURLWithPath: "/scan/file.bin"), allocatedSizeValue: 200, logicalSizeValue: 200)]
        )
        let state: TreemapViewState = TreemapViewState(render: { request, _ in TreemapRenderJob.renderIfNotCancelled(request) })
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let firstMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: root, usePhysicalSize: true, sharesKindColors: false
        )
        let secondMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: refreshedRoot, usePhysicalSize: true, sharesKindColors: false
        )

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: root, presentationMetrics: firstMetrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )
        for _ in 0..<100 {
            if state.renderedImage(in: bounds, scale: 1) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        _ = state.configure(
            source: ScanSource(path: "/scan", displayName: "scan"),
            rootItem: refreshedRoot, presentationMetrics: secondMetrics,
            showsFreeSpace: false, showsOtherSpace: false,
            freeSpaceItem: nil, otherSpaceItem: nil, selectedItem: nil
        )

        #expect(state.pendingZoomTransition == nil)
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let attempts: Int = Int(timeoutNanoseconds / 10_000_000)
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }
}

struct TreemapRasterGeometryTests {

    @Test func subpixelSelectionGetsAPixelAlignedVisibleMarker() {
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 536, height: 368)
        let pixelRect: NSRect = TreemapRasterGeometry.pixelAlignedRect(
            for: NSRect(x: 532.182, y: 367.842, width: 0.764, height: 0.158),
            scale: 1
        )
        let marker: NSRect = TreemapRasterGeometry.visibleMarkerRect(
            for: pixelRect,
            in: bounds,
            scale: 1
        )

        #expect(pixelRect == NSRect(x: 532, y: 367, width: 1, height: 1))
        #expect(marker == NSRect(x: 531, y: 365, width: 3, height: 3))
        #expect(bounds.contains(marker))
    }

    @Test func visibleMarkerClampsAtTheTreemapEdge() {
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        let marker: NSRect = TreemapRasterGeometry.visibleMarkerRect(
            for: NSRect(x: 9, y: 9, width: 1, height: 1),
            in: bounds,
            scale: 2
        )

        #expect(marker == NSRect(x: 8.5, y: 8.5, width: 1.5, height: 1.5))
        #expect(bounds.contains(marker))
    }

    @Test func discoveryRectangleRemainsInsideSmallTreemapBounds() {
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 100, height: 70)
        let discoveryRect: NSRect = TreemapRasterGeometry.discoveryRect(
            around: NSRect(x: 95, y: 65, width: 1, height: 1),
            in: bounds
        )

        #expect(discoveryRect == NSRect(x: 30, y: 0, width: 70, height: 70))
        #expect(bounds.contains(discoveryRect))
    }
}

@MainActor
struct TreemapCushionRendererTests {

    @Test func cushionByteConversionClampsOutOfRangeComponents() {
        // Overflow redistribution has an internal normalized-input invariant.
        // Byte conversion is the independent final safety boundary and must be
        // safe even if an upstream caller violates that invariant.
        #expect(TreemapColorNormalization.byte(from: 5.0) == 255)
        #expect(TreemapColorNormalization.byte(from: -1.0) == 0)
        #expect(TreemapColorNormalization.byte(from: Double.nan) == 0)
    }

    @Test func backgroundRasterizerMatchesTheLegacyCushionPixels() throws {
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        let bitmap: NSBitmapImageRep = try #require(NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: bounds,
            backingScaleFactor: 1,
            colorSpace: .genericRGB
        ))
        let renderer: TreemapCushionRenderer = TreemapCushionRenderer(rect: bounds)
        renderer.setColor(NSColor(calibratedRed: 1, green: 0.8, blue: 0.2, alpha: 1))
        renderer.setSurface([0, 0, 0, 0])
        renderer.renderCushion(in: bitmap)
        let bitmapData: UnsafeMutablePointer<UInt8> = try #require(bitmap.bitmapData)
        let rowPixelByteCount: Int = bitmap.pixelsWide * 3
        var legacyPixels: Data = Data(capacity: rowPixelByteCount * bitmap.pixelsHigh)
        for row: Int in 0..<bitmap.pixelsHigh {
            legacyPixels.append(Data(
                bytes: bitmapData + row * bitmap.bytesPerRow,
                count: rowPixelByteCount
            ))
        }

        let backgroundPixels: Data = TreemapBitmapRasterizer.render(
            snapshots: [TreemapCushionSnapshot(
                x: 0,
                y: 0,
                width: 10,
                height: 10,
                surface: [0, 0, 0, 0],
                red: 1,
                green: 0.8,
                blue: 0.2
            )],
            pixelsWide: 10,
            pixelsHigh: 10,
            scale: 1
        )

        #expect(backgroundPixels == legacyPixels)
    }

    @Test func fillsTheFullPixelAreaOfARetinaBitmap() throws {
        let bitmap: NSBitmapImageRep = try #require(NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: NSRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 2,
            colorSpace: .genericRGB
        ))
        let renderer: TreemapCushionRenderer = TreemapCushionRenderer(
            rect: NSRect(x: 0, y: 0, width: 100, height: 100)
        )
        renderer.setColor(NSColor.red)
        renderer.renderCushion(in: bitmap, backingScaleFactor: 2)

        let bytes: UnsafeMutablePointer<UInt8> = try #require(bitmap.bitmapData)
        let pixelOutsidePointSpace: UnsafeMutablePointer<UInt8> = bytes + 150 * bitmap.bytesPerRow + 150 * 3
        #expect(pixelOutsidePointSpace[0] > 0)
    }

    @Test func clampsExpandedFractionalPointRectsToBitmapBounds() throws {
        let fractionalBounds: NSRect = NSRect(x: 0, y: 0, width: 100.5, height: 100.5)
        let bitmap: NSBitmapImageRep = try #require(NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: fractionalBounds,
            backingScaleFactor: 2,
            colorSpace: .genericRGB
        ))
        let renderer: TreemapCushionRenderer = TreemapCushionRenderer(
            rect: NSIntegralRect(fractionalBounds)
        )
        renderer.setColor(NSColor.red)

        #expect(bitmap.pixelsWide == 201)
        #expect(bitmap.pixelsHigh == 201)

        renderer.renderCushion(in: bitmap, backingScaleFactor: 2)

        let bytes: UnsafeMutablePointer<UInt8> = try #require(bitmap.bitmapData)
        let lastPixel: UnsafeMutablePointer<UInt8> = bytes
            + (bitmap.pixelsHigh - 1) * bitmap.bytesPerRow
            + (bitmap.pixelsWide - 1) * 3
        #expect(lastPixel[0] > 0)
    }

    @Test func rejectsInvalidBitmapScaleWithoutRendering() {
        let bitmap: NSBitmapImageRep? = NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: NSRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 0,
            colorSpace: .genericRGB
        )

        #expect(bitmap == nil)
    }

    @Test func colorNormalizationRedistributesOverflowAcrossRemainingChannels() {
        var red: CGFloat = 1.4
        var green: CGFloat = 0.8
        var blue: CGFloat = 0.2

        TreemapCushionRenderer.normalizeColorRed(&red, green: &green, blue: &blue)

        #expect(Self.isNearlyEqual(red, 1.0))
        #expect(Self.isNearlyEqual(green, 1.0))
        #expect(Self.isNearlyEqual(blue, 0.4))
    }

    @Test func normalizeColorBalancesBrightnessAndPreservesAlpha() {
        let normalizedColor: NSColor = TreemapCushionRenderer.normalizeColor(
            NSColor(calibratedRed: 0, green: 0, blue: 0.9, alpha: 0.25)
        )

        #expect(Self.isNearlyEqual(normalizedColor.redComponent, 0.4))
        #expect(Self.isNearlyEqual(normalizedColor.greenComponent, 0.4))
        #expect(Self.isNearlyEqual(normalizedColor.blueComponent, 1.0))
        #expect(Self.isNearlyEqual(normalizedColor.alphaComponent, 0.25))
    }

    private static func isNearlyEqual(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < 0.0001
    }
}

struct ScanResourceBudgetTests {
    @Test func acquireTraversalPermitThrowsImmediatelyWhenAlreadyCancelled() async throws {
        let budget: ScanResourceBudget = ScanResourceBudget(maximumConcurrentFilesystemTraversals: 1)

        withUnsafeCurrentTask { $0?.cancel() }

        await #expect(throws: CancellationError.self) {
            try await budget.acquireTraversalPermit()
        }
    }

    @Test func acquireTraversalPermitThrowsWhenCancelledWhileWaitingForAFreeSlot() async throws {
        let budget: ScanResourceBudget = ScanResourceBudget(maximumConcurrentFilesystemTraversals: 1)
        let firstPermit: ScanResourcePermit = try await budget.acquireTraversalPermit()

        let waitingTask: Task<ScanResourcePermit, Error> = Task {
            try await budget.acquireTraversalPermit()
        }
        // Give the waiting task a moment to actually reach the point of waiting for a
        // free slot (there's only one, already held by firstPermit) before cancelling it.
        try await Task.sleep(nanoseconds: 50_000_000)
        waitingTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await waitingTask.value
        }

        // Cancelling a waiter must not corrupt the slot bookkeeping - releasing the
        // held permit should still let a fresh acquire succeed normally afterward.
        await firstPermit.release()
        _ = try await budget.acquireTraversalPermit()
    }
}

struct DiskInventoryZScannerTests {

    @Test(
        "Localizes common fallback kind names",
        arguments: ["Document", "text", "folder", "symbolic link", "data", "Unix executable"]
    )
    func localizesCommonFallbackKindNames(_ kindName: String) {
        #expect(DiskItemBuilderFactory.localizedFallbackKindName(kindName) == kindName)
    }

    @Test func itemFactorySafelySharesItsKindCacheAcrossTasks() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-factory-cache-\(UUID().uuidString)", isDirectory: true)
        let fileURL: URL = rootURL.appendingPathComponent("sample.txt")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "sample".write(to: fileURL, atomically: true, encoding: .utf8)

        let factory: DiskItemBuilderFactory = DiskItemBuilderFactory()
        let kindNames: [String?] = await withTaskGroup(of: String?.self, returning: [String?].self) { taskGroup in
            for _ in 0..<32 {
                taskGroup.addTask {
                    factory.makeItem(url: fileURL, values: nil).kindName
                }
            }

            var collectedKindNames: [String?] = []
            for await kindName: String? in taskGroup {
                collectedKindNames.append(kindName)
            }
            return collectedKindNames
        }

        #expect(kindNames.allSatisfy { $0 == kindNames.first })
        #expect(kindNames.first != nil)
    }

    @Test func concurrentScansKeepHardlinkDedupStateIsolated() async throws {
        let firstRootURL: URL = try Self.makeHardlinkFixture(named: "first")
        let secondRootURL: URL = try Self.makeHardlinkFixture(named: "second")
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }

        async let firstScan: DiskScanOutcome = DiskInventoryZScanner().scan(
            source: ScanSource(path: firstRootURL.path, displayName: firstRootURL.lastPathComponent)
        )
        async let secondScan: DiskScanOutcome = DiskInventoryZScanner().scan(
            source: ScanSource(path: secondRootURL.path, displayName: secondRootURL.lastPathComponent)
        )

        let firstRoot: DiskItem = try await firstScan.item
        let secondRoot: DiskItem = try await secondScan.item

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
        ).item

        #expect(Self.hardlinkDuplicateCount(in: root) == 1)
    }

    @Test func simultaneousScansShareTheGlobalTraversalBudget() async throws {
        let firstRootURL: URL = try Self.makeManyTopLevelDirectoryFixture(named: "first", directoryCount: 12)
        let secondRootURL: URL = try Self.makeManyTopLevelDirectoryFixture(named: "second", directoryCount: 12)
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }

        let resourceBudget: ScanResourceBudget = ScanResourceBudget(maximumConcurrentFilesystemTraversals: 2)
        let resourceReadTracker: ConcurrentResourceReadTracker = ConcurrentResourceReadTracker()
        let provider: DiskInventoryZScanner.ResourceValuesProvider = { url, keys in
            if url.lastPathComponent == "payload.dat" {
                resourceReadTracker.enter()
                Thread.sleep(forTimeInterval: 0.01)
                resourceReadTracker.leave()
            }

            return try url.resourceValues(forKeys: keys)
        }
        let firstScanner: DiskInventoryZScanner = DiskInventoryZScanner(
            recursiveResourceValuesProvider: provider,
            resourceBudget: resourceBudget
        )
        let secondScanner: DiskInventoryZScanner = DiskInventoryZScanner(
            recursiveResourceValuesProvider: provider,
            resourceBudget: resourceBudget
        )

        async let firstScan: DiskScanOutcome = firstScanner.scan(
            source: ScanSource(path: firstRootURL.path, displayName: firstRootURL.lastPathComponent)
        )
        async let secondScan: DiskScanOutcome = secondScanner.scan(
            source: ScanSource(path: secondRootURL.path, displayName: secondRootURL.lastPathComponent)
        )

        _ = try await (firstScan, secondScan)

        #expect(resourceReadTracker.maximumActiveCount <= 2)
        #expect(resourceReadTracker.totalEntryCount == 24)
    }

    @Test func topLevelScanProcessesEveryItemEvenFarBeyondTheTraversalBudget() async throws {
        // Top-level tasks are submitted in a budget-sized window and refilled as each
        // one completes (rather than all at once) - this exercises that refill loop
        // with far more items than the budget, to confirm it walks every item instead
        // of silently stopping after the initial batch.
        let rootURL: URL = try Self.makeManyTopLevelDirectoryFixture(named: "refill", directoryCount: 20)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let resourceBudget: ScanResourceBudget = ScanResourceBudget(maximumConcurrentFilesystemTraversals: 2)
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner(resourceBudget: resourceBudget)

        let root: DiskItem = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        ).item

        #expect(root.children.count == 20)
        #expect(Set(root.children.map(\.name)).count == 20)
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

    @Test func scanReportsItsMajorWorkStages() async throws {
        let rootURL: URL = try Self.makeCrossTopLevelHardlinkFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let stageRecorder: ScanStageRecorder = ScanStageRecorder()

        _ = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            stageHandler: { stage in
                await stageRecorder.record(stage)
            }
        )

        let stages: [DiskScanStage] = await stageRecorder.stages
        #expect(stages.first == .enumeratingRootItems)
        #expect(stages.dropFirst().first == .scanningFiles)
        let percentages: [Int] = stages.compactMap {
            if case .packagingScanResults(let percent) = $0 { return percent }
            return nil
        }
        #expect(percentages.last == 100)
        #expect(zip(percentages, percentages.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(stages.last == .finalizingScan)
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

        let scanTask: Task<DiskScanOutcome, Error> = Task {
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
        let outcome: DiskScanOutcome = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )
        let root: DiskItem = outcome.item
        let folder: DiskItem? = root.children.first { $0.name == "folder" }

        #expect(folder != nil)
        #expect(folder?.children.map(\.name) == ["readable.txt"])
        #expect(outcome.skippedItems.map(\.path) == [
            canonicalPath(rootURL.appendingPathComponent("folder/vanished.dat"))
        ])
        #expect(outcome.skippedItems.first?.reason.isEmpty == false)
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
        let outcome: DiskScanOutcome = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )
        let root: DiskItem = outcome.item

        #expect(root.children.map(\.name) == ["readable.txt"])
        #expect(outcome.skippedItems.map(\.path) == [
            canonicalPath(rootURL.appendingPathComponent("vanished.dat"))
        ])
        #expect(outcome.skippedItems.first?.reason.isEmpty == false)
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
                lookInsidePackages: false
            )
        ).item

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
                lookInsidePackages: false
            )
        ).item
        let package: DiskItem? = root.children.first { $0.name == "Example.app" }

        #expect(package != nil)
        #expect(package?.logicalSizeValue == 17)
        #expect(package?.allocatedSizeValue != package?.logicalSizeValue)
    }

    @Test func opaquePackageSizingCanBeSubstitutedForSingleItemScans() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-package-sizer-substitution-\(UUID().uuidString)", isDirectory: true)
        let packageURL: URL = rootURL.appendingPathComponent("Example.app", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let packageSizer: FixedOpaquePackageSizer = FixedOpaquePackageSizer(
            size: OpaquePackageSize(allocated: 123_456, logical: 654_321)
        )
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
            packageSizer: packageSizer
        )

        let package: DiskItem = try await scanner.scanItem(
            at: packageURL,
            from: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            settings: DiskScanSettings(
                usePhysicalSize: true,
                lookInsidePackages: false
            )
        ).item

        #expect(package.allocatedSizeValue == 123_456)
        #expect(package.logicalSizeValue == 654_321)
        #expect(packageSizer.sizedURLs == [packageURL])
    }

    @Test func itemBuilderCanBeSubstitutedForKindNaming() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-item-factory-substitution-\(UUID().uuidString)", isDirectory: true)
        let itemURL: URL = rootURL.appendingPathComponent("unknown.custom")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 8).write(to: itemURL)
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
            itemFactory: FixedKindItemFactory(kindName: "Injected Kind")
        )

        let item: DiskItem = try await scanner.scanItem(
            at: itemURL,
            from: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        ).item

        #expect(item.kindName == "Injected Kind")
    }

    @Test func hardlinkDeduplicatorCanBeSubstituted() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-hardlink-dedup-substitution-\(UUID().uuidString)", isDirectory: true)
        let itemURL: URL = rootURL.appendingPathComponent("duplicate.dat")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 8).write(to: itemURL)
        let hardlinkDeduplicator: AlwaysDuplicateHardlinkDeduplicator = AlwaysDuplicateHardlinkDeduplicator()
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
            hardlinkDeduplicator: hardlinkDeduplicator
        )

        let item: DiskItem = try await scanner.scanItem(
            at: itemURL,
            from: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        ).item

        #expect(item.isHardlinkDuplicate)
        #expect(item.allocatedSizeValue == 0)
        #expect(item.logicalSizeValue == 0)
        #expect(hardlinkDeduplicator.didReset)
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

    private static func makeManyTopLevelDirectoryFixture(
        named name: String,
        directoryCount: Int
    ) throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-budget-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for index: Int in 0..<directoryCount {
            let folderURL: URL = rootURL.appendingPathComponent(
                String(format: "folder-%02d", index),
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try Data(repeating: UInt8(index), count: 8).write(
                to: folderURL.appendingPathComponent("payload.dat")
            )
        }
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

struct DiskInventoryZScanSessionTreeWorkerTests {
    @Test func deletePermanentlyReconcilesTreeEvenWhenCancelledImmediatelyAfterFileRemoval() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-delete-cancel-race-\(UUID().uuidString)", isDirectory: true)
        let fileURL: URL = rootURL.appendingPathComponent("doomed.txt")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("doomed".utf8).write(to: fileURL)

        // The scanner's directory enumeration canonicalizes descendant paths (e.g.
        // resolving /var to /private/var), so the root must be constructed from an
        // already-canonical path too - otherwise DiskItem.item(atPath:)'s prefix
        // check between root and descendant paths would never match.
        let source: ScanSource = ScanSource(path: canonicalPath(rootURL), displayName: rootURL.lastPathComponent)
        let settings: DiskScanSettings = .diskInventoryZDefault
        let currentRoot: DiskItem = try await DiskInventoryZScanner().scan(source: source, settings: settings).item
        let fileItem: DiskItem = try #require(currentRoot.item(atPath: canonicalPath(fileURL)))

        // The mutation is irreversible, so a cancellation landing right after it -
        // simulated here by cancelling from inside the deletion closure itself -
        // must not stop the tree from being reconciled to match the now-deleted file.
        let worker: DiskInventoryZScanSessionTreeWorker = DiskInventoryZScanSessionTreeWorker(
            performDeletion: { url, deletionMethod in
                try FileManager.default.removeItem(at: url)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        )

        let result: ScanSessionTreeUpdateResult = try await worker.delete(
            item: fileItem,
            deletionMethod: .deletePermanently,
            currentRoot: currentRoot,
            source: source,
            settings: settings
        )

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        #expect(result.rootItem.item(atPath: canonicalPath(fileURL)) == nil)
    }

    @Test func deleteThrowsWithoutTouchingTheFileWhenAlreadyCancelled() async throws {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-delete-precancelled-\(UUID().uuidString)", isDirectory: true)
        let fileURL: URL = rootURL.appendingPathComponent("safe.txt")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("safe".utf8).write(to: fileURL)

        let source: ScanSource = ScanSource(path: canonicalPath(rootURL), displayName: rootURL.lastPathComponent)
        let settings: DiskScanSettings = .diskInventoryZDefault
        let currentRoot: DiskItem = try await DiskInventoryZScanner().scan(source: source, settings: settings).item
        let fileItem: DiskItem = try #require(currentRoot.item(atPath: canonicalPath(fileURL)))
        let worker: DiskInventoryZScanSessionTreeWorker = DiskInventoryZScanSessionTreeWorker()

        withUnsafeCurrentTask { $0?.cancel() }

        await #expect(throws: CancellationError.self) {
            try await worker.delete(
                item: fileItem,
                deletionMethod: .deletePermanently,
                currentRoot: currentRoot,
                source: source,
                settings: settings
            )
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

/// `URL.resolvingSymlinksInPath()`/`.standardizedFileURL` deliberately leave the
/// well-known /tmp, /var, /etc symlinks unresolved, but the scanner's directory
/// enumeration reports fully realpath()-resolved paths (e.g. /private/var/...
/// rather than /var/...) - so tests comparing against a scanned path must
/// canonicalize the same way the real filesystem does.
private func canonicalPath(_ url: URL) -> String {
    var buffer: [Int8] = [Int8](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else {
        return url.path
    }
    return String(cString: buffer)
}

private final class FixedOpaquePackageSizer: @unchecked Sendable, OpaquePackageSizing {
    private let lock: NSLock = NSLock()
    private let size: OpaquePackageSize
    private var lockedSizedURLs: [URL] = []

    var sizedURLs: [URL] {
        lock.withLock {
            lockedSizedURLs
        }
    }

    init(size: OpaquePackageSize) {
        self.size = size
    }

    func size(of url: URL) throws -> OpaquePackageSize {
        lock.withLock {
            lockedSizedURLs.append(url)
        }
        return size
    }
}

private final class FixedKindItemFactory: @unchecked Sendable, DiskItemBuilding {
    private let kindName: String

    init(kindName: String) {
        self.kindName = kindName
    }

    func makeItem(url: URL, values: URLResourceValues?) -> DiskItemBuilder {
        DiskItemBuilder(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            allocatedSizeValue: UInt64(values?.totalFileAllocatedSize ?? 0),
            logicalSizeValue: UInt64(values?.fileSize ?? 0),
            kindName: kindName,
            isDirectory: values?.isDirectory ?? url.hasDirectoryPath,
            isPackage: values?.isPackage ?? false,
            isAliasOrSymbolicLink: values?.isSymbolicLink ?? false
        )
    }

    func makeItem(url: URL, values: URLResourceValues?, in arenaOwner: DiskItemBuilder) -> DiskItemBuilder {
        arenaOwner.makeChild(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            allocatedSizeValue: UInt64(values?.totalFileAllocatedSize ?? 0),
            logicalSizeValue: UInt64(values?.fileSize ?? 0),
            kindName: kindName,
            isDirectory: values?.isDirectory ?? url.hasDirectoryPath,
            isPackage: values?.isPackage ?? false,
            isAliasOrSymbolicLink: values?.isSymbolicLink ?? false
        )
    }
}

private final class AlwaysDuplicateHardlinkDeduplicator: @unchecked Sendable, HardlinkDeduplicating {
    private let lock: NSLock = NSLock()
    private var lockedDidReset: Bool = false

    var didReset: Bool {
        lock.withLock {
            lockedDidReset
        }
    }

    func reset() {
        lock.withLock {
            lockedDidReset = true
        }
    }

    func markDuplicateIfNeeded(item: DiskItemBuilder, values: URLResourceValues) {
        item.isHardlinkDuplicate = true
    }
}

private actor ProgressRecorder {
    private(set) var byteCounts: [UInt64] = []

    func record(_ progress: DiskScanProgress) {
        byteCounts.append(progress.scannedByteCount)
    }
}

private actor ScanStageRecorder {
    private(set) var stages: [DiskScanStage] = []

    func record(_ stage: DiskScanStage) {
        stages.append(stage)
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

private final class ConcurrentResourceReadTracker: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var activeCount: Int = 0
    private var lockedMaximumActiveCount: Int = 0
    private var lockedTotalEntryCount: Int = 0

    var maximumActiveCount: Int {
        lock.withLock {
            lockedMaximumActiveCount
        }
    }

    var totalEntryCount: Int {
        lock.withLock {
            lockedTotalEntryCount
        }
    }

    func enter() {
        lock.withLock {
            activeCount += 1
            lockedTotalEntryCount += 1
            lockedMaximumActiveCount = max(lockedMaximumActiveCount, activeCount)
        }
    }

    func leave() {
        lock.withLock {
            activeCount -= 1
        }
    }
}
