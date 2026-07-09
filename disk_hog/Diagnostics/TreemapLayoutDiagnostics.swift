import AppKit
import Foundation

nonisolated enum TreemapLayoutDiagnostics {
    static func recordLayoutChange(
        rootItem: DiskItem,
        size: CGSize,
        renderer: TreemapViewRenderer,
        minimumRenderableSide: CGFloat
    ) {
#if TREEMAP_LAYOUT_DIAGNOSTICS
        writeBounds(rootItem: rootItem, size: size)
        writeLayout(rootItem: rootItem, size: size, renderer: renderer)
        writeLayoutUsingZBoundsIfAvailable(
            rootItem: rootItem,
            minimumRenderableSide: minimumRenderableSide
        )
#endif
    }

    private static func writeBounds(rootItem: DiskItem, size: CGSize) {
        let diagnostics: [String: Any] = [
            "app": "Disk Hog",
            "recordType": "treemap-bounds",
            "rootDisplayName": rootItem.displayName,
            "rootPath": rootItem.path,
            "pointX": 0,
            "pointY": 0,
            "pointWidth": Double(size.width),
            "pointHeight": Double(size.height),
            "layoutX": 0,
            "layoutY": 0,
            "layoutWidth": Double(size.width),
            "layoutHeight": Double(size.height),
            "pointAspect": size.height == 0 ? 0 : Double(size.width / size.height),
            "layoutAspect": size.height == 0 ? 0 : Double(size.width / size.height),
            "timestamp": Date().timeIntervalSince1970
        ]
        let outputURL: URL = URL(fileURLWithPath: "/tmp/diskhog-treemap-bounds.json")

        do {
            let data: Data = try JSONSerialization.data(
                withJSONObject: diagnostics,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: outputURL, options: .atomic)
        } catch {
            NSLog("Disk Hog treemap bounds diagnostics failed: \(String(describing: error))")
        }
    }

    private static func writeLayout(rootItem: DiskItem, size: CGSize, renderer: TreemapViewRenderer) {
        let outputURL: URL = URL(fileURLWithPath: "/tmp/diskhog-treemap-layout.jsonl")
        writeLayout(rootItem: rootItem, size: size, renderer: renderer, outputURL: outputURL)
    }

    private static func writeLayoutUsingZBoundsIfAvailable(rootItem: DiskItem, minimumRenderableSide: CGFloat) {
        let zBoundsURL: URL = URL(fileURLWithPath: "/tmp/disk-inventory-z-treemap-bounds.json")
        guard let data: Data = try? Data(contentsOf: zBoundsURL),
              let object: Any = try? JSONSerialization.jsonObject(with: data),
              let diagnostics: [String: Any] = object as? [String: Any],
              let width: Double = numericValue(from: diagnostics["layoutWidth"]),
              let height: Double = numericValue(from: diagnostics["layoutHeight"]),
              width >= minimumRenderableSide,
              height >= minimumRenderableSide else {
            return
        }

        let size: CGSize = CGSize(width: width, height: height)
        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: rootItem)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        renderer.reloadData()
        renderer.calcLayout(NSRect(origin: .zero, size: size))
        writeLayout(
            rootItem: rootItem,
            size: size,
            renderer: renderer,
            outputURL: URL(fileURLWithPath: "/tmp/diskhog-treemap-layout-zbounds.jsonl")
        )
    }

    private static func writeLayout(rootItem: DiskItem, size: CGSize, renderer: TreemapViewRenderer, outputURL: URL) {
        var lines: [String] = []
        let metadata: [String: Any] = [
            "app": "Disk Hog",
            "recordType": "metadata",
            "rootDisplayName": rootItem.displayName,
            "rootPath": rootItem.path,
            "layoutWidth": Double(size.width),
            "layoutHeight": Double(size.height),
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            lines.append(try jsonLine(for: metadata))
            for row: [String: Any] in renderer.layoutDiagnosticsRows() {
                lines.append(try jsonLine(for: row))
            }
            try lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Disk Hog treemap layout diagnostics failed: \(String(describing: error))")
        }
    }

    private static func numericValue(from value: Any?) -> Double? {
        if let doubleValue: Double = value as? Double {
            return doubleValue
        }

        if let intValue: Int = value as? Int {
            return Double(intValue)
        }

        if let numberValue: NSNumber = value as? NSNumber {
            return numberValue.doubleValue
        }

        return nil
    }

    private static func jsonLine(for dictionary: [String: Any]) throws -> String {
        let data: Data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
