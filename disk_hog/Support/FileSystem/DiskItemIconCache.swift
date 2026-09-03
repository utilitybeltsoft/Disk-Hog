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

    /// Warms the cache for paths not yet loaded, off the main thread. Volume root icons in
    /// particular can be slow to resolve (spun-down external drives, network shares), and callers
    /// that fetch icons synchronously on first use (matching the rest of this app's convention)
    /// would otherwise block the main thread right when the user acts on that path - e.g. clicking
    /// a volume in the source list immediately after it appears.
    func prefetch(paths: [String]) {
        let loadIcon: IconLoader = loadIcon
        for path: String in paths {
            let key: NSString = path as NSString
            guard cache.object(forKey: key) == nil else {
                continue
            }
            Task.detached(priority: .utility) {
                let icon: NSImage = loadIcon(path)
                await MainActor.run {
                    guard self.cache.object(forKey: key) == nil else { return }
                    self.cache.setObject(icon, forKey: key)
                }
            }
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
