import AppKit

@MainActor
final class InspectorWindowPlacementCoordinator {
    private var wasInspectorKeyBeforeApplicationDeactivation: Bool = false

    func placeInitially(_ inspectorWindow: NSWindow) {
        ApplicationWindowPlacementService.shared.register(inspectorWindow, role: .inspector)
        ApplicationWindowPlacementService.shared.placeNewWindow(inspectorWindow)
    }

    func rememberKeyWindow(_ inspectorWindow: NSWindow?) {
        wasInspectorKeyBeforeApplicationDeactivation = inspectorWindow?.isKeyWindow == true
    }

    func restoreOrdering(isVisible: Bool, inspectorWindow: NSWindow?) {
        guard isVisible,
              let inspectorWindow,
              inspectorWindow.isVisible else {
            return
        }

        if wasInspectorKeyBeforeApplicationDeactivation {
            inspectorWindow.orderFront(nil)
            return
        }

        let scanWindows: [NSWindow] = ApplicationWindowPlacementService.shared
            .visibleWindows(withRole: .scan)
        inspectorWindow.orderFront(nil)
        let orderByWindowID: [ObjectIdentifier: Int] = Dictionary(
            uniqueKeysWithValues: NSApp.orderedWindows.enumerated().map {
                (ObjectIdentifier($0.element), $0.offset)
            }
        )
        let orderedScanWindows: [NSWindow] = scanWindows.sorted {
            (orderByWindowID[ObjectIdentifier($0)] ?? Int.max)
                < (orderByWindowID[ObjectIdentifier($1)] ?? Int.max)
        }
        for scanWindow: NSWindow in orderedScanWindows.reversed() {
            scanWindow.orderFront(nil)
        }
    }

    func arrangeBesideScanWindow(
        _ inspectorWindow: NSWindow,
        scanWindow: NSWindow,
        session: ScanSession
    ) {
        guard scanWindow.isVisible,
              session.source.volumeKind != .folder else {
            return
        }
        ApplicationWindowPlacementService.shared.placeNewWindow(inspectorWindow)
    }

    func scheduleInitialArrangement(
        for context: InspectorWindowContext,
        arrange: @escaping (NSWindow, ScanSession) -> Void
    ) {
        guard context.isVolumeScan else {
            return
        }

        DispatchQueue.main.async { [weak context] in
            guard let context,
                  let scanWindow: NSWindow = ScanWindowRegistry.shared.window(
                    for: context.session.source
                  ) else {
                return
            }
            arrange(scanWindow, context.session)
        }
    }
}
