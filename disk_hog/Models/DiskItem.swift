import Foundation

nonisolated final class DiskItem: Identifiable, Hashable, @unchecked Sendable {
    var url: URL
    private(set) weak var parent: DiskItem?
    private var childrenStorage: [DiskItem]
    private let fileSystemName: String
    private let fileSystemDisplayName: String
    private let fileSystemNameForComparison: NSString

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
        self.url = url
        self.parent = parent
        self.childrenStorage = []
        let lastPathComponent: String = name ?? url.lastPathComponent
        self.fileSystemName = lastPathComponent.isEmpty ? url.path : lastPathComponent
        self.fileSystemDisplayName = displayName ?? self.fileSystemName
        self.fileSystemNameForComparison = self.fileSystemName as NSString
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
            return fileSystemDisplayName
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
        isSpecialItem ? "" : url.path
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
        childrenStorage.append(child)

        if updateSize {
            addToSize(allocated: child.allocatedSizeValue, logical: child.logicalSizeValue)
        }
    }

    func removeAllChildren() {
        for child: DiskItem in childrenStorage {
            child.parent = nil
        }
        childrenStorage.removeAll(keepingCapacity: true)
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }

    func sortChildrenInDiskInventoryZOrder(recursive: Bool = true) {
        if recursive {
            for child: DiskItem in childrenStorage {
                child.sortChildrenInDiskInventoryZOrder(recursive: true)
            }
        }

        childrenStorage.sort { firstChild, secondChild in
            Self.compareSizeDescending(firstChild, secondChild) == .orderedAscending
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
            sortChildrenInDiskInventoryZOrder(recursive: false)
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

    private static func compareSize(_ firstItem: DiskItem, _ secondItem: DiskItem) -> ComparisonResult {
        if firstItem.isSpecialItem != secondItem.isSpecialItem {
            return firstItem.isSpecialItem ? .orderedAscending : .orderedDescending
        }

        if firstItem.allocatedSizeValue > secondItem.allocatedSizeValue {
            return .orderedDescending
        }

        if firstItem.allocatedSizeValue < secondItem.allocatedSizeValue {
            return .orderedAscending
        }

        return firstItem.fileSystemNameForComparison.compare(
            secondItem.fileSystemName,
            options: [.numeric, .caseInsensitive]
        )
    }

    private static func compareSizeDescending(_ firstItem: DiskItem, _ secondItem: DiskItem) -> ComparisonResult {
        switch compareSize(firstItem, secondItem) {
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
