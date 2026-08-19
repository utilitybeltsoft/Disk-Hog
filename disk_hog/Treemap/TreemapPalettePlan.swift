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
        var pendingItems: [DiskItem] = [rootItem]
        while let item: DiskItem = pendingItems.popLast() {
            visitedItemCount += 1
            if visitedItemCount.isMultiple(of: progressUpdateStride)
                || visitedItemCount == totalItemCount {
                progress?(min(Double(visitedItemCount) / Double(totalItemCount), 1))
            }

            if item.isFolder && !item.isPackage {
                pendingItems.append(contentsOf: item.children)
                continue
            }

            let kindName: String = item.resolvedKindName(folderName: folderKindName)
            guard !kindName.isEmpty else {
                continue
            }

            var aggregate: TreemapKindAggregate = aggregatesByKind[kindName] ?? TreemapKindAggregate()
            aggregate.size += item.sizeValue(usePhysicalSize: usePhysicalSize)
            aggregate.fileCount += 1
            aggregatesByKind[kindName] = aggregate
        }
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

}

nonisolated struct TreemapRawColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

nonisolated enum TreemapColorScheme: String, CaseIterable, Sendable {
    case diskHog
    case diskInventoryZ
}

nonisolated struct TreemapPalettePlan: Sendable {
    private static let goldenRatioConjugate: Double = 0.618_033_988_749_895
    private static let generatedSaturations: [Double] = [0.70, 0.85, 0.55]
    private static let generatedBrightnesses: [Double] = [0.92, 0.76, 0.62]
    private static let sharedGeneratedColorCount: Int = 512

    let orderedKinds: [String]
    private let rawColorsByKind: [String: TreemapRawColor]
    let fallbackFolderColor: TreemapRawColor

    init(orderedKinds: [String], colorScheme: TreemapColorScheme = .diskHog) {
        self.orderedKinds = orderedKinds
        var rawColorsByKind: [String: TreemapRawColor] = [:]
        for (index, kindName) in orderedKinds.enumerated() {
            rawColorsByKind[kindName] = Self.rawColor(at: index, colorScheme: colorScheme)
        }
        self.rawColorsByKind = rawColorsByKind
        fallbackFolderColor = Self.rawColor(at: orderedKinds.count, colorScheme: colorScheme)
    }

    func rawColor(forKind kindName: String) -> TreemapRawColor {
        rawColorsByKind[kindName] ?? fallbackFolderColor
    }

    static func rawColor(at index: Int, colorScheme: TreemapColorScheme = .diskHog) -> TreemapRawColor {
        guard index < predefinedColors.count else {
            if colorScheme == .diskInventoryZ {
                let component: Double = min(Double(index) * 0.05, 0.9)
                return TreemapRawColor(red: component, green: component, blue: component, alpha: 1)
            }
            return generatedColor(at: index - predefinedColors.count)
        }
        return predefinedColors[index]
    }

    static let sharedColorCount: Int = predefinedColors.count + sharedGeneratedColorCount

    private static func generatedColor(at index: Int) -> TreemapRawColor {
        let hue: Double = (Double(index) * goldenRatioConjugate)
            .truncatingRemainder(dividingBy: 1)
        let saturation: Double = generatedSaturations[index % generatedSaturations.count]
        let brightnessIndex: Int = (index / generatedSaturations.count) % generatedBrightnesses.count
        let brightness: Double = generatedBrightnesses[brightnessIndex]

        return rawColor(hue: hue, saturation: saturation, brightness: brightness)
    }

    private static func rawColor(hue: Double, saturation: Double, brightness: Double) -> TreemapRawColor {
        let scaledHue: Double = hue * 6
        let sector: Int = Int(scaledHue.rounded(.down))
        let fraction: Double = scaledHue - Double(sector)

        let p: Double = brightness * (1 - saturation)
        let q: Double = brightness * (1 - saturation * fraction)
        let t: Double = brightness * (1 - saturation * (1 - fraction))

        switch sector % 6 {
        case 0:
            return TreemapRawColor(red: brightness, green: t, blue: p, alpha: 1)
        case 1:
            return TreemapRawColor(red: q, green: brightness, blue: p, alpha: 1)
        case 2:
            return TreemapRawColor(red: p, green: brightness, blue: t, alpha: 1)
        case 3:
            return TreemapRawColor(red: p, green: q, blue: brightness, alpha: 1)
        case 4:
            return TreemapRawColor(red: t, green: p, blue: brightness, alpha: 1)
        default:
            return TreemapRawColor(red: brightness, green: p, blue: q, alpha: 1)
        }
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
