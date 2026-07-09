import Foundation

nonisolated final class DiskItem: Identifiable, Hashable, @unchecked Sendable {
    private(set) weak var parent: DiskItem?
    private var childrenStorage: [DiskItem]
    private var rootOrDetachedURL: URL?
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

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    init(
        url: URL,
        parent: DiskItem? = nil,
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
        self.parent = parent
        self.childrenStorage = []
        let lastPathComponent: String = name ?? url.lastPathComponent
        self.fileSystemName = lastPathComponent.isEmpty ? url.path : lastPathComponent
        self.displayNameOverride = displayName == self.fileSystemName ? nil : displayName
        self.rootOrDetachedURL = parent == nil ? url : nil
        self.itemType = itemType
        self.allocatedSizeValue = allocatedSizeValue
        self.logicalSizeValue = logicalSizeValue
        self.kindName = kindName
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAliasOrSymbolicLink = isAliasOrSymbolicLink
        self.isHardlinkDuplicate = isHardlinkDuplicate
    }

    var children: [DiskItem] {
        childrenStorage
    }

    var childCount: Int {
        childrenStorage.count
    }

    var isRoot: Bool {
        parent == nil
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
        if isSpecialItem {
            return ""
        }

        if let parent: DiskItem = parent {
            return (parent.path as NSString).appendingPathComponent(fileSystemName)
        }

        return rootOrDetachedURL?.path ?? fileSystemName
    }

    var url: URL {
        if let parent: DiskItem = parent {
            return parent.url.appendingPathComponent(fileSystemName, isDirectory: isDirectory)
        }

        return rootOrDetachedURL ?? URL(fileURLWithPath: fileSystemName, isDirectory: isDirectory)
    }

    var folderName: String {
        if isSpecialItem {
            return ""
        }

        if let parent: DiskItem = parent {
            return parent.path
        }

        return (path as NSString).deletingLastPathComponent
    }

    var displayFolderName: String {
        guard !isSpecialItem, let parent: DiskItem = parent else {
            return ""
        }

        return (parent.displayFolderName as NSString).appendingPathComponent(parent.displayName)
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

    func pathFromRoot() -> [DiskItem] {
        var items: [DiskItem] = []
        var currentItem: DiskItem? = self

        while let item: DiskItem = currentItem {
            items.append(item)
            currentItem = item.parent
        }

        return items.reversed()
    }

    func appendChild(_ child: DiskItem, updateSize: Bool = true) {
        child.parent = self
        child.rootOrDetachedURL = nil
        childrenStorage.append(child)

        if updateSize {
            addToSize(allocated: child.allocatedSizeValue, logical: child.logicalSizeValue)
        }
    }

    func removeAllChildren() {
        for child: DiskItem in childrenStorage {
            child.rootOrDetachedURL = child.url
            child.parent = nil
        }
        childrenStorage.removeAll(keepingCapacity: true)
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }

    func sortChildrenInDiskInventoryZOrder(recursive: Bool = true, usePhysicalSize: Bool) {
        if recursive {
            for child: DiskItem in childrenStorage {
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

    static func == (leftItem: DiskItem, rightItem: DiskItem) -> Bool {
        leftItem === rightItem
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    private func addToSize(allocated: UInt64, logical: UInt64) {
        allocatedSizeValue += allocated
        logicalSizeValue += logical
        parent?.addToSize(allocated: allocated, logical: logical)
    }

    private func recalculateFileOrFolderSize(usePhysicalSize: Bool) {
        if isFolder {
            if childrenStorage.isEmpty && isPackage && allocatedSizeValue > 0 {
                return
            }

            var allocatedSize: UInt64 = 0
            var logicalSize: UInt64 = 0

            let childRecalculationStartTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
            for child: DiskItem in childrenStorage {
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

    private static func compareSize(_ firstItem: DiskItem, _ secondItem: DiskItem, usePhysicalSize: Bool) -> ComparisonResult {
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
        _ firstItem: DiskItem,
        _ secondItem: DiskItem,
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

nonisolated enum DiskItemType: Hashable {
    case fileOrFolder
    case otherSpace
    case freeSpace
}
