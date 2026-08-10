import AppKit

struct InspectorWindowFrameMigration {
    static let diskHogDefaults: InspectorWindowFrameMigration = InspectorWindowFrameMigration(
        previousDefaultContentSizes: [
            .information: [
                NSSize(width: 720, height: 760),
                NSSize(width: 720, height: 680),
                NSSize(width: 720, height: 700)
            ],
            .diskUsage: [
                NSSize(width: 460, height: 520),
                NSSize(width: 460, height: 540),
                NSSize(width: 460, height: 500)
            ]
        ]
    )

    let previousDefaultContentSizes: [InspectorWindowTab: [NSSize]]

    func migratedFrame(
        _ frame: NSRect,
        restoredContentSize: NSSize,
        tab: InspectorWindowTab,
        targetFrameSize: NSSize
    ) -> NSRect {
        guard let previousSizes: [NSSize] = previousDefaultContentSizes[tab],
              previousSizes.contains(where: {
                  abs(restoredContentSize.width - $0.width) < 1
                      && abs(restoredContentSize.height - $0.height) < 1
              }) else {
            return frame
        }

        var migratedFrame: NSRect = frame
        migratedFrame.origin.y = frame.maxY - targetFrameSize.height
        migratedFrame.size = targetFrameSize
        return migratedFrame
    }
}
