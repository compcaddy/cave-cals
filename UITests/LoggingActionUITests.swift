import XCTest

final class LoggingActionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["skipGoal"].waitForExistence(timeout: 10))
    }

    private func completeSetup() {
        app.buttons["skipGoal"].tap()
    }

    func testPendingLinkSurvivesSetup() {
        XCUIDevice.shared.system.open(URL(string: "cavecals://log/voice")!)
        XCTAssertTrue(app.buttons["skipGoal"].waitForExistence(timeout: 5))
        completeSetup()
        XCTAssertTrue(app.navigationBars["Voice logging"].waitForExistence(timeout: 5))
        if !app.buttons["aiRecord"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["aiRecord"].waitForExistence(timeout: 5))
    }

    func testAllLinksReplaceCurrentDrawerAndRepeat() {
        completeSetup()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        for (action, title) in [("voice", "Voice logging"), ("image", "Meal Scan"), ("barcode", "Scan a Barcode"), ("voice", "Voice logging")] {
            XCUIDevice.shared.system.open(URL(string: "cavecals://log/\(action)")!)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), action)
        }
        XCUIDevice.shared.system.open(URL(string: "cavecals://log/add")!)
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }

    func testColdLaunchLinkSurvivesSetup() {
        app.terminate()
        app.open(URL(string: "cavecals://log/image")!)
        XCTAssertTrue(app.buttons["skipGoal"].waitForExistence(timeout: 10))
        completeSetup()
        XCTAssertTrue(app.navigationBars["Meal Scan"].waitForExistence(timeout: 5))
    }

    private func chooseQuickAction(_ title: String) {
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = home.icons["Cave Cals"].firstMatch
        for _ in 0..<6 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: icon)
            if XCTWaiter.wait(for: [ready], timeout: 3) == .completed { break }
            home.swipeLeft()
        }
        XCTAssertTrue(icon.isHittable)
        icon.press(forDuration: 1)
        let action = home.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
    }

    func testWarmQuickActionsOpenRequestedFeatures() {
        completeSetup()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        for (action, title) in [("Voice Log", "Voice logging"), ("Meal Scan", "Meal Scan"), ("Barcode Scan", "Scan a Barcode")] {
            chooseQuickAction(action)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        }
        chooseQuickAction("Search/Add")
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }

    func testColdQuickActionOpensVoice() {
        app.terminate()
        chooseQuickAction("Voice Log")
        // SpringBoard launches without --uitesting, so it may use an existing profile.
        if app.buttons["skipGoal"].waitForExistence(timeout: 3) { completeSetup() }
        XCTAssertTrue(app.navigationBars["Voice logging"].waitForExistence(timeout: 5))
    }
}
