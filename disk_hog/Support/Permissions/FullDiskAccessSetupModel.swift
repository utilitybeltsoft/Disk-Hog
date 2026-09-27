import Combine
import Foundation

@MainActor
final class FullDiskAccessSetupModel: ObservableObject {
    @Published private(set) var status: FullDiskAccessStatus = .inconclusive
    @Published private(set) var isChecking = false
    @Published private(set) var hasChecked = false
    @Published private(set) var isPresented = false
    @Published private(set) var settingsOpenFailed = false
    @Published private(set) var hasOpenedSettings = false

    private let checkAccess: @Sendable () async -> FullDiskAccessStatus
    private let openSettings: () -> Bool
    private let accessBecameAvailable: () -> Void
    private let terminate: () -> Void
    private var task: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var openingSettings = false

    init(checkAccess: @escaping @Sendable () async -> FullDiskAccessStatus,
         openSettings: @escaping () -> Bool,
         accessBecameAvailable: @escaping () -> Void = {},
         terminate: @escaping () -> Void) {
        self.checkAccess = checkAccess
        self.openSettings = openSettings
        self.accessBecameAvailable = accessBecameAvailable
        self.terminate = terminate
    }

    // Initial checking gates scanning; an inconclusive result never traps the user.
    var blocksScanning: Bool { (started && !hasChecked) || status == .protectedAccessDenied }

    func start() {
        guard !started else { return }
        started = true
        runCheck(openAfter: false)
    }

    func showGuidance() { isPresented = true }

    func dismissGuidance() {
        guard !blocksScanning else { return }
        isPresented = false
    }

    func recheck() {
        guard !isChecking else { return }
        runCheck(openAfter: false)
    }

    func applicationDidBecomeActive() {
        guard started, hasChecked, !openingSettings else { return }
        recheck()
    }

    func requestSettings() {
        guard !openingSettings else { return }
        isPresented = true
        settingsOpenFailed = false
        openingSettings = true
        // Supersede an older check; its result must not override this request.
        runCheck(openAfter: true)
    }

    func quit() { terminate() }

    private func runCheck(openAfter: Bool) {
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
            if openAfter {
                let opened = self.openSettings()
                self.hasOpenedSettings = self.hasOpenedSettings || opened
                self.settingsOpenFailed = !opened
                self.openingSettings = false
            } else if result == .protectedAccessDenied {
                self.isPresented = true
            } else if result == .available {
                self.isPresented = false
            }
            if result == .available && previous != .available {
                self.accessBecameAvailable()
            }
            self.task = nil
        }
    }
}
