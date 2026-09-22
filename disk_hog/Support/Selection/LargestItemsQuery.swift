import Foundation

nonisolated enum LargestItemsCategory: String, CaseIterable, Sendable {
    case files, folders

    func includes(_ item: DiskItem, lookInsidePackages: Bool) -> Bool {
        guard !item.isSpecialItem else { return false }
        let opaquePackage = item.isFolder && item.isPackage && !lookInsidePackages
        switch self {
        case .files: return !item.isFolder || opaquePackage
        case .folders: return item.isFolder && !opaquePackage
        }
    }
}

nonisolated enum LargestItemsDepth: String, CaseIterable, Sendable {
    case descendants, immediateChildren
}

nonisolated struct LargestItemsQuery: Hashable, Sendable {
    static let initialLimit = 1_000
    static let maximumLimit = 10_000
    var category: LargestItemsCategory = .files
    var depth: LargestItemsDepth = .descendants
    var usesPhysicalSize = true
    var lookInsidePackages = false
    var kind: String?
    var searchText = ""
    var searchScope: SelectionListSearchScope = .all
    var limit = initialLimit

    var boundedLimit: Int { min(max(limit, 1), Self.maximumLimit) }
}
