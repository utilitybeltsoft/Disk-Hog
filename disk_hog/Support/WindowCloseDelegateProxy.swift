import AppKit

@MainActor
final class WindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    // NSWindow.delegate is weak; SwiftUI retains its scene delegate elsewhere on
    // current macOS releases, so keep this weak and forward only while it lives.
    private weak var forwardingDelegate: (any NSWindowDelegate)?
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
