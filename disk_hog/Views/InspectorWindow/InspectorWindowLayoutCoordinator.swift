import AppKit

@MainActor
final class InspectorWindowLayoutCoordinator {
    private var contentSizesBySlot: [InspectorContentSizeSlot: NSSize] = [:]

    func slot(for tab: InspectorWindowTab, context: InspectorWindowContext?) -> InspectorContentSizeSlot {
        switch tab {
        case .information:
            context == nil ? .empty : .information
        case .diskUsage:
            context?.isVolumeScan == true ? .fullDiskUsage : .compactDiskUsage
        case .selectionList:
            context == nil ? .empty : .selectionList
        case .cleanupQueue:
            .cleanupQueue
        case .scanIssues:
            context == nil ? .empty : .scanIssues
        }
    }

    func layout(for slot: InspectorContentSizeSlot) -> InspectorWindowLayout {
        switch slot {
        case .empty:
            .empty
        case .information:
            InspectorWindowTab.information.layout
        case .compactDiskUsage:
            .compactDiskUsage
        case .fullDiskUsage:
            InspectorWindowTab.diskUsage.layout
        case .selectionList:
            InspectorWindowTab.selectionList.layout
        case .cleanupQueue:
            InspectorWindowTab.cleanupQueue.layout
        case .scanIssues:
            InspectorWindowTab.scanIssues.layout
        }
    }

    func preferredContentSize(
        for slot: InspectorContentSizeSlot,
        on screen: NSScreen?
    ) -> NSSize {
        contentSizesBySlot[slot] ?? fittedContentSize(for: layout(for: slot), on: screen)
    }

    func resize(window: NSWindow, from oldSlot: InspectorContentSizeSlot, to newSlot: InspectorContentSizeSlot) {
        guard oldSlot != newSlot else {
            return
        }

        contentSizesBySlot[oldSlot] = window.contentLayoutRect.size
        let layout: InspectorWindowLayout = layout(for: newSlot)
        let targetContentSize: NSSize = preferredContentSize(for: newSlot, on: window.screen)
        InspectorWindowSizing.applyMinimum(layout.minimumContentSize, to: window)
        setContentSize(InspectorWindowSizing.clamped(targetContentSize, minimum: layout.minimumContentSize), on: window)
    }

    private func setContentSize(_ targetContentSize: NSSize, on window: NSWindow) {
        let targetFrameSize: NSSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var targetFrame: NSRect = window.frame
        targetFrame.origin.y = targetFrame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize
        if let screen: NSScreen = window.screen {
            targetFrame = window.constrainFrameRect(targetFrame, to: screen)
        }
        window.setFrame(targetFrame, display: true, animate: false)
    }

    private func fittedContentSize(for layout: InspectorWindowLayout, on screen: NSScreen?) -> NSSize {
        guard let visibleFrame: NSRect = screen?.visibleFrame else {
            return layout.preferredContentSize
        }
        let availableWidth: CGFloat = max(
            layout.minimumContentSize.width,
            visibleFrame.width - InspectorWindowController.visibleScreenInset
        )
        let availableHeight: CGFloat = max(
            layout.minimumContentSize.height,
            visibleFrame.height - InspectorWindowController.visibleScreenInset
        )
        return NSSize(
            width: min(layout.preferredContentSize.width, availableWidth),
            height: min(layout.preferredContentSize.height, availableHeight)
        )
    }
}
