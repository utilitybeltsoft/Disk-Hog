import AppKit

@MainActor
final class DiskItemIconCache {
    typealias IconLoader = (String) -> NSImage

    static let shared: DiskItemIconCache = DiskItemIconCache()

    private let cache: NSCache<NSString, NSImage>
    private let loadIcon: IconLoader

    init(
        countLimit: Int = 4_096,
        loadIcon: @escaping IconLoader = { NSWorkspace.shared.icon(forFile: $0) }
    ) {
        let cache: NSCache<NSString, NSImage> = NSCache()
        cache.countLimit = countLimit
        self.cache = cache
        self.loadIcon = loadIcon
    }

    func icon(for item: DiskItem) -> NSImage {
        icon(forFile: item.path)
    }

    func icon(forFile path: String) -> NSImage {
        let key: NSString = path as NSString
        if let cachedIcon: NSImage = cache.object(forKey: key) {
            return cachedIcon
        }

        let icon: NSImage = loadIcon(path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
