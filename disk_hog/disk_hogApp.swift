//
//  disk_hogApp.swift
//  disk_hog
//
//

import SwiftUI

@main
struct DiskHogApp: App {
    var body: some Scene {
        WindowGroup("Choose Source", id: WindowIDs.sourcePalette) {
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scan Window") {
                openWindow(id: WindowIDs.sourcePalette)
            }
            .keyboardShortcut("n", modifiers: .command)
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
