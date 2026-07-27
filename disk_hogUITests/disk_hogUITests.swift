//
//  disk_hogUITests.swift
//  disk_hogUITests
//
//

import XCTest

final class disk_hogUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testInspectorOpensAtPreferredInformationSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DISK_HOG_RESET_INSPECTOR_FRAME"] = "1"
        app.launch()
        app.typeKey("i", modifierFlags: .command)

        let inspectorWindow = app.windows["Inspector"]
        XCTAssertTrue(inspectorWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(inspectorWindow.frame.width, 720, accuracy: 2)
        XCTAssertEqual(inspectorWindow.frame.height, 708, accuracy: 2)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
