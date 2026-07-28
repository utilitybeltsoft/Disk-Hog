import AppKit
import SwiftUI

struct ScanWindowRegistrationView: NSViewRepresentable {
    let session: ScanSession
    let source: ScanSource

    func makeNSView(context: Context) -> ScanWindowRegistrationNSView {
        ScanWindowRegistrationNSView(session: session, source: source)
    }

    func updateNSView(_ nsView: ScanWindowRegistrationNSView, context: Context) {
        nsView.session = session
        nsView.source = source
    }
}

final class ScanWindowRegistrationNSView: NSView {
    weak var session: ScanSession?
    var source: ScanSource
    private weak var registeredWindow: NSWindow?
    private lazy var closeDelegateProxy: WindowCloseDelegateProxy = WindowCloseDelegateProxy { [weak self] _ in
        self?.shouldCloseScanWindow() ?? true
    }
    private let initialGeometryApplier: ScanWindowInitialGeometryApplier = ScanWindowInitialGeometryApplier()

    init(session: ScanSession, source: ScanSource) {
        self.session = session
        self.source = source
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        unregisterCurrentWindow()

        guard let window: NSWindow = window else {
            return
        }

        window.tabbingMode = .disallowed
        window.isRestorable = false
        initialGeometryApplier.applyIfNeeded(to: window)
        if let session: ScanSession = session {
            ScanWindowRegistry.shared.register(window, session: session, for: source)
            InspectorWindowController.shared.arrangeBesideScanWindowIfNeeded(
                window,
                for: session
            )
        }
        closeDelegateProxy.install(on: window)
        registeredWindow = window
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            unregisterCurrentWindow()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    private func unregisterCurrentWindow() {
        guard let registeredWindow: NSWindow = registeredWindow else {
            return
        }

        ScanWindowRegistry.shared.unregister(registeredWindow, for: source)
        closeDelegateProxy.restore()
        self.registeredWindow = nil
    }

    private func shouldCloseScanWindow() -> Bool {
        guard let session: ScanSession = session, session.state == .scanning else {
            return true
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = "Cancel this scan and close this window?"
        alert.informativeText = "This scan is still running. Closing the window will cancel it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Scan and Close")
        alert.addButton(withTitle: "Keep Scanning")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        session.cancel()
        return true
    }
}
