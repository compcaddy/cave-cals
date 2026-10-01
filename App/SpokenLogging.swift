import Foundation
import AppIntents

/// Reads typed or spoken shorthand for a manual entry: "300", "300 cals", "pizza 300", "pizza, 300 calories",
/// "300 calories of pizza". A bare trailing number must be at least 10 so "eggs 2" stays a food search.
enum QuickEntryText {
    struct Parsed: Equatable {
        var name: String
        var calories: Double
    }
    private static let number = #"(\d[\d,]*(?:\.\d+)?)"#
    private static let unit = #"(?:kcals?|k?cals?|calories|calorie)"#
    private static let caloriesOnly = pattern(#"^\#(number)\s*\#(unit)?$"#)
    private static let caloriesFirst = pattern(#"^\#(number)\s*\#(unit)\s+(?:(?:of|for)\s+)?(.+)$"#)
    private static let caloriesLast = pattern(#"^(.+?)[\s,:-]+(?:(?:that|with|for|at|of|is|was|about|around)\s+)*\#(number)\s*\#(unit)$"#)
    private static let bareNumberLast = pattern(#"^(.+?)[\s,:-]+\#(number)$"#)

    static func parse(_ text: String) -> Parsed? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        guard !clean.isEmpty, clean.count <= 200 else { return nil }
        if let groups = match(caloriesOnly, clean), let calories = amount(groups[0]) {
            return Parsed(name: "", calories: calories)
        }
        if let groups = match(caloriesFirst, clean), let calories = amount(groups[0]), let name = foodName(groups[1]) {
            return Parsed(name: name, calories: calories)
        }
        if let groups = match(caloriesLast, clean), let name = foodName(groups[0]), let calories = amount(groups[1]) {
            return Parsed(name: name, calories: calories)
        }
        if let groups = match(bareNumberLast, clean), let name = foodName(groups[0]),
           let calories = amount(groups[1]), calories >= 10 {
            return Parsed(name: name, calories: calories)
        }
        return nil
    }

    private static func pattern(_ value: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: value, options: [.caseInsensitive])
    }
    private static func match(_ expression: NSRegularExpression, _ text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let result = expression.firstMatch(in: text, range: range) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    private static func amount(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: "")),
              value.isFinite, value >= 0, value <= 100_000 else { return nil }
        return value.rounded()
    }
    private static func foodName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:-")))
        guard !normalizedFoodName(name).isEmpty, Double(name) == nil else { return nil }
        return name
    }
}

/// Logs what someone told Siri. Shorthand with calories and foods they've logged before are handled on the
/// iPhone for free; anything else is estimated like a voice log (one scan) and logged without a review step.
@MainActor enum SpokenFoodLogger {
    typealias Estimator = (_ text: String, _ regularLogCount: Int) async throws -> AIResult
    static let example = "“pizza, 300 calories”"

    static func log(_ text: String, store: AppStore, now: Date = Date(),
                    estimate: Estimator = { try await AIBackend.shared.describe(text: $0, regularLogCount: $1) }) async -> String {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return "I didn’t catch a food. Try something like \(example)." }
        store.refresh()
        if let parsed = QuickEntryText.parse(spoken) {
            var draft = EntryDraft(name: parsed.name, calories: parsed.calories, timestamp: now)
            draft.source = "manual"
            return save([draft], store: store, now: now)
        }
        if let meal = savedMeal(named: spoken, store: store) {
            guard store.addMeal(meal, date: now) else { return saveFailure }
            return confirmation(names: [meal.name], calories: meal.calories, store: store, now: now)
        }
        if let draft = knownFood(named: spoken, store: store, now: now) {
            return save([draft], store: store, now: now)
        }
        do {
            let result = try await estimate(spoken, store.regularLogCount)
            let drafts = result.drafts(at: now, source: "aiVoice")
            guard !drafts.isEmpty else {
                return "I couldn’t find a food in that. Try naming it with its calories, like \(example)."
            }
            return save(drafts, store: store, now: now)
        } catch let error as AIServiceError where error.code == "subscription_required" {
            return "Your free AI logs are used up. Say the calories too, like \(example), or open Cave Cals to upgrade."
        } catch {
            return "\(error.localizedDescription) You can also say the calories, like \(example)."
        }
    }

    /// "a banana", "my usual coffee" → the words that identify the food.
    static func foodWords(_ text: String) -> String {
        let fillers: Set<String> = ["a", "an", "one", "my", "some", "the", "usual"]
        var words = normalizedFoodName(text).split(separator: " ").map(String.init)
        while let first = words.first, fillers.contains(first), words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }

    private static func savedMeal(named text: String, store: AppStore) -> SavedMeal? {
        let words = foodWords(text)
        return store.meals.first { foodWords($0.name) == words }
    }

    private static func knownFood(named text: String, store: AppStore, now: Date) -> EntryDraft? {
        let words = foodWords(text)
        guard !words.isEmpty else { return nil }
        let history = FoodHistory.foods(store.entries)
            .filter { foodWords($0.draft.name) == words }
            .max { $0.uses.count < $1.uses.count }
        guard var draft = history?.draft ?? CommonFoods.matching(words)?.draft else { return nil }
        draft = store.applyingCommonDefault(to: draft)
        draft.entryID = nil; draft.timestamp = now
        return draft
    }

    private static let saveFailure = "Cave Cals couldn’t save that. Please try again in the app."

    private static func save(_ drafts: [EntryDraft], store: AppStore, now: Date) -> String {
        guard store.add(drafts) else { return saveFailure }
        let names = drafts.map { $0.name.isEmpty ? "\($0.calories.calorieText) calories" : $0.name }
        return confirmation(names: names, calories: drafts.reduce(0) { $0 + $1.calories.rounded() }, store: store, now: now,
                            namesIncludeCalories: drafts.count == 1 && drafts[0].name.isEmpty)
    }

    private static func confirmation(names: [String], calories: Double, store: AppStore, now: Date,
                                     namesIncludeCalories: Bool = false) -> String {
        let logged: String
        if namesIncludeCalories { logged = "Logged \(names[0])." }
        else if names.count == 1 { logged = "Logged \(names[0]), \(calories.calorieText) calories." }
        else { logged = "Logged \(names.count) foods, \(calories.calorieText) calories: \(names.formatted(.list(type: .and)))." }
        let total = store.total(now)
        guard let goal = store.goal(now) else { return "\(logged) \(total.calorieText) today." }
        let left = goal - total
        return "\(logged) \(total.calorieText) today, " + (left >= 0 ? "\(left.calorieText) left." : "\((-left).calorieText) over.")
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Say what you ate, like “two eggs and toast” or “pizza, 300 calories”.")
    static let openAppWhenRun = false

    @Parameter(title: "Food", requestValueDialog: IntentDialog("What did you eat?"))
    var food: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store: AppStore
        do { store = try Persistence.sharedStore() }
        catch { return .result(dialog: "Cave Cals couldn’t open your log. Please open the app and try again.") }
        let message = await SpokenFoodLogger.log(food, store: store)
        return .result(dialog: "\(message)")
    }
}
