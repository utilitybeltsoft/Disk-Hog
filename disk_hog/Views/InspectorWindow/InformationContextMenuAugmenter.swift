@preconcurrency import AppKit
import SwiftUI

struct InformationContextMenuAugmenter: NSViewRepresentable {
    let item: DiskItem
    let snapshot: FileInformationSnapshot?
    let kindDescription: String?

    func makeCoordinator() -> InformationContextMenuCoordinator {
        InformationContextMenuCoordinator()
    }

    func makeNSView(context: Context) -> InformationContextMenuTrackingView {
        let view: InformationContextMenuTrackingView = InformationContextMenuTrackingView()
        context.coordinator.attach(to: view)
        context.coordinator.update(
            item: item,
            snapshot: snapshot,
            kindDescription: kindDescription
        )
        return view
    }

    func updateNSView(_ nsView: InformationContextMenuTrackingView, context: Context) {
        context.coordinator.update(
            item: item,
            snapshot: snapshot,
            kindDescription: kindDescription
        )
    }

    static func dismantleNSView(
        _ nsView: InformationContextMenuTrackingView,
        coordinator: InformationContextMenuCoordinator
    ) {
        coordinator.detach()
    }
}

final class InformationContextMenuTrackingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

nonisolated private struct InformationContextMenuEvent: @unchecked Sendable {
    let value: NSEvent
}

@MainActor
final class InformationContextMenuCoordinator: NSObject {
    private weak var trackingView: InformationContextMenuTrackingView?
    private var item: DiskItem?
    private var snapshot: FileInformationSnapshot?
    private var kindDescription: String?
    private var eventMonitor: Any?

    func attach(to view: InformationContextMenuTrackingView) {
        trackingView = view
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let eventBox: InformationContextMenuEvent = InformationContextMenuEvent(value: event)
            let didConsumeEvent: Bool = MainActor.assumeIsolated { [weak self] in
                self?.handleContextMenuEvent(eventBox.value) == nil
            }
            return didConsumeEvent ? nil : event
        }
    }

    func update(
        item: DiskItem,
        snapshot: FileInformationSnapshot?,
        kindDescription: String? = nil
    ) {
        self.item = item
        self.snapshot = snapshot
        self.kindDescription = kindDescription
    }

    func detach() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        trackingView = nil
    }

    private func handleContextMenuEvent(_ event: NSEvent) -> NSEvent? {
        guard let trackingView,
              event.window === trackingView.window else {
            return event
        }

        let location: NSPoint = trackingView.convert(event.locationInWindow, from: nil)
        guard trackingView.bounds.contains(location),
              let window: NSWindow = event.window else {
            return event
        }

        let hitView: NSView = window.contentView?.hitTest(event.locationInWindow) ?? trackingView
        let menu: NSMenu = makeContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: hitView)
        return nil
    }

    func makeContextMenu() -> NSMenu {
        let menu: NSMenu = NSMenu()
        addInformationCommands(to: menu)
        return menu
    }

    private func addInformationCommands(to menu: NSMenu) {
        guard menu.item(withTitle: String(localized: "Copy Information")) == nil else {
            return
        }

        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        let copyItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Copy Information"),
            action: #selector(copyInformation(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = snapshot != nil
        menu.addItem(copyItem)

        let revealItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Reveal in Finder"),
            action: #selector(revealInFinder(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.isEnabled = item != nil
        menu.addItem(revealItem)
    }

    @objc private func copyInformation(_ sender: NSMenuItem) {
        guard let item, let snapshot else {
            return
        }

        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(
            snapshot.plainText(
                itemName: item.displayName,
                kindDescription: kindDescription
                    ?? item.kindName
                    ?? (item.isFolder
                        ? String(localized: "Folder")
                        : String(localized: "File"))
            ),
            forType: .string
        )
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let item else {
            return
        }

        DiskItemWorkspaceActions.revealInFinder(item)
    }
}
