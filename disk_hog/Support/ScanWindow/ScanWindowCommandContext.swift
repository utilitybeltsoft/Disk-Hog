import Combine
import Foundation

@MainActor
final class ScanWindowCommandContext: ObservableObject {
    @Published var canOpenSelectedItem: Bool = false
    @Published var canRevealSelectedItem: Bool = false
    @Published var canSelectParentFolder: Bool = false
    @Published var canToggleFreeSpace: Bool = false
    @Published var canToggleOtherSpace: Bool = false
    @Published var showsFreeSpace: Bool = false
    @Published var showsOtherSpace: Bool = false
    @Published var canZoomIn: Bool = false
    @Published var canZoomOut: Bool = false
    #if FILE_MATCHING_DIAGNOSTICS
    @Published var canCopyMatchingFile: Bool = false
    #endif

    private weak var session: ScanSession?
    // DiskItem instances are short-lived flyweights over immutable packed storage.
    // Keep the command target alive independently of the selection view's instance.
    private var selectedItem: DiskItem?
    private weak var selectionCoordinator: ScanWindowSelectionCoordinator?
    private weak var treemapNavigation: TreemapNavigationState?

    init(session: ScanSession, selectionCoordinator: ScanWindowSelectionCoordinator, treemapNavigation: TreemapNavigationState) {
        self.session = session
        self.selectionCoordinator = selectionCoordinator
        self.treemapNavigation = treemapNavigation
    }

    var commandSelectedItem: DiskItem? { selectedItem }
    var actionSession: ScanSession? { session }

    func updateSelectedItem(_ selectedItem: DiskItem?) {
        updateSelectedItemAvailability(selectedItem)
    }

    func updateScanState() {
        guard let session: ScanSession else {
            canToggleFreeSpace = false
            canToggleOtherSpace = false
            showsFreeSpace = false
            showsOtherSpace = false
            canZoomIn = false
            canZoomOut = false
            #if FILE_MATCHING_DIAGNOSTICS
            canCopyMatchingFile = false
            #endif
            return
        }
        updateScanState(from: session)
    }

    func deactivate() {
        selectedItem = nil
        setIfChanged(\.canOpenSelectedItem, to: false)
        setIfChanged(\.canRevealSelectedItem, to: false)
        setIfChanged(\.canSelectParentFolder, to: false)
        setIfChanged(\.canToggleFreeSpace, to: false)
        setIfChanged(\.canToggleOtherSpace, to: false)
        setIfChanged(\.showsFreeSpace, to: false)
        setIfChanged(\.showsOtherSpace, to: false)
        setIfChanged(\.canZoomIn, to: false)
        setIfChanged(\.canZoomOut, to: false)
        #if FILE_MATCHING_DIAGNOSTICS
        setIfChanged(\.canCopyMatchingFile, to: false)
        #endif
    }

    func openSelectedItem() {
        guard canOpenSelectedItem, let selectedItem: DiskItem else { return }
        DiskItemWorkspaceActions.open(selectedItem)
    }

    func revealSelectedItemInFinder() {
        guard canRevealSelectedItem, let selectedItem: DiskItem else { return }
        DiskItemWorkspaceActions.revealInFinder(selectedItem)
    }

    func selectParentFolder() {
        guard canSelectParentFolder,
              let session: ScanSession,
              let rootItem: DiskItem = session.rootItem,
              let selectedItem: DiskItem,
              let parent: DiskItem = rootItem.descendantsMatchingAncestorPath(of: selectedItem).dropLast().last else {
            return
        }
        selectionCoordinator?.setSelectedItem(parent)
        updateSelectedItemAvailability(parent)
    }

    func toggleFreeSpace() {
        guard let session: ScanSession else { return }
        session.toggleFreeSpace()
        updateScanState(from: session)
    }

    func toggleOtherSpace() {
        guard let session: ScanSession else { return }
        session.toggleOtherSpace()
        updateScanState(from: session)
    }

    func zoomIn() {
        treemapNavigation?.zoom(into: selectedItem)
        updateSelectedItemAvailability(selectedItem)
    }

    func zoomOut() {
        treemapNavigation?.zoomOut()
        canZoomOut = treemapNavigation?.canZoomOut ?? false
    }

    #if FILE_MATCHING_DIAGNOSTICS
    func copyMatchingFile() {
        guard canCopyMatchingFile else { return }
        session?.exportTreemapInputDiagnostics()
        if let session: ScanSession { updateScanState(from: session) }
    }
    #endif

    private func updateScanState(from session: ScanSession) {
        canToggleFreeSpace = session.canToggleFreeSpace
        canToggleOtherSpace = session.canToggleOtherSpace
        showsFreeSpace = session.showsFreeSpace
        showsOtherSpace = session.showsOtherSpace
        canZoomOut = treemapNavigation?.canZoomOut ?? false
        #if FILE_MATCHING_DIAGNOSTICS
        canCopyMatchingFile = session.rootItem != nil && session.diagnosticsExportState.isWriting == false
        #endif
    }

    private func updateSelectedItemAvailability(_ item: DiskItem?) {
        selectedItem = item
        let canActOnItem: Bool = item?.isSpecialItem == false
        canOpenSelectedItem = canActOnItem
        canRevealSelectedItem = canActOnItem
        canZoomIn = treemapNavigation?.canZoom(into: item) ?? false
        canZoomOut = treemapNavigation?.canZoomOut ?? false
        if let session: ScanSession,
           let rootItem: DiskItem = session.rootItem,
           let item: DiskItem {
            canSelectParentFolder = rootItem.descendantsMatchingAncestorPath(of: item).count > 1
        } else {
            canSelectParentFolder = false
        }
    }

    private func setIfChanged(_ keyPath: ReferenceWritableKeyPath<ScanWindowCommandContext, Bool>, to value: Bool) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }
}
