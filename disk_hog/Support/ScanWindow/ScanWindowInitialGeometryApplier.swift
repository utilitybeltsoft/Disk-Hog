import AppKit

@MainActor
final class ScanWindowInitialGeometryApplier {
    private var didApplyInitialWindowGeometry: Bool = false

    func applyIfNeeded(to window: NSWindow) {
        guard didApplyInitialWindowGeometry == false else {
            return
        }

        didApplyInitialWindowGeometry = true
        apply(to: window)
    }

    private func apply(to window: NSWindow) {
        let screen: NSScreen? = window.screen ?? NSScreen.main
        let visibleFrame: NSRect = screen?.visibleFrame ?? window.frame
        let usableFrame: NSRect = ScanWindowInitialGeometry.usableFrame(within: visibleFrame)
        let minimumContentSize: NSSize = ScanWindowInitialGeometry.contentSize(
            fitting: usableFrame,
            desiredContentSize: ScanWindowGeometry.minimumContentSize,
            window: window
        )
        let initialContentSize: NSSize = ScanWindowInitialGeometry.contentSize(
            fitting: usableFrame,
            desiredContentSize: ScanWindowGeometry.defaultContentSize,
            window: window
        )

        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        window.setContentSize(initialContentSize)
        window.setFrame(ScanWindowInitialGeometry.frame(window.frame, fittingIn: usableFrame), display: false)
    }
}
