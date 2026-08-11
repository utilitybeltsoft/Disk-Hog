import SwiftUI

nonisolated struct ScanSessionFailureAlertPresentation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let dismissButtonTitle: String

    init(failure: ScanSessionFailure) {
        self.id = failure.id
        self.title = failure.title
        self.message = "\(failure.message)\n\n\(failure.recoverySuggestion)"
        self.dismissButtonTitle = String(localized: "OK")
    }
}

@MainActor
enum ScanSessionFailureAlertBinding {
    static func binding(for session: ScanSession) -> Binding<ScanSessionFailureAlertPresentation?> {
        Binding {
            session.failure.map(ScanSessionFailureAlertPresentation.init)
        } set: { _ in
            session.dismissFailure()
        }
    }
}
