import Combine
import Foundation

nonisolated enum SizeModePreferences {
    static var usesPhysicalSize: Bool {
        guard UserDefaults.standard.object(
            forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize
        ) != nil else {
            return DiskScanSettings.diskInventoryZDefault.usePhysicalSize
        }
        return UserDefaults.standard.bool(
            forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize
        )
    }
}

@MainActor
final class SizeModePreferenceCoordinator: ObservableObject {
    static let shared: SizeModePreferenceCoordinator = SizeModePreferenceCoordinator()

    @Published private(set) var usesPhysicalSize: Bool

    private init() {
        usesPhysicalSize = SizeModePreferences.usesPhysicalSize
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
}
