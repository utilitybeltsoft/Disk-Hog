import Foundation

// Builder instances are mutable scanner-local construction state. Top-level
// scan tasks transfer their builders back exactly once, then freeze the root
// into immutable Sendable DiskItem values before reaching UI code.
nonisolated final class DiskItemBuilder: @unchecked Sendable, DiskItemTreeNode {
    typealias ChildItem = DiskItemBuilder

    var itemMetadata: DiskItemMetadata
    let childStorage: DiskItemBuilderChildStorage = DiskItemBuilderChildStorage()
    private(set) var folderSizeSource: DiskItemBuilderFolderSizeSource = .children

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
        itemMetadata = DiskItemMetadata(
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
    }

    var itemChildren: [DiskItemBuilder] {
        childStorage.items
    }

    var itemType: DiskItemType {
        get { itemMetadata.itemType }
        set { itemMetadata.itemType = newValue }
    }

    var allocatedSizeValue: UInt64 {
        get { itemMetadata.allocatedSizeValue }
        set { itemMetadata.allocatedSizeValue = newValue }
    }

    var logicalSizeValue: UInt64 {
        get { itemMetadata.logicalSizeValue }
        set { itemMetadata.logicalSizeValue = newValue }
    }

    var kindName: String? {
        get { itemMetadata.kindName }
        set { itemMetadata.kindName = newValue }
    }

    var isDirectory: Bool {
        get { itemMetadata.isDirectory }
        set { itemMetadata.isDirectory = newValue }
    }

    var isPackage: Bool {
        get { itemMetadata.isPackage }
        set { itemMetadata.isPackage = newValue }
    }

    var isAliasOrSymbolicLink: Bool {
        get { itemMetadata.isAliasOrSymbolicLink }
        set { itemMetadata.isAliasOrSymbolicLink = newValue }
    }

    var isHardlinkDuplicate: Bool {
        get { itemMetadata.isHardlinkDuplicate }
        set { itemMetadata.isHardlinkDuplicate = newValue }
    }

    func setOpaquePackageSize(allocated: UInt64, logical: UInt64) {
        precondition(isDirectory && isPackage, "Only package directories can have an opaque package size.")
        precondition(childStorage.isEmpty, "An opaque package cannot also contain scanned children.")
        folderSizeSource = .opaquePackage
        allocatedSizeValue = allocated
        logicalSizeValue = logical
    }

    func useChildDerivedSize() {
        guard folderSizeSource == .opaquePackage else {
            return
        }
        folderSizeSource = .children
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }
}

nonisolated enum DiskItemBuilderFolderSizeSource: Sendable {
    case children
    case opaquePackage
}

nonisolated final class DiskItemBuilderChildStorage: @unchecked Sendable {
    private var storage: [DiskItemBuilder] = []

    var items: [DiskItemBuilder] {
        storage
    }

    var isEmpty: Bool {
        storage.isEmpty
    }

    func append(_ child: DiskItemBuilder) {
        storage.append(child)
    }

    func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }

    func sort(by areInIncreasingOrder: (DiskItemBuilder, DiskItemBuilder) throws -> Bool) rethrows {
        try storage.sort(by: areInIncreasingOrder)
    }
}
