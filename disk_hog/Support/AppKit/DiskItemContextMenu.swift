import AppKit

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
    var openWithMenuController: OpenWithMenuController?

    init(session: ScanSession? = nil) {
        self.session = session
    }

    @objc func openMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        DiskItemWorkspaceActions.open(payload.item)
    }

    @objc func openWithMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload,
              let applicationURL = payload.applicationURL else { return }
        DiskItemWorkspaceActions.open(payload.item, withApplicationAt: applicationURL)
    }

    @objc func revealMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        DiskItemWorkspaceActions.revealInFinder(payload.item)
    }

    @objc func refreshMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        session?.refresh(payload.item)
    }

    @objc func trashMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        if CleanupQueueStore.shared.isDirectlyQueued(payload.item) {
            DiskItemDeletionCoordinator.requestQueueUndo(of: payload.item)
        } else {
            DiskItemDeletionCoordinator.requestQueueing(of: payload.item, from: session)
        }
    }

    @objc func showInSelectionListMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        InspectorWindowController.shared.showSelectionList(for: payload.item, from: session)
    }

    @objc func showInspectorMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DiskItemContextMenuPayload else { return }
        InspectorWindowController.shared.showInformation(for: payload.item, from: session)
    }
}

@MainActor
enum DiskItemContextMenuBuilder {
    static func menu(
        for item: DiskItem?,
        actionTarget: DiskItemContextMenuActionTarget,
        treeActionsEnabled: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        populate(menu, with: item, actionTarget: actionTarget, treeActionsEnabled: treeActionsEnabled)
        return menu
    }

    static func populate(
        _ menu: NSMenu,
        with item: DiskItem?,
        actionTarget: DiskItemContextMenuActionTarget,
        treeActionsEnabled: Bool
    ) {
        menu.removeAllItems()
        guard let item, item.isSpecialItem == false else {
            let noItem = NSMenuItem(title: String(localized: "No Item Selected"), action: nil, keyEquivalent: "")
            noItem.isEnabled = false
            menu.addItem(noItem)
            return
        }

        menu.addItem(menuItem(
            title: String(localized: "Open"),
            action: #selector(DiskItemContextMenuActionTarget.openMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item)
        ))

        let openWithItem = NSMenuItem(title: String(localized: "Open With"), action: nil, keyEquivalent: "")
        let openWithMenuController = OpenWithMenuController(item: item, actionTarget: actionTarget)
        actionTarget.openWithMenuController = openWithMenuController
        openWithItem.submenu = openWithMenuController.makeMenu()
        menu.addItem(openWithItem)
        menu.addItem(.separator())

        menu.addItem(menuItem(
            title: String(localized: "Reveal in Finder"),
            action: #selector(DiskItemContextMenuActionTarget.revealMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item)
        ))

        let refreshItem = menuItem(
            title: String(localized: "Refresh"),
            action: #selector(DiskItemContextMenuActionTarget.refreshMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item)
        )
        refreshItem.toolTip = String(localized: "Synchronizes folder or file with Finder.")
        refreshItem.isEnabled = treeActionsEnabled
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let isDirectlyQueued = CleanupQueueStore.shared.isDirectlyQueued(item)
        let isAlreadyQueued = CleanupQueueStore.shared.contains(item)
        let trashItem = menuItem(
            title: CleanupQueueMenuPresentation.title(isDirectlyQueued: isDirectlyQueued),
            action: #selector(DiskItemContextMenuActionTarget.trashMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item),
            keyEquivalent: "t"
        )
        trashItem.isEnabled = treeActionsEnabled
            && CleanupQueueMenuPresentation.isEnabled(item: item, isDirectlyQueued: isDirectlyQueued, isAlreadyQueued: isAlreadyQueued)
        menu.addItem(trashItem)
        menu.addItem(.separator())

        menu.addItem(menuItem(
            title: String(localized: "Show Inspector"),
            action: #selector(DiskItemContextMenuActionTarget.showInspectorMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item)
        ))

        let selectionListItem = menuItem(
            title: String(localized: "Show Files in Selection List"),
            action: #selector(DiskItemContextMenuActionTarget.showInSelectionListMenuItem(_:)),
            target: actionTarget,
            payload: DiskItemContextMenuPayload(item: item)
        )
        selectionListItem.isEnabled = !item.isFolder && !(item.kindName ?? "").isEmpty
        menu.addItem(selectionListItem)
    }

    private static func menuItem(
        title: String,
        action: Selector,
        target: DiskItemContextMenuActionTarget,
        payload: DiskItemContextMenuPayload,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.representedObject = payload
        return item
    }
}
