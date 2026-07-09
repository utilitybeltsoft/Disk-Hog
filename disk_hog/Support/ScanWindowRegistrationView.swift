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

        initialGeometryApplier.applyIfNeeded(to: window)
        if let session: ScanSession = session {
            ScanWindowRegistry.shared.register(window, session: session, for: source)
        }
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
        self.registeredWindow = nil
    }
}
