import XCTest

final class ECCUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.textFields["profileGoal"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["profileName"].exists)
        XCTAssertTrue(app.images["Caveman logo"].exists)
        XCTAssertTrue(app.buttons["Me Start Now"].isEnabled)
        app.buttons["Me Start Now"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }
    func quickAdd(_ calories: String) {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText(calories)
        let add = app.buttons["Add \(calories) calories"]
        XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
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
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.textFields["settingsName"].exists)
        app.buttons["adjustGoal"].tap()
        let goal = app.textFields["profileGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap(); goal.typeText("2100")
        app.buttons["Me Start Now"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 of 2,100 calories")
        app.buttons["Settings"].tap()
        app.buttons["adjustGoal"].tap()
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "2100")
        app.buttons["skipGoal"].tap()
        app.buttons["Done"].tap()
        assertSummary("325 calories")
    }
    func testAdjustGoalCancelKeepsExistingGoal() {
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
        XCTAssertTrue(app.staticTexts["Nothing logged yet"].exists)
        quickAdd("180")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.swipeLeft(); app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Nothing logged yet"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["180 calories"].waitForExistence(timeout: 3))
    }
    func testNamedEntryServingEditorAndSavedMeal() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["Edit 140 calories"].tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Cheerios")
        app.staticTexts["More Details"].tap()
        app.buttons["Increase servings"].tap()
        app.buttons["saveEntry"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Meals"].tap()
        app.buttons["Create from Today’s Entries"].tap()
        app.buttons["Select Cheerios"].tap()
        let mealName = app.textFields["mealName"]; mealName.tap(); mealName.typeText("Breakfast")
        app.buttons["Save Meal"].tap()
        XCTAssertTrue(app.buttons["Add Breakfast"].waitForExistence(timeout: 3))
    }
    func testWeekNavigationAndManualBarcodeFallback() {
        app.buttons["Previous week"].tap()
        XCTAssertTrue(app.buttons["Next week"].isEnabled)
        app.buttons["Next week"].tap()
        XCTAssertFalse(app.buttons["Next week"].isEnabled)
        app.buttons["Scan barcode"].tap()
        let manual = app.buttons["Enter calories manually"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        XCTAssertTrue(app.textFields["entryCalories"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }
    func testUnknownBarcodeCanBeSavedAndReusedLocally() {
        app.buttons["Scan barcode"].tap()
        let barcode = app.textFields["barcodeInput"]
        XCTAssertTrue(barcode.waitForExistence(timeout: 4)); barcode.tap(); barcode.typeText("12345678")
        app.buttons["Enter calories manually"].tap()
        let calories = app.textFields["entryCalories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 3)); calories.tap(); calories.typeText(XCUIKeyboardKey.delete.rawValue + "220")
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 4))
        app.buttons["Scan barcode"].tap()
        XCTAssertTrue(barcode.waitForExistence(timeout: 4)); barcode.tap(); barcode.typeText("12345678")
        app.buttons["Look Up"].tap()
        XCTAssertTrue(app.buttons["Add 220 calories"].waitForExistence(timeout: 4))
        app.buttons["Add 220 calories"].tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.otherElements["calorieSummary"].label, "440 of 2,100 calories")
    }
    func testMealFromScratchAndScaledAdd() {
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
        app.buttons["Increase servings"].tap(); app.buttons["Add Meal"].tap()
        let back = app.navigationBars["Meals"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 4)); back.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["180"].waitForExistence(timeout: 4))
    }
}
