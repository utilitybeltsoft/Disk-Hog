import AppKit
import Combine
import SwiftUI

enum InspectorWindowTab: String, CaseIterable, Identifiable {
    case information
    case diskUsage
    case selectionList
    case cleanupQueue
    case scanIssues

    var id: Self { self }

    var title: String {
        switch self {
        case .information: String(localized: "Information")
        case .diskUsage: String(localized: "Disk Usage")
        case .selectionList: String(localized: "Selection List")
        case .cleanupQueue: String(localized: "Cleanup Queue")
        case .scanIssues: String(localized: "Scan Issues")
        }
    }

    var systemImage: String {
        switch self {
        case .information: "info.circle"
        case .diskUsage: "chart.pie"
        case .selectionList: "list.bullet.rectangle"
        case .cleanupQueue: "trash"
        case .scanIssues: "exclamationmark.triangle"
        }
    }

    var inactiveTitle: String {
        switch self {
        case .diskUsage: String(localized: "No Volume Selected")
        case .information, .selectionList, .scanIssues: String(localized: "No Scan Window Active")
        case .cleanupQueue: String(localized: "Cleanup Queue")
        }
    }

    var inactiveSystemImage: String {
        switch self {
        case .diskUsage: "externaldrive"
        case .information, .selectionList, .scanIssues: "macwindow"
        case .cleanupQueue: "trash"
        }
    }

    var inactiveDescription: String {
        switch self {
        case .diskUsage:
            String(localized: "Select a volume in the source window or activate a volume scan window.")
        case .information:
            String(localized: "Select a scan window to inspect its contents.")
        case .selectionList:
            String(localized: "Select a scan window to view its file selection list.")
        case .cleanupQueue:
            String(localized: "Add files or folders from a scan window to review them here before moving them to Finder Trash.")
        case .scanIssues:
            String(localized: "Select a scan window to view items that could not be scanned.")
        }
    }

    var layout: InspectorWindowLayout {
        let tabBarWidth: CGFloat = InspectorWindowLayout.minimumTabBarWidth
        return switch self {
        case .information:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 720),
                minimumContentSize: NSSize(width: tabBarWidth, height: 360)
            )
        case .diskUsage:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: tabBarWidth, height: 420),
                minimumContentSize: NSSize(width: tabBarWidth, height: 400)
            )
        case .selectionList:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 440),
                minimumContentSize: NSSize(width: tabBarWidth, height: 320)
            )
        case .cleanupQueue:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 780, height: 520),
                minimumContentSize: NSSize(width: max(600, tabBarWidth), height: 380)
            )
        case .scanIssues:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 440),
                minimumContentSize: NSSize(width: tabBarWidth, height: 320)
            )
        }
    }
}

struct InspectorWindowLayout {
    let preferredContentSize: NSSize
    let minimumContentSize: NSSize

    /// Every tab shares the same tab-switcher row at the top of the Inspector
    /// window (Information / Disk Usage / Selection List / Cleanup Queue / Scan
    /// Issues), so no tab's width may go narrower than what that row needs to
    /// show all five labels without truncating the last one.
    static let minimumTabBarWidth: CGFloat = 700

    static let compactDiskUsage: InspectorWindowLayout = InspectorWindowLayout(
        preferredContentSize: NSSize(width: minimumTabBarWidth, height: 350),
        minimumContentSize: NSSize(width: minimumTabBarWidth, height: 340)
    )

    /// Shared by every tab's "nothing to show" placeholder (a scan window isn't
    /// active, or none is selected) - these all render the same simple centered
    /// ContentUnavailableView, so there's no reason for the window to jump
    /// between several different sizes as the user clicks through empty tabs.
    static let empty: InspectorWindowLayout = compactDiskUsage
}

enum InspectorContentSizeSlot: Hashable {
    case empty
    case information
    case compactDiskUsage
    case fullDiskUsage
    case selectionList
    case cleanupQueue
    case scanIssues
}

@MainActor
final class InspectorWindowController: NSObject, ObservableObject {
    static let shared: InspectorWindowController = InspectorWindowController()
    static let frameAutosaveName: String = "DiskHogInspectorWindowV5"
    static let visibleScreenInset: CGFloat = 80

