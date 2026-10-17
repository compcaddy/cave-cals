import Foundation

/// Grams for one serving. Nil means unknown; zero is a known zero.
struct MacroNutrients: Codable, Equatable, Sendable {
    var protein: Double?
    var totalCarbs: Double?
    var fiber: Double?
    var fat: Double?
    // Preserve estimate provenance independently when a user edits another nutrient.
    var estimatedProtein: Bool? = nil
    var estimatedTotalCarbs: Bool? = nil
    var estimatedFiber: Bool? = nil
    var estimatedFat: Bool? = nil

    var isValid: Bool {
        let validAmounts = [protein, totalCarbs, fiber, fat].allSatisfy {
            $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 100_000)
        }
        guard validAmounts else { return false }
        if let totalCarbs, let fiber { return fiber <= totalCarbs }
        return true
    }
    /// Unknown fiber is never treated as zero.
    var netCarbs: Double? {
        guard isValid, let totalCarbs, let fiber else { return nil }
        return totalCarbs - fiber
    }
    var estimatedNetCarbs: Bool { estimatedTotalCarbs == true || estimatedFiber == true }
    var isValidGoal: Bool {
        isValid && [protein, totalCarbs, fiber, fat].compactMap { $0 }.allSatisfy { $0 > 0 && $0 <= 9999 }
    }
    var hasValues: Bool { protein != nil || totalCarbs != nil || fiber != nil || fat != nil }
    var isComplete: Bool { protein != nil && totalCarbs != nil && fiber != nil && fat != nil }
    var hasEstimates: Bool { estimatedProtein == true || estimatedTotalCarbs == true || estimatedFiber == true || estimatedFat == true }
    func scaled(_ factor: Double) -> Self {
        var copy = self
        copy.protein = protein.map { $0 * factor }; copy.totalCarbs = totalCarbs.map { $0 * factor }; copy.fiber = fiber.map { $0 * factor }; copy.fat = fat.map { $0 * factor }
        return copy
    }
    func markedEstimated() -> Self {
        var copy = self
        copy.estimatedProtein = protein != nil; copy.estimatedTotalCarbs = totalCarbs != nil; copy.estimatedFiber = fiber != nil; copy.estimatedFat = fat != nil
        return copy
    }
    func fillingMissing(from other: Self) -> Self {
        var copy = self
        if protein == nil { copy.protein = other.protein; copy.estimatedProtein = other.estimatedProtein }
        if totalCarbs == nil { copy.totalCarbs = other.totalCarbs; copy.estimatedTotalCarbs = other.estimatedTotalCarbs }
        if fiber == nil { copy.fiber = other.fiber; copy.estimatedFiber = other.estimatedFiber }
        if fat == nil { copy.fat = other.fat; copy.estimatedFat = other.estimatedFat }
        return copy
    }
    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum MacroKind: String, CaseIterable, Identifiable {
    case protein, totalCarbs, fiber, fat
    static let primary: [Self] = [.protein, .totalCarbs, .fat]
    var id: String { rawValue }
    var title: String { switch self { case .protein: "Protein"; case .totalCarbs: "Carbs"; case .fiber: "Fiber"; case .fat: "Fat" } }
    var editorTitle: String { self == .totalCarbs ? "Carbohydrates" : title }
    var shortTitle: String { switch self { case .protein: "P"; case .totalCarbs: "C"; case .fiber: "Fiber"; case .fat: "F" } }
    var keyPath: WritableKeyPath<MacroNutrients, Double?> {
        switch self { case .protein: \.protein; case .totalCarbs: \.totalCarbs; case .fiber: \.fiber; case .fat: \.fat }
    }
    var estimateKeyPath: WritableKeyPath<MacroNutrients, Bool?> {
        switch self { case .protein: \.estimatedProtein; case .totalCarbs: \.estimatedTotalCarbs; case .fiber: \.estimatedFiber; case .fat: \.estimatedFat }
    }
}

struct MacroTotal {
    var grams: Double?
    var incomplete: Bool
    var estimated: Bool
    var text: String {
        guard let grams else { return "—" }
        return "\(estimated ? "≈" : "")\(grams.macroText)\(incomplete ? "+" : "")"
    }
}

struct MacroSummary {
    let values: [MacroNutrients?]
    init(_ drafts: [EntryDraft]) { values = drafts.map(\.totalMacros) }
    func total(_ kind: MacroKind) -> MacroTotal {
        let known = values.compactMap { $0?[keyPath: kind.keyPath] }
        return MacroTotal(grams: values.isEmpty ? 0 : known.isEmpty ? nil : known.reduce(0, +),
                          incomplete: known.count < values.count,
                          estimated: values.contains { $0?[keyPath: kind.estimateKeyPath] == true })
    }
    var compactText: String {
        MacroKind.primary.map { "\($0.shortTitle) \(total($0).text)" }.joined(separator: " · ") + " g"
    }
    var accessibilityText: String {
        MacroKind.primary.map { kind in
            let amount = total(kind)
            return "\(kind.title), \(amount.grams.map { "\($0.macroText) grams" } ?? "unknown")\(amount.incomplete ? ", incomplete" : "")\(amount.estimated ? ", estimated" : "")"
        }.joined(separator: "; ")
    }
    var incomplete: Bool { MacroKind.primary.contains { total($0).incomplete } }
}

