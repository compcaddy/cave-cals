import XCTest
import SwiftData
@testable import CaveCals

@MainActor final class ECCTests: XCTestCase {
    func testRegularLogAllowanceCountPersistsAndExcludesScans() throws {
        let suite = "scan-allowance-tests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(container: container, publishesWidget: false, preferences: preferences)
        var photo = EntryDraft(calories: 80); photo.source = "aiPhoto"
        var voice = EntryDraft(calories: 90); voice.source = "aiVoice"
        XCTAssertTrue(store.add([photo, voice]))
        XCTAssertEqual(store.regularLogCount, 0)
        XCTAssertTrue(store.add([EntryDraft(calories: 100)]))
        XCTAssertEqual(store.regularLogCount, 1)
        store.undo()
        XCTAssertEqual(store.regularLogCount, 1)
        XCTAssertTrue(store.add((0..<98).map { _ in EntryDraft(calories: 100) }))
        XCTAssertEqual(store.regularLogCount, 99)
        store.refresh()
        XCTAssertEqual(store.regularLogCount, 99)
        let reopened = AppStore(container: container, publishesWidget: false, preferences: preferences)
        XCTAssertEqual(reopened.regularLogCount, 99)
        XCTAssertTrue(reopened.add([EntryDraft(calories: 100)]))
        XCTAssertEqual(reopened.regularLogCount, 100)
        XCTAssertTrue(reopened.add([EntryDraft(calories: 100)]))
        XCTAssertEqual(reopened.regularLogCount, 100)
    }

    func testFreeScanAccountIsNotAPaidMembership() throws {
        let json = #"{"accountId":"00000000-0000-4000-8000-000000000001","active":false,"canScan":true,"freeScansRemaining":10,"scansUsed":0,"regularLogCount":0,"productIds":[],"dailyLimit":30,"monthlyLimit":300}"#
        let account = try JSONDecoder().decode(AIAccount.self, from: Data(json.utf8))
        XCTAssertFalse(account.active)
        XCTAssertTrue(account.canScan)
        XCTAssertEqual(account.freeScansRemaining, 10)
    }

    func testShortcutMenuRoutesAndPreservesQuickCaloriesOnColdStart() {
        let router = LoggingActionRouter()
        for (choice, action) in [(CalorieLoggingChoice.voice, LoggingAction.voice), (.meal, .image), (.barcode, .barcode)] {
            choice.open(using: router)
            XCTAssertEqual(router.consume(), action)
            XCTAssertNil(router.pending)
        }
        CalorieLoggingChoice.quickCalories.open(using: router)
        XCTAssertEqual(router.pending?.action, .add)
        XCTAssertEqual(router.pending?.quickCalories, true)
        let firstID = router.pending?.id
        CalorieLoggingChoice.quickCalories.open(using: router)
        XCTAssertNotEqual(router.pending?.id, firstID)
        XCTAssertEqual(router.consume(), .add)
        XCTAssertNil(router.pending)
        router.open(.add)
        XCTAssertEqual(router.pending?.quickCalories, false)
    }

    func makeStore() throws -> AppStore { try Persistence.make(inMemory: true) }
    func yesterday() -> Date { Calendar.current.date(byAdding: .day, value: -1, to: Date())! }

    func testOnboardingWithoutNameOrGoalAllowsLogging() throws {
        let store = try makeStore()
        XCTAssertTrue(store.saveGoal(nil))
        XCTAssertNotNil(store.profile)
        XCTAssertEqual(store.profile?.name, "")
        XCTAssertNil(store.profile?.dailyGoal)
        XCTAssertNil(store.goal(Date()))
        XCTAssertTrue(store.add([EntryDraft(calories: 325)]))
        XCTAssertEqual(store.total(Date()), 325)
        XCTAssertNil(store.goal(Date()))
        XCTAssertFalse(store.saveGoal(0))
        XCTAssertFalse(store.saveGoal(.nan))
        XCTAssertFalse(store.saveGoal(-200))
        XCTAssertNil(store.goal(Date()))
    }
    func testAddingGoalPreservesEarlierGoalFreeDays() throws {
        let store = try makeStore()
        store.saveGoal(nil)
        store.add([EntryDraft(calories: 120, timestamp: yesterday())])
        XCTAssertTrue(store.saveGoal(2100))
        XCTAssertEqual(store.goal(Date()), 2100)
        XCTAssertNil(store.goal(yesterday()))
        XCTAssertNil(store.goal(Calendar.current.date(byAdding: .day, value: -7, to: Date())!))
    }
    func testRemovingGoalPreservesHistoricalTargetsAndLegacyProfile() throws {
        let store = try makeStore()
        store.context.insert(UserProfile(name: "Existing user", goal: 2100)); store.commit()
        store.saveGoal(2100)
        store.add([EntryDraft(calories: 120, timestamp: yesterday())])
        XCTAssertTrue(store.saveGoal(nil))
        XCTAssertNil(store.goal(Date()))
        XCTAssertEqual(store.goal(yesterday()), 2100)
        XCTAssertEqual(store.total(yesterday()), 120)
        XCTAssertEqual(store.profile?.name, "Existing user")
    }
    func testDailyGoalFourDigitLimit() throws {
        let store = try makeStore()
        XCTAssertTrue(store.saveGoal(9999))
        XCTAssertFalse(store.saveGoal(10_000))
        XCTAssertFalse(store.saveGoal(0.5))
        XCTAssertEqual(store.goal(Date()), 9999)
    }

    func testNoGoalPreferencePersistsAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: Persistence.schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        do {
            let store = AppStore(container: try ModelContainer(for: Persistence.schema, configurations: [config]))
            store.saveGoal(nil)
            store.add([EntryDraft(calories: 325)])
        }
        let reopened = AppStore(container: try ModelContainer(for: Persistence.schema, configurations: [config]))
        XCTAssertNotNil(reopened.profile)
        XCTAssertNil(reopened.profile?.dailyGoal)
        XCTAssertNil(reopened.goal(Date()))
        XCTAssertEqual(reopened.total(Date()), 325)
    }

    func testCalorieAndServingLastEditWins() {
        var draft = EntryDraft(name: "Cereal", calories: 140)
        draft.changeCalories(210)
        XCTAssertEqual(draft.servings, 1.5)
        draft.changeServings(2)
        XCTAssertEqual(draft.calories, 280)
        draft.changePerServing(150)
        XCTAssertEqual(draft.calories, 300)
        draft.changeServings(1.25)
        XCTAssertEqual(draft.calories, 188)
    }
    func testFractionalCaloriesRoundWhileServingsStayDecimal() throws {
        var draft = EntryDraft(calories: 100.5)
        XCTAssertEqual(draft.calories, 101)
        XCTAssertEqual(draft.perServing, 101)
        draft.changeServings(1.25)
        XCTAssertEqual(draft.servings, 1.25)
        XCTAssertEqual(draft.calories, 126)
        draft.changePerServing(90.5)
        XCTAssertEqual(draft.perServing, 91)
        XCTAssertEqual(draft.calories, 114)
        draft.changeCalories(150.5)
        XCTAssertEqual(draft.calories, 151)
        XCTAssertEqual(draft.servings, 151.0 / 91)
        let scaled = EntryDraft(calories: 101).scaled(0.5, at: Date(), meal: UUID(), order: 0)
        XCTAssertEqual(scaled.calories, 51)
        XCTAssertEqual(scaled.servings, 0.5)

        // Imported or previously saved drafts can still contain fractional values.
        draft.calories = 120.6
        draft.perServing = 80.4
        draft.servings = 1.5
        let store = try makeStore()
        XCTAssertTrue(store.add([draft]))
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.totalCalories, 121)
        XCTAssertEqual(entry.caloriesPerServing, 80)
        XCTAssertEqual(entry.servings, 1.5)
        XCTAssertEqual(120.5.calorieText, 121.0.calorieText)
    }
    func testClearingCaloriesResetsServingsToZero() {
        var draft = EntryDraft(name: "1% milk", calories: 105)
        draft.changeCalories(0)
        XCTAssertEqual(draft.calories, 0)
        XCTAssertEqual(draft.servings, 0)
        XCTAssertEqual(draft.perServing, 105)
        draft.changeCalories(210)
        XCTAssertEqual(draft.servings, 2)

        var manual = EntryDraft()
        manual.changeCalories(0)
        XCTAssertEqual(manual.servings, 0)
    }
    func testManualCaloriesInitializeServingFieldsWhileTyping() {
        var draft = EntryDraft()
        draft.changeCalories(0)
        draft.changeCalories(7)
        draft.changeCalories(75)
        XCTAssertEqual(draft.calories, 75)
        XCTAssertEqual(draft.servings, 1)
        XCTAssertEqual(draft.perServing, 75)
        draft.changePerServing(draft.perServing)
        XCTAssertEqual(draft.calories, 75)
        XCTAssertTrue(draft.isValid)
        draft.changeServings(2)
        XCTAssertEqual(draft.calories, 150)
        draft.changeCalories(225)
        XCTAssertEqual(draft.perServing, 75)
        XCTAssertEqual(draft.servings, 3)
    }

    func testInputValidation() {
        var draft = EntryDraft(calories: 0)
        XCTAssertTrue(draft.isValid)
        draft.calories = -1; XCTAssertFalse(draft.isValid)
        draft.calories = .nan; XCTAssertFalse(draft.isValid)
        draft.calories = 250; draft.servings = 0; XCTAssertFalse(draft.isValid)
        draft.servings = 1; draft.timestamp = Date().addingTimeInterval(3600); XCTAssertFalse(draft.isValid)
    }
    func testQuickEntryAndUndo() throws {
        let store = try makeStore()
        XCTAssertTrue(store.saveGoal(2100))
        XCTAssertTrue(store.add([EntryDraft(calories: 325)]))
        XCTAssertEqual(store.total(Date()), 325)
        XCTAssertEqual(store.entries[0].name, "")
        store.undo()
        XCTAssertEqual(store.total(Date()), 0)
    }
    func testDeleteUndoRetainsSnapshotAndIdentity() throws {
        let store = try makeStore()
        store.add([EntryDraft(name: "Coffee", calories: 120)])
        let id = store.entries[0].id, timestamp = store.entries[0].timestamp
        store.delete(store.entries[0]); XCTAssertTrue(store.entries.isEmpty)
        store.undo()
        XCTAssertEqual(store.entries[0].id, id)
        XCTAssertEqual(store.entries[0].timestamp, timestamp)
        XCTAssertEqual(store.entries[0].totalCalories, 120)
    }
    func testTimestampEditMovesDailyTotal() throws {
        let store = try makeStore()
        store.add([EntryDraft(calories: 325)])
        var edit = EntryDraft(store.entries[0]); edit.timestamp = yesterday()
        XCTAssertTrue(store.update(edit))
        XCTAssertEqual(store.total(Date()), 0)
        XCTAssertEqual(store.total(yesterday()), 325)
    }
    func testGoalChangePreservesYesterdayAndEarlier() throws {
        let store = try makeStore()
        store.saveGoal(2100)
        store.add([EntryDraft(calories: 325, timestamp: yesterday())])
        store.saveGoal(2300)
        XCTAssertEqual(store.goal(Date()), 2300)
        XCTAssertEqual(store.goal(yesterday()), 2100)
        let previousWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        XCTAssertEqual(store.goal(previousWeek), 2100)
    }
    func testSkippedDaysKeepEffectiveGoal() throws {
        let store = try makeStore()
        let old = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        store.context.insert(DailyGoal(day: Day.key(old), goal: 1800))
        store.context.insert(UserProfile(name: "Phil", goal: 1800)); store.commit()
        store.saveGoal(2100)
        XCTAssertEqual(store.goal(yesterday()), 1800)
        XCTAssertEqual(store.goal(Date()), 2100)
    }
    func testMealsAreScaledIndependentSnapshotsAndUndoTogether() throws {
        let store = try makeStore()
        let items = [EntryDraft(name: "Coffee", calories: 120), EntryDraft(name: "Eggs", calories: 210), EntryDraft(name: "Toast", calories: 180)]
        store.saveMeal(nil, name: "Breakfast", items: items)
        let meal = store.meals[0]
        XCTAssertTrue(store.addMeal(meal, factor: 1.5, date: Date()))
        XCTAssertEqual(store.entries.map(\.totalCalories), [180, 315, 270])
        XCTAssertEqual(store.total(Date()), 765)
        XCTAssertEqual(Set(store.entries.map(\.timestamp)).count, 1)
        XCTAssertEqual(store.goals.count, 1)
        store.saveMeal(meal, name: "Changed", items: [EntryDraft(name: "Coffee", calories: 999)])
        XCTAssertEqual(store.total(Date()), 765)
        store.undo(); XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.meals.count, 1)
    }
    func testCreatingAndDeletingMealDoesNotChangeHistory() throws {
        let store = try makeStore()
        store.add([EntryDraft(name: "Coffee", calories: 120)])
        store.saveMeal(nil, name: "Coffee break", items: store.entries.map(EntryDraft.init))
        XCTAssertEqual(store.total(Date()), 120)
        store.context.delete(store.meals[0]); store.commit()
        XCTAssertEqual(store.total(Date()), 120)
    }
    func testBarcodeOverridesSurviveEntryDeletionIncludingUnnamedFoods() throws {
        let store = try makeStore()
        var item = EntryDraft(calories: 220); item.barcode = "12345678"
        store.add([item]); store.delete(store.entries[0])
        XCTAssertEqual(store.localBarcode("12345678")?.calories, 220)
        item.calories = 230; store.add([item])
        XCTAssertEqual(store.localBarcode("12345678")?.calories, 230)
    }
    func testHistoryNormalizationAndOutlierResistance() throws {
        let store = try makeStore()
        let names = ["My Coffee", "my coffee", " My   Coffee ", "MY COFFEE!", "My Coffee"]
        for (i, name) in names.enumerated() {
            store.add([EntryDraft(name: name, calories: i == 4 ? 999 : 120, timestamp: Date().addingTimeInterval(Double(i - 10) * 3600))])
        }
        let results = FoodHistory.search("my cof", entries: store.entries)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].draft.calories, 120)
        store.add([EntryDraft(name: "Coffee cake", calories: 400)])
        XCTAssertEqual(FoodHistory.foods(store.entries).count, 2)
    }
    func testHistorySearchPrioritizesExactThenLikelyMatches() throws {
        let store = try makeStore()
        let now = Date()
        store.add([EntryDraft(name: "Popcorn kettle", calories: 120, timestamp: now.addingTimeInterval(-60 * 86_400))])
        for day in 1...5 {
            store.add([EntryDraft(name: "Popcorn sea salt", calories: 100, timestamp: now.addingTimeInterval(Double(-day) * 86_400))])
        }
        store.add([EntryDraft(name: "Popcorn", calories: 90, timestamp: now.addingTimeInterval(-90 * 86_400))])

        let results = FoodHistory.search("popcorn", entries: store.entries, date: now)

        XCTAssertEqual(results.map(\.draft.name), ["Popcorn", "Popcorn sea salt", "Popcorn kettle"])
    }
    func testExternalIdentityOverridesName() throws {
        let store = try makeStore()
        var a = EntryDraft(name: "Oats", calories: 140); a.externalID = "off:123"
        var b = EntryDraft(name: "New oats name", calories: 140); b.externalID = "off:123"
        store.add([a, b])
        XCTAssertEqual(FoodHistory.foods(store.entries).count, 1)
    }
    func testSuggestionsColdStartLimitAndRepeatVisibility() throws {
        let store = try makeStore()
        XCTAssertTrue(FoodHistory.suggestions(entries: store.entries, date: Date()).isEmpty)
        for i in 0..<12 { store.add([EntryDraft(name: "Food \(i)", calories: 100)]) }
        let suggestions = FoodHistory.suggestions(entries: store.entries, date: Date())
        XCTAssertEqual(suggestions.count, 10)
        var repeated = suggestions[0].draft; repeated.timestamp = Date(); store.add([repeated])
        XCTAssertTrue(FoodHistory.suggestions(entries: store.entries, date: Date()).contains { $0.id == suggestions[0].id })
    }
    func testPinnedSuggestionsStayAtTopWithinTenItemLimit() {
        let date = Date().addingTimeInterval(60)
        let entries = (0..<12).map { index in
            suggestionEntry("Food \(index)", calories: Double(100 + index), at: date.addingTimeInterval(Double(-index - 1)))
        }
        let foods = FoodHistory.foods(entries).sorted { $0.id < $1.id }
        let pinnedIDs = [foods[10].id, foods[3].id]
        let suggestions = FoodHistory.suggestions(entries: entries, date: date, pinnedIDs: pinnedIDs)
        XCTAssertEqual(suggestions.count, 10)
        XCTAssertEqual(Array(suggestions.prefix(2).map(\.id)), pinnedIDs)
        XCTAssertEqual(Set(suggestions.map(\.id)).count, suggestions.count)
    }
    func testPinPreferencesPreserveOrderRenameAndUnpin() throws {
        let suite = "CaveCalsTests.pins.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let store = AppStore(
            container: try ModelContainer(for: Persistence.schema, configurations: [config]),
            publishesWidget: false,
            preferences: preferences
        )
        store.setPinned(true, foodID: "name:coffee")
        store.setPinned(true, foodID: "name:oats")
        XCTAssertEqual(store.pinnedFoodIDs, ["name:coffee", "name:oats"])
        store.updatePin(originalID: "name:coffee", replacementID: "name:iced coffee", pinned: true)
        XCTAssertEqual(store.pinnedFoodIDs, ["name:iced coffee", "name:oats"])
        store.setPinned(false, foodID: "name:iced coffee")
        XCTAssertEqual(store.pinnedFoodIDs, ["name:oats"])
    }
    func testMealPinsPersistInInsertionOrderAndClearOnDelete() throws {
        let suite = "CaveCalsTests.mealPins.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let store = AppStore(
            container: try ModelContainer(for: Persistence.schema, configurations: [config]),
            publishesWidget: false,
            preferences: preferences
        )
        store.saveMeal(nil, name: "Breakfast", items: [EntryDraft(name: "Eggs", calories: 160)])
        store.saveMeal(nil, name: "Lunch", items: [EntryDraft(name: "Soup", calories: 240)])
        let breakfast = try XCTUnwrap(store.meals.first { $0.name == "Breakfast" })
        let lunch = try XCTUnwrap(store.meals.first { $0.name == "Lunch" })
        store.setMealPinned(true, mealID: lunch.id)
        store.setMealPinned(true, mealID: breakfast.id)
        XCTAssertEqual(store.pinnedMealIDs, [lunch.id.uuidString, breakfast.id.uuidString])
        store.setMealPinned(false, mealID: lunch.id)
        XCTAssertEqual(store.pinnedMealIDs, [breakfast.id.uuidString])
        store.deleteMeal(breakfast)
        XCTAssertTrue(store.pinnedMealIDs.isEmpty)
        XCTAssertEqual(store.meals.map(\.name), ["Lunch"])
    }
    func testSuggestionsLearnFoodSpecificTimeWindows() {
        let calendar = suggestionCalendar()
        let target = suggestionDate(day: 0, hour: 7, minute: 40, calendar: calendar)
        var entries: [CalorieEntry] = []
        for day in -14 ... -1 {
            entries.append(suggestionEntry("Coffee", calories: 80, at: suggestionDate(day: day, hour: 7, minute: 30, calendar: calendar)))
            entries.append(suggestionEntry("Afternoon snack", calories: 180, at: suggestionDate(day: day, hour: 14, minute: 0, calendar: calendar)))
            entries.append(suggestionEntry("Afternoon snack", calories: 180, at: suggestionDate(day: day, hour: 16, minute: 0, calendar: calendar)))
        }
        XCTAssertEqual(FoodHistory.suggestions(entries: entries, date: target, calendar: calendar).first?.draft.name, "Coffee")
    }
    func testSameDaySuppressionLearnsWhetherFoodRepeats() {
        let calendar = suggestionCalendar()
        let target = suggestionDate(day: 0, hour: 8, minute: 30, calendar: calendar)
        var entries: [CalorieEntry] = []
        for day in -12 ... -1 {
            entries.append(suggestionEntry("Once daily", calories: 100, at: suggestionDate(day: day, hour: 8, minute: 0, calendar: calendar)))
            for hour in [8, 12, 16] {
                entries.append(suggestionEntry("Repeater", calories: 10, at: suggestionDate(day: day, hour: hour, minute: 0, calendar: calendar)))
            }
            for index in 0..<4 {
                entries.append(suggestionEntry("Alternative \(index)", calories: 100, at: suggestionDate(day: day, hour: 8, minute: 30, calendar: calendar)))
            }
        }
        entries.append(suggestionEntry("Once daily", calories: 100, at: suggestionDate(day: 0, hour: 8, minute: 0, calendar: calendar)))
        entries.append(suggestionEntry("Repeater", calories: 10, at: suggestionDate(day: 0, hour: 8, minute: 0, calendar: calendar)))

        let names = FoodHistory.suggestions(entries: entries, date: target, calendar: calendar).map(\.draft.name)
        // With six candidates and ten available slots, suppression lowers rank;
        // it does not remove an otherwise valid food from the list.
        XCTAssertEqual(Set(names), Set(["Repeater", "Once daily"] + (0..<4).map { "Alternative \($0)" }))
        XCTAssertEqual(names.last, "Once daily")
    }
    func testRecentSessionCoOccurrencePromotesCompanionFood() {
        let calendar = suggestionCalendar()
        let target = suggestionDate(day: 0, hour: 19, minute: 2, calendar: calendar)
        var entries: [CalorieEntry] = []
        for day in -24 ... -13 {
            entries.append(suggestionEntry("Burger", calories: 500, at: suggestionDate(day: day, hour: 19, minute: 0, calendar: calendar)))
            entries.append(suggestionEntry("Fries", calories: 300, at: suggestionDate(day: day, hour: 19, minute: 8, calendar: calendar)))
        }
        for day in -12 ... -1 {
            entries.append(suggestionEntry("Salad", calories: 200, at: suggestionDate(day: day, hour: 19, minute: 0, calendar: calendar)))
        }
        entries.append(suggestionEntry("Burger", calories: 500, at: suggestionDate(day: 0, hour: 19, minute: 0, calendar: calendar)))

        let names = FoodHistory.suggestions(entries: entries, date: target, calendar: calendar).map(\.draft.name)
        guard let friesIndex = names.firstIndex(of: "Fries"),
              let saladIndex = names.firstIndex(of: "Salad") else {
            return XCTFail("Expected both foods in the ranked suggestions")
        }
        XCTAssertLessThan(friesIndex, saladIndex)
    }
    func testSuggestionsUseCaloriesForTheCurrentFoodTimePattern() {
        let calendar = suggestionCalendar()
        var entries: [CalorieEntry] = []
        for day in -12 ... -1 {
            entries.append(suggestionEntry("Coffee", calories: 80, at: suggestionDate(day: day, hour: 7, minute: 30, calendar: calendar)))
            entries.append(suggestionEntry("Coffee", calories: 30, at: suggestionDate(day: day, hour: 15, minute: 30, calendar: calendar)))
        }
        let morning = FoodHistory.suggestions(entries: entries, date: suggestionDate(day: 0, hour: 7, minute: 40, calendar: calendar), calendar: calendar)
        let afternoon = FoodHistory.suggestions(entries: entries, date: suggestionDate(day: 0, hour: 15, minute: 40, calendar: calendar), calendar: calendar)
        XCTAssertEqual(morning.first?.draft.calories, 80)
        XCTAssertEqual(afternoon.first?.draft.calories, 30)
    }
    func testSuggestionReplayMetricsMeasureKnownRoutine() {
        let calendar = suggestionCalendar()
        var entries: [CalorieEntry] = []
        for day in -20 ... -1 {
            entries.append(suggestionEntry("Breakfast", calories: 400, at: suggestionDate(day: day, hour: 7, minute: 0, calendar: calendar)))
            entries.append(suggestionEntry("Lunch", calories: 600, at: suggestionDate(day: day, hour: 12, minute: 0, calendar: calendar)))
        }
        let metrics = FoodHistory.replayMetrics(entries: entries, maximumSamples: 30, calendar: calendar)
        XCTAssertEqual(metrics.samples, 30)
        XCTAssertGreaterThan(metrics.top1Accuracy, 0.8)
        XCTAssertEqual(metrics.top5Accuracy, 1)
        XCTAssertGreaterThan(metrics.meanReciprocalRank, 0.8)
    }

    private func suggestionCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func suggestionDate(day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        let date = calendar.date(byAdding: .day, value: day, to: anchor)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }
    private func suggestionEntry(_ name: String, calories: Double, at date: Date) -> CalorieEntry {
        CalorieEntry(draft: EntryDraft(name: name, calories: calories, timestamp: date))
    }
    func testLocalDateBoundaryAndHistoricalQuickEntry() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        let instant = ISO8601DateFormatter().date(from: "2026-09-05T06:59:00Z")!
        XCTAssertEqual(Day.key(instant, calendar: calendar), "01-2026-09-04")
        XCTAssertEqual(Day.key(instant.addingTimeInterval(120), calendar: calendar), "01-2026-09-05")
        let past = instant.addingTimeInterval(-86_400)
        XCTAssertEqual(Day.key(Day.loggingDate(past, now: instant, calendar: calendar), calendar: calendar), Day.key(past, calendar: calendar))
    }
    func testProviderUsesServingCaloriesAndPreservesDescription() throws {
        let json = #"{"code":"123","product_name":"Cereal","serving_size":"1.5 cups","nutriments":{"energy-kcal_serving":140,"energy-kcal_100g":380}}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenFoodFacts.Product.self, from: json).result
        XCTAssertEqual(result?.calories, 140)
        XCTAssertEqual(result?.servingDescription, "1.5 cups")
    }
    func testProviderNeverLabels100gCaloriesAsOnePackage() throws {
        let json = #"{"code":"123","product_name":"Cereal","serving_size":"1 package","nutriments":{"energy-kcal_100g":"380"}}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenFoodFacts.Product.self, from: json).result
        XCTAssertEqual(result?.calories, 380)
        XCTAssertEqual(result?.servingDescription, "100 g / 100 ml")
    }
    func testProviderConvertsKilojoulesAndRejectsMissingEnergy() throws {
        let json = #"{"code":"123","product_name":"Food","serving_size":"1 bar","nutriments":{"energy_serving":418.4}}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenFoodFacts.Product.self, from: json).result
        XCTAssertEqual(result!.calories, 100, accuracy: 0.001)
        let absent = #"{"code":"123","product_name":"Food","nutriments":{}}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(OpenFoodFacts.Product.self, from: absent).result)
    }
    func testSearchFailureKeepsManualAndLocalLoggingUsable() async throws {
        struct Offline: FoodSearchService { func search(query: String) async throws -> [FoodResult] { throw URLError(.notConnectedToInternet) } }
        let search = FoodSearchState(provider: Offline(), persistCache: false)
        await search.search("coffee")
        XCTAssertEqual(search.message, FoodServiceError.offline.localizedDescription)
        XCTAssertFalse(search.loading)
        let store = try makeStore(); XCTAssertTrue(store.add([EntryDraft(name: "Coffee", calories: 120)]))
        XCTAssertEqual(FoodHistory.search("coffee", entries: store.entries).count, 1)
    }
    func testFatSecretClientUsesBackendAndPreservesServingContract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoodSearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = FatSecretSearch(session: session, baseURL: URL(string: "https://fixture.invalid")!)
        let page = try await provider.searchPage(query: "Urbane Cafe")
        XCTAssertEqual(page.results.first?.calories, 800)
        XCTAssertEqual(page.results.first?.servingDescription, "1 sandwich")
        XCTAssertEqual(page.cacheLifetime, 0)
        do { _ = try await provider.search(query: "busy"); XCTFail("Must surface rate limit") }
        catch { XCTAssertEqual(error.localizedDescription, FoodServiceError.rateLimited.localizedDescription) }
    }
    func testBrandedResultsLeadWithProductNameAndKeepBrandForOneWordNames() {
        let diet = FoodResult(id: "fatsecret:1", name: "Diet Coke", brand: "Coca-Cola", calories: 0, servingDescription: "1 can")
        XCTAssertEqual(diet.draft.name, "Diet Coke")
        XCTAssertEqual(diet.searchDetail, "Coca-Cola · 1 can")
        let latte = FoodResult(id: "fatsecret:2", name: "Latte", brand: "Starbucks", calories: 190, servingDescription: "1 grande")
        XCTAssertEqual(latte.draft.name, "Starbucks Latte")
        XCTAssertEqual(latte.searchDetail, "1 grande")
        let named = FoodResult(id: "fatsecret:3", name: "Coca-Cola Classic", brand: "Coca-Cola", calories: 140, servingDescription: "1 can")
        XCTAssertEqual(named.draft.name, "Coca-Cola Classic")
        XCTAssertEqual(named.searchDetail, "1 can")
    }
    func testFoodSearchNeverCachesEmptyResultsAndShowsBrandBesideServing() async throws {
        let provider = SearchFixture(pages: [FoodSearchPage(results: [], cacheLifetime: 3600), SearchFixture.page])
        let search = FoodSearchState(provider: provider, persistCache: false, debounce: .zero)
        await search.search("Urbane Cafe")
        XCTAssertTrue(search.results.isEmpty)
        XCTAssertNotNil(search.message)
        await search.search("Urbane Cafe")
        XCTAssertEqual(search.results.count, 1)
        XCTAssertEqual(search.results.first?.draft.name, "So-Cal Sandwich")
        XCTAssertEqual(search.results.first?.searchDetail, "Urbane Cafe · 1 sandwich")
        XCTAssertEqual(search.results.first?.draft.calories, 800)
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
    }
    func testFoodSearchPositiveCacheExpiresAndBasicResultsAreNeverPersisted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("search.json")
        var now = Date()
        let provider = SearchFixture(pages: [SearchFixture.page])
        let search = FoodSearchState(provider: provider, cacheURL: file, now: { now }, debounce: .zero)
        await search.search("Urbane Cafe"); await search.search("urbane cafe")
        var calls = await provider.calls; XCTAssertEqual(calls, 1)
        let reopened = FoodSearchState(provider: provider, cacheURL: file, now: { now }, debounce: .zero)
        await reopened.search("urbane cafe")
        calls = await provider.calls; XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(3601)
        await reopened.search("urbane cafe")
        calls = await provider.calls; XCTAssertEqual(calls, 2)
        let basicFile = folder.appendingPathComponent("basic.json")
        let basic = SearchFixture(pages: [FoodSearchPage(results: SearchFixture.page.results, cacheLifetime: 0)])
        let uncached = FoodSearchState(provider: basic, cacheURL: basicFile, debounce: .zero)
        await uncached.search("urbane"); await uncached.search("urbane")
        calls = await basic.calls; XCTAssertEqual(calls, 2)
        XCTAssertFalse(String(data: try Data(contentsOf: basicFile), encoding: .utf8)!.contains("Sandwich"))
    }
    func testFoodSearchIgnoresOlderResponsesAfterQueryChanges() async throws {
        let provider = SlowSearchFixture()
        let search = FoodSearchState(provider: provider, persistCache: false, debounce: .zero)
        let first = Task { await search.search("old query") }
        while !(await provider.waiting) { await Task.yield() }
        await search.search("new query")
        await provider.finish()
        await first.value
        XCTAssertEqual(search.results.first?.name, "new query")
        XCTAssertFalse(search.loading)
    }
    func testPersistentStoreReopensWithoutLosingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("test.store")
        let config = ModelConfiguration(schema: Persistence.schema, url: url, cloudKitDatabase: .none)
        do {
            let store = AppStore(container: try ModelContainer(for: Persistence.schema, configurations: [config]))
            store.saveGoal(2100)
            store.add([EntryDraft(name: "Coffee", calories: 120)])
        }
        let reopened = AppStore(container: try ModelContainer(for: Persistence.schema, configurations: [config]))
        XCTAssertEqual(reopened.profile?.dailyGoal, 2100)
        XCTAssertEqual(reopened.total(Date()), 120)
    }
}

