import AppKit
import Combine
import SwiftUI

enum InspectorPaletteTab: String, CaseIterable, Identifiable {
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

    var layout: InspectorPaletteLayout {
        switch self {
        case .information:
            InspectorPaletteLayout(
                preferredContentSize: NSSize(width: 620, height: 520),
                minimumContentSize: NSSize(width: 480, height: 360)
            )
        case .diskUsage:
            InspectorPaletteLayout(
                preferredContentSize: NSSize(width: 460, height: 520),
                minimumContentSize: NSSize(width: 400, height: 440)
            )
        case .selectionList:
            InspectorPaletteLayout(
                preferredContentSize: NSSize(width: 720, height: 440),
                minimumContentSize: NSSize(width: 520, height: 320)
            )
        }
    }
}

struct InspectorPaletteLayout {
    let preferredContentSize: NSSize
    let minimumContentSize: NSSize
}

@MainActor
final class InspectorPaletteController: NSObject, ObservableObject {
    static let shared: InspectorPaletteController = InspectorPaletteController()

    @Published private(set) var activeContext: InspectorPaletteContext?
    @Published private(set) var isVisible: Bool = false
    @Published var selectedTab: InspectorPaletteTab = .information {
        didSet {
            guard selectedTab != oldValue else {
                return
            }
            resizePanel(from: oldValue, to: selectedTab)
        }
    }

    private var panelController: NSWindowController?
    private var contentSizesByTab: [InspectorPaletteTab: NSSize] = [:]

    private override init() {
        super.init()
    }

    func activate(_ context: InspectorPaletteContext) {
        activeContext = context
        updateWindowTitle()
    }

    func deactivate(if context: InspectorPaletteContext? = nil) {
        if let context, activeContext !== context {
            return
        }
        activeContext = nil
        updateWindowTitle()
    }

    func show(tab: InspectorPaletteTab? = nil) {
        if let tab {
            selectedTab = tab
        }

        let panelController: NSWindowController = panelController ?? makePanelController()
        self.panelController = panelController
        updateWindowTitle()
        panelController.window?.orderFront(nil)
        isVisible = true
    }

    func toggle() {
        if let window: NSWindow = panelController?.window, window.isVisible {
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
              let context: InspectorPaletteContext = activeContext,
              session == nil || context.session === session else {
            return
        }

        context.selectKind(kindName)
        show(tab: .selectionList)
    }

    func showSelectionList(filter: SelectionListFilter, from session: ScanSession) {
        guard let context: InspectorPaletteContext = activeContext,
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

    func automaticallyShowDiskUsageIfNeeded(for context: InspectorPaletteContext) {
        guard context.isVolumeScan, !context.didAutomaticallyShowDiskUsage else {
            return
        }

        context.markDiskUsageAutomaticallyShown()
        activate(context)
        show(tab: .diskUsage)
    }

    private func makePanelController() -> NSWindowController {
        let layout: InspectorPaletteLayout = selectedTab.layout
        let contentSize: NSSize = contentSizesByTab[selectedTab] ?? layout.preferredContentSize
        let contentRect: NSRect = NSRect(origin: .zero, size: contentSize)
        let panel: NSPanel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setFrameAutosaveName("DiskHogInspectorPalette")
        panel.contentMinSize = layout.minimumContentSize
        panel.contentViewController = NSHostingController(
            rootView: InspectorPaletteView(controller: self)
        )
        panel.center()
        return NSWindowController(window: panel)
    }

    private func resizePanel(from oldTab: InspectorPaletteTab, to newTab: InspectorPaletteTab) {
        guard let panel: NSWindow = panelController?.window else {
            return
        }

        contentSizesByTab[oldTab] = panel.contentLayoutRect.size

        let layout: InspectorPaletteLayout = newTab.layout
        let targetContentSize: NSSize = contentSizesByTab[newTab] ?? layout.preferredContentSize
        panel.contentMinSize = layout.minimumContentSize

        let targetFrameSize: NSSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var targetFrame: NSRect = panel.frame
        targetFrame.origin.y = targetFrame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize
        if let screen: NSScreen = panel.screen {
            targetFrame = panel.constrainFrameRect(targetFrame, to: screen)
        }
        panel.setFrame(targetFrame, display: true, animate: panel.isVisible)
    }

    private func updateWindowTitle() {
        guard let window: NSWindow = panelController?.window else {
            return
        }

        if let context: InspectorPaletteContext = activeContext {
            window.title = "Inspector - \(context.session.source.displayName)"
        } else {
            window.title = "Inspector"
        }
    }
}

extension InspectorPaletteController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}
