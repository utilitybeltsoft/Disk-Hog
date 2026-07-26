import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let sourceWindowChooseFolderToScan: Notification.Name = Notification.Name("sourceWindowChooseFolderToScan")
    static let sourceWindowScanSelectedVolume: Notification.Name = Notification.Name("sourceWindowScanSelectedVolume")
}

@MainActor
final class SourceWindowCommandState: ObservableObject {
    static let shared: SourceWindowCommandState = SourceWindowCommandState()

    @Published var canScanSelectedVolume: Bool = false

    private init() {}
}
