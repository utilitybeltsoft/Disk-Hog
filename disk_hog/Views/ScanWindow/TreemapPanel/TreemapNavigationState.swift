import Combine

@MainActor
final class TreemapNavigationState: ObservableObject {
    @Published private(set) var baseRoot: DiskItem?
    @Published private(set) var zoomPath: [DiskItem] = []

    var zoomRoot: DiskItem? { zoomPath.last ?? baseRoot }
    var canZoomOut: Bool { zoomPath.count > 1 }

    func configure(baseRoot: DiskItem?) {
        guard self.baseRoot !== baseRoot else { return }
        self.baseRoot = baseRoot
        zoomPath = baseRoot.map { [$0] } ?? []
    }

    func canZoom(into item: DiskItem?) -> Bool {
        guard let item, item.isSpecialItem == false,
              item.isFolder, item.isPackage == false, item.childCount > 0,
              let baseRoot else { return false }
        return baseRoot.descendantsMatchingAncestorPath(of: item).isEmpty == false
    }

    func zoom(into item: DiskItem?) {
        guard canZoom(into: item), let item, let baseRoot else { return }
        zoomPath = baseRoot.descendantsMatchingAncestorPath(of: item)
    }

    func zoomOut() {
        guard canZoomOut else { return }
        zoomPath.removeLast()
    }

    func zoom(toPathIndex index: Int) {
        guard zoomPath.indices.contains(index) else { return }
        zoomPath = Array(zoomPath.prefix(through: index))
    }
}
