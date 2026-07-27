import AppKit
import Combine
import Foundation

@MainActor
final class PackageContentsPreferenceCoordinator: ObservableObject {
    static let shared: PackageContentsPreferenceCoordinator = PackageContentsPreferenceCoordinator()

    @Published private(set) var showPackageContents: Bool

    private var pendingShowPackageContents: Bool?

    private init() {
        showPackageContents = UserDefaults.standard.bool(
            forKey: DiskScanSettingsDefaultsKeys.showPackageContents
        )
    }

    func requestChange(to newValue: Bool) {
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
            self.applyChange(to: newValue)
        }
    }

    private func applyChange(to newValue: Bool) {
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
            ? "Rescan the Open Scan Window?"
            : "Rescan All Open Scan Windows?"
        alert.informativeText = newValue
            ? "Showing package contents changes which files and folders are included. Rescan now to apply this setting to existing results."
            : "Hiding package contents changes which files and folders are included. Rescan now to apply this setting to existing results."
        alert.alertStyle = .informational
        alert.addButton(withTitle: affectedSessions.count == 1 ? "Rescan" : "Rescan All")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            ScanWindowRegistry.shared.rescanAllForPackageContentsPreference(newValue)
        } else {
            ScanWindowRegistry.shared.markPackageContentsSynchronization(with: newValue)
        }
    }

    func rescan(_ session: ScanSession) {
        session.rescanForPackageContentsPreference(showPackageContents)
    }
}
