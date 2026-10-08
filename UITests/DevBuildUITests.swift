import XCTest

#if CAVE_CALS_DEV
let testAppURLScheme = "cavecals-dev"
#else
let testAppURLScheme = "cavecals"
#endif

final class DevBuildUITests: XCTestCase {
    func testPersistentDiaryResetReturnsToFreshSetup() throws {
        #if !CAVE_CALS_DEV
        throw XCTSkip("This test intentionally resets only the separate Dev app.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        // No --uitesting: exercise the real on-disk database and real cold-launch reset.
        app.launch()
        if app.staticTexts["Close and reopen Cave Cals Dev"].exists { app.terminate(); app.launch() }
        if app.buttons["skipGoal"].waitForExistence(timeout: 5) { completeSetup(app) }
        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 15))
        reset(app, cancelFirst: true)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["skipGoal"].waitForExistence(timeout: 15))
        completeSetup(app)
        let search = app.textFields["foodSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("123")
        let addCalories = app.buttons["Add 123 calories"].firstMatch
        XCTAssertTrue(addCalories.waitForExistence(timeout: 5)); addCalories.tap()
        if app.buttons["cancelAddMode"].waitForExistence(timeout: 5) { app.buttons["cancelAddMode"].tap() }
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["calorieSummary"].label.contains("123"))
        reset(app, cancelFirst: false)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["skipGoal"].waitForExistence(timeout: 15))
        completeSetup(app)
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["calorieSummary"].label.contains("123"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Cave Cals Dev after reset"; screenshot.lifetime = .keepAlways
        add(screenshot)
        #endif
    }

    private func completeSetup(_ app: XCUIApplication) {
        let start = app.buttons["skipGoal"]
        // The real welcome animates its footer; AX can keep reporting it as unhittable
        // after the slide finishes. Wait for its observed frame to settle, then tap its center.
        var previousFrame = CGRect.zero
        let settled = NSPredicate { _, _ in
            guard start.exists else { return false }
            let frame = start.frame
            defer { previousFrame = frame }
            return frame == previousFrame && (start.isHittable || app.windows.firstMatch.frame.contains(frame))
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 20), .completed, "Welcome button: \(start.frame); window: \(app.windows.firstMatch.frame)")
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts.buttons["Yes, skip plan"].waitForExistence(timeout: 5))
        app.alerts.buttons["Yes, skip plan"].tap()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        if app.buttons["discovery-other"].waitForExistence(timeout: 5) {
            app.buttons["discovery-other"].tap(); app.buttons["discoveryContinue"].tap()
        }
        XCTAssertTrue(app.buttons["skipOnboardingPaywall"].waitForExistence(timeout: 10))
        app.buttons["skipOnboardingPaywall"].tap()
    }

    private func reset(_ app: XCUIApplication, cancelFirst: Bool) {
        app.buttons["appSettings"].tap()
        let reset = app.buttons["resetTestData"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5)); reset.tap()
        if cancelFirst {
            app.alerts.buttons["Cancel"].tap()
            XCTAssertTrue(reset.exists); reset.tap()
        }
        app.alerts.buttons["Reset Test Data"].tap()
        XCTAssertTrue(app.staticTexts["Close and reopen Cave Cals Dev"].waitForExistence(timeout: 5))
    }
}
