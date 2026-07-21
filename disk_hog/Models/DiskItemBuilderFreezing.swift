import Foundation

extension DiskItemBuilder {
    nonisolated func freeze(isRoot: Bool = true) -> DiskItem {
        let frozenChildren: [DiskItem] = itemChildren.map { child in
            child.freeze(isRoot: false)
        }
        return DiskItem(
            url: url,
            itemType: itemType,
            displayName: displayName,
            name: itemMetadata.fileSystemName,
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
}
