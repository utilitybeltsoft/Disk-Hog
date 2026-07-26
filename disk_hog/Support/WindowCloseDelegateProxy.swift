import AppKit

@MainActor
final class WindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    // Replacing NSWindow's weak delegate can remove its last owner. Keep the
    // displaced delegate alive while AppKit may still send callbacks through us.
    private var forwardingDelegate: (any NSWindowDelegate)?
    private weak var installedWindow: NSWindow?
    private let shouldClose: (NSWindow) -> Bool

    init(shouldClose: @escaping (NSWindow) -> Bool) {
        self.shouldClose = shouldClose
        super.init()
    }

    func install(on window: NSWindow) {
        guard installedWindow !== window || window.delegate !== self else {
            return
        }

        restore()
        forwardingDelegate = window.delegate
        installedWindow = window
        window.delegate = self
    }

    func restore() {
        if let installedWindow: NSWindow = installedWindow,
           installedWindow.delegate === self {
            installedWindow.delegate = forwardingDelegate
        }

        installedWindow = nil
        forwardingDelegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldClose(sender)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || forwardingDelegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard forwardingDelegate?.responds(to: aSelector) == true else {
            return super.forwardingTarget(for: aSelector)
        }

        return forwardingDelegate
    }
}
