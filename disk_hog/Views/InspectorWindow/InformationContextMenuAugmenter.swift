import AppKit
import SwiftUI

struct InformationContextMenuAugmenter: NSViewRepresentable {
    let item: DiskItem
    let snapshot: FileInformationSnapshot?

    func makeCoordinator() -> InformationContextMenuCoordinator {
        InformationContextMenuCoordinator()
    }

    func makeNSView(context: Context) -> InformationContextMenuTrackingView {
        let view: InformationContextMenuTrackingView = InformationContextMenuTrackingView()
        context.coordinator.attach(to: view)
        context.coordinator.update(item: item, snapshot: snapshot)
        return view
    }

    func updateNSView(_ nsView: InformationContextMenuTrackingView, context: Context) {
        context.coordinator.update(item: item, snapshot: snapshot)
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

@MainActor
final class InformationContextMenuCoordinator: NSObject {
    private weak var trackingView: InformationContextMenuTrackingView?
    private var item: DiskItem?
    private var snapshot: FileInformationSnapshot?
    private var eventMonitor: Any?
    private var menuObserver: NSObjectProtocol?
    private var shouldAugmentNextMenu: Bool = false
    private var menuRequestID: UUID?

    func attach(to view: InformationContextMenuTrackingView) {
        trackingView = view
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.prepareForContextMenu(event)
            }
            return event
        }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.menuDidBeginTracking(notification)
            }
        }
    }

    func update(item: DiskItem, snapshot: FileInformationSnapshot?) {
        self.item = item
        self.snapshot = snapshot
    }

    func detach() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let menuObserver {
            NotificationCenter.default.removeObserver(menuObserver)
            self.menuObserver = nil
        }
        trackingView = nil
        shouldAugmentNextMenu = false
        menuRequestID = nil
    }

    private func prepareForContextMenu(_ event: NSEvent) {
        guard let trackingView,
              event.window === trackingView.window else {
            shouldAugmentNextMenu = false
            return
        }

        let location: NSPoint = trackingView.convert(event.locationInWindow, from: nil)
        shouldAugmentNextMenu = trackingView.bounds.contains(location)
        guard shouldAugmentNextMenu else {
            menuRequestID = nil
            return
        }

        let requestID: UUID = UUID()
        menuRequestID = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard self?.menuRequestID == requestID else {
                return
            }
            self?.shouldAugmentNextMenu = false
            self?.menuRequestID = nil
        }
    }

    private func menuDidBeginTracking(_ notification: Notification) {
        guard shouldAugmentNextMenu,
              let menu: NSMenu = notification.object as? NSMenu else {
            return
        }

        shouldAugmentNextMenu = false
        menuRequestID = nil
        addInformationCommands(to: menu)
    }

    private func addInformationCommands(to menu: NSMenu) {
        guard menu.item(withTitle: "Copy Information") == nil else {
            return
        }

        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        let copyItem: NSMenuItem = NSMenuItem(
            title: "Copy Information",
            action: #selector(copyInformation(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = snapshot != nil
        menu.addItem(copyItem)

        let revealItem: NSMenuItem = NSMenuItem(
            title: "Reveal in Finder",
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
                kindDescription: item.kindName ?? (item.isFolder ? "Folder" : "File")
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
