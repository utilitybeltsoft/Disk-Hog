import AppKit

enum ScanWindowInitialGeometry {
    static func usableFrame(within visibleFrame: NSRect) -> NSRect {
        let horizontalInset: CGFloat = min(
            ScanWindowGeometry.visibleFrameInset,
            max((visibleFrame.width - ScanWindowGeometry.minimumUsableContentSize.width) / 2, 0)
        )
        let verticalInset: CGFloat = min(
            ScanWindowGeometry.visibleFrameInset,
            max((visibleFrame.height - ScanWindowGeometry.minimumUsableContentSize.height) / 2, 0)
        )
        return visibleFrame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    static func contentSize(fitting visibleFrame: NSRect, desiredContentSize: NSSize, window: NSWindow) -> NSSize {
        let desiredFrameSize: NSSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: desiredContentSize)).size
        let frameWidthOverflow: CGFloat = max(desiredFrameSize.width - visibleFrame.width, 0)
        let frameHeightOverflow: CGFloat = max(desiredFrameSize.height - visibleFrame.height, 0)
        return NSSize(
            width: max(desiredContentSize.width - frameWidthOverflow, ScanWindowGeometry.minimumUsableContentSize.width),
            height: max(desiredContentSize.height - frameHeightOverflow, ScanWindowGeometry.minimumUsableContentSize.height)
        )
    }

    static func frame(_ frame: NSRect, fittingIn visibleFrame: NSRect) -> NSRect {
        var fittedFrame: NSRect = frame
        if fittedFrame.width > visibleFrame.width {
            fittedFrame.size.width = visibleFrame.width
        }
        if fittedFrame.height > visibleFrame.height {
            fittedFrame.size.height = visibleFrame.height
        }
        if fittedFrame.maxX > visibleFrame.maxX {
            fittedFrame.origin.x = visibleFrame.maxX - fittedFrame.width
        }
        if fittedFrame.minX < visibleFrame.minX {
            fittedFrame.origin.x = visibleFrame.minX
        }
        if fittedFrame.maxY > visibleFrame.maxY {
            fittedFrame.origin.y = visibleFrame.maxY - fittedFrame.height
        }
        if fittedFrame.minY < visibleFrame.minY {
            fittedFrame.origin.y = visibleFrame.minY
        }
        return fittedFrame
    }
}

nonisolated enum ScanWindowGeometry {
    static let defaultContentSize: NSSize = NSSize(width: 837, height: 900)
    static let minimumContentSize: NSSize = NSSize(width: 837, height: 720)
    static let minimumUsableContentSize: NSSize = NSSize(width: 640, height: 540)
    static let visibleFrameInset: CGFloat = 16
    static let defaultWidth: CGFloat = defaultContentSize.width
    static let defaultHeight: CGFloat = defaultContentSize.height
    static let minimumWidth: CGFloat = minimumContentSize.width
    static let minimumHeight: CGFloat = minimumContentSize.height
}
