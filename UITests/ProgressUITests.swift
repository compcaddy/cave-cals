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
        capture("Weekly Recap five-week PDF")
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
        reveal(picker)
        XCTAssertTrue(app.staticTexts["Weekday Start"].exists)
        XCTAssertFalse(app.buttons["progressMethod"].exists, "How averages work is hidden for now")
        picker.tap()
        app.buttons["Sunday"].tap()
        XCTAssertTrue(app.staticTexts["Sunday"].waitForExistence(timeout: 5), app.debugDescription)
        capture("Progress week preferences")
    }

    func testProgressPhotosCameraTimerGhostCompareAndEdit() {
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        let take = app.buttons["progressPhotoTake"].firstMatch
        reveal(take)
        capture("Progress photos card")
        take.tap()
        let shutter = app.buttons["progressPhotoShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        // The preview has earlier Front photos, so the last one shows as a ghost to line up with.
        XCTAssertTrue(app.sliders["progressPhotoGhost"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["progressPhotoAngle-Front"].isSelected)
        capture("Camera with ghost")
        let timer = app.buttons["progressPhotoTimer"]
        if timer.value as? String == "Off" { timer.tap() }
        shutter.tap()
        let countdown = app.staticTexts["progressPhotoCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 3))
        capture("Timer counting down")
        // The shutter stops a countdown.
        shutter.tap()
        XCTAssertFalse(countdown.waitForExistence(timeout: 1.5))
        timer.tap()
        XCTAssertEqual(timer.value as? String, "Off")
        shutter.tap()
        let use = app.buttons["progressPhotoUse"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        capture("Review shot")
        use.tap()
        // Members stay in the camera, moved on to the next angle.
        let done = app.buttons["progressPhotoDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["progressPhotoAngle-Back"].isSelected)
        // No earlier Back photo: no ghost slider and no explanation, just space kept for it.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.sliders["progressPhotoGhost"])
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Next time")).firstMatch.exists)
        capture("Camera without a ghost")
        done.tap()

        let compare = app.buttons["progressPhotosCompare"]
        reveal(compare)
        capture("Progress photos card with today")
        compare.tap()
        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["compareSummary"].waitForExistence(timeout: 5))
        capture("Compare side by side")
        app.segmentedControls["compareLayout"].buttons["Slider"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["compareSlider"].waitForExistence(timeout: 3))
        capture("Compare slider")
        app.navigationBars.buttons.firstMatch.tap()

        let all = app.buttons["progressPhotosAll"]
        reveal(all); all.tap()
        XCTAssertTrue(app.navigationBars["Progress Photos"].waitForExistence(timeout: 5))
        capture("All photos")
        app.buttons["progressPhoto-Front"].tap()
        let edit = app.buttons["editProgressPhoto"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        capture("Photo viewer")
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Photo"].waitForExistence(timeout: 5))
        app.buttons["photoAngleOther"].tap()
        let name = app.textFields["photoAngleName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Flexing")
        capture("Edit photo angle")
        app.buttons["saveProgressPhoto"].tap()
        XCTAssertTrue(app.navigationBars["Flexing"].waitForExistence(timeout: 5))
    }
    /// On-Target vs. Over Days: the sample over days start later and add a late snack; Cave Coach gives 3 tips;
    /// what counts as on target can change.
    func testGoodDaysVersusOverDaysAndCaveCoach() {
        app.terminate()
        app.launchArguments += ["--coach-fixture"]
        app.launch()
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        let good = app.descendants(matching: .any)["habitsGood"].firstMatch
        reveal(good)
        XCTAssertTrue(good.label.hasPrefix("On-target days: "), good.label)
        let start = app.descendants(matching: .any)["habitFinding-start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.label.contains("earlier than over days"), start.label)
        let ask = app.buttons["askCoach"]
        reveal(ask)
        // Clear of the bottom edge, so the tap lands on the button.
        app.scrollViews.firstMatch.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        ask.tap()
        let intro = app.staticTexts["coachIntro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        XCTAssertEqual(intro.label, "Based on your last 90 days, here are 3 tips for healthier eating habits:")
        XCTAssertTrue(app.descendants(matching: .any)["coachTip-0"].firstMatch.label.hasPrefix("Eat breakfast by 9"))
        XCTAssertEqual(ask.label, "Get new tips")
        // New tips replace the old ones (the stand-in marks a second round).
        ask.tap()
        let first = app.descendants(matching: .any)["coachTip-0"].firstMatch
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Eat breakfast by 9 again'"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 5), .completed, first.label)
        XCTAssertFalse(app.descendants(matching: .any)["coachTip-3"].firstMatch.exists)
        // What counts as on target: pick within a percentage and change it to 10%.
        let change = app.buttons["habitsChangeRule"]
        for _ in 0..<12 where !change.isHittable { app.scrollViews.firstMatch.swipeDown() }
        change.tap()
        let within = app.descendants(matching: .any)["onTarget-withinPercent"].firstMatch
        XCTAssertTrue(within.waitForExistence(timeout: 5))
        within.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["onTargetEdit-withinPercent"].tap()
        let value = app.alerts.textFields.firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        value.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "10")
        app.alerts.buttons["Save"].tap()
        app.buttons["onTargetDone"].tap()
        let summary = app.staticTexts["habitsRuleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "On target: within 10% of your goal")
    }
    /// Trends: weekday and hour charts over a chosen range; tapping a bar shows its value.
    func testTrendsShowWeekdaysAndHours() {
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        let hourChart = app.descendants(matching: .any)["trendsHourChart"].firstMatch
        reveal(app.segmentedControls["trendsHourMode"])
        let weekdayDetail = app.staticTexts["trendsWeekdayDetail"]
        XCTAssertTrue(weekdayDetail.label.hasPrefix("Average calories on complete days · based on"), weekdayDetail.label)
        let weekdayChart = app.descendants(matching: .any)["trendsWeekdayChart"].firstMatch
        Thread.sleep(forTimeInterval: 0.8) // let the scroll settle so the tap selects rather than stops it
        XCTAssertTrue(tap(weekdayChart, at: CGVector(dx: 0.2, dy: 0.5), until: weekdayDetail, contains: "cals on average"), weekdayDetail.label)
        // The sample days are breakfast, lunch, and dinner: lunch hour has food.
        let hourDetail = app.staticTexts["trendsHourDetail"]
        XCTAssertTrue(hourDetail.label.hasPrefix("Average calories in each hour"), hourDetail.label)
        // Bring the whole hour chart on screen first; a coordinate tap doesn't scroll.
        reveal(hourDetail)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(tap(hourChart, at: CGVector(dx: 0.56, dy: 0.4), until: hourDetail, contains: "cals a day"), hourDetail.label)
        app.segmentedControls["trendsHourMode"].buttons["% of day"].tap()
        XCTAssertTrue(waitForLabel(hourDetail, containing: "% of the day’s calories"), hourDetail.label)
        app.segmentedControls["trendsRange"].buttons["All time"].tap()
    }
    /// Taps a chart until the detail line changes (a tap can land while the page is still settling).
    private func tap(_ chart: XCUIElement, at offset: CGVector, until detail: XCUIElement, contains text: String) -> Bool {
        for _ in 0..<3 {
            chart.coordinate(withNormalizedOffset: offset).tap()
            if waitForLabel(detail, containing: text) { return true }
        }
        return false
    }
    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
    /// Long-press a progress photo → Delete, then confirm (on the card's latest photos and in the grid).
    func testLongPressDeletesAProgressPhoto() {
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        // The card's latest photos: Delete asks first, and Cancel keeps the photo.
        let latest = app.buttons["progressPhotosLatest"]
        reveal(latest)
        latest.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.7)).press(forDuration: 1.0)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        capture("Progress photo long-press menu")
        delete.tap()
        let confirmCard = app.buttons["Delete Photo"]
        XCTAssertTrue(confirmCard.waitForExistence(timeout: 3))
        // iOS 26 shows the question as a popover without a Cancel button; tapping away cancels.
        app.navigationBars["Progress"].tap()
        XCTAssertTrue(confirmCard.waitForNonExistence(timeout: 3))
        XCTAssertTrue(latest.exists, "Cancel keeps the photo")
        // In the latest day's grid, confirming removes it.
        latest.tap()
        XCTAssertTrue(app.navigationBars["Progress Photos"].waitForExistence(timeout: 5))
        let front = app.buttons["progressPhoto-Front"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.press(forDuration: 1.0)
        XCTAssertTrue(delete.waitForExistence(timeout: 3)); delete.tap()
        let confirm = app.buttons["Delete Photo"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap()
        XCTAssertTrue(front.waitForNonExistence(timeout: 3))
    }
    func testLibraryPhotoOpensAddPhotoDatedWhenTaken() throws {
        app.buttons["progress"].tap()
        let library = app.buttons["progressPhotoLibrary"].firstMatch
        reveal(library); library.tap()
        // The system picker runs out of process; pick its first photo.
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo")).firstMatch
        guard photo.waitForExistence(timeout: 10) else { throw XCTSkip("No photos in this simulator's library") }
        // Its cells don't report as hittable, so tap the middle of one.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Add Photo"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["photoAngle-Back"].tap()
        capture("Add photo from library")
        app.buttons["saveProgressPhoto"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.navigationBars["Add Photo"])
        waitForExpectations(timeout: 5)
        let all = app.buttons["progressPhotosAll"]
        reveal(all); all.tap()
        XCTAssertTrue(app.navigationBars["Progress Photos"].waitForExistence(timeout: 5))
        capture("All photos after library import")
    }
    func testSecondPhotoOfADayAsksForCaveCalsPlusWhenFree() {
        app.terminate()
        app.launchArguments += ["--photos-free"]
        app.launch()
        app.buttons["progress"].tap()
        let take = app.buttons["progressPhotoTake"].firstMatch
        reveal(take); take.tap()
        let shutter = app.buttons["progressPhotoShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        let timer = app.buttons["progressPhotoTimer"]
        if timer.value as? String == "On" { timer.tap() }
        shutter.tap()
        let use = app.buttons["progressPhotoUse"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        use.tap()
        // Free: the camera closes after the day's one photo, and the card says why.
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["progressPhotoFreeLimit"].waitForExistence(timeout: 5))
        reveal(take); take.tap()
        XCTAssertTrue(app.staticTexts["Subscriptions unavailable"].waitForExistence(timeout: 5), "Simulator paywall stand-in")
        XCTAssertFalse(app.buttons["progressPhotoShutter"].exists)
        capture("Second photo paywall")
    }
}
