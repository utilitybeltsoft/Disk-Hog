import AppKit
import Combine
import Foundation

@MainActor
final class ScanWindowCommandState: ObservableObject {
    static let shared: ScanWindowCommandState = ScanWindowCommandState()

    @Published var canOpenSelectedItem: Bool = false
    @Published var canRevealSelectedItem: Bool = false
    #if FILE_MATCHING_DIAGNOSTICS
    @Published var canCopyMatchingFile: Bool = false
    #endif

    private weak var activeSession: ScanSession?
    private weak var selectedItem: DiskItem?

    private init() {}

    func activate(session: ScanSession, selectedItem: DiskItem?) {
        activeSession = session
        updateSelectedItemAvailability(selectedItem)
        updateScanState(from: session)
    }

    func updateSelectedItem(_ item: DiskItem?, from session: ScanSession) {
        guard activeSession === session else {
            return
        }

        updateSelectedItemAvailability(item)
    }

    func updateScanState(from session: ScanSession) {
        guard activeSession === session else {
            return
        }

        #if FILE_MATCHING_DIAGNOSTICS
        canCopyMatchingFile = session.rootItem != nil && session.diagnosticsExportState.isWriting == false
        #endif
    }

    func openSelectedItem() {
        guard canOpenSelectedItem, let selectedItem: DiskItem else {
            return
        }

        DiskItemWorkspaceActions.open(selectedItem)
    }

    func revealSelectedItemInFinder() {
        guard canRevealSelectedItem, let selectedItem: DiskItem else {
            return
        }

        DiskItemWorkspaceActions.revealInFinder(selectedItem)
    }

    private func updateSelectedItemAvailability(_ item: DiskItem?) {
        selectedItem = item
        let canActOnItem: Bool = item?.isSpecialItem == false
        canOpenSelectedItem = canActOnItem
        canRevealSelectedItem = canActOnItem
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() {
        guard canCopyMatchingFile else {
            return
        }

        activeSession?.exportTreemapInputDiagnostics()
        if let activeSession: ScanSession {
            updateScanState(from: activeSession)
        }
    }
    #endif
}

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

@MainActor
final class DiskItemContextMenuPayload: NSObject {
    let item: DiskItem
    let applicationURL: URL?

    init(item: DiskItem, applicationURL: URL? = nil) {
        self.item = item
        self.applicationURL = applicationURL
    }
}

@MainActor
final class DiskItemContextMenuActionTarget: NSObject {
    weak var session: ScanSession?

    init(session: ScanSession? = nil) {
        self.session = session
    }

    @objc func openMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

        DiskItemWorkspaceActions.open(payload.item)
    }

    @objc func openWithMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload,
              let applicationURL: URL = payload.applicationURL else {
            return
        }

        DiskItemWorkspaceActions.open(payload.item, withApplicationAt: applicationURL)
    }

    @objc func revealMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

        DiskItemWorkspaceActions.revealInFinder(payload.item)
    }

    @objc func refreshMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

        session?.refresh(payload.item)
    }

    @objc func trashMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

        session?.moveToTrash(payload.item)
    }
}

@MainActor
enum DiskItemContextMenuBuilder {
    static func menu(
        for item: DiskItem?,
        actionTarget: DiskItemContextMenuActionTarget,
        treeActionsEnabled: Bool
    ) -> NSMenu {
        let menu: NSMenu = NSMenu()
        populate(
            menu,
            with: item,
            actionTarget: actionTarget,
            treeActionsEnabled: treeActionsEnabled
        )
        return menu
    }

