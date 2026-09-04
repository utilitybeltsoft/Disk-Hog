import AppKit

@MainActor
enum SourceFolderChooser {
    private static let preparedPanel: NSOpenPanel = {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Scan")
        return panel
    }()
    private static var activePanel: NSOpenPanel?

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
