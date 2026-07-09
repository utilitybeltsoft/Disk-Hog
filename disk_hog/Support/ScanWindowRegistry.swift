import AppKit

@MainActor
final class ScanWindowRegistry {
    static let shared: ScanWindowRegistry = ScanWindowRegistry()

    private var windowsBySourceKey: [String: WeakScanWindow] = [:]

    private init() {}

    func register(_ window: NSWindow, for source: ScanSource) {
        windowsBySourceKey[source.scanWindowRegistryKey] = WeakScanWindow(window)
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
}

private final class WeakScanWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }
}
