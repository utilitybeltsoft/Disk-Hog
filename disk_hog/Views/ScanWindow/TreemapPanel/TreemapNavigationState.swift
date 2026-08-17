import Combine

@MainActor
final class TreemapNavigationState: ObservableObject {
    @Published private(set) var baseRoot: DiskItem?
    @Published private(set) var zoomPath: [DiskItem] = []
    @Published private(set) var previewRoot: DiskItem?
    @Published private(set) var isPreviewActive: Bool = false

    var zoomRoot: DiskItem? { zoomPath.last ?? baseRoot }
    var canZoomOut: Bool { zoomPath.count > 1 }

    func configure(baseRoot: DiskItem?) {
        guard self.baseRoot !== baseRoot else { return }
        self.baseRoot = baseRoot
        zoomPath = baseRoot.map { [$0] } ?? []
        previewRoot = nil
        isPreviewActive = false
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
        previewRoot = nil
        isPreviewActive = false
    }

    func zoomOut() {
        guard canZoomOut else { return }
        zoomPath.removeLast()
        previewRoot = nil
        isPreviewActive = false
    }

    func zoom(toPathIndex index: Int) {
        guard zoomPath.indices.contains(index) else { return }
        zoomPath = Array(zoomPath.prefix(through: index))
        previewRoot = nil
        isPreviewActive = false
    }

    func updatePreviewRoot(from item: DiskItem?) {
        guard isPreviewActive == false else { return }
        previewRoot = canZoom(into: item) ? item : nil
    }

    func beginPreview() {
        guard previewRoot != nil else { return }
        isPreviewActive = true
    }

    func endPreview() {
        isPreviewActive = false
    }

    func commitPreviewZoom(into item: DiskItem) {
        guard isPreviewActive else { return }
        zoom(into: item)
        endPreview()
    }
}
