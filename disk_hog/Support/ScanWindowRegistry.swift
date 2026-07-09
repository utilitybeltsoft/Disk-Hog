import AppKit

@MainActor
final class ScanWindowRegistry {
    static let shared: ScanWindowRegistry = ScanWindowRegistry()

    private var windowsBySourceKey: [String: WeakScanWindow] = [:]

    private init() {}

    func register(_ window: NSWindow, session: ScanSession, for source: ScanSource) {
        windowsBySourceKey[source.scanWindowRegistryKey] = WeakScanWindow(window, session: session)
    }

    func unregister(_ window: NSWindow, for source: ScanSource) {
        let sourceKey: String = source.scanWindowRegistryKey
        guard windowsBySourceKey[sourceKey]?.window === window else {
            return
        }

        windowsBySourceKey[sourceKey] = nil
    }

    func activateWindow(for source: ScanSource) -> Bool {
        let sourceKey: String = source.scanWindowRegistryKey
        guard let window: NSWindow = windowsBySourceKey[sourceKey]?.window else {
            windowsBySourceKey[sourceKey] = nil
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    var activeScanningSessions: [ScanSession] {
        windowsBySourceKey = windowsBySourceKey.filter { _, weakWindow in
            weakWindow.window != nil
        }
        return windowsBySourceKey.values.compactMap { weakWindow in
            guard let session: ScanSession = weakWindow.session,
                  session.state == .scanning else {
                return nil
            }

            return session
        }
    }

    func cancelActiveScans() {
        for session: ScanSession in activeScanningSessions {
            session.cancel()
        }
    }
}

private final class WeakScanWindow {
    weak var window: NSWindow?
    weak var session: ScanSession?

    init(_ window: NSWindow, session: ScanSession) {
        self.window = window
        self.session = session
    }
}
