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
    nonisolated var children: [ChildItem] { itemChildren }
    nonisolated var childCount: Int { itemChildren.count }
    nonisolated var itemType: DiskItemType { itemMetadata.itemType }
    nonisolated var allocatedSizeValue: UInt64 { itemMetadata.allocatedSizeValue }
    nonisolated var logicalSizeValue: UInt64 { itemMetadata.logicalSizeValue }
    nonisolated var kindName: String? { itemMetadata.kindName }
    nonisolated var resolvedKindName: String {
        resolvedKindName(folderName: String(localized: "Folder"))
    }
    nonisolated func resolvedKindName(folderName: String) -> String {
        if let kindName: String = itemMetadata.kindName { return kindName }
        return isFolder && !isPackage ? folderName : ""
    }
    nonisolated var isDirectory: Bool { itemMetadata.isDirectory }
    nonisolated var isPackage: Bool { itemMetadata.isPackage }
    nonisolated var isAliasOrSymbolicLink: Bool { itemMetadata.isAliasOrSymbolicLink }
    nonisolated var isHardlinkDuplicate: Bool { itemMetadata.isHardlinkDuplicate }
    nonisolated var isSpecialItem: Bool { itemMetadata.itemType != .fileOrFolder }
    nonisolated var isFolder: Bool { itemMetadata.isDirectory && !itemMetadata.isAliasOrSymbolicLink }
    nonisolated var displayName: String {
        switch itemMetadata.itemType {
        case .fileOrFolder: itemMetadata.displayNameOverride ?? itemMetadata.fileSystemName
        case .otherSpace: String(localized: "space occupied by other files and folders")
        case .freeSpace: String(localized: "free space on drive")
        }
    }
    nonisolated var name: String {
        switch itemMetadata.itemType {
        case .fileOrFolder: itemMetadata.fileSystemName
        case .otherSpace, .freeSpace: displayName
        }
    }
    nonisolated var path: String { isSpecialItem ? "" : itemMetadata.url.path }
    nonisolated var url: URL { itemMetadata.url }
    nonisolated func sizeValue(usePhysicalSize: Bool) -> UInt64 {
        usePhysicalSize ? itemMetadata.allocatedSizeValue : itemMetadata.logicalSizeValue
    }
    nonisolated func child(at index: Int) -> ChildItem { itemChildren[index] }
}

nonisolated struct DiskItemID: Hashable, Sendable {
    fileprivate let snapshotID: ObjectIdentifier
    fileprivate let address: PackedDiskItemAddress
}

