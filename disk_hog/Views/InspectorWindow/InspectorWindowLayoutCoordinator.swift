import AppKit

@MainActor
final class InspectorWindowLayoutCoordinator {

    func slot(for tab: InspectorWindowTab, context: InspectorWindowContext?, hasSource: Bool = false) -> InspectorContentSizeSlot {
        switch tab {
        case .information:
            context == nil && !hasSource ? .empty : .information
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
        fittedContentSize(for: layout(for: slot), on: screen)
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
