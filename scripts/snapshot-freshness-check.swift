import Foundation

@main struct SnapshotFreshnessCheck {
    static func main() {
        let start = Date(timeIntervalSince1970: 100)
        let finish = Date(timeIntervalSince1970: 200)
        var value = SnapshotFreshness()
        precondition(value.wholeScan == nil)
        value.record(startedAt: start, finishedAt: finish, hasSkippedItems: true,
                     refreshedPath: "/scan", rootPath: "/scan")
        let original = value.wholeScan
        precondition(original?.startedAt == start && original?.finishedAt == finish)
        precondition(original?.hasSkippedItems == true)
        value.record(startedAt: finish, finishedAt: finish.addingTimeInterval(20), hasSkippedItems: false,
                     refreshedPath: "/scan/folder", rootPath: "/scan")
        precondition(value.wholeScan == original)
        precondition(value.latestPartialRefresh?.path == "/scan/folder")
        precondition(value.latestPartialRefresh?.acquisition.hasSkippedItems == false)
        value.record(startedAt: finish, finishedAt: finish.addingTimeInterval(30), hasSkippedItems: false,
                     refreshedPath: "/scan", rootPath: "/scan")
        precondition(value.latestPartialRefresh == nil)
        precondition(value.wholeScan?.finishedAt == finish.addingTimeInterval(30))
        precondition(value.wholeScan?.hasSkippedItems == false)
        let independent = SnapshotFreshness()
        precondition(independent.wholeScan == nil)
        print("PASS: whole/partial acquisition intervals, skipped-item provenance, replacement, and independent state")
    }
}
