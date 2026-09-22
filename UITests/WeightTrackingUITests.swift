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
    func testWeekPickerLoadsDaysWithoutMovingWeightsAndProtectsEdits() {
        enableWeight()
        app.buttons["todayWeight"].tap()
        let amount = app.textFields["weightAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(); amount.typeText("180.5")
        app.buttons["saveWeight"].tap()
        app.buttons["todayWeight"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let today = Calendar.current.startOfDay(for: Date())
        func dayButton(_ date: Date) -> XCUIElement {
            let c = Calendar.current.dateComponents([.era, .year, .month, .day], from: date)
            return app.buttons[String(format: "weightDay-%02d-%04d-%02d-%02d", c.era!, c.year!, c.month!, c.day!)]
        }
        XCTAssertFalse(app.buttons["nextWeightWeek"].isEnabled)
        for offset in 1...6 {
            let future = Calendar.current.date(byAdding: .day, value: offset, to: today)!
            if dayButton(future).exists { XCTAssertFalse(dayButton(future).isEnabled) }
        }
        app.buttons["previousWeightWeek"].tap()
        XCTAssertTrue(["", "Weight"].contains(amount.value as? String ?? "unexpected value"))
        XCTAssertFalse(app.buttons["deleteWeight"].exists)
        XCTAssertTrue(app.buttons["nextWeightWeek"].isEnabled)
        let prior = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        XCTAssertEqual(dayButton(prior).value as? String, "No weigh-in")
        amount.tap(); amount.typeText("181.2")
        app.buttons["nextWeightWeek"].tap()
        XCTAssertTrue(app.buttons["Save and switch"].waitForExistence(timeout: 3))
        app.buttons["Save and switch"].tap()
        XCTAssertEqual(amount.value as? String, "180.5")
        XCTAssertTrue(app.buttons["deleteWeight"].exists)
        app.buttons["previousWeightWeek"].tap()
        XCTAssertEqual(amount.value as? String, "181.2")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Weigh-in week picker"; attachment.lifetime = .keepAlways; add(attachment)
        // A changed amount must stay on its own date when another day is selected.
        amount.tap(); amount.typeText("3")
        let neighboring = Calendar.current.date(byAdding: .day, value: Calendar.current.component(.weekday, from: prior) == 7 ? -1 : 1, to: prior)!
        dayButton(neighboring).tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 3))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(["", "Weight"].contains(amount.value as? String ?? "unexpected value"))
        dayButton(prior).tap()
        XCTAssertEqual(amount.value as? String, "181.2")
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
