import AppKit
import Foundation

@MainActor
final class OpenWithMenuController: NSObject, NSMenuDelegate {
    private let item: DiskItem
    private weak var actionTarget: DiskItemContextMenuActionTarget?
    private weak var menu: NSMenu?

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
        installLoadingItem(in: menu)
        OpenWithApplicationCache.shared.applications(for: item) { [weak self, weak menu] applications in
            guard let self, let menu else {
                return
            }
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
                menuItem?.image = image
            }
        }
    }
}

struct OpenWithApplication: Sendable {
    let url: URL
    let displayName: String
    let isDefaultApplication: Bool
}

@MainActor
final class OpenWithApplicationCache {
    static let shared: OpenWithApplicationCache = OpenWithApplicationCache()

    private let cache: OpenWithLookupCache<[OpenWithApplication]>
    private let loader: @MainActor (URL, @escaping @MainActor ([OpenWithApplication]) -> Void) -> Void

    init(cache: OpenWithLookupCache<[OpenWithApplication]>? = nil,
         loader: @escaping @MainActor (URL, @escaping @MainActor ([OpenWithApplication]) -> Void) -> Void = OpenWithApplicationCache.load) {
        self.cache = cache ?? OpenWithLookupCache(capacity: 128)
        self.loader = loader
    }

    func applications(for item: DiskItem, completion: @escaping @MainActor ([OpenWithApplication]) -> Void) {
        let url = item.url.standardizedFileURL
        cache.value(for: url.path, load: { [loader] completion in loader(url, completion) }, completion: completion)
    }

    private static func load(_ url: URL, completion: @escaping @MainActor ([OpenWithApplication]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let applications = findApplications(for: url)
            DispatchQueue.main.async { completion(applications) }
        }
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
final class OpenWithApplicationIconCache {
    static let shared = OpenWithApplicationIconCache()
    private let cache: OpenWithLookupCache<NSImage>
    private let loader: @MainActor (URL, @escaping @MainActor (NSImage) -> Void) -> Void

    init(cache: OpenWithLookupCache<NSImage>? = nil,
         loader: @escaping @MainActor (URL, @escaping @MainActor (NSImage) -> Void) -> Void = OpenWithApplicationIconCache.load) {
        self.cache = cache ?? OpenWithLookupCache(capacity: 256)
        self.loader = loader
    }

    func icon(for applicationURL: URL, completion: @escaping @MainActor (NSImage) -> Void) {
        let url = applicationURL.standardizedFileURL
        cache.value(for: url.path, load: { [loader] completion in loader(url, completion) }, completion: completion)
    }

    private static func load(_ url: URL, completion: @escaping @MainActor (NSImage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            DispatchQueue.main.async { completion(icon) }
        }
    }
}
