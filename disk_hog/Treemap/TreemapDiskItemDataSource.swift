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
        if item === rootItem && index >= item.childCount {
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
        if item === rootItem {
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
        if item === rootItem {
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

    init(rootItem: DiskItem, usePhysicalSize: Bool) {
        var statisticsByKind: [String: TreemapKindStatisticAccumulator] = [:]
        TreemapDiskItemColorTable.collectLeafKindStatistics(from: rootItem, usePhysicalSize: usePhysicalSize, into: &statisticsByKind)
        let orderedKinds: [String] = Self.orderedKinds(from: statisticsByKind)
        let colorTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(orderedKinds: orderedKinds)
        self.colorTable = colorTable
        self.kindStatistics = orderedKinds.map { kindName in
            let accumulator: TreemapKindStatisticAccumulator = statisticsByKind[kindName] ?? TreemapKindStatisticAccumulator()
            return TreemapKindStatistic(
                kindName: kindName,
                size: accumulator.size,
                fileCount: accumulator.fileCount,
                color: colorTable.colorForKind(kindName)
            )
        }
    }

    private static func orderedKinds(from statisticsByKind: [String: TreemapKindStatisticAccumulator]) -> [String] {
        statisticsByKind.keys.sorted { leftKind, rightKind in
            let leftSize: UInt64 = statisticsByKind[leftKind]?.size ?? 0
            let rightSize: UInt64 = statisticsByKind[rightKind]?.size ?? 0
            if leftSize != rightSize {
                return leftSize > rightSize
            }
            return leftKind.localizedStandardCompare(rightKind) == .orderedAscending
        }
    }
}

nonisolated final class TreemapDiskItemColorTable: @unchecked Sendable {
    private let colorsByKind: [String: NSColor]
    private let predefinedColors: [NSColor]
    private let fallbackFolderColor: NSColor

    init(orderedKinds: [String]) {
        self.predefinedColors = Self.makePredefinedColors()
        var colorsByKind: [String: NSColor] = [:]
        for kindIndex: Int in 0..<orderedKinds.count {
            colorsByKind[orderedKinds[kindIndex]] = Self.color(at: kindIndex, predefinedColors: predefinedColors)
        }
        self.colorsByKind = colorsByKind
        self.fallbackFolderColor = Self.color(at: orderedKinds.count, predefinedColors: predefinedColors)
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
        if let color: NSColor = colorsByKind[kind] {
            return color
        }
        return color(at: colorsByKind.count)
    }

    private func color(at index: Int) -> NSColor {
        Self.color(at: index, predefinedColors: predefinedColors)
    }

    private static func color(at index: Int, predefinedColors: [NSColor]) -> NSColor {
        if predefinedColors.count > index {
            return predefinedColors[index]
        }
        var rgbComponent: CGFloat = CGFloat(index) * 0.05
        if rgbComponent > 0.9 {
            rgbComponent = 0.9
        }
        return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: rgbComponent, green: rgbComponent, blue: rgbComponent, alpha: 1))
    }

    private static func makePredefinedColors() -> [NSColor] {
        let rawColors: [NSColor] = [
            NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 0, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 1, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 0.58, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.58, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 1, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 1, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.58, blue: 1, alpha: 1),
            NSColor(calibratedRed: 1, green: 1, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.5, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0.5, green: 0, blue: 1, alpha: 1),
            NSColor(calibratedRed: 0, green: 0.5, blue: 0.5, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.4, blue: 0.7, alpha: 1),
            NSColor(calibratedRed: 0.5, green: 1, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0.6, green: 0.3, blue: 0, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.78, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.55, blue: 1, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.75, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 1, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0, green: 0, blue: 0.65, alpha: 1),
            NSColor(calibratedRed: 0.65, green: 0, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0, green: 0.65, blue: 0, alpha: 1),
            NSColor(calibratedRed: 0, green: 0.65, blue: 0.65, alpha: 1),
            NSColor(calibratedRed: 0.65, green: 0, blue: 0.65, alpha: 1),
            NSColor(calibratedRed: 0.65, green: 0.65, blue: 0, alpha: 1)
        ]
        return rawColors.map { color in
            TreemapCushionRenderer.normalizeColor(color)
        }
    }

    fileprivate static func collectLeafKindStatistics(from item: DiskItem, usePhysicalSize: Bool, into statisticsByKind: inout [String: TreemapKindStatisticAccumulator]) {
        if item.isFolder && !item.isPackage {
            for child: DiskItem in item.children {
                collectLeafKindStatistics(from: child, usePhysicalSize: usePhysicalSize, into: &statisticsByKind)
            }
            return
        }
        let kindName: String = item.resolvedKindName
        guard !kindName.isEmpty else {
            return
        }
        var accumulator: TreemapKindStatisticAccumulator = statisticsByKind[kindName] ?? TreemapKindStatisticAccumulator()
        accumulator.size += item.sizeValue(usePhysicalSize: usePhysicalSize)
        accumulator.fileCount += 1
        statisticsByKind[kindName] = accumulator
    }

}

fileprivate nonisolated struct TreemapKindStatisticAccumulator: Sendable {
    var size: UInt64 = 0
    var fileCount: Int = 0
}
