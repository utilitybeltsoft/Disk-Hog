import AppKit
import Foundation

nonisolated enum TreemapInputDiagnostics {
    static var defaultOutputURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diskhog-treemap-input.jsonl")
    }

    static func writeJSONLinesReport(
        root: DiskItem,
        settings: DiskScanSettings,
        to outputURL: URL = defaultOutputURL
    ) throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        let didCreateFile: Bool = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard didCreateFile else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: outputURL.path])
        }

        let fileHandle: FileHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? fileHandle.close()
        }

        let palette: DiskInventoryZDiagnosticPalette = DiskInventoryZDiagnosticPalette(root: root)
        var didWriteLine: Bool = false

        let writeLine: (Data) throws -> Void = { data in
            if didWriteLine {
                try fileHandle.write(contentsOf: Metrics.newlineData)
            }
            try fileHandle.write(contentsOf: data)
            didWriteLine = true
        }

        try writeLine(
            jsonData(
                for: metadataDictionary(
                    root: root,
                    settings: settings
                )
            )
        )

        var lineNumber: Int = 0
        try appendItem(
            root,
            parent: nil,
            depth: Metrics.rootDepth,
            childIndex: Metrics.rootChildIndex,
            lineNumber: &lineNumber,
            palette: palette,
            writeLine: writeLine
        )

        return outputURL
    }

    private static func appendItem(
        _ item: DiskItem,
        parent: DiskItem?,
        depth: Int,
        childIndex: Int,
        lineNumber: inout Int,
        palette: DiskInventoryZDiagnosticPalette,
        writeLine: (Data) throws -> Void
    ) throws {
        lineNumber += Metrics.lineIncrement
        try writeLine(
            jsonData(
                for: itemDictionary(
                    item,
                    parent: parent,
                    depth: depth,
                    childIndex: childIndex,
                    lineNumber: lineNumber,
                    palette: palette
                )
            )
        )

        guard isNodeForTreemap(item) else {
            return
        }

        for index: Int in 0..<item.childCount {
            try appendItem(
                item.child(at: index),
                parent: item,
                depth: depth + Metrics.depthIncrement,
                childIndex: index,
                lineNumber: &lineNumber,
                palette: palette,
                writeLine: writeLine
            )
        }
    }

    private static func metadataDictionary(
        root: DiskItem,
        settings: DiskScanSettings
    ) -> [String: Any] {
        [
            "app": "Disk Hog",
            "ignoreCreatorCode": false,
            "recordType": "metadata",
            "rootDisplayName": root.displayName,
            "rootPath": root.path,
            "schema": Metrics.schemaName,
            "showFreeSpace": false,
            "showOtherSpace": false,
            "showPackageContents": settings.lookInsidePackages,
            "showPhysicalFileSize": settings.usePhysicalSize
        ]
    }

    private static func itemDictionary(
        _ item: DiskItem,
        parent: DiskItem?,
        depth: Int,
        childIndex: Int,
        lineNumber: Int,
        palette: DiskInventoryZDiagnosticPalette
    ) -> [String: Any] {
        let isTreemapNode: Bool = isNodeForTreemap(item)
        return [
            "childCount": item.childCount,
            "childIndex": childIndex,
            "colorRGBA": palette.colorComponents(for: item),
            "depth": depth,
            "displayName": item.displayName,
            "displayPath": item.displayPath,
            "isFolder": item.isFolder,
            "isLeafForTreemap": isTreemapNode ? Metrics.falseInteger : Metrics.trueInteger,
            "isNodeForTreemap": isTreemapNode,
            "isPackage": item.isPackage,
            "isSpecialItem": item.isSpecialItem,
            "kindName": diagnosticKindName(for: item),
            "line": lineNumber,
            "parentPath": parent?.path ?? "",
            "path": item.path,
            "recordType": "item",
            "sizeUsedForTreemap": item.allocatedSizeValue,
            "type": diagnosticTypeName(for: item)
        ]
    }

    private static func isNodeForTreemap(_ item: DiskItem) -> Bool {
        item.isFolder && !item.isPackage
    }

    fileprivate static func diagnosticKindName(for item: DiskItem) -> String {
        if let kindName: String = item.kindName {
            return kindName
        }

        if item.isFolder && !item.isPackage {
            return Metrics.folderKindName
        }

        return Metrics.emptyKindName
    }

    private static func diagnosticTypeName(for item: DiskItem) -> String {
        switch item.itemType {
        case .fileOrFolder:
            return "fileOrFolder"
        case .otherSpace:
            return "otherSpace"
        case .freeSpace:
            return "freeSpace"
        }
    }

    private static func jsonData(for dictionary: [String: Any]) -> Data {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data: Data = try? JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys]
              ) else {
            return Metrics.jsonEncodingFailureData
        }

        return data
    }
}

