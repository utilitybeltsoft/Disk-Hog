import AppKit

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
    let orderedKindNames: [String]
    let sharesKindColors: Bool
    let colorScheme: TreemapColorScheme

    init(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool = false,
        colorScheme: TreemapColorScheme = .diskHog,
        progress: (@Sendable (Double) -> Void)? = nil
    ) {
        let statisticsByKind: [String: TreemapKindAggregate] = TreemapKindCatalog.aggregates(
            from: rootItem,
            usePhysicalSize: usePhysicalSize,
            folderKindName: String(localized: "Folder"),
            progress: progress
        )
        let orderedKinds: [String] = TreemapKindCatalog.orderedKinds(from: statisticsByKind)
        let colorTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(
            orderedKinds: orderedKinds,
            sharesKindColors: sharesKindColors,
            colorScheme: colorScheme
        )
        self.colorTable = colorTable
        self.orderedKindNames = orderedKinds
        self.sharesKindColors = sharesKindColors
        self.colorScheme = colorScheme
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

    init(
        orderedKinds: [String],
        sharesKindColors: Bool = false,
        colorScheme: TreemapColorScheme = .diskHog
    ) {
        var colorsByKind: [String: NSColor] = [:]
        if sharesKindColors && colorScheme == .diskHog {
            for kindName: String in orderedKinds {
                colorsByKind[kindName] = Self.color(
                    from: TreemapPalettePlan.rawColor(
                        at: SharedKindColorRegistry.colorIndex(for: kindName)
                    )
                )
            }
        } else {
            let plan: TreemapPalettePlan = TreemapPalettePlan(
                orderedKinds: orderedKinds,
                colorScheme: colorScheme
            )
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

nonisolated enum SharedKindColorRegistry {
    /// Uses a fixed hash rather than Swift's randomized `Hasher`, so the same
    /// kind keeps its color across scans and application launches.
    static func colorIndex(for kindName: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte: UInt8 in kindName.precomposedStringWithCanonicalMapping.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(TreemapPalettePlan.sharedColorCount))
    }
}
