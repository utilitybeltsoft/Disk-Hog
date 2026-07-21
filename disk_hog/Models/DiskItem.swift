import Foundation

nonisolated struct DiskItemMetadata: Sendable {
    var url: URL
    var fileSystemName: String
    var displayNameOverride: String?
    var itemType: DiskItemType
    var allocatedSizeValue: UInt64
    var logicalSizeValue: UInt64
    var kindName: String?
    var isDirectory: Bool
    var isPackage: Bool
    var isAliasOrSymbolicLink: Bool
    var isHardlinkDuplicate: Bool

    init(
        url: URL,
        itemType: DiskItemType = .fileOrFolder,
        displayName: String? = nil,
        name: String? = nil,
        allocatedSizeValue: UInt64 = 0,
        logicalSizeValue: UInt64 = 0,
        kindName: String? = nil,
        isDirectory: Bool = false,
        isPackage: Bool = false,
        isAliasOrSymbolicLink: Bool = false,
        isHardlinkDuplicate: Bool = false
    ) {
        let lastPathComponent: String = name ?? url.lastPathComponent
        let fileSystemName: String = lastPathComponent.isEmpty ? url.path : lastPathComponent

        self.url = url
        self.fileSystemName = fileSystemName
        self.displayNameOverride = displayName == fileSystemName ? nil : displayName
        self.itemType = itemType
        self.allocatedSizeValue = allocatedSizeValue
        self.logicalSizeValue = logicalSizeValue
        self.kindName = kindName
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAliasOrSymbolicLink = isAliasOrSymbolicLink
        self.isHardlinkDuplicate = isHardlinkDuplicate
    }
}

nonisolated protocol DiskItemTreeNode {
    associatedtype ChildItem

    var itemMetadata: DiskItemMetadata { get }
    var itemChildren: [ChildItem] { get }
}

extension DiskItemTreeNode {
    nonisolated var children: [ChildItem] {
        itemChildren
    }

    nonisolated var childCount: Int {
        itemChildren.count
    }

    nonisolated var itemType: DiskItemType {
        itemMetadata.itemType
    }

    nonisolated var allocatedSizeValue: UInt64 {
        itemMetadata.allocatedSizeValue
    }

    nonisolated var logicalSizeValue: UInt64 {
        itemMetadata.logicalSizeValue
    }

    nonisolated var kindName: String? {
        itemMetadata.kindName
    }

    nonisolated var resolvedKindName: String {
        resolvedKindName(folderName: "Folder")
    }

    nonisolated func resolvedKindName(folderName: String) -> String {
        if let kindName: String = itemMetadata.kindName {
            return kindName
        }
        return isFolder && !isPackage ? folderName : ""
    }

    nonisolated var isDirectory: Bool {
        itemMetadata.isDirectory
    }

    nonisolated var isPackage: Bool {
        itemMetadata.isPackage
    }

    nonisolated var isAliasOrSymbolicLink: Bool {
        itemMetadata.isAliasOrSymbolicLink
    }

    nonisolated var isHardlinkDuplicate: Bool {
        itemMetadata.isHardlinkDuplicate
    }

    nonisolated var isSpecialItem: Bool {
        itemMetadata.itemType != .fileOrFolder
    }

    nonisolated var isFolder: Bool {
        itemMetadata.isDirectory && !itemMetadata.isAliasOrSymbolicLink
    }

    nonisolated var displayName: String {
        switch itemMetadata.itemType {
        case .fileOrFolder:
            return itemMetadata.displayNameOverride ?? itemMetadata.fileSystemName
        case .otherSpace:
            return "space occupied by other files and folders"
        case .freeSpace:
            return "free space on drive"
        }
    }

    nonisolated var name: String {
        switch itemMetadata.itemType {
        case .fileOrFolder:
            return itemMetadata.fileSystemName
        case .otherSpace, .freeSpace:
            return displayName
        }
    }

    nonisolated var path: String {
        isSpecialItem ? "" : itemMetadata.url.path
    }

    nonisolated var url: URL {
        itemMetadata.url
    }

    nonisolated func sizeValue(usePhysicalSize: Bool) -> UInt64 {
        usePhysicalSize ? itemMetadata.allocatedSizeValue : itemMetadata.logicalSizeValue
    }

    nonisolated func child(at index: Int) -> ChildItem {
        itemChildren[index]
    }
}

