import Foundation

nonisolated enum DiskItemTreeEditor {
    static func replacingSubtree(
        in root: DiskItem,
        atPath targetPath: String,
        with replacement: DiskItem,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        guard root.item(atPath: targetPath) != nil else { return nil }
        if root.path == targetPath {
            return builderCopy(of: replacement).freeze(isRoot: root.isRoot)
        }
        guard let builder: DiskItemBuilder = transformedBuilder(
            from: root,
            targetPath: targetPath,
            replacement: replacement,
            remove: false
        ) else { return nil }
        builder.recalculateSize(usePhysicalSize: usePhysicalSize)
        return builder.freeze(isRoot: root.isRoot)
    }

    static func removingSubtree(
        from root: DiskItem,
        atPath targetPath: String,
        usePhysicalSize: Bool
    ) -> DiskItem? {
        guard root.path != targetPath, root.item(atPath: targetPath) != nil else { return nil }
        guard let builder: DiskItemBuilder = transformedBuilder(
            from: root,
            targetPath: targetPath,
            replacement: nil,
            remove: true
        ) else { return nil }
        builder.recalculateSize(usePhysicalSize: usePhysicalSize)
        return builder.freeze(isRoot: root.isRoot)
    }

    static func reordered(_ root: DiskItem, usePhysicalSize: Bool) -> DiskItem {
        let builder: DiskItemBuilder = builderCopy(of: root)
        builder.recalculateSize(usePhysicalSize: usePhysicalSize)
        return builder.freeze(isRoot: root.isRoot)
    }

    private static func transformedBuilder(
        from root: DiskItem,
        targetPath: String,
        replacement: DiskItem?,
        remove: Bool
    ) -> DiskItemBuilder? {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(metadata: root.itemMetadata)
        var didTransform: Bool = false
        var pending: [(source: DiskItem, destination: DiskItemBuilder)] = [(root, rootBuilder)]

        while let (source, destination) = pending.popLast() {
            for child: DiskItem in source.children {
                if child.path == targetPath {
                    didTransform = true
                    if !remove, let replacement {
                        destination.appendChild(builderCopy(of: replacement), updateSize: false)
                    }
                    continue
                }
                let childBuilder: DiskItemBuilder = destination.makeChild(metadata: child.itemMetadata)
                destination.appendChild(childBuilder, updateSize: false)
                pending.append((child, childBuilder))
            }
        }

        return didTransform ? rootBuilder : nil
    }

    static func builderCopy(of root: DiskItem) -> DiskItemBuilder {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(metadata: root.itemMetadata)
        var pending: [(source: DiskItem, destination: DiskItemBuilder)] = [(root, rootBuilder)]
        while let (source, destination) = pending.popLast() {
            for child: DiskItem in source.children {
                let childBuilder: DiskItemBuilder = destination.makeChild(metadata: child.itemMetadata)
                destination.appendChild(childBuilder, updateSize: false)
                pending.append((child, childBuilder))
            }
        }
        return rootBuilder
    }
}
