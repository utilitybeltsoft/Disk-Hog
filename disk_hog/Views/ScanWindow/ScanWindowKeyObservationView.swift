@preconcurrency import AppKit
import SwiftUI

struct ScanWindowKeyObservationView: NSViewRepresentable {
    let onDidBecomeKey: @Sendable @MainActor () -> Void

    func makeNSView(context: Context) -> ScanWindowKeyObservationNSView {
        ScanWindowKeyObservationNSView(onDidBecomeKey: onDidBecomeKey)
    }

    func updateNSView(_ nsView: ScanWindowKeyObservationNSView, context: Context) {
        nsView.onDidBecomeKey = onDidBecomeKey
    }
}

@MainActor
final class ScanWindowKeyObservationNSView: NSView {
    var onDidBecomeKey: @Sendable @MainActor () -> Void
    private weak var observedWindow: NSWindow?
    private var didBecomeKeyObserver: NSObjectProtocol?
    private var pendingDidBecomeKey: DispatchWorkItem?

    init(onDidBecomeKey: @escaping @Sendable @MainActor () -> Void) {
        self.onDidBecomeKey = onDidBecomeKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pendingDidBecomeKey?.cancel()
        if let didBecomeKeyObserver: NSObjectProtocol {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowIfNeeded(window)
    }

    private func observeWindowIfNeeded(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }

        if let didBecomeKeyObserver: NSObjectProtocol {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            self.didBecomeKeyObserver = nil
        }

        observedWindow = window

        guard let window: NSWindow = window else {
            return
        }

        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleDidBecomeKey(for: window)
            }
        }

        if window.isKeyWindow {
            scheduleDidBecomeKey(for: window)
        }
    }

    private func scheduleDidBecomeKey(for window: NSWindow) {
        pendingDidBecomeKey?.cancel()

        let workItem: DispatchWorkItem = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  window?.isKeyWindow == true else {
                return
            }

            self.pendingDidBecomeKey = nil
            self.onDidBecomeKey()
        }
        pendingDidBecomeKey = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}
