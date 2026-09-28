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
    @Test func settingsButtonWaitsForTheAccessCheck() async throws {
        let gate = AccessCheckGate()
        var openedSettings = 0
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
            openSettings: { openedSettings += 1; return true }, terminate: {})
        model.requestSettings()
        model.requestSettings()
        #expect(openedSettings == 0)
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .protectedAccessDenied)
        try await waitUntil { !model.isChecking }
        #expect(openedSettings == 1)
        #expect(model.hasOpenedSettings)
        #expect(model.isPresented)
        #expect(model.blocksScanning)
    }

    @Test func onlyExplicitLimitedAccessChoiceSuppressesFutureLaunchPrompts() async throws {
        var accepted = false
        var records = 0
        func makeModel() -> FullDiskAccessSetupModel {
            FullDiskAccessSetupModel(limitedAccessAccepted: accepted,
                recordLimitedAccessChoice: { accepted = true; records += 1 },
                checkAccess: { .protectedAccessDenied }, openSettings: { true }, terminate: {})
        }
        let first = makeModel()
        first.start()
        first.continueWithLimitedAccess() // Cannot accept before the check finishes.
        try await waitUntil { first.hasChecked }
        first.requestSettings()
        try await waitUntil { !first.isChecking }
        first.quit()
        #expect(!accepted)
        #expect(records == 0)

        let second = makeModel()
        second.start()
        try await waitUntil { second.hasChecked }
        #expect(second.isPresented)
        #expect(second.blocksScanning)
        second.continueWithLimitedAccess()
        #expect(accepted)
        #expect(records == 1)
        #expect(!second.blocksScanning)

        let third = makeModel()
        third.start()
        #expect(!third.isPresented)
        #expect(third.blocksScanning) // The access check still runs.
        try await waitUntil { third.hasChecked }
        #expect(!third.isPresented)
        #expect(third.isUsingLimitedAccess)
        #expect(third.allowsSourceDiscovery)
        third.showGuidance()
        #expect(third.isPresented)
        third.continueWithLimitedAccess()
        #expect(records == 1)
    }

    @Test func launchEntersApplicationOnlyAfterExplicitLimitedAccessChoice() async throws {
        var entries = 0
        let model = FullDiskAccessSetupModel(checkAccess: { .protectedAccessDenied },
            openSettings: { true }, enterApplication: { entries += 1 }, terminate: {})
        model.start()
        #expect(!model.isPresented)
        model.continueWithLimitedAccess()
        #expect(entries == 0)
        try await waitUntil { model.hasChecked }
        #expect(entries == 0)
        #expect(model.blocksScanning)
        model.continueWithLimitedAccess()
        #expect(entries == 1)
        #expect(model.isUsingLimitedAccess)
        #expect(!model.isPresented)
        #expect(model.allowsSourceDiscovery)
        #expect(model.allowsFolderChooserWarmup)
        model.applicationDidBecomeActive()
        try await waitUntil { !model.isChecking }
        #expect(!model.isPresented)
        #expect(!model.blocksScanning)
        model.showGuidance()
        #expect(!model.allowsSourceDiscovery)
        model.continueWithLimitedAccess()
        #expect(entries == 1)
    }

    @Test func confirmedAccessEntersApplicationAutomaticallyOnce() async throws {
        var entries = 0
        let model = FullDiskAccessSetupModel(checkAccess: { .available },
            openSettings: { false }, enterApplication: { entries += 1 }, terminate: {})
        model.start()
        try await waitUntil { model.hasChecked }
        #expect(entries == 1)
        #expect(!model.isPresented)
        #expect(!model.isUsingLimitedAccess)
        model.recheck()
        try await waitUntil { !model.isChecking }
        #expect(entries == 1)
    }

    @Test func permissionExampleImageIsBundled() {
        #expect(NSImage(named: "FullDiskAccessExample") != nil)
    }

    @Test func folderChooserWarmupWaitsForChecksAndGuidance() async throws {
        let gate = AccessCheckGate()
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
                                            openSettings: { true }, terminate: {})
        #expect(!model.allowsFolderChooserWarmup)
        model.start()
        #expect(!model.allowsFolderChooserWarmup)
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .available)
        try await waitUntil { model.hasChecked }
        #expect(model.allowsFolderChooserWarmup)
        model.showGuidance()
        #expect(!model.allowsFolderChooserWarmup)
        model.dismissGuidance()
        #expect(model.allowsFolderChooserWarmup)
        model.recheck()
        #expect(!model.allowsFolderChooserWarmup)
        try await waitUntilAsync { await gate.calls == 2 }
        await gate.finish(2, with: .protectedAccessDenied)
        try await waitUntil { !model.isChecking }
        #expect(!model.allowsFolderChooserWarmup)
        #expect(!model.isUsingLimitedAccess)
    }


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
        #expect(!model.allowsFolderChooserWarmup)
        model.dismissGuidance()
        #expect(model.allowsFolderChooserWarmup)
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
        #expect(model.isPresented)
        model.showGuidance()
        model.dismissGuidance()
        #expect(!model.isPresented)
    }

    @Test func guidanceWaitsForCheckingAndNeverChecksWhileVisible() async throws {
        let gate = AccessCheckGate()
        var opened = 0
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
            openSettings: { opened += 1; return true }, terminate: {})
        model.start()
        try await waitUntilAsync { await gate.calls == 1 }
        #expect(!model.isPresented)
        model.showGuidance() // Help must also wait for an in-flight check.
        model.requestSettings()
        model.requestSettings()
        #expect(!model.isPresented)
        #expect(opened == 0)
        #expect(await gate.calls == 1)
        await gate.finish(1, with: .protectedAccessDenied)
        try await waitUntil { !model.isChecking }
        #expect(model.isPresented)
        #expect(opened == 1)
        #expect(model.blocksScanning)
        model.applicationDidBecomeActive()
        model.recheck()
        model.requestSettings()
        model.requestSettings()
        #expect(!model.isChecking)
        #expect(opened == 3)
        #expect(await gate.calls == 1)
        #expect(model.blocksScanning)
    }

    @Test func manualGuidanceWaitsForBackgroundCheckEvenWhenAccessIsAvailable() async throws {
        let gate = AccessCheckGate()
        let model = FullDiskAccessSetupModel(checkAccess: { await gate.check() },
            openSettings: { true }, terminate: {})
        model.start()
        try await waitUntilAsync { await gate.calls == 1 }
        await gate.finish(1, with: .available)
        try await waitUntil { model.hasChecked }
        model.recheck()
        model.showGuidance()
        #expect(!model.isPresented)
        try await waitUntilAsync { await gate.calls == 2 }
        await gate.finish(2, with: .available)
        try await waitUntil { !model.isChecking }
        #expect(model.isPresented)
    }

    @Test func returningToAppPromptsOnRevocationWithoutAnExplicitLimitedAccessChoice() async throws {
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
        #expect(!model.isUsingLimitedAccess)
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
