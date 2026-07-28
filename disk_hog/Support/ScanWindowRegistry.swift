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

    func window(for source: ScanSource) -> NSWindow? {
        let sourceKey: String = source.scanWindowRegistryKey
        guard let window: NSWindow = windowsBySourceKey[sourceKey]?.window else {
            windowsBySourceKey[sourceKey] = nil
            return nil
        }
        return window
    }

    var activeScanningSessions: [ScanSession] {
        openSessions.filter { $0.state == .scanning }
    }

    func cancelActiveScans() {
        for session: ScanSession in activeScanningSessions {
            session.cancel()
        }
    }

    func sessionsAffectedByPackageContentsPreference(_ showPackageContents: Bool) -> [ScanSession] {
        openSessions.filter { $0.scanSettings.lookInsidePackages != showPackageContents }
    }

    func rescanAllForPackageContentsPreference(_ showPackageContents: Bool) {
        for session: ScanSession in openSessions {
            session.rescanForPackageContentsPreference(showPackageContents)
        }
    }

    func markPackageContentsSynchronization(with showPackageContents: Bool) {
        for session: ScanSession in openSessions {
            session.updatePackageContentsSynchronization(with: showPackageContents)
        }
    }

    private var openSessions: [ScanSession] {
        windowsBySourceKey = windowsBySourceKey.filter { _, weakWindow in
            weakWindow.window != nil
        }
        return windowsBySourceKey.values.compactMap(\.session)
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
