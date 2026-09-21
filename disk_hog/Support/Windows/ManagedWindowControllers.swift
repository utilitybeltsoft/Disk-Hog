import AppKit
import SwiftUI

@MainActor
final class SourceWindowController: NSWindowController, NSWindowDelegate {
    static let shared: SourceWindowController = SourceWindowController()

    private init() {
        let contentSize: NSSize = NSSize(
            width: SourceWindowMetrics.windowMinimumWidth,
            height: SourceWindowMetrics.windowMinimumHeight
        )
        let window: NSWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Choose Source to Scan")
        window.contentMinSize = contentSize
        window.isRestorable = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: ContentView())
        window.delegate = self
        ApplicationWindowPlacementService.shared.register(window, role: .source)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let activeScanningSessions: [ScanSession] = ScanWindowRegistry.shared.activeScanningSessions
        guard activeScanningSessions.isEmpty == false else {
            NSApp.terminate(nil)
            return false
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = String(
            localized: "Cancel active scans before closing the source window?"
        )
        alert.informativeText = activeScanningSessions.count == 1
            ? String(localized: "One scan is still running. Disk Hog will keep the source window open after cancelling it.")
            : String(localized: "\(activeScanningSessions.count) scans are still running. Disk Hog will keep the source window open after cancelling them.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Cancel Active Scans"))
        alert.addButton(withTitle: String(localized: "Keep Scanning"))

        if alert.runModal() == .alertFirstButtonReturn {
            ScanWindowRegistry.shared.cancelActiveScans()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            ApplicationWindowPlacementService.shared.unregister(window)
        }
    }
}

@MainActor
final class ScanWindowController: NSWindowController, NSWindowDelegate {
    let source: ScanSource
    let session: ScanSession

    private let initialGeometryApplier: ScanWindowInitialGeometryApplier = ScanWindowInitialGeometryApplier()

    convenience init(source: ScanSource) {
        self.init(source: source, session: ScanSession(source: source))
    }

    init(source: ScanSource, session: ScanSession) {
        self.source = source
        self.session = session
        let window: NSWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: ScanWindowGeometry.defaultWidth, height: ScanWindowGeometry.defaultHeight)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = source.scanWindowTitle
        window.tabbingMode = .disallowed
        window.isRestorable = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: ScanWindowView(session: session))
        window.delegate = self
        initialGeometryApplier.applyIfNeeded(to: window)
        ApplicationWindowPlacementService.shared.register(window, role: .scan)
        ScanWindowRegistry.shared.register(window, session: session, for: source)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        ApplicationWindowPlacementService.shared.placeNewWindow(window)
        showWindow(nil)
        activate()
        InspectorWindowController.shared.arrangeBesideScanWindowIfNeeded(window, for: session)
    }

    func activate() {
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard session.state == .scanning else {
            return true
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = String(localized: "Cancel this scan and close this window?")
        alert.informativeText = String(
            localized: "This scan is still running. Closing the window will cancel it."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Cancel Scan and Close"))
        alert.addButton(withTitle: String(localized: "Keep Scanning"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        session.cancel()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        session.cancel()
        guard let window else {
            return
        }
        ScanWindowRegistry.shared.unregister(window, for: source)
        ApplicationWindowPlacementService.shared.unregister(window)
        ScanWindowControllerRegistry.shared.remove(self)
    }
}

@MainActor
final class ScanWindowControllerRegistry {
    static let shared: ScanWindowControllerRegistry = ScanWindowControllerRegistry()

    private var controllersBySourceKey: [String: ScanWindowController] = [:]

    private init() {}

    func show(source: ScanSource) {
        let sourceKey: String = source.scanWindowRegistryKey
        if let controller: ScanWindowController = controllersBySourceKey[sourceKey] {
            controller.activate()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller: ScanWindowController = ScanWindowController(source: source)
        controllersBySourceKey[sourceKey] = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func remove(_ controller: ScanWindowController) {
        let sourceKey: String = controller.source.scanWindowRegistryKey
        guard controllersBySourceKey[sourceKey] === controller else {
            return
        }
        controllersBySourceKey[sourceKey] = nil
    }
}
