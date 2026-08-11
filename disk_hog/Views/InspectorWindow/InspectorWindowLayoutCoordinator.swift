import AppKit

@MainActor
final class InspectorWindowLayoutCoordinator {
    private var contentSizesBySlot: [InspectorContentSizeSlot: NSSize] = [:]
    private var pendingInformationContentHeight: CGFloat?
    private var isInformationHeightUpdateScheduled: Bool = false

    func slot(for tab: InspectorWindowTab, context: InspectorWindowContext?) -> InspectorContentSizeSlot {
        switch tab {
        case .information:
            .information
        case .diskUsage:
            context?.isVolumeScan == true ? .fullDiskUsage : .compactDiskUsage
        case .selectionList:
            .selectionList
        case .cleanupQueue:
            .cleanupQueue
        }
    }

    func layout(for slot: InspectorContentSizeSlot) -> InspectorWindowLayout {
        switch slot {
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
        window.contentMinSize = layout.minimumContentSize
        setContentSize(targetContentSize, on: window)
    }

    func scheduleInformationContentHeight(
        _ measuredHeight: CGFloat,
        selectedTab: @escaping () -> InspectorWindowTab,
        window: NSWindow?
    ) {
        guard measuredHeight > 0 else {
            return
        }

        pendingInformationContentHeight = measuredHeight
        guard !isInformationHeightUpdateScheduled else {
            return
        }

        isInformationHeightUpdateScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else {
                return
            }
            self.isInformationHeightUpdateScheduled = false
            guard let measuredHeight: CGFloat = self.pendingInformationContentHeight else {
                return
            }
            self.pendingInformationContentHeight = nil
            self.updateInformationContentHeight(
                measuredHeight,
                selectedTab: selectedTab(),
                window: window
            )
        }
    }

    private func updateInformationContentHeight(
        _ measuredHeight: CGFloat,
        selectedTab: InspectorWindowTab,
        window: NSWindow?
    ) {
        guard selectedTab == .information,
              let window else {
            return
        }

        let currentContentSize: NSSize = window.contentLayoutRect.size
        let targetContentHeight: CGFloat = InspectorInformationSizing.contentHeight(
            measuredInformationHeight: measuredHeight,
            minimumHeight: InspectorWindowTab.information.layout.minimumContentSize.height,
            visibleScreenHeight: window.screen?.visibleFrame.height
        )
        guard abs(currentContentSize.height - targetContentHeight) >= 1 else {
            return
        }

        let targetContentSize: NSSize = NSSize(
            width: currentContentSize.width,
            height: targetContentHeight
        )
        contentSizesBySlot[.information] = targetContentSize
        setContentSize(targetContentSize, on: window)
        window.layoutIfNeeded()
        window.displayIfNeeded()
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
