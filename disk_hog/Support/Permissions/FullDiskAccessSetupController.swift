import AppKit
import Combine
import SwiftUI

@MainActor
final class FullDiskAccessSetupController: NSWindowController, NSWindowDelegate {
    let model: FullDiskAccessSetupModel
    private var observation: AnyCancellable?

    init(model: FullDiskAccessSetupModel) {
        self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
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
            model: model,
            revealApplication: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
        ))
        panel.center()
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
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.blocksScanning else { return false }
        model.dismissGuidance()
        return true
    }

    private func updateVisibility() {
        if model.isPresented {
            if window?.isVisible != true { window?.makeKeyAndOrderFront(nil) }
        } else {
            window?.orderOut(nil)
        }
    }
}

private struct FullDiskAccessSetupView: View {
    @ObservedObject var model: FullDiskAccessSetupModel
    let revealApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable Full Disk Access")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Disk Hog needs access to protected folders to include them in disk scans. Without it, scans can miss files and underreport disk usage.")
            Text("In System Settings, turn on Disk Hog under Privacy & Security → Full Disk Access. Choose Quit & Reopen if macOS asks; otherwise quit and reopen Disk Hog.")
            if model.isChecking {
                ProgressView("Checking protected-folder access…")
            } else if model.hasChecked && model.status == .inconclusive {
                Text("Disk Hog could not determine whether protected-folder access is available. You can continue using accessible folders or review Full Disk Access in System Settings.")
                    .foregroundStyle(.secondary)
            }
            if model.settingsOpenFailed {
                Text("System Settings could not be opened. Open it from the Apple menu, then choose Privacy & Security → Full Disk Access.")
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Disk Hog isn’t listed") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Click + in Full Disk Access and select the Disk Hog application shown in Finder. Enable it, then reopen Disk Hog.")
                    Button("Show Disk Hog in Finder", action: revealApplication)
                }
            }
            HStack {
                Button("Quit Disk Hog", action: model.quit)
                    .keyboardShortcut("q", modifiers: .command)
                Spacer()
                Button("Open Full Disk Access", action: model.requestSettings)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isChecking)
            }
            if model.hasOpenedSettings {
                Button("Check Again", action: model.recheck)
                    .disabled(model.isChecking)
            }
            if !model.blocksScanning {
                Button("Continue", action: model.dismissGuidance)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
