import AppKit
import SwiftUI

struct SourceWindowCloseRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> SourceWindowCloseRegistrationNSView {
        SourceWindowCloseRegistrationNSView()
    }

    func updateNSView(_ nsView: SourceWindowCloseRegistrationNSView, context: Context) {}
}

final class SourceWindowCloseRegistrationNSView: NSView {
    private lazy var closeDelegateProxy: WindowCloseDelegateProxy = WindowCloseDelegateProxy { _ in
        Self.shouldCloseSourceWindow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        closeDelegateProxy.install(on: window)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            closeDelegateProxy.restore()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    private static func shouldCloseSourceWindow() -> Bool {
        let activeScanningSessions: [ScanSession] = ScanWindowRegistry.shared.activeScanningSessions
        guard activeScanningSessions.isEmpty == false else {
            NSApp.terminate(nil)
            return false
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = "Cancel active scans before closing the source window?"
        alert.informativeText = activeScanningSessions.count == 1
            ? "One scan is still running. Disk Hog will keep the source window open after cancelling it."
            : "\(activeScanningSessions.count) scans are still running. Disk Hog will keep the source window open after cancelling them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Active Scans")
        alert.addButton(withTitle: "Keep Scanning")

        if alert.runModal() == .alertFirstButtonReturn {
            ScanWindowRegistry.shared.cancelActiveScans()
        }

        return false
    }
}

@MainActor
enum SourceFolderChooser {
    private static let preparedPanel: NSOpenPanel = {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"
        return panel
    }()
    private static var activePanel: NSOpenPanel?

    static func prepare() {
        _ = preparedPanel
    }

    static func chooseSource(completion: @escaping @MainActor (ScanSource?) -> Void) {
        guard activePanel == nil else {
            activePanel?.makeKeyAndOrderFront(nil)
            return
        }

        let panel: NSOpenPanel = preparedPanel
        activePanel = panel
        panel.begin { response in
            MainActor.assumeIsolated {
                let source: ScanSource?
                if response == .OK, let url: URL = panel.url {
                    let bookmarkData: Data? = try? url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    source = ScanSourceProvider.scanSource(for: url, bookmarkData: bookmarkData)
                } else {
                    source = nil
                }

                activePanel = nil
                completion(source)
            }
        }
    }
}
