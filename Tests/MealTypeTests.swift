import XCTest
import SwiftData
@testable import CaveCals

@MainActor
final class MealTypeTests: XCTestCase {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 1) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func makeStore(_ settings: MealSettings? = nil) throws -> AppStore {
        let store = try Persistence.make(inMemory: true)
        XCTAssertTrue(store.saveGoal(2000))
        if let settings { XCTAssertTrue(store.saveMealSettings(settings)) }
        return store
    }

    // MARK: Times

    func testMealTimeContainsHalfOpenBlocksAndWrapsPastMidnight() {
        let breakfast = MealTime(start: 5 * 60, end: 9 * 60)
        XCTAssertTrue(breakfast.contains(5 * 60))
        XCTAssertTrue(breakfast.contains(9 * 60 - 1))
        XCTAssertFalse(breakfast.contains(9 * 60), "The end minute belongs to the next meal")
        XCTAssertFalse(breakfast.contains(4 * 60 + 59))
        let evening = MealTime(start: 20 * 60, end: 4 * 60)
        XCTAssertTrue(evening.crossesMidnight)
        XCTAssertTrue(evening.contains(23 * 60 + 59))
        XCTAssertTrue(evening.contains(0))
        XCTAssertTrue(evening.contains(3 * 60 + 59))
        XCTAssertFalse(evening.contains(4 * 60))
        XCTAssertFalse(evening.contains(19 * 60 + 59))
        XCTAssertFalse(MealTime(start: 600, end: 600).isValid)
        XCTAssertEqual(MealTime(start: -60, end: 1500), MealTime(start: 23 * 60, end: 60))
    }

    func testOverlapsTreatsTouchingBlocksAsSeparate() {
        let lunch = MealTime(start: 11 * 60, end: 14 * 60)
        XCTAssertFalse(lunch.overlaps(MealTime(start: 14 * 60, end: 16 * 60)))
        XCTAssertFalse(lunch.overlaps(MealTime(start: 9 * 60, end: 11 * 60)))
        XCTAssertTrue(lunch.overlaps(MealTime(start: 13 * 60, end: 15 * 60)))
        XCTAssertTrue(lunch.overlaps(MealTime(start: 12 * 60, end: 13 * 60)), "Inside another block")
        XCTAssertTrue(lunch.overlaps(MealTime(start: 10 * 60, end: 15 * 60)), "Around another block")
        let evening = MealTime(start: 20 * 60, end: 4 * 60)
        XCTAssertTrue(evening.overlaps(MealTime(start: 1 * 60, end: 2 * 60)))
        XCTAssertTrue(MealTime(start: 3 * 60, end: 5 * 60).overlaps(evening))
        XCTAssertFalse(evening.overlaps(MealTime(start: 4 * 60, end: 5 * 60)))
    }

    func testDefaultMealTimesFollowTheDay() {
        let settings = MealSettings(tracks: true)
        let expected: [(Int, Int, String?)] = [
            (4, 30, nil), (5, 0, "breakfast"), (8, 59, "breakfast"), (9, 0, "morningSnack"), (10, 59, "morningSnack"),
            (11, 0, "lunch"), (13, 59, "lunch"), (14, 0, "afternoonSnack"), (15, 59, "afternoonSnack"),
            (16, 0, "dinner"), (19, 59, "dinner"), (20, 0, "eveningSnack"), (23, 59, "eveningSnack"),
            (0, 0, "eveningSnack"), (3, 59, "eveningSnack"), (4, 0, nil),
        ]
        for (hour, minute, meal) in expected {
            XCTAssertEqual(settings.meal(at: at(hour, minute)), meal, "\(hour):\(minute)")
        }
        XCTAssertNil(MealType.defaults.first { $0.id == "dessert" }?.time, "Dessert has no default time")
        XCTAssertEqual(settings.uncoveredTimes, [MealTime(start: 4 * 60, end: 5 * 60)])
    }

    func testRemovedTypesNoLongerClaimTheirTime() {
        let settings = MealSettings(tracks: true).removing("lunch", inUse: true)
        XCTAssertEqual(settings.type(id: "lunch")?.removed, true, "Kept so logged food keeps its label")
        XCTAssertNil(settings.meal(at: at(12)))
        XCTAssertFalse(settings.visibleTypes.contains { $0.id == "lunch" })
        XCTAssertEqual(settings.uncoveredTimes, [MealTime(start: 4 * 60, end: 5 * 60), MealTime(start: 11 * 60, end: 14 * 60)])
        XCTAssertNil(MealSettings(tracks: true).removing("lunch", inUse: false).type(id: "lunch"))
    }

    func testUncoveredTimeThroughMidnightIsOneStretch() {
        let settings = MealSettings(tracks: true, types: [MealType(id: "day", name: "Day", time: MealTime(start: 6 * 60, end: 22 * 60))])
        XCTAssertEqual(settings.uncoveredTimes, [MealTime(start: 22 * 60, end: 6 * 60)])
        XCTAssertEqual(MealSettings(tracks: true, types: [MealType(id: "any", name: "Any")]).uncoveredTimes, [])
    }

    // MARK: Assigning

    func testAssignedMealFollowsTheSettings() {
        let off = MealSettings(tracks: false)
        XCTAssertNil(off.assignedMeal(chosen: "lunch", at: at(12)), "Nothing is filed while meal types are off")
        let byTime = MealSettings(tracks: true, byTime: true)
        XCTAssertEqual(byTime.assignedMeal(chosen: nil, at: at(12)), "lunch")
        XCTAssertEqual(byTime.assignedMeal(chosen: "dessert", at: at(12)), "dessert", "A picked meal wins")
        XCTAssertNil(byTime.assignedMeal(chosen: nil, at: at(4, 30)), "Outside every meal's time")
        XCTAssertEqual(byTime.assignedMeal(chosen: "gone", at: at(12)), "lunch", "An unknown meal falls back to the time")
        let asks = MealSettings(tracks: true, byTime: false)
        XCTAssertTrue(asks.asks)
        XCTAssertNil(asks.assignedMeal(chosen: nil, at: at(12)), "Not picked stays unspecified")
        XCTAssertEqual(asks.assignedMeal(chosen: "lunch", at: at(8)), "lunch")
        XCTAssertNil(asks.removing("lunch", inUse: true).assignedMeal(chosen: "lunch", at: at(12)))
    }

    func testAddingAssignsMealsAndOffLeavesThemUnspecified() throws {
        let store = try makeStore()
        XCTAssertTrue(store.add([EntryDraft(name: "Before", calories: 100, timestamp: at(12))]))
        XCTAssertNil(store.entries.last?.mealType, "Meal types are off by default")

        XCTAssertTrue(store.saveMealSettings(MealSettings(tracks: true)))
        XCTAssertTrue(store.add([EntryDraft(name: "Soup", calories: 200, timestamp: at(12, 30))]))
        XCTAssertEqual(store.entries.first { $0.name == "Soup" }?.mealType, "lunch")
        XCTAssertTrue(store.add([EntryDraft(name: "Toast", calories: 90, timestamp: at(4, 15))]))
        XCTAssertNil(store.entries.first { $0.name == "Toast" }?.mealType)
        XCTAssertNil(store.entries.first { $0.name == "Before" }?.mealType, "Turning meal types on never rewrites old food")

        var picked = EntryDraft(name: "Cake", calories: 400, timestamp: at(12, 45)); picked.mealType = "dessert"
        XCTAssertTrue(store.add([picked]))
        XCTAssertEqual(store.entries.first { $0.name == "Cake" }?.mealType, "dessert")

        XCTAssertTrue(store.saveMealSettings(MealSettings(tracks: true, byTime: false)))
        XCTAssertTrue(store.add([EntryDraft(name: "Apple", calories: 95, timestamp: at(12))]))
        XCTAssertNil(store.entries.first { $0.name == "Apple" }?.mealType, "Asking without a pick leaves it unspecified")
    }

    func testEditingKeepsTheMealEvenWhileMealTypesAreOff() throws {
        let store = try makeStore(MealSettings(tracks: true))
        XCTAssertTrue(store.add([EntryDraft(name: "Soup", calories: 200, timestamp: at(12))]))
        XCTAssertTrue(store.saveMealSettings(MealSettings(tracks: false)))
        var draft = EntryDraft(try XCTUnwrap(store.entries.first))
        XCTAssertEqual(draft.mealType, "lunch")
        draft.changeCalories(250)
        XCTAssertTrue(store.update(draft))
        XCTAssertEqual(store.entries.first?.mealType, "lunch", "Turning meal types back on finds it where it was")

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(store.setMealType("dinner", for: entry))
        XCTAssertEqual(store.entries.first?.mealType, "dinner")
        XCTAssertTrue(store.setMealType(nil, for: entry))
        XCTAssertNil(store.entries.first?.mealType)
    }

    func testCopiesToLogAgainDropTheOriginalMeal() throws {
        let store = try makeStore(MealSettings(tracks: true))
        var coffee = EntryDraft(name: "Coffee", calories: 5, timestamp: at(7)); coffee.barcode = "0123456789012"
        XCTAssertTrue(store.add([coffee]))
        XCTAssertTrue(store.add([EntryDraft(name: "Coffee", calories: 5, timestamp: at(7, 30))]))
        XCTAssertEqual(store.entries.first?.mealType, "breakfast")

        // Quick Add, search history, and Siri's foods logged before all come from history.
        let foods = FoodHistory.foods(store.entries)
        XCTAssertFalse(foods.isEmpty)
        XCTAssertTrue(foods.allSatisfy { $0.draft.mealType == nil })
        let suggestions = FoodHistory.suggestions(entries: store.entries, date: at(15, daysAgo: 0), pinnedIDs: [], hiddenIDs: [])
        XCTAssertTrue(suggestions.allSatisfy { $0.draft.mealType == nil })

        // A barcode remembers the product, not the meal it was eaten at.
        XCTAssertNil(store.localBarcode("0123456789012")?.mealType)

        // Saved meals are templates; built from a day's log they don't keep its meals.
        XCTAssertTrue(store.saveMeal(nil, name: "Morning", items: store.entries.map(EntryDraft.init)))
        let meal = try XCTUnwrap(store.meals.first)
        XCTAssertTrue(meal.items.allSatisfy { $0.mealType == nil })
        XCTAssertTrue(store.addMeal(meal, date: at(12, 15)))
        XCTAssertEqual(store.entries.filter { $0.mealTemplateID == meal.id }.map(\.mealType), ["lunch", "lunch"])
        XCTAssertTrue(store.addMeal(meal, date: at(12, 20), mealType: "dessert"))
        XCTAssertEqual(store.entries.filter { $0.mealTemplateID == meal.id }.filter { $0.mealType == "dessert" }.count, 2)

        // Undoing a delete puts the food back under its meal.
        let entry = try XCTUnwrap(store.entries.first { $0.mealType == "breakfast" })
        let id = entry.id
        store.delete(entry)
        store.undo()
        XCTAssertEqual(store.entries.first { $0.id == id }?.mealType, "breakfast")
    }

    func testNewMealNamesFollowMealTypesWhenOn() {
        XCTAssertEqual(MealRoute.suggestedName(existing: [], at: at(10)), "Breakfast", "Off: the usual time-of-day names")
        XCTAssertEqual(MealRoute.suggestedName(existing: [], at: at(10), mealTypes: MealSettings(tracks: true)), "Morning Snack")
        XCTAssertEqual(MealRoute.suggestedName(existing: ["Morning Snack"], at: at(10), mealTypes: MealSettings(tracks: true)), "Morning Snack 2")
        XCTAssertEqual(MealRoute.suggestedName(existing: [], at: at(4, 30), mealTypes: MealSettings(tracks: true)), "Breakfast",
                       "Outside every meal's time falls back to the usual name")
    }

    // MARK: Editing the list

    func testSavingSlotsNewTypesByTimeAndValidates() {
        let settings = MealSettings(tracks: true)
        let early = MealType(id: "early", name: "Early Bird", time: MealTime(start: 4 * 60, end: 5 * 60))
        XCTAssertEqual(settings.saving(early).types.first?.id, "early", "4 AM starts the day")
        let late = MealType(id: "late", name: "Second Dessert")
        XCTAssertEqual(settings.saving(late).types.last?.id, "late", "No time goes last")

        var renamed = settings.types[0]; renamed.name = "First Meal"
        let saved = settings.saving(renamed)
        XCTAssertEqual(saved.types.count, settings.types.count)
        XCTAssertEqual(saved.types[0].name, "First Meal")
        XCTAssertEqual(saved.types[0].id, "breakfast", "Renaming keeps the id logged food points to")

        XCTAssertEqual(settings.conflict(with: MealTime(start: 13 * 60, end: 15 * 60), excluding: nil)?.id, "lunch")
        XCTAssertNil(settings.conflict(with: MealTime(start: 11 * 60, end: 14 * 60), excluding: "lunch"), "A type doesn't conflict with itself")
        XCTAssertNil(settings.conflict(with: MealTime(start: 4 * 60, end: 5 * 60), excluding: nil))
        XCTAssertEqual(settings.duplicate(named: " lunch ", excluding: nil)?.id, "lunch")
        XCTAssertNil(settings.duplicate(named: "Lunch", excluding: "lunch"))
        XCTAssertNil(settings.removing("lunch", inUse: true).duplicate(named: "Lunch", excluding: nil), "A removed name can be used again")
    }

    func testOverlappingANeighborAtOneEndOffersToShortenIt() throws {
        let settings = MealSettings(tracks: true)
        let snack = try XCTUnwrap(settings.type(id: "afternoonSnack"))
        // Lunch running to 3 PM pushes the afternoon snack back to 3.
        XCTAssertEqual(settings.trimmedTime(of: snack, avoiding: MealTime(start: 11 * 60, end: 15 * 60)), MealTime(start: 15 * 60, end: 16 * 60))
        // Dinner starting at 3 PM pulls the snack's end in.
        XCTAssertEqual(settings.trimmedTime(of: snack, avoiding: MealTime(start: 15 * 60, end: 20 * 60)), MealTime(start: 14 * 60, end: 15 * 60))
        XCTAssertNil(settings.trimmedTime(of: snack, avoiding: MealTime(start: 13 * 60, end: 17 * 60)), "Covering it entirely can't shorten it")
        XCTAssertNil(settings.trimmedTime(of: snack, avoiding: MealTime(start: 14 * 60 + 30, end: 15 * 60)), "Inside it would split it")
        XCTAssertNil(settings.trimmedTime(of: snack, avoiding: MealTime(start: 16 * 60, end: 17 * 60)), "No overlap, nothing to shorten")
        let evening = try XCTUnwrap(settings.type(id: "eveningSnack"))
        XCTAssertEqual(settings.trimmedTime(of: evening, avoiding: MealTime(start: 3 * 60, end: 5 * 60)), MealTime(start: 20 * 60, end: 3 * 60),
                       "Works across midnight")
        let fixed = settings.saving(MealType(id: "afternoonSnack", name: "Afternoon Snack", time: MealTime(start: 15 * 60, end: 16 * 60)))
        XCTAssertNil(fixed.conflict(with: MealTime(start: 11 * 60, end: 15 * 60), excluding: "lunch"))
    }

    func testMovingReordersVisibleTypesAndKeepsRemovedOnes() {
        let settings = MealSettings(tracks: true).removing("dessert", inUse: true)
        let moved = settings.moving(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(moved.visibleTypes.map(\.id), ["morningSnack", "lunch", "breakfast", "afternoonSnack", "dinner", "eveningSnack"])
        XCTAssertEqual(moved.types.last?.id, "dessert")
        XCTAssertEqual(moved.types.count, settings.types.count)
    }

    // MARK: Storage

    func testSettingsDecodeWithMissingFields() throws {
        XCTAssertEqual(MealSettings.decode(nil), MealSettings())
        XCTAssertFalse(MealSettings.decode(nil).tracks, "Off until someone turns it on")
        XCTAssertEqual(MealSettings.decode(Data("{}".utf8)), MealSettings())
        let json = #"{"tracks":true,"types":[{"id":"x","name":"Brunch","time":{"start":600,"end":720}},{"id":"y","name":"Later","future":1}],"future":"ignored"}"#
        let decoded = MealSettings.decode(Data(json.utf8))
        XCTAssertTrue(decoded.tracks)
        XCTAssertTrue(decoded.byTime)
        XCTAssertEqual(decoded.types.map(\.name), ["Brunch", "Later"])
        XCTAssertEqual(decoded.types[0].time, MealTime(start: 600, end: 720))
        XCTAssertFalse(decoded.types[1].removed)
        let roundTrip = MealSettings.decode(MealSettings(tracks: true, byTime: false).removing("lunch", inUse: true).encoded)
        XCTAssertEqual(roundTrip, MealSettings(tracks: true, byTime: false).removing("lunch", inUse: true))
    }

    func testSettingsLiveOnTheSyncedProfile() throws {
        let store = try makeStore()
        XCTAssertNil(store.profile?.mealSettingsData, "Nothing is stored until meal types are set up")
        XCTAssertTrue(store.saveMealSettings(MealSettings(tracks: true, byTime: false)))
        let reopened = AppStore(container: store.container, publishesWidget: false, persistsUsage: false, persistsFoodDefaults: false)
        XCTAssertEqual(reopened.mealSettings, MealSettings(tracks: true, byTime: false))
    }

    func testDraftsWithoutMealTypeStillDecode() throws {
        let legacy = try JSONSerialization.data(withJSONObject: ["name": "Old", "calories": 100, "timestamp": 0, "servings": 1, "perServing": 100,
                                                                  "servingDescription": "", "source": "manual", "order": 0, "id": UUID().uuidString])
        XCTAssertNil(try JSONDecoder().decode(EntryDraft.self, from: legacy).mealType)
    }

    // MARK: Home sections

    func testSectionsFollowTheMealListWithOtherLast() {
        struct Food { let name: String; let meal: String? }
        let settings = MealSettings(tracks: true).removing("dessert", inUse: true)
        let foods = [Food(name: "a", meal: "dinner"), Food(name: "b", meal: nil), Food(name: "c", meal: "breakfast"),
                     Food(name: "d", meal: "dessert"), Food(name: "e", meal: "unknown"), Food(name: "f", meal: "breakfast")]
        let groups = MealSections.group(foods, settings: settings, mealType: \.meal)
        XCTAssertEqual(groups?.map(\.id), ["breakfast", "dinner", "dessert", "none"])
        XCTAssertEqual(groups?.first?.items.map(\.name), ["c", "f"], "Keeps the day's order within a meal")
        XCTAssertEqual(groups?.last?.items.map(\.name), ["b", "e"])
        XCTAssertEqual(groups?.last?.title, "Other")
        XCTAssertEqual(groups?[2].title, "Dessert", "A removed type still names its food")
    }

    func testDaysWithoutMealsShowAsOneList() {
        struct Food { let meal: String? }
        let foods = [Food(meal: nil), Food(meal: nil)]
        XCTAssertNil(MealSections.group(foods, settings: MealSettings(tracks: true), mealType: \.meal))
        XCTAssertNil(MealSections.group([Food(meal: "lunch")], settings: MealSettings(tracks: false), mealType: \.meal),
                     "Meal types off shows no meals at all")
        XCTAssertNil(MealSections.group([Food](), settings: MealSettings(tracks: true), mealType: \.meal))
    }

    // MARK: Upgrade

    func testUpgradeFromStoreBeforeMealTypesKeepsEverything() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Upgrade.store")
        let oldSchema = Schema([BeforeMealTypes.UserProfile.self, BeforeMealTypes.DailyGoal.self, BeforeMealTypes.CalorieEntry.self,
                                BeforeMealTypes.SavedMeal.self, BeforeMealTypes.BarcodeFood.self])
        try autoreleasepool {
            let config = ModelConfiguration("Upgrade", schema: oldSchema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: oldSchema, configurations: [config])
            let context = ModelContext(container)
            let draft = EntryDraft(name: "Before meal types", calories: 325, timestamp: at(12))
            let profile = BeforeMealTypes.UserProfile(goal: 1800)
            profile.macroGoalsData = MacroNutrients(protein: 120).encoded
            context.insert(profile)
            context.insert(BeforeMealTypes.CalorieEntry(draft: draft))
            context.insert(BeforeMealTypes.SavedMeal(name: "Existing meal", items: [draft]))
            context.insert(BeforeMealTypes.BarcodeFood(barcode: "123", draft: draft))
            context.insert(BeforeMealTypes.DailyGoal(day: Day.key(Date()), goal: 1800))
            try context.save()
        }
        let config = ModelConfiguration("Upgrade", schema: Persistence.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Persistence.schema, configurations: [config])
        let store = AppStore(container: container, publishesWidget: false, persistsUsage: false, persistsFoodDefaults: false)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.entries.first?.mealType, "Existing food is unspecified")
        XCTAssertEqual(store.goal(Date()), 1800)
        XCTAssertEqual(store.macroGoals.protein, 120)
        XCTAssertEqual(store.mealSettings, MealSettings(), "Meal types start off")
        XCTAssertEqual(store.meals.first?.items.first?.name, "Before meal types")
        XCTAssertEqual(store.barcodes.first?.draft?.calories, 325)
        XCTAssertNil(MealSections.group(store.entries, settings: MealSettings(tracks: true, byTime: false)), "Old days keep their plain list")
        XCTAssertNotNil(MealSections.group(store.entries, settings: MealSettings(tracks: true)), "By time of day, old food groups by its time")

        XCTAssertTrue(store.saveMealSettings(MealSettings(tracks: true)))
        XCTAssertTrue(store.add([EntryDraft(name: "After", calories: 100, timestamp: at(18))]))
        XCTAssertEqual(store.entries.first { $0.name == "After" }?.mealType, "dinner")
        XCTAssertEqual(store.goal(Date()), 1800)
    }
}

