import AppKit
import Testing
@testable import disk_hog

struct FullDiskAccessServiceTests {
    private let paths = [URL(fileURLWithPath: "/fixture/Mail"), URL(fileURLWithPath: "/fixture/Messages")]

    @Test func accessibleDirectoriesProvideEvidence() {
        #expect(FullDiskAccessService(directories: paths, listDirectory: { _ in }).check() == .available)
        #expect(FullDiskAccessService(directories: [paths[0]], listDirectory: { _ in }).check() == .inconclusive)
    }

    @Test(arguments: [ENOENT, ENOTDIR, EACCES, EIO])
    func ordinaryErrorsAreInconclusive(code: Int32) {
        let service = FullDiskAccessService(directories: paths) { _ in
            throw POSIXError(POSIXErrorCode(rawValue: code)!)
        }
        #expect(service.check() == .inconclusive)
    }

    @Test func protectedDenialWinsOverSuccessfulAccess() {
        let service = FullDiskAccessService(directories: paths) { url in
            if url.lastPathComponent == "Mail" { throw POSIXError(.EPERM) }
        }
        #expect(service.check() == .protectedAccessDenied)
    }

    @Test func underlyingPOSIXPermissionsAreNotMisreportedAsFullDiskAccess() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                            userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES)])
        #expect(FileAccessFailure.classify(error) == .filesystemPermission)
        let reason = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/"), isLocalVolume: true,
            protectedURLs: [paths[0]], fileExists: { _ in true },
            directoryContents: { url in
                if url.path != "/" { throw error }
                return []
            }
        )
        #expect(reason == String(localized: "Folder access denied"))
    }

    @Test func missingDirectoriesDoNotPreventOtherEvidence() {
        let service = FullDiskAccessService(directories: paths + [URL(fileURLWithPath: "/fixture/missing")]) {
            if $0.lastPathComponent == "missing" { throw POSIXError(.ENOENT) }
        }
        #expect(service.check() == .available)
    }
}

private actor AccessCheckGate {
    private var continuations: [Int: CheckedContinuation<FullDiskAccessStatus, Never>] = [:]
    private(set) var calls = 0

    func check() async -> FullDiskAccessStatus {
        calls += 1
        let call = calls
        return await withCheckedContinuation { continuations[call] = $0 }
    }

    func finish(_ call: Int, with result: FullDiskAccessStatus) {
        continuations.removeValue(forKey: call)?.resume(returning: result)
    }
}

