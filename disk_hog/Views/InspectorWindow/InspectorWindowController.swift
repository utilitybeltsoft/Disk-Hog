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

    var layout: InspectorWindowLayout {
        switch self {
        case .information:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 720, height: 680),
                minimumContentSize: NSSize(width: 480, height: 360)
            )
        case .diskUsage:
            InspectorWindowLayout(
                preferredContentSize: NSSize(width: 460, height: 520),
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
}

@MainActor
final class InspectorWindowController: NSObject, ObservableObject {
    static let shared: InspectorWindowController = InspectorWindowController()
    private static let frameAutosaveName: String = "DiskHogInspectorWindowV3"
    private static let visibleScreenInset: CGFloat = 80
    private static let previousInformationContentSizes: [NSSize] = [
        NSSize(width: 720, height: 760),
        NSSize(width: 720, height: 700)
    ]

    @Published private(set) var activeContext: InspectorWindowContext?
    @Published private(set) var isVisible: Bool = false
    @Published var selectedTab: InspectorWindowTab = .information {
        didSet {
            guard selectedTab != oldValue else {
                return
            }
            resizeWindow(from: oldValue, to: selectedTab)
        }
    }

    private var windowController: NSWindowController?
    private var contentSizesByTab: [InspectorWindowTab: NSSize] = [:]

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
        activeContext = context
        updateWindowTitle()
    }

    func deactivate(if context: InspectorWindowContext? = nil) {
        if let context, activeContext !== context {
            return
        }
        activeContext = nil
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
        let layout: InspectorWindowLayout = selectedTab.layout
        let contentSize: NSSize = contentSizesByTab[selectedTab]
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
        guard selectedTab == .information else {
            return frame
        }

        let restoredContentSize: NSSize = window.contentRect(forFrameRect: frame).size
        let usesPreviousDefaultSize: Bool = Self.previousInformationContentSizes.contains { previousSize in
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

    private func resizeWindow(from oldTab: InspectorWindowTab, to newTab: InspectorWindowTab) {
        guard let window: NSWindow = windowController?.window else {
            return
        }

        contentSizesByTab[oldTab] = window.contentLayoutRect.size

        let layout: InspectorWindowLayout = newTab.layout
        let targetContentSize: NSSize = contentSizesByTab[newTab]
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
