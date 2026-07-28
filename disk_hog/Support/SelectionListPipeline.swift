import Foundation

nonisolated enum SelectionListSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case name
    case kind
    case path

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All fields"
        case .name: "Name"
        case .kind: "Kind"
        case .path: "Path"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .all: "name, kind, and path"
        case .name: "file name"
        case .kind: "file kind"
        case .path: "file path"
        }
    }

    var helpText: String {
        "Performs a case-insensitive substring search in \(accessibilityTitle)."
    }
}

nonisolated struct SelectionListRow: Identifiable, Sendable {
    let item: DiskItem
    let size: UInt64

    var id: DiskItemID { item.id }
    var name: String { item.displayName }
    var kindName: String { item.kindName ?? "" }
    var parentPath: String { item.url.deletingLastPathComponent().path }
    var fullPath: String { item.path }

    func matches(_ searchText: String, in scope: SelectionListSearchScope) -> Bool {
        switch scope {
        case .all:
            name.localizedCaseInsensitiveContains(searchText)
                || kindName.localizedCaseInsensitiveContains(searchText)
                || fullPath.localizedCaseInsensitiveContains(searchText)
        case .name:
            name.localizedCaseInsensitiveContains(searchText)
        case .kind:
            kindName.localizedCaseInsensitiveContains(searchText)
        case .path:
            fullPath.localizedCaseInsensitiveContains(searchText)
        }
    }
}

nonisolated struct SelectionListSnapshot: Sendable {
    let rows: [SelectionListRow]
    let rowsByID: [DiskItemID: SelectionListRow]
}

nonisolated enum SelectionListSortField: Hashable, Sendable {
    case name
    case path
    case size
}

nonisolated struct SelectionListSortDescriptor: Hashable, Sendable {
    let field: SelectionListSortField
    let isAscending: Bool
}

nonisolated enum SelectionListPipeline {
    private static let cancellationInterval: Int = 2_048

    static func makeSnapshot(
        rootItem: DiskItem,
        filter: SelectionListFilter,
        usePhysicalSize: Bool
    ) throws -> SelectionListSnapshot {
        var rows: [SelectionListRow] = []
        var rowsByID: [DiskItemID: SelectionListRow] = [:]
        var pendingItems: [DiskItem] = [rootItem]
        var visitedCount: Int = 0

        while let item: DiskItem = pendingItems.popLast() {
            visitedCount += 1
            if visitedCount.isMultiple(of: cancellationInterval) {
                try Task.checkCancellation()
            }

            if !item.isFolder, filter.includes(item) {
                let row: SelectionListRow = SelectionListRow(
                    item: item,
                    size: item.sizeValue(usePhysicalSize: usePhysicalSize)
                )
                rows.append(row)
                rowsByID[row.id] = row
            }
            pendingItems.append(contentsOf: item.children)
        }

        try Task.checkCancellation()
        return SelectionListSnapshot(rows: rows, rowsByID: rowsByID)
    }

    static func visibleRows(
        from rows: [SelectionListRow],
        searchText: String,
        scope: SelectionListSearchScope,
        sortDescriptors: [SelectionListSortDescriptor]
    ) throws -> [SelectionListRow] {
        var filteredRows: [SelectionListRow]
        if searchText.isEmpty {
            filteredRows = rows
        } else {
            filteredRows = []
            filteredRows.reserveCapacity(min(rows.count, 4_096))
            for (index, row) in rows.enumerated() {
                if index.isMultiple(of: cancellationInterval) {
                    try Task.checkCancellation()
                }
                if row.matches(searchText, in: scope) {
                    filteredRows.append(row)
                }
            }
        }

        let descriptors: [SelectionListSortDescriptor] = sortDescriptors.isEmpty
            ? [SelectionListSortDescriptor(field: .size, isAscending: false)]
            : sortDescriptors
        try cancellableStableSort(&filteredRows, descriptors: descriptors)
        return filteredRows
    }

    private static func cancellableStableSort(
        _ rows: inout [SelectionListRow],
        descriptors: [SelectionListSortDescriptor]
    ) throws {
        guard rows.count > 1 else {
            try Task.checkCancellation()
            return
        }

        var source: [SelectionListRow] = rows
        var destination: [SelectionListRow] = rows
        var width: Int = 1

        while width < source.count {
            try Task.checkCancellation()
            var lowerBound: Int = 0
            var writtenCount: Int = 0

            while lowerBound < source.count {
                let middle: Int = min(lowerBound + width, source.count)
                let upperBound: Int = min(lowerBound + (width * 2), source.count)
                var leftIndex: Int = lowerBound
                var rightIndex: Int = middle
                var destinationIndex: Int = lowerBound

                while leftIndex < middle || rightIndex < upperBound {
                    writtenCount += 1
                    if writtenCount.isMultiple(of: cancellationInterval) {
                        try Task.checkCancellation()
                    }

                    if rightIndex >= upperBound
                        || (leftIndex < middle
                            && orderedBeforeOrEqual(
                                source[leftIndex],
                                source[rightIndex],
                                descriptors: descriptors
                            )) {
                        destination[destinationIndex] = source[leftIndex]
                        leftIndex += 1
                    } else {
                        destination[destinationIndex] = source[rightIndex]
                        rightIndex += 1
                    }
                    destinationIndex += 1
                }
                lowerBound = upperBound
            }

            swap(&source, &destination)
            width *= 2
        }

        rows = source
    }

    private static func orderedBeforeOrEqual(
        _ lhs: SelectionListRow,
        _ rhs: SelectionListRow,
        descriptors: [SelectionListSortDescriptor]
    ) -> Bool {
        for descriptor: SelectionListSortDescriptor in descriptors {
            let comparison: ComparisonResult
            switch descriptor.field {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .path:
                comparison = lhs.parentPath.localizedStandardCompare(rhs.parentPath)
            case .size:
                comparison = lhs.size == rhs.size
                    ? .orderedSame
                    : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
            }

            guard comparison != .orderedSame else { continue }
            return descriptor.isAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }

        return lhs.fullPath.localizedStandardCompare(rhs.fullPath) != .orderedDescending
    }
}

private extension SelectionListFilter {
    nonisolated func includes(_ item: DiskItem) -> Bool {
        switch self {
        case .all:
            true
        case .kind(let kindName):
            item.kindName == kindName
        }
    }
}
