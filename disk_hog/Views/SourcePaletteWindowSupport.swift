import AppKit
import SwiftUI

struct SourcePaletteCloseRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> SourcePaletteCloseRegistrationNSView {
        SourcePaletteCloseRegistrationNSView()
    }

    func updateNSView(_ nsView: SourcePaletteCloseRegistrationNSView, context: Context) {}
}

final class SourcePaletteCloseRegistrationNSView: NSView {
    private lazy var closeDelegateProxy: WindowCloseDelegateProxy = WindowCloseDelegateProxy { _ in
        Self.shouldCloseSourcePalette()
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

    private static func shouldCloseSourcePalette() -> Bool {
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

enum SourceFolderChooser {
    static func chooseSource() -> ScanSource? {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"

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
