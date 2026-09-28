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
        Settings {
            EmptyView()
        }
        .commands {
            DiskHogCommands(
                access: DiskHogApplicationDelegate.fullDiskAccess.model,
                showAccessGuidance: { DiskHogApplicationDelegate.fullDiskAccess.showGuidance() },
                showAbout: { DiskHogApplicationDelegate.about.show() }
            )
        }
    }
}

@MainActor
final class DiskHogApplicationDelegate: NSObject, NSApplicationDelegate {
    static let about = AboutWindowController()
    static let fullDiskAccess: FullDiskAccessSetupController = FullDiskAccessSetupController(model: FullDiskAccessSetupModel(
        guidanceWasShown: UserDefaults.standard.bool(forKey: "fullDiskAccessGuidanceShown"),
        recordGuidanceShown: { UserDefaults.standard.set(true, forKey: "fullDiskAccessGuidanceShown") },
        checkAccess: { await FullDiskAccessService().checkAsync() },
        openSettings: {
            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
            return NSWorkspace.shared.open(url)
        },
        accessBecameAvailable: {
            NotificationCenter.default.post(name: .sourceWindowAccessDidChange, object: nil)
        },
        enterApplication: {
            DiskHogApplicationDelegate.fullDiskAccess.window?.orderOut(nil)
            SourceWindowController.shared.show()
        },
        terminate: { NSApp.terminate(nil) }
    ))
    private let registry: ScanWindowRegistry = .shared
    private var allowsTerminationAfterConfirmation: Bool = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip the additional launch probe and setup UI in the isolated unit host.
        if Bundle.main.bundleIdentifier != "software.utilitybelt.diskhog.testhost",
           ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            Self.fullDiskAccess.model.start()
        } else {
            SourceWindowController.shared.show()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.fullDiskAccess.model.applicationDidBecomeActive()
        DispatchQueue.main.async {
            InspectorWindowController.shared.restoreWindowOrderingWhenApplicationBecomesActive()
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        InspectorWindowController.shared.applicationWillResignActive()
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsTerminationAfterConfirmation {
            return .terminateNow
        }

        let activeScanningSessions: [ScanSession] = registry.activeScanningSessions
        guard activeScanningSessions.isEmpty == false else {
            return .terminateNow
        }

        let alert: NSAlert = NSAlert()
        alert.messageText = String(localized: "Cancel active scans and quit Disk Hog?")
        alert.informativeText = activeScanningSessions.count == 1
            ? String(localized: "One scan is still running. Quitting Disk Hog will cancel it.")
            : String(localized: "\(activeScanningSessions.count) scans are still running. Quitting Disk Hog will cancel them.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Cancel Scans and Quit"))
        alert.addButton(withTitle: String(localized: "Keep Scanning"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        registry.cancelActiveScans()
        allowsTerminationAfterConfirmation = true
        return .terminateNow
    }
}

private struct DiskHogCommands: Commands {
    @ObservedObject private var scanWindowCommandState: ScanWindowCommandState = .shared
    @ObservedObject var access: FullDiskAccessSetupModel
    let showAccessGuidance: () -> Void
    let showAbout: () -> Void
    @ObservedObject private var appCommandRouter: AppCommandRouter = .shared
    @ObservedObject private var cleanupQueueStore: CleanupQueueStore = .shared
    @ObservedObject private var inspectorWindowController: InspectorWindowController = .shared
    @ObservedObject private var scanPreferences: ScanPreferences = .shared

    var body: some Commands {
        let _ = cleanupQueueStore.items

        CommandGroup(replacing: .appInfo) {
            Button("About Disk Hog…", action: showAbout)
        }

        CommandGroup(replacing: .newItem) {
            Button("Choose Folder to Scan") {
                NotificationCenter.default.post(name: .sourceWindowChooseFolderToScan, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(access.blocksScanning)

            Button("Scan Selected Volume") {
                NotificationCenter.default.post(name: .sourceWindowScanSelectedVolume, object: nil)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(access.blocksScanning || appCommandRouter.canScanSelectedVolume == false)
        }

        CommandGroup(after: .help) {
            Button("Full Disk Access…", action: showAccessGuidance)
        }

        CommandGroup(after: .newItem) {
            Button("Open Selected Item") {
                scanWindowCommandState.openSelectedItem()
            }
            .disabled(scanWindowCommandState.canOpenSelectedItem == false)

            Button("Reveal Selected Item in Finder") {
                scanWindowCommandState.revealSelectedItemInFinder()
            }
            .disabled(scanWindowCommandState.canRevealSelectedItem == false)

            Button(
                appCommandRouter.isSelectionListBatchQueueActive
                    ? appCommandRouter.selectionListBatchQueueTitle
                    : scanWindowCommandState.selectedItemCleanupQueueCommandTitle
            ) {
                if appCommandRouter.isSelectionListBatchQueueActive {
                    appCommandRouter.toggleSelectionListBatchQueue()
                } else {
                    scanWindowCommandState.toggleSelectedItemInCleanupQueue()
                }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(
                appCommandRouter.isSelectionListBatchQueueActive
                    ? appCommandRouter.canToggleSelectionListBatchQueue == false
                    : scanWindowCommandState.canToggleSelectedItemInCleanupQueue == false
            )
        }

        #if FILE_MATCHING_DIAGNOSTICS
        CommandGroup(after: .saveItem) {
            Button("Copy Matching File") {
                scanWindowCommandState.copyMatchingFile()
            }
            .disabled(scanWindowCommandState.canCopyMatchingFile == false)
        }
        #endif

        CommandGroup(before: .sidebar) {
            Button("Zoom In") {
                scanWindowCommandState.zoomIn()
            }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(scanWindowCommandState.canZoomIn == false)

            Button("Zoom Out") {
                scanWindowCommandState.zoomOut()
            }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(scanWindowCommandState.canZoomOut == false)

            Menu("Zoom Out To") {
                Button("No Zoom History") {}
                    .disabled(true)
            }
            .disabled(true)

            Divider()

            Button("Select Parent Folder") {
                scanWindowCommandState.selectParentFolder()
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(scanWindowCommandState.canSelectParentFolder == false)

            Divider()

            Button(scanWindowCommandState.showsFreeSpace ? "Hide Free Space" : "Show Free Space") {
                scanWindowCommandState.toggleFreeSpace()
            }
            .disabled(scanWindowCommandState.canToggleFreeSpace == false)

            Button(scanWindowCommandState.showsOtherSpace ? "Hide Other Space" : "Show Other Space") {
                scanWindowCommandState.toggleOtherSpace()
            }
            .disabled(scanWindowCommandState.canToggleOtherSpace == false)

            Divider()

            Toggle(
                "Show Package Contents",
                isOn: Binding(
                    get: { scanPreferences.showPackageContents },
                    set: { scanPreferences.requestShowPackageContentsChange(to: $0) }
                )
            )

            Button(scanPreferences.usesPhysicalSize ? "Show Logical File Size" : "Show Physical File Size") {
                scanPreferences.setUsesPhysicalSize(!scanPreferences.usesPhysicalSize)
            }
        }

        CommandGroup(before: .windowList) {
            Button(inspectorWindowController.isVisible ? "Hide Inspector" : "Show Inspector") {
                inspectorWindowController.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()
        }
    }
}
