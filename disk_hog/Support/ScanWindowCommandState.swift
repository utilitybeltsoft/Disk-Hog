#if FILE_MATCHING_DIAGNOSTICS
import Combine
import Foundation

@MainActor
final class ScanWindowCommandState: ObservableObject {
    static let shared: ScanWindowCommandState = ScanWindowCommandState()

    @Published var canCopyMatchingFile: Bool = false

    private weak var activeSession: ScanSession?

    private init() {}

    func activate(session: ScanSession) {
        activeSession = session
        update(from: session)
    }

    func update(from session: ScanSession) {
        guard activeSession === session else {
            return
        }

        canCopyMatchingFile = session.rootItem != nil && session.diagnosticsExportState.isWriting == false
    }

    func copyMatchingFile() {
        guard canCopyMatchingFile else {
            return
        }

        activeSession?.exportTreemapInputDiagnostics()
        if let activeSession: ScanSession {
            update(from: activeSession)
        }
    }
}
#endif