    static func populate(
        _ menu: NSMenu,
        with item: DiskItem?,
        actionTarget: DiskItemContextMenuActionTarget,
        treeActionsEnabled: Bool
    ) {
        menu.removeAllItems()

        guard let item: DiskItem = item, item.isSpecialItem == false else {
            let noItem: NSMenuItem = NSMenuItem(title: "No Item Selected", action: nil, keyEquivalent: "")
            noItem.isEnabled = false
            menu.addItem(noItem)
            return
        }

        let openItem: NSMenuItem = NSMenuItem(
            title: "Open",
            action: #selector(DiskItemContextMenuActionTarget.openMenuItem(_:)),
            keyEquivalent: ""
        )
        openItem.target = actionTarget
        openItem.representedObject = DiskItemContextMenuPayload(item: item)
        menu.addItem(openItem)

        let openWithItem: NSMenuItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWithItem.submenu = openWithSubmenu(for: item, actionTarget: actionTarget)
        menu.addItem(openWithItem)

        menu.addItem(.separator())

        let revealItem: NSMenuItem = NSMenuItem(
            title: "Reveal in Finder",
            action: #selector(DiskItemContextMenuActionTarget.revealMenuItem(_:)),
            keyEquivalent: ""
        )
        revealItem.target = actionTarget
        revealItem.representedObject = DiskItemContextMenuPayload(item: item)
        menu.addItem(revealItem)

        let refreshItem: NSMenuItem = NSMenuItem(
            title: "Refresh",
            action: #selector(DiskItemContextMenuActionTarget.refreshMenuItem(_:)),
            keyEquivalent: ""
        )
        refreshItem.target = actionTarget
        refreshItem.representedObject = DiskItemContextMenuPayload(item: item)
        refreshItem.toolTip = "Synchronizes folder or file with Finder."
        refreshItem.isEnabled = treeActionsEnabled
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let trashItem: NSMenuItem = NSMenuItem(
            title: "Move To Trash",
            action: #selector(DiskItemContextMenuActionTarget.trashMenuItem(_:)),
            keyEquivalent: ""
        )
        trashItem.target = actionTarget
        trashItem.representedObject = DiskItemContextMenuPayload(item: item)
        trashItem.isEnabled = treeActionsEnabled && !item.isRoot
        menu.addItem(trashItem)

        menu.addItem(.separator())

        let selectionListItem: NSMenuItem = NSMenuItem(title: "Show Files in Selection List", action: nil, keyEquivalent: "")
        selectionListItem.isEnabled = false
        menu.addItem(selectionListItem)
    }

    private static func openWithSubmenu(
        for item: DiskItem,
        actionTarget: DiskItemContextMenuActionTarget
    ) -> NSMenu {
        let submenu: NSMenu = NSMenu(title: "Open With")
        var addedApplicationURLs: Set<URL> = []

        if let defaultApplicationURL: URL = NSWorkspace.shared.urlForApplication(toOpen: item.url) {
            addOpenWithItem(
                to: submenu,
                title: displayName(forApplicationAt: defaultApplicationURL),
                applicationURL: defaultApplicationURL,
                item: item,
                actionTarget: actionTarget
            )
            addedApplicationURLs.insert(defaultApplicationURL)
            submenu.addItem(.separator())
        }

        let applicationURLs: [URL] = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
            .filter { addedApplicationURLs.contains($0) == false }
            .sorted { displayName(forApplicationAt: $0).localizedStandardCompare(displayName(forApplicationAt: $1)) == .orderedAscending }

        for applicationURL: URL in applicationURLs {
            addOpenWithItem(
                to: submenu,
                title: displayName(forApplicationAt: applicationURL),
                applicationURL: applicationURL,
                item: item,
                actionTarget: actionTarget
            )
        }

        if submenu.items.isEmpty {
            let unavailableItem: NSMenuItem = NSMenuItem(title: "No Applications Available", action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            submenu.addItem(unavailableItem)
        }

        return submenu
    }

    private static func addOpenWithItem(
        to menu: NSMenu,
        title: String,
        applicationURL: URL,
        item: DiskItem,
        actionTarget: DiskItemContextMenuActionTarget
    ) {
        let menuItem: NSMenuItem = NSMenuItem(
            title: title,
            action: #selector(DiskItemContextMenuActionTarget.openWithMenuItem(_:)),
            keyEquivalent: ""
        )
        menuItem.target = actionTarget
        menuItem.toolTip = applicationURL.path
        menuItem.representedObject = DiskItemContextMenuPayload(item: item, applicationURL: applicationURL)

        let icon: NSImage = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 16, height: 16)
        menuItem.image = icon

        menu.addItem(menuItem)
    }

    private static func displayName(forApplicationAt applicationURL: URL) -> String {
        FileManager.default.displayName(atPath: applicationURL.path)
    }
}
