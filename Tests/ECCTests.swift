import XCTest
import SwiftData
@testable import CaveCals

@MainActor final class ECCTests: XCTestCase {
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
        for i in 0..<8 { store.add([EntryDraft(name: "Food \(i)", calories: 100)]) }
        let suggestions = FoodHistory.suggestions(entries: store.entries, date: Date())
        XCTAssertEqual(suggestions.count, 5)
        var repeated = suggestions[0].draft; repeated.timestamp = Date(); store.add([repeated])
        XCTAssertTrue(FoodHistory.suggestions(entries: store.entries, date: Date()).contains { $0.id == suggestions[0].id })
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
