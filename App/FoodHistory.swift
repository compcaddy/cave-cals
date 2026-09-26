import Foundation

struct CommonFood: Decodable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let calories: Double
    let serving: String
    var macrosPerServing: MacroNutrients?
    var draft: EntryDraft {
        var draft = EntryDraft(name: name, calories: calories)
        draft.servingDescription = serving
        draft.externalID = "common:\(id)"
        draft.source = "common"
        draft.macrosPerServing = macrosPerServing
        return draft
    }
}

struct CommonFoodDefault: Codable, Equatable {
    var macrosPerServing: MacroNutrients?
    var calories: Double
    var perServing: Double
    var servings: Double
    var servingDescription: String

    init(_ draft: EntryDraft) {
        macrosPerServing = draft.macrosPerServing
        calories = draft.calories
        perServing = draft.perServing
        servings = draft.servings
        servingDescription = draft.servingDescription
    }

    func applying(to input: EntryDraft) -> EntryDraft {
        var draft = input
        draft.macrosPerServing = macrosPerServing
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

struct SuggestionReplayMetrics: Equatable {
    var samples = 0
    var top1Hits = 0
    var top3Hits = 0
    var top5Hits = 0
    var reciprocalRankTotal = 0.0

    var top1Accuracy: Double { samples == 0 ? 0 : Double(top1Hits) / Double(samples) }
    var top3Accuracy: Double { samples == 0 ? 0 : Double(top3Hits) / Double(samples) }
    var top5Accuracy: Double { samples == 0 ? 0 : Double(top5Hits) / Double(samples) }
    var meanReciprocalRank: Double { samples == 0 ? 0 : reciprocalRankTotal / Double(samples) }
}

enum FoodHistory {
    private static let day: TimeInterval = 86_400
    private static let suggestionLimit = 10

    private static func key(for entry: CalorieEntry) -> String {
        entry.externalID.map { "external:\($0)" } ?? "name:\(normalizedFoodName(entry.name))"
    }

    /// The Quick Add identity of a logged entry (matches `HistoricalFood.id`).
    static func foodID(for entry: CalorieEntry) -> String { key(for: entry) }

    static func identifier(for draft: EntryDraft) -> String? {
        if let externalID = draft.externalID, !externalID.isEmpty { return "external:\(externalID)" }
        let name = normalizedFoodName(draft.name)
        return name.isEmpty ? nil : "name:\(name)"
    }

    static func foods(_ entries: [CalorieEntry]) -> [HistoricalFood] {
        let named = entries.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groups = Dictionary(grouping: named, by: key)
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
    static func search(_ query: String, entries: [CalorieEntry], date: Date = Date(), calendar: Calendar = .current) -> [HistoricalFood] {
        let q = normalizedFoodName(query)
        guard !q.isEmpty else { return [] }
        let candidates = foods(entries).filter { normalizedFoodName($0.draft.name).contains(q) }
        let histories = Dictionary(grouping: entries.filter { $0.timestamp <= date }, by: key)
        let contexts = Array(entries.filter { $0.timestamp <= date }.sorted { $0.timestamp > $1.timestamp }.prefix(3))
        let scored = candidates.map { food -> (food: HistoricalFood, textRank: Int, relevance: Double) in
            let name = normalizedFoodName(food.draft.name)
            let textRank = name == q ? 0 : (name.hasPrefix(q) ? 1 : 2)
            let uses = histories[food.id] ?? food.uses
            let habit = habitStrength(uses: uses, date: date, hasRecentHistory: false)
            let time = 0.25 + 2.75 * timePatternProbability(uses: uses, date: date, calendar: calendar, hasRecentHistory: false)
            let day = conditionalDayFactor(uses: uses, date: date, calendar: calendar)
            let session = sessionFactor(candidateKey: food.id, contexts: contexts, histories: histories, date: date, calendar: calendar)
            return (food, textRank, habit * time * day * session)
        }
        return scored.sorted {
            if $0.textRank != $1.textRank { return $0.textRank < $1.textRank }
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            return normalizedFoodName($0.food.draft.name) < normalizedFoodName($1.food.draft.name)
        }.map(\.food)
    }
    /// True when a food is usually logged more than once on the days it's eaten (two coffees most
    /// mornings) and today's count hasn't reached that usual number yet.
    static func expectsAnotherToday(foodID: String, entries: [CalorieEntry], date: Date, calendar: Calendar = .current) -> Bool {
        let uses = entries.filter { key(for: $0) == foodID && $0.timestamp <= date }
        let startOfToday = calendar.startOfDay(for: date)
        let loggedToday = uses.filter { $0.timestamp >= startOfToday }.count
        let counts = Dictionary(grouping: uses.filter { $0.timestamp < startOfToday }) { calendar.startOfDay(for: $0.timestamp) }
            .values.map(\.count).sorted()
        guard counts.count >= 3, counts.filter({ $0 > 1 }).count * 2 > counts.count else { return false }
        return loggedToday < counts[counts.count / 2]
    }
    static func suggestions(entries: [CalorieEntry], date: Date, calendar: Calendar = .current, pinnedIDs: [String] = [], hiddenIDs: Set<String> = []) -> [HistoricalFood] {
        let eligible = entries
            .filter { $0.timestamp <= date && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        guard !eligible.isEmpty else { return [] }

        let startOfToday = calendar.startOfDay(for: date)
        let establishedEntries = eligible.filter { $0.timestamp < startOfToday }
        // On the first day, use what little data exists. Once prior days exist, today's
        // entries are context rather than training data for the routine itself.
        let trainingEntries = establishedEntries.isEmpty ? eligible : establishedEntries
        let histories = Dictionary(grouping: trainingEntries, by: key)
        let recentDataCount = eligible.filter { date.timeIntervalSince($0.timestamp) <= 14 * day }.count
        let historySpan = date.timeIntervalSince(eligible.first!.timestamp)
        let hasRecentHistory = recentDataCount >= 10 && historySpan >= 7 * day
        let contexts = Array(eligible.reversed().prefix(3))

        let scored: [(food: HistoricalFood, score: Double)] = foods(eligible).map { food in
            let trainingUses = histories[food.id] ?? food.uses
            let habit = habitStrength(uses: trainingUses, date: date, hasRecentHistory: hasRecentHistory)
            let timeProbability = timePatternProbability(uses: trainingUses, date: date, calendar: calendar, hasRecentHistory: hasRecentHistory)
            let timeFactor = 0.15 + 3.85 * timeProbability
            let dayFactor = conditionalDayFactor(uses: trainingUses, date: date, calendar: calendar)
            let occurrence = occurrenceFactor(uses: food.uses, date: date, calendar: calendar)
            let session = sessionFactor(candidateKey: food.id, contexts: contexts, histories: histories, date: date, calendar: calendar)
            var contextual = food
            contextual.draft = contextualDraft(for: food, date: date, calendar: calendar)
            return (food: contextual, score: habit * timeFactor * dayFactor * occurrence * session)
        }
        let ranked = scored.sorted { a, b in
            if a.score == b.score { return a.food.id < b.food.id }
            return a.score > b.score
        }
        let foodsByID = Dictionary(uniqueKeysWithValues: scored.map { ($0.food.id, $0.food) })
        let pinned = pinnedIDs.filter { !hiddenIDs.contains($0) }.compactMap { foodsByID[$0] }
        let pinnedSet = Set(pinned.map(\.id))
        let unpinned = ranked.map(\.food).filter { !pinnedSet.contains($0.id) && !hiddenIDs.contains($0.id) }
        return Array((pinned + unpinned).prefix(suggestionLimit))
    }

    static func replayMetrics(entries: [CalorieEntry], maximumSamples: Int = 500, calendar: Calendar = .current) -> SuggestionReplayMetrics {
        let ordered = entries
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        guard ordered.count > 5, maximumSamples > 0 else { return SuggestionReplayMetrics() }
        let firstIndex = max(5, ordered.count - maximumSamples)
        var metrics = SuggestionReplayMetrics()
        for index in firstIndex..<ordered.count {
            let history = Array(ordered[..<index])
            let ranked = suggestions(entries: history, date: ordered[index].timestamp, calendar: calendar)
            guard let rank = ranked.firstIndex(where: { $0.id == key(for: ordered[index]) }) else {
                metrics.samples += 1
                continue
            }
            metrics.samples += 1
            if rank == 0 { metrics.top1Hits += 1 }
            if rank < 3 { metrics.top3Hits += 1 }
            if rank < 5 { metrics.top5Hits += 1 }
            metrics.reciprocalRankTotal += 1 / Double(rank + 1)
        }
        return metrics
    }

    private static func habitStrength(uses: [CalorieEntry], date: Date, hasRecentHistory: Bool) -> Double {
        let recentMass = uses.reduce(0.0) { total, entry in
            let age = max(0, date.timeIntervalSince(entry.timestamp))
            return total + (age <= 14 * day ? exp(-age / (7 * day)) : 0)
        }
        let establishedMass = uses.reduce(0.0) { total, entry in
            let age = max(0, date.timeIntervalSince(entry.timestamp))
            return total + exp(-age / (90 * day))
        }
        let recentWeight = hasRecentHistory ? 0.65 : 0.4
        return 0.45 + recentWeight * log1p(recentMass) + (1 - recentWeight) * log1p(establishedMass)
    }

    private static func timePatternProbability(uses: [CalorieEntry], date: Date, calendar: Calendar, hasRecentHistory: Bool) -> Double {
        let recent = uses.filter { date.timeIntervalSince($0.timestamp) <= 14 * day }
        let established = Array(uses.filter { date.timeIntervalSince($0.timestamp) <= 120 * day }.suffix(120))
        let longTerm = established.isEmpty ? Array(uses.suffix(120)) : established
        let recentValue = kernelTimeProbability(uses: recent, date: date, calendar: calendar)
        let establishedValue = kernelTimeProbability(uses: longTerm, date: date, calendar: calendar)
        guard !recent.isEmpty else { return establishedValue }
        let recentWeight = hasRecentHistory && recent.count >= 3 ? 0.65 : 0.4
        return recentWeight * recentValue + (1 - recentWeight) * establishedValue
    }

    private static func kernelTimeProbability(uses: [CalorieEntry], date: Date, calendar: Calendar) -> Double {
        guard !uses.isEmpty else { return 0 }
        let target = minuteOfDay(date, calendar: calendar)
        return uses.reduce(0.0) { total, entry in
            let distance = circularMinuteDistance(target, minuteOfDay(entry.timestamp, calendar: calendar))
            return total + exp(-0.5 * pow(distance / 75, 2))
        } / Double(uses.count)
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) * 60 + Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60
    }

    private static func circularMinuteDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let distance = abs(lhs - rhs)
        return min(distance, 1_440 - distance)
    }

    private static func conditionalDayFactor(uses: [CalorieEntry], date: Date, calendar: Calendar) -> Double {
        guard uses.count >= 6 else { return 1 }
        let counts = Dictionary(grouping: uses) { calendar.component(.weekday, from: $0.timestamp) }.mapValues(\.count)
        let current = calendar.component(.weekday, from: date)

        if uses.count >= 21 {
            let smoothed = (1...7).map { Double(counts[$0, default: 0] + 2) / Double(uses.count + 14) * 7 }
            if smoothed.max() ?? 1 >= 1.45, smoothed.min() ?? 1 <= 0.75 {
                return min(1.55, max(0.5, smoothed[current - 1]))
            }
        }

        let weekendDays: Set<Int> = [1, 7]
        let weekdayUses = (2...6).reduce(0) { $0 + counts[$1, default: 0] }
        let weekendUses = counts[1, default: 0] + counts[7, default: 0]
        let weekdayRate = (Double(weekdayUses) + 2.5) / 5
        let weekendRate = (Double(weekendUses) + 1) / 2
        let ratio = max(weekdayRate, weekendRate) / max(0.001, min(weekdayRate, weekendRate))
        guard ratio >= 1.8 else { return 1 }
        let overallRate = Double(uses.count + 3) / 7
        let currentRate = weekendDays.contains(current) ? weekendRate : weekdayRate
        return min(1.45, max(0.55, currentRate / overallRate))
    }

    private static func occurrenceFactor(uses: [CalorieEntry], date: Date, calendar: Calendar) -> Double {
        let today = calendar.startOfDay(for: date)
        let todayUses = uses.filter { calendar.isDate($0.timestamp, inSameDayAs: date) && $0.timestamp <= date }
        guard !todayUses.isEmpty else { return 1 }
        let previous = uses.filter { $0.timestamp < today }
        let days = Dictionary(grouping: previous) { calendar.startOfDay(for: $0.timestamp) }
        guard days.count >= 3 else { return 0.65 }

        let counts = days.values.map(\.count)
        let meanCount = Double(counts.reduce(0, +)) / Double(counts.count)
        let repeatDayRate = Double(counts.filter { $0 > 1 }.count) / Double(counts.count)
        if meanCount <= 1.25, repeatDayRate <= 0.2 {
            return 0.08
        }

        let remainingShare = max(0, meanCount - Double(todayUses.count)) / max(1, meanCount)
        let countFactor = 0.65 + 0.35 * min(1, remainingShare + 0.25)
        let gaps = days.values.flatMap { values -> [TimeInterval] in
            let ordered = values.sorted { $0.timestamp < $1.timestamp }
            return zip(ordered, ordered.dropFirst()).compactMap { first, second in
                let gap = second.timestamp.timeIntervalSince(first.timestamp)
                return gap > 0 && gap <= 18 * 3_600 ? gap : nil
            }
        }.sorted()
        guard let typicalGap = median(gaps),
              let last = todayUses.max(by: { $0.timestamp < $1.timestamp }) else {
            return min(1, max(0.35, countFactor * 0.8))
        }
        let progress = max(0, date.timeIntervalSince(last.timestamp)) / typicalGap
        let intervalFactor = 0.3 + 0.7 * min(1, progress)
        return min(1, max(0.18, countFactor * intervalFactor))
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    private static func sessionFactor(candidateKey: String, contexts: [CalorieEntry], histories: [String: [CalorieEntry]], date: Date, calendar: Calendar) -> Double {
        var signal = 0.0
        var normalizer = 0.0
        let positionWeights = [1.0, 0.7, 0.45]
        for (index, context) in contexts.enumerated() {
            let contextKey = key(for: context)
            guard contextKey != candidateKey else { continue }
            let elapsed = max(0, date.timeIntervalSince(context.timestamp))
            guard elapsed <= 3 * 3_600 else { continue }
            let positionWeight = positionWeights[min(index, positionWeights.count - 1)]
            normalizer += positionWeight
            let recency = exp(-elapsed / (30 * 60))
            let coOccurrence = coOccurrenceSignal(
                contextUses: histories[contextKey] ?? [],
                candidateUses: histories[candidateKey] ?? [],
                calendar: calendar
            )
            signal += positionWeight * recency * coOccurrence
        }
        guard normalizer > 0 else { return 1 }
        return 1 + 3.5 * signal / normalizer
    }

    private static func coOccurrenceSignal(contextUses: [CalorieEntry], candidateUses: [CalorieEntry], calendar: Calendar) -> Double {
        let contexts = Array(contextUses.suffix(120))
        let candidates = Array(candidateUses.suffix(120))
        guard !contexts.isEmpty, !candidates.isEmpty else { return 0 }
        let matches = contexts.reduce(0) { total, context in
            let matched = candidates.contains { candidate in
                calendar.isDate(candidate.timestamp, inSameDayAs: context.timestamp)
                    && abs(candidate.timestamp.timeIntervalSince(context.timestamp)) <= 30 * 60
            }
            return total + (matched ? 1 : 0)
        }
        guard matches > 0 else { return 0 }
        let probability = Double(matches + 1) / Double(contexts.count + 4)
        let confidence = Double(matches) / Double(matches + 2)
        return probability * confidence
    }

    private static func contextualDraft(for food: HistoricalFood, date: Date, calendar: Calendar) -> EntryDraft {
        let target = minuteOfDay(date, calendar: calendar)
        let candidates = Array(food.uses.filter { $0.timestamp <= date }.prefix(60))
        let groups = Dictionary(grouping: candidates) { $0.totalCalories.rounded() }
        guard let best = groups.values.max(by: { lhs, rhs in
            contextualVariantScore(lhs, target: target, date: date, calendar: calendar)
                < contextualVariantScore(rhs, target: target, date: date, calendar: calendar)
        }), best.count >= 2 else { return food.draft }
        let entry = best.max { lhs, rhs in
            contextualEntryWeight(lhs, target: target, date: date, calendar: calendar)
                < contextualEntryWeight(rhs, target: target, date: date, calendar: calendar)
        }!
        var draft = EntryDraft(entry)
        draft.entryID = nil
        draft.source = "historical"
        return draft
    }

    private static func contextualVariantScore(_ entries: [CalorieEntry], target: Double, date: Date, calendar: Calendar) -> Double {
        let confidence = min(1, Double(entries.count) / 2)
        return confidence * entries.reduce(0.0) { $0 + contextualEntryWeight($1, target: target, date: date, calendar: calendar) }
    }

    private static func contextualEntryWeight(_ entry: CalorieEntry, target: Double, date: Date, calendar: Calendar) -> Double {
        let distance = circularMinuteDistance(target, minuteOfDay(entry.timestamp, calendar: calendar))
        let timeWeight = 0.2 + 1.8 * exp(-0.5 * pow(distance / 90, 2))
        let age = max(0, date.timeIntervalSince(entry.timestamp))
        let recencyWeight = 0.35 + 0.65 * exp(-age / (60 * day))
        return timeWeight * recencyWeight
    }
}
