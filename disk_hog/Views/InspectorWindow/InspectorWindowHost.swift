import AppKit
import SwiftUI

@MainActor
final class InspectorWindowHost: NSObject, NSWindowDelegate {
    let windowController: NSWindowController
    private let onClose: () -> Void
    private let minimumSize: () -> NSSize

    var window: NSWindow? {
        windowController.window
    }

    init(
        contentSize: NSSize,
        minimumContentSize: NSSize,
        frameAutosaveName: String,
        contentView: InspectorWindowView,
        minimumSize: @escaping () -> NSSize,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.minimumSize = minimumSize
        let window: NSWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let restoredSavedFrame: Bool = window.setFrameUsingName(frameAutosaveName)
        let hostingController: NSHostingController<InspectorWindowView> = NSHostingController(
            rootView: contentView
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        if !restoredSavedFrame {
            window.setContentSize(contentSize)
            window.center()
        }
        // Hosting setup and restored frames must not undo the usable minimum.
        InspectorWindowSizing.applyMinimum(minimumContentSize, to: window)
        window.setFrameAutosaveName(frameAutosaveName)
        windowController = NSWindowController(window: window)
        super.init()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimumFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: minimumSize())).size
        return InspectorWindowSizing.clamped(frameSize, minimum: minimumFrame)
    }
}
