import Foundation

enum SourcePaletteMetrics {
    static let outerSpacing: CGFloat = 12
    static let tableSpacing: CGFloat = 4
    static let standardFontSize: CGFloat = 11
    static let sourceRowSpacing: CGFloat = 8
    static let sourceColumnSpacing: CGFloat = 16
    static let sourceTextSpacing: CGFloat = 2
    static let sourceIconWidth: CGFloat = 28
    static let sourceRowHeight: CGFloat = 42
    static let tableHorizontalPadding: CGFloat = 8
    static let volumeColumnMinimumWidth: CGFloat = 210
    static let sizeColumnWidth: CGFloat = 88
    static let percentColumnWidth: CGFloat = 52
    static let usageColumnWidth: CGFloat = 96
    static let selectionOpacity: CGFloat = 0.22
    static let listCornerRadius: CGFloat = 4
    static let usageBarHeight: CGFloat = 8
    static let filterSpacing: CGFloat = 18
    static let buttonSpacing: CGFloat = 10
    static let buttonHeight: CGFloat = 30
    static let iconButtonWidth: CGFloat = 30
    static let visibleVolumeRowCount: CGFloat = 6
    static let volumeListHeight: CGFloat = sourceRowHeight * visibleVolumeRowCount
    static let windowPadding: CGFloat = 12
    static let windowMinimumWidth: CGFloat = 798
    static let windowMinimumHeight: CGFloat = 390
    static let scanSettingsPadding: CGFloat = 14
    static let scanSettingsSpacing: CGFloat = 14
    static let scanSettingsDescriptionSpacing: CGFloat = 2
    static let scanSettingsDescriptionIndent: CGFloat = 18
    static let scanSettingsWidth: CGFloat = 380
}

enum SourcePaletteDefaults {
    static let showExternalVolumesKey: String = "DIXShowExternalDevices"
    static let showNetworkVolumesKey: String = "DIXShowNetworkDrives"
    static let showDiskImagesKey: String = "DIXShowMountedImages"
}