private actor SearchFixture: FoodSearchService {
    static let page = FoodSearchPage(results: [FoodResult(id: "fatsecret:123", name: "So-Cal Sandwich", brand: "Urbane Cafe", calories: 800, servingDescription: "1 sandwich")], cacheLifetime: 3600)
    private let pages: [FoodSearchPage]
    private(set) var calls = 0
    init(pages: [FoodSearchPage]) { self.pages = pages }
    func search(query: String) async throws -> [FoodResult] { try await searchPage(query: query).results }
    func searchPage(query: String) async throws -> FoodSearchPage {
        let page = pages[min(calls, pages.count - 1)]; calls += 1; return page
    }
}
private actor SlowSearchFixture: FoodSearchService {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func finish() { continuation?.resume(); continuation = nil }
    func search(query: String) async throws -> [FoodResult] {
        if query == "old query" { await withCheckedContinuation { continuation = $0 } }
        return [FoodResult(id: "fixture:\(query)", name: query, calories: 100, servingDescription: "1 serving")]
    }
}

private final class FoodSearchURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/foods/search")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; body.append(contentsOf: buffer.prefix(size)) }
        }
        let query = (try? JSONDecoder().decode([String: String].self, from: body))?["query"]
        XCTAssertNotNil(query)
        let status = query == "busy" ? 429 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let data = #"{"results":[{"id":"fatsecret:123","name":"So-Cal Sandwich","brand":"Urbane Cafe","calories":800,"servingDescription":"1 sandwich"}],"cacheLifetime":0}"#.data(using: .utf8)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class MacroTests: XCTestCase {
    private func food() -> EntryDraft {
        var draft = EntryDraft(name: "Egg", calories: 70)
        draft.macrosPerServing = MacroNutrients(protein: 6.25, totalCarbs: 0, fiber: 0, fat: 5)
        return draft
    }
    func testCatalogNutritionSurvivesSearchLoggingQuickAddMealsAndPortions() throws {
        XCTAssertEqual(CommonFoods.foods.count, 5904)
        XCTAssertTrue(CommonFoods.foods.allSatisfy { $0.draft.isValid && $0.macrosPerServing?.isComplete == true })
        let banana = try XCTUnwrap(CommonFoods.search("banana").first { $0.id == "banana" })
        XCTAssertEqual(banana.draft.totalMacros, MacroNutrients(protein: 1, totalCarbs: 30, fiber: 3, fat: 0))
        let store = try Persistence.make(inMemory: true)
        var draft = banana.draft
        draft.timestamp = Date().addingTimeInterval(-60)
        XCTAssertTrue(store.add([draft]))
        let suggestion = try XCTUnwrap(FoodHistory.suggestions(entries: store.entries, date: Date()).first)
        XCTAssertEqual(suggestion.draft.totalMacros, draft.totalMacros)
        var repeated = suggestion.draft
        repeated.changeServings(2)
        XCTAssertTrue(store.add([repeated]))
        let summary = MacroSummary(store.entries.map(EntryDraft.init))
        XCTAssertEqual(summary.total(.totalCarbs).grams, 90)
        XCTAssertEqual(summary.total(.fiber).grams, 9)
        XCTAssertTrue(store.saveMeal(nil, name: "Fruit", items: [repeated]))
        XCTAssertEqual(store.meals.first?.items.first?.totalMacros?.netCarbs, 54)
    }
    func testNetCarbsAreDerivedAndFiberScalesWithoutInventingUnknowns() throws {
        let macros = MacroNutrients(protein: 1, totalCarbs: 30, fiber: 3, fat: 0)
        XCTAssertEqual(macros.netCarbs, 27)
        XCTAssertEqual(macros.scaled(2.5).fiber, 7.5)
        XCTAssertEqual(macros.scaled(2.5).netCarbs, 67.5)
        XCTAssertNil(MacroNutrients(totalCarbs: 30).netCarbs)
        XCTAssertNil(MacroNutrients(fiber: 3).netCarbs)
        XCTAssertEqual(MacroNutrients(totalCarbs: 0, fiber: 0).netCarbs, 0)
        XCTAssertFalse(MacroNutrients(totalCarbs: 2, fiber: 3).isValid)
        let filled = MacroNutrients(totalCarbs: 30).fillingMissing(from: macros.markedEstimated())
        XCTAssertEqual(filled.totalCarbs, 30)
        XCTAssertEqual(filled.fiber, 3)
        XCTAssertTrue(filled.estimatedNetCarbs)
        let encoded = try JSONEncoder().encode(macros)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["netCarbs"], "Derived values must not become a second source of truth")
        XCTAssertEqual(try JSONDecoder().decode(MacroNutrients.self, from: encoded), macros)
    }
    func testBarcodeTotalCarbsPreferExplicitValuesAndPreserveUnknownFiber() throws {
        func decode(_ nutrients: String) throws -> MacroNutrients {
            let json = "{\"code\":\"123\",\"product_name\":\"Food\",\"nutriments\":{\"energy-kcal_100g\":100," + nutrients + "}}"
            return try XCTUnwrap(JSONDecoder().decode(OpenFoodFacts.Product.self, from: Data(json.utf8)).result?.macros)
        }
        let explicit = try decode(#""carbohydrates-total_100g":30,"carbohydrates_100g":25,"fiber_100g":5"#)
        XCTAssertEqual(explicit.totalCarbs, 30)
        XCTAssertEqual(explicit.netCarbs, 25)
        let unknown = try decode(#""carbohydrates_100g":25"#)
        XCTAssertNil(unknown.totalCarbs)
        XCTAssertNil(unknown.fiber)
        let totalOnly = try decode(#""carbohydrates-total_100g":30"#)
        XCTAssertEqual(totalOnly.totalCarbs, 30)
        XCTAssertNil(totalOnly.netCarbs)
        let invalid = try decode(#""carbohydrates-total_100g":3,"fiber_100g":5"#)
        XCTAssertEqual(invalid.totalCarbs, 3)
        XCTAssertNil(invalid.fiber)
        let excessive = try decode(#""carbohydrates_100g":100000,"fiber_100g":1"#)
        XCTAssertNil(excessive.totalCarbs)
        XCTAssertTrue(excessive.isValid)
        let zero = try decode(#""carbohydrates_100g":0,"fiber_100g":0"#)
        XCTAssertEqual(zero.totalCarbs, 0)
        XCTAssertEqual(zero.netCarbs, 0)
    }
    func testUpgradeFromCalorieOnlyStorePreservesHistoryAndDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Upgrade.store")
        let oldSchema = Schema([BeforeMacros.UserProfile.self, BeforeMacros.DailyGoal.self, BeforeMacros.CalorieEntry.self, BeforeMacros.SavedMeal.self, BeforeMacros.BarcodeFood.self])
        try autoreleasepool {
            let config = ModelConfiguration("Upgrade", schema: oldSchema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: oldSchema, configurations: [config])
            let context = ModelContext(container)
            let draft = EntryDraft(name: "Before macros", calories: 325)
            context.insert(BeforeMacros.UserProfile(goal: 1800))
            context.insert(BeforeMacros.CalorieEntry(draft: draft))
            context.insert(BeforeMacros.SavedMeal(name: "Existing meal", items: [draft]))
            context.insert(BeforeMacros.BarcodeFood(barcode: "123", draft: draft))
            context.insert(BeforeMacros.DailyGoal(day: Day.key(Date()), goal: 1800))
            try context.save()
        }
        let config = ModelConfiguration("Upgrade", schema: Persistence.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Persistence.schema, configurations: [config])
        let store = AppStore(container: container)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.total(Date()), 325)
        XCTAssertEqual(store.goal(Date()), 1800)
        XCTAssertTrue(store.tracksMacros)
        XCTAssertNil(EntryDraft(try XCTUnwrap(store.entries.first)).totalMacros)
        XCTAssertEqual(store.meals.first?.items.first?.name, "Before macros")
        XCTAssertEqual(store.barcodes.first?.draft?.calories, 325)
        var edited = EntryDraft(try XCTUnwrap(store.entries.first))
        edited.macrosPerServing = MacroNutrients(protein: 20)
        XCTAssertTrue(store.update(edited))
        XCTAssertEqual(store.total(Date()), 325)
        XCTAssertEqual(EntryDraft(try XCTUnwrap(store.entries.first)).totalMacros?.protein, 20)
    }
    func testServingCalorieAndMealScalingKeepsNutritionTogether() {
        var draft = food()
        draft.changeServings(2.5)
        XCTAssertEqual(draft.totalMacros?.protein, 15.625)
        XCTAssertEqual(draft.totalMacros?.totalCarbs, 0)
        draft.changeCalories(140)
        XCTAssertEqual(draft.totalMacros?.protein, 12.5)
        draft.changePerServing(80)
        XCTAssertEqual(draft.totalMacros?.protein, 12.5, "Editing calories per serving is not a new food portion")
        let scaled = draft.scaled(3, at: Date(), meal: UUID(), order: 0)
        XCTAssertEqual(scaled.totalMacros?.protein, 37.5)
        XCTAssertEqual(scaled.macrosPerServing, draft.macrosPerServing)
    }
    func testLegacyDraftsMealsAndDefaultsDecodeWithoutInventingMacros() throws {
        let encoded = try JSONEncoder().encode(food())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "macrosPerServing")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let draft = try JSONDecoder().decode(EntryDraft.self, from: legacy)
        XCTAssertNil(draft.totalMacros)
        let meal = SavedMeal(name: "Old", items: [draft])
        XCTAssertNil(meal.items.first?.totalMacros)
        let entry = CalorieEntry(draft: draft)
        XCTAssertNil(EntryDraft(entry).totalMacros)
        let oldDefault = Data(#"{"calories":70,"perServing":70,"servings":1,"servingDescription":"1 egg"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(CommonFoodDefault.self, from: oldDefault).macrosPerServing)
    }
    func testKnownZeroUnknownAndPartialTotalsAreDistinct() {
        let known = food(), unknown = EntryDraft(calories: 50)
        XCTAssertEqual(MacroSummary([]).total(.protein).grams, 0)
        XCTAssertNil(MacroSummary([unknown]).total(.protein).grams)
        let summary = MacroSummary([known, unknown])
        XCTAssertEqual(summary.total(.protein).grams, 6.25)
        XCTAssertTrue(summary.total(.protein).incomplete)
        XCTAssertTrue(summary.total(.protein).text.hasSuffix("+"))
        XCTAssertEqual(summary.total(.totalCarbs).grams, 0)
        XCTAssertTrue(summary.incomplete)
    }
    func testEstimatesFillOnlyMissingFieldsAndPreserveProvenance() {
        let existing = MacroNutrients(protein: 0, fat: 3)
        let filled = existing.fillingMissing(from: MacroNutrients(protein: 8, totalCarbs: 6, fiber: 2, fat: 5).markedEstimated())
        XCTAssertEqual(filled.protein, 0); XCTAssertEqual(filled.fat, 3); XCTAssertEqual(filled.totalCarbs, 6)
        XCTAssertNotEqual(filled.estimatedProtein, true); XCTAssertEqual(filled.estimatedTotalCarbs, true)
        var draft = food(); draft.macrosPerServing = filled
        XCTAssertTrue(MacroSummary([draft]).total(.totalCarbs).estimated)
        XCTAssertFalse(MacroSummary([draft]).total(.protein).estimated)
    }
    func testInvalidMacroInputCannotBeSaved() {
        for invalid in [Double.nan, .infinity, -1, 100001] {
            var draft = food(); draft.macrosPerServing?.protein = invalid
            XCTAssertFalse(draft.isValid)
        }
        var draft = food(); draft.macrosPerServing?.protein = 60000; draft.changeServings(2)
        XCTAssertFalse(draft.isValid, "Totals also have a bound")
    }
    func testPersistenceEditUndoSavedMealBarcodeAndCommonDefault() throws {
        let store = try Persistence.make(inMemory: true)
        store.saveGoal(2100)
        var draft = food(); draft.barcode = "1234"; draft.macrosPerServing?.estimatedFat = true
        XCTAssertTrue(store.add([draft]))
        var entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(EntryDraft(entry).totalMacros, draft.totalMacros)
        var edited = EntryDraft(entry); edited.macrosPerServing?.protein = 8
        XCTAssertTrue(store.update(edited))
        XCTAssertEqual(store.barcodes.first?.draft?.totalMacros?.protein, 8)
        store.delete(entry); store.undo()
        entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(EntryDraft(entry).totalMacros?.protein, 8)
        XCTAssertEqual(CommonFoodDefault(edited).applying(to: EntryDraft()).totalMacros, edited.totalMacros)
        XCTAssertTrue(store.saveMeal(nil, name: "Egg meal", items: [edited]))
        let meal = try XCTUnwrap(store.meals.first)
        XCTAssertEqual(meal.items.first?.totalMacros, edited.totalMacros)
        XCTAssertTrue(store.addMeal(meal, factor: 2, date: Date()))
        XCTAssertEqual(store.entries.filter { $0.mealTemplateID == meal.id }.map(EntryDraft.init).first?.totalMacros?.protein, 16)
    }
    func testMacroPreferencesStartEnabledAndGoalsPreserveHistory() throws {
        let store = try Persistence.make(inMemory: true)
        store.saveGoal(2100)
        XCTAssertTrue(store.tracksMacros)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.add([EntryDraft(calories: 100, timestamp: yesterday)])
        XCTAssertTrue(store.saveMacroGoals(MacroNutrients(protein: 140, totalCarbs: 100)))
        XCTAssertEqual(store.macroGoals(Date()).protein, 140)
        XCTAssertNil(store.macroGoals(yesterday).protein)
        XCTAssertTrue(store.setTracksMacros(false))
        XCTAssertFalse(store.tracksMacros)
        XCTAssertEqual(store.macroGoals.protein, 140)
        XCTAssertTrue(store.setTracksMacros(true))
        XCTAssertFalse(store.saveMacroGoals(MacroNutrients(protein: 0)))
        XCTAssertTrue(store.saveMacroGoals(MacroNutrients()))
        XCTAssertNil(store.macroGoals(Date()).protein)
        XCTAssertEqual(store.goal(Date()), 2100)
    }
    func testAIMacrosMatchEntirePortionIncludingLegacyFallback() {
        let macros = MacroNutrients(protein: 6, totalCarbs: 48, fiber: 6, fat: 1)
        let item = AIFoodEstimate(name: "Bananas", calories: 210, portion: "2 bananas", servingSize: "1 banana", servings: 2, confidence: "high", macros: macros)
        var draft = AIResult(items: [item], notes: "").drafts(at: Date(), source: "aiAudio")[0]
        XCTAssertEqual(draft.macrosPerServing?.protein, 3)
        XCTAssertEqual(draft.totalMacros?.totalCarbs, 48)
        XCTAssertEqual(draft.totalMacros?.fiber, 6)
        XCTAssertEqual(draft.totalMacros?.netCarbs, 42)
        XCTAssertTrue(draft.totalMacros?.hasEstimates == true)
        draft.changeServings(1)
        XCTAssertEqual(draft.totalMacros?.totalCarbs, 24)
        XCTAssertEqual(draft.totalMacros?.fiber, 3)
        XCTAssertEqual(draft.totalMacros?.netCarbs, 21)
        var legacy = item; legacy.servingSize = nil; legacy.servings = nil; legacy.macros = nil
        XCTAssertNil(AIResult(items: [legacy], notes: "").drafts(at: Date(), source: "aiAudio")[0].totalMacros)
    }
    func testBarcodeNutritionUsesSamePortionAndDoesNotSubtractFiberTwice() throws {
        let json = #"{"code":"123","product_name":"Cereal","serving_size":"30 g","serving_quantity":30,"nutriments":{"energy-kcal_100g":400,"proteins_100g":10,"carbohydrates_100g":60,"fiber_100g":12,"fat_100g":5}}"#
        let product = try JSONDecoder().decode(OpenFoodFacts.Product.self, from: Data(json.utf8))
        let result = try XCTUnwrap(product.result)
        XCTAssertEqual(result.calories, 120)
        XCTAssertEqual(result.macros?.protein, 3)
        XCTAssertEqual(try XCTUnwrap(result.macros?.totalCarbs), 21.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.macros?.fiber), 3.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.macros?.netCarbs), 18, accuracy: 0.0001)
        XCTAssertEqual(result.macros?.fat, 1.5)
        XCTAssertEqual(result.draft.macrosPerServing, result.macros)
    }
}

// Frozen pre-macro schema: exercises SwiftData’s actual on-disk additive migration.
private enum BeforeMacros {
@Model final class UserProfile {
    var id: UUID = UUID()
    var name: String = "" // Retained for compatibility with existing stores; no longer collected.
    // Zero represents no goal, preserving the existing local/CloudKit schema.
    var currentDailyGoal: Double = 2100
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(name: String = "", goal: Double) { self.name = name; currentDailyGoal = goal }
    var dailyGoal: Double? { currentDailyGoal > 0 ? currentDailyGoal : nil }
}

@Model final class DailyGoal {
    var id: UUID = UUID()
    var day: String = ""
    var calorieGoal: Double = 2100 // Zero preserves a historical day without a goal.
    var updatedAt: Date = Date()
    init(day: String, goal: Double) { self.day = day; calorieGoal = goal }
}

@Model final class CalorieEntry {
    var id: UUID = UUID()
    var name: String = ""
    var totalCalories: Double = 0
    var timestamp: Date = Date()
    var servings: Double = 1
    var caloriesPerServing: Double = 0
    var servingDescription: String = ""
    var sourceType: String = "manual"
    var externalID: String?
    var barcode: String?
    var mealTemplateID: UUID?
    var componentOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(draft: EntryDraft) { apply(draft) }
    func apply(_ draft: EntryDraft) {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        totalCalories = draft.calories.rounded(); timestamp = draft.timestamp
        servings = draft.servings; caloriesPerServing = draft.perServing.rounded()
        servingDescription = draft.servingDescription; externalID = draft.externalID
        barcode = draft.barcode; sourceType = draft.source
        mealTemplateID = draft.mealID; componentOrder = draft.order; updatedAt = Date()
    }
}

// Meal components are one atomic value, avoiding partially synchronized templates.
@Model final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var componentsData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(name: String, items: [EntryDraft]) {
        self.name = name
        componentsData = (try? JSONEncoder().encode(items)) ?? Data()
    }
    var items: [EntryDraft] { (try? JSONDecoder().decode([EntryDraft].self, from: componentsData)) ?? [] }
    var calories: Double { items.reduce(0) { $0 + $1.calories.rounded() } }
}

@Model final class BarcodeFood {
    var id: UUID = UUID()
    var barcode: String = ""
    var payload: Data = Data()
    var updatedAt: Date = Date()
    init(barcode: String, draft: EntryDraft) {
        self.barcode = barcode; payload = (try? JSONEncoder().encode(draft)) ?? Data()
    }
    var draft: EntryDraft? { try? JSONDecoder().decode(EntryDraft.self, from: payload) }
}


}
