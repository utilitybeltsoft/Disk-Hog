import Foundation

nonisolated struct DiskItemBuilder: @unchecked Sendable, DiskItemTreeNode {
    typealias ChildItem = DiskItemBuilder

    let arena: DiskItemBuilderArena
    let index: Int

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
        let arena: DiskItemBuilderArena = DiskItemBuilderArena()
        self.arena = arena
        self.index = arena.append(
            metadata: DiskItemMetadata(
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
        )
    }

    init(metadata: DiskItemMetadata) {
        let arena: DiskItemBuilderArena = DiskItemBuilderArena()
        self.arena = arena
        self.index = arena.append(metadata: metadata)
    }

    init(arena: DiskItemBuilderArena, index: Int) {
        self.arena = arena
        self.index = index
    }

    var itemMetadata: DiskItemMetadata {
        get { arena.records[index].metadata }
        nonmutating set { arena.records[index].metadata = newValue }
    }

    var itemChildren: [DiskItemBuilder] {
        arena.childIndices(of: index).map { DiskItemBuilder(arena: arena, index: $0) }
    }

    var folderSizeSource: DiskItemBuilderFolderSizeSource {
        arena.records[index].folderSizeSource
    }

    var itemType: DiskItemType {
        get { itemMetadata.itemType }
        nonmutating set { arena.records[index].metadata.itemType = newValue }
    }

    var allocatedSizeValue: UInt64 {
        get { itemMetadata.allocatedSizeValue }
        nonmutating set { arena.records[index].metadata.allocatedSizeValue = newValue }
    }

    var logicalSizeValue: UInt64 {
        get { itemMetadata.logicalSizeValue }
        nonmutating set { arena.records[index].metadata.logicalSizeValue = newValue }
    }

    var kindName: String? {
        get { itemMetadata.kindName }
        nonmutating set { arena.records[index].metadata.kindName = newValue }
    }

    var isDirectory: Bool {
        get { itemMetadata.isDirectory }
        nonmutating set { arena.records[index].metadata.isDirectory = newValue }
    }

    var isPackage: Bool {
        get { itemMetadata.isPackage }
        nonmutating set { arena.records[index].metadata.isPackage = newValue }
    }

    var isAliasOrSymbolicLink: Bool {
        get { itemMetadata.isAliasOrSymbolicLink }
        nonmutating set { arena.records[index].metadata.isAliasOrSymbolicLink = newValue }
    }

    var isHardlinkDuplicate: Bool {
        get { itemMetadata.isHardlinkDuplicate }
        nonmutating set { arena.records[index].metadata.isHardlinkDuplicate = newValue }
    }

    func makeChild(
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
    ) -> DiskItemBuilder {
        let childIndex: Int = arena.append(metadata: DiskItemMetadata(
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
        ))
        return DiskItemBuilder(arena: arena, index: childIndex)
    }

    func makeChild(metadata: DiskItemMetadata) -> DiskItemBuilder {
        DiskItemBuilder(arena: arena, index: arena.append(metadata: metadata))
    }

    func setOpaquePackageSize(allocated: UInt64, logical: UInt64) {
        precondition(isDirectory && isPackage, "Only package directories can have an opaque package size.")
        precondition(itemChildren.isEmpty, "An opaque package cannot also contain scanned children.")
        arena.records[index].folderSizeSource = .opaquePackage
        allocatedSizeValue = allocated
        logicalSizeValue = logical
    }

    func useChildDerivedSize() {
        guard folderSizeSource == .opaquePackage else { return }
        arena.records[index].folderSizeSource = .children
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }
}

nonisolated enum DiskItemBuilderFolderSizeSource: Sendable {
    case children
    case opaquePackage
}

nonisolated struct DiskItemBuilderRecord: Sendable {
    var metadata: DiskItemMetadata
    var firstChild: Int = -1
    var lastChild: Int = -1
    var nextSibling: Int = -1
    var folderSizeSource: DiskItemBuilderFolderSizeSource = .children
}

nonisolated final class DiskItemBuilderArena: @unchecked Sendable {
    var records: [DiskItemBuilderRecord] = []

    func append(metadata: DiskItemMetadata) -> Int {
        records.append(DiskItemBuilderRecord(metadata: metadata))
        return records.count - 1
    }

    func appendChild(_ childIndex: Int, to parentIndex: Int) {
        precondition(records[childIndex].nextSibling < 0, "A builder node can only have one parent.")
        let lastChild: Int = records[parentIndex].lastChild
        if lastChild >= 0 {
            records[lastChild].nextSibling = childIndex
        } else {
            records[parentIndex].firstChild = childIndex
        }
        records[parentIndex].lastChild = childIndex
    }

    func childIndices(of parentIndex: Int) -> [Int] {
        var result: [Int] = []
        var childIndex: Int = records[parentIndex].firstChild
        while childIndex >= 0 {
            result.append(childIndex)
            childIndex = records[childIndex].nextSibling
        }
        return result
    }

    func replaceChildren(of parentIndex: Int, with childIndices: [Int]) {
        records[parentIndex].firstChild = childIndices.first ?? -1
        records[parentIndex].lastChild = childIndices.last ?? -1
        for (offset, childIndex) in childIndices.enumerated() {
            records[childIndex].nextSibling = offset + 1 < childIndices.count ? childIndices[offset + 1] : -1
        }
    }

    func importSubtree(from source: DiskItemBuilderArena, rootIndex: Int) -> Int {
        var sourceToDestination: [Int: Int] = [:]
        var pending: [Int] = [rootIndex]
        while let sourceIndex: Int = pending.popLast() {
            let destinationIndex: Int = append(metadata: source.records[sourceIndex].metadata)
            records[destinationIndex].folderSizeSource = source.records[sourceIndex].folderSizeSource
            sourceToDestination[sourceIndex] = destinationIndex
            pending.append(contentsOf: source.childIndices(of: sourceIndex).reversed())
        }
        for (sourceIndex, destinationIndex) in sourceToDestination {
            replaceChildren(
                of: destinationIndex,
                with: source.childIndices(of: sourceIndex).compactMap { sourceToDestination[$0] }
            )
        }
        return sourceToDestination[rootIndex]!
    }
}
