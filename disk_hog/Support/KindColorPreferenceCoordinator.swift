import Combine
import Foundation

nonisolated enum KindColorPreferences {
    static let sharesColorsKey: String = "ShareKindColors"

    static var sharesColors: Bool {
        guard UserDefaults.standard.object(forKey: sharesColorsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: sharesColorsKey)
    }
}

@MainActor
final class KindColorPreferenceCoordinator: ObservableObject {
    static let shared: KindColorPreferenceCoordinator = KindColorPreferenceCoordinator()

    @Published private(set) var sharesColors: Bool

    private init() {
        sharesColors = KindColorPreferences.sharesColors
    }

    func setSharesColors(_ newValue: Bool) {
        guard newValue != sharesColors else {
            return
        }

        sharesColors = newValue
        UserDefaults.standard.set(newValue, forKey: KindColorPreferences.sharesColorsKey)
        ScanWindowRegistry.shared.rebuildPresentationMetricsForColorPreference(newValue)
    }
}
