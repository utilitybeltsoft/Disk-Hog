import AppKit
import Combine
import SwiftUI

enum InspectorWindowTab: String, CaseIterable, Identifiable {
    case information
    case diskUsage
    case selectionList

    var id: Self { self }

    var title: String {
        switch self {
        case .information: "Information"
        case .diskUsage: "Disk Usage"
        case .selectionList: "Selection List"
        }
    }

    var systemImage: String {
        switch self {
        case .information: "info.circle"
        case .diskUsage: "chart.pie"
        case .selectionList: "list.bullet.rectangle"
        }
    }

    var inactiveTitle: String {
        switch self {
        case .diskUsage: "No Volume Selected"
        case .information, .selectionList: "No Scan Window Active"
        }
    }

    var inactiveSystemImage: String {
        switch self {
        case .diskUsage: "externaldrive"
        case .information, .selectionList: "macwindow"
        }
    }

    var inactiveDescription: String {
        switch self {
        case .diskUsage:
            "Select a volume in the source window or activate a volume scan window."
        case .information:
            "Select a scan window to inspect its contents."
        case .selectionList:
            "Select a scan window to view its file selection list."
        }
    }

    var layout: InspectorWindowLayout {
        switch self {
        case .information:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 700),
                minimumContentSize: NSSize(width: 480, height: 360)
            )
        case .diskUsage:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 460, height: 500),
                minimumContentSize: NSSize(width: 400, height: 440)
            )
        case .selectionList:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 440),
                minimumContentSize: NSSize(width: 520, height: 320)
            )
        }
    }
}

struct InspectorWindowLayout {
    let preferredContentSize: NSSize
    let minimumContentSize: NSSize

    static let compactDiskUsage: InspectorWindowLayout = InspectorWindowLayout(
        preferredContentSize: NSSize(width: 460, height: 350),
        minimumContentSize: NSSize(width: 400, height: 340)
    )
}

private enum InspectorContentSizeSlot: Hashable {
    case information
    case compactDiskUsage
    case fullDiskUsage
    case selectionList
}

@MainActor
final class InspectorWindowController: NSObject, ObservableObject {
    static let shared: InspectorWindowController = InspectorWindowController()
    private static let frameAutosaveName: String = "DiskHogInspectorWindowV3"
    private static let visibleScreenInset: CGFloat = 80
    private static let previousDefaultContentSizes: [InspectorWindowTab: [NSSize]] = [
        .information: [
            NSSize(width: 720, height: 760),
            NSSize(width: 720, height: 680)
        ],
        .diskUsage: [
            NSSize(width: 460, height: 520),
            NSSize(width: 460, height: 540),
            NSSize(width: 460, height: 500)
        ]
    ]

    @Published private(set) var activeContext: InspectorWindowContext?
    @Published private(set) var activeSource: ScanSource?
    @Published private(set) var isVisible: Bool = false
    @Published var selectedTab: InspectorWindowTab = .information {
        didSet {
            guard selectedTab != oldValue else {
                return
            }
            resizeWindow(
                from: contentSizeSlot(for: oldValue),
                to: currentContentSizeSlot
            )
        }
    }

    private var windowController: NSWindowController?
    private var contentSizesBySlot: [InspectorContentSizeSlot: NSSize] = [:]

