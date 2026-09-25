import Foundation

/// Historical successful data acquisitions, independent of rendering and failed attempts.
nonisolated struct SnapshotFreshness: Equatable, Sendable {
    struct Acquisition: Equatable, Sendable {
        let startedAt: Date
        let finishedAt: Date
        let hasSkippedItems: Bool
    }
    struct PartialRefresh: Equatable, Sendable {
        let path: String
        let acquisition: Acquisition
    }
    private(set) var wholeScan: Acquisition?
    private(set) var latestPartialRefresh: PartialRefresh?

    mutating func record(startedAt: Date, finishedAt: Date, hasSkippedItems: Bool,
                         refreshedPath: String, rootPath: String) {
        let acquisition = Acquisition(startedAt: startedAt, finishedAt: finishedAt,
                                      hasSkippedItems: hasSkippedItems)
        if refreshedPath == rootPath {
            wholeScan = acquisition
            latestPartialRefresh = nil
        } else {
            latestPartialRefresh = PartialRefresh(path: refreshedPath, acquisition: acquisition)
        }
    }
}
