import Foundation

extension DiskItemBuilder {
    nonisolated func sortChildrenInDiskInventoryZOrder(recursive: Bool = true, usePhysicalSize: Bool) {
        if recursive {
            for child: DiskItemBuilder in itemChildren {
                child.sortChildrenInDiskInventoryZOrder(recursive: true, usePhysicalSize: usePhysicalSize)
            }
        }

        childStorage.sort { firstChild, secondChild in
            DiskItemBuilderOrdering.areInOrder(
                firstChild,
                secondChild,
                usePhysicalSize: usePhysicalSize
            )
        }
    }
}

nonisolated enum DiskItemBuilderOrdering {
    static func areInOrder(
        _ firstItem: DiskItemBuilder,
        _ secondItem: DiskItemBuilder,
        usePhysicalSize: Bool
    ) -> Bool {
        compare(firstItem, secondItem, usePhysicalSize: usePhysicalSize) == .orderedDescending
    }

    private static func compare(
        _ firstItem: DiskItemBuilder,
        _ secondItem: DiskItemBuilder,
        usePhysicalSize: Bool
    ) -> ComparisonResult {
        if firstItem.isSpecialItem != secondItem.isSpecialItem {
            return firstItem.isSpecialItem ? .orderedAscending : .orderedDescending
        }

        let firstSize: UInt64 = firstItem.sizeValue(usePhysicalSize: usePhysicalSize)
        let secondSize: UInt64 = secondItem.sizeValue(usePhysicalSize: usePhysicalSize)
        if firstSize != secondSize {
            return firstSize > secondSize ? .orderedDescending : .orderedAscending
        }

        return (firstItem.name as NSString).compare(
            secondItem.name,
            options: [.numeric, .caseInsensitive]
        )
    }
}
