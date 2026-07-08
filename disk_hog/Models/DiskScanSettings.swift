import Foundation

nonisolated struct DiskScanSettings: Codable, Hashable, Sendable {
    var usePhysicalSize: Bool
    var lookInsidePackages: Bool
    var ignoreCreatorCode: Bool

    static let diskInventoryZDefault: DiskScanSettings = DiskScanSettings(
        usePhysicalSize: true,
        lookInsidePackages: false,
        ignoreCreatorCode: false
    )

}

nonisolated enum DiskScanSettingsDefaultsKeys {
    static let showPackageContents: String = "ShowPackageContents"
    static let ignoreCreatorCode: String = "IgnoreCreatorCode"
    static let showPhysicalFileSize: String = "ShowPhysicalFileSize"
}
