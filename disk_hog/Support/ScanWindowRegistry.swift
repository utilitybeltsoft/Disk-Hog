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
    private var didApplyInitialWindowGeometry: Bool = false

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

        applyInitialWindowGeometryIfNeeded(to: window)
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

    private func applyInitialWindowGeometryIfNeeded(to window: NSWindow) {
        guard didApplyInitialWindowGeometry == false else {
            return
        }

        didApplyInitialWindowGeometry = true
        applyInitialWindowGeometry(to: window)
    }

    private func applyInitialWindowGeometry(to window: NSWindow) {
        let screen: NSScreen? = window.screen ?? NSScreen.main
        let visibleFrame: NSRect = screen?.visibleFrame ?? window.frame
        let minimumContentSize: NSSize = ScanWindowInitialGeometry.contentSize(
            fitting: visibleFrame,
            desiredContentSize: ScanWindowGeometry.minimumContentSize,
            window: window
        )
        let initialContentSize: NSSize = ScanWindowInitialGeometry.contentSize(
            fitting: visibleFrame,
            desiredContentSize: ScanWindowGeometry.defaultContentSize,
            window: window
        )

        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        window.setContentSize(initialContentSize)
        window.setFrame(ScanWindowInitialGeometry.frame(window.frame, fittingIn: visibleFrame), display: false)
    }
}

private enum ScanWindowInitialGeometry {
    static func contentSize(fitting visibleFrame: NSRect, desiredContentSize: NSSize, window: NSWindow) -> NSSize {
        let desiredFrameSize: NSSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: desiredContentSize)).size
        let frameWidthOverflow: CGFloat = max(desiredFrameSize.width - visibleFrame.width, 0)
        let frameHeightOverflow: CGFloat = max(desiredFrameSize.height - visibleFrame.height, 0)
        return NSSize(
            width: max(desiredContentSize.width - frameWidthOverflow, ScanWindowGeometry.minimumUsableContentSize.width),
            height: max(desiredContentSize.height - frameHeightOverflow, ScanWindowGeometry.minimumUsableContentSize.height)
        )
    }

    static func frame(_ frame: NSRect, fittingIn visibleFrame: NSRect) -> NSRect {
        var fittedFrame: NSRect = frame
        if fittedFrame.width > visibleFrame.width {
            fittedFrame.size.width = visibleFrame.width
        }
        if fittedFrame.height > visibleFrame.height {
            fittedFrame.size.height = visibleFrame.height
        }
        if fittedFrame.maxX > visibleFrame.maxX {
            fittedFrame.origin.x = visibleFrame.maxX - fittedFrame.width
        }
        if fittedFrame.minX < visibleFrame.minX {
            fittedFrame.origin.x = visibleFrame.minX
        }
        if fittedFrame.maxY > visibleFrame.maxY {
            fittedFrame.origin.y = visibleFrame.maxY - fittedFrame.height
        }
        if fittedFrame.minY < visibleFrame.minY {
            fittedFrame.origin.y = visibleFrame.minY
        }
        return fittedFrame
    }
}

nonisolated enum ScanWindowGeometry {
    static let defaultContentSize: NSSize = NSSize(width: 837, height: 1080)
    static let minimumContentSize: NSSize = NSSize(width: 837, height: 720)
    static let minimumUsableContentSize: NSSize = NSSize(width: 640, height: 540)
    static let defaultWidth: CGFloat = defaultContentSize.width
    static let defaultHeight: CGFloat = defaultContentSize.height
    static let minimumWidth: CGFloat = minimumContentSize.width
    static let minimumHeight: CGFloat = minimumContentSize.height
}
