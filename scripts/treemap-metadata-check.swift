import Foundation

// Compile with production DiskItems/Treemap sources, as for treemap-benchmark.
@main struct TreemapMetadataCheck {
    static func main() {
        for directory in [false, true] {
            for package in [false, true] {
                for alias in [false, true] {
                    for kind: String? in [nil, "", "Data"] {
                        // Deliberately use the same path for conflicting recorded flags.
                        // Results must follow the snapshot, not what exists at this path.
                        let builder = DiskItemBuilder(
                            url: URL(fileURLWithPath: "/private/tmp", isDirectory: directory),
                            kindName: kind, isDirectory: directory,
                            isPackage: package, isAliasOrSymbolicLink: alias
                        )
                        let item = builder.freeze()
                        let expectedFolder = directory && !alias
                        let expectedKind = kind ?? (expectedFolder && !package ? "Test Folder" : "")
                        precondition(item.isFolder == expectedFolder)
                        precondition(item.isFolder == builder.isFolder)
                        precondition(item.resolvedKindName(folderName: "Test Folder") == expectedKind)
                        precondition(item.resolvedKindName(folderName: "Test Folder") ==
                                     builder.resolvedKindName(folderName: "Test Folder"))
                        precondition(item.resolvedKindName == builder.resolvedKindName)
                        precondition(item.itemMetadata.url.hasDirectoryPath == directory)
                    }
                }
            }
        }
        // Special items must retain their recorded flag and kind semantics too.
        for type in [DiskItemType.freeSpace, .otherSpace] {
            let item = DiskItem(url: URL(fileURLWithPath: "/unused", isDirectory: false), itemType: type)
            precondition(!item.isFolder && item.resolvedKindName == "")
        }
        print("PASS: packed folder/kind accessors match builder semantics across 24 flag/kind combinations and special items")
    }
}