    var currentLayout: InspectorWindowLayout {
        layout(for: currentContentSizeSlot)
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

        let windowController: NSWindowController = windowController ?? makeWindowController()
        self.windowController = windowController
        updateWindowTitle()
        windowController.window?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func toggle() {
        if let window: NSWindow = windowController?.window, window.isVisible {
            window.orderOut(nil)
            isVisible = false
        } else {
            show()
        }
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
    }

    private func makeWindowController() -> NSWindowController {
        let layout: InspectorWindowLayout = currentLayout
        let contentSize: NSSize = contentSizesBySlot[currentContentSizeSlot]
            ?? preferredContentSize(for: layout, on: NSScreen.main)
        let contentRect: NSRect = NSRect(origin: .zero, size: contentSize)
        let window: NSWindow = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        let restoredSavedFrame: Bool = window.setFrameUsingName(Self.frameAutosaveName)
        let restoredFrame: NSRect? = restoredSavedFrame
            ? migratedRestoredFrameIfNeeded(window.frame, for: window, targetContentSize: contentSize)
            : nil
        window.contentMinSize = layout.minimumContentSize
        let hostingController: NSHostingController<InspectorWindowView> = NSHostingController(
            rootView: InspectorWindowView(controller: self)
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController

        if let restoredFrame {
            window.setFrame(restoredFrame, display: false)
        } else {
            window.setContentSize(contentSize)
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return NSWindowController(window: window)
    }

    private func migratedRestoredFrameIfNeeded(
        _ frame: NSRect,
        for window: NSWindow,
        targetContentSize: NSSize
    ) -> NSRect {
        guard let previousSizes: [NSSize] = Self.previousDefaultContentSizes[selectedTab] else {
            return frame
        }

        let restoredContentSize: NSSize = window.contentRect(forFrameRect: frame).size
        let usesPreviousDefaultSize: Bool = previousSizes.contains { previousSize in
            abs(restoredContentSize.width - previousSize.width) < 1
                && abs(restoredContentSize.height - previousSize.height) < 1
        }
        guard usesPreviousDefaultSize else {
            return frame
        }

        let targetFrameSize: NSSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var migratedFrame: NSRect = frame
        migratedFrame.origin.y = frame.maxY - targetFrameSize.height
        migratedFrame.size = targetFrameSize
        return migratedFrame
    }

    private var currentContentSizeSlot: InspectorContentSizeSlot {
        contentSizeSlot(for: selectedTab)
    }

    private func contentSizeSlot(for tab: InspectorWindowTab) -> InspectorContentSizeSlot {
        switch tab {
        case .information:
            .information
        case .diskUsage:
            activeContext?.isVolumeScan == true ? .fullDiskUsage : .compactDiskUsage
        case .selectionList:
            .selectionList
        }
    }

    private func layout(for slot: InspectorContentSizeSlot) -> InspectorWindowLayout {
        switch slot {
        case .information:
            InspectorWindowTab.information.layout
        case .compactDiskUsage:
            .compactDiskUsage
        case .fullDiskUsage:
            InspectorWindowTab.diskUsage.layout
        case .selectionList:
            InspectorWindowTab.selectionList.layout
        }
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
        guard let window: NSWindow = windowController?.window else {
            return
        }

        contentSizesBySlot[oldSlot] = window.contentLayoutRect.size

        let layout: InspectorWindowLayout = layout(for: newSlot)
        let targetContentSize: NSSize = contentSizesBySlot[newSlot]
            ?? preferredContentSize(for: layout, on: window.screen)
        window.contentMinSize = layout.minimumContentSize

        let targetFrameSize: NSSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var targetFrame: NSRect = window.frame
        targetFrame.origin.y = targetFrame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize
        if let screen: NSScreen = window.screen {
            targetFrame = window.constrainFrameRect(targetFrame, to: screen)
        }
        window.setFrame(targetFrame, display: true, animate: window.isVisible)
    }

    private func updateWindowTitle() {
        guard let window: NSWindow = windowController?.window else {
            return
        }

        if let context: InspectorWindowContext = activeContext {
            window.title = "Inspector - \(context.session.source.displayName)"
        } else if let activeSource {
            window.title = "Inspector - \(activeSource.displayName)"
        } else {
            window.title = "Inspector"
        }
    }

    private func preferredContentSize(
        for layout: InspectorWindowLayout,
        on screen: NSScreen?
    ) -> NSSize {
        guard let visibleFrame: NSRect = screen?.visibleFrame else {
            return layout.preferredContentSize
        }

        let availableWidth: CGFloat = max(
            layout.minimumContentSize.width,
            visibleFrame.width - Self.visibleScreenInset
        )
        let availableHeight: CGFloat = max(
            layout.minimumContentSize.height,
            visibleFrame.height - Self.visibleScreenInset
        )
        return NSSize(
            width: min(layout.preferredContentSize.width, availableWidth),
            height: min(layout.preferredContentSize.height, availableHeight)
        )
    }

}

extension InspectorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}