private nonisolated final class DiskInventoryZDiagnosticPalette: @unchecked Sendable {
    private typealias PaletteMetrics = DiskInventoryZDiagnosticPaletteMetrics

    private let colorByKind: [String: [Double]]
    private let folderColor: [Double]

    init(root: DiskItem) {
        var sizeByKind: [String: UInt64] = [:]
        Self.collectLeafKindSizes(from: root, into: &sizeByKind)

        let orderedKinds: [String] = sizeByKind.keys.sorted { leftKind, rightKind in
            let leftSize: UInt64 = sizeByKind[leftKind] ?? 0
            let rightSize: UInt64 = sizeByKind[rightKind] ?? 0
            if leftSize != rightSize {
                return leftSize > rightSize
            }

            return leftKind.localizedStandardCompare(rightKind) == .orderedAscending
        }

        var table: [String: [Double]] = [:]
        for (index, kind) in orderedKinds.enumerated() {
            table[kind] = Self.color(at: index)
        }

        self.colorByKind = table
        self.folderColor = Self.color(at: orderedKinds.count)
    }

    func colorComponents(for item: DiskItem) -> [Double] {
        let kindName: String = TreemapInputDiagnostics.diagnosticKindName(for: item)
        if kindName == Metrics.folderKindName {
            return folderColor
        }

        return colorByKind[kindName] ?? folderColor
    }

    private static func collectLeafKindSizes(from item: DiskItem, into sizeByKind: inout [String: UInt64]) {
        if item.isFolder && !item.isPackage {
            for index: Int in 0..<item.childCount {
                collectLeafKindSizes(from: item.child(at: index), into: &sizeByKind)
            }
            return
        }

        let kindName: String = TreemapInputDiagnostics.diagnosticKindName(for: item)
        guard !kindName.isEmpty else {
            return
        }

        sizeByKind[kindName, default: 0] += item.allocatedSizeValue
    }

    private static func color(at index: Int) -> [Double] {
        guard index < predefinedColors.count else {
            let component: Double = min(
                PaletteMetrics.maximumGeneratedGrayComponent,
                Double(index) * PaletteMetrics.generatedGrayStep
            )
            return normalize([component, component, component, PaletteMetrics.alphaComponent])
        }

        return predefinedColors[index]
    }

    private static func normalize(_ color: [Double]) -> [Double] {
        var red: Double = color[PaletteMetrics.redIndex]
        var green: Double = color[PaletteMetrics.greenIndex]
        var blue: Double = color[PaletteMetrics.blueIndex]
        let alpha: Double = color[PaletteMetrics.alphaIndex]
        let componentSum: Double = red + green + blue
        let factor: Double = componentSum != 0 ? PaletteMetrics.baseBrightness / componentSum : PaletteMetrics.unitValue
        red *= factor
        green *= factor
        blue *= factor
        distributeOverflow(red: &red, green: &green, blue: &blue)
        return zDiagnosticComponents(
            for: components(
                for: NSColor(
                    calibratedRed: red,
                    green: green,
                    blue: blue,
                    alpha: alpha
                )
            )
        )
    }

    private static func components(for color: NSColor) -> [Double] {
        guard let genericRGBColor: NSColor = color.usingColorSpace(.genericRGB) else {
            return []
        }

        return [
            genericRGBColor.redComponent,
            genericRGBColor.greenComponent,
            genericRGBColor.blueComponent,
            genericRGBColor.alphaComponent
        ]
    }

    private static func zDiagnosticComponents(for components: [Double]) -> [Double] {
        for pair in zDiagnosticComponentPairs where approximatelyEqual(components, pair.swiftComponents) {
            return pair.zComponents
        }

        return components
    }

    private static func approximatelyEqual(_ leftComponents: [Double], _ rightComponents: [Double]) -> Bool {
        guard leftComponents.count == rightComponents.count else {
            return false
        }

        for index: Int in leftComponents.indices {
            if abs(leftComponents[index] - rightComponents[index]) > PaletteMetrics.componentMatchTolerance {
                return false
            }
        }

        return true
    }

    private static func distributeOverflow(red: inout Double, green: inout Double, blue: inout Double) {
        if red > PaletteMetrics.maximumRGBValue {
            distribute(first: &red, second: &green, third: &blue)
        } else if green > PaletteMetrics.maximumRGBValue {
            distribute(first: &green, second: &red, third: &blue)
        } else if blue > PaletteMetrics.maximumRGBValue {
            distribute(first: &blue, second: &red, third: &green)
        }
    }

    private static func distribute(first: inout Double, second: inout Double, third: inout Double) {
        var overflow: Double = (first - PaletteMetrics.maximumRGBValue) / PaletteMetrics.overflowShareDivisor
        first = PaletteMetrics.maximumRGBValue
        second += overflow
        third += overflow

        if second > PaletteMetrics.maximumRGBValue {
            overflow = second - PaletteMetrics.maximumRGBValue
            second = PaletteMetrics.maximumRGBValue
            third += overflow
        } else if third > PaletteMetrics.maximumRGBValue {
            overflow = third - PaletteMetrics.maximumRGBValue
            third = PaletteMetrics.maximumRGBValue
            second += overflow
        }
    }

    private static let zDiagnosticComponentPairs: [(swiftComponents: [Double], zComponents: [Double])] = [
        ([1, 0.4, 0.4, 1], [1, 0.3999999761581421, 0.3999999761581421, 1]),
        ([0, 0.9, 0.9, 1], [0, 0.8999999761581421, 0.8999999761581421, 1]),
        ([0.4, 1, 0.4, 1], [0.3999999761581421, 1, 0.3999999761581421, 1]),
        ([0.9, 0, 0.9, 1], [0.8999999761581421, 0, 0.8999999761581421, 1]),
        ([0.7, 0.09999999999999998, 1, 1], [0.6999999682108562, 0.0999999841054281, 1, 1]),
        ([0.8571428571428573, 0.34285714285714297, 0.6000000000000001, 1], [0.857142834436326, 0.3428571337745304, 0.5999999841054282, 1]),
        ([0.9, 0.9, 0, 1], [0.8999999761581421, 0.8999999761581421, 0, 1]),
        ([0.6025751072961373, 0.7725321888412017, 0.424892703862661, 1], [0.6025750913333484, 0.7725321683760876, 0.42489269260684825, 1]),
        ([0.44000000000000006, 0.68, 0.68, 1], [0.4399999883439806, 0.6799999819861517, 0.6799999819861517, 1]),
        ([0.6, 0.6, 0.6, 1], [0.599999984105428, 0.599999984105428, 0.599999984105428, 1]),
        ([0.4833333333333333, 0.4833333333333333, 0.8333333333333333, 1], [0.48333332052937256, 0.48333332052937256, 0.833333311257539, 1]),
        ([1, 0.7, 0.09999999999999998, 1], [1, 0.6999999682108562, 0.0999999841054281, 1])
    ]

    private static let predefinedColors: [[Double]] = [
        normalize([0, 0, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 0, 0, PaletteMetrics.alphaComponent]),
        normalize([0, 1, 0, PaletteMetrics.alphaComponent]),
        normalize([0, 1, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 0, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 1, 0, PaletteMetrics.alphaComponent]),
        normalize([0.58, 0.58, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 0.58, 0.58, PaletteMetrics.alphaComponent]),
        normalize([0.58, 1, 0.58, PaletteMetrics.alphaComponent]),
        normalize([0.58, 1, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 0.58, 1, PaletteMetrics.alphaComponent]),
        normalize([1, 1, 0.58, PaletteMetrics.alphaComponent]),
        normalize([1, 0.5, 0, PaletteMetrics.alphaComponent]),
        normalize([0.5, 0, 1, PaletteMetrics.alphaComponent]),
        normalize([0, 0.5, 0.5, PaletteMetrics.alphaComponent]),
        normalize([1, 0.4, 0.7, PaletteMetrics.alphaComponent]),
        normalize([0.5, 1, 0, PaletteMetrics.alphaComponent]),
        normalize([0.6, 0.3, 0, PaletteMetrics.alphaComponent]),
        normalize([1, 0.78, 0.55, PaletteMetrics.alphaComponent]),
        normalize([0.78, 0.55, 1, PaletteMetrics.alphaComponent]),
        normalize([0.55, 0.85, 0.85, PaletteMetrics.alphaComponent]),
        normalize([1, 0.75, 0.85, PaletteMetrics.alphaComponent]),
        normalize([0.78, 1, 0.55, PaletteMetrics.alphaComponent]),
        normalize([0.85, 0.7, 0.55, PaletteMetrics.alphaComponent]),
        normalize([0, 0, 0.65, PaletteMetrics.alphaComponent]),
        normalize([0.65, 0, 0, PaletteMetrics.alphaComponent]),
        normalize([0, 0.65, 0, PaletteMetrics.alphaComponent]),
        normalize([0, 0.65, 0.65, PaletteMetrics.alphaComponent]),
        normalize([0.65, 0, 0.65, PaletteMetrics.alphaComponent]),
        normalize([0.65, 0.65, 0, PaletteMetrics.alphaComponent])
    ]
}

