import Foundation

extension DiskItemBuilder {
    nonisolated func appendChild(_ child: DiskItemBuilder, updateSize: Bool = true) {
        useChildDerivedSize()
        let childIndex: Int = child.arena === arena
            ? child.index
            : arena.importSubtree(from: child.arena, rootIndex: child.index)
        arena.appendChild(childIndex, to: index)
        if updateSize {
            allocatedSizeValue += arena.records[childIndex].metadata.allocatedSizeValue
            logicalSizeValue += arena.records[childIndex].metadata.logicalSizeValue
        }
    }

    nonisolated func removeAllChildren() {
        useChildDerivedSize()
        arena.replaceChildren(of: index, with: [])
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }

    @discardableResult
    nonisolated func recalculateSize(usePhysicalSize: Bool) -> UInt64 {
        var sourceIndices: [Int] = []
        var pending: [Int] = [index]
        while let sourceIndex: Int = pending.popLast() {
            sourceIndices.append(sourceIndex)
            pending.append(contentsOf: arena.childIndices(of: sourceIndex).reversed())
        }

        for sourceIndex: Int in sourceIndices.reversed() {
            var record: DiskItemBuilderRecord = arena.records[sourceIndex]
            guard record.metadata.itemType == .fileOrFolder else { continue }
            let isFolder: Bool = record.metadata.isDirectory && !record.metadata.isAliasOrSymbolicLink
            guard isFolder else {
                if record.metadata.isHardlinkDuplicate {
                    record.metadata.allocatedSizeValue = 0
                    record.metadata.logicalSizeValue = 0
                    arena.records[sourceIndex] = record
                }
                continue
            }
            if record.folderSizeSource == .opaquePackage {
                precondition(arena.childIndices(of: sourceIndex).isEmpty, "An opaque package cannot also contain scanned children.")
                continue
            }

            let sortedChildren: [Int] = arena.childIndices(of: sourceIndex).sorted { firstIndex, secondIndex in
                DiskItemBuilderOrdering.areInOrder(
                    DiskItemBuilder(arena: arena, index: firstIndex),
                    DiskItemBuilder(arena: arena, index: secondIndex),
                    usePhysicalSize: usePhysicalSize
                )
            }
            record.metadata.allocatedSizeValue = sortedChildren.reduce(0) {
                $0 + arena.records[$1].metadata.allocatedSizeValue
            }
            record.metadata.logicalSizeValue = sortedChildren.reduce(0) {
                $0 + arena.records[$1].metadata.logicalSizeValue
            }
            arena.records[sourceIndex] = record
            arena.replaceChildren(of: sourceIndex, with: sortedChildren)
        }
        return sizeValue(usePhysicalSize: usePhysicalSize)
    }
}
