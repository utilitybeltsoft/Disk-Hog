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

        var pendingItems: [DiskItem] = [self]
        var parentByItemID: [ObjectIdentifier: DiskItem] = [:]
        while let currentItem: DiskItem = pendingItems.popLast() {
            if currentItem === item {
                return Self.ancestorPath(
                    endingAt: currentItem,
                    parentByItemID: parentByItemID
                )
            }

            for child: DiskItem in currentItem.childrenStorage.reversed() where child.containsPath(item.path) {
                parentByItemID[ObjectIdentifier(child)] = currentItem
                pendingItems.append(child)
            }
        }

        return []
    }

    func item(atPath candidatePath: String, allowAncestors: Bool = false) -> DiskItem? {
        guard isSpecialItem == false else {
            return nil
        }

        var pendingItems: [(item: DiskItem, depth: Int)] = [(self, 0)]
        var deepestAncestor: (item: DiskItem, depth: Int)?
        while let current: (item: DiskItem, depth: Int) = pendingItems.popLast() {
            if current.item.path == candidatePath {
                return current.item
            }
            guard current.item.containsPath(candidatePath) else {
                continue
            }

            if deepestAncestor == nil || current.depth > deepestAncestor!.depth {
                deepestAncestor = current
            }
            for child: DiskItem in current.item.childrenStorage.reversed()
                where !child.isSpecialItem && child.containsPath(candidatePath) {
                pendingItems.append((child, current.depth + 1))
            }
        }

        return allowAncestors ? deepestAncestor?.item : nil
    }

    func replacingSubtree(
        atPath targetPath: String,
        with replacement: DiskItem,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        if path == targetPath {
            return replacement.copy(isRoot: isRoot)
        }

        guard let pathToTarget: [DiskItemPathFrame] = pathFrames(to: targetPath),
              let targetItem: DiskItem = pathToTarget.last?.child else {
            return nil
        }

        var updatedItem: DiskItem = replacement.copy(isRoot: targetItem.isRoot)
        for frame: DiskItemPathFrame in pathToTarget.reversed() {
            updatedItem = frame.parent.copyReplacingChild(
                at: frame.childIndex,
                with: updatedItem,
                usePhysicalSize: usePhysicalSize
            )
        }
        return updatedItem
    }

    func removingSubtree(atPath targetPath: String, usePhysicalSize: Bool) -> DiskItem? {
        guard path != targetPath,
              let pathToTarget: [DiskItemPathFrame] = pathFrames(to: targetPath),
              let removalFrame: DiskItemPathFrame = pathToTarget.last else {
            return nil
        }

        var updatedItem: DiskItem = removalFrame.parent.copyRemovingChild(at: removalFrame.childIndex)

        for frame: DiskItemPathFrame in pathToTarget.dropLast().reversed() {
            updatedItem = frame.parent.copyReplacingChild(
                at: frame.childIndex,
                with: updatedItem,
                usePhysicalSize: usePhysicalSize
            )
        }
        return updatedItem
    }

    func scanCounts(includeSelf: Bool = true) -> (files: Int, folders: Int) {
        var files: Int = 0
        var folders: Int = 0
        var pendingItems: [DiskItem] = includeSelf
            ? [self]
            : childrenStorage.reversed().filter { !$0.isSpecialItem }

        while let currentItem: DiskItem = pendingItems.popLast() {
            if currentItem.isDirectory {
                folders += 1
            } else {
                files += 1
            }
            for child: DiskItem in currentItem.childrenStorage.reversed() where !child.isSpecialItem {
                pendingItems.append(child)
            }
        }
        return (files, folders)
    }

    private func pathFrames(to targetPath: String) -> [DiskItemPathFrame]? {
        guard containsPath(targetPath) else {
            return nil
        }

        var frames: [DiskItemPathFrame] = []
        var currentItem: DiskItem = self
        while currentItem.path != targetPath {
            guard let childIndex: Int = currentItem.childrenStorage.firstIndex(where: {
                $0.containsPath(targetPath)
            }) else {
                return nil
            }

            let child: DiskItem = currentItem.childrenStorage[childIndex]
            frames.append(DiskItemPathFrame(parent: currentItem, childIndex: childIndex, child: child))
            currentItem = child
        }
        return frames
    }

    private static func ancestorPath(
        endingAt item: DiskItem,
        parentByItemID: [ObjectIdentifier: DiskItem]
    ) -> [DiskItem] {
        var path: [DiskItem] = []
        var currentItem: DiskItem? = item
        while let item: DiskItem = currentItem {
            path.append(item)
            currentItem = parentByItemID[ObjectIdentifier(item)]
        }
        return Array(path.reversed())
    }

    private func copyReplacingChild(
        at childIndex: Int,
        with replacement: DiskItem,
        usePhysicalSize: Bool
    ) -> DiskItem {
        let replacedChild: DiskItem = childrenStorage[childIndex]
        var updatedChildren: [DiskItem] = childrenStorage
        updatedChildren[childIndex] = replacement

        var updatedIndex: Int = childIndex
        while updatedIndex > 0,
              Self.isOrderedBefore(replacement, updatedChildren[updatedIndex - 1], usePhysicalSize: usePhysicalSize) {
            updatedChildren.swapAt(updatedIndex, updatedIndex - 1)
            updatedIndex -= 1
        }
        while updatedIndex + 1 < updatedChildren.count,
              Self.isOrderedBefore(updatedChildren[updatedIndex + 1], replacement, usePhysicalSize: usePhysicalSize) {
            updatedChildren.swapAt(updatedIndex, updatedIndex + 1)
            updatedIndex += 1
        }

        return copy(
            allocatedSizeValue: updatedTotal(
                current: allocatedSizeValue,
                removing: replacedChild.allocatedSizeValue,
                adding: replacement.allocatedSizeValue,
                children: updatedChildren,
                value: \.allocatedSizeValue
            ),
            logicalSizeValue: updatedTotal(
                current: logicalSizeValue,
                removing: replacedChild.logicalSizeValue,
                adding: replacement.logicalSizeValue,
                children: updatedChildren,
                value: \.logicalSizeValue
            ),
            children: updatedChildren
        )
    }

    private func copyRemovingChild(at childIndex: Int) -> DiskItem {
        let removedChild: DiskItem = childrenStorage[childIndex]
        var updatedChildren: [DiskItem] = childrenStorage
        updatedChildren.remove(at: childIndex)
        return copy(
            allocatedSizeValue: updatedTotal(
                current: allocatedSizeValue,
                removing: removedChild.allocatedSizeValue,
                adding: 0,
                children: updatedChildren,
                value: \.allocatedSizeValue
            ),
            logicalSizeValue: updatedTotal(
                current: logicalSizeValue,
                removing: removedChild.logicalSizeValue,
                adding: 0,
                children: updatedChildren,
                value: \.logicalSizeValue
            ),
            children: updatedChildren
        )
    }

    private func updatedTotal(
        current: UInt64,
        removing removedValue: UInt64,
        adding addedValue: UInt64,
        children: [DiskItem],
        value: KeyPath<DiskItem, UInt64>
    ) -> UInt64 {
        guard current >= removedValue else {
            return children.reduce(0) { $0 + $1[keyPath: value] }
        }
        return current - removedValue + addedValue
    }

    private static func isOrderedBefore(
        _ firstItem: DiskItem,
        _ secondItem: DiskItem,
        usePhysicalSize: Bool
    ) -> Bool {
        let firstSize: UInt64 = firstItem.sizeValue(usePhysicalSize: usePhysicalSize)
        let secondSize: UInt64 = secondItem.sizeValue(usePhysicalSize: usePhysicalSize)
        if firstSize != secondSize {
            return firstSize > secondSize
        }
        return firstItem.name.localizedStandardCompare(secondItem.name) == .orderedDescending
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

nonisolated private struct DiskItemPathFrame {
    let parent: DiskItem
    let childIndex: Int
    let child: DiskItem
}

nonisolated enum DiskItemType: Hashable, Sendable {
    case fileOrFolder
    case otherSpace
    case freeSpace
}
