import AppKit
import XCTest

final class DiskHogUITests: XCTestCase {

    @MainActor
    private func launchInstalledApp() throws -> XCUIApplication {
        let url = URL(fileURLWithPath: "/Applications/Disk Hog.app")
        let bundle = try XCTUnwrap(Bundle(url: url), "Install Disk Hog in /Applications before running UI tests.")
        guard bundle.bundleIdentifier == "software.utilitybelt.diskhog" else {
            throw NSError(domain: "DiskHogUITests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The installed app does not have Disk Hog's production identity."])
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "software.utilitybelt.diskhog").isEmpty else {
            throw NSError(domain: "DiskHogUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Quit Disk Hog before testing; active scans will not be interrupted."])
        }
        let app = XCUIApplication(url: url)
        addTeardownBlock { @MainActor in app.terminate() }
        app.launch()
        return app
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, matching predicate: NSPredicate,
                         stage: String, app: XCUIApplication, timeout: TimeInterval = 10) throws {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Folder chooser failure: \(stage)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            throw NSError(domain: "DiskHogUITests.FolderChooser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out while \(stage). No further chooser actions were attempted."])
        }
    }

    @MainActor
    private func scan(_ folder: URL, using app: XCUIApplication) throws -> XCUIElement {
        let ready = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        let chooseFolder = app.buttons["Choose Folder to Scan"].firstMatch
        try waitFor(chooseFolder, matching: ready, stage: "waiting for Choose Folder", app: app)
        chooseFolder.click()
        let panel = app.windows["open-panel"]
        try waitFor(panel, matching: NSPredicate(format: "exists == true"),
                    stage: "opening the folder chooser", app: app)
        // Address the chooser, not whichever application window currently has focus.
        panel.typeKey("/", modifierFlags: [])
        // The native panel's path sheet is hosted by a separate accessibility
        // process. Its focused field can report non-hittable through the parent
        // window query, so resolve the unique field directly and verify input.
        let location = app.textFields["PathTextField"]
        try waitFor(location, matching: NSPredicate(format: "exists == true AND enabled == true"),
                    stage: "finding the Go to Folder path field", app: app)
        location.click()
        location.typeKey("a", modifierFlags: .command)
        location.typeText(folder.path)
        try waitFor(location, matching: NSPredicate(format: "value == %@ OR value == %@", folder.path, folder.path + "/"),
                    stage: "verifying the complete fixture path", app: app)
        location.typeKey(.return, modifierFlags: [])
        try waitFor(location, matching: NSPredicate(format: "exists == false"),
                    stage: "closing Go to Folder after navigation", app: app)
        // Existence of Scan alone is insufficient: it also exists behind the path sheet.
        // Confirm the destination before allowing the test to initiate any scan.
        let destination = panel.popUpButtons["where popup"]
        try waitFor(destination, matching: NSPredicate(format: "value == %@", folder.lastPathComponent),
                    stage: "confirming the selected fixture folder", app: app)
        let scanButton = panel.buttons["OKButton"]
        try waitFor(scanButton, matching: ready, stage: "waiting for Scan to become actionable", app: app)
        scanButton.click()
        try waitFor(panel, matching: NSPredicate(format: "exists == false"),
                    stage: "dismissing the folder chooser", app: app)
        let window = app.windows.containing(.button, identifier: "Re-scan").firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let finished = window.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "Scan finished:", "Scan finished:")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(window.title.contains(folder.lastPathComponent))
        return window
    }

    @MainActor
    func testScanRankNavigateQueueAndRescanWithoutDeletingUserFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Disk Hog UI fixture \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let big = root.appendingPathComponent("largest-fixture.bin")
        try Data(repeating: 1, count: 65536).write(to: big)
        try Data(repeating: 2, count: 4096).write(to: root.appendingPathComponent("small-fixture.txt"))
        let nested = root.appendingPathComponent("nested-fixture")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 8192).write(to: nested.appendingPathComponent("nested-file.txt"))
        let app = try launchInstalledApp()
        defer { app.terminate() }
        let window = try scan(root, using: app)

        let rankedFile = window.staticTexts["largest-fixture.bin"].firstMatch
        XCTAssertTrue(rankedFile.waitForExistence(timeout: 10))
        rankedFile.rightClick()
        let reveal = app.menuItems["Show in Folder Tree"].firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.click()
        let folderTree = window.radioButtons["Folder Tree"]
        XCTAssertTrue(folderTree.value as? String == "1" || folderTree.value as? Int == 1,
                      "Show in Folder Tree must actually switch the inspection pane.")
        let treeFile = window.staticTexts["largest-fixture.bin"].firstMatch
        XCTAssertTrue(treeFile.waitForExistence(timeout: 5))
        treeFile.rightClick()
        let add = app.menuItems["Add to Cleanup Queue"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()

        app.typeKey("i", modifierFlags: .command)
        let inspector = app.windows.containing(.button, identifier: "Cleanup Queue").firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        inspector.buttons["Cleanup Queue"].click()
        XCTAssertTrue(inspector.staticTexts["largest-fixture.bin"].waitForExistence(timeout: 5))
        XCTAssertTrue(inspector.buttons["Move Selected to Finder Trash"].isEnabled)
        // Queue removal must not mutate the filesystem.
        inspector.buttons["Remove Selected from Queue"].click()
        XCTAssertTrue(inspector.staticTexts["Cleanup Queue Is Empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: big).count, 65536)

        window.click()
        let added = root.appendingPathComponent("added-after-scan.bin")
        try Data(repeating: 4, count: 32768).write(to: added)
        window.buttons["Re-scan"].click()
        XCTAssertTrue(window.staticTexts["added-after-scan.bin"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(FileManager.default.fileExists(atPath: big.path))
    }

    @MainActor
    func testScanIssuesShowUnreadableFolderThenClearAfterRescan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("disk-hog-issues-ui-\(UUID().uuidString)")
        let locked = root.appendingPathComponent("locked-fixture")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 4096).write(to: root.appendingPathComponent("readable.txt"))
        try Data(repeating: 2, count: 8192).write(to: locked.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let app = try launchInstalledApp()
        defer { app.terminate() }
        let window = try scan(root, using: app)
        app.typeKey("i", modifierFlags: .command)
        let inspector = app.windows.containing(.button, identifier: "Scan Issues").firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        inspector.buttons["Scan Issues"].click()
        let issue = inspector.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "locked-fixture", "locked-fixture")).firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        XCTAssertFalse(inspector.staticTexts["No Scan Issues"].exists)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        window.click()
        window.buttons["Re-scan"].click()
        XCTAssertTrue(inspector.staticTexts["No Scan Issues"].waitForExistence(timeout: 20))
        XCTAssertFalse(issue.exists)
        XCTAssertEqual(try Data(contentsOf: locked.appendingPathComponent("hidden.txt")).count, 8192)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInspectorOpensFromMenuCommand() throws {
        let app = try launchInstalledApp()
        defer { app.terminate() }

        app.typeKey("i", modifierFlags: .command)

        let inspectorWindow: XCUIElement = app.windows["Inspector"]
        XCTAssertTrue(
            inspectorWindow.waitForExistence(timeout: 5),
            "The Inspector window should open from Command-I."
        )

        XCTAssertTrue(inspectorWindow.buttons["Information"].exists)
        XCTAssertTrue(inspectorWindow.buttons["Disk Usage"].exists)
        XCTAssertTrue(inspectorWindow.buttons["Selection List"].exists)
        XCTAssertTrue(inspectorWindow.staticTexts["No Scan Window Active"].exists)
        XCTAssertGreaterThanOrEqual(inspectorWindow.frame.width, 480)
        XCTAssertGreaterThanOrEqual(inspectorWindow.frame.height, 360)
    }
}