    @Published private(set) var activeContext: InspectorWindowContext?
    @Published private(set) var activeSource: ScanSource?
    @Published private(set) var isVisible: Bool = false
    @Published private(set) var measuredTabBarWidth: CGFloat = InspectorWindowLayout.minimumTabBarWidth
    @Published var selectedTab: InspectorWindowTab = .information {
        didSet {
            guard selectedTab != oldValue else {
                return
            }
            resizeWindow(from: contentSizeSlot(for: oldValue), to: currentContentSizeSlot)
        }
    }

    private var windowHost: InspectorWindowHost?
    private let layoutCoordinator: InspectorWindowLayoutCoordinator = InspectorWindowLayoutCoordinator()
    private let placementCoordinator: InspectorWindowPlacementCoordinator = InspectorWindowPlacementCoordinator()

    var currentLayout: InspectorWindowLayout {
        let layout = layoutCoordinator.layout(for: currentContentSizeSlot)
        return InspectorWindowLayout(
            preferredContentSize: NSSize(width: max(layout.preferredContentSize.width, measuredTabBarWidth),
                                         height: layout.preferredContentSize.height),
            minimumContentSize: NSSize(width: max(layout.minimumContentSize.width, measuredTabBarWidth),
                                       height: layout.minimumContentSize.height)
        )
    }

    func updateTabBarWidth(_ width: CGFloat) {
        let width = max(ceil(width), InspectorWindowLayout.minimumTabBarWidth)
        guard width > measuredTabBarWidth else { return }
        measuredTabBarWidth = width
        if let window = windowHost?.window {
            InspectorWindowSizing.applyMinimum(currentLayout.minimumContentSize, to: window)
        }
    }