nonisolated final class DiskItem: Identifiable, Hashable, Sendable, DiskItemTreeNode {
    typealias ChildItem = DiskItem

    let itemMetadata: DiskItemMetadata
    private let childrenStorage: [DiskItem]
    private let isRootValue: Bool

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    init(
        url: URL,
        itemType: DiskItemType = .fileOrFolder,
        displayName: String? = nil,
        name: String? = nil,
        allocatedSizeValue: UInt64 = 0,
        logicalSizeValue: UInt64 = 0,
        kindName: String? = nil,
        isDirectory: Bool = false,
        isPackage: Bool = false,
        isAliasOrSymbolicLink: Bool = false,
        isHardlinkDuplicate: Bool = false,
        children: [DiskItem] = [],
        isRoot: Bool = true
    ) {
        self.itemMetadata = DiskItemMetadata(
            url: url,
            itemType: itemType,
            displayName: displayName,
            name: name,
            allocatedSizeValue: allocatedSizeValue,
            logicalSizeValue: logicalSizeValue,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isAliasOrSymbolicLink,
            isHardlinkDuplicate: isHardlinkDuplicate
        )
        self.childrenStorage = children
        self.isRootValue = isRoot
    }

    var itemChildren: [DiskItem] {
        childrenStorage
    }

    var isRoot: Bool {
        isRootValue
    }

    func descendantsMatchingAncestorPath(of item: DiskItem) -> [DiskItem] {
        guard containsPath(item.path) else {
            return []
        }

        if self === item {
            return [self]
        }

        for child: DiskItem in childrenStorage {
            let childPath: [DiskItem] = child.descendantsMatchingAncestorPath(of: item)
            if childPath.isEmpty == false {
                return [self] + childPath
            }
        }

        return []
    }

    func item(atPath candidatePath: String, allowAncestors: Bool = false) -> DiskItem? {
        guard isSpecialItem == false else {
            return nil
        }

        if path == candidatePath {
            return self
        }

        for child: DiskItem in childrenStorage where child.containsPath(candidatePath) {
            if let match: DiskItem = child.item(atPath: candidatePath, allowAncestors: allowAncestors) {
                return match
            }
        }

        return allowAncestors && containsPath(candidatePath) ? self : nil
    }

    func replacingSubtree(
        atPath targetPath: String,
        with replacement: DiskItem,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        if path == targetPath {
            return replacement.copy(isRoot: isRoot)
        }

        guard containsPath(targetPath) else {
            return nil
        }

        var updatedChildren: [DiskItem] = childrenStorage
        guard let childIndex: Int = updatedChildren.firstIndex(where: { $0.containsPath(targetPath) }),
              let updatedChild: DiskItem = updatedChildren[childIndex].replacingSubtree(
                atPath: targetPath,
                with: replacement,
                usePhysicalSize: usePhysicalSize
              ) else {
            return nil
        }

        updatedChildren[childIndex] = updatedChild
        return copyWithRecalculatedChildren(updatedChildren, usePhysicalSize: usePhysicalSize)
    }

    func removingSubtree(atPath targetPath: String, usePhysicalSize: Bool) -> DiskItem? {
        guard path != targetPath, containsPath(targetPath) else {
            return nil
        }

        var updatedChildren: [DiskItem] = childrenStorage
        if let childIndex: Int = updatedChildren.firstIndex(where: { $0.path == targetPath }) {
            updatedChildren.remove(at: childIndex)
            return copyWithRecalculatedChildren(updatedChildren, usePhysicalSize: usePhysicalSize)
        }

        guard let childIndex: Int = updatedChildren.firstIndex(where: { $0.containsPath(targetPath) }),
              let updatedChild: DiskItem = updatedChildren[childIndex].removingSubtree(
                atPath: targetPath,
                usePhysicalSize: usePhysicalSize
              ) else {
            return nil
        }

        updatedChildren[childIndex] = updatedChild
        return copyWithRecalculatedChildren(updatedChildren, usePhysicalSize: usePhysicalSize)
    }

    func scanCounts(includeSelf: Bool = true) -> (files: Int, folders: Int) {
        var files: Int = includeSelf && !isDirectory ? 1 : 0
        var folders: Int = includeSelf && isDirectory ? 1 : 0
        for child: DiskItem in childrenStorage where child.isSpecialItem == false {
            let childCounts: (files: Int, folders: Int) = child.scanCounts()
            files += childCounts.files
            folders += childCounts.folders
        }
        return (files, folders)
    }

    private func copyWithRecalculatedChildren(_ children: [DiskItem], usePhysicalSize: Bool) -> DiskItem {
        let sortedChildren: [DiskItem] = children.sorted {
            let leftSize: UInt64 = $0.sizeValue(usePhysicalSize: usePhysicalSize)
            let rightSize: UInt64 = $1.sizeValue(usePhysicalSize: usePhysicalSize)
            if leftSize != rightSize {
                return leftSize > rightSize
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedDescending
        }
        let allocatedSize: UInt64 = sortedChildren.reduce(0) { $0 + $1.allocatedSizeValue }
        let logicalSize: UInt64 = sortedChildren.reduce(0) { $0 + $1.logicalSizeValue }
        return copy(
            allocatedSizeValue: allocatedSize,
            logicalSizeValue: logicalSize,
            children: sortedChildren
        )
    }

    private func copy(
        allocatedSizeValue: UInt64? = nil,
        logicalSizeValue: UInt64? = nil,
        children: [DiskItem]? = nil,
        isRoot: Bool? = nil
    ) -> DiskItem {
        DiskItem(
            url: url,
            itemType: itemType,
            displayName: displayName,
            name: itemMetadata.fileSystemName,
            allocatedSizeValue: allocatedSizeValue ?? self.allocatedSizeValue,
            logicalSizeValue: logicalSizeValue ?? self.logicalSizeValue,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isAliasOrSymbolicLink,
            isHardlinkDuplicate: isHardlinkDuplicate,
            children: children ?? childrenStorage,
            isRoot: isRoot ?? isRootValue
        )
    }

    private func containsPath(_ candidatePath: String) -> Bool {
        if isSpecialItem {
            return candidatePath.isEmpty
        }

        if candidatePath == path {
            return true
        }

        let prefix: String = path.hasSuffix("/") ? path : path + "/"
        return candidatePath.hasPrefix(prefix)
    }

    static func == (leftItem: DiskItem, rightItem: DiskItem) -> Bool {
        leftItem === rightItem
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

nonisolated enum DiskItemType: Hashable, Sendable {
    case fileOrFolder
    case otherSpace
    case freeSpace
}
