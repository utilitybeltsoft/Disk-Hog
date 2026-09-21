import Foundation

nonisolated struct ScanSkippedItem: Sendable, Equatable, Identifiable {
    let path: String
    let reason: String

    var id: String { path }
}

nonisolated struct DiskScanOutcome: Sendable {
    let item: DiskItem
    let skippedItems: [ScanSkippedItem]
}
