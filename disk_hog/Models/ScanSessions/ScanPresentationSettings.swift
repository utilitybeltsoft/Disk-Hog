import Foundation

nonisolated struct ScanPresentationSettings: Sendable, Equatable {
    var sharesKindColors: Bool = true
    var colorScheme: TreemapColorScheme = .diskHog
}
