import Foundation
import SwiftData

@Model final class UserProfile {
    var id: UUID = UUID()
    var name: String = "" // Retained for compatibility with existing stores; no longer collected.
    var tracksMacros: Bool = true
    var macroGoalsData: Data?
    // Zero represents no goal, preserving the existing local/CloudKit schema.
    var currentDailyGoal: Double = 2100
    /// Meal types and their times (`MealSettings`), synced with the diary. Nil means meal types were never set up.
    var mealSettingsData: Data?
    /// Progress settings (`ProgressSettings`: week start, on-target rule, chart ranges), synced with the diary.
    /// Nil until changed on any device. Added October 8, 2026; a new CloudKit field.
    var progressSettingsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(name: String = "", goal: Double) { self.name = name; currentDailyGoal = goal }
    var dailyGoal: Double? { currentDailyGoal > 0 ? currentDailyGoal : nil }
}

@Model final class DailyGoal {
    var id: UUID = UUID()
    var day: String = ""
    var macroGoalsData: Data?
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
    var macrosPerServingData: Data?
    var caloriesPerServing: Double = 0
    var servingDescription: String = ""
    var sourceType: String = "manual"
    var externalID: String?
    var barcode: String?
    var mealTemplateID: UUID?
    var componentOrder: Int = 0
    /// The `MealType` id this food was logged under (Breakfast, Lunch…). Nil is "unspecified": everything
    /// logged before meal types existed, while they're off, or outside every meal's time.
    var mealType: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(draft: EntryDraft) { apply(draft) }
    func apply(_ draft: EntryDraft) {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        totalCalories = draft.calories.rounded(); timestamp = draft.timestamp
        macrosPerServingData = draft.macrosPerServing?.encoded
        servings = draft.servings; caloriesPerServing = draft.perServing.rounded()
        servingDescription = draft.servingDescription; externalID = draft.externalID
        barcode = draft.barcode; sourceType = draft.source
        mealTemplateID = draft.mealID; componentOrder = draft.order; mealType = draft.mealType; updatedAt = Date()
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
    /// How many servings the meal's recipe makes; its stored components are one of them.
    var recipeServings: Int { RecipeServings.count(of: items) }
    /// The whole recipe, for editing.
    var recipeItems: [EntryDraft] { RecipeServings.whole(items) }
}

/// A saved meal can be a whole recipe (a family pot) that makes several servings. Its components are stored as one
/// serving's share, so adding the meal, its calories, search and Siri all see one serving, and older app versions
/// syncing the same meal still log the right amount. Each share remembers the count, which keeps the meal one
/// atomic Codable value (no new CloudKit field) and lets the editor rebuild the whole recipe exactly.
enum RecipeServings {
    static let range = 1...100

    /// One serving's share of each whole-recipe component. Values stay unrounded so `whole` restores them.
    static func share(_ items: [EntryDraft], servings: Int) -> [EntryDraft] {
        let count = min(max(servings, range.lowerBound), range.upperBound)
        return items.map { item in
            var share = item
            share.recipeServings = nil
            guard count > 1 else { return share }
            share.calories = item.calories / Double(count)
            share.servings = item.servings / Double(count)
            share.recipeServings = count
            return share
        }
    }

    /// The whole recipe again: each share multiplied back by its serving count.
    static func whole(_ items: [EntryDraft]) -> [EntryDraft] {
        items.map { item in
            var whole = item
            whole.recipeServings = nil
            guard let count = item.recipeServings, count > 1 else { return whole }
            whole.calories = (item.calories * Double(count)).rounded()
            // Trim floating-point noise (2 / 7 * 7) without losing typed fractions such as 1.25.
            whole.servings = (item.servings * Double(count) * 1_000_000).rounded() / 1_000_000
            return whole
        }
    }