@MainActor
struct FullDiskAccessSetupTests {
    @Test func launchDiscoveryWaitsForAccessAndStaysBlockedAfterDenial() async throws {
        let gate = AccessCheckGate()
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
                                            openSettings: { true }, terminate: {})
        model.start()
        let sources = SourceWindowViewModel(sources: [], filter: SourceVolumeFilter(),
            sourceLoader: { Issue.record("Volume discovery ran during access setup"); return [] },
            canRefresh: { model.allowsSourceDiscovery })
        await sources.refresh().value
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .protectedAccessDenied)
        try await waitUntil { model.hasChecked }
        await sources.refresh().value
        #expect(!model.allowsSourceDiscovery)
        #expect(!sources.isLoading)
    }

    @Test func inconclusiveGuidanceDefersDiscoveryUntilDismissed() async throws {
        let model = FullDiskAccessSetupModel(checkAccess: { .inconclusive },
                                            openSettings: { false }, terminate: {})
        model.start()
        try await waitUntil { model.hasChecked }
        model.showGuidance()
        let counter = SourceDiscoveryCounter()
        let sources = SourceWindowViewModel(sources: [], filter: SourceVolumeFilter(),
            sourceLoader: { await counter.load() }, canRefresh: { model.allowsSourceDiscovery })
        await sources.refresh().value
        #expect(await counter.calls == 0)
        model.dismissGuidance()
        await sources.refresh().value
        #expect(await counter.calls == 1)
    }

    @Test func scheduledDiscoveryRechecksGateBeforeTouchingVolumes() async {
        var allowed = true
        let sources = SourceWindowViewModel(sources: [], filter: SourceVolumeFilter(),
            sourceLoader: { Issue.record("Queued discovery ignored newly opened guidance"); return [] },
            canRefresh: { allowed })
        let pending = sources.refresh()
        allowed = false
        await pending.value
    }

    @Test func deniedLaunchGatesScanningButQuitRemainsAvailable() async throws {
        var quit = false
        let model = FullDiskAccessSetupModel(checkAccess: { .protectedAccessDenied },
                                            openSettings: { Issue.record("Unexpected Settings launch"); return false },
                                            terminate: { quit = true })
        model.start()
        #expect(model.blocksScanning)
        try await waitUntil { model.hasChecked }
        #expect(model.isPresented)
        model.dismissGuidance()
        #expect(model.isPresented)
        model.quit()
        #expect(quit)
    }

    @Test func inconclusiveLaunchDoesNotTrapTheUser() async throws {
        let model = FullDiskAccessSetupModel(checkAccess: { .inconclusive }, openSettings: { false }, terminate: {})
        model.start()
        try await waitUntil { model.hasChecked }
        #expect(!model.blocksScanning)
        #expect(!model.isPresented)
        model.showGuidance()
        model.dismissGuidance()
        #expect(!model.isPresented)
    }

    @Test func settingsWaitsForPrimingAndDoesNotTreatOpeningAsApproval() async throws {
        let gate = AccessCheckGate()
        var opened = 0
        var refreshed = 0
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
                                            openSettings: { opened += 1; return true },
                                            accessBecameAvailable: { refreshed += 1 }, terminate: {})
        model.start()
        try await waitUntilAsync { await gate.calls == 1 }
        model.requestSettings() // Supersedes the startup check.
        model.requestSettings() // Does not duplicate the request.
        try await waitUntilAsync { await gate.calls == 2 }
        #expect(opened == 0)
        await gate.finish(2, with: .protectedAccessDenied)
        try await waitUntil { !model.isChecking }
        #expect(opened == 1)
        #expect(model.hasOpenedSettings)
        #expect(model.blocksScanning)
        // A late, stale successful result cannot clear the setup gate.
        await gate.finish(1, with: .available)
        model.applicationDidBecomeActive()
        try await waitUntilAsync { await gate.calls == 3 }
        await gate.finish(3, with: .available)
        try await waitUntil { !model.isChecking }
        #expect(!model.blocksScanning)
        #expect(!model.isPresented)
        #expect(refreshed == 1)
        #expect(opened == 1)
        model.applicationDidBecomeActive()
        try await waitUntilAsync { await gate.calls == 4 }
        await gate.finish(4, with: .available)
        try await waitUntil { !model.isChecking }
        #expect(refreshed == 1)
    }

    @Test func returningToAppDetectsRevocationEvenWithoutUsingTheSettingsButton() async throws {
        let gate = AccessCheckGate()
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() }, openSettings: { false }, terminate: {})
        model.start()
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .available)
        try await waitUntil { !model.isChecking }
        #expect(!model.blocksScanning)
        model.applicationDidBecomeActive()
        try await waitUntilAsync { await gate.calls == 2 }
        await gate.finish(2, with: .protectedAccessDenied)
        try await waitUntil { !model.isChecking }
        #expect(model.blocksScanning)
        #expect(model.isPresented)
    }

    @Test func failedSettingsLaunchKeepsManualInstructionsAvailable() async throws {
        let model = FullDiskAccessSetupModel(checkAccess: { .protectedAccessDenied },
                                            openSettings: { false }, terminate: {})
        model.requestSettings()
        try await waitUntil { !model.isChecking }
        #expect(model.settingsOpenFailed)
        #expect(!model.hasOpenedSettings)
        #expect(model.isPresented)
        #expect(model.blocksScanning)
    }

    @Test func repeatedLaunchAndRecheckDoNotDuplicateAnActiveCheck() async throws {
        let gate = AccessCheckGate()
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() }, openSettings: { false }, terminate: {})
        model.start()
        model.start()
        model.recheck()
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .available)
        try await waitUntil { !model.isChecking }
        #expect(await gate.calls == 1)
        #expect(!model.isPresented)
    }

    @Test func guidancePanelAllowsSystemTerminationAndStaysVisibleWhenInactive() throws {
        let model = FullDiskAccessSetupModel(checkAccess: { .inconclusive }, openSettings: { false }, terminate: {})
        let controller = FullDiskAccessSetupController(model: model)
        let panel = try #require(controller.window as? NSPanel)
        #expect(!panel.preventsApplicationTerminationWhenModal)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isVisible)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(predicate(), "Permission setup did not reach the expected state")
    }

    private func waitUntilAsync(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await predicate(), "Permission check did not start")
    }
}

private actor SourceDiscoveryCounter {
    private(set) var calls = 0
    func load() -> [ScanSource] {
        calls += 1
        return []
    }
}
