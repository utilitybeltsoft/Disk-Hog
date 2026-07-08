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
        .defaultSize(width: ScanWindowDefaults.width, height: ScanWindowDefaults.height)
        .commands {
            DiskHogCommands()
        }
    }
}

private struct DiskHogCommands: Commands {
    @ObservedObject private var commandState: SourcePaletteCommandState = .shared
    @ObservedObject private var scanWindowCommandState: ScanWindowCommandState = .shared

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

        CommandGroup(after: .newItem) {
            Button("Open Selected Item") {
                ScanWindowCommandState.shared.openSelectedItem()
            }
            .disabled(scanWindowCommandState.canOpenSelectedItem == false)

            Button("Reveal Selected Item in Finder") {
                ScanWindowCommandState.shared.revealSelectedItemInFinder()
            }
            .disabled(scanWindowCommandState.canRevealSelectedItem == false)
        }

        #if FILE_MATCHING_DIAGNOSTICS
        CommandGroup(after: .saveItem) {
            Button("Copy Matching File") {
                ScanWindowCommandState.shared.copyMatchingFile()
            }
            .disabled(scanWindowCommandState.canCopyMatchingFile == false)
        }
        #endif
    }
}

private enum WindowIDs {
    static let sourcePalette: String = "sourcePalette"
}

private enum SourcePaletteWindowDefaults {
    static let width: CGFloat = SourcePaletteMetrics.windowMinimumWidth
    static let height: CGFloat = SourcePaletteMetrics.windowMinimumHeight
}

private enum ScanWindowDefaults {
    static let width: CGFloat = 837
    static let height: CGFloat = 1080
}
