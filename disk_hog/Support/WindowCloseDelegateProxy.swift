import AppKit

@MainActor
final class WindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    private weak var forwardingDelegate: (any NSWindowDelegate)?
    private let shouldClose: (NSWindow) -> Bool

    init(forwardingDelegate: (any NSWindowDelegate)?, shouldClose: @escaping (NSWindow) -> Bool) {
        self.forwardingDelegate = forwardingDelegate
        self.shouldClose = shouldClose
        super.init()
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
