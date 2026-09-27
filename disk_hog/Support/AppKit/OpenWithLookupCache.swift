import AppKit
import Combine

/// Small LRU cache shared by application discovery and icon loading. All state
/// and callbacks stay on MainActor; loaders perform their expensive work elsewhere.
@MainActor
final class OpenWithLookupCache<Value> {
    typealias Completion = @MainActor (Value) -> Void
    typealias Loader = @MainActor (@escaping Completion) -> Void
    private struct Entry {
        let value: Value
        let expiresAt: TimeInterval
        var access: UInt64
    }
    private struct Pending {
        let load: Loader
        var completions: [Completion]
    }
    private var entries: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private var generation: UInt64 = 0
    private var access: UInt64 = 0
    private let capacity: Int
    private let lifetime: TimeInterval
    private let now: () -> TimeInterval
    private var observers: Set<AnyCancellable> = []

    init(capacity: Int, lifetime: TimeInterval = 30,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         applicationNotifications: NotificationCenter = .default,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.lifetime = lifetime
        self.now = now
        observe(NSApplication.didBecomeActiveNotification, on: applicationNotifications)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observe(name, on: workspaceNotifications)
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.invalidate()
        }.store(in: &observers)
    }

    func invalidate() {
        generation &+= 1
        entries.removeAll()
        // Keep waiters attached to in-flight work. Its result is discarded and
        // reloaded below, rather than delivering stale data or losing callbacks.
    }

    func value(for key: String, load: @escaping Loader, completion: @escaping Completion) {
        access &+= 1
        if var entry = entries[key], entry.expiresAt > now() {
            entry.access = access
            entries[key] = entry
            completion(entry.value)
            return
        }
        entries[key] = nil
        if pending[key] != nil {
            pending[key]?.completions.append(completion)
            return
        }
        pending[key] = Pending(load: load, completions: [completion])
        start(key)
    }

    private func start(_ key: String) {
        let revision = generation
        pending[key]?.load { [weak self] value in
            guard let self else { return }
            guard revision == self.generation else {
                self.start(key)
                return
            }
            guard let request = self.pending.removeValue(forKey: key) else { return }
            self.access &+= 1
            self.entries[key] = Entry(value: value, expiresAt: self.now() + self.lifetime, access: self.access)
            if self.entries.count > self.capacity,
               let oldest = self.entries.min(by: { $0.value.access < $1.value.access })?.key {
                self.entries[oldest] = nil
            }
            for completion in request.completions { completion(value) }
        }
    }
}