extension Double {
    var macroText: String { formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
}

/// Fills blank macros on named foods by itself, so people tracking macros rarely see a "+" on Home (October 17,
/// 2026). Right after a food is saved, and over the last 30 days on opening, each blank protein, carb, fiber, or
/// fat is filled from the first source that has it:
/// 1. the same food logged before with macros, scaled by calories;
/// 2. the built-in food list, when the name (amounts like "2 oz" aside) clearly matches one, scaled by calories (≈);
/// 3. an AI estimate (≈), sent as `automatic`, which never counts toward scans or the AI budget.
/// Typed amounts are never replaced. Each food is tried once per name, calories, and servings, so a box someone
/// empties stays empty until the food itself changes. Bare calorie numbers have nothing to go on and stay blank.
@MainActor final class MacroAutoFill {
    typealias Estimator = @MainActor (EntryDraft) async throws -> MacroNutrients
    static let triedKey = "macroAutoFillTried.v1"
    static let lookback: TimeInterval = 30 * 86_400

    private weak var store: AppStore?
    private let estimate: Estimator
    private let preferences: UserDefaults
    /// Spacing between backfill requests, which keeps them under the server's per-minute cap. Fresh foods skip it.
    private let backfillPause: Duration
    /// Waiting for an AI estimate; fresh foods go to the front.
    private(set) var queue: [UUID] = []
    private var fresh = Set<UUID>()
    private var worker: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var failures = 0
    private var limitHits = 0
    private var reportedError = false
    /// Entry ID → the name, calories, and servings it was last tried with.
    private var tried: [String: String]

    init(store: AppStore, preferences: UserDefaults = .standard, backfillPause: Duration = .milliseconds(2500),
         estimate: Estimator? = nil) {
        self.store = store
        self.preferences = preferences
        self.backfillPause = backfillPause
        self.estimate = estimate ?? { try await AIBackend.shared.estimateMacros(for: $0, automatic: true) }
        tried = preferences.dictionary(forKey: Self.triedKey) as? [String: String] ?? [:]
    }

    /// UI tests and screenshots keep their blanks, unless a DEBUG UI test opts in with `--macro-autofill`.
    static var isAllowed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--macro-autofill") { return true }
        #endif
        return !arguments.contains { $0 == "--uitesting" || $0 == "--screenshots" }
    }

    /// A named food with calories and a blank protein, carbs, or fat (fiber alone doesn't show on Home).
    static func needsMacros(_ entry: CalorieEntry) -> Bool {
        guard entry.name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2, entry.totalCalories > 0 else { return false }
        let totals = MacroNutrients.decode(entry.macrosPerServingData)?.scaled(entry.servings)
        return MacroKind.primary.contains { totals?[keyPath: $0.keyPath] == nil }
    }
    static func signature(_ entry: CalorieEntry) -> String {
        "\(normalizedFoodName(entry.name))|\(entry.totalCalories.rounded())|\(entry.servings)|\(entry.servingDescription)"
    }

    // MARK: Matching names

    nonisolated private static let amountWords: Set<String> = [
        "a", "an", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "dozen", "half",
        "quarter", "couple", "few", "some", "of", "x", "oz", "ounce", "ounces", "fl", "g", "gram", "grams", "kg",
        "lb", "lbs", "pound", "pounds", "ml", "l", "liter", "liters", "cup", "cups", "c", "tbsp", "tablespoon",
        "tablespoons", "tsp", "teaspoon", "teaspoons", "slice", "slices", "piece", "pieces", "serving", "servings",
        "scoop", "scoops", "can", "cans", "bottle", "bottles", "glass", "glasses", "bowl", "bowls", "plate", "plates",
        "handful", "handfuls", "small", "medium", "large",
    ]
    /// The food's name without a leading amount: "2 oz cheddar cheese" → "cheddar cheese".
    nonisolated static func foodName(_ name: String) -> String {
        var words = normalizedFoodName(name).split(separator: " ").map(String.init)
        while let first = words.first, words.count > 1, first.allSatisfy(\.isNumber) || amountWords.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }
    /// A built-in food whose name or alias matches exactly (also without the amount, and singular).
    static func commonFood(named name: String) -> CommonFood? {
        let bare = foodName(name)
        var tries = [normalizedFoodName(name), bare]
        if bare.hasSuffix("es") { tries.append(String(bare.dropLast(2))) }
        if bare.hasSuffix("s") { tries.append(String(bare.dropLast())) }
        for candidate in tries where !candidate.isEmpty {
            if let food = CommonFoods.matching(candidate), food.calories > 0, food.macrosPerServing?.hasValues == true { return food }
        }
        return nil
    }

