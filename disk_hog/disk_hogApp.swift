//
//  disk_hogApp.swift
//  disk_hog
//
//

import AppKit
import SwiftUI

@main
struct DiskHogApp: App {
    var body: some Scene {
        WindowGroup("Choose Source to Scan", id: WindowIDs.sourcePalette) {
            ContentView()
        }
        .defaultSize(width: SourcePaletteWindowDefaults.width, height: SourcePaletteWindowDefaults.height)

        WindowGroup("Disk Hog", for: ScanSource.self) { source in
            if let source: ScanSource = source.wrappedValue {
                ScanWindowView(source: source)
            } else {
                SourcePaletteView()
            }
        }
        .commands {
            DiskHogCommands()
        }
    }
}

private struct DiskHogCommands: Commands {
    @ObservedObject private var commandState: SourcePaletteCommandState = .shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Choose Folder to Scan") {
                NotificationCenter.default.post(name: .sourcePaletteChooseFolderToScan, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Scan Selected Volume") {
                NotificationCenter.default.post(name: .sourcePaletteScanSelectedVolume, object: nil)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(commandState.canScanSelectedVolume == false)
        }
    }
}

private enum WindowIDs {
    static let sourcePalette: String = "sourcePalette"
}

private enum SourcePaletteWindowDefaults {
    static let width: CGFloat = SourcePaletteMetrics.windowMinimumWidth
    static let height: CGFloat = SourcePaletteMetrics.windowMinimumHeight
}
