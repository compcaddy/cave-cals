import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 10))
    }
    private func skipOffer() {
        let skip = app.buttons["skipOnboardingPaywall"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        XCTAssertFalse(skip.exists)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
    }
    private func next() { let button = app.buttons["onboardingContinue"]; reveal(button); button.tap() }
    /// Confirms "Just start tracking" and lands on the tracking step.
    private func skipPlan() {
        app.buttons["skipGoal"].tap()
        let skip = app.alerts.buttons["Yes, skip plan"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.switches["planTrackWeight"].waitForExistence(timeout: 5))
    }
    private var ageDial: XCUIElement { app.descendants(matching: .any)["planAge"] }
    /// Drags the age dial a few numbers at a time until it reads the target. Each number's slot scales with
    /// text size along with the dial, so its width is 56/104 of the dial's height.
    private func setAge(_ target: Int) {
        let dial = ageDial
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        revealField(dial)
        let slot = dial.frame.height * 56 / 104
        let reach = max(1, Int((dial.frame.width / 2 - 20) / slot))
        for _ in 0..<30 {
            guard let text = dial.value as? String, let current = Int(text.prefix { $0.isNumber }), current != target else { break }
            let steps = max(-reach, min(reach, current - target))
            let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: CGFloat(steps) * slot, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertEqual(dial.value as? String, "\(target) years")
    }
    private func assertTrackingDefaults() {
        XCTAssertTrue(app.switches["planTrackWeight"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["planTrackWeight"].value as? String, "1")
        XCTAssertEqual(app.switches["planTrackMacros"].value as? String, "1")
    }
    private func revealField(_ field: XCUIElement) {
        for _ in 0..<5 {
            let button = app.buttons["onboardingContinue"]
            if field.isHittable && field.frame.maxY < button.frame.minY - 10 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
    }
    private func enter(_ id: String, _ text: String) {
        let field = app.textFields[id]
        revealField(field)
        field.tap(); field.typeText(text)
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    /// Tapping the target card selects the whole number, so typing replaces it; closing the keyboard regroups it.
    private func replaceTarget(with text: String, shows expected: String) {
        let field = app.textFields["planCalories"]
        revealField(field)
        app.staticTexts["Tap to adjust"].tap()
        field.typeText(text)
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        XCTAssertEqual(field.value as? String, expected)
    }
    private func basics(startingWeight: String = "90") {
        next()
        XCTAssertFalse(app.buttons["onboardingContinue"].isEnabled)
        XCTAssertEqual(ageDial.value as? String, "40 years")
        Thread.sleep(forTimeInterval: 0.6) // let the step transition finish so the dial is captured at rest
        capture("Me info default")
        app.buttons["gender-Male"].tap(); setAge(35)
        capture("Me info")
        next()
        let metric = app.segmentedControls["planUnits"].buttons["kg / cm"]
        metric.tap()
        enter("planHeight", "180"); enter("planWeight", startingWeight); next()
        app.buttons["activity-Lightly active"].tap()
        capture("Usual Day")
        next()
    }
    func testUnavailableOnboardingOfferCanCloseAndStillLog() {
        skipPlan(); next()
        XCTAssertTrue(app.buttons["skipOnboardingPaywall"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Subscriptions unavailable"].exists)
        capture("Skippable onboarding offer unavailable")
        app.buttons["Close"].tap()
        let search = app.textFields["foodSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("325")
        app.buttons["Add 325 calories"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skipOnboardingPaywall"].exists)
    }
    func testExistingProfileDoesNotShowOnboardingOffer() {
        app.terminate()
        app.launchArguments += ["--seed-goal", "2100"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skipOnboardingPaywall"].exists)
    }
    func testCalculatedPlanAndWeightIntegration() {
        capture("01 Welcome")
        basics()
        XCTAssertTrue(app.buttons["pace-0.25"].label.contains("0.25 kg per week"))
        XCTAssertTrue(app.buttons["pace-0.75"].label.contains("0.75 kg per week"))
        enter("planGoalWeight", "80")
        XCTAssertEqual(app.staticTexts["planGoalWeightNote"].label, "Current: 90.0 kg")
        app.buttons["pace-0.5"].tap()
        capture("Set Goal")
        next()
        assertTrackingDefaults()
        capture("02 Tracking choices")
        next()
        XCTAssertTrue(app.textFields["planCalories"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["planCalories"].value as? String, "2,050")
        capture("03 Calorie plan")
        next()
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 of 2,050 calories")
        app.buttons["profile"].tap()
        XCTAssertTrue(app.buttons["todayWeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
        app.buttons["caloriePlan"].tap(); next()
        XCTAssertEqual(ageDial.value as? String, "35 years")
        next()
        XCTAssertEqual(app.textFields["planWeight"].value as? String, "90")
        XCTAssertEqual(app.textFields["planHeight"].value as? String, "180")
    }
    func testWelcomeOffersPlanOrSkipWithoutManualShortcut() {
        XCTAssertEqual(app.buttons["onboardingContinue"].label, "Me Build Plan")
        XCTAssertFalse(app.buttons["manualSetup"].exists)
        XCTAssertFalse(app.switches["planTrackWeight"].exists)
        capture("Welcome")
        // Skipping asks first; declining starts the plan instead.
        app.buttons["skipGoal"].tap()
        let buildPlan = app.alerts.buttons["No, me build plan"]
        XCTAssertTrue(buildPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Yes, skip plan"].exists)
        capture("Skip plan confirmation")
        buildPlan.tap()
        XCTAssertTrue(app.buttons["gender-Male"].waitForExistence(timeout: 5))
        app.buttons["onboardingBack"].tap()
        skipPlan()
        assertTrackingDefaults()
        XCTAssertEqual(app.buttons["onboardingContinue"].label, "Let’s go")
        capture("Skip tracking choices")
        // Back from the skip route's tracking step returns to the welcome.
        app.buttons["onboardingBack"].tap()
        XCTAssertEqual(app.buttons["onboardingContinue"].label, "Me Build Plan")
        skipPlan(); next()
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 calories")
        XCTAssertTrue(app.buttons["weighInReminder"].exists)
        app.buttons["profile"].tap()
        XCTAssertEqual(app.switches["trackMacros"].firstMatch.value as? String, "1")
        XCTAssertEqual(app.switches["trackWeight"].firstMatch.value as? String, "1")
    }
    private func turnOffTrackingChoices() {
        for id in ["planTrackWeight", "planTrackMacros"] {
            let toggle = app.switches[id]
            // Compatibility mode can report a switch behind the fixed footer as hittable.
            revealField(toggle); toggle.tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
    }
    private func assertTrackingOff() {
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["weighInReminder"].exists)
        app.buttons["profile"].tap()
        XCTAssertEqual(app.switches["trackMacros"].firstMatch.value as? String, "0")
        XCTAssertEqual(app.switches["trackWeight"].firstMatch.value as? String, "0")
        XCTAssertFalse(app.buttons["todayWeight"].exists)
    }
    func testTrackingChoicesCanBeDisabledWithoutAGoal() {
        skipPlan()
        turnOffTrackingChoices(); next()
        assertTrackingOff()
    }
    func testCalculatedPlanRespectsDisabledTracking() {
        basics(); enter("planGoalWeight", "80"); next()
        turnOffTrackingChoices(); next(); next()
        assertTrackingOff()
    }
    func testManualGoalRespectsDisabledTracking() {
        next(); app.buttons["gender-Prefer not to say"].tap(); setAge(35); next()
        turnOffTrackingChoices(); next()
        app.buttons["manualSetup"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap(); goal.typeText("2100")
        app.buttons["Save Changes"].tap()
        assertTrackingOff()
    }
    private func openDeveloperSettings() {
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        app.buttons["appSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let developer = app.buttons["Developer settings"]
        for _ in 0..<5 {
            if developer.exists && developer.isHittable { break }
            app.collectionViews.allElementsBoundByIndex.last?.swipeUp()
        }
        XCTAssertTrue(developer.waitForExistence(timeout: 5))
        developer.tap()
        XCTAssertTrue(app.buttons["previewOnboarding"].waitForExistence(timeout: 5))
    }
    private func openOnboardingPreview() {
        app.buttons["previewOnboarding"].tap()
        XCTAssertTrue(app.buttons["closeOnboardingPreview"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboardingContinue"].label, "Me Build Plan")
    }
    private func closeDeveloperSettings() {
        app.navigationBars["Developer settings"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
    }
    func testDeveloperOnboardingPreviewKeepsHistoryAndStartsFreshEachTime() {
        basics(); enter("planGoalWeight", "80"); app.buttons["pace-0.5"].tap(); next(); next(); next()
        skipOffer()
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("325")
        app.buttons["Add 325 calories"].firstMatch.tap()
        app.buttons["cancelAddMode"].tap()
        openDeveloperSettings()
        openOnboardingPreview()
        next(); app.buttons["gender-Female"].tap(); setAge(40)
        app.buttons["closeOnboardingPreview"].tap()
        XCTAssertTrue(app.buttons["previewOnboarding"].waitForExistence(timeout: 5))
        openOnboardingPreview()
        skipPlan(); assertTrackingDefaults()
        turnOffTrackingChoices(); next()
        XCTAssertTrue(app.buttons["previewOnboarding"].waitForExistence(timeout: 5))
        openOnboardingPreview()
        basics(startingWeight: "100")
        enter("planGoalWeight", "80"); next()
        assertTrackingDefaults()
        let macros = app.switches["planTrackMacros"]
        revealField(macros); macros.tap()
        next(); next()
        XCTAssertTrue(app.buttons["previewOnboarding"].waitForExistence(timeout: 5))
        closeDeveloperSettings()
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "325 of 2,050 calories")
        app.buttons["profile"].tap()
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
        XCTAssertEqual(app.switches["trackMacros"].firstMatch.value as? String, "1")
        app.buttons["caloriePlan"].tap(); next()
        XCTAssertEqual(ageDial.value as? String, "35 years")
    }
    func testDeveloperOnboardingPreviewManualGoalKeepsRealGoal() {
        skipPlan(); next()
        skipOffer()
        openDeveloperSettings(); openOnboardingPreview()
        next(); app.buttons["gender-Prefer not to say"].tap(); setAge(35); next(); next()
        app.buttons["manualSetup"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap(); goal.typeText("2400")
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["previewOnboarding"].waitForExistence(timeout: 5))
        closeDeveloperSettings()
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 calories")
    }
    func testMinorGetsNoAutomatedTarget() {
        next(); app.buttons["gender-Female"].tap(); setAge(16); next()
        assertTrackingDefaults(); next()
        XCTAssertFalse(app.textFields["planCalories"].exists)
        XCTAssertTrue(app.buttons["manualSetup"].exists)
        capture("04 Manual path")
        app.buttons["skipGoal"].tap()
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    private func waitForFocus(_ element: XCUIElement, _ message: String) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 3), .completed, message)
    }
    func testImperialHeightMovesAlongAndRejectsImpossibleValues() {
        next(); app.buttons["gender-Female"].tap(); next()
        app.segmentedControls["planUnits"].buttons["lb / ft"].tap()
        let feet = app.textFields["planHeight"], inches = app.textFields["planInches"], weight = app.textFields["planWeight"]
        feet.tap(); feet.typeText("8")
        XCTAssertNotEqual(feet.value as? String, "8")
        waitForFocus(feet, "An impossible foot value keeps the box open")
        feet.typeText("5")
        XCTAssertEqual(feet.value as? String, "5")
        waitForFocus(inches, "A foot value moves on to inches")
        inches.typeText("1")
        waitForFocus(inches, "1 could still become 10 or 11")
        inches.typeText("5")
        XCTAssertEqual(inches.value as? String, "1")
        inches.typeText("1")
        XCTAssertEqual(inches.value as? String, "11")
        waitForFocus(weight, "A finished inch value moves on to weight")
        inches.tap(); inches.typeText("7")
        XCTAssertEqual(inches.value as? String, "7")
        waitForFocus(weight, "Retyping inches replaces the old value and moves on")
        weight.typeText("150")
        capture("You start")
        XCTAssertTrue(app.buttons["onboardingContinue"].isEnabled)
    }
    func testAgeDialFlickTravelsFar() {
        next()
        let dial = ageDial
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        dial.swipeRight(velocity: .fast)
        Thread.sleep(forTimeInterval: 2) // let momentum settle and snap
        let age = (dial.value as? String).flatMap { Int($0.prefix { $0.isNumber }) } ?? 40
        XCTAssertLessThanOrEqual(age, 30, "One flick should move well past a handful of ages")
        setAge(15)
        capture("Age dial near 15")
    }
    func testUnitsBackNavigationAndUnsafeGoal() {
        next(); app.buttons["gender-Female"].tap(); setAge(30); next()
        app.segmentedControls["planUnits"].buttons["lb / ft"].tap()
        enter("planHeight", "5"); enter("planInches", "6"); enter("planWeight", "150")
        app.segmentedControls["planUnits"].buttons["kg / cm"].tap()
        XCTAssertEqual(app.textFields["planHeight"].value as? String, "167.6")
        next(); app.buttons["activity-Mostly sitting"].tap(); next()
        enter("planGoalWeight", "40"); next(); next()
        XCTAssertTrue(app.buttons["manualSetup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["planCalories"].exists)
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.switches["planTrackWeight"].waitForExistence(timeout: 5))
        app.buttons["onboardingBack"].tap()
        XCTAssertEqual(app.textFields["planGoalWeight"].value as? String, "40")
    }
    func testMaintenanceCustomTargetAndForgettingDetails() {
        basics()
        app.segmentedControls["planIntent"].buttons["Maintain"].tap(); next(); next()
        XCTAssertEqual(app.textFields["planCalories"].value as? String, "2,600")
        replaceTarget(with: "400", shows: "400")
        XCTAssertFalse(app.buttons["onboardingContinue"].isEnabled)
        XCTAssertTrue(app.staticTexts["planTargetValidation"].exists)
        replaceTarget(with: "2500", shows: "2,500")
        next()
        skipOffer()
        app.buttons["profile"].tap()
        // The saved goal shows under the calorie goal; its pencil reopens the calculator.
        XCTAssertTrue(app.buttons["caloriePlan"].label.hasPrefix("Goal: stay around"))
        app.buttons["caloriePlan"].tap()
        let clear = app.buttons["clearSavedAnswers"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap(); app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(clear.exists)
        clear.tap(); app.alerts.buttons["Clear answers"].tap()
        XCTAssertFalse(clear.waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons["caloriePlan"].label, "Help me decide")
        XCTAssertEqual(app.buttons["adjustGoal"].value as? String, "2,500")
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
    }
    func testManualRouteBackReturnsToAboutYouAfterRevisingAnswers() {
        basics()
        app.buttons["onboardingBack"].tap()
        app.buttons["onboardingBack"].tap()
        app.buttons["onboardingBack"].tap()
        app.buttons["gender-Prefer not to say"].tap(); next(); next()
        XCTAssertTrue(app.buttons["manualSetup"].exists)
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.switches["planTrackWeight"].waitForExistence(timeout: 5))
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.buttons["gender-Prefer not to say"].exists)
    }
    func testLargestTextCanFinishWithoutAGoal() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        capture("Large text welcome")
        next()
        app.buttons["gender-Male"].tap()
        setAge(16); next(); next()
        capture("05 Large text manual route")
        reveal(app.buttons["skipGoal"])
        XCTAssertTrue(app.buttons["skipGoal"].isHittable)
        app.buttons["skipGoal"].tap()
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    func testLargestTextCanCompleteCalculatedPlan() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        basics()
        enter("planGoalWeight", "80")
        let pace = app.buttons["pace-0.5"]
        reveal(pace); pace.tap(); next(); next()
        XCTAssertEqual(app.textFields["planCalories"].value as? String, "2,050")
        capture("06 Large text calculated target")
        next()
        skipOffer()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 of 2,050 calories")
    }
    func testCancelRevisedPlanKeepsAcceptedDetails() {
        basics(); enter("planGoalWeight", "80"); app.buttons["pace-0.5"].tap(); next(); next(); next()
        skipOffer()
        app.buttons["profile"].tap(); app.buttons["caloriePlan"].tap(); next()
        setAge(45)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons["adjustGoal"].value as? String, "2,050")
        XCTAssertTrue(app.buttons["todayWeight"].label.contains("90"))
        app.buttons["caloriePlan"].tap(); next()
        XCTAssertEqual(ageDial.value as? String, "35 years")
    }
    func testOversizedHeightCanBeCorrectedAfterChangingUnits() {
        next(); app.buttons["gender-Female"].tap(); setAge(30); next()
        app.segmentedControls["planUnits"].buttons["kg / cm"].tap()
        enter("planHeight", "999999999999999999999")
        enter("planWeight", "65")
        app.segmentedControls["planUnits"].buttons["lb / ft"].tap()
        XCTAssertTrue(app.staticTexts["Enter your height again."].exists)
        XCTAssertFalse(app.buttons["onboardingContinue"].isEnabled)
        enter("planHeight", "5"); enter("planInches", "6"); next()
        XCTAssertTrue(app.buttons["activity-Lightly active"].exists)
    }
}
