import Foundation

nonisolated enum SelectionListSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case name
    case kind
    case path

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All fields")
        case .name: String(localized: "Name")
        case .kind: String(localized: "Kind")
        case .path: String(localized: "Path")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .all: String(localized: "name, kind, and path")
        case .name: String(localized: "file name")
        case .kind: String(localized: "file kind")
        case .path: String(localized: "file path")
        }
    }

    var helpText: String {
        String(
            localized: "Performs a case-insensitive substring search in \(accessibilityTitle)."
        )
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

nonisolated struct SelectionListQueryResult: Sendable {
    let rows: [SelectionListRow]
    let rowIndexByID: [DiskItemID: Int]

    static let empty: SelectionListQueryResult = SelectionListQueryResult(
        rows: [],
        rowIndexByID: [:]
    )
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
    ) throws -> SelectionListQueryResult {
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
        try Task.checkCancellation()
        filteredRows.sort {
            orderedBefore($0, $1, descriptors: descriptors)
        }
        try Task.checkCancellation()
        var rowIndexByID: [DiskItemID: Int] = [:]
        rowIndexByID.reserveCapacity(filteredRows.count)
        for (index, row) in filteredRows.enumerated() {
            if index.isMultiple(of: cancellationInterval) {
                try Task.checkCancellation()
            }
            rowIndexByID[row.id] = index
        }
        return SelectionListQueryResult(
            rows: filteredRows,
            rowIndexByID: rowIndexByID
        )
    }

    private static func orderedBefore(
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

        return lhs.fullPath.localizedStandardCompare(rhs.fullPath) == .orderedAscending
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
