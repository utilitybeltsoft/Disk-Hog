import AppKit
import Combine
import Foundation

@MainActor
final class ScanWindowCommandContext: ObservableObject {
    @Published var canOpenSelectedItem: Bool = false
    @Published var canRevealSelectedItem: Bool = false
    @Published var canSelectParentFolder: Bool = false
    @Published var canToggleFreeSpace: Bool = false
    @Published var canToggleOtherSpace: Bool = false
    @Published var showsFreeSpace: Bool = false
    @Published var showsOtherSpace: Bool = false
    #if FILE_MATCHING_DIAGNOSTICS
    @Published var canCopyMatchingFile: Bool = false
    #endif

    private weak var session: ScanSession?
    // DiskItem instances are short-lived flyweights over immutable packed storage.
    // Keep the command target alive independently of the selection view's instance.
    private var selectedItem: DiskItem?
    private weak var selectionCoordinator: ScanWindowSelectionCoordinator?

    init(session: ScanSession, selectionCoordinator: ScanWindowSelectionCoordinator) {
        self.session = session
        self.selectionCoordinator = selectionCoordinator
    }

    var commandSelectedItem: DiskItem? {
        selectedItem
    }

    func updateSelectedItem(_ selectedItem: DiskItem?) {
        updateSelectedItemAvailability(selectedItem)
    }

    func updateScanState() {
        guard let session: ScanSession else {
            canToggleFreeSpace = false
            canToggleOtherSpace = false
            showsFreeSpace = false
            showsOtherSpace = false
            #if FILE_MATCHING_DIAGNOSTICS
            canCopyMatchingFile = false
            #endif
            return
        }

        updateScanState(from: session)
    }

    func deactivate() {
        selectedItem = nil
        setIfChanged(\.canOpenSelectedItem, to: false)
        setIfChanged(\.canRevealSelectedItem, to: false)
        setIfChanged(\.canSelectParentFolder, to: false)
        setIfChanged(\.canToggleFreeSpace, to: false)
        setIfChanged(\.canToggleOtherSpace, to: false)
        setIfChanged(\.showsFreeSpace, to: false)
        setIfChanged(\.showsOtherSpace, to: false)
        #if FILE_MATCHING_DIAGNOSTICS
        setIfChanged(\.canCopyMatchingFile, to: false)
        #endif
    }

    private func updateScanState(from session: ScanSession) {
        canToggleFreeSpace = session.canToggleFreeSpace
        canToggleOtherSpace = session.canToggleOtherSpace
        showsFreeSpace = session.showsFreeSpace
        showsOtherSpace = session.showsOtherSpace
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

    func selectParentFolder() {
        guard canSelectParentFolder,
              let session: ScanSession,
              let rootItem: DiskItem = session.rootItem,
              let selectedItem: DiskItem,
              let parent: DiskItem = rootItem.descendantsMatchingAncestorPath(of: selectedItem).dropLast().last else {
            return
        }

        selectionCoordinator?.setSelectedItem(parent)
        updateSelectedItemAvailability(parent)
    }

    func toggleFreeSpace() {
        guard let session: ScanSession else {
            return
        }
        session.toggleFreeSpace()
        updateScanState(from: session)
    }

    func toggleOtherSpace() {
        guard let session: ScanSession else {
            return
        }
        session.toggleOtherSpace()
        updateScanState(from: session)
    }

    private func updateSelectedItemAvailability(_ item: DiskItem?) {
        selectedItem = item
        let canActOnItem: Bool = item?.isSpecialItem == false
        canOpenSelectedItem = canActOnItem
        canRevealSelectedItem = canActOnItem
        if let session: ScanSession,
           let rootItem: DiskItem = session.rootItem,
           let item: DiskItem {
            canSelectParentFolder = rootItem.descendantsMatchingAncestorPath(of: item).count > 1
        } else {
            canSelectParentFolder = false
        }
    }

    private func setIfChanged(_ keyPath: ReferenceWritableKeyPath<ScanWindowCommandContext, Bool>, to value: Bool) {
        guard self[keyPath: keyPath] != value else {
            return
        }
        self[keyPath: keyPath] = value
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() {
        guard canCopyMatchingFile else {
            return
        }

        session?.exportTreemapInputDiagnostics()
        if let session: ScanSession {
            updateScanState(from: session)
        }
    }
    #endif
}

@MainActor
final class ScanWindowCommandState: ObservableObject {
    static let shared: ScanWindowCommandState = ScanWindowCommandState()

    private weak var activeContext: ScanWindowCommandContext?
    private var activeContextCancellable: AnyCancellable?

    init() {}

    var canOpenSelectedItem: Bool { activeContext?.canOpenSelectedItem ?? false }
    var canRevealSelectedItem: Bool { activeContext?.canRevealSelectedItem ?? false }
    var canSelectParentFolder: Bool { activeContext?.canSelectParentFolder ?? false }
    var canToggleFreeSpace: Bool { activeContext?.canToggleFreeSpace ?? false }
    var canToggleOtherSpace: Bool { activeContext?.canToggleOtherSpace ?? false }
    var showsFreeSpace: Bool { activeContext?.showsFreeSpace ?? false }
    var showsOtherSpace: Bool { activeContext?.showsOtherSpace ?? false }
    #if FILE_MATCHING_DIAGNOSTICS
    var canCopyMatchingFile: Bool { activeContext?.canCopyMatchingFile ?? false }
    #endif

    var commandSelectedItem: DiskItem? {
        activeContext?.commandSelectedItem
    }

    func activate(_ context: ScanWindowCommandContext) {
        guard activeContext !== context else {
            return
        }

        activeContext = context
        activeContextCancellable = context.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }

    func deactivate(if context: ScanWindowCommandContext? = nil) {
        if let context, activeContext !== context {
            return
        }
        guard activeContext != nil else {
            return
        }

        activeContext = nil
        activeContextCancellable = nil
        objectWillChange.send()
    }

    func openSelectedItem() {
        activeContext?.openSelectedItem()
    }

    func revealSelectedItemInFinder() {
        activeContext?.revealSelectedItemInFinder()
    }

    func selectParentFolder() {
        activeContext?.selectParentFolder()
    }

    func toggleFreeSpace() {
        activeContext?.toggleFreeSpace()
    }

    func toggleOtherSpace() {
        activeContext?.toggleOtherSpace()
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() {
        activeContext?.copyMatchingFile()
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
    var openWithMenuController: OpenWithMenuController?

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

        if CleanupQueueStore.shared.isDirectlyQueued(payload.item) {
            DiskItemDeletionCoordinator.requestQueueUndo(of: payload.item)
        } else {
            DiskItemDeletionCoordinator.requestQueueing(
                of: payload.item,
                from: session
            )
        }
    }

    @objc func showInSelectionListMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

        InspectorWindowController.shared.showSelectionList(for: payload.item, from: session)
    }

    @objc func showInspectorMenuItem(_ sender: NSMenuItem) {
        guard let payload: DiskItemContextMenuPayload = sender.representedObject as? DiskItemContextMenuPayload else {
            return
        }

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
            let noItem: NSMenuItem = NSMenuItem(
                title: String(localized: "No Item Selected"),
                action: nil,
                keyEquivalent: ""
            )
            noItem.isEnabled = false
            menu.addItem(noItem)
            return
        }

        let openItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Open"),
            action: #selector(DiskItemContextMenuActionTarget.openMenuItem(_:)),
            keyEquivalent: ""
        )
        openItem.target = actionTarget
        openItem.representedObject = DiskItemContextMenuPayload(item: item)
        menu.addItem(openItem)

        let openWithItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Open With"),
            action: nil,
            keyEquivalent: ""
        )
        let openWithMenuController: OpenWithMenuController = OpenWithMenuController(
            item: item,
            actionTarget: actionTarget
        )
        actionTarget.openWithMenuController = openWithMenuController
        openWithItem.submenu = openWithMenuController.makeMenu()
        menu.addItem(openWithItem)

