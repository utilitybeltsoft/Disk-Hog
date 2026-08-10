import Foundation

extension DiskItemBuilder {
    nonisolated func sortChildrenInDiskInventoryZOrder(recursive: Bool = true, usePhysicalSize: Bool) {
        if recursive {
            for child: DiskItemBuilder in itemChildren {
                child.sortChildrenInDiskInventoryZOrder(recursive: true, usePhysicalSize: usePhysicalSize)
            }
        }

        let sortedChildren: [DiskItemBuilder] = itemChildren.sorted { firstChild, secondChild in
            DiskItemBuilderOrdering.areInOrder(
                firstChild,
                secondChild,
                usePhysicalSize: usePhysicalSize
            )
        }
        arena.replaceChildren(of: index, with: sortedChildren.map(\.index))
    }
}

nonisolated enum DiskItemBuilderOrdering {
    static func areInOrder<Item: DiskItemTreeNode>(
        _ firstItem: Item,
        _ secondItem: Item,
        usePhysicalSize: Bool
    ) -> Bool {
        areInOrder(
            firstName: firstItem.name,
            firstAllocatedSize: firstItem.allocatedSizeValue,
            firstLogicalSize: firstItem.logicalSizeValue,
            firstIsSpecialItem: firstItem.isSpecialItem,
            secondName: secondItem.name,
            secondAllocatedSize: secondItem.allocatedSizeValue,
            secondLogicalSize: secondItem.logicalSizeValue,
            secondIsSpecialItem: secondItem.isSpecialItem,
            usePhysicalSize: usePhysicalSize
        )
    }

    static func areInOrder(
        firstName: String,
        firstAllocatedSize: UInt64,
        firstLogicalSize: UInt64,
        firstIsSpecialItem: Bool,
        secondName: String,
        secondAllocatedSize: UInt64,
        secondLogicalSize: UInt64,
        secondIsSpecialItem: Bool,
        usePhysicalSize: Bool
    ) -> Bool {
        compare(
            firstName: firstName,
            firstAllocatedSize: firstAllocatedSize,
            firstLogicalSize: firstLogicalSize,
            firstIsSpecialItem: firstIsSpecialItem,
            secondName: secondName,
            secondAllocatedSize: secondAllocatedSize,
            secondLogicalSize: secondLogicalSize,
            secondIsSpecialItem: secondIsSpecialItem,
            usePhysicalSize: usePhysicalSize
        ) == .orderedDescending
    }

    private static func compare(
        firstName: String,
        firstAllocatedSize: UInt64,
        firstLogicalSize: UInt64,
        firstIsSpecialItem: Bool,
        secondName: String,
        secondAllocatedSize: UInt64,
        secondLogicalSize: UInt64,
        secondIsSpecialItem: Bool,
        usePhysicalSize: Bool
    ) -> ComparisonResult {
        if firstIsSpecialItem != secondIsSpecialItem {
            return firstIsSpecialItem ? .orderedAscending : .orderedDescending
        }

        let firstSize: UInt64 = usePhysicalSize ? firstAllocatedSize : firstLogicalSize
        let secondSize: UInt64 = usePhysicalSize ? secondAllocatedSize : secondLogicalSize
        if firstSize != secondSize {
            return firstSize > secondSize ? .orderedDescending : .orderedAscending
        }

        return (firstName as NSString).compare(
            secondName,
            options: [.numeric, .caseInsensitive]
        )
    }
}
