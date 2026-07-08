import AppKit
import SwiftUI

struct ScanWindowKeyObservationView: NSViewRepresentable {
    let onDidBecomeKey: @MainActor () -> Void

    func makeNSView(context: Context) -> ScanWindowKeyObservationNSView {
        ScanWindowKeyObservationNSView(onDidBecomeKey: onDidBecomeKey)
    }

    func updateNSView(_ nsView: ScanWindowKeyObservationNSView, context: Context) {
        nsView.onDidBecomeKey = onDidBecomeKey
    }
}

@MainActor
final class ScanWindowKeyObservationNSView: NSView {
    var onDidBecomeKey: @MainActor () -> Void
    private weak var observedWindow: NSWindow?
    private var didBecomeKeyObserver: NSObjectProtocol?

    init(onDidBecomeKey: @escaping @MainActor () -> Void) {
        self.onDidBecomeKey = onDidBecomeKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
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
            self?.onDidBecomeKey()
        }

        if window.isKeyWindow {
            DispatchQueue.main.async { [weak self, weak window] in
                guard window?.isKeyWindow == true else {
                    return
                }

                self?.onDidBecomeKey()
            }
        }
    }
}

private struct SelectedScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct HoveredScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct ActiveScanWindowPaneKey: EnvironmentKey {
    static let defaultValue: Binding<ScanWindowPane?> = .constant(nil)
}

extension EnvironmentValues {
    var selectedScanItem: Binding<DiskItem?> {
        get { self[SelectedScanItemKey.self] }
        set { self[SelectedScanItemKey.self] = newValue }
    }

    var hoveredScanItem: Binding<DiskItem?> {
        get { self[HoveredScanItemKey.self] }
        set { self[HoveredScanItemKey.self] = newValue }
    }

    var activeScanWindowPane: Binding<ScanWindowPane?> {
        get { self[ActiveScanWindowPaneKey.self] }
        set { self[ActiveScanWindowPaneKey.self] = newValue }
    }
}
