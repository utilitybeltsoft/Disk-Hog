import Combine

@MainActor
final class TreemapNavigationState: ObservableObject {
    @Published private(set) var baseRoot: DiskItem?
    @Published private(set) var zoomPath: [DiskItem] = []
    private var selectionAfterZoom: DiskItem?

    var zoomRoot: DiskItem? { zoomPath.last ?? baseRoot }
    var canZoomOut: Bool { zoomPath.count > 1 }

    func configure(baseRoot: DiskItem?) {
        guard self.baseRoot !== baseRoot else { return }
        self.baseRoot = baseRoot
        zoomPath = baseRoot.map { [$0] } ?? []
        selectionAfterZoom = nil
    }

    func canZoom(into item: DiskItem?) -> Bool {
        zoomTarget(for: item) != nil
    }

    func zoom(into item: DiskItem?) {
        guard let target: DiskItem = zoomTarget(for: item), let baseRoot else { return }
        zoomPath = baseRoot.descendantsMatchingAncestorPath(of: target)
        selectionAfterZoom = target
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
        let selectionPath: [DiskItem] = baseRoot.descendantsMatchingAncestorPath(of: item)
        guard selectionPath.isEmpty == false else { return }
        let sharedPathLength: Int = zip(zoomPath, selectionPath)
            .prefix { pair in pair.0 == pair.1 }
            .count
        guard sharedPathLength < zoomPath.count else { return }
        zoomPath = Array(selectionPath.prefix(max(sharedPathLength, 1)))
        selectionAfterZoom = nil
    }

    func consumeSelectionAfterZoom() -> DiskItem? {
        defer { selectionAfterZoom = nil }
        return selectionAfterZoom
    }

    private func zoomTarget(for item: DiskItem?) -> DiskItem? {
        guard let item, item.isSpecialItem == false, let baseRoot else { return nil }
        let path: [DiskItem] = baseRoot.descendantsMatchingAncestorPath(of: item)
        guard path.isEmpty == false else { return nil }
        let target: DiskItem
        if item.isFolder, item.isPackage == false, item.childCount > 0 {
            target = item
        } else if let parent: DiskItem = path.dropLast().last {
            target = parent
        } else {
            return nil
        }
        return target == zoomRoot ? nil : target
    }
}
