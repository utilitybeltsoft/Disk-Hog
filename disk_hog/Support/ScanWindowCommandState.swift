import AppKit
import Combine
import Foundation

@MainActor
final class ScanWindowCommandState: ObservableObject {
    static let shared: ScanWindowCommandState = ScanWindowCommandState()

    @Published var canOpenSelectedItem: Bool = false
    @Published var canRevealSelectedItem: Bool = false
    #if FILE_MATCHING_DIAGNOSTICS
    @Published var canCopyMatchingFile: Bool = false
    #endif

    private weak var activeSession: ScanSession?
    private weak var selectedItem: DiskItem?

    private init() {}

    func activate(session: ScanSession, selectedItem: DiskItem?) {
        activeSession = session
        updateSelectedItemAvailability(selectedItem)
        updateScanState(from: session)
    }

    func updateSelectedItem(_ item: DiskItem?, from session: ScanSession) {
        guard activeSession === session else {
            return
        }

        updateSelectedItemAvailability(item)
    }

    func updateScanState(from session: ScanSession) {
        guard activeSession === session else {
            return
        }

        #if FILE_MATCHING_DIAGNOSTICS
        canCopyMatchingFile = session.rootItem != nil && session.diagnosticsExportState.isWriting == false
        #endif
    }

    func openSelectedItem() {
        guard canOpenSelectedItem, let selectedItem: DiskItem else {
            return
        }

        NSWorkspace.shared.open(selectedItem.url)
    }

    func revealSelectedItemInFinder() {
        guard canRevealSelectedItem, let selectedItem: DiskItem else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([selectedItem.url])
    }

    private func updateSelectedItemAvailability(_ item: DiskItem?) {
        selectedItem = item
        let canActOnItem: Bool = item?.isSpecialItem == false
        canOpenSelectedItem = canActOnItem
        canRevealSelectedItem = canActOnItem
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() {
        guard canCopyMatchingFile else {
            return
        }

        activeSession?.exportTreemapInputDiagnostics()
        if let activeSession: ScanSession {
            updateScanState(from: activeSession)
        }
    }
    #endif
}
