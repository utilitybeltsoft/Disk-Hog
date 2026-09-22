import Foundation

nonisolated struct LargestItemsResult: Sendable {
    let rows: [SelectionListRow]
    let matchingCount: Int
}

nonisolated enum LargestItemsPipeline {
    /// O(N log K) work, O(K + tree depth) live storage. No full child arrays,
    /// metadata reconstruction, or filesystem calls.
    static func run(root: DiskItem, query: LargestItemsQuery,
                    checkCancellation: () throws -> Void = { try Task.checkCancellation() }) rethrows -> LargestItemsResult {
        try checkCancellation()
        var heap: [SelectionListRow] = []
        heap.reserveCapacity(query.boundedLimit)
        var matchingCount = 0
        var visited = 0
        var stack: [(item: DiskItem, nextChild: Int)] = [(root, 0)]
        while var frame = stack.popLast() {
            if visited.isMultiple(of: 256) { try checkCancellation() }
            visited += 1
            guard canTraverse(frame.item, query: query), frame.nextChild < frame.item.childCount else { continue }
            let child = frame.item.child(at: frame.nextChild)
            frame.nextChild += 1
            stack.append(frame)
            if query.depth == .descendants && canTraverse(child, query: query) {
                stack.append((child, 0))
            }
            guard query.category.includes(child, lookInsidePackages: query.lookInsidePackages),
                  query.kind == nil || child.kindName == query.kind else { continue }
            let row = SelectionListRow(item: child, size: child.sizeValue(usePhysicalSize: query.usesPhysicalSize))
            guard query.searchText.isEmpty || row.matches(query.searchText, in: query.searchScope) else { continue }
            matchingCount += 1
            if heap.count < query.boundedLimit {
                heap.append(row)
                var index = heap.count - 1
                while index > 0 {
                    let parent = (index - 1) / 2
                    guard precedes(heap[parent], heap[index]) else { break }
                    heap.swapAt(parent, index)
                    index = parent
                }
            } else if precedes(row, heap[0]) {
                heap[0] = row
                var index = 0
                while index * 2 + 1 < heap.count {
                    var worst = index * 2 + 1
                    if worst + 1 < heap.count && precedes(heap[worst], heap[worst + 1]) { worst += 1 }
                    guard precedes(heap[index], heap[worst]) else { break }
                    heap.swapAt(index, worst)
                    index = worst
                }
            }
        }
        try checkCancellation()
        heap.sort(by: precedes)
        try checkCancellation()
        return LargestItemsResult(rows: heap, matchingCount: matchingCount)
    }

    private static func canTraverse(_ item: DiskItem, query: LargestItemsQuery) -> Bool {
        item.isFolder && !item.isSpecialItem && (!item.isPackage || query.lookInsidePackages)
    }

    private static func precedes(_ lhs: SelectionListRow, _ rhs: SelectionListRow) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        return lhs.fullPath < rhs.fullPath
    }
}
