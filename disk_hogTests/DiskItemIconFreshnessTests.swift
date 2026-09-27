import AppKit
import Testing
@testable import disk_hog

@MainActor
struct DiskItemIconFreshnessTests {
    @Test func treeChangeImmediatelyInvalidatesSamePathIcon() {
        let center = NotificationCenter()
        var loads = 0
        let cache = DiskItemIconCache(applicationNotifications: center,
                                      workspaceNotifications: NotificationCenter()) { _ in
            loads += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let original = cache.icon(forFile: "/fixture/file")
        center.post(name: .scanSessionTreeDidChange, object: nil)
        #expect(cache.cachedIcon(forFile: "/fixture/file") == nil)
        let replacement = cache.icon(forFile: "/fixture/file")
        #expect(original !== replacement)
        #expect(loads == 2)
    }

    @Test func expiredPeekDoesNotLoadAndNextRequestRefreshes() {
        var time: TimeInterval = 0
        var loads = 0
        let cache = DiskItemIconCache(now: { time }, applicationNotifications: NotificationCenter(),
                                      workspaceNotifications: NotificationCenter()) { _ in
            loads += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        _ = cache.icon(forFile: "/fixture/file")
        time = 30
        #expect(cache.cachedIcon(forFile: "/fixture/file") == nil)
        #expect(loads == 1)
        _ = cache.icon(forFile: "/fixture/file")
        #expect(loads == 2)
    }

    @Test func invalidationDuringPrefetchCannotRestoreOrReturnOldIcon() async throws {
        let loader = GatedDiskIconLoader()
        defer { loader.release() }
        let cache = DiskItemIconCache(applicationNotifications: NotificationCenter(),
                                      workspaceNotifications: NotificationCenter(), loadIcon: loader.load)
        cache.prefetch(paths: ["/fixture/file", "/fixture/file"])
        try await Self.wait { loader.calls == 1 }
        let waiting = Task { await cache.loadIconAsync(forFile: "/fixture/file") }
        await Task.yield()
        cache.removeAll()
        let fresh = await cache.loadIconAsync(forFile: "/fixture/file")
        loader.release()
        let delivered = await waiting.value
        #expect(delivered === fresh)
        #expect(cache.cachedIcon(forFile: "/fixture/file") === fresh)
        #expect(loader.calls == 2)
    }

    @Test func concurrentAsyncRequestsShareOneLoader() async throws {
        let loader = GatedDiskIconLoader()
        defer { loader.release() }
        let cache = DiskItemIconCache(applicationNotifications: NotificationCenter(),
                                      workspaceNotifications: NotificationCenter(), loadIcon: loader.load)
        let first = Task { await cache.loadIconAsync(forFile: "/fixture/file") }
        let second = Task { await cache.loadIconAsync(forFile: "/fixture/file") }
        try await Self.wait { loader.calls == 1 }
        loader.release()
        let firstIcon = await first.value
        let secondIcon = await second.value
        #expect(firstIcon === secondIcon)
        #expect(loader.calls == 1)
    }

    @Test func activationAndVolumeEventsInvalidateIcons() async throws {
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let cache = DiskItemIconCache(applicationNotifications: appCenter, workspaceNotifications: workspaceCenter) { _ in
            NSImage(size: NSSize(width: 16, height: 16))
        }
        let events: [(NotificationCenter, Notification.Name)] = [
            (appCenter, NSApplication.didBecomeActiveNotification),
            (workspaceCenter, NSWorkspace.didMountNotification),
            (workspaceCenter, NSWorkspace.didUnmountNotification),
            (workspaceCenter, NSWorkspace.didRenameVolumeNotification)
        ]
        for (center, name) in events {
            _ = cache.icon(forFile: "/fixture/file")
            center.post(name: name, object: nil)
            try await Self.wait { cache.cachedIcon(forFile: "/fixture/file") == nil }
        }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition(), "Timed out waiting for icon cache work")
    }
}

private final class GatedDiskIconLoader: @unchecked Sendable {
    private let condition = NSCondition()
    private var count = 0
    private var released = false
    var calls: Int { condition.withLock { count } }
    func release() { condition.withLock { released = true; condition.broadcast() } }
    func load(_ path: String) -> NSImage {
        condition.lock()
        count += 1
        if count == 1 {
            let deadline = Date().addingTimeInterval(15)
            while !released { if !condition.wait(until: deadline) { break } }
        }
        condition.unlock()
        return NSImage(size: NSSize(width: 16, height: 16))
    }
}
