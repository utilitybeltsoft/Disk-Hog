import AppKit

@MainActor
enum DiskItemWorkspaceActions {
    static func open(_ item: DiskItem) {
        NSWorkspace.shared.open(item.url)
    }

    static func open(_ item: DiskItem, withApplicationAt applicationURL: URL) {
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([item.url], withApplicationAt: applicationURL, configuration: configuration)
    }

    static func revealInFinder(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
