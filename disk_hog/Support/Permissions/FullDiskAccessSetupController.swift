import AppKit
import Combine
import SwiftUI

@MainActor
final class FullDiskAccessSetupController: NSWindowController, NSWindowDelegate {
    let model: FullDiskAccessSetupModel
    private var observation: AnyCancellable?

    init(model: FullDiskAccessSetupModel) {
        self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = String(localized: "Full Disk Access")
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // A modal setup sheet must never block System Settings' Quit & Reopen.
        panel.preventsApplicationTerminationWhenModal = false
        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: FullDiskAccessSetupView(
            model: model
        ))
        sizeAndCenterWindow()
        observation = model.objectWillChange.sink { [weak self] in
            // Published notifications precede the mutation. Read the completed state.
            Task { @MainActor [weak self] in self?.updateVisibility() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showGuidance() {
        model.showGuidance()
        updateVisibility()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.blocksScanning else { return false }
        model.dismissGuidance()
        return true
    }

    func windowDidResize(_ notification: Notification) {
        centerWindow()
    }

    private func centerWindow() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: available.midX - window.frame.width / 2,
                                      y: available.midY - window.frame.height / 2))
    }

    private func sizeAndCenterWindow() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        centerWindow()
    }

    private func updateVisibility() {
        if model.isPresented {
            sizeAndCenterWindow()
            if window?.isVisible != true { window?.makeKeyAndOrderFront(nil) }
        } else {
            window?.orderOut(nil)
        }
    }
}

private struct FullDiskAccessSetupView: View {
    @ObservedObject var model: FullDiskAccessSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enable Full Disk Access")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Disk Hog needs access to protected folders to include them in disk scans. Without it, scans can miss files and underreport disk usage.")
            Text("In System Settings, turn on Disk Hog under Privacy & Security → Full Disk Access. When macOS asks, choose Quit & Reopen.")
            if model.settingsOpenFailed {
                Text("System Settings could not be opened. Open it from the Apple menu, then choose Privacy & Security → Full Disk Access.")
                    .foregroundStyle(.secondary)
            }
            Text("After you set it, it should look like this:")
            Image("FullDiskAccessExample")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 455)
                .accessibilityLabel("Example: Disk Hog listed in Full Disk Access with its switch turned on.")
            Button("Open Privacy & Security in System Settings", action: model.requestPrivacySettings)
            VStack(alignment: .leading, spacing: 8) {
                Text("If Disk Hog isn’t listed").font(.headline)
                Text("Click + in Full Disk Access and select the Disk Hog application. Turn it on, then choose Quit & Reopen.")
            }
            Text("You can continue with limited access. Protected folders may be skipped and disk usage may be understated. Incomplete scans show a warning; the scan issues list identifies paths that could not be read and their reported errors.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer(minLength: 0)
                Button("Continue with Limited Access", action: model.continueWithLimitedAccess)
            }
            HStack {
                Button("Quit Disk Hog", action: model.quit)
                    .keyboardShortcut("q", modifiers: .command)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }
}
