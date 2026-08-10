import AppKit
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

    static var showPackageContents: Bool {
        bool(
            forKey: DiskScanSettingsDefaultsKeys.showPackageContents,
            defaultValue: DiskScanSettings.diskInventoryZDefault.lookInsidePackages
        )
    }

    static var sharesKindColors: Bool {
        bool(forKey: sharesKindColorsKey, defaultValue: true)
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
    @Published private(set) var showPackageContents: Bool
    @Published private(set) var sharesKindColors: Bool

    private var pendingShowPackageContents: Bool?

    init() {
        usesPhysicalSize = ScanPreferenceDefaults.usesPhysicalSize
        showPackageContents = ScanPreferenceDefaults.showPackageContents
        sharesKindColors = ScanPreferenceDefaults.sharesKindColors
    }

    func requestShowPackageContentsChange(to newValue: Bool) {
        let effectiveValue: Bool = pendingShowPackageContents ?? showPackageContents
        guard newValue != effectiveValue else {
            return
        }

        pendingShowPackageContents = newValue
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pendingShowPackageContents == newValue else {
                return
            }

            self.pendingShowPackageContents = nil
            self.applyShowPackageContentsChange(to: newValue)
        }
    }

    func rescanForPackageContentsPreference(_ session: ScanSession) {
        session.rescanForPackageContentsPreference(showPackageContents)
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

    var scanSettings: DiskScanSettings {
        DiskScanSettings(
            usePhysicalSize: usesPhysicalSize,
            lookInsidePackages: showPackageContents
        )
    }

    private func applyShowPackageContentsChange(to newValue: Bool) {
        guard newValue != showPackageContents else {
            return
        }

        showPackageContents = newValue
        UserDefaults.standard.set(
            newValue,
            forKey: DiskScanSettingsDefaultsKeys.showPackageContents
        )

        let affectedSessions: [ScanSession] = ScanWindowRegistry.shared.sessionsAffectedByPackageContentsPreference(
            newValue
        )
        guard affectedSessions.isEmpty == false else {
            ScanWindowRegistry.shared.markPackageContentsSynchronization(with: newValue)
            return
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = affectedSessions.count == 1
            ? String(localized: "Rescan the Open Scan Window?")
            : String(localized: "Rescan All Open Scan Windows?")
        alert.informativeText = newValue
            ? String(localized: "Showing package contents changes which files and folders are included. Rescan now to apply this setting to existing results.")
            : String(localized: "Hiding package contents changes which files and folders are included. Rescan now to apply this setting to existing results.")
        alert.alertStyle = .informational
        alert.addButton(
            withTitle: affectedSessions.count == 1
                ? String(localized: "Rescan")
                : String(localized: "Rescan All")
        )
        alert.addButton(withTitle: String(localized: "Not Now"))

        if alert.runModal() == .alertFirstButtonReturn {
            ScanWindowRegistry.shared.rescanAllForPackageContentsPreference(newValue)
        } else {
            ScanWindowRegistry.shared.markPackageContentsSynchronization(with: newValue)
        }
    }
}
