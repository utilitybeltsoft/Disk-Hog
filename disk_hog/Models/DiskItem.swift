import Foundation

nonisolated final class DiskItem: Identifiable, Hashable, Sendable {
    private let childrenStorage: [DiskItem]
    private let fileSystemName: String
    private let displayNameOverride: String?
    private let urlValue: URL
    private let folderNameValue: String
    private let displayFolderNameValue: String
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
        isRoot: Bool = true,
        displayFolderName: String? = nil
    ) {
        let lastPathComponent: String = name ?? url.lastPathComponent
        self.fileSystemName = lastPathComponent.isEmpty ? url.path : lastPathComponent
        self.displayNameOverride = displayName == self.fileSystemName ? nil : displayName
        self.urlValue = url
        self.folderNameValue = itemType == .fileOrFolder ? (url.path as NSString).deletingLastPathComponent : ""
        self.displayFolderNameValue = displayFolderName ?? ""
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

    var folderName: String {
        folderNameValue
    }

    var displayFolderName: String {
        displayFolderNameValue
    }

    var displayPath: String {
        if isSpecialItem {
            return displayName
        }

        return (displayFolderName as NSString).appendingPathComponent(displayName)
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

    func freeze(isRoot: Bool = true, displayFolderName: String = "") -> DiskItem {
        let childDisplayFolderName: String = (displayFolderName as NSString).appendingPathComponent(displayName)
        let frozenChildren: [DiskItem] = childrenStorage.map { child in
            child.freeze(isRoot: false, displayFolderName: childDisplayFolderName)
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
            isRoot: isRoot,
            displayFolderName: displayFolderName
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
