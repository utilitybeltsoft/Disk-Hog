import XCTest

final class DiskHogUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInspectorOpensFromMenuCommand() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DISK_HOG_RESET_INSPECTOR_FRAME"] = "1"
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
