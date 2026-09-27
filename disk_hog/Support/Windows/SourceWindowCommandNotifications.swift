import Foundation

extension Notification.Name {
    static let sourceWindowAccessDidChange = Notification.Name("sourceWindowAccessDidChange")
    static let sourceWindowChooseFolderToScan: Notification.Name = Notification.Name("sourceWindowChooseFolderToScan")
    static let sourceWindowScanSelectedVolume: Notification.Name = Notification.Name("sourceWindowScanSelectedVolume")
}