    private override init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DISK_HOG_RESET_INSPECTOR_FRAME"] == "1" {
            UserDefaults.standard.removeObject(
                forKey: "NSWindow Frame \(Self.frameAutosaveName)"
            )
        }
        #endif
        super.init()
    }

    func activate(_ context: InspectorWindowContext) {
        let previousContentSizeSlot: InspectorContentSizeSlot = currentContentSizeSlot
        var didChangeContext: Bool = false
        if activeSource != nil {
            activeSource = nil
            didChangeContext = true
        }
        if activeContext !== context {
            activeContext = context
            didChangeContext = true
        }
        guard didChangeContext else {
            return
        }
        resizeWindowIfNeeded(from: previousContentSizeSlot)
        updateWindowTitle()
    }

    func activate(source: ScanSource?) {
        let previousContentSizeSlot: InspectorContentSizeSlot = currentContentSizeSlot
        var didChangeContext: Bool = false
        if activeContext != nil {
            activeContext = nil
            didChangeContext = true
        }
        if activeSource != source {
            activeSource = source
            didChangeContext = true
        }
        guard didChangeContext else {
            return
        }
        resizeWindowIfNeeded(from: previousContentSizeSlot)
        updateWindowTitle()
    }

    func deactivate(if context: InspectorWindowContext? = nil) {
        if let context, activeContext !== context {
            return
        }
        guard activeContext != nil || activeSource != nil else {
            return
        }
        let previousContentSizeSlot: InspectorContentSizeSlot = currentContentSizeSlot
        if activeContext != nil {
            activeContext = nil
        }
        if activeSource != nil {
            activeSource = nil
        }
        resizeWindowIfNeeded(from: previousContentSizeSlot)
        updateWindowTitle()
    }

    func show(tab: InspectorWindowTab? = nil) {
        if let tab {
            selectedTab = tab
        }

        let needsInitialPlacement: Bool = windowHost == nil
        let windowHost: InspectorWindowHost = windowHost ?? makeWindowHost()
        self.windowHost = windowHost
        updateWindowTitle()
        if needsInitialPlacement, let window: NSWindow = windowHost.window {
            placementCoordinator.placeInitially(window)
        }
        windowHost.window?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func toggle() {
        if let window: NSWindow = windowHost?.window, window.isVisible {
            window.orderOut(nil)
            isVisible = false
        } else {
            show()
        }
    }

    func applicationWillResignActive() {
        placementCoordinator.rememberKeyWindow(windowHost?.window)
    }

    func restoreWindowOrderingWhenApplicationBecomesActive() {
        placementCoordinator.restoreOrdering(
            isVisible: isVisible,
            inspectorWindow: windowHost?.window
        )
    }

    func showSelectionList(for item: DiskItem, from session: ScanSession?) {
        guard !item.isFolder,
              let kindName: String = item.kindName,
              !kindName.isEmpty,
              let context: InspectorWindowContext = activeContext,
              session == nil || context.session === session else {
            return
        }

        context.selectKind(kindName)
        show(tab: .selectionList)
    }

    func showInformation(for item: DiskItem, from session: ScanSession?) {
        selectedTab = .information

        guard let context: InspectorWindowContext = activeContext,
              session == nil || context.session === session else {
            return
        }

        context.selectionCoordinator.setSelectedItem(item)
        show()
    }

    func showScanIssues(from session: ScanSession) {
        guard let context: InspectorWindowContext = activeContext,
              context.session === session else {
            return
        }

        show(tab: .scanIssues)
    }

    func showSelectionList(filter: SelectionListFilter, from session: ScanSession) {
        guard let context: InspectorWindowContext = activeContext,
              context.session === session else {
            return
        }

        switch filter {
        case .all:
            context.selectAllKinds()
        case .kind(let kindName):
            context.selectKind(kindName)
        }
        show(tab: .selectionList)
    }

    func automaticallyShowDiskUsageIfNeeded(for context: InspectorWindowContext) {
        guard context.isVolumeScan, !context.didAutomaticallyShowDiskUsage else {
            return
        }

        context.markDiskUsageAutomaticallyShown()
        activate(context)
        show(tab: .diskUsage)
        scheduleInitialArrangementBesideActiveScanWindow()
    }

    func arrangeBesideScanWindowIfNeeded(_ scanWindow: NSWindow, for session: ScanSession) {
        guard selectedTab == .diskUsage,
              activeContext?.session === session,
              session.source.volumeKind != .folder,
              let inspectorWindow: NSWindow = windowHost?.window,
              inspectorWindow.isVisible else {
            return
        }
        placementCoordinator.arrangeBesideScanWindow(
            inspectorWindow,
            scanWindow: scanWindow,
            session: session
        )
    }

    private func makeWindowHost() -> InspectorWindowHost {
        let slot: InspectorContentSizeSlot = currentContentSizeSlot
        let layout: InspectorWindowLayout = layoutCoordinator.layout(for: slot)
        let contentSize: NSSize = layoutCoordinator.preferredContentSize(for: slot, on: NSScreen.main)
        return InspectorWindowHost(
            contentSize: contentSize,
            minimumContentSize: currentLayout.minimumContentSize,
            frameAutosaveName: Self.frameAutosaveName,
            contentView: InspectorWindowView(controller: self),
            minimumSize: { [weak self] in self?.currentLayout.minimumContentSize ?? layout.minimumContentSize },
            onClose: { [weak self] in self?.isVisible = false }
        )
    }

    private var currentContentSizeSlot: InspectorContentSizeSlot {
        contentSizeSlot(for: selectedTab)
    }

    private func contentSizeSlot(for tab: InspectorWindowTab) -> InspectorContentSizeSlot {
        layoutCoordinator.slot(for: tab, context: activeContext, hasSource: activeSource != nil)
    }

    private func resizeWindowIfNeeded(from previousSlot: InspectorContentSizeSlot) {
        let newSlot: InspectorContentSizeSlot = currentContentSizeSlot
        guard previousSlot != newSlot else {
            return
        }
        resizeWindow(from: previousSlot, to: newSlot)
    }

    private func resizeWindow(
        from oldSlot: InspectorContentSizeSlot,
        to newSlot: InspectorContentSizeSlot
    ) {
        guard let window: NSWindow = windowHost?.window else { return }
        layoutCoordinator.resize(window: window, from: oldSlot, to: newSlot)
        InspectorWindowSizing.applyMinimum(currentLayout.minimumContentSize, to: window)
    }

    private func scheduleInitialArrangementBesideActiveScanWindow() {
        guard selectedTab == .diskUsage,
              let context: InspectorWindowContext = activeContext,
              context.isVolumeScan else {
            return
        }

        placementCoordinator.scheduleInitialArrangement(for: context) { [weak self, weak context] scanWindow, session in
            guard let self,
                  let context,
                  self.activeContext === context else {
                return
            }
            self.arrangeBesideScanWindowIfNeeded(scanWindow, for: session)
        }
    }

    private func updateWindowTitle() {
        guard let window: NSWindow = windowHost?.window else {
            return
        }

        window.title = InspectorWindowTitleFormatter.title(
            context: activeContext,
            source: activeSource
        )
    }

}
