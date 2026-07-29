import AppKit

nonisolated final class TreemapDiskItemDataSource: @unchecked Sendable {
    private let rootItem: DiskItem
    private let showFreeSpace: Bool
    private let showOtherSpace: Bool
    private let freeSpaceItem: DiskItem?
    private let otherSpaceItem: DiskItem?
    private let colorTable: TreemapDiskItemColorTable
    private let usePhysicalSize: Bool

    init(rootItem: DiskItem, usePhysicalSize: Bool = true, showFreeSpace: Bool = false, showOtherSpace: Bool = false, freeSpaceItem: DiskItem? = nil, otherSpaceItem: DiskItem? = nil, presentationMetrics: TreemapPresentationMetrics? = nil) {
        self.rootItem = rootItem
        self.usePhysicalSize = usePhysicalSize
        self.showFreeSpace = showFreeSpace
        self.showOtherSpace = showOtherSpace
        self.freeSpaceItem = freeSpaceItem
        self.otherSpaceItem = otherSpaceItem
        self.colorTable = presentationMetrics?.colorTable ?? TreemapPresentationMetrics(rootItem: rootItem, usePhysicalSize: usePhysicalSize).colorTable
    }

    var root: DiskItem {
        rootItem
    }

    static func kindStatistics(for rootItem: DiskItem, usePhysicalSize: Bool = true) -> [TreemapKindStatistic] {
        TreemapPresentationMetrics(rootItem: rootItem, usePhysicalSize: usePhysicalSize).kindStatistics
    }

    func child(_ index: Int, of item: DiskItem) -> DiskItem {
        if item == rootItem && index >= item.childCount {
            if (index - item.childCount) == 0 {
                return (showOtherSpace ? otherSpaceItem : freeSpaceItem) ?? item
            } else {
                return freeSpaceItem ?? item
            }
        } else {
            return item.child(at: index)
        }
    }

    func isNode(_ item: DiskItem) -> Bool {
        !item.isSpecialItem && item.isFolder && !item.isPackage
    }

    func numberOfChildren(of item: DiskItem) -> Int {
        var childCount: Int = item.childCount
        if item == rootItem {
            if showFreeSpace {
                childCount += 1
            }
            if showOtherSpace {
                childCount += 1
            }
        }
        return childCount
    }

    func weight(of item: DiskItem) -> UInt64 {
        var size: UInt64 = item.sizeValue(usePhysicalSize: usePhysicalSize)
        if item == rootItem {
            if showFreeSpace, let freeSpaceItem: DiskItem = freeSpaceItem {
                size += freeSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)
            }
            if showOtherSpace, let otherSpaceItem: DiskItem = otherSpaceItem {
                size += otherSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize)
            }
        }
        return size
    }

    @MainActor
    func prepareRenderer(_ renderer: TreemapItemRenderer, for item: DiskItem) {
        let color: NSColor = colorTable.color(for: item)
        renderer.setCushionColor(color)
    }

    func shouldSelect(_ item: DiskItem) -> Bool {
        !item.isSpecialItem
    }
}

nonisolated struct TreemapKindStatistic: Identifiable, Sendable {
    let kindName: String
    let size: UInt64
    let fileCount: Int
    let color: NSColor

    var id: String {
        kindName
    }
}

nonisolated final class TreemapPresentationMetrics: @unchecked Sendable {
    let colorTable: TreemapDiskItemColorTable
    let kindStatistics: [TreemapKindStatistic]

    init(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) {
        let statisticsByKind: [String: TreemapKindAggregate] = TreemapKindCatalog.aggregates(
            from: rootItem,
            usePhysicalSize: usePhysicalSize,
            folderKindName: "Folder",
            progress: progress
        )
        let orderedKinds: [String] = TreemapKindCatalog.orderedKinds(from: statisticsByKind)
        let colorTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: orderedKinds,
            sharesKindColors: sharesKindColors
        )
        self.colorTable = colorTable
        self.kindStatistics = orderedKinds.map { kindName in
            let accumulator: TreemapKindAggregate = statisticsByKind[kindName] ?? TreemapKindAggregate()
            return TreemapKindStatistic(
                kindName: kindName,
                size: accumulator.size,
                fileCount: accumulator.fileCount,
                color: colorTable.colorForKind(kindName)
            )
        }
    }

}

nonisolated final class TreemapDiskItemColorTable: @unchecked Sendable {
    private let colorsByKind: [String: NSColor]
    private let fallbackFolderColor: NSColor

    init(orderedKinds: [String], sharesKindColors: Bool = false) {
        var colorsByKind: [String: NSColor] = [:]
        if sharesKindColors {
            let colorIndexes: [String: Int] = SharedKindColorRegistry.shared.colorIndexes(
                for: orderedKinds
            )
            for kindName: String in orderedKinds {
                colorsByKind[kindName] = Self.color(
                    from: TreemapPalettePlan.rawColor(at: colorIndexes[kindName] ?? 0)
                )
            }
        } else {
            let plan: TreemapPalettePlan = TreemapPalettePlan(orderedKinds: orderedKinds)
            for kindName: String in plan.orderedKinds {
                colorsByKind[kindName] = Self.color(from: plan.rawColor(forKind: kindName))
            }
        }
        self.colorsByKind = colorsByKind
        fallbackFolderColor = Self.color(
            from: TreemapRawColor(red: 0.66, green: 0.66, blue: 0.66, alpha: 1)
        )
    }

    func color(for item: DiskItem) -> NSColor {
        switch item.itemType {
        case .fileOrFolder:
            return colorForKind(item.resolvedKindName)
        case .freeSpace:
            return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0.66, green: 0.66, blue: 0.66, alpha: 1))
        case .otherSpace:
            return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0.33, green: 0.33, blue: 0.33, alpha: 1))
        }
    }

    func colorForKind(_ kind: String) -> NSColor {
        colorsByKind[kind] ?? fallbackFolderColor
    }

    private static func color(from rawColor: TreemapRawColor) -> NSColor {
        TreemapCushionRenderer.normalizeColor(
            NSColor(
                calibratedRed: CGFloat(rawColor.red),
                green: CGFloat(rawColor.green),
                blue: CGFloat(rawColor.blue),
                alpha: CGFloat(rawColor.alpha)
            )
        )
    }
}

nonisolated final class SharedKindColorRegistry: @unchecked Sendable {
    static let shared: SharedKindColorRegistry = SharedKindColorRegistry()

    private let lock: NSLock = NSLock()
    private var colorIndexByKind: [String: Int] = [:]

    func colorIndexes(for orderedKinds: [String]) -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }

        for kindName: String in orderedKinds where colorIndexByKind[kindName] == nil {
            colorIndexByKind[kindName] = colorIndexByKind.count
        }
        return Dictionary(
            uniqueKeysWithValues: orderedKinds.compactMap { kindName in
                colorIndexByKind[kindName].map { (kindName, $0) }
            }
        )
    }

    func resetForTesting() {
        lock.lock()
        colorIndexByKind = [:]
        lock.unlock()
    }
}