nonisolated final class DiskItem: Identifiable, Hashable, Sendable, DiskItemTreeNode {
    typealias ChildItem = DiskItem

    let snapshot: PackedDiskItemSnapshot
    let address: PackedDiskItemAddress

    var id: DiskItemID {
        DiskItemID(snapshotID: ObjectIdentifier(snapshot), address: address)
    }

    init(snapshot: PackedDiskItemSnapshot, address: PackedDiskItemAddress) {
        self.snapshot = snapshot
        self.address = address
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
        let builder: DiskItemBuilder = DiskItemBuilder(
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
        for child: DiskItem in children {
            builder.appendChild(child.builderCopy(), updateSize: false)
        }
        let chunk: PackedDiskItemChunk = builder.packedChunk(isRoot: isRoot)
        let snapshot: PackedDiskItemSnapshot = PackedDiskItemSnapshot(
            chunks: [chunk],
            rootAddress: PackedDiskItemAddress(chunkIndex: 0, recordIndex: 0)
        )
        self.snapshot = snapshot
        self.address = snapshot.rootAddress
    }

    var itemMetadata: DiskItemMetadata {
        let record: PackedDiskItemRecord = snapshot.record(at: address)
        let path: String = snapshot.string(record.path, at: address) ?? ""
        return DiskItemMetadata(
            url: URL(fileURLWithPath: path),
            itemType: record.itemType,
            displayName: snapshot.string(record.displayName, at: address),
            name: snapshot.string(record.fileSystemName, at: address),
            allocatedSizeValue: record.allocatedSizeValue,
            logicalSizeValue: record.logicalSizeValue,
            kindName: snapshot.string(record.kindName, at: address),
            isDirectory: record.isDirectory,
            isPackage: record.isPackage,
            isAliasOrSymbolicLink: record.isAliasOrSymbolicLink,
            isHardlinkDuplicate: record.isHardlinkDuplicate
        )
    }

    var itemChildren: [DiskItem] {
        snapshot.children(of: address).map { DiskItem(snapshot: snapshot, address: $0) }
    }

    private var record: PackedDiskItemRecord { snapshot.record(at: address) }

    var children: [DiskItem] { itemChildren }
    var childCount: Int { snapshot.childCount(of: address) }
    var itemType: DiskItemType { record.itemType }
    var allocatedSizeValue: UInt64 { record.allocatedSizeValue }
    var logicalSizeValue: UInt64 { record.logicalSizeValue }
    var kindName: String? { snapshot.string(record.kindName, at: address) }
    var isDirectory: Bool { record.isDirectory }
    var isPackage: Bool { record.isPackage }
    var isAliasOrSymbolicLink: Bool { record.isAliasOrSymbolicLink }
    var isHardlinkDuplicate: Bool { record.isHardlinkDuplicate }
    var isSpecialItem: Bool { record.itemType != .fileOrFolder }
    var isFolder: Bool { record.isDirectory && !record.isAliasOrSymbolicLink }
    var displayName: String {
        switch record.itemType {
        case .fileOrFolder:
            return snapshot.string(record.displayName, at: address)
                ?? snapshot.string(record.fileSystemName, at: address)
                ?? ""
        case .otherSpace: return String(localized: "space occupied by other files and folders")
        case .freeSpace: return String(localized: "free space on drive")
        }
    }
    var name: String {
        switch record.itemType {
        case .fileOrFolder: return snapshot.string(record.fileSystemName, at: address) ?? ""
        case .otherSpace, .freeSpace: return displayName
        }
    }
    var path: String { isSpecialItem ? "" : snapshot.string(record.path, at: address) ?? "" }
    var url: URL { URL(fileURLWithPath: snapshot.string(record.path, at: address) ?? "") }
    var isRoot: Bool { record.isRoot }

    func sizeValue(usePhysicalSize: Bool) -> UInt64 {
        usePhysicalSize ? record.allocatedSizeValue : record.logicalSizeValue
    }

    func child(at index: Int) -> DiskItem {
        DiskItem(snapshot: snapshot, address: snapshot.child(of: address, at: index))
    }

    func sameNode(as other: DiskItem) -> Bool { self == other }

    static func chunkedRoot(rootChunk: PackedDiskItemChunk, childChunks: [PackedDiskItemChunk]) -> DiskItem {
        let chunks: [PackedDiskItemChunk] = [rootChunk] + childChunks
        let rootAddress: PackedDiskItemAddress = PackedDiskItemAddress(chunkIndex: 0, recordIndex: 0)
        let childAddresses: [PackedDiskItemAddress] = childChunks.indices.map {
            PackedDiskItemAddress(chunkIndex: $0 + 1, recordIndex: 0)
        }
        let snapshot: PackedDiskItemSnapshot = PackedDiskItemSnapshot(
            chunks: chunks,
            rootAddress: rootAddress,
            rootChildren: childAddresses
        )
        return DiskItem(snapshot: snapshot, address: rootAddress)
    }

    func descendantsMatchingAncestorPath(of item: DiskItem) -> [DiskItem] {
        guard containsPath(item.path) else { return [] }
        var pendingItems: [DiskItem] = [self]
        var parentByID: [DiskItemID: DiskItem] = [:]
        while let currentItem: DiskItem = pendingItems.popLast() {
            if currentItem == item {
                var result: [DiskItem] = []
                var cursor: DiskItem? = currentItem
                while let current: DiskItem = cursor {
                    result.append(current)
                    cursor = parentByID[current.id]
                }
                return result.reversed()
            }
            for child: DiskItem in currentItem.children.reversed() where child.containsPath(item.path) {
                parentByID[child.id] = currentItem
                pendingItems.append(child)
            }
        }
        return []
    }

    func item(atPath candidatePath: String, allowAncestors: Bool = false) -> DiskItem? {
        guard !isSpecialItem else { return nil }
        var pendingItems: [(DiskItem, Int)] = [(self, 0)]
        var deepest: (DiskItem, Int)?
        while let (item, depth) = pendingItems.popLast() {
            if item.path == candidatePath { return item }
            guard item.containsPath(candidatePath) else { continue }
            if deepest == nil || depth > deepest!.1 { deepest = (item, depth) }
            for child: DiskItem in item.children.reversed() where !child.isSpecialItem && child.containsPath(candidatePath) {
                pendingItems.append((child, depth + 1))
            }
        }
        return allowAncestors ? deepest?.0 : nil
    }

    func replacingSubtree(atPath targetPath: String, with replacement: DiskItem, usePhysicalSize: Bool) -> DiskItem? {
        guard item(atPath: targetPath) != nil else { return nil }
        if path == targetPath {
            return replacement.copy(isRoot: isRoot)
        }
        return rebuilt(replacingPath: targetPath, replacement: replacement, remove: false, usePhysicalSize: usePhysicalSize)
    }

    func removingSubtree(atPath targetPath: String, usePhysicalSize: Bool) -> DiskItem? {
        guard path != targetPath, item(atPath: targetPath) != nil else { return nil }
        return rebuilt(replacingPath: targetPath, replacement: nil, remove: true, usePhysicalSize: usePhysicalSize)
    }

    func reordered(usePhysicalSize: Bool) -> DiskItem {
        let builder: DiskItemBuilder = builderCopy()
        builder.recalculateSize(usePhysicalSize: usePhysicalSize)
        return builder.freeze(isRoot: isRoot)
    }

    func scanCounts(includeSelf: Bool = true) -> (files: Int, folders: Int) {
        let record: PackedDiskItemRecord = snapshot.record(at: address)
        let counts: (files: Int, folders: Int) = snapshot.scanCounts(at: address)
        return (
            counts.files - (!includeSelf && !record.isDirectory ? 1 : 0),
            counts.folders - (!includeSelf && record.isDirectory ? 1 : 0)
        )
    }

    func files(ofKind kindName: String) -> [DiskItem] {
        allFiles().filter { $0.kindName == kindName }
    }

    func allFiles() -> [DiskItem] {
        var matches: [DiskItem] = []
        var pendingItems: [DiskItem] = [self]
        while let item: DiskItem = pendingItems.popLast() {
            if !item.isFolder {
                matches.append(item)
            }
            pendingItems.append(contentsOf: item.children)
        }
        return matches
    }

    private func rebuilt(
        replacingPath targetPath: String,
        replacement: DiskItem?,
        remove: Bool,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        if path == targetPath { return remove ? nil : replacement }
        let rebuiltChildren: [DiskItem] = children.compactMap { child in
            child.containsPath(targetPath)
                ? child.rebuilt(replacingPath: targetPath, replacement: replacement, remove: remove, usePhysicalSize: usePhysicalSize)
                : child
        }.sorted {
            let firstSize: UInt64 = $0.sizeValue(usePhysicalSize: usePhysicalSize)
            let secondSize: UInt64 = $1.sizeValue(usePhysicalSize: usePhysicalSize)
            return firstSize == secondSize
                ? $0.name.localizedStandardCompare($1.name) == .orderedDescending
                : firstSize > secondSize
        }
        let allocated: UInt64 = isFolder ? rebuiltChildren.reduce(0) { $0 + $1.allocatedSizeValue } : allocatedSizeValue
        let logical: UInt64 = isFolder ? rebuiltChildren.reduce(0) { $0 + $1.logicalSizeValue } : logicalSizeValue
        return DiskItem(
            url: url,
            itemType: itemType,
            displayName: displayName,
            name: itemMetadata.fileSystemName,
            allocatedSizeValue: allocated,
            logicalSizeValue: logical,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isAliasOrSymbolicLink,
            isHardlinkDuplicate: isHardlinkDuplicate,
            children: rebuiltChildren,
            isRoot: isRoot
        )
    }

    private func builderCopy() -> DiskItemBuilder {
        let root: DiskItemBuilder = DiskItemBuilder(
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
            isHardlinkDuplicate: isHardlinkDuplicate
        )
        var pending: [(DiskItem, DiskItemBuilder)] = [(self, root)]
        while let (source, destination) = pending.popLast() {
            for child: DiskItem in source.children {
                let childBuilder: DiskItemBuilder = destination.makeChild(
                    url: child.url,
                    itemType: child.itemType,
                    displayName: child.displayName,
                    name: child.itemMetadata.fileSystemName,
                    allocatedSizeValue: child.allocatedSizeValue,
                    logicalSizeValue: child.logicalSizeValue,
                    kindName: child.kindName,
                    isDirectory: child.isDirectory,
                    isPackage: child.isPackage,
                    isAliasOrSymbolicLink: child.isAliasOrSymbolicLink,
                    isHardlinkDuplicate: child.isHardlinkDuplicate
                )
                destination.appendChild(childBuilder, updateSize: false)
                pending.append((child, childBuilder))
            }
        }
        return root
    }

    private func copy(isRoot: Bool) -> DiskItem {
        DiskItem(
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
            children: children,
            isRoot: isRoot
        )
    }

    private func containsPath(_ candidatePath: String) -> Bool {
        if isSpecialItem { return candidatePath.isEmpty }
        if candidatePath == path { return true }
        let prefix: String = path.hasSuffix("/") ? path : path + "/"
        return candidatePath.hasPrefix(prefix)
    }

    static func == (lhs: DiskItem, rhs: DiskItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated enum DiskItemType: Hashable, Sendable {
    case fileOrFolder
    case otherSpace
    case freeSpace
}
