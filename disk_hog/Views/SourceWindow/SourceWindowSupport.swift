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
    private static let panel: NSOpenPanel = {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"
        return panel
    }()

    static func chooseSource() -> ScanSource? {
        guard panel.runModal() == .OK, let url: URL = panel.url else {
            return nil
        }

        let bookmarkData: Data? = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return ScanSourceProvider.scanSource(for: url, bookmarkData: bookmarkData)
    }
}
