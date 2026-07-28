import AppKit

struct OrganizedWindowFrames: Equatable {
    let primary: NSRect
    let accessory: NSRect
}

@MainActor
final class ApplicationWindowOrganizer {
    static let shared: ApplicationWindowOrganizer = ApplicationWindowOrganizer()

    static let windowGap: CGFloat = 12
    static let screenInset: CGFloat = 16

    private init() {}

    func place(_ accessoryWindow: NSWindow, beside primaryWindow: NSWindow) {
        guard let screen: NSScreen = primaryWindow.screen ?? accessoryWindow.screen ?? NSScreen.main else {
            return
        }

        let frames: OrganizedWindowFrames = Self.frames(
            primary: primaryWindow.frame,
            accessory: accessoryWindow.frame,
            visibleFrame: screen.visibleFrame
        )
        primaryWindow.setFrame(frames.primary, display: true, animate: false)
        accessoryWindow.setFrame(frames.accessory, display: true, animate: false)
    }

    static func frames(
        primary: NSRect,
        accessory: NSRect,
        visibleFrame: NSRect
    ) -> OrganizedWindowFrames {
        let groupWidth: CGFloat = primary.width + windowGap + accessory.width
        let horizontalInset: CGFloat = min(
            screenInset,
            max((visibleFrame.width - groupWidth) / 2, 0)
        )
        let verticalInset: CGFloat = min(
            screenInset,
            max((visibleFrame.height - max(primary.height, accessory.height)) / 2, 0)
        )
        let usableFrame: NSRect = visibleFrame.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        )
        guard groupWidth <= usableFrame.width else {
            var fittedAccessory: NSRect = accessory
            fittedAccessory.origin.x = usableFrame.maxX - fittedAccessory.width
            fittedAccessory.origin.y = min(
                max(fittedAccessory.origin.y, usableFrame.minY),
                usableFrame.maxY - fittedAccessory.height
            )
            return OrganizedWindowFrames(primary: primary, accessory: fittedAccessory)
        }

        let preferredGroupX: CGFloat = min(
            max(primary.minX, usableFrame.minX),
            usableFrame.maxX - groupWidth
        )
        let commonTop: CGFloat = min(
            max(primary.maxY, usableFrame.minY + max(primary.height, accessory.height)),
            usableFrame.maxY
        )
        var arrangedPrimary: NSRect = primary
        arrangedPrimary.origin = NSPoint(
            x: preferredGroupX,
            y: commonTop - primary.height
        )
        var arrangedAccessory: NSRect = accessory
        arrangedAccessory.origin = NSPoint(
            x: arrangedPrimary.maxX + windowGap,
            y: commonTop - accessory.height
        )
        return OrganizedWindowFrames(
            primary: arrangedPrimary,
            accessory: arrangedAccessory
        )
    }
}