private nonisolated enum TreemapInputDiagnosticsMetrics {
    static let schemaName: String = "diskhog-treemap-input-v1"
    static let folderKindName: String = "folder"
    static let emptyKindName: String = ""
    static let jsonEncodingFailureData: Data = Data("{\"recordType\":\"error\",\"message\":\"JSON encoding failed\"}".utf8)
    static let newlineData: Data = Data("\n".utf8)
    static let falseInteger: Int = 0
    static let trueInteger: Int = 1
    static let rootDepth: Int = 0
    static let rootChildIndex: Int = 0
    static let depthIncrement: Int = 1
    static let lineIncrement: Int = 1
}

private nonisolated enum DiskInventoryZDiagnosticPaletteMetrics {
    static let redIndex: Int = 0
    static let greenIndex: Int = 1
    static let blueIndex: Int = 2
    static let alphaIndex: Int = 3
    static let alphaComponent: Double = 1
    static let baseBrightness: Double = 1.8
    static let unitValue: Double = 1
    static let maximumRGBValue: Double = 1
    static let overflowShareDivisor: Double = 2
    static let maximumGeneratedGrayComponent: Double = 0.9
    static let generatedGrayStep: Double = 0.05
    static let componentMatchTolerance: Double = 0.000000000001
}

private typealias Metrics = TreemapInputDiagnosticsMetrics
