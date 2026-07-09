import AppKit
import SwiftUI

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
    private let initialGeometryApplier: ScanWindowInitialGeometryApplier = ScanWindowInitialGeometryApplier()

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

        unregisterCurrentWindow()

        guard let window: NSWindow = window else {
            return
        }

        initialGeometryApplier.applyIfNeeded(to: window)
        ScanWindowRegistry.shared.register(window, for: source)
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
