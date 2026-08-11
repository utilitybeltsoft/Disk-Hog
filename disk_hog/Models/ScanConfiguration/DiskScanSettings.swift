import Foundation

nonisolated struct DiskScanSettings: Codable, Hashable, Sendable {
    var usePhysicalSize: Bool
    var lookInsidePackages: Bool

    static let diskInventoryZDefault: DiskScanSettings = DiskScanSettings(
        usePhysicalSize: true,
        lookInsidePackages: false
    )

}

nonisolated enum DiskScanSettingsDefaultsKeys {
    static let showPackageContents: String = "ShowPackageContents"
    static let showPhysicalFileSize: String = "ShowPhysicalFileSize"
}
