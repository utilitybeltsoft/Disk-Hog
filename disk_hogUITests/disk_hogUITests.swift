import AppKit
import XCTest

final class DiskHogUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInspectorOpensFromMenuCommand() throws {
        let appURL = URL(fileURLWithPath: "/Applications/Disk Hog.app")
        let installedBundle = try XCTUnwrap(
            Bundle(url: appURL),
            "Install Disk Hog in /Applications before running UI tests."
        )
        XCTAssertEqual(installedBundle.bundleIdentifier, "software.utilitybelt.diskhog")
        guard installedBundle.bundleIdentifier == "software.utilitybelt.diskhog" else {
            return
        }
        // Do not terminate a user's running scan to establish the test fixture.
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "software.utilitybelt.diskhog"
        ).isEmpty else {
            XCTFail("Quit installed Disk Hog before running UI tests; it may have active scans.")
            return
        }
        // Target the actual installed app, preserving its signature and permissions.
        // Unit tests still use the isolated host to exercise compiled internals.
        let app = XCUIApplication(url: appURL)
        defer { app.terminate() }
        app.launch()

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
