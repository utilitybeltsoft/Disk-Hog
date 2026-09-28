import Combine
import Foundation

@MainActor
final class FullDiskAccessSetupModel: ObservableObject {
    @Published private(set) var isUsingLimitedAccess = false
    @Published private(set) var status: FullDiskAccessStatus = .inconclusive
    @Published private(set) var isChecking = false
    @Published private(set) var hasChecked = false
    @Published private(set) var isPresented = false
    @Published private(set) var settingsOpenFailed = false
    @Published private(set) var hasOpenedSettings = false

    private var limitedAccessAccepted: Bool
    private let recordLimitedAccessChoice: () -> Void
    private let checkAccess: @Sendable () async -> FullDiskAccessStatus
    private let openSettings: () -> Bool
    private let openPrivacySettings: () -> Bool
    private let accessBecameAvailable: () -> Void
    private let enterApplication: () -> Void
    private var enteredApplication = false
    private let terminate: () -> Void
    private var task: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var openingSettings = false

    init(limitedAccessAccepted: Bool = false,
         recordLimitedAccessChoice: @escaping () -> Void = {},
         checkAccess: @escaping @Sendable () async -> FullDiskAccessStatus,
         openSettings: @escaping () -> Bool,
         openPrivacySettings: (() -> Bool)? = nil,
         accessBecameAvailable: @escaping () -> Void = {},
         enterApplication: @escaping () -> Void = {},
         terminate: @escaping () -> Void) {
        self.limitedAccessAccepted = limitedAccessAccepted
        self.recordLimitedAccessChoice = recordLimitedAccessChoice
        self.isUsingLimitedAccess = limitedAccessAccepted
        self.checkAccess = checkAccess
        self.openSettings = openSettings
        self.openPrivacySettings = openPrivacySettings ?? openSettings
        self.accessBecameAvailable = accessBecameAvailable
        self.enterApplication = enterApplication
        self.terminate = terminate
    }

    // Initial checking gates scanning; an inconclusive result never traps the user.
    var blocksScanning: Bool { (started && !hasChecked) || (status == .protectedAccessDenied && !isUsingLimitedAccess) }

    /// Discovery reads volume roots and can trigger macOS privacy prompts.
    /// Keep it behind the access check and any visible setup guidance.
    var allowsSourceDiscovery: Bool { !blocksScanning && !isPresented }

    var allowsFolderChooserWarmup: Bool {
        hasChecked && !isChecking && allowsSourceDiscovery
    }

    func start() {
        guard !started else { return }
        started = true
        if !limitedAccessAccepted { showGuidance() }
        runCheck(openAfter: nil)
    }

    func showGuidance() { isPresented = true }

    func dismissGuidance() {
        guard !blocksScanning else { return }
        isPresented = false
        enterApplicationIfNeeded()
    }

    func continueWithLimitedAccess() {
        guard hasChecked, !isChecking else { return }
        if !limitedAccessAccepted {
            limitedAccessAccepted = true
            recordLimitedAccessChoice()
        }
        isUsingLimitedAccess = status != .available
        isPresented = false
        enterApplicationIfNeeded()
    }

    private func enterApplicationIfNeeded() {
        guard hasChecked, !blocksScanning, !isPresented, !enteredApplication else { return }
        enteredApplication = true
        enterApplication()
    }

    func recheck() {
        guard !isChecking else { return }
        runCheck(openAfter: nil)
    }

    func applicationDidBecomeActive() {
        guard started, hasChecked, !openingSettings else { return }
        recheck()
    }

    func requestSettings() { requestSettings(using: openSettings) }

    func requestPrivacySettings() { requestSettings(using: openPrivacySettings) }

    private func requestSettings(using open: @escaping () -> Bool) {
        guard !openingSettings else { return }
        showGuidance()
        settingsOpenFailed = false
        openingSettings = true
        // Supersede an older check; its result must not override this request.
        runCheck(openAfter: open)
    }

    func quit() { terminate() }

    private func runCheck(openAfter: (() -> Bool)?) {
        generation += 1
        let current = generation
        task?.cancel()
        isChecking = true
        let checkAccess = checkAccess
        task = Task { [weak self] in
            let result = await checkAccess()
            guard let self, current == self.generation, !Task.isCancelled else { return }
            let previous = self.status
            self.status = result
            self.hasChecked = true
            self.isChecking = false
            self.isUsingLimitedAccess = result != .available && self.limitedAccessAccepted
            if let openAfter {
                let opened = openAfter()
                self.hasOpenedSettings = self.hasOpenedSettings || opened
                self.settingsOpenFailed = !opened
                self.openingSettings = false
            } else if result == .protectedAccessDenied && !self.isUsingLimitedAccess {
                self.showGuidance()
            } else if result == .available {
                self.isUsingLimitedAccess = false
                self.isPresented = false
            }
            if result == .available && previous != .available {
                self.accessBecameAvailable()
            }
            self.enterApplicationIfNeeded()
            self.task = nil
        }
    }
}
