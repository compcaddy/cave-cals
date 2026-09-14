import XCTest

final class ECCUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.textFields["profileGoal"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["profileName"].exists)
        XCTAssertTrue(app.buttons["Me Start Now"].isEnabled)
        app.buttons["Me Start Now"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    private func closeSearchDrawer() {
        if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap() }
        app.buttons["Close search"].tap()
    }
    func testTypingHidesFooterAndClearRestoresIt() {
        let search = app.textFields["foodSearch"]
        search.tap()
        search.typeText("Ban")
        XCTAssertTrue(app.buttons["Clear search"].exists)
        XCTAssertFalse(app.buttons["Close search"].exists)
        XCTAssertFalse(app.buttons["searchQuickCalories"].exists)
        app.buttons["Clear search"].tap()
        XCTAssertEqual(search.value as? String, "search food or enter cals")
        XCTAssertTrue(app.buttons["Close search"].exists)
        XCTAssertTrue(app.buttons["searchQuickCalories"].exists)
    }
    func quickAdd(_ calories: String) {
        if !app.buttons["Close search"].exists { app.buttons["openSearch"].tap() }
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText(calories)
        let add = app.buttons["Add \(calories) calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
        closeSearchDrawer()
    }
    func testRepeatedAddsStayInSearchAndUndoLatest() {
        let search = app.textFields["foodSearch"]
        search.tap()
        search.typeText("75")
        let add = app.buttons["Add 75 calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(search.exists)
        XCTAssertEqual(search.value as? String, "75")
        // Wait for the coin to complete before intentionally logging another serving.
        sleep(2)
        add.tap()
        XCTAssertFalse(app.buttons["Close search"].exists)
        app.buttons["Undo"].firstMatch.tap()
        closeSearchDrawer()
        assertSummary("75 of 2,100 calories")
    }

    func testQuickCalorieGridAddsWithoutOpeningEditor() {
        app.buttons["Quick calories"].tap()
        XCTAssertTrue(app.buttons["Select 50 calories"].exists)
        XCTAssertTrue(app.buttons["Select 1,000 calories"].exists || app.buttons["Select 1000 calories"].exists)
        let gridShot = XCTAttachment(screenshot: app.screenshot())
        gridShot.name = "Quick calorie grid"
        gridShot.lifetime = .keepAlways
        add(gridShot)
        XCTAssertFalse(app.buttons["Add quick calories"].isEnabled)
        app.buttons["Select 200 calories"].tap()
        let name = app.textFields["quickCalorieName"]
        name.tap()
        name.typeText("Afternoon snack")
        XCTAssertTrue(app.buttons["Add quick calories"].isEnabled)
        app.buttons["Add quick calories"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '200 cal'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["foodSearch"].exists)
        XCTAssertFalse(app.textFields["servingSize"].exists)
        closeSearchDrawer()
        assertSummary("200 of 2,100 calories")
    }

    func testSkipGoalThenAddGoalInSettings() {
        app.terminate(); app.launch()
        let skip = app.buttons["skipGoal"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5)); skip.tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "0 calories")
        quickAdd("325")
        assertSummary("325 calories")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'remaining'")).firstMatch.exists)
        if app.buttons["Close search"].exists { closeSearchDrawer() }
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.textFields["settingsName"].exists)
        app.buttons["adjustGoal"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap(); goal.typeText("2100")
        app.buttons["Save Changes"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 of 2,100 calories")
        if app.buttons["Close search"].exists { closeSearchDrawer() }
        app.buttons["Settings"].tap()
        app.buttons["adjustGoal"].tap()
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "2100")
        app.buttons["skipGoal"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 calories")
    }
    func testAdjustGoalCancelKeepsExistingGoal() {
        if app.buttons["Close search"].exists { closeSearchDrawer() }
        app.buttons["Settings"].tap()
        app.buttons["adjustGoal"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "2100")
        goal.tap(); goal.typeText(XCUIKeyboardKey.delete.rawValue + "5")
        app.buttons["Me Go Back"].tap()
        app.buttons["Done"].tap()
        assertSummary("0 of 2,100 calories")
    }
    private func assertSummary(_ label: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: app.otherElements["calorieSummary"])
        let result = XCTWaiter.wait(for: [match], timeout: 5)
        if result != .completed {
            print(app.debugDescription)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(result, .completed)
    }
    func testQuickAddUndoAndDelete() {
        quickAdd("325")
        XCTAssertTrue(app.staticTexts["325 calories"].waitForExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' ")).count, 0)
        quickAdd("180")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.swipeLeft(); app.buttons["Delete"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' ")).count, 0)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["180 calories"].waitForExistence(timeout: 3))
    }
    func testEntryRowsSelectTheirValuesForReplacement() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["Edit 140 calories"].tap()
        let size = app.textFields["servingSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        app.staticTexts["serving size"].tap()
        size.typeText("14.2 g")
        app.staticTexts["cals / serving"].tap()
        let calories = app.textFields["caloriesPerServing"]
        calories.typeText("70")
        XCTAssertEqual(calories.value as? String, "70")
        app.staticTexts["# of servings"].tap()
        let servings = app.textFields["servingCount"]
        servings.typeText("1.5")
        XCTAssertEqual(servings.value as? String, "1.5")
        size.tap(); size.typeText("1 cup")
        XCTAssertEqual(size.value as? String, "1 cup")
        // Tapping the same row again also selects its current value.
        app.staticTexts["serving size"].tap(); size.typeText("2 cups")
        XCTAssertEqual(size.value as? String, "2 cups")
        XCTAssertEqual(app.textFields["entryCalories"].value as? String, "105")
    }
    func testNamedEntryServingEditorAndSavedMeal() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["Edit 140 calories"].tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Cheerios")
        // Serving controls are shown directly in the editor.
        app.buttons["Increase servings"].tap()
        app.buttons["saveEntry"].tap()
        if app.buttons["Close search"].exists { closeSearchDrawer() }
        app.buttons["Settings"].tap()
        app.buttons["Meals"].tap()
        app.buttons["Create from Today’s Entries"].tap()
        app.buttons["Select Cheerios"].tap()
        let mealName = app.textFields["mealName"]; mealName.tap(); mealName.typeText("Breakfast")
        app.buttons["Save Meal"].tap()
        XCTAssertTrue(app.buttons["Add Breakfast"].waitForExistence(timeout: 3))
    }
    func testWeekNavigationAndManualBarcodeFallback() {
        closeSearchDrawer()
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["Next day"].isEnabled)
        app.buttons["Next day"].tap()
        XCTAssertFalse(app.buttons["Next day"].isEnabled)
        app.buttons["Scan barcode"].tap()
        let manual = app.buttons["Enter calories manually"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        XCTAssertTrue(app.textFields["entryCalories"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }
    func testUnavailableCameraOffersManualCaloriesWithoutBarcodeLookup() {
        app.buttons["Scan barcode"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Make sure you have granted this app access to your camera."].exists)
        XCTAssertFalse(app.textFields["barcodeInput"].exists)
        XCTAssertFalse(app.buttons["Look Up"].exists)
        XCTAssertFalse(app.staticTexts["Product data from Open Food Facts"].exists)
        app.buttons["Enter calories manually"].tap()
        let calories = app.textFields["entryCalories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 3))
        calories.tap(); calories.typeText(XCUIKeyboardKey.delete.rawValue + "220")
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "220 of 2,100 calories")
    }
    func testMealFromScratchAndScaledAdd() {
        if app.buttons["Close search"].exists { closeSearchDrawer() }
        app.buttons["Settings"].tap(); app.buttons["Meals"].tap()
        app.buttons["Create from Scratch"].tap()
        let mealName = app.textFields["mealName"]
        XCTAssertTrue(mealName.waitForExistence(timeout: 3)); mealName.tap(); mealName.typeText("Coffee break")
        app.buttons["Add food"].tap()
        app.buttons["Create manual item"].tap()
        let calories = app.textFields["entryCalories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 3)); calories.tap(); calories.typeText(XCUIKeyboardKey.delete.rawValue + "120")
        let name = app.textFields["entryName"]; name.tap(); name.typeText("Coffee")
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.buttons["Save Meal"].waitForExistence(timeout: 4)); app.buttons["Save Meal"].tap()
        let add = app.buttons["Add Coffee break"]
        XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
        closeSearchDrawer()
        app.buttons["Increase servings"].tap(); app.buttons["Add Meal"].tap()
        let back = app.navigationBars["Meals"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 4)); back.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["180"].waitForExistence(timeout: 4))
    }
}

final class ReleaseScreenshotTests: XCTestCase {
    func testCaptureScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Close search"].waitForExistence(timeout: 10))
        app.buttons["Close search"].tap()
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
        capture(app, "01-Daily-diary")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'entry-' ")).firstMatch.tap()
        XCTAssertTrue(app.textFields["entryName"].waitForExistence(timeout: 5))
        capture(app, "02-Edit-portions")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
        capture(app, "03-Smart-suggestions")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

final class AICaptureFlowTests: XCTestCase {
    func testMealPhotoSelectionAndRemovalWithoutUpfrontPaywall() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Close search"].waitForExistence(timeout: 5))
        app.buttons["Close search"].tap()
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.navigationBars["Meal Scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiPaywall"].exists)
        XCTAssertFalse(app.switches["aiConsent"].exists)
        app.buttons["aiPhotoPicker"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        // The simulator fixture is imported before this test; first tile in the system picker.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.39)).tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Scan and Analyze"].isEnabled)
        XCTAssertFalse(app.buttons["aiPaywall"].exists)
        app.buttons["Remove photo"].tap()
        XCTAssertFalse(app.buttons["Remove photo"].exists)
        XCTAssertTrue(app.buttons["aiPhotoPicker"].exists)
    }

    func testVoiceStartsWithoutUpfrontPaywall() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Close search"].waitForExistence(timeout: 5))
        app.buttons["Close search"].tap()
        app.buttons["Voice entry"].tap()
        XCTAssertTrue(app.navigationBars["Voice logging"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Recording"].waitForExistence(timeout: 5))
        app.buttons["Start Recording"].tap()
        XCTAssertTrue(app.buttons["Stop and Analyze"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Up to 60 seconds"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Analyze sends this recording'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["aiPaywall"].exists)
        XCTAssertFalse(app.switches["aiConsent"].exists)
        app.buttons["aiCancelRecording"].tap()
        XCTAssertTrue(app.buttons["openSearch"].waitForExistence(timeout: 5))
    }
}
