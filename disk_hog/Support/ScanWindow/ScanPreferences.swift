import AppKit
import Combine
import Foundation

nonisolated enum ScanPreferenceDefaults {
    static let sharesKindColorsKey: String = "ShareKindColors"
    static let treemapColorSchemeKey: String = "TreemapColorScheme"

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

    static var treemapColorScheme: TreemapColorScheme {
        guard let rawValue: String = UserDefaults.standard.string(forKey: treemapColorSchemeKey),
              let scheme: TreemapColorScheme = TreemapColorScheme(rawValue: rawValue) else {
            return .diskHog
        }
        return scheme
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
    @Published private(set) var treemapColorScheme: TreemapColorScheme

    private var pendingShowPackageContents: Bool?

    private let registry: ScanWindowRegistry
    private let defaults: UserDefaults

    init(registry: ScanWindowRegistry? = nil, defaults: UserDefaults = .standard) {
        let registry = registry ?? .shared
        self.registry = registry
        self.defaults = defaults
        usesPhysicalSize = defaults.object(forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize) as? Bool
            ?? DiskScanSettings.diskInventoryZDefault.usePhysicalSize
        showPackageContents = defaults.object(forKey: DiskScanSettingsDefaultsKeys.showPackageContents) as? Bool
            ?? DiskScanSettings.diskInventoryZDefault.lookInsidePackages
        sharesKindColors = defaults.object(forKey: ScanPreferenceDefaults.sharesKindColorsKey) as? Bool ?? true
        treemapColorScheme = defaults.string(forKey: ScanPreferenceDefaults.treemapColorSchemeKey)
            .flatMap(TreemapColorScheme.init(rawValue:)) ?? .diskHog
    }

    var presentationSettings: ScanPresentationSettings {
        ScanPresentationSettings(sharesKindColors: sharesKindColors, colorScheme: treemapColorScheme)
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
        defaults.set(
            newValue,
            forKey: DiskScanSettingsDefaultsKeys.showPhysicalFileSize
        )
        for session in registry.openSessions {
            session.updateSizeMode(newValue)
        }
    }

    func setSharesKindColors(_ newValue: Bool) {
        guard newValue != sharesKindColors else {
            return
        }

        sharesKindColors = newValue
        defaults.set(newValue, forKey: ScanPreferenceDefaults.sharesKindColorsKey)
        updatePresentationForOpenSessions()
    }

    func setTreemapColorScheme(_ newValue: TreemapColorScheme) {
        guard newValue != treemapColorScheme else {
            return
        }

        treemapColorScheme = newValue
        defaults.set(newValue.rawValue, forKey: ScanPreferenceDefaults.treemapColorSchemeKey)
        updatePresentationForOpenSessions()
    }

    private func updatePresentationForOpenSessions() {
        for session in registry.openSessions {
            session.rebuildPresentationMetrics(
                sharesKindColors: sharesKindColors,
                colorScheme: treemapColorScheme
            )
        }
    }

    private func markPackageContentsSynchronization(with showPackageContents: Bool) {
        for session in registry.openSessions {
            session.updatePackageContentsSynchronization(with: showPackageContents)
        }
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
        defaults.set(
            newValue,
            forKey: DiskScanSettingsDefaultsKeys.showPackageContents
        )

        let affectedSessions = registry.openSessions.filter {
            $0.scanSettings.lookInsidePackages != newValue
        }
        guard affectedSessions.isEmpty == false else {
            markPackageContentsSynchronization(with: newValue)
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
            // Fetch live sessions again after the modal dialog, matching window
            // changes that may have occurred while it was displayed.
            for session in registry.openSessions {
                session.rescanForPackageContentsPreference(newValue)
            }
        } else {
            markPackageContentsSynchronization(with: newValue)
        }
    }
}
