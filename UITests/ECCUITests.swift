import XCTest

final class ECCUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["manualSetup"].waitForExistence(timeout: 10))
        app.buttons["manualSetup"].tap()
        XCTAssertTrue(app.textFields["profileGoal"].waitForExistence(timeout: 5))
        app.textFields["profileGoal"].tap(); app.textFields["profileGoal"].typeText("2100")
        XCTAssertFalse(app.textFields["profileName"].exists)
        XCTAssertTrue(app.buttons["Save Changes"].isEnabled)
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    /// Home = date, totals, and the day's log. Clearing search always returns there.
    private func closeSearchDrawer() {
        if app.buttons["clearSearch"].exists { app.buttons["clearSearch"].tap() }
        if app.buttons["cancelAddMode"].exists { app.buttons["cancelAddMode"].tap() }
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
    }
    /// Add mode (pills) opens by tapping search; pills: "Logged" (Today), "Quick Add", "Meals".
    private func openAddMode(_ pill: String = "Quick Add") {
        let search = app.textFields["foodSearch"]
        if !app.buttons["Quick Add"].exists { search.tap() }
        XCTAssertTrue(app.buttons[pill].waitForExistence(timeout: 5))
        app.buttons[pill].tap()
    }
    private var onHome: Bool { app.otherElements["calorieSummary"].waitForExistence(timeout: 5) && !app.buttons["Quick Add"].exists }
    func testBriefBackgroundPreservesLoggedTab() {
        openAddMode("Meals")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Meals"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Meals"].isSelected)
    }

    func testUnifiedHomeSearchRestoresSelectedList() {
        XCTAssertTrue(onHome)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["Logged"].exists)
        let search = app.textFields["foodSearch"]
        XCTAssertTrue(app.buttons["Voice entry"].exists)
        // Tapping search hides the date and totals and shows the pills with Quick Add selected.
        search.tap()
        XCTAssertTrue(app.buttons["Quick Add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Quick Add"].isSelected)
        XCTAssertFalse(app.otherElements["calorieSummary"].exists)
        XCTAssertFalse(app.buttons["profile"].exists)
        XCTAssertFalse(app.buttons["Voice entry"].exists)
        search.typeText("75")
        let add = app.buttons["Add 75 calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertEqual(search.value as? String, "search / add")
        XCTAssertTrue(onHome)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        assertSummary("75 of 2,100 calories")
        XCTAssertTrue(app.staticTexts["homeLogHeader"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).firstMatch.exists)
        search.tap()
        search.typeText("Ban")
        let manualAdd = app.buttons["Add \"Ban\", enter calories"]
        XCTAssertTrue(manualAdd.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Quick Add"].exists)
        XCTAssertLessThan(manualAdd.frame.maxY, search.frame.minY)
        XCTAssertTrue(app.staticTexts["Results"].exists)
        closeSearchDrawer()
        XCTAssertTrue(onHome)
        XCTAssertTrue(app.buttons["Voice entry"].exists)
    }
    func testAddModeTodayListRepeatsOrEditsWithoutChangingTheOriginal() {
        quickAdd("140")
        openAddMode("Logged")
        let again = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add 140 calories", "foodDetails-140 calories")).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 3))
        again.tap()
        XCTAssertTrue(app.buttons["Logged"].isSelected)
        closeSearchDrawer()
        assertSummary("280 of 2,100 calories")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).count, 2)
    }
    func quickAdd(_ calories: String) {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText(calories)
        let add = app.buttons["Add \(calories) calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
        closeSearchDrawer()
    }
    func testSearchTitleEditsAndOnlyPlusAdds() {
        let search = app.textFields["foodSearch"]
        search.tap()
        search.typeText("Banana")
        let row = app.cells.containing(.button, identifier: "foodDetails-Banana").firstMatch
        let details = row.buttons["foodDetails-Banana"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(details.label, "Edit Banana")
        XCTAssertTrue(details.staticTexts["Banana"].exists)
        XCTAssertTrue(details.staticTexts.matching(NSPredicate(format: "label CONTAINS ' · 110 Cals'")).firstMatch.exists)
        details.tap()
        XCTAssertTrue(app.textFields["entryName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["entryName"].value as? String, "Banana")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Banana")
        XCTAssertFalse(app.buttons["Undo"].exists)
        let add = row.buttons.matching(identifier: "Add Banana")
        XCTAssertEqual(add.count, 1)
        add.firstMatch.tap()
        XCTAssertTrue(onHome)
        assertSummary("110 of 2,100 calories")
        app.buttons["Undo"].firstMatch.tap()
        assertSummary("0 of 2,100 calories")
    }

    func testSearchAddReturnsToLoggedAndUndoRemovesIt() {
        let search = app.textFields["foodSearch"]
        search.tap()
        search.typeText("75")
        let add = app.buttons["Add 75 calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(search.exists)
        XCTAssertEqual(search.value as? String, "search / add")
        XCTAssertTrue(onHome)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["Undo"].firstMatch.tap()
        assertSummary("0 of 2,100 calories")
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
        closeSearchDrawer()
        app.buttons["profile"].tap()
        XCTAssertFalse(app.textFields["settingsName"].exists)
        app.buttons["adjustGoal"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap(); goal.typeText("2100")
        app.buttons["Save Changes"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 of 2,100 calories")
        closeSearchDrawer()
        app.buttons["profile"].tap()
        app.buttons["adjustGoal"].tap()
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "2100")
        app.buttons["skipGoal"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 calories")
    }
    func testAdjustGoalCancelKeepsExistingGoal() {
        closeSearchDrawer()
        app.buttons["profile"].tap()
        app.buttons["adjustGoal"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "2100")
        goal.tap(); goal.typeText(XCUIKeyboardKey.delete.rawValue + "5")
        app.buttons["Me Go Back"].tap()
        app.buttons["Done"].tap()
        assertSummary("0 of 2,100 calories")
    }
    func testBundledNutritionFlowsThroughSearchAndQuickAddWithoutRowMacros() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("Banana")
        let details = app.buttons["foodDetails-Banana"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(details.label.contains("Protein"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'P 1 · C 30'")).firstMatch.exists)
        app.buttons["Add Banana"].firstMatch.tap()
        XCTAssertTrue(onHome)
        let carbs = app.descendants(matching: .any)["dailyMacro-totalCarbs"].firstMatch
        XCTAssertTrue(carbs.waitForExistence(timeout: 5))
        XCTAssertTrue(carbs.label.contains("30 g"))
        openAddMode("Quick Add")
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(details.label.contains("Protein"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'P 1 · C 30'")).firstMatch.exists)
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add Banana", "foodDetails-Banana")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Quick Add"].isSelected)
        closeSearchDrawer()
        let total = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '60 g'"), object: carbs)
        XCTAssertEqual(XCTWaiter.wait(for: [total], timeout: 5), .completed)
        openAddMode("Quick Add")
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Edit Banana", "foodDetails-Banana")).firstMatch.tap()
        let fiber = app.textFields["macro-fiber"]
        for _ in 0..<4 where !fiber.isHittable { app.swipeUp() }
        XCTAssertTrue(fiber.waitForExistence(timeout: 3))
        XCTAssertEqual(fiber.value as? String, "3")
        XCTAssertEqual(app.textFields["macro-totalCarbs"].value as? String, "30")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Bundled nutrition editor"; shot.lifetime = .keepAlways; add(shot)
    }

    func testMacroEntryGoalsAndOptionalDisplay() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("Banana")
        let details = app.buttons["foodDetails-Banana"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'P 1 · C 30'")).firstMatch.exists)
        app.buttons["Edit Banana"].firstMatch.tap()
        let protein = app.textFields["macro-protein"]
        for _ in 0..<3 where !protein.isHittable { app.swipeUp() }
        XCTAssertTrue(protein.waitForExistence(timeout: 3))
        XCTAssertEqual(protein.value as? String, "1")
        XCTAssertEqual(app.textFields["macro-totalCarbs"].value as? String, "30")
        XCTAssertEqual(app.textFields["macro-fiber"].value as? String, "3")
        protein.tap(); protein.typeText("1.5")
        app.buttons["Done"].firstMatch.tap()
        let carbs = app.textFields["macro-totalCarbs"]
        for _ in 0..<6 where !carbs.isHittable { app.swipeUp() }
        carbs.tap(); carbs.typeText("24")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(carbs.value as? String, "24")
        let fat = app.textFields["macro-fat"]
        for _ in 0..<6 where !fat.isHittable { app.swipeUp() }
        fat.tap(); fat.typeText("0")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["saveEntry"].isEnabled)
        let editorShot = XCTAttachment(screenshot: app.screenshot()); editorShot.name = "Macros editor"; editorShot.lifetime = .keepAlways; add(editorShot)
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(onHome)
        let proteinTotal = app.descendants(matching: .any)["dailyMacro-protein"].firstMatch
        XCTAssertTrue(proteinTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(proteinTotal.label.contains("1.5"))
        app.buttons["profile"].tap()
        let tracking = app.switches["trackMacros"]
        XCTAssertTrue(tracking.waitForExistence(timeout: 5))
        XCTAssertEqual(tracking.value as? String, "1")
        app.buttons["macroGoals"].tap()
        let goal = app.textFields["goal-protein"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5)); goal.tap(); goal.typeText("120")
        app.buttons["saveMacroGoals"].tap()
        XCTAssertTrue(tracking.waitForExistence(timeout: 5))
        (tracking.switches.firstMatch.exists ? tracking.switches.firstMatch : tracking).tap(); app.buttons["Done"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["dailyMacro-protein"].firstMatch.exists)
        app.buttons["profile"].tap()
        (tracking.switches.firstMatch.exists ? tracking.switches.firstMatch : tracking).tap(); app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(proteinTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(proteinTotal.label.contains("120"))
        let homeShot = XCTAttachment(screenshot: app.screenshot()); homeShot.name = "Macros home"; homeShot.lifetime = .keepAlways; add(homeShot)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).firstMatch
        entry.tap()
        for _ in 0..<3 where !protein.isHittable { app.swipeUp() }
        XCTAssertEqual(protein.value as? String, "1.5")
        for _ in 0..<6 where !fat.isHittable { app.swipeUp() }
        XCTAssertEqual(fat.value as? String, "0")
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
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' "))
        quickAdd("325")
        assertSummary("325 of 2,100 calories")
        app.buttons["Undo"].firstMatch.tap()
        assertSummary("0 of 2,100 calories")
        XCTAssertEqual(entries.count, 0)
        quickAdd("180")
        let entry = entries.firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.swipeLeft()
        XCTAssertTrue(app.buttons["Duplicate"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        assertSummary("0 of 2,100 calories")
        XCTAssertEqual(entries.count, 0)
        app.buttons["Undo"].firstMatch.tap()
        assertSummary("180 of 2,100 calories")
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
    }
    func testLoggedEntryLongPressOffersEditAndDelete() {
        quickAdd("180")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete"].exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 3))
    }
    func testQuickAddLongPressOffersPinAndEditorShowsPinToggle() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("180")
        app.buttons["Edit 180 calories"].firstMatch.tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Pinned snack")
        app.buttons["saveEntry"].tap()

        openAddMode("Quick Add")
        let row = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add Pinned snack", "foodDetails-Pinned snack")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add"].exists)

        // Make the test repeatable if a previous interrupted run left this item pinned.
        if app.buttons["Un-Pin"].exists {
            app.buttons["Un-Pin"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 3))
            row.press(forDuration: 0.8)
        }
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 3))
        app.buttons["Pin"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue((row.value as? String)?.hasPrefix("Pinned") == true)
        let pencil = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Edit Pinned snack", "foodDetails-Pinned snack")).firstMatch
        XCTAssertTrue(pencil.waitForExistence(timeout: 3))
        pencil.tap()
        let pinToggle = app.switches["pinOnQuickAdd"]
        XCTAssertTrue(app.textFields["entryName"].waitForExistence(timeout: 3))
        for _ in 0..<6 where !pinToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(pinToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(pinToggle.value as? String, "1")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Un-Pin"].waitForExistence(timeout: 3))
        app.buttons["Un-Pin"].tap()
    }
    func testEntryRowsSelectTheirValuesForReplacement() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["foodDetails-140 calories"].tap()
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
        app.buttons["foodDetails-140 calories"].tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Cheerios")
        // Serving controls are shown directly in the editor.
        app.buttons["Done"].tap()
        let entryServings = app.textFields["servingCount"]
        entryServings.tap(); entryServings.typeText("2")
        app.buttons["saveEntry"].tap()
        closeSearchDrawer()
        openAddMode("Meals")
        app.buttons["newMeal"].tap()
        app.buttons["newMealToday"].tap()
        app.buttons["Select Cheerios"].tap()
        let mealName = app.textFields["mealName"]; mealName.tap(); mealName.typeText("Breakfast")
        app.buttons["Save Meal"].tap()
        XCTAssertTrue(app.buttons["Add Breakfast"].waitForExistence(timeout: 3))
    }
    func testWeekNavigationAndBarcodeSheetCopy() {
        closeSearchDrawer()
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["Next day"].isEnabled)
        app.buttons["Next day"].tap()
        XCTAssertFalse(app.buttons["Next day"].isEnabled)
        app.buttons["Scan barcode"].tap()
        XCTAssertTrue(app.navigationBars["Barcode Scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Enter calories manually"].exists)
        app.buttons["captureCancel"].tap()
    }
    func testUnavailableCameraHasNoManualEntryAction() {
        app.buttons["Scan barcode"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Make sure you have granted this app access to your camera."].exists)
        XCTAssertFalse(app.textFields["barcodeInput"].exists)
        XCTAssertFalse(app.buttons["Look Up"].exists)
        XCTAssertFalse(app.staticTexts["Product data from Open Food Facts"].exists)
        XCTAssertFalse(app.buttons["Enter calories manually"].exists)
        XCTAssertTrue(app.buttons["captureCancel"].exists)
    }
    func testMealFromScratchAndScaledAdd() {
        closeSearchDrawer()
        openAddMode("Meals"); app.buttons["newMeal"].tap()
        XCTAssertTrue(app.buttons["newMealPhoto"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["newMealVoice"].exists)
        XCTAssertTrue(app.buttons["newMealLink"].exists)
        XCTAssertFalse(app.buttons["newMealToday"].isEnabled)
        app.buttons["newMealManual"].tap()
        let mealName = app.textFields["mealName"]
        XCTAssertTrue(mealName.waitForExistence(timeout: 3)); mealName.tap(); mealName.typeText("Coffee break")
        app.buttons["Add food"].tap()
        app.buttons["Create manual item"].tap()
        let calories = app.textFields["entryCalories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 3)); calories.tap(); calories.typeText(XCUIKeyboardKey.delete.rawValue + "120")
        let name = app.textFields["entryName"]; name.tap(); name.typeText("Coffee")
        app.buttons["saveEntry"].tap()
        // The food picker stays open for adding several foods; Done returns to the meal.
        XCTAssertTrue(app.buttons["mealPickerDone"].waitForExistence(timeout: 4)); app.buttons["mealPickerDone"].tap()
        XCTAssertTrue(app.buttons["Save Meal"].waitForExistence(timeout: 4)); app.buttons["Save Meal"].tap()
        let add = app.buttons["Add Coffee break"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertTrue(app.buttons["Pin"].exists)
        app.buttons["Pin"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue((add.value as? String)?.hasPrefix("Pinned") == true)
        add.tap()
        let mealServings = app.textFields["servingCount"]
        XCTAssertTrue(mealServings.waitForExistence(timeout: 3))
        mealServings.tap(); mealServings.typeText("1.5")
        app.buttons["Add Meal"].tap()
        XCTAssertTrue(app.buttons["cancelAddMode"].waitForExistence(timeout: 4))
        closeSearchDrawer()
        XCTAssertTrue(onHome)
        XCTAssertTrue(app.staticTexts["180"].waitForExistence(timeout: 4))
    }
}

final class ReleaseScreenshotTests: XCTestCase {
    func testCaptureMealScanMarketing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo entry"].waitForExistence(timeout: 10))
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.buttons["aiPhotoPicker"].waitForExistence(timeout: 5))
        app.buttons["aiPhotoPicker"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.39)).tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 10))
        capture(app, "Meal-Scan-Marketing")
    }
    func testCaptureScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
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
    func testMealScanOpensWithoutUpfrontPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo entry"].waitForExistence(timeout: 5))
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.navigationBars["Meal Scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["captureCancel"].exists)
        XCTAssertFalse(app.otherElements["aiUpgradePaywall"].exists)
        app.buttons["captureCancel"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }

    func testMealPhotoSelectionAndRemovalWithoutUpfrontPaywall() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.navigationBars["Meal Scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Meal Scan"].buttons["Cancel"].exists)
        let cancel = app.buttons["captureCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cancel.frame.midY, app.frame.height * 0.75)
        XCTAssertFalse(app.buttons["aiPaywall"].exists)
        XCTAssertFalse(app.switches["aiConsent"].exists)
        app.buttons["aiPhotoPicker"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        // Select a real picker tile so this also works in iPad's iPhone compatibility layout.
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "Import a photo fixture into the simulator before running this test.")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        app.buttons["Voice entry"].tap()
        XCTAssertTrue(app.navigationBars["Speak Food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["aiRecord"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Up to 60 seconds"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Analyze sends this recording'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["aiPaywall"].exists)
        XCTAssertFalse(app.switches["aiConsent"].exists)
        XCTAssertFalse(app.navigationBars["Speak Food"].buttons["Cancel"].exists)
        let cancel = app.buttons["captureCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cancel.frame.midY, app.frame.height * 0.75)
        cancel.tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
}
