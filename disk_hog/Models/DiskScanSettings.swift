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

    static func userDefaultsValue(userDefaults: UserDefaults = .standard) -> DiskScanSettings {
        DiskScanSettings(
            usePhysicalSize: userDefaults.object(forKey: DefaultsKeys.showPhysicalFileSize) as? Bool ?? true,
            lookInsidePackages: userDefaults.bool(forKey: DefaultsKeys.showPackageContents),
            ignoreCreatorCode: userDefaults.bool(forKey: DefaultsKeys.ignoreCreatorCode)
        )
    }
}

nonisolated enum DiskScanSettingsDefaultsKeys {
    static let showPackageContents: String = "ShowPackageContents"
    static let ignoreCreatorCode: String = "IgnoreCreatorCode"
    static let showPhysicalFileSize: String = "ShowPhysicalFileSize"
}

private typealias DefaultsKeys = DiskScanSettingsDefaultsKeys
