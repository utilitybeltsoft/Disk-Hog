import AppKit
import Testing
@testable import disk_hog

@MainActor
struct OpenWithCacheTests {
    @Test func iconRequestsShareOneInFlightLoadAndThenHitCache() {
        var loads = 0
        var finish: (@MainActor (NSImage) -> Void)?
        let cache = OpenWithApplicationIconCache(cache: Self.cache(capacity: 2)) { _, completion in
            loads += 1
            finish = completion
        }
        let url = URL(fileURLWithPath: "/Applications/Fixture.app")
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        var received: [NSImage] = []
        cache.icon(for: url) { received.append($0) }
        cache.icon(for: url) { received.append($0) }
        #expect(loads == 1)
        #expect(received.isEmpty)
        finish?(icon)
        cache.icon(for: url) { received.append($0) }
        #expect(loads == 1)
        #expect(received.count == 3)
        #expect(received.allSatisfy { $0 === icon })
    }

    @Test func iconCacheEvictsLeastRecentlyUsedEntry() {
        var loads: [String: Int] = [:]
        let cache = OpenWithApplicationIconCache(cache: Self.cache(capacity: 2)) { url, completion in
            loads[url.lastPathComponent, default: 0] += 1
            completion(NSImage(size: NSSize(width: 16, height: 16)))
        }
        func request(_ name: String) { cache.icon(for: URL(fileURLWithPath: "/\(name)")) { _ in } }
        request("A.app")
        request("B.app")
        request("A.app") // A stays hot; B must be evicted next.
        request("C.app")
        request("A.app")
        #expect(loads["A.app"] == 1)
        request("B.app")
        #expect(loads["B.app"] == 2)
    }

    @Test func applicationLookupExpiresAndDoesNotSharePerFileDefaults() {
        var time: TimeInterval = 0
        let storage: OpenWithLookupCache<[OpenWithApplication]> = Self.cache(capacity: 2, now: { time })
        let state = ApplicationState()
        var loads = 0
        let cache = OpenWithApplicationCache(cache: storage) { url, completion in
            loads += 1
            completion([OpenWithApplication(url: URL(fileURLWithPath: state.updated ? "/New.app" : "/Old.app"),
                displayName: url.lastPathComponent, isDefaultApplication: true)])
        }
        func request(_ path: String) -> [OpenWithApplication] {
            var result: [OpenWithApplication] = []
            cache.applications(for: DiskItem(url: URL(fileURLWithPath: path))) { result = $0 }
            return result
        }
        #expect(request("/a.txt").first?.displayName == "a.txt")
        #expect(request("/b.txt").first?.displayName == "b.txt")
        state.updated = true
        #expect(request("/a.txt").first?.url.path == "/Old.app")
        time = 30
        #expect(request("/a.txt").first?.url.path == "/New.app")
        #expect(loads == 3)
    }

    @Test func iconsExpireWithoutAnApplicationEvent() {
        var time: TimeInterval = 0
        let storage: OpenWithLookupCache<NSImage> = Self.cache(capacity: 2, now: { time })
        var loads = 0
        let cache = OpenWithApplicationIconCache(cache: storage) { _, completion in
            loads += 1
            completion(NSImage(size: NSSize(width: 16, height: 16)))
        }
        let url = URL(fileURLWithPath: "/Fixture.app")
        cache.icon(for: url) { _ in }
        time = 29
        cache.icon(for: url) { _ in }
        #expect(loads == 1)
        time = 30
        cache.icon(for: url) { _ in }
        #expect(loads == 2)
    }

    @Test func invalidationDiscardsOldWorkAndPreservesEveryWaiter() {
        let cache: OpenWithLookupCache<Int> = Self.cache(capacity: 2)
        var finishes: [@MainActor (Int) -> Void] = []
        let loader: OpenWithLookupCache<Int>.Loader = { finishes.append($0) }
        var received: [Int] = []
        cache.value(for: "key", load: loader) { received.append($0) }
        cache.value(for: "key", load: loader) { received.append($0) }
        cache.invalidate()
        cache.value(for: "key", load: loader) { received.append($0) }
        #expect(finishes.count == 1)
        finishes[0](1)
        #expect(received.isEmpty)
        #expect(finishes.count == 2)
        finishes[1](2)
        #expect(received == [2, 2, 2])
        cache.value(for: "key", load: loader) { received.append($0) }
        #expect(received == [2, 2, 2, 2])
        #expect(finishes.count == 2)
    }

    @Test func applicationAndWorkspaceEventsInvalidateCachedValues() async throws {
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let cache = OpenWithLookupCache<Int>(capacity: 2, applicationNotifications: appCenter,
                                             workspaceNotifications: workspaceCenter)
        var loads = 0
        let loader: OpenWithLookupCache<Int>.Loader = { completion in loads += 1; completion(loads) }
        cache.value(for: "key", load: loader) { _ in }
        let events: [(NotificationCenter, Notification.Name)] = [
            (appCenter, NSApplication.didBecomeActiveNotification),
            (workspaceCenter, NSWorkspace.didLaunchApplicationNotification),
            (workspaceCenter, NSWorkspace.didTerminateApplicationNotification),
            (workspaceCenter, NSWorkspace.didMountNotification),
            (workspaceCenter, NSWorkspace.didUnmountNotification)
        ]
        for (center, name) in events {
            let previousLoads = loads
            center.post(name: name, object: nil)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while loads == previousLoads && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
                cache.value(for: "key", load: loader) { _ in }
            }
            #expect(loads == previousLoads + 1)
        }
    }

    @Test func destroyingCacheReleasesStoredValuesAndNotificationSubscriptions() {
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        var cache: OpenWithLookupCache<NSImage>? = OpenWithLookupCache(
            capacity: 2, applicationNotifications: appCenter, workspaceNotifications: workspaceCenter)
        weak var weakCache = cache
        weak var cachedImage: NSImage?
        cache?.value(for: "icon", load: { completion in
            let image = NSImage(size: NSSize(width: 16, height: 16))
            cachedImage = image
            completion(image)
        }, completion: { _ in })
        #expect(cachedImage != nil)
        cache = nil
        #expect(weakCache == nil)
        #expect(cachedImage == nil)
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didMountNotification, object: nil)
    }

    private final class ApplicationState { var updated = false }

    private static func cache<Value>(capacity: Int, now: @escaping () -> TimeInterval = { 0 }) -> OpenWithLookupCache<Value> {
        OpenWithLookupCache(capacity: capacity, now: now,
                            applicationNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
    }
}