/// The store as it was before meal types (1.0.4), to prove the additive upgrade keeps every record.
private enum BeforeMealTypes {
@Model final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var tracksMacros: Bool = true
    var macroGoalsData: Data?
    var currentDailyGoal: Double = 2100
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(name: String = "", goal: Double) { self.name = name; currentDailyGoal = goal }
}

@Model final class DailyGoal {
    var id: UUID = UUID()
    var day: String = ""
    var macroGoalsData: Data?
    var calorieGoal: Double = 2100
    var updatedAt: Date = Date()
    init(day: String, goal: Double) { self.day = day; calorieGoal = goal }
}

@Model final class CalorieEntry {
    var id: UUID = UUID()
    var name: String = ""
    var totalCalories: Double = 0
    var timestamp: Date = Date()
    var servings: Double = 1
    var macrosPerServingData: Data?
    var caloriesPerServing: Double = 0
    var servingDescription: String = ""
    var sourceType: String = "manual"
    var externalID: String?
    var barcode: String?
    var mealTemplateID: UUID?
    var componentOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(draft: EntryDraft) {
        name = draft.name; totalCalories = draft.calories; timestamp = draft.timestamp
        servings = draft.servings; caloriesPerServing = draft.perServing; sourceType = draft.source
    }
}

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
}

@Model final class BarcodeFood {
    var id: UUID = UUID()
    var barcode: String = ""
    var payload: Data = Data()
    var updatedAt: Date = Date()
    init(barcode: String, draft: EntryDraft) {
        self.barcode = barcode; payload = (try? JSONEncoder().encode(draft)) ?? Data()
    }
}
}
