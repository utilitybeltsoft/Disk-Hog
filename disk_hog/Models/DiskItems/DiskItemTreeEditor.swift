import Foundation

nonisolated enum DiskItemTreeEditor {
    static func replacingSubtree(
        in root: DiskItem,
        atPath targetPath: String,
        with replacement: DiskItem,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        guard let target: DiskItem = root.item(atPath: targetPath) else { return nil }
        if root.path == targetPath {
            return builderCopy(of: replacement).freeze(isRoot: root.isRoot)
        }
        return pathEditedRoot(
            from: root,
            to: target,
            replacement: replacement,
            usePhysicalSize: usePhysicalSize
        )
    }

    static func removingSubtree(
        from root: DiskItem,
        atPath targetPath: String,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        guard root.path != targetPath,
              let target: DiskItem = root.item(atPath: targetPath) else { return nil }
        return pathEditedRoot(
            from: root,
            to: target,
            replacement: nil,
            usePhysicalSize: usePhysicalSize
        )
    }

    /// Removes known-deleted entries without filesystem enumeration. Missing nodes
    /// are already reconciled; a root/out-of-tree path requires a real rescan.
    static func removingSubtrees(from root: DiskItem, atPaths paths: [String],
                                 usePhysicalSize: Bool) -> DiskItem? {
        let ordered = Set(paths).sorted { $0.count < $1.count }
        var removed: [String] = []
        var updated = root
        for path in ordered {
            guard path != root.path, FilePathContainment.contains(path, in: root.path) else { return nil }
            if removed.contains(where: { FilePathContainment.contains(path, in: $0) }) { continue }
            removed.append(path)
            guard updated.item(atPath: path) != nil else { continue }
            guard let next = removingSubtree(from: updated, atPath: path, usePhysicalSize: usePhysicalSize) else {
                return nil
            }
            updated = next
        }
        return updated
    }

    static func reordered(_ root: DiskItem, usePhysicalSize: Bool) -> DiskItem {
        let builder: DiskItemBuilder = builderCopy(of: root)
        builder.recalculateSize(usePhysicalSize: usePhysicalSize)
        return builder.freeze(isRoot: root.isRoot)
    }

    private static func pathEditedRoot(
        from root: DiskItem,
        to target: DiskItem,
        replacement: DiskItem?,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        let path: [DiskItem] = root.descendantsMatchingAncestorPath(of: target)
        guard path.count > 1 else { return nil }

        var chunks: [PackedDiskItemChunk] = root.snapshot.chunks
        let replacementAddress: PackedDiskItemAddress?
        if let replacement {
            let normalizedReplacement: DiskItem = replacementUsesExternalChildStorage(replacement)
                ? builderCopy(of: replacement).freeze(isRoot: false)
                : replacement
            let chunkOffset: Int = chunks.count
            chunks.append(contentsOf: normalizedReplacement.snapshot.chunks)
            replacementAddress = PackedDiskItemAddress(
                chunkIndex: normalizedReplacement.address.chunkIndex + chunkOffset,
                recordIndex: normalizedReplacement.address.recordIndex
            )
        } else {
            replacementAddress = nil
        }

        let updateChunkIndex: Int = chunks.count
        var encoder: PackedDiskItemStringEncoder = PackedDiskItemStringEncoder()
        var records: [PackedDiskItemRecord] = []
        var childOverrides: [PackedDiskItemAddress: [PackedDiskItemAddress]] = root.snapshot.childOverrides
        var newMetadataByAddress: [PackedDiskItemAddress: DiskItemMetadata] = [:]

        var editedChildAddress: PackedDiskItemAddress? = replacementAddress
        for pathIndex: Int in stride(from: path.count - 2, through: 0, by: -1) {
            let ancestor: DiskItem = path[pathIndex]
            let originalChild: DiskItem = path[pathIndex + 1]
            let originalChildren: [DiskItem] = ancestor.children
            var editedChildren: [PackedDiskItemAddress] = []
            editedChildren.reserveCapacity(originalChildren.count + (replacementAddress == nil ? 0 : 1))

            for child: DiskItem in originalChildren {
                if child == originalChild {
                    if let editedChildAddress {
                        editedChildren.append(editedChildAddress)
                    }
                } else {
                    editedChildren.append(child.address)
                }
            }

            editedChildren.sort {
                areAddressesInDiskInventoryZOrder(
                    $0,
                    $1,
                    chunks: chunks,
                    newMetadataByAddress: newMetadataByAddress,
                    usePhysicalSize: usePhysicalSize
                )
            }

            let metadata: DiskItemMetadata = recalculatedMetadata(
                for: ancestor,
                children: editedChildren,
                chunks: chunks,
                records: records
            )
            let counts: (files: Int, folders: Int) = scanCounts(
                for: metadata,
                children: editedChildren,
                chunks: chunks,
                records: records
            )
            let newAddress: PackedDiskItemAddress = PackedDiskItemAddress(
                chunkIndex: updateChunkIndex,
                recordIndex: records.count
            )
            records.append(PackedDiskItemRecord(
                path: encoder.append(metadata.url.path),
                fileSystemName: encoder.append(metadata.fileSystemName),
                displayName: encoder.append(metadata.displayNameOverride),
                kindName: encoder.append(metadata.kindName),
                firstChild: 0,
                childCount: editedChildren.count,
                allocatedSizeValue: metadata.allocatedSizeValue,
                logicalSizeValue: metadata.logicalSizeValue,
                fileCount: counts.files,
                folderCount: counts.folders,
                itemType: metadata.itemType,
                isDirectory: metadata.isDirectory,
                isPackage: metadata.isPackage,
                isAliasOrSymbolicLink: metadata.isAliasOrSymbolicLink,
                isHardlinkDuplicate: metadata.isHardlinkDuplicate,
                isRoot: ancestor.isRoot
            ))
            childOverrides[newAddress] = editedChildren
            newMetadataByAddress[newAddress] = metadata
            editedChildAddress = newAddress
        }

        guard let rootAddress: PackedDiskItemAddress = editedChildAddress else { return nil }
        chunks.append(PackedDiskItemChunk(records: records, childIndices: [], stringBytes: encoder.data))
        return DiskItem(
            snapshot: PackedDiskItemSnapshot(
                chunks: chunks,
                rootAddress: rootAddress,
                childOverrides: childOverrides
            ),
            address: rootAddress
        )
    }

    static func builderCopy(of root: DiskItem) -> DiskItemBuilder {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(metadata: root.itemMetadata)
        var pending: [(source: DiskItem, destination: DiskItemBuilder)] = [(root, rootBuilder)]
        while let (source, destination) = pending.popLast() {
            for child: DiskItem in source.children {
                let childBuilder: DiskItemBuilder = destination.makeChild(metadata: child.itemMetadata)
                destination.appendChild(childBuilder, updateSize: false)
                pending.append((child, childBuilder))
            }
        }
        return rootBuilder
    }

    private static func replacementUsesExternalChildStorage(_ item: DiskItem) -> Bool {
        item.snapshot.hasExternalChildStorage
    }

    private static func recalculatedMetadata(
        for ancestor: DiskItem,
        children: [PackedDiskItemAddress],
        chunks: [PackedDiskItemChunk],
        records: [PackedDiskItemRecord]
    ) -> DiskItemMetadata {
        var metadata: DiskItemMetadata = ancestor.itemMetadata
        guard metadata.itemType == .fileOrFolder,
              metadata.isDirectory,
              !metadata.isAliasOrSymbolicLink else {
            return metadata
        }
        metadata.allocatedSizeValue = children.reduce(0) {
            $0 + record(at: $1, chunks: chunks, newRecords: records).allocatedSizeValue
        }
        metadata.logicalSizeValue = children.reduce(0) {
            $0 + record(at: $1, chunks: chunks, newRecords: records).logicalSizeValue
        }
        return metadata
    }

    private static func scanCounts(
        for metadata: DiskItemMetadata,
        children: [PackedDiskItemAddress],
        chunks: [PackedDiskItemChunk],
        records: [PackedDiskItemRecord]
    ) -> (files: Int, folders: Int) {
        var files: Int = metadata.isDirectory ? 0 : 1
        var folders: Int = metadata.isDirectory ? 1 : 0
        for child: PackedDiskItemAddress in children {
            let childRecord: PackedDiskItemRecord = record(
                at: child,
                chunks: chunks,
                newRecords: records
            )
            guard childRecord.itemType == .fileOrFolder else { continue }
            files += childRecord.fileCount
            folders += childRecord.folderCount
        }
        return (files, folders)
    }

    private static func areAddressesInDiskInventoryZOrder(
        _ first: PackedDiskItemAddress,
        _ second: PackedDiskItemAddress,
        chunks: [PackedDiskItemChunk],
        newMetadataByAddress: [PackedDiskItemAddress: DiskItemMetadata],
        usePhysicalSize: Bool
    ) -> Bool {
        let firstMetadata: DiskItemMetadata = metadata(
            at: first,
            chunks: chunks,
            newMetadataByAddress: newMetadataByAddress
        )
        let secondMetadata: DiskItemMetadata = metadata(
            at: second,
            chunks: chunks,
            newMetadataByAddress: newMetadataByAddress
        )
        return DiskItemBuilderOrdering.areInOrder(
            firstName: firstMetadata.fileSystemName,
            firstAllocatedSize: firstMetadata.allocatedSizeValue,
            firstLogicalSize: firstMetadata.logicalSizeValue,
            firstIsSpecialItem: firstMetadata.itemType != .fileOrFolder,
            secondName: secondMetadata.fileSystemName,
            secondAllocatedSize: secondMetadata.allocatedSizeValue,
            secondLogicalSize: secondMetadata.logicalSizeValue,
            secondIsSpecialItem: secondMetadata.itemType != .fileOrFolder,
            usePhysicalSize: usePhysicalSize
        )
    }

    private static func metadata(
        at address: PackedDiskItemAddress,
        chunks: [PackedDiskItemChunk],
        newMetadataByAddress: [PackedDiskItemAddress: DiskItemMetadata]
    ) -> DiskItemMetadata {
        if let metadata: DiskItemMetadata = newMetadataByAddress[address] {
            return metadata
        }
        let record: PackedDiskItemRecord = record(at: address, chunks: chunks)
        let chunk: PackedDiskItemChunk = chunks[address.chunkIndex]
        return DiskItemMetadata(
            url: URL(fileURLWithPath: chunk.string(in: record.path) ?? ""),
            itemType: record.itemType,
            displayName: chunk.string(in: record.displayName),
            name: chunk.string(in: record.fileSystemName),
            allocatedSizeValue: record.allocatedSizeValue,
            logicalSizeValue: record.logicalSizeValue,
            kindName: chunk.string(in: record.kindName),
            isDirectory: record.isDirectory,
            isPackage: record.isPackage,
            isAliasOrSymbolicLink: record.isAliasOrSymbolicLink,
            isHardlinkDuplicate: record.isHardlinkDuplicate
        )
    }

    private static func record(
        at address: PackedDiskItemAddress,
        chunks: [PackedDiskItemChunk],
        newRecords: [PackedDiskItemRecord] = []
    ) -> PackedDiskItemRecord {
        if address.chunkIndex == chunks.count {
            return newRecords[address.recordIndex]
        }
        return chunks[address.chunkIndex].records[address.recordIndex]
    }
}
