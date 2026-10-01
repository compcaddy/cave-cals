import XCTest

final class ProgressUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--progress-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["progress"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testRecapStartsOnCurrentWeekAndCanGoBack() {
        app.buttons["progress"].tap()
        let status = app.staticTexts["reviewWeekStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "In progress")
        XCTAssertFalse(app.buttons["reviewWeekNext"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["reviewWeightAverage"].firstMatch.exists)
        app.buttons["reviewWeekPrevious"].tap()
        XCTAssertFalse(status.exists)
        XCTAssertTrue(app.buttons["reviewWeekNext"].isEnabled)
        app.buttons["reviewWeekNext"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["reviewWeekNext"].isEnabled)
        capture("Current week recap")
        app.buttons["printProgress"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Recap"].waitForExistence(timeout: 5))
        capture("Current week PDF")
    }
    func testProgressReviewChartsWeightHistoryAndPrintPreview() {
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        capture("Weekly Recap cards")
        XCTAssertEqual(app.buttons["progressDailyBreakdown"].firstMatch.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "incomplete calorie day")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["reviewCalorieAverage"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let nutrition = app.segmentedControls["nutritionChartRange"]
        reveal(nutrition)
        for period in ["Month", "Year", "Week"] {
            nutrition.buttons[period].tap()
            capture("Progress macro breakdown " + period)
            reveal(nutrition)
        }
        app.buttons["nutritionChartMode"].tap()
        app.buttons["Protein"].tap()
        // The sample diary ends yesterday, so on the first day of a week (--uitesting starts weeks on Monday)
        // this week is still empty and yesterday is last week's final column.
        var calendar = Calendar.current; calendar.firstWeekday = 2
        if calendar.dateInterval(of: .weekOfYear, for: Date())!.start == calendar.startOfDay(for: Date()) {
            XCTAssertTrue(app.staticTexts["No food logged in this period."].exists)
            app.buttons["nutritionChartRangePrevious"].tap()
        }
        XCTAssertTrue(app.staticTexts["nutritionChartValue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["nutritionChartValue"].label.contains("g protein"))
        capture("Progress protein chart")
        let weight = app.segmentedControls["weightChartRange"]
        reveal(weight)
        for period in ["Week", "Year", "Month"] { weight.buttons[period].tap() }
        capture("Progress weight chart")
        let history = app.buttons["weightHistory"]
        reveal(history); history.tap()
        XCTAssertTrue(app.navigationBars["Weigh-ins"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["printProgress"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Recap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sendProgressToPrinter"].isEnabled)
        capture("Weekly Recap six-week PDF")
        app.buttons["sendProgressToPrinter"].tap()
        XCTAssertTrue(app.staticTexts["Printer"].waitForExistence(timeout: 5), app.debugDescription)
        capture("Native print options")
    }
    func testProgressAtLargestTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        capture("Progress largest text")
        reveal(app.buttons["progressDailyBreakdown"].firstMatch)
        app.buttons["progressDailyBreakdown"].firstMatch.tap()
        app.scrollViews.firstMatch.swipeUp()
        capture("Daily breakdown largest text")
        reveal(app.buttons["printProgress"])
        app.buttons["printProgress"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Recap"].waitForExistence(timeout: 5))
    }
    func testWeekStartPreferenceAndNoWeightChartInProfile() {
        app.buttons["profile"].tap()
        XCTAssertFalse(app.segmentedControls["weightChartRange"].exists)
        XCTAssertTrue(app.buttons["todayWeight"].exists)
        app.navigationBars["About You"].buttons["Done"].tap()
        app.buttons["progress"].tap()
        let picker = app.buttons["progressWeekStart"]
        reveal(picker); picker.tap()
        app.buttons["Sunday"].tap()
        XCTAssertTrue(app.staticTexts["Sunday"].waitForExistence(timeout: 5), app.debugDescription)
        capture("Progress week preferences")
    }
}
