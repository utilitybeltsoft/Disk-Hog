import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let sourcePaletteChooseFolderToScan: Notification.Name = Notification.Name("sourcePaletteChooseFolderToScan")
    static let sourcePaletteScanSelectedVolume: Notification.Name = Notification.Name("sourcePaletteScanSelectedVolume")
}

@MainActor
final class SourcePaletteCommandState: ObservableObject {
    static let shared: SourcePaletteCommandState = SourcePaletteCommandState()

    @Published var canScanSelectedVolume: Bool = false

    private init() {}
}
