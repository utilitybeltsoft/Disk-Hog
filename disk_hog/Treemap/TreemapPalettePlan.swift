import Foundation

nonisolated struct TreemapKindAggregate: Sendable {
    var size: UInt64 = 0
    var fileCount: Int = 0
}

nonisolated enum TreemapKindCatalog {
    private static let progressUpdateStride: Int = 4_096

    static func aggregates(
        from rootItem: DiskItem,
        usePhysicalSize: Bool,
        folderKindName: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> [String: TreemapKindAggregate] {
        var aggregatesByKind: [String: TreemapKindAggregate] = [:]
        let counts: (files: Int, folders: Int) = rootItem.scanCounts()
        let totalItemCount: Int = max(counts.files + counts.folders, 1)
        var visitedItemCount: Int = 0
        progress?(0)
        collect(
            from: rootItem,
            usePhysicalSize: usePhysicalSize,
            folderKindName: folderKindName,
            into: &aggregatesByKind,
            visitedItemCount: &visitedItemCount,
            totalItemCount: totalItemCount,
            progress: progress
        )
        return aggregatesByKind
    }

    static func orderedKinds(from aggregatesByKind: [String: TreemapKindAggregate]) -> [String] {
        aggregatesByKind.keys.sorted { leftKind, rightKind in
            let leftSize: UInt64 = aggregatesByKind[leftKind]?.size ?? 0
            let rightSize: UInt64 = aggregatesByKind[rightKind]?.size ?? 0
            if leftSize != rightSize {
                return leftSize > rightSize
            }
            return leftKind.localizedStandardCompare(rightKind) == .orderedAscending
        }
    }

    private static func collect(
        from item: DiskItem,
        usePhysicalSize: Bool,
        folderKindName: String,
        into aggregatesByKind: inout [String: TreemapKindAggregate],
        visitedItemCount: inout Int,
        totalItemCount: Int,
        progress: (@Sendable (Double) -> Void)?
    ) {
        visitedItemCount += 1
        if visitedItemCount.isMultiple(of: progressUpdateStride)
            || visitedItemCount == totalItemCount {
            progress?(min(Double(visitedItemCount) / Double(totalItemCount), 1))
        }

        if item.isFolder && !item.isPackage {
            for child: DiskItem in item.children {
                collect(
                    from: child,
                    usePhysicalSize: usePhysicalSize,
                    folderKindName: folderKindName,
                    into: &aggregatesByKind,
                    visitedItemCount: &visitedItemCount,
                    totalItemCount: totalItemCount,
                    progress: progress
                )
            }
            return
        }

        let kindName: String = item.resolvedKindName(folderName: folderKindName)
        guard !kindName.isEmpty else {
            return
        }

        var aggregate: TreemapKindAggregate = aggregatesByKind[kindName] ?? TreemapKindAggregate()
        aggregate.size += item.sizeValue(usePhysicalSize: usePhysicalSize)
        aggregate.fileCount += 1
        aggregatesByKind[kindName] = aggregate
    }
}

nonisolated struct TreemapRawColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

nonisolated struct TreemapPalettePlan: Sendable {
    private static let generatedGrayStep: Double = 0.05
    private static let maximumGeneratedGrayComponent: Double = 0.9

    let orderedKinds: [String]
    private let rawColorsByKind: [String: TreemapRawColor]
    let fallbackFolderColor: TreemapRawColor

    init(orderedKinds: [String]) {
        self.orderedKinds = orderedKinds
        var rawColorsByKind: [String: TreemapRawColor] = [:]
        for (index, kindName) in orderedKinds.enumerated() {
            rawColorsByKind[kindName] = Self.rawColor(at: index)
        }
        self.rawColorsByKind = rawColorsByKind
        fallbackFolderColor = Self.rawColor(at: orderedKinds.count)
    }

    func rawColor(forKind kindName: String) -> TreemapRawColor {
        rawColorsByKind[kindName] ?? fallbackFolderColor
    }

    static func rawColor(at index: Int) -> TreemapRawColor {
        guard index < predefinedColors.count else {
            let component: Double = min(
                maximumGeneratedGrayComponent,
                Double(index) * generatedGrayStep
            )
            return TreemapRawColor(red: component, green: component, blue: component, alpha: 1)
        }
        return predefinedColors[index]
    }

    private static let predefinedColors: [TreemapRawColor] = [
        TreemapRawColor(red: 0, green: 0, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 0, blue: 0, alpha: 1),
        TreemapRawColor(red: 0, green: 1, blue: 0, alpha: 1),
        TreemapRawColor(red: 0, green: 1, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 0, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 1, blue: 0, alpha: 1),
        TreemapRawColor(red: 0.58, green: 0.58, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 0.58, blue: 0.58, alpha: 1),
        TreemapRawColor(red: 0.58, green: 1, blue: 0.58, alpha: 1),
        TreemapRawColor(red: 0.58, green: 1, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 0.58, blue: 1, alpha: 1),
        TreemapRawColor(red: 1, green: 1, blue: 0.58, alpha: 1),
        TreemapRawColor(red: 1, green: 0.5, blue: 0, alpha: 1),
        TreemapRawColor(red: 0.5, green: 0, blue: 1, alpha: 1),
        TreemapRawColor(red: 0, green: 0.5, blue: 0.5, alpha: 1),
        TreemapRawColor(red: 1, green: 0.4, blue: 0.7, alpha: 1),
        TreemapRawColor(red: 0.5, green: 1, blue: 0, alpha: 1),
        TreemapRawColor(red: 0.6, green: 0.3, blue: 0, alpha: 1),
        TreemapRawColor(red: 1, green: 0.78, blue: 0.55, alpha: 1),
        TreemapRawColor(red: 0.78, green: 0.55, blue: 1, alpha: 1),
        TreemapRawColor(red: 0.55, green: 0.85, blue: 0.85, alpha: 1),
        TreemapRawColor(red: 1, green: 0.75, blue: 0.85, alpha: 1),
        TreemapRawColor(red: 0.78, green: 1, blue: 0.55, alpha: 1),
        TreemapRawColor(red: 0.85, green: 0.7, blue: 0.55, alpha: 1),
        TreemapRawColor(red: 0, green: 0, blue: 0.65, alpha: 1),
        TreemapRawColor(red: 0.65, green: 0, blue: 0, alpha: 1),
        TreemapRawColor(red: 0, green: 0.65, blue: 0, alpha: 1),
        TreemapRawColor(red: 0, green: 0.65, blue: 0.65, alpha: 1),
        TreemapRawColor(red: 0.65, green: 0, blue: 0.65, alpha: 1),
        TreemapRawColor(red: 0.65, green: 0.65, blue: 0, alpha: 1)
    ]
}
