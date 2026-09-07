import Foundation

struct CommonFood: Decodable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let calories: Double
    let serving: String
    var draft: EntryDraft {
        var draft = EntryDraft(name: name, calories: calories)
        draft.servingDescription = serving
        draft.externalID = "common:\(id)"
        draft.source = "common"
        return draft
    }
}

struct CommonFoodDefault: Codable, Equatable {
    var calories: Double
    var perServing: Double
    var servings: Double
    var servingDescription: String

    init(_ draft: EntryDraft) {
        calories = draft.calories
        perServing = draft.perServing
        servings = draft.servings
        servingDescription = draft.servingDescription
    }

    func applying(to input: EntryDraft) -> EntryDraft {
        var draft = input
        draft.calories = calories
        draft.perServing = perServing
        draft.servings = servings
        draft.servingDescription = servingDescription
        return draft
    }
}

enum CommonFoods {
    static func matching(_ name: String) -> CommonFood? {
        let normalized = normalizedFoodName(name)
        guard !normalized.isEmpty else { return nil }
        if let exact = indexedFoods.first(where: { $0.name == normalized }) { return exact.food }
        let aliases = indexedFoods.filter { $0.names.contains(normalized) }
        // Ambiguous aliases must never save a personal default to the wrong food.
        return aliases.count == 1 ? aliases[0].food : nil
    }
    private struct Catalog: Decodable { let foods: [CommonFood] }
    static let foods: [CommonFood] = {
        guard let url = Bundle.main.url(forResource: "CommonFoods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.foods
    }()
    private static let indexedFoods = foods.map { food in
        (food: food, name: normalizedFoodName(food.name),
         names: ([food.name] + food.aliases).map(normalizedFoodName))
    }
    static func search(_ query: String) -> [CommonFood] {
        let q = normalizedFoodName(query)
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        return indexedFoods.compactMap { item -> (food: CommonFood, rank: Int)? in
            let rank: Int
            if item.name == q { rank = 0 }
            else if item.names.contains(q) { rank = 1 }
            else if item.names.contains(where: { $0.hasPrefix(q) }) { rank = 2 }
            else if item.names.contains(where: { name in words.allSatisfy { name.contains($0) } }) { rank = 3 }
            else { return nil }
            return (item.food, rank)
        }.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.food.name < $1.food.name
        }.map(\.food)
    }
}

struct HistoricalFood: Identifiable {
    var id: String
    var draft: EntryDraft
    var uses: [CalorieEntry]
}

enum FoodHistory {
    static func foods(_ entries: [CalorieEntry]) -> [HistoricalFood] {
        let named = entries.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groups = Dictionary(grouping: named) { entry in
            entry.externalID.map { "external:\($0)" } ?? "name:\(normalizedFoodName(entry.name))"
        }
        return groups.map { key, values in
            let recent = values.sorted { $0.timestamp > $1.timestamp }
            // A recent repeated value wins; a single outlier doesn't redefine a food.
            let variants = Dictionary(grouping: Array(recent.prefix(20))) { ($0.totalCalories * 10).rounded() }
            let best = variants.values.max { a, b in
                func score(_ group: [CalorieEntry]) -> Double {
                    group.reduce(0) { $0 + 1 + exp(-Date().timeIntervalSince($1.timestamp) / (14 * 86_400)) }
                }
                if score(a) == score(b) { return a[0].timestamp < b[0].timestamp }
                return score(a) < score(b)
            }!.max { $0.timestamp < $1.timestamp }!
            var draft = EntryDraft(best); draft.entryID = nil; draft.source = "historical"
            return HistoricalFood(id: key, draft: draft, uses: recent)
        }
    }
    static func search(_ query: String, entries: [CalorieEntry]) -> [HistoricalFood] {
        let q = normalizedFoodName(query)
        return foods(entries).filter { normalizedFoodName($0.draft.name).contains(q) }.sorted {
            let a = normalizedFoodName($0.draft.name), b = normalizedFoodName($1.draft.name)
            if (a == q) != (b == q) { return a == q }
            if a.hasPrefix(q) != b.hasPrefix(q) { return a.hasPrefix(q) }
            return $0.uses[0].timestamp > $1.uses[0].timestamp
        }
    }
    static func suggestions(entries: [CalorieEntry], date: Date) -> [HistoricalFood] {
        let calendar = Calendar.current
        let eligible = entries.filter { $0.timestamp <= date }
        let latest = eligible.last(where: { !$0.name.isEmpty })
        var followers = Set<String>()
        if let latest {
            let previousName = normalizedFoodName(latest.name)
            var lastMatchingTime: Date?
            for entry in eligible {
                if let time = lastMatchingTime, entry.timestamp.timeIntervalSince(time) > 0, entry.timestamp.timeIntervalSince(time) < 3600 {
                    followers.insert(normalizedFoodName(entry.name))
                }
                if normalizedFoodName(entry.name) == previousName { lastMatchingTime = entry.timestamp }
            }
        }
        func score(_ food: HistoricalFood) -> Double {
            let frequency = log(Double(food.uses.count) + 1) * 2
            let recency = exp(-max(0, date.timeIntervalSince(food.uses[0].timestamp)) / (7 * 86_400)) * 3
            let hour = calendar.component(.hour, from: date)
            let time = food.uses.prefix(30).map { entry -> Double in
                let difference = abs(calendar.component(.hour, from: entry.timestamp) - hour)
                return exp(-Double(min(difference, 24 - difference)) / 2)
            }.reduce(0, +) / Double(min(food.uses.count, 30)) * 3
            let weekday = Double(food.uses.filter { calendar.component(.weekday, from: $0.timestamp) == calendar.component(.weekday, from: date) }.count) / Double(food.uses.count)
            let sequence: Double = followers.contains(normalizedFoodName(food.draft.name)) ? 1 : 0
            return frequency + recency + time + weekday + sequence
        }
        let scored: [(food: HistoricalFood, score: Double)] = foods(eligible).map { (food: $0, score: score($0)) }
        let ranked = scored.sorted { a, b in
            if a.score == b.score { return a.food.id < b.food.id }
            return a.score > b.score
        }
        return ranked.prefix(5).map { $0.food }
    }
}