    // MARK: Local sources

    /// Foods already logged with macros, most recent first, by identity and by name.
    struct History {
        private var byFood: [String: [CalorieEntry]] = [:]
        private var byName: [String: [CalorieEntry]] = [:]
        init(_ entries: [CalorieEntry]) {
            for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) where entry.totalCalories > 0 {
                guard MacroNutrients.decode(entry.macrosPerServingData)?.hasValues == true else { continue }
                byFood[FoodHistory.foodID(for: entry), default: []].append(entry)
                let name = MacroAutoFill.foodName(entry.name)
                if !name.isEmpty { byName[name, default: []].append(entry) }
            }
        }
        /// The kinds asked for, from the most recent log of this food that has the most of them, scaled by calories.
        func macros(for entry: CalorieEntry, kinds: [MacroKind]) -> MacroNutrients? {
            let candidates = (byFood[FoodHistory.foodID(for: entry)] ?? []) + (byName[MacroAutoFill.foodName(entry.name)] ?? [])
            var best: (source: CalorieEntry, macros: MacroNutrients, count: Int)?
            for source in candidates where source.id != entry.id {
                guard let macros = MacroNutrients.decode(source.macrosPerServingData)?.scaled(source.servings) else { continue }
                let count = kinds.filter { macros[keyPath: $0.keyPath] != nil }.count
                if count > (best?.count ?? 0) { best = (source, macros, count) }
            }
            guard let best else { return nil }
            return MacroAutoFill.portion(of: best.macros, kinds: kinds, ratio: entry.totalCalories / best.source.totalCalories)
        }
    }

    /// `kinds` from `totals`, scaled and rounded to 0.1 g, keeping each one's estimate mark.
    nonisolated static func portion(of totals: MacroNutrients, kinds: [MacroKind], ratio: Double, estimated: Bool? = nil) -> MacroNutrients? {
        guard ratio.isFinite, ratio > 0 else { return nil }
        var result = MacroNutrients()
        for kind in kinds {
            guard let value = totals[keyPath: kind.keyPath] else { continue }
            result[keyPath: kind.keyPath] = (value * ratio * 10).rounded() / 10
            result[keyPath: kind.estimateKeyPath] = estimated ?? totals[keyPath: kind.estimateKeyPath]
        }
        return result.hasValues ? result : nil
    }

    static func blanks(_ entry: CalorieEntry) -> [MacroKind] {
        let totals = MacroNutrients.decode(entry.macrosPerServingData)?.scaled(entry.servings)
        return MacroKind.allCases.filter { totals?[keyPath: $0.keyPath] == nil }
    }

    /// Fills what history and the built-in list can, in one save. Returns the foods still needing an AI estimate.
    @discardableResult private func fillLocally(_ candidates: [CalorieEntry]) -> [UUID] {
        guard let store, !candidates.isEmpty else { return [] }
        let history = History(store.entries)
        var found: [UUID: MacroNutrients] = [:]
        var fromHistory = 0, fromList = 0
        for entry in candidates {
            var blanks = Self.blanks(entry)
            var totals = MacroNutrients()
            if let past = history.macros(for: entry, kinds: blanks) {
                totals = totals.fillingMissing(from: past); fromHistory += 1
                blanks = blanks.filter { totals[keyPath: $0.keyPath] == nil }
            }
            if !blanks.isEmpty, let food = Self.commonFood(named: entry.name), let macros = food.macrosPerServing,
               let listed = Self.portion(of: macros, kinds: blanks, ratio: entry.totalCalories / food.calories, estimated: true) {
                totals = totals.fillingMissing(from: listed); fromList += 1
            }
            if totals.hasValues { found[entry.id] = totals }
        }
        if !found.isEmpty, store.fillMissingMacros(found) > 0 {
            if fromHistory > 0 { UsageStats.shared.count("macroAutoFill.history", by: fromHistory) }
            if fromList > 0 { UsageStats.shared.count("macroAutoFill.builtIn", by: fromList) }
        }
        var remaining: [UUID] = []
        for id in candidates.map(\.id) {
            guard let entry = store.entries.first(where: { $0.id == id }) else { continue }
            if Self.needsMacros(entry) { remaining.append(id) } else { markTried(entry) }
        }
        return remaining
    }

    private func markTried(_ entry: CalorieEntry) {
        tried[entry.id.uuidString] = Self.signature(entry)
        preferences.set(tried, forKey: Self.triedKey)
    }
    private func untried(_ entry: CalorieEntry) -> Bool { tried[entry.id.uuidString] != Self.signature(entry) }

    // MARK: Triggers

    /// Just logged or edited: local sources now, then an AI estimate next in line.
    func consider(_ ids: [UUID]) {
        guard Self.isAllowed, let store, store.tracksMacros else { return }
        let wanted = Set(ids)
        let candidates = store.entries.filter { wanted.contains($0.id) && Self.needsMacros($0) && untried($0) }
        let remaining = fillLocally(candidates)
        guard !remaining.isEmpty else { return }
        queue.removeAll { remaining.contains($0) }
        queue.insert(contentsOf: remaining, at: 0)
        fresh.formUnion(remaining)
        startWorker()
    }

    /// On opening: foods from the last 30 days still blank and not tried yet (this is also the one-time backfill),
    /// newest first, behind anything just logged.
    func sweep(now: Date = Date()) {
        guard Self.isAllowed, let store, store.tracksMacros else { return }
        let since = now.addingTimeInterval(-Self.lookback)
        let recent = store.entries.filter { $0.timestamp >= since }
        let recentIDs = Set(recent.map(\.id.uuidString))
        if tried.keys.contains(where: { !recentIDs.contains($0) }) {
            tried = tried.filter { recentIDs.contains($0.key) }
            preferences.set(tried, forKey: Self.triedKey)
        }
        let candidates = recent.filter { Self.needsMacros($0) && untried($0) }.sorted { $0.timestamp > $1.timestamp }
        let queued = Set(queue)
        queue.append(contentsOf: fillLocally(candidates).filter { !queued.contains($0) })
        startWorker()
    }

    // MARK: AI estimates

    static func secondsUntilServerTomorrow(now: Date = Date()) -> Int {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let tomorrow = utc.startOfDay(for: now).addingTimeInterval(86_400)
        return max(60, Int(tomorrow.timeIntervalSince(now)) + 60)
    }
    /// Paused by a limit or failures; a sweep only queues until it resumes.
    var isPaused: Bool { resumeTask != nil }

    /// Tests: waits until the queue has been worked through (or paused).
    func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    private func startWorker() {
        guard worker == nil, resumeTask == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.work()
            self?.worker = nil
        }
    }
    private func resume(after delay: Duration) {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.resumeTask = nil
            self?.startWorker()
        }
    }

    private func work() async {
        while !queue.isEmpty {
            guard let store, store.tracksMacros else { queue.removeAll(); fresh.removeAll(); return }
            let id = queue.removeFirst()
            let isFresh = fresh.remove(id) != nil
            guard let entry = store.entries.first(where: { $0.id == id }), Self.needsMacros(entry), untried(entry) else { continue }
            // An answer for the same food logged on another day may cover this one now.
            guard !fillLocally([entry]).isEmpty, let current = store.entries.first(where: { $0.id == id }) else { continue }
            let snapshot = EntryDraft(current), signature = Self.signature(current)
            do {
                let estimate = try await estimate(snapshot)
                failures = 0; limitHits = 0
                if let latest = store.entries.first(where: { $0.id == id }), Self.signature(latest) == signature {
                    if estimate.hasValues, store.fillMissingMacros([id: estimate]) > 0 { UsageStats.shared.count("macroAutoFill.ai") }
                    markTried(latest)
                }
            } catch is CancellationError {
                return
            } catch let error as AIServiceError where error.code == "macro_autofill_limit" {
                // The daily safeguard (100 a person): stop until the server's day turns over (midnight UTC).
                queue.insert(id, at: 0); if isFresh { fresh.insert(id) }
                resume(after: .seconds(Self.secondsUntilServerTomorrow()))
                return
            } catch let error as AIServiceError where error.code == "usage_limit" {
                // The server's per-minute (or daily) cap: wait, then pick up where this left off.
                queue.insert(id, at: 0); if isFresh { fresh.insert(id) }
                limitHits += 1
                resume(after: limitHits >= 3 ? .seconds(3600) : .seconds(65))
                return
            } catch let error as AIServiceError where error.code == "invalid_estimate" {
                markTried(current)
            } catch {
                // Offline or unavailable: stop after a few in a row; the next opening (or ten minutes) tries again.
                failures += 1
                if !reportedError, !(error is URLError) { reportedError = true; UsageStats.shared.error(.macroEstimate, error) }
                if failures >= 3 {
                    queue.insert(id, at: 0); if isFresh { fresh.insert(id) }
                    resume(after: .seconds(600))
                    return
                }
            }
            if !isFresh, !queue.isEmpty, fresh.isEmpty { try? await Task.sleep(for: backfillPause) }
        }
    }
}
