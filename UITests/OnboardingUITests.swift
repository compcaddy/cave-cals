import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 10))
    }
    private func next() { app.buttons["onboardingContinue"].tap() }
    private func enter(_ id: String, _ text: String) {
        let field = app.textFields[id]
        for _ in 0..<5 {
            let button = app.buttons["onboardingContinue"]
            if field.isHittable && field.frame.maxY < button.frame.minY - 10 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        field.tap(); field.typeText(text)
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func replace(_ id: String, with text: String) {
        let field = app.textFields[id]
        let old = field.value as? String ?? ""
        // Centered numbers put a center tap inside the text; tap its trailing edge.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        XCTAssertEqual(field.value as? String, text)
    }
    private func basics() {
        next()
        XCTAssertFalse(app.buttons["onboardingContinue"].isEnabled)
        app.buttons["gender-Male"].tap(); enter("planAge", "35"); next()
        let metric = app.segmentedControls["planUnits"].buttons["kg / cm"]
        metric.tap()
        enter("planHeight", "180"); enter("planWeight", "90"); next()
        app.buttons["activity-Lightly active"].tap(); next()
    }
    func testCalculatedPlanAndWeightIntegration() {
        capture("01 Welcome")
        basics()
        enter("planGoalWeight", "80")
        app.buttons["pace-0.5"].tap(); next()
        XCTAssertTrue(app.textFields["planCalories"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["planCalories"].value as? String, "2050")
        capture("02 Calorie plan")
        next()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 of 2,050 calories")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["todayWeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
        app.buttons["caloriePlan"].tap(); next()
        XCTAssertEqual(app.textFields["planAge"].value as? String, "35")
        next()
        XCTAssertEqual(app.textFields["planWeight"].value as? String, "90")
        XCTAssertEqual(app.textFields["planHeight"].value as? String, "180")
    }
    func testSkipAndManualSetupRemainAvailable() {
        app.buttons["manualSetup"].tap()
        XCTAssertTrue(app.textFields["profileGoal"].waitForExistence(timeout: 5))
        app.buttons["Me Go Back"].tap()
        app.buttons["skipGoal"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 calories")
    }
    func testMinorGetsNoAutomatedTarget() {
        next(); app.buttons["gender-Female"].tap(); enter("planAge", "16"); next()
        XCTAssertFalse(app.textFields["planCalories"].exists)
        XCTAssertTrue(app.buttons["manualSetup"].exists)
        capture("03 Manual path")
        app.buttons["skipGoal"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    func testUnitsBackNavigationAndUnsafeGoal() {
        next(); app.buttons["gender-Female"].tap(); enter("planAge", "30"); next()
        app.segmentedControls["planUnits"].buttons["lb / ft"].tap()
        enter("planHeight", "5"); enter("planInches", "6"); enter("planWeight", "150")
        app.segmentedControls["planUnits"].buttons["kg / cm"].tap()
        XCTAssertEqual(app.textFields["planHeight"].value as? String, "167.6")
        next(); app.buttons["activity-Mostly sitting"].tap(); next()
        enter("planGoalWeight", "40"); next()
        XCTAssertFalse(app.textFields["planCalories"].exists)
        app.buttons["onboardingBack"].tap()
        XCTAssertEqual(app.textFields["planGoalWeight"].value as? String, "40")
    }
    func testMaintenanceCustomTargetAndForgettingDetails() {
        basics()
        app.segmentedControls["planIntent"].buttons["Maintain weight"].tap(); next()
        XCTAssertEqual(app.textFields["planCalories"].value as? String, "2600")
        replace("planCalories", with: "400")
        XCTAssertFalse(app.buttons["onboardingContinue"].isEnabled)
        XCTAssertTrue(app.staticTexts["planTargetValidation"].exists)
        replace("planCalories", with: "2500")
        next()
        app.buttons["Settings"].tap()
        app.buttons["forgetCaloriePlan"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["forgetCaloriePlan"].exists)
        app.buttons["forgetCaloriePlan"].tap(); app.buttons["Forget details"].tap()
        XCTAssertFalse(app.buttons["forgetCaloriePlan"].exists)
        XCTAssertTrue(app.buttons["caloriePlan"].label.contains("Build"))
        XCTAssertEqual(app.buttons["adjustGoal"].value as? String, "2,500")
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
    }
    func testManualRouteBackReturnsToAboutYouAfterRevisingAnswers() {
        basics()
        app.buttons["onboardingBack"].tap()
        app.buttons["onboardingBack"].tap()
        app.buttons["onboardingBack"].tap()
        app.buttons["gender-Prefer not to say"].tap(); next()
        XCTAssertTrue(app.buttons["manualSetup"].exists)
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.buttons["gender-Prefer not to say"].exists)
    }
    func testLargestTextCanFinishWithoutAGoal() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        next()
        app.buttons["gender-Male"].tap()
        enter("planAge", "16"); next()
        capture("04 Large text manual route")
        XCTAssertTrue(app.buttons["skipGoal"].isHittable)
        app.buttons["skipGoal"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
}
