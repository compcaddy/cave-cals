import XCTest

final class ECCUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting", "--seed-goal", "2100"]; app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
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
    /// Editors have no Done bar over the keyboard; tapping the navigation title closes it.
    private func closeKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let bar = app.navigationBars.allElementsBoundByIndex.last { $0.isHittable }
        bar?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool == true
    }
    private var onHome: Bool { app.otherElements["calorieSummary"].waitForExistence(timeout: 5) && !app.buttons["Quick Add"].exists }

    private func launchSearchLayoutFixture() {
        app.terminate()
        app.launchArguments += ["--search-layout-fixture"]
        app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
    }

    func testFooterStaysBelowLogThroughKeyboardAndReminderChanges() {
        launchSearchLayoutFixture()
        let search = app.textFields["foodSearch"]
        let footer = app.otherElements["loggingFooter"]
        let list = app.descendants(matching: .any)["foodList"].firstMatch
        let initialBottom = search.frame.maxY
        func assertFooterPosition() {
            XCTAssertEqual(search.frame.maxY, initialBottom, accuracy: 2)
            XCTAssertLessThanOrEqual(list.frame.maxY, footer.frame.minY + 1)
            // iPad compatibility mode has extra space outside the app's phone-sized viewport.
            if app.frame.width < 600 {
                XCTAssertLessThan(app.frame.maxY - search.frame.maxY, 65)
            }
        }
        XCTAssertTrue(app.buttons["finishDay"].waitForExistence(timeout: 5))
        assertFooterPosition()
        list.swipeUp()
        assertFooterPosition()
        search.tap(); search.typeText("bo")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(search.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(list.frame.maxY, footer.frame.minY + 1)
        closeSearchDrawer()
        assertFooterPosition()
        app.buttons["dismissFinishDay"].tap()
        assertFooterPosition()
        app.buttons["profile"].tap()
        XCTAssertTrue(app.navigationBars["About You"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(URL(string: "\(testAppURLScheme)://home")!)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        assertFooterPosition()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Footer below scrolling log"; shot.lifetime = .keepAlways; add(shot)
    }

    func testFooterReturnsToBottomAfterKeyboardLeaves() {
        let search = app.textFields["foodSearch"]
        let footer = app.otherElements["loggingFooter"]
        let keyboard = app.keyboards.firstMatch
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).firstMatch
        let initialBottom = footer.frame.maxY
        // A search add returns Home with the field (and keyboard) still up.
        func keyboardUpOnHome(_ calories: String) {
            if !hasKeyboardFocus(search) { search.tap() }
            search.typeText(calories)
            let add = app.buttons["Add \(calories) calories"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 3)); add.tap()
            XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(search.frame.maxY, keyboard.frame.minY)
        }
        func assertFooterAtBottom(_ step: String) {
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), step)
            let deadline = Date().addingTimeInterval(3)
            while footer.frame.maxY < initialBottom - 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            XCTAssertEqual(footer.frame.maxY, initialBottom, accuracy: 2, step)
        }
        // The editor opens over Home with its own keyboard; swiping it away leaves no keyboard.
        keyboardUpOnHome("75")
        entry.tap()
        XCTAssertTrue(app.textFields["entryCalories"].waitForExistence(timeout: 3))
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.11))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        assertFooterAtBottom("editor swiped away")
        // Home still makes room for the keyboard the next time search is used.
        keyboardUpOnHome("50")
        entry.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3)); app.buttons["Cancel"].tap()
        assertFooterAtBottom("editor canceled")
        keyboardUpOnHome("25")
        app.buttons["cancelAddMode"].tap()
        assertFooterAtBottom("search canceled")
    }

    func testChangedSearchStartsAtTopWithHistoryBeforeRemoteResults() {
        launchSearchLayoutFixture()
        let search = app.textFields["foodSearch"]
        let list = app.descendants(matching: .any)["foodList"].firstMatch
        let history = app.buttons["foodDetails-Zesty testbowl"]
        let meal = app.buttons["foodDetails-Testbowl meal"]
        let remote = app.buttons["foodDetails-A Testbowl option 01"]
        func assertHistoryFirst() {
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            XCTAssertTrue(history.isHittable)
            XCTAssertTrue(app.staticTexts["Results"].isHittable)
            XCTAssertTrue(remote.waitForExistence(timeout: 5))
            XCTAssertLessThan(history.frame.minY, meal.frame.minY)
            XCTAssertLessThan(meal.frame.minY, remote.frame.minY)
        }
        search.tap(); search.typeText("testbo")
        assertHistoryFirst()
        list.swipeUp(); list.swipeUp()
        XCTAssertFalse(history.isHittable)
        // Both queries match the same row IDs; changing the text must still reset the list.
        search.tap(); search.typeText("wl")
        XCTAssertEqual(search.value as? String, "testbowl")
        assertHistoryFirst()
        list.swipeUp(); list.swipeUp()
        app.buttons["clearSearch"].tap()
        search.tap(); search.typeText("testbo")
        assertHistoryFirst()
        // Returning to the diary still reveals the new entry, despite the list identity change.
        app.buttons["Add A Testbowl option 01"].tap()
        XCTAssertTrue(onHome)
        let logged = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-' AND label BEGINSWITH 'A Testbowl option 01,'")).firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 5))
        XCTAssertTrue(logged.isHittable)
    }

    func testDoneEatingSwapsFooterUntilReopened() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("1900")
        let add = app.buttons["Add 1,900 calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        if app.buttons["cancelAddMode"].exists { app.buttons["cancelAddMode"].tap() }
        // 90% of the 2,100 goal offers the button at any hour.
        let finish = app.buttons["finishDay"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertEqual(finish.label, "Done eating for today")
        finish.tap()
        let reopen = app.buttons["reopenDay"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        XCTAssertFalse(search.exists)
        XCTAssertFalse(app.buttons["Voice entry"].exists)
        XCTAssertFalse(finish.exists)
        reopen.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        app.buttons["dismissFinishDay"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: finish)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(search.exists)
    }
    private func launchWithReviewPrompt() {
        app.terminate(); app.launchArguments += ["--review-prompt"]; app.launch()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 10))
    }
    /// The fifth food of a day asks how it's going, but not while the field is ready for the next food.
    func testFifthFoodOfTheDayAsksHowItsGoingAndNoOffersFeedback() {
        launchWithReviewPrompt()
        let search = app.textFields["foodSearch"]
        let question = app.alerts["Cave Cals good?"]
        for _ in 1...5 {
            if !app.keyboards.firstMatch.exists { search.tap() }
            search.typeText("100")
            let add = app.buttons["Add 100 calories"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 3))
            add.tap()
            XCTAssertTrue(onHome)
        }
        assertSummary("500 of 2,100 calories")
        XCTAssertFalse(question.waitForExistence(timeout: 2.5))
        app.buttons["cancelAddMode"].tap()
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.buttons["Not really"].tap()
        let feedback = app.alerts["Help fix cave?"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(feedback.buttons["Send Feedback"].exists)
        feedback.buttons["Not now"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: feedback)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(onHome)
    }
    func testDoneEatingAsksHowItsGoingAndYesClosesTheQuestion() {
        launchWithReviewPrompt()
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("1900")
        let add = app.buttons["Add 1,900 calories"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        if app.buttons["cancelAddMode"].exists { app.buttons["cancelAddMode"].tap() }
        // One food isn't enough on its own.
        let question = app.alerts["Cave Cals good?"]
        XCTAssertFalse(question.waitForExistence(timeout: 2.5))
        let finish = app.buttons["finishDay"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.buttons["Yes! Me like"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: question)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(app.alerts["Help fix cave?"].exists)
    }
    func testWidgetSearchLinkFocusesSearchAndBackgroundLinkReturnsHome() {
        app.buttons["profile"].tap()
        XCTAssertTrue(app.navigationBars["About You"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(URL(string: "\(testAppURLScheme)://log/add")!)
        XCTAssertTrue(app.buttons["Quick Add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["About You"].exists)
        app.textFields["foodSearch"].typeText("Banana")
        XCUIDevice.shared.system.open(URL(string: "\(testAppURLScheme)://home")!)
        XCTAssertTrue(app.otherElements["calorieSummary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["Quick Add"].exists)
    }

    func testColdWidgetSearchLinkFocusesSearch() {
        app.terminate()
        app.open(URL(string: "\(testAppURLScheme)://log/add")!)
        XCTAssertTrue(app.buttons["Quick Add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textFields["foodSearch"].typeText("123")
        XCTAssertTrue(app.buttons["Add 123 calories"].firstMatch.waitForExistence(timeout: 5))
    }

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
        // Home shows the new total and row, with the field still ready for the next food.
        XCTAssertEqual(search.value as? String, "search food or enter cals")
        XCTAssertTrue(onHome)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
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
    func testAddModeTodayListRepeatsOrEditsWithoutChangingTheOriginal() throws {
        // The Today pill is hidden for now (October 7, 2026).
        throw XCTSkip("Add mode's Today pill is hidden")
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
        let parts = calories.split(separator: " ")
        let label = parts.count == 2 ? "Add \"\(parts[0])\" · \(parts[1]) calories" : "Add \(calories) calories"
        let add = app.buttons[label].firstMatch
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
        XCTAssertTrue(onHome)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        // The next food can be typed straight away, without tapping search again.
        search.typeText("pizza 300")
        let named = app.buttons["Add \"pizza\" · 300 calories"].firstMatch
        XCTAssertTrue(named.waitForExistence(timeout: 3))
        named.tap()
        XCTAssertTrue(onHome)
        assertSummary("375 of 2,100 calories")
        XCTAssertTrue(app.buttons["cancelAddMode"].exists)
        app.buttons["cancelAddMode"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(onHome)
        XCTAssertEqual(search.value as? String, "search / add")
        app.buttons["Undo"].firstMatch.tap()
        assertSummary("75 of 2,100 calories")
    }
    func testEmptyTodayOffersQuickAddOnHome() {
        let header = app.descendants(matching: .any)["homeQuickAddHeader"]
        XCTAssertFalse(header.exists)
        // Backfilling yesterday leaves today's picks available.
        app.buttons["Previous day"].tap()
        quickAdd("Banana 110"); quickAdd("Yogurt 130")
        app.buttons["Next day"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        func plus(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add \(name)", "foodDetails-\(name)")).firstMatch
        }
        XCTAssertTrue(plus("Banana").waitForExistence(timeout: 3))
        plus("Banana").tap()
        assertSummary("110 of 2,100 calories")
        XCTAssertTrue(onHome)
        XCTAssertTrue(app.staticTexts["homeLogHeader"].waitForExistence(timeout: 3))
        // The added pick leaves after its confirmation; the others stay for a second add.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: plus("Banana"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(header.exists)
        plus("Yogurt").tap()
        assertSummary("240 of 2,100 calories")
        // Using search retires the picks for the rest of the day.
        app.textFields["foodSearch"].tap()
        closeSearchDrawer()
        XCTAssertFalse(header.waitForExistence(timeout: 2))
    }

    func testSkipGoalThenAddGoalInSettings() {
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        let skip = app.buttons["skipGoal"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5)); skip.tap()
        XCTAssertTrue(app.alerts.buttons["Yes, skip plan"].waitForExistence(timeout: 5))
        app.alerts.buttons["Yes, skip plan"].tap()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.buttons["skipOnboardingPaywall"].waitForExistence(timeout: 5))
        app.buttons["skipOnboardingPaywall"].tap()
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

    func testResetSavedNutritionRequiresConfirmationAndKeepsDailyLog() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("Banana")
        let edit = app.buttons["Edit Banana"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let calories = app.textFields["caloriesPerServing"]
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        calories.tap(); calories.typeText("250")
        closeKeyboard()
        let saveDefault = app.switches["saveCommonFoodDefault"]
        for _ in 0..<4 where !saveDefault.isHittable { app.swipeUp() }
        XCTAssertTrue(saveDefault.waitForExistence(timeout: 3))
        (saveDefault.switches.firstMatch.exists ? saveDefault.switches.firstMatch : saveDefault).tap()
        app.buttons["saveEntry"].tap()
        assertSummary("250 of 2,100 calories")
        closeSearchDrawer()
        app.buttons["appSettings"].tap()
        let reset = app.buttons["resetSavedNutrition"]
        for _ in 0..<6 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        XCTAssertTrue(reset.isEnabled); reset.tap()
        let confirmation = app.alerts["Reset saved nutrition?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(confirmation.staticTexts.containing(NSPredicate(format: "label CONTAINS 'daily logs'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Reset saved nutrition confirmation"; shot.lifetime = .keepAlways; add(shot)
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(reset.isEnabled)
        reset.tap(); confirmation.buttons["Reset"].tap()
        XCTAssertFalse(reset.isEnabled)
        XCTAssertTrue(app.staticTexts["Saved nutrition reset. Your daily logs are unchanged."].exists)
        app.buttons["Done"].tap()
        assertSummary("250 of 2,100 calories")
        openAddMode("Quick Add")
        let add = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add Banana", "foodDetails-Banana")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        closeSearchDrawer()
        assertSummary("360 of 2,100 calories") // Original 250 is intact; future add uses catalog's 110.
    }

    /// Tapping Protein on Home lists the day's foods: blank where a food has no protein (the "+"), editable in place,
    /// with AI estimates for the blanks.
    func testMacroBreakdownFillsMissingAmounts() throws {
        app.terminate()
        app.launchArguments += ["--macro-estimate-fixture"]
        app.launch()
        let search = app.textFields["foodSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Banana")
        let add = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Add Banana", "foodDetails-Banana")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        closeSearchDrawer()
        quickAdd("140")
        let protein = app.descendants(matching: .any)["dailyMacro-protein"].firstMatch
        XCTAssertTrue(protein.waitForExistence(timeout: 5))
        XCTAssertTrue(protein.label.hasPrefix("Protein 1+ g"), protein.label)
        protein.tap()
        // Only foods with blanks offer an estimate; the top button fills them all.
        XCTAssertTrue(app.buttons["macroEstimateAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["macroEstimate-1"].exists)
        XCTAssertFalse(app.buttons["macroEstimate-0"].exists)
        let blank = app.textFields["macroCell-protein-1"]
        XCTAssertEqual(blank.value as? String ?? "", "")
        blank.tap(); blank.typeText("20")
        // A tap selects the whole value, so typing replaces it.
        let banana = app.textFields["macroCell-protein-0"]
        XCTAssertEqual(banana.value as? String, "1")
        banana.tap(); banana.typeText("3")
        XCTAssertEqual(banana.value as? String, "3")
        // The total follows what's typed, before it's saved.
        XCTAssertEqual(app.staticTexts["macroBreakdownTotal-protein"].label, "23")
        // The estimate fills only the blanks; the typed 20 g of protein stays.
        app.buttons["macroEstimate-1"].tap()
        let carbs = app.textFields["macroCell-totalCarbs-1"]
        XCTAssertTrue(NSPredicate(format: "value == '12'").evaluate(with: carbs) || XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == '12'"), evaluatedWith: carbs)], timeout: 5) == .completed)
        XCTAssertEqual(app.textFields["macroCell-fat-1"].value as? String, "2")
        XCTAssertEqual(blank.value as? String, "20")
        XCTAssertTrue(app.buttons["macroEstimate-1"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["macroEstimateAll"].exists)
        app.buttons["macroBreakdownDone"].tap()
        XCTAssertTrue(protein.waitForExistence(timeout: 5))
        XCTAssertTrue(protein.label.hasPrefix("Protein 23 g"), protein.label)
        let carbsTotal = app.descendants(matching: .any)["dailyMacro-totalCarbs"].firstMatch
        XCTAssertTrue(carbsTotal.label.hasPrefix("Carbs ≈"), carbsTotal.label)
    }

    /// Macros typed for one food fill the same food's other entries, even a box just tapped.
    func testMacroBreakdownSharesMacrosWithTheSameFood() {
        quickAdd("pizza 300")
        quickAdd("pizza 300")
        let protein = app.descendants(matching: .any)["dailyMacro-protein"].firstMatch
        XCTAssertTrue(protein.waitForExistence(timeout: 5))
        protein.tap()
        let first = app.textFields["macroCell-protein-0"], second = app.textFields["macroCell-protein-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap(); first.typeText("12")
        second.tap()
        XCTAssertTrue(app.staticTexts["macroBreakdownNote"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["macroBreakdownNote"].label.hasPrefix("Also filled 1 other"), app.staticTexts["macroBreakdownNote"].label)
        XCTAssertEqual(second.value as? String, "12")
        app.buttons["macroBreakdownDone"].tap()
        XCTAssertTrue(protein.waitForExistence(timeout: 5))
        XCTAssertTrue(protein.label.hasPrefix("Protein 24 g"), protein.label)
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
        closeKeyboard()
        let carbs = app.textFields["macro-totalCarbs"]
        for _ in 0..<6 where !carbs.isHittable { app.swipeUp() }
        carbs.tap(); carbs.typeText("24")
        closeKeyboard()
        XCTAssertEqual(carbs.value as? String, "24")
        let fat = app.textFields["macro-fat"]
        for _ in 0..<6 where !fat.isHittable { app.swipeUp() }
        fat.tap(); fat.typeText("0")
        closeKeyboard()
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
        // Add mode's search Cancel is also on screen; close the editor.
        app.navigationBars.buttons["Cancel"].firstMatch.tap()

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
    func testEditorKeyboardClosesOnTapOutsideAndRowsKeepIt() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["foodDetails-140 calories"].tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Toast")
        XCTAssertFalse(app.toolbars.buttons["Done"].exists)
        // A row's label opens its field without closing the keyboard.
        app.staticTexts["cals / serving"].tap()
        let perServing = app.textFields["caloriesPerServing"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: perServing)
        waitForExpectations(timeout: 5)
        // Buttons in a field's pop-up list still work: a servings preset fills the field.
        let servings = app.textFields["servingCount"]
        servings.tap()
        let preset = app.buttons["Use 2 servings"]
        XCTAssertTrue(preset.waitForExistence(timeout: 3)); preset.tap()
        XCTAssertEqual(servings.value as? String, "2")
        // Anywhere else closes it.
        name.tap()
        XCTAssertTrue(hasKeyboardFocus(name))
        closeKeyboard()
        XCTAssertFalse(hasKeyboardFocus(name))
        XCTAssertEqual(name.value as? String, "Toast")
    }
    func testNamedEntryServingEditorAndSavedMeal() {
        let search = app.textFields["foodSearch"]
        search.tap(); search.typeText("140")
        app.buttons["foodDetails-140 calories"].tap()
        let name = app.textFields["entryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Cheerios")
        // Serving controls are shown directly in the editor.
        closeKeyboard()
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
    func testRecipeImportChoicesAndServingsSplitAMeal() {
        closeSearchDrawer()
        openAddMode("Meals"); app.buttons["newMeal"].tap()
        XCTAssertTrue(app.buttons["newMealLink"].waitForExistence(timeout: 3))
        app.buttons["newMealLink"].tap()
        XCTAssertTrue(app.buttons["recipeFromLink"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["recipeFromPhoto"].exists)
        XCTAssertTrue(app.buttons["recipeFromClipboard"].exists)
        app.buttons["recipeFromClipboard"].tap()
        let recipeText = app.textViews["recipeText"]
        XCTAssertTrue(recipeText.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["importMeal"].isEnabled)
        recipeText.tap(); recipeText.typeText("2 lb ground beef, 2 cans beans, 1 onion. Serves 6.")
        XCTAssertTrue(app.buttons["importMeal"].isEnabled)
        app.navigationBars["Paste Recipe"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["newMeal"].waitForExistence(timeout: 4)); app.buttons["newMeal"].tap()
        XCTAssertTrue(app.buttons["newMealManual"].waitForExistence(timeout: 3)); app.buttons["newMealManual"].tap()
        let mealName = app.textFields["mealName"]
        XCTAssertTrue(mealName.waitForExistence(timeout: 3)); mealName.tap(); mealName.typeText("Family chili")
        app.buttons["Add food"].tap()
        app.buttons["Create manual item"].tap()
        let calories = app.textFields["entryCalories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 3)); calories.tap(); calories.typeText(XCUIKeyboardKey.delete.rawValue + "1400")
        let name = app.textFields["entryName"]; name.tap(); name.typeText("Chili pot")
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.buttons["mealPickerDone"].waitForExistence(timeout: 4)); app.buttons["mealPickerDone"].tap()
        let servings = app.textFields["recipeServings"]
        XCTAssertTrue(servings.waitForExistence(timeout: 4))
        servings.tap(); servings.typeText("7")
        XCTAssertTrue(app.staticTexts["200 cal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1,400 cal"].exists)
        app.buttons["Save Meal"].tap()
        let add = app.buttons["Add Family chili"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.staticTexts["Recipe makes 7 servings."].waitForExistence(timeout: 3))
        app.buttons["Add Meal"].tap()
        XCTAssertTrue(app.buttons["cancelAddMode"].waitForExistence(timeout: 4))
        closeSearchDrawer()
        XCTAssertTrue(app.staticTexts["200"].waitForExistence(timeout: 4))
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
