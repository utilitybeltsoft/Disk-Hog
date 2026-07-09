import SwiftUI

private struct SelectedScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct HoveredScanItemKey: EnvironmentKey {
    static let defaultValue: Binding<DiskItem?> = .constant(nil)
}

private struct ActiveScanWindowPaneKey: EnvironmentKey {
    static let defaultValue: Binding<ScanWindowPane?> = .constant(nil)
}

extension EnvironmentValues {
    var selectedScanItem: Binding<DiskItem?> {
        get { self[SelectedScanItemKey.self] }
        set { self[SelectedScanItemKey.self] = newValue }
    }

    var hoveredScanItem: Binding<DiskItem?> {
        get { self[HoveredScanItemKey.self] }
        set { self[HoveredScanItemKey.self] = newValue }
    }

    var activeScanWindowPane: Binding<ScanWindowPane?> {
        get { self[ActiveScanWindowPaneKey.self] }
        set { self[ActiveScanWindowPaneKey.self] = newValue }
    }
}
