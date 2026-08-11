import Foundation

extension DiskItemBuilder {
    nonisolated func freeze(isRoot: Bool = true) -> DiskItem {
        DiskItem(
            snapshot: PackedDiskItemSnapshot(
                chunks: [packedChunk(isRoot: isRoot)],
                rootAddress: PackedDiskItemAddress(chunkIndex: 0, recordIndex: 0)
            ),
            address: PackedDiskItemAddress(chunkIndex: 0, recordIndex: 0)
        )
    }

    nonisolated func packedChunk(isRoot: Bool) -> PackedDiskItemChunk {
        var sourceIndices: [Int] = []
        var pending: [Int] = [index]
        while let sourceIndex: Int = pending.popLast() {
            sourceIndices.append(sourceIndex)
            pending.append(contentsOf: arena.childIndices(of: sourceIndex).reversed())
        }

        let destinationBySource: [Int: Int] = Dictionary(
            uniqueKeysWithValues: sourceIndices.enumerated().map { ($0.element, $0.offset) }
        )
        var countsBySource: [Int: (files: Int, folders: Int)] = [:]
        for sourceIndex: Int in sourceIndices.reversed() {
            let metadata: DiskItemMetadata = arena.records[sourceIndex].metadata
            var files: Int = metadata.isDirectory ? 0 : 1
            var folders: Int = metadata.isDirectory ? 1 : 0
            for childIndex: Int in arena.childIndices(of: sourceIndex) {
                guard arena.records[childIndex].metadata.itemType == .fileOrFolder,
                      let childCounts = countsBySource[childIndex] else { continue }
                files += childCounts.files
                folders += childCounts.folders
            }
            countsBySource[sourceIndex] = (files, folders)
        }

        var encoder: PackedDiskItemStringEncoder = PackedDiskItemStringEncoder()
        var records: [PackedDiskItemRecord] = []
        var childIndices: [Int] = []
        records.reserveCapacity(sourceIndices.count)
        childIndices.reserveCapacity(max(0, sourceIndices.count - 1))

        for sourceIndex: Int in sourceIndices {
            let metadata: DiskItemMetadata = arena.records[sourceIndex].metadata
            let children: [Int] = arena.childIndices(of: sourceIndex).compactMap { destinationBySource[$0] }
            let firstChild: Int = childIndices.count
            childIndices.append(contentsOf: children)
            let counts = countsBySource[sourceIndex]!
            records.append(PackedDiskItemRecord(
                path: encoder.append(metadata.url.path),
                fileSystemName: encoder.append(metadata.fileSystemName),
                displayName: encoder.append(metadata.displayNameOverride),
                kindName: encoder.append(metadata.kindName),
                firstChild: firstChild,
                childCount: children.count,
                allocatedSizeValue: metadata.allocatedSizeValue,
                logicalSizeValue: metadata.logicalSizeValue,
                fileCount: counts.files,
                folderCount: counts.folders,
                itemType: metadata.itemType,
                isDirectory: metadata.isDirectory,
                isPackage: metadata.isPackage,
                isAliasOrSymbolicLink: metadata.isAliasOrSymbolicLink,
                isHardlinkDuplicate: metadata.isHardlinkDuplicate,
                isRoot: sourceIndex == index && isRoot
            ))
        }
        return PackedDiskItemChunk(records: records, childIndices: childIndices, stringBytes: encoder.data)
    }
}
