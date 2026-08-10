import AppKit
import SwiftUI

@MainActor
final class InspectorWindowHost: NSObject, NSWindowDelegate {
    let windowController: NSWindowController
    private let onClose: () -> Void

    var window: NSWindow? {
        windowController.window
    }

    init(
        contentSize: NSSize,
        minimumContentSize: NSSize,
        selectedTab: InspectorWindowTab,
        frameAutosaveName: String,
        frameMigration: InspectorWindowFrameMigration,
        contentView: InspectorWindowView,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window: NSWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let restoredSavedFrame: Bool = window.setFrameUsingName(frameAutosaveName)
        let restoredFrame: NSRect? = restoredSavedFrame
            ? frameMigration.migratedFrame(
                window.frame,
                restoredContentSize: window.contentRect(forFrameRect: window.frame).size,
                tab: selectedTab,
                targetFrameSize: window.frameRect(
                    forContentRect: NSRect(origin: .zero, size: contentSize)
                ).size
            )
            : nil
        window.contentMinSize = minimumContentSize
        let hostingController: NSHostingController<InspectorWindowView> = NSHostingController(
            rootView: contentView
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        if let restoredFrame {
            window.setFrame(restoredFrame, display: false)
        } else {
            window.setContentSize(contentSize)
            window.center()
        }
        window.setFrameAutosaveName(frameAutosaveName)
        windowController = NSWindowController(window: window)
        super.init()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
