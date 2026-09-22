import Foundation

@main struct LargestItemsCheck {
    static func main() throws {
        let count = Int(CommandLine.arguments.dropFirst().first ?? "10000")!
        let builder = DiskItemBuilder(url: URL(fileURLWithPath: "/fixture", isDirectory: true), isDirectory: true)
        for index in 0..<count {
            builder.appendChild(builder.makeChild(
                url: URL(fileURLWithPath: "/fixture/file-\(index)", isDirectory: false),
                allocatedSizeValue: UInt64(index % 397), logicalSizeValue: UInt64(index % 619), kindName: "Data"))
        }
        let folder = builder.makeChild(url: URL(fileURLWithPath: "/fixture/folder", isDirectory: true), isDirectory: true)
        folder.appendChild(folder.makeChild(url: URL(fileURLWithPath: "/fixture/folder/needle", isDirectory: false),
                                           allocatedSizeValue: 9999, logicalSizeValue: 8888, kindName: "Data"))
        builder.appendChild(folder)
        let root = builder.freeze()
        for physical in [true, false] {
            var query = LargestItemsQuery()
            query.usesPhysicalSize = physical
            query.limit = 73
            let start = ProcessInfo.processInfo.systemUptime
            let result = try LargestItemsPipeline.run(root: root, query: query)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let expected = root.allFiles().sorted {
                let a = $0.sizeValue(usePhysicalSize: physical), b = $1.sizeValue(usePhysicalSize: physical)
                return a == b ? $0.path < $1.path : a > b
            }.prefix(73)
            precondition(result.rows.map(\.id) == expected.map(\.id))
            precondition(result.matchingCount == count + 1)
            query.searchText = "needle"
            let searched = try LargestItemsPipeline.run(root: root, query: query)
            precondition(searched.matchingCount == 1 && searched.rows.first?.name == "needle")
            query.searchText = ""
            query.category = .folders
            let folders = try LargestItemsPipeline.run(root: root, query: query)
            precondition(folders.rows.count == 1 && folders.rows[0].name == "folder")
            query.category = .files
            query.depth = .immediateChildren
            let immediate = try LargestItemsPipeline.run(root: root, query: query)
            precondition(immediate.matchingCount == count)
            var checks = 0
            do {
                _ = try LargestItemsPipeline.run(root: root, query: query) {
                    checks += 1
                    if checks == 2 { throw CancellationError() }
                }
                preconditionFailure("Cancelled query returned results")
            } catch is CancellationError {}
            print("PASS: \(count) files, physical=\(physical), bounded ranking/search/folders/scope/cancellation, seconds=\(elapsed)")
        }
    }
}
