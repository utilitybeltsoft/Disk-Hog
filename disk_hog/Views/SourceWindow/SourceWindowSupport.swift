import AppKit
import OSLog

@MainActor
enum SourceFolderChooser {
    private static let logger = Logger(subsystem: "software.utilitybelt.diskhog", category: "FolderChooserPerformance")
    private static var preparedPanel: NSOpenPanel?
    private static var keyObserver: NSObjectProtocol?
    private static var nextRequest = 0

    /// Called only after permission setup clears; reuse a panel opened by the user.
    static func prepareAfterLaunch() {
        guard preparedPanel == nil else { return }
        _ = preparePanel(reason: "after-access-setup")
    }

    private static func preparePanel(reason: String) -> NSOpenPanel {
        if let preparedPanel { return preparedPanel }
        let started = ProcessInfo.processInfo.systemUptime
        logger.notice("prepare started reason=\(reason, privacy: .public)")
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Scan")
        preparedPanel = panel
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        logger.notice("prepare finished reason=\(reason, privacy: .public) duration_ms=\(elapsed, privacy: .public)")
        return panel
    }
    private static var activePanel: NSOpenPanel?

    static func chooseSource(completion: @escaping @MainActor (ScanSource?) -> Void) {
        guard activePanel == nil else {
            activePanel?.makeKeyAndOrderFront(nil)
            return
        }

        nextRequest += 1
        let request = nextRequest
        let started = ProcessInfo.processInfo.systemUptime
        let wasPrepared = preparedPanel != nil
        logger.notice("open requested request=\(request, privacy: .public) prepared=\(wasPrepared, privacy: .public)")
        let panel = preparePanel(reason: "user-request")
        activePanel = panel
        // Key-window notification is a presentation milestone, not a guarantee
        // that macOS has finished populating every file-picker row or sidebar item.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                logger.notice("panel became key request=\(request, privacy: .public) since_request_ms=\(elapsed, privacy: .public)")
                removeKeyObserver()
            }
        }
        let beginStarted = ProcessInfo.processInfo.systemUptime
        panel.begin { response in
            MainActor.assumeIsolated {
                removeKeyObserver()
                logger.notice("panel completed request=\(request, privacy: .public) accepted=\(response == .OK, privacy: .public)")
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
        let beginElapsed = (ProcessInfo.processInfo.systemUptime - beginStarted) * 1_000
        logger.notice("begin returned request=\(request, privacy: .public) duration_ms=\(beginElapsed, privacy: .public)")
    }

    private static func removeKeyObserver() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
    }
}