    static func count(of items: [EntryDraft]) -> Int {
        min(max(items.compactMap(\.recipeServings).max() ?? 1, range.lowerBound), range.upperBound)
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
    var draft: EntryDraft? { try? JSONDecoder().decode(EntryDraft.self, from: payload) }
}

struct EntryDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var entryID: UUID?
    var name = ""
    var calories: Double = 0
    var timestamp = Date()
    var servings: Double = 1
    var macrosPerServing: MacroNutrients?
    var totalMacros: MacroNutrients? { macrosPerServing?.scaled(servings) }
    var perServing: Double = 0
    var servingDescription = ""
    var externalID: String?
    var barcode: String?
    var source = "manual"
    var mealID: UUID?
    var order = 0
    /// Only on a saved meal's components: this is one serving's share of a recipe that makes this many.
    /// Optional so older drafts decode without it; older app versions ignore it (see `RecipeServings`).
    var recipeServings: Int?
    /// The meal it's logged under. Only an entry being edited, or a meal someone just picked, carries one:
    /// copies made to log again drop it so `AppStore.add` assigns the meal for the new time.
    var mealType: String?
    // Keep following each typed digit until the user changes a serving field.
    // Optional so previously persisted drafts decode without this new field.
    private var derivesPerServingFromCalories: Bool? = nil
    init(name: String = "", calories: Double = 0, timestamp: Date = Date()) {
        self.name = name; self.calories = calories.rounded(); self.timestamp = timestamp; perServing = calories.rounded()
    }
    init(_ entry: CalorieEntry) {
        entryID = entry.id; name = entry.name; calories = entry.totalCalories.rounded()
        timestamp = entry.timestamp; servings = entry.servings; perServing = entry.caloriesPerServing.rounded()
        servingDescription = entry.servingDescription; externalID = entry.externalID; barcode = entry.barcode
        macrosPerServing = MacroNutrients.decode(entry.macrosPerServingData)
        source = entry.sourceType; mealID = entry.mealTemplateID; order = entry.componentOrder
        mealType = entry.mealType
    }
    var isValid: Bool {
        calories.isFinite && calories >= 0 && calories <= 100_000 && servings.isFinite && servings > 0
        && perServing.isFinite && perServing >= 0 && timestamp <= Date()
        && (macrosPerServing?.isValid ?? true) && (totalMacros?.isValid ?? true)
    }
    mutating func changeCalories(_ value: Double) {
        calories = value.rounded()
        if perServing == 0 { derivesPerServingFromCalories = true }
        if calories > 0, servings == 0 { servings = 1 }
        if derivesPerServingFromCalories == true {
            perServing = calories
        } else if perServing > 0 { servings = calories / perServing }
        if calories == 0 { servings = 0 }
    }
    mutating func changeServings(_ value: Double) {
        if value != servings { derivesPerServingFromCalories = false }
        servings = value
        if perServing > 0 { calories = (value * perServing).rounded() }
    }
    mutating func changePerServing(_ value: Double) {
        if value.rounded() != perServing { derivesPerServingFromCalories = false }
        perServing = value.rounded(); calories = (servings * perServing).rounded()
    }
    func scaled(_ factor: Double, at date: Date, meal: UUID, order: Int) -> EntryDraft {
        var copy = self; copy.id = UUID(); copy.entryID = nil
        copy.calories = (copy.calories * factor).rounded(); copy.perServing = copy.perServing.rounded(); copy.servings *= factor; copy.timestamp = date
        copy.mealID = meal; copy.order = order; copy.source = "savedMeal"; copy.recipeServings = nil; copy.mealType = nil
        return copy
    }
}

enum Day {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return String(format: "%02d-%04d-%02d-%02d", c.era ?? 1, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func loggingDate(_ selected: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(selected, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: selected) ?? selected
    }
    static func week(_ date: Date) -> Date { Calendar.current.dateInterval(of: .weekOfYear, for: date)!.start }
    /// "Breakfast", "Lunch", "Dinner", or "Snack" by time of day.
    static func mealName(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 4..<11: "Breakfast"
        case 11..<16: "Lunch"
        case 16..<21: "Dinner"
        default: "Snack"
        }
    }
}

extension Double {
    var calorieText: String { rounded().formatted(.number.precision(.fractionLength(0))) }
}

func normalizedFoodName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
}

extension CalorieEntry {
    var foodDisplayName: String {
        // Older Open Food Facts entries stored "company · product" together.
        guard externalID?.hasPrefix("openfoodfacts:") == true,
              let separator = name.range(of: " · ") else { return name }
        return String(name[separator.upperBound...])
    }
}
