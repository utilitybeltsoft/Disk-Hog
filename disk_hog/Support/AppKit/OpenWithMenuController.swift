import AppKit
import Foundation

@MainActor
final class OpenWithMenuController: NSObject, NSMenuDelegate {
    private let item: DiskItem
    private weak var actionTarget: DiskItemContextMenuActionTarget?
    private weak var menu: NSMenu?
    private var applications: [OpenWithApplication]?

    init(item: DiskItem, actionTarget: DiskItemContextMenuActionTarget) {
        self.item = item
        self.actionTarget = actionTarget
    }

    func makeMenu() -> NSMenu {
        let menu: NSMenu = NSMenu(title: String(localized: "Open With"))
        menu.delegate = self
        self.menu = menu
        installLoadingItem(in: menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let applications {
            populate(menu, with: applications)
            return
        }

        installLoadingItem(in: menu)
        OpenWithApplicationCache.shared.applications(for: item) { [weak self, weak menu] applications in
            guard let self, let menu else {
                return
            }
            self.applications = applications
            self.populate(menu, with: applications)
        }
    }

    private func installLoadingItem(in menu: NSMenu) {
        menu.removeAllItems()
        let loadingItem: NSMenuItem = NSMenuItem(
            title: String(localized: "Loading Applications…"),
            action: nil,
            keyEquivalent: ""
        )
        loadingItem.isEnabled = false
        menu.addItem(loadingItem)
    }

    private func populate(_ menu: NSMenu, with applications: [OpenWithApplication]) {
        menu.removeAllItems()
        guard let actionTarget else {
            return
        }

        guard !applications.isEmpty else {
            let unavailableItem: NSMenuItem = NSMenuItem(
                title: String(localized: "No Applications Available"),
                action: nil,
                keyEquivalent: ""
            )
            unavailableItem.isEnabled = false
            menu.addItem(unavailableItem)
            return
        }

        for (index, application) in applications.enumerated() {
            if index == 1, applications.first?.isDefaultApplication == true {
                menu.addItem(.separator())
            }

            let menuItem: NSMenuItem = NSMenuItem(
                title: application.displayName,
                action: #selector(DiskItemContextMenuActionTarget.openWithMenuItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = actionTarget
            menuItem.toolTip = application.url.path
            menuItem.representedObject = DiskItemContextMenuPayload(
                item: item,
                applicationURL: application.url
            )
            menu.addItem(menuItem)

            OpenWithApplicationIconCache.shared.icon(for: application.url) { [weak menuItem] image in
                image.size = NSSize(width: 16, height: 16)
                menuItem?.image = image
            }
        }
    }
}

private struct OpenWithApplication: Sendable {
    let url: URL
    let displayName: String
    let isDefaultApplication: Bool
}

@MainActor
private final class OpenWithApplicationCache {
    static let shared: OpenWithApplicationCache = OpenWithApplicationCache()

    private var applicationsByContentKey: [String: [OpenWithApplication]] = [:]
    private var waitingCompletions: [String: [([OpenWithApplication]) -> Void]] = [:]

    func applications(
        for item: DiskItem,
        completion: @escaping ([OpenWithApplication]) -> Void
    ) {
        let contentKey: String = Self.contentKey(for: item)
        if let applications: [OpenWithApplication] = applicationsByContentKey[contentKey] {
            completion(applications)
            return
        }

        if waitingCompletions[contentKey] != nil {
            waitingCompletions[contentKey, default: []].append(completion)
            return
        }
        waitingCompletions[contentKey] = [completion]

        let itemURL: URL = item.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let applications: [OpenWithApplication] = Self.findApplications(for: itemURL)
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.applicationsByContentKey[contentKey] = applications
                let completions: [([OpenWithApplication]) -> Void] = self.waitingCompletions.removeValue(forKey: contentKey) ?? []
                for completion in completions {
                    completion(applications)
                }
            }
        }
    }

    private static func contentKey(for item: DiskItem) -> String {
        item.isFolder
            ? "folder"
            : "extension:\(item.url.pathExtension.localizedLowercase)"
    }

    private nonisolated static func findApplications(for itemURL: URL) -> [OpenWithApplication] {
        let workspace: NSWorkspace = NSWorkspace.shared
        let defaultApplicationURL: URL? = workspace.urlForApplication(toOpen: itemURL)
        var applicationURLs: [URL] = workspace.urlsForApplications(toOpen: itemURL)
        if let defaultApplicationURL,
           !applicationURLs.contains(defaultApplicationURL) {
            applicationURLs.append(defaultApplicationURL)
        }

        let defaultPath: String? = defaultApplicationURL?.standardizedFileURL.path
        return applicationURLs
            .map { applicationURL in
                OpenWithApplication(
                    url: applicationURL,
                    displayName: FileManager.default.displayName(atPath: applicationURL.path),
                    isDefaultApplication: applicationURL.standardizedFileURL.path == defaultPath
                )
            }
            .sorted {
                if $0.isDefaultApplication != $1.isDefaultApplication {
                    return $0.isDefaultApplication
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }
}

@MainActor
private final class OpenWithApplicationIconCache {
    static let shared: OpenWithApplicationIconCache = OpenWithApplicationIconCache()

    private var iconsByURL: [URL: NSImage] = [:]

    func icon(for applicationURL: URL, completion: @escaping (NSImage) -> Void) {
        if let icon: NSImage = iconsByURL[applicationURL] {
            completion(icon)
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let icon: NSImage = NSWorkspace.shared.icon(forFile: applicationURL.path)
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.iconsByURL[applicationURL] = icon
                completion(icon)
            }
        }
    }
}
