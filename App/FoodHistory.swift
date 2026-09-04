import Foundation

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
