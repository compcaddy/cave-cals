import XCTest

final class WeightTrackingUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["Me Start Now"].waitForExistence(timeout: 10))
        app.buttons["Me Start Now"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    private func openProfile() {
        let profile = app.buttons["Settings"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: profile)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        profile.tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 5))
    }
    private func toggleTracking() {
        let toggle = app.switches["trackWeight"].firstMatch
        let control = toggle.switches.firstMatch
        if control.exists { control.tap() } else { toggle.tap() }
    }
    private func enableWeight() {
        openProfile()
        toggleTracking()
        XCTAssertTrue(app.buttons["todayWeight"].waitForExistence(timeout: 5))
    }
    func testOptionalReminderDismissalAndTrackingOff() {
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
        enableWeight()
        app.navigationBars["You"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["weighInReminder"].waitForExistence(timeout: 5))
        app.buttons["dismissWeighIn"].tap()
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
        openProfile()
        app.swipeUp()
        let toggle = app.switches["trackWeight"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3)); toggleTracking()
        XCTAssertFalse(app.buttons["todayWeight"].exists)
        app.navigationBars["You"].buttons["Done"].tap()
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
    }
    func testWeighInEditChartAndDelete() {
        enableWeight()
        app.navigationBars["You"].buttons["Done"].tap()
        app.buttons["weighInReminder"].tap()
        let amount = app.textFields["weightAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveWeight"].isEnabled)
        amount.tap(); amount.typeText("180.5")
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
        openProfile()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 5))
        for range in ["Week", "Year", "Month"] { app.segmentedControls["weightChartRange"].buttons[range].tap() }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Personal area with weight graph"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["todayWeight"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        let old = amount.value as? String ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "179.8")
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.buttons["todayWeight"].waitForExistence(timeout: 5))
        app.buttons["todayWeight"].tap()
        app.buttons["deleteWeight"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete weigh-in", "deleteWeight")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap()
        XCTAssertTrue(app.buttons["todayWeight"].waitForExistence(timeout: 5))
        app.navigationBars["You"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["weighInReminder"].waitForExistence(timeout: 5))
    }
    func testSavingFromProfileRefreshesGraphAndPeriodBrowsing() {
        enableWeight()
        app.buttons["todayWeight"].tap()
        let amount = app.textFields["weightAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(); amount.typeText("180.5")
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 5))
        app.buttons["Previous weight period"].tap()
        XCTAssertTrue(app.staticTexts["No weigh-ins in this period"].waitForExistence(timeout: 3))
        app.buttons["Next weight period"].tap()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 3))
    }
}
