import Foundation

/// Sendable counterpart of the AppKit color table used by the existing view.
/// It keeps treemap preparation independent from NSColor.
nonisolated struct TreemapPlanColorTable: Sendable {
    private let colorsByKind: [String: TreemapRawColor]
    private let fallbackFolderColor: TreemapRawColor

    init(
        orderedKinds: [String],
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) {
        var colors: [String: TreemapRawColor] = [:]
        if sharesKindColors && colorScheme == .diskHog {
            for kind: String in orderedKinds {
                colors[kind] = Self.normalized(
                    TreemapPalettePlan.rawColor(at: SharedKindColorRegistry.colorIndex(for: kind))
                )
            }
        } else {
            let palette: TreemapPalettePlan = TreemapPalettePlan(orderedKinds: orderedKinds, colorScheme: colorScheme)
            for kind: String in orderedKinds {
                colors[kind] = Self.normalized(palette.rawColor(forKind: kind))
            }
        }
        colorsByKind = colors
        fallbackFolderColor = Self.normalized(TreemapRawColor(red: 0.66, green: 0.66, blue: 0.66, alpha: 1))
    }

    func color(for item: DiskItem) -> TreemapRawColor {
        switch item.itemType {
        case .fileOrFolder:
            return colorsByKind[item.resolvedKindName] ?? fallbackFolderColor
        case .freeSpace:
            return fallbackFolderColor
        case .otherSpace:
            return Self.normalized(TreemapRawColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1))
        }
    }

    private static func normalized(_ raw: TreemapRawColor) -> TreemapRawColor {
        var red: Double = raw.red
        var green: Double = raw.green
        var blue: Double = raw.blue
        TreemapColorNormalization.normalize(red: &red, green: &green, blue: &blue, baseBrightness: 1.8)
        return TreemapRawColor(red: red, green: green, blue: blue, alpha: raw.alpha)
    }
}
