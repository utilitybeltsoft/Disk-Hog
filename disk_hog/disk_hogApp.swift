//
//  disk_hogApp.swift
//  disk_hog
//
//

import AppKit
import SwiftUI

@main
struct DiskHogApp: App {
    @NSApplicationDelegateAdaptor(DiskHogApplicationDelegate.self) private var appDelegate

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

@MainActor
private final class DiskHogApplicationDelegate: NSObject, NSApplicationDelegate {
    private var allowsTerminationAfterConfirmation: Bool = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsTerminationAfterConfirmation {
            return .terminateNow
        }

        let activeScanningSessions: [ScanSession] = ScanWindowRegistry.shared.activeScanningSessions
        guard activeScanningSessions.isEmpty == false else {
            return .terminateNow
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = "Cancel active scans and quit?"
        alert.informativeText = activeScanningSessions.count == 1
            ? "One scan is still running. Quitting Disk Hog will cancel it."
            : "\(activeScanningSessions.count) scans are still running. Quitting Disk Hog will cancel them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Scans and Quit")
        alert.addButton(withTitle: "Keep Scanning")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        ScanWindowRegistry.shared.cancelActiveScans()
        allowsTerminationAfterConfirmation = true
        return .terminateNow
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
    static let width: CGFloat = ScanWindowGeometry.defaultWidth
    static let height: CGFloat = ScanWindowGeometry.defaultHeight
}
