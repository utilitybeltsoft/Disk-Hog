import Combine

@MainActor
final class TreemapNavigationState: ObservableObject {
    @Published private(set) var baseRoot: DiskItem?
    @Published private(set) var zoomPath: [DiskItem] = []
    private var selectionAfterZoom: DiskItem?

    var zoomRoot: DiskItem? { zoomPath.last ?? baseRoot }
    var canZoomOut: Bool { zoomPath.count > 1 }

    func configure(baseRoot: DiskItem?) {
        guard self.baseRoot != baseRoot else { return }
        self.baseRoot = baseRoot
        zoomPath = baseRoot.map { [$0] } ?? []
        selectionAfterZoom = nil
    }

    /// - Parameter allowingFileFallback: When `item` is not itself a zoomable
    ///   folder, whether to zoom to its parent instead. Activation gestures
    ///   (double-click, outline `doubleAction`) pass `false` so a file behaves
    ///   identically to a plain click. The explicit "Zoom In" command (toolbar
    ///   button, its Return-key equivalent, and the menu command) passes
    ///   `true`, since selecting a file and asking to zoom in has nowhere else
    ///   to go but the file's parent.
    func canZoom(into item: DiskItem?, allowingFileFallback: Bool = false) -> Bool {
        zoomDestination(for: item, allowingFileFallback: allowingFileFallback) != nil
    }

    func zoom(into item: DiskItem?, allowingFileFallback: Bool = false) {
        guard let destination: ZoomDestination = zoomDestination(for: item, allowingFileFallback: allowingFileFallback) else { return }
        zoomPath = destination.path
        selectionAfterZoom = destination.selection
    }

    func zoomOut() {
        guard canZoomOut else { return }
        zoomPath.removeLast()
        selectionAfterZoom = zoomPath.last
    }

    func zoom(toPathIndex index: Int) {
        guard zoomPath.indices.contains(index) else { return }
        zoomPath = Array(zoomPath.prefix(through: index))
        selectionAfterZoom = zoomPath.last
    }

    func revealSelection(_ item: DiskItem?) {
        guard let item, let baseRoot else { return }
        // Treemap arrow navigation always produces an item below the current
        // zoom root.  Avoid re-walking the complete packed tree just to prove
        // that an in-scope selection needs no zoom adjustment.
        if let zoomRoot, contains(item.path, within: zoomRoot.path) {
            return
        }
        let selectionPath: [DiskItem] = baseRoot.descendantsMatchingAncestorPath(of: item)
        guard selectionPath.isEmpty == false else { return }
        // Land on the selected item's own parent folder (or the item itself, if it's
        // already the base root) rather than merely the nearest ancestor shared with
        // the current zoom - stopping at the shared ancestor can leave the item itself
        // still out of view, requiring a second, manual zoom to actually see it.
        let targetPath: [DiskItem] = selectionPath.count > 1 ? Array(selectionPath.dropLast()) : selectionPath
        guard targetPath != zoomPath else { return }
        zoomPath = targetPath
        selectionAfterZoom = nil
    }

    func consumeSelectionAfterZoom() -> DiskItem? {
        defer { selectionAfterZoom = nil }
        return selectionAfterZoom
    }

    private func zoomDestination(for item: DiskItem?, allowingFileFallback: Bool) -> ZoomDestination? {
        guard let item, item.isSpecialItem == false, let baseRoot else { return nil }
        let itemPath: [DiskItem] = baseRoot.descendantsMatchingAncestorPath(of: item)
        guard itemPath.isEmpty == false else { return nil }

        if item.isFolder, item.isPackage == false, item.childCount > 0 {
            guard item != zoomRoot else { return nil }
            return ZoomDestination(path: itemPath, selection: item)
        }

        guard allowingFileFallback,
              let parent: DiskItem = itemPath.dropLast().last,
              parent != zoomRoot else {
            return nil
        }
        return ZoomDestination(path: Array(itemPath.dropLast()), selection: item)
    }

    private func contains(_ itemPath: String, within rootPath: String) -> Bool {
        itemPath == rootPath
            || itemPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }
}

private struct ZoomDestination {
    let path: [DiskItem]
    let selection: DiskItem
}