        menu.addItem(.separator())

        let revealItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Reveal in Finder"),
            action: #selector(DiskItemContextMenuActionTarget.revealMenuItem(_:)),
            keyEquivalent: ""
        )
        revealItem.target = actionTarget
        revealItem.representedObject = DiskItemContextMenuPayload(item: item)
        menu.addItem(revealItem)

        let refreshItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Refresh"),
            action: #selector(DiskItemContextMenuActionTarget.refreshMenuItem(_:)),
            keyEquivalent: ""
        )
        refreshItem.target = actionTarget
        refreshItem.representedObject = DiskItemContextMenuPayload(item: item)
        refreshItem.toolTip = String(localized: "Synchronizes folder or file with Finder.")
        refreshItem.isEnabled = treeActionsEnabled
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let isDirectlyQueued: Bool = CleanupQueueStore.shared.isDirectlyQueued(item)
        let isAlreadyQueued: Bool = CleanupQueueStore.shared.contains(item)
        let trashItem: NSMenuItem = NSMenuItem(
            title: isDirectlyQueued
                ? String(localized: "Already Queued for Finder Trash: Undo")
                : String(localized: "Add to Cleanup Queue"),
            action: #selector(DiskItemContextMenuActionTarget.trashMenuItem(_:)),
            keyEquivalent: "t"
        )
        trashItem.target = actionTarget
        trashItem.representedObject = DiskItemContextMenuPayload(item: item)
        trashItem.isEnabled = treeActionsEnabled
            && (!isAlreadyQueued || isDirectlyQueued)
            && DiskItemDeletionPolicy.canDelete(item)
        menu.addItem(trashItem)

        menu.addItem(.separator())

        let showInspectorItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Show Inspector"),
            action: #selector(DiskItemContextMenuActionTarget.showInspectorMenuItem(_:)),
            keyEquivalent: ""
        )
        showInspectorItem.target = actionTarget
        showInspectorItem.representedObject = DiskItemContextMenuPayload(item: item)
        menu.addItem(showInspectorItem)

        let selectionListItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Show Files in Selection List"),
            action: #selector(DiskItemContextMenuActionTarget.showInSelectionListMenuItem(_:)),
            keyEquivalent: ""
        )
        selectionListItem.target = actionTarget
        selectionListItem.representedObject = DiskItemContextMenuPayload(item: item)
        selectionListItem.isEnabled = !item.isFolder && !(item.kindName ?? "").isEmpty
        menu.addItem(selectionListItem)
    }

}
