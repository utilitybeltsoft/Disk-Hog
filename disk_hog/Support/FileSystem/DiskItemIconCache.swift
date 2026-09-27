import AppKit
import Combine

@MainActor
final class DiskItemIconCache {
    typealias IconLoader = (String) -> NSImage

    static let shared: DiskItemIconCache = DiskItemIconCache()

    private final class Entry {
        let icon: NSImage
        let expiresAt: TimeInterval
        init(icon: NSImage, expiresAt: TimeInterval) { self.icon = icon; self.expiresAt = expiresAt }
    }
    private struct Pending {
        let id = UUID()
        let generation: UInt64
        let task: Task<NSImage, Never>
    }
    private let cache: NSCache<NSString, Entry>
    private let loadIcon: IconLoader
    private let lifetime: TimeInterval
    private let now: () -> TimeInterval
    private var generation: UInt64 = 0
    private var pending: [String: Pending] = [:]
    private var observers: Set<AnyCancellable> = []

    init(
        countLimit: Int = 4_096,
        lifetime: TimeInterval = 30,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        applicationNotifications: NotificationCenter = .default,
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        loadIcon: @escaping IconLoader = { NSWorkspace.shared.icon(forFile: $0) }
    ) {
        let cache: NSCache<NSString, Entry> = NSCache()
        cache.countLimit = countLimit
        self.cache = cache
        self.loadIcon = loadIcon
        self.lifetime = lifetime
        self.now = now
        // ScanSession posts this synchronously on MainActor. Clear before views
        // consume the new tree, rather than scheduling invalidation after redraw.
        applicationNotifications.publisher(for: .scanSessionTreeDidChange).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }.store(in: &observers)
        observe(NSApplication.didBecomeActiveNotification, on: applicationNotifications)
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observe(name, on: workspaceNotifications)
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.removeAll()
        }.store(in: &observers)
    }

    func icon(for item: DiskItem) -> NSImage { icon(forFile: item.path) }

    func icon(forFile path: String) -> NSImage {
        if let icon = cachedIcon(forFile: path) { return icon }
        let icon = loadIcon(path)
        store(icon, for: path)
        return icon
    }

    /// Never performs filesystem work on a cache miss or expired entry.
    func cachedIcon(forFile path: String) -> NSImage? {
        let key = path as NSString
        guard let entry = cache.object(forKey: key) else { return nil }
        guard entry.expiresAt > now() else {
            cache.removeObject(forKey: key)
            return nil
        }
        return entry.icon
    }

    /// Prefetch and visible rows share one background load per path/generation.
    /// An invalidation while awaiting a load makes every waiter retry, so stale
    /// work can neither refill the cache nor be delivered to a view.
    func loadIconAsync(forFile path: String) async -> NSImage {
        while true {
            if let icon = cachedIcon(forFile: path) { return icon }
            let request: Pending
            if let existing = pending[path] {
                request = existing
            } else {
                let loadIcon = loadIcon
                request = Pending(generation: generation, task: Task.detached(priority: .userInitiated) {
                    loadIcon(path)
                })
                pending[path] = request
            }
            let icon = await request.task.value
            guard request.generation == generation else { continue }
            if pending[path]?.id == request.id { pending[path] = nil }
            // A synchronous lookup may have supplied a newer icon meanwhile.
            if let cached = cachedIcon(forFile: path) { return cached }
            store(icon, for: path)
            return icon
        }
    }

    func prefetch(paths: [String]) {
        for path in Set(paths) where cachedIcon(forFile: path) == nil {
            Task { _ = await loadIconAsync(forFile: path) }
        }
    }

    private func store(_ icon: NSImage, for path: String) {
        cache.setObject(Entry(icon: icon, expiresAt: now() + lifetime), forKey: path as NSString)
    }

    func removeAll() {
        generation &+= 1
        cache.removeAllObjects()
        pending.removeAll()
    }
}
