import Foundation

struct CoverageReport: Decodable { let targets: [CoverageTarget] }
struct CoverageTarget: Decodable {
    let name: String
    let coveredLines: Int
    let executableLines: Int
    let files: [CoverageFile]
}
struct CoverageFile: Decodable {
    let path: String
    let coveredLines: Int
    let executableLines: Int
    var missing: Int { executableLines - coveredLines }
}
func percent(_ covered: Int, _ total: Int) -> String {
    total == 0 ? "n/a" : String(format: "%.2f%%", 100 * Double(covered) / Double(total))
}
do {
    let report = try JSONDecoder().decode(CoverageReport.self, from: FileHandle.standardInput.readDataToEndOfFile())
    guard let app = report.targets.first(where: { $0.name == "disk_hog.app" }) else {
        throw NSError(domain: "CoverageSummary", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "No Disk Hog app coverage found in this run."])
    }
    print("\nApp line coverage: \(percent(app.coveredLines, app.executableLines)) (\(app.coveredLines)/\(app.executableLines) executable lines)")
    print("Not exercised: \(app.executableLines - app.coveredLines) lines. Coverage measures execution, not correctness.")
    let priorities = ["DiskItemDeletionPolicy.swift", "ScanSessionScanWorker.swift", "ScanSessionTreeWorker.swift",
                      "CleanupQueueStore.swift", "DiskDirectoryTraversal.swift", "ScanIssuesView.swift"]
    print("\nSafety and scan workflow coverage:")
    for name in priorities {
        if let file = app.files.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == name }) {
            print("  \(name): \(percent(file.coveredLines, file.executableLines)) — \(file.missing) lines not exercised")
        }
    }
    print("\nLargest gaps by unexecuted line count (not a severity ranking):")
    for file in app.files.filter({ $0.missing > 0 }).sorted(by: {
        $0.missing == $1.missing ? $0.path < $1.path : $0.missing > $1.missing
    }).prefix(5) {
        print("  \(URL(fileURLWithPath: file.path).lastPathComponent): \(file.missing) lines not exercised")
    }
    print("\nTest-code coverage is excluded from this summary.")
    print("Installed-app UI execution and Full Disk Access are not measured by these percentages.")
} catch {
    FileHandle.standardError.write(Data("Coverage summary unavailable: \(error.localizedDescription)\n".utf8))
    exit(1)
}
