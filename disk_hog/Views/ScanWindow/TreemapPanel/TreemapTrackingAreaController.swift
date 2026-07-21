import AppKit

@MainActor
final class TreemapTrackingAreaController {
    private var trackingArea: NSTrackingArea?

    func update(on view: NSView) {
        discard(from: view)
        let trackingArea: NSTrackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    func discard(from view: NSView) {
        if let trackingArea: NSTrackingArea = trackingArea {
            view.removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }
}
