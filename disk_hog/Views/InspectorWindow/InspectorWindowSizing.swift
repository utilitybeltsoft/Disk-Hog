import AppKit

@MainActor
enum InspectorWindowSizing {
    static func clamped(_ size: NSSize, minimum: NSSize) -> NSSize {
        NSSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    static func applyMinimum(_ minimum: NSSize, to window: NSWindow) {
        window.contentMinSize = minimum
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimum)).size
        let size = clamped(window.frame.size, minimum: window.minSize)
        guard size != window.frame.size else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        window.setFrame(frame, display: false)
    }
}
