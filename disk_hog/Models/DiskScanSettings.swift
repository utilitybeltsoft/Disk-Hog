import Foundation

nonisolated struct DiskScanSettings: Sendable {
    var usePhysicalSize: Bool
    var lookInsidePackages: Bool

    static let diskInventoryZDefault: DiskScanSettings = DiskScanSettings(
        usePhysicalSize: true,
        lookInsidePackages: false
    )
}
