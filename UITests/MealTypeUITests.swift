import XCTest

/// Meal types: Settings, Home's meal sections, Move to, and picking a meal while adding asks for one.
final class MealTypeUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ mealTypes: String? = nil) {
        app.launchArguments = ["--uitesting", "--seed-goal", "2100"] + (mealTypes.map { ["--meal-types", $0] } ?? [])
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
    }

    /// The meal the default times give food logged right now (nil from 4 to 5 AM).
    private var mealNow: String? {
        let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
        switch (time.hour ?? 0) * 60 + (time.minute ?? 0) {
        case 300..<540: return "breakfast"
        case 540..<660: return "morningSnack"
        case 660..<840: return "lunch"
        case 840..<960: return "afternoonSnack"
        case 960..<1200: return "dinner"
        case 240..<300: return nil
        default: return "eveningSnack"
        }
    }

    /// Types "pizza 300" and taps its +, which logs it (or, when adding asks for a meal, opens the editor).
    private func tapAddForTypedFood(_ text: String = "pizza 300") {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText(text)
        let parts = text.split(separator: " ")
        let add = app.buttons["Add \"\(parts[0])\" · \(parts[1]) calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
    }

    private func returnHome() {
        if app.buttons["clearSearch"].exists { app.buttons["clearSearch"].tap() }
        if app.buttons["cancelAddMode"].exists { app.buttons["cancelAddMode"].tap() }
        if app.keyboards.firstMatch.exists { app.otherElements["calorieSummary"].tap() }
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
    }

    /// Meal headers combine their label and calories, so look them up whatever element type that makes.
    private func section(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mealSection-\(id)").firstMatch
    }

    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        guard (toggle.value as? String == "1") != on else { return }
        toggle.tap()
        if (toggle.value as? String == "1") != on {
            // Some iOS versions only flip a Form switch when the switch itself is tapped.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0")
    }

    func testSettingsTurnOnMealTypesAndEditTheList() {
        launch()
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'mealSection-'")).firstMatch.exists)
        app.buttons["appSettings"].tap()
        let track = app.switches["trackMealTypes"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // Settings is a long list; rows further down load as it scrolls.
        for _ in 0..<8 where !track.exists || !track.isHittable { app.swipeUp() }
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["mealTypesByTime"].exists, "Only offered once meal types are on")
        setSwitch(track, on: true)
        let byTime = app.switches["mealTypesByTime"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 3))
        XCTAssertEqual(byTime.value as? String, "1", "Turning meal types on starts with meals set by time of day")

        let edit = app.buttons["editMealTypes"]
        for _ in 0..<4 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.navigationBars["Meal Types"].waitForExistence(timeout: 5))
        for id in ["breakfast", "morningSnack", "lunch", "afternoonSnack", "dinner", "dessert", "eveningSnack"] {
            XCTAssertTrue(app.buttons["mealType-\(id)"].exists, id)
        }
        XCTAssertTrue(app.staticTexts["mealTimeGaps"].label.contains("No meal"), "The default times leave 4 to 5 AM open")

        // A new type starts in the open part of the day, so it can be saved right away.
        app.buttons["addMealType"].tap()
        let name = app.textFields["mealTypeName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveMealType"].isEnabled, "A name is required")
        name.tap(); name.typeText("Lunch")
        XCTAssertFalse(app.buttons["saveMealType"].isEnabled, "Names can't repeat")
        name.typeText(" Two")
        XCTAssertTrue(app.buttons["saveMealType"].isEnabled)
        app.buttons["saveMealType"].tap()
        XCTAssertTrue(app.navigationBars["Meal Types"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lunch Two"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["mealTimeGaps"].label.contains("Every time of day"))

        // Moving Lunch's end into the afternoon snack offers to shorten the snack, saved together.
        app.buttons["mealType-lunch"].tap()
        let end = app.datePickers["mealTypeEnd"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        let hours = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hours.waitForExistence(timeout: 3))
        hours.adjust(toPickerWheelValue: "3")
        app.navigationBars["Edit Meal Type"].tap()
        let shorten = app.buttons["shortenMealType"]
        XCTAssertTrue(shorten.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["saveMealType"].isEnabled, "Meal times can't overlap")
        shorten.tap()
        XCTAssertTrue(app.buttons["saveMealType"].isEnabled)
        app.buttons["saveMealType"].tap()
        XCTAssertTrue(app.navigationBars["Meal Types"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mealType-afternoonSnack"].label.contains("3:00"), app.buttons["mealType-afternoonSnack"].label)
        XCTAssertTrue(app.buttons["mealType-lunch"].label.contains("3:00"), app.buttons["mealType-lunch"].label)

        // Deleting a type no food uses takes it off the list.
        app.buttons["mealType-dessert"].tap()
        let delete = app.buttons["deleteMealType"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        for _ in 0..<3 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap()
        XCTAssertTrue(app.navigationBars["Meal Types"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mealType-dessert"].waitForNonExistence(timeout: 3))

        // Turning "by time of day" off makes adding ask.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        setSwitch(app.switches["mealTypesByTime"], on: false)
        app.buttons["Done"].firstMatch.tap()
        tapAddForTypedFood()
        XCTAssertTrue(app.navigationBars["Add Calories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mealChip-lunch"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mealChip-dessert"].exists, "Deleted types aren't offered")
    }

    func testTimeOfDaySortsHomeByMealAndMoveToChangesIt() {
        launch("time")
        tapAddForTypedFood()
        returnHome()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Add Calories"].exists, "By time of day, adding stays one tap")
        if let meal = mealNow {
            XCTAssertTrue(section(meal).waitForExistence(timeout: 3))
            XCTAssertFalse(app.staticTexts["homeLogHeader"].exists, "Meal labels replace the Today label")
        } else {
            XCTAssertTrue(app.staticTexts["homeLogHeader"].waitForExistence(timeout: 3), "Outside every meal's time")
        }

        entry.press(forDuration: 0.8)
        let move = app.buttons["Move to"]
        XCTAssertTrue(move.waitForExistence(timeout: 3)); move.tap()
        let dessert = app.buttons["Dessert"]
        XCTAssertTrue(dessert.waitForExistence(timeout: 3)); dessert.tap()
        let header = section("dessert")
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertEqual(header.label, "Dessert, 300 calories")

        // Editing shows the meal row, and None takes the food out of every meal.
        entry.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        let row = app.buttons["mealTypeRow"]
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        XCTAssertEqual(row.value as? String, "Dessert")
        row.tap()
        let none = app.buttons["mealChip-none"]
        XCTAssertTrue(none.waitForExistence(timeout: 3)); none.tap()
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.staticTexts["homeLogHeader"].waitForExistence(timeout: 5), "No meals that day: one plain list")
    }

    func testReviewScanSharesOneMealChoiceForItsFoods() {
        app.launchArguments = ["--uitesting", "--seed-goal", "2100", "--meal-types", "ask", "--review-scan-fixture"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Scan"].waitForExistence(timeout: 5))
        let lunch = app.buttons["mealChip-lunch"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 3))
        lunch.tap()
        XCTAssertTrue(lunch.isSelected)
        app.buttons["aiAdd"].tap()
        let header = section("lunch")
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Lunch, 370 calories")
    }

    func testReviewScanSetByTimeOfDayAsksNothing() {
        app.launchArguments = ["--uitesting", "--seed-goal", "2100", "--meal-types", "time", "--review-scan-fixture"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
        app.buttons["Photo entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mealChip-lunch"].exists)
        app.buttons["aiAdd"].tap()
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
        if let meal = mealNow { XCTAssertTrue(section(meal).waitForExistence(timeout: 5)) }
    }

    func testAskingOpensTheEditorWithTheMealChoice() {
        launch("ask")
        tapAddForTypedFood()
        XCTAssertTrue(app.navigationBars["Add Calories"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Everything else is filled in, so the keyboard stays down")
        let dinner = app.buttons["mealChip-dinner"]
        XCTAssertTrue(dinner.waitForExistence(timeout: 3))
        XCTAssertTrue(dinner.isHittable, "The meal choice scrolls into view")
        XCTAssertFalse(app.buttons["mealChip-none"].exists)
        XCTAssertEqual(app.buttons["mealTypeRow"].value as? String, "None")
        dinner.tap()
        XCTAssertTrue(dinner.isSelected)
        XCTAssertEqual(app.buttons["mealTypeRow"].value as? String, "Dinner")
        app.buttons["saveEntry"].tap()
        returnHome()
        XCTAssertTrue(section("dinner").waitForExistence(timeout: 5))

        // Duplicate asks too, with the copy filled in.
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).firstMatch
        entry.swipeLeft()
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 3)); duplicate.tap()
        XCTAssertTrue(app.navigationBars["Add Calories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mealChip-breakfast"].waitForExistence(timeout: 3))
        app.buttons["mealChip-breakfast"].tap()
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(section("breakfast").waitForExistence(timeout: 5))
        XCTAssertTrue(section("dinner").exists)
        let sections = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'mealSection-'"))
        XCTAssertEqual(sections.element(boundBy: 0).identifier, "mealSection-breakfast", "Meals follow the list's order")
    }
}
