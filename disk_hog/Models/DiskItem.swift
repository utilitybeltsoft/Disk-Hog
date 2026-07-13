import Foundation

nonisolated final class DiskItem: Identifiable, Hashable, Sendable {
    private let childrenStorage: [DiskItem]
    private let fileSystemName: String
    private let displayNameOverride: String?
    private let urlValue: URL
    private let isRootValue: Bool

    let itemType: DiskItemType
    let allocatedSizeValue: UInt64
    let logicalSizeValue: UInt64
    let kindName: String?
    let isDirectory: Bool
    let isPackage: Bool
    let isAliasOrSymbolicLink: Bool
    let isHardlinkDuplicate: Bool

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
        let lastPathComponent: String = name ?? url.lastPathComponent
        self.fileSystemName = lastPathComponent.isEmpty ? url.path : lastPathComponent
        self.displayNameOverride = displayName == self.fileSystemName ? nil : displayName
        self.urlValue = url
        self.isRootValue = isRoot
        self.itemType = itemType
        self.allocatedSizeValue = allocatedSizeValue
        self.logicalSizeValue = logicalSizeValue
        self.kindName = kindName
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAliasOrSymbolicLink = isAliasOrSymbolicLink
        self.isHardlinkDuplicate = isHardlinkDuplicate
        self.childrenStorage = children
    }

    var children: [DiskItem] {
        childrenStorage
    }

    var childCount: Int {
        childrenStorage.count
    }

    var isRoot: Bool {
        isRootValue
    }

    var isSpecialItem: Bool {
        itemType != .fileOrFolder
    }

    var isFolder: Bool {
        isDirectory && !isAliasOrSymbolicLink
    }

    var displayName: String {
        switch itemType {
        case .fileOrFolder:
            return displayNameOverride ?? fileSystemName
        case .otherSpace:
            return "space occupied by other files and folders"
        case .freeSpace:
            return "free space on drive"
        }
    }

    var name: String {
        switch itemType {
        case .fileOrFolder:
            return fileSystemName
        case .otherSpace, .freeSpace:
            return displayName
        }
    }

    var path: String {
        isSpecialItem ? "" : urlValue.path
    }

    var url: URL {
        urlValue
    }

    func sizeValue(usePhysicalSize: Bool) -> UInt64 {
        usePhysicalSize ? allocatedSizeValue : logicalSizeValue
    }

    func child(at index: Int) -> DiskItem {
        childrenStorage[index]
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
            url: urlValue,
            itemType: itemType,
            displayName: displayName,
            name: fileSystemName,
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

// Builder instances are mutable scanner-local construction state. Top-level
// scan tasks transfer their builders back exactly once, then the root is frozen
// into immutable Sendable DiskItem values before reaching UI code.
nonisolated final class DiskItemBuilder: @unchecked Sendable {
    private var childrenStorage: [DiskItemBuilder]
    private let urlValue: URL
    private let fileSystemName: String
    private let displayNameOverride: String?

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
        self.childrenStorage = []
        self.urlValue = url
        let lastPathComponent: String = name ?? url.lastPathComponent
        self.fileSystemName = lastPathComponent.isEmpty ? url.path : lastPathComponent
        self.displayNameOverride = displayName == self.fileSystemName ? nil : displayName
        self.itemType = itemType
        self.allocatedSizeValue = allocatedSizeValue
        self.logicalSizeValue = logicalSizeValue
        self.kindName = kindName
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAliasOrSymbolicLink = isAliasOrSymbolicLink
        self.isHardlinkDuplicate = isHardlinkDuplicate
    }

    var children: [DiskItemBuilder] {
        childrenStorage
    }

    var childCount: Int {
        childrenStorage.count
    }

    var isSpecialItem: Bool {
        itemType != .fileOrFolder
    }

    var isFolder: Bool {
        isDirectory && !isAliasOrSymbolicLink
    }

    var displayName: String {
        switch itemType {
        case .fileOrFolder:
            return displayNameOverride ?? fileSystemName
        case .otherSpace:
            return "space occupied by other files and folders"
        case .freeSpace:
            return "free space on drive"
        }
    }

    var path: String {
        isSpecialItem ? "" : urlValue.path
    }

    var url: URL {
        urlValue
    }

    func sizeValue(usePhysicalSize: Bool) -> UInt64 {
        usePhysicalSize ? allocatedSizeValue : logicalSizeValue
    }

    func child(at index: Int) -> DiskItemBuilder {
        childrenStorage[index]
    }

    func appendChild(_ child: DiskItemBuilder, updateSize: Bool = true) {
        childrenStorage.append(child)

        if updateSize {
            addToSize(allocated: child.allocatedSizeValue, logical: child.logicalSizeValue)
        }
    }

    func removeAllChildren() {
        childrenStorage.removeAll(keepingCapacity: true)
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }

    func sortChildrenInDiskInventoryZOrder(recursive: Bool = true, usePhysicalSize: Bool) {
        if recursive {
            for child: DiskItemBuilder in childrenStorage {
                child.sortChildrenInDiskInventoryZOrder(recursive: true, usePhysicalSize: usePhysicalSize)
            }
        }

        childrenStorage.sort { firstChild, secondChild in
            Self.compareSizeDescending(firstChild, secondChild, usePhysicalSize: usePhysicalSize) == .orderedAscending
        }
    }

    @discardableResult
    func recalculateSize(usePhysicalSize: Bool) -> UInt64 {
        switch itemType {
        case .fileOrFolder:
            recalculateFileOrFolderSize(usePhysicalSize: usePhysicalSize)
        case .otherSpace, .freeSpace:
            break
        }

        return usePhysicalSize ? allocatedSizeValue : logicalSizeValue
    }

    func freeze(isRoot: Bool = true) -> DiskItem {
        let frozenChildren: [DiskItem] = childrenStorage.map { child in
            child.freeze(isRoot: false)
        }
        return DiskItem(
            url: urlValue,
            itemType: itemType,
            displayName: displayName,
            name: fileSystemName,
            allocatedSizeValue: allocatedSizeValue,
            logicalSizeValue: logicalSizeValue,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isAliasOrSymbolicLink,
            isHardlinkDuplicate: isHardlinkDuplicate,
            children: frozenChildren,
            isRoot: isRoot
        )
    }

    private func addToSize(allocated: UInt64, logical: UInt64) {
        allocatedSizeValue += allocated
        logicalSizeValue += logical
    }

    private func recalculateFileOrFolderSize(usePhysicalSize: Bool) {
        if isFolder {
            if childrenStorage.isEmpty && isPackage && allocatedSizeValue > 0 {
                return
            }

            var allocatedSize: UInt64 = 0
            var logicalSize: UInt64 = 0

            let childRecalculationStartTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
            for child: DiskItemBuilder in childrenStorage {
                child.recalculateSize(usePhysicalSize: usePhysicalSize)
                allocatedSize += child.allocatedSizeValue
                logicalSize += child.logicalSizeValue
            }
            if ScanPerformanceRecorder.isEnabled {
                ScanPerformanceRecorder.shared.addTime(
                    "recalculate.children.total",
                    seconds: CFAbsoluteTimeGetCurrent() - childRecalculationStartTime
                )
            }

            allocatedSizeValue = allocatedSize
            logicalSizeValue = logicalSize
            let sortStartTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
            sortChildrenInDiskInventoryZOrder(recursive: false, usePhysicalSize: usePhysicalSize)
            if ScanPerformanceRecorder.isEnabled {
                ScanPerformanceRecorder.shared.addTime(
                    "recalculate.sort.total",
                    seconds: CFAbsoluteTimeGetCurrent() - sortStartTime
                )
            }
        } else if isHardlinkDuplicate {
            allocatedSizeValue = 0
            logicalSizeValue = 0
        }
    }

    private static func compareSize(_ firstItem: DiskItemBuilder, _ secondItem: DiskItemBuilder, usePhysicalSize: Bool) -> ComparisonResult {
        if firstItem.isSpecialItem != secondItem.isSpecialItem {
            return firstItem.isSpecialItem ? .orderedAscending : .orderedDescending
        }

        let firstSize: UInt64 = firstItem.sizeValue(usePhysicalSize: usePhysicalSize)
        let secondSize: UInt64 = secondItem.sizeValue(usePhysicalSize: usePhysicalSize)

        if firstSize > secondSize {
            return .orderedDescending
        }

        if firstSize < secondSize {
            return .orderedAscending
        }

        return (firstItem.fileSystemName as NSString).compare(
            secondItem.fileSystemName,
            options: [.numeric, .caseInsensitive]
        )
    }

    private static func compareSizeDescending(
        _ firstItem: DiskItemBuilder,
        _ secondItem: DiskItemBuilder,
        usePhysicalSize: Bool
    ) -> ComparisonResult {
        switch compareSize(firstItem, secondItem, usePhysicalSize: usePhysicalSize) {
        case .orderedDescending:
            return .orderedAscending
        case .orderedAscending:
            return .orderedDescending
        case .orderedSame:
            return .orderedSame
        }
    }
}

nonisolated enum DiskItemType: Hashable, Sendable {
    case fileOrFolder
    case otherSpace
    case freeSpace
}
