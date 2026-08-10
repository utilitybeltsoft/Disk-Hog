import Combine
import Foundation

nonisolated enum ScanPreferenceDefaults {
    static let sharesKindColorsKey: String = "ShareKindColors"

    static var usesPhysicalSize: Bool {
        bool(
            forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize,
            defaultValue: DiskScanSettings.diskInventoryZDefault.usePhysicalSize
        )
    }

    static var sharesKindColors: Bool {
        bool(forKey: sharesKindColorsKey, defaultValue: true)
    }

    static var ignoreCreatorCode: Bool {
        bool(
            forKey: DiskScanSettingsDefaultsKeys.ignoreCreatorCode,
            defaultValue: DiskScanSettings.diskInventoryZDefault.ignoreCreatorCode
        )
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

@MainActor
final class ScanPreferences: ObservableObject {
    static let shared: ScanPreferences = ScanPreferences()

    @Published private(set) var usesPhysicalSize: Bool
    @Published private(set) var sharesKindColors: Bool
    @Published private(set) var ignoreCreatorCode: Bool

    init() {
        usesPhysicalSize = ScanPreferenceDefaults.usesPhysicalSize
        sharesKindColors = ScanPreferenceDefaults.sharesKindColors
        ignoreCreatorCode = ScanPreferenceDefaults.ignoreCreatorCode
    }

    func setUsesPhysicalSize(_ newValue: Bool) {
        guard newValue != usesPhysicalSize else {
            return
        }

        usesPhysicalSize = newValue
        UserDefaults.standard.set(
            newValue,
            forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize
        )
        ScanWindowRegistry.shared.updateSizeModeForOpenSessions(newValue)
    }

    func setSharesKindColors(_ newValue: Bool) {
        guard newValue != sharesKindColors else {
            return
        }

        sharesKindColors = newValue
        UserDefaults.standard.set(newValue, forKey: ScanPreferenceDefaults.sharesKindColorsKey)
        ScanWindowRegistry.shared.rebuildPresentationMetricsForColorPreference(newValue)
    }

    func setIgnoreCreatorCode(_ newValue: Bool) {
        guard newValue != ignoreCreatorCode else {
            return
        }

        ignoreCreatorCode = newValue
        UserDefaults.standard.set(
            newValue,
            forKey: DiskScanSettingsDefaultsKeys.ignoreCreatorCode
        )
    }

    var scanSettings: DiskScanSettings {
        DiskScanSettings(
            usePhysicalSize: usesPhysicalSize,
            lookInsidePackages: PackageContentsPreferenceCoordinator.shared.showPackageContents,
            ignoreCreatorCode: ignoreCreatorCode
        )
    }
}
