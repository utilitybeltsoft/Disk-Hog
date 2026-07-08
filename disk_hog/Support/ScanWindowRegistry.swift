import AppKit
import SwiftUI

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

struct ScanWindowRegistrationView: NSViewRepresentable {
    let source: ScanSource

    func makeNSView(context: Context) -> ScanWindowRegistrationNSView {
        ScanWindowRegistrationNSView(source: source)
    }

    func updateNSView(_ nsView: ScanWindowRegistrationNSView, context: Context) {
        nsView.source = source
    }
}

final class ScanWindowRegistrationNSView: NSView {
    var source: ScanSource
    private weak var registeredWindow: NSWindow?
    private var didScheduleInitialWindowSize: Bool = false

    init(source: ScanSource) {
        self.source = source
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let registeredWindow: NSWindow = registeredWindow {
            ScanWindowRegistry.shared.unregister(registeredWindow, for: source)
            self.registeredWindow = nil
        }

        guard let window: NSWindow = window else {
            return
        }

        scheduleInitialWindowSizeIfNeeded(for: window)
        ScanWindowRegistry.shared.register(window, for: source)
        registeredWindow = window
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let registeredWindow: NSWindow = registeredWindow {
            ScanWindowRegistry.shared.unregister(registeredWindow, for: source)
            self.registeredWindow = nil
        }

        super.viewWillMove(toWindow: newWindow)
    }

    private func scheduleInitialWindowSizeIfNeeded(for window: NSWindow) {
        guard didScheduleInitialWindowSize == false else {
            return
        }

        didScheduleInitialWindowSize = true
        applyInitialWindowSize(to: window, attempt: 0)
        DispatchQueue.main.async { [weak window] in
            guard let window: NSWindow = window else {
                return
            }

            self.applyInitialWindowSize(to: window, attempt: 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ScanWindowInitialGeometry.restorationDelay) { [weak window] in
            guard let window: NSWindow = window else {
                return
            }

            self.applyInitialWindowSize(to: window, attempt: 2)
        }
    }

    private func applyInitialWindowSize(to window: NSWindow, attempt: Int) {
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: ScanWindowInitialGeometry.minimumContentSize)).size
        window.setContentSize(ScanWindowInitialGeometry.contentSize)
    }
}

private enum ScanWindowInitialGeometry {
    static let contentSize: NSSize = NSSize(width: 837, height: 1080)
    static let minimumContentSize: NSSize = NSSize(width: 837, height: 1080)
    static let restorationDelay: TimeInterval = 0.15
}
