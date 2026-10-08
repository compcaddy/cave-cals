import SwiftUI
import Charts

// Progress → On-Target vs. Over Days (October 7, 2026; "Good Days" until October 8): what's different about days on
// target (by the person's `OnTargetRule`) compared with days over it, worked out on the iPhone, plus Cave Coach,
// which turns it into three tips with AI (Cave Cals+). In code, "good" means on target.
// See Documentation/Progress.md.

/// One logged food, as the habits comparison needs it.
struct HabitFood {
    let timestamp: Date
    let createdAt: Date
    let calories: Double
    let name: String
    /// For the whole entry; nil when unknown.
    let macros: MacroNutrients?
}

/// Parts of the day for comparing when calories are eaten.
enum HabitPeriod: String, CaseIterable, Identifiable {
    case morning, midday, evening, late
    var id: Self { self }
    var title: String {
        switch self { case .morning: "Morning"; case .midday: "Midday"; case .evening: "Evening"; case .late: "Late" }
    }
    var span: String {
        switch self { case .morning: "before 11 AM"; case .midday: "11 AM–4 PM"; case .evening: "4–8 PM"; case .late: "after 8 PM" }
    }
    /// For sentences: "between 11 AM and 4 PM".
    var phrase: String {
        switch self { case .morning: "before 11 AM"; case .midday: "between 11 AM and 4 PM"; case .evening: "between 4 and 8 PM"; case .late: "after 8 PM" }
    }
    static func of(hour: Int) -> Self { hour < 11 ? .morning : hour < 16 ? .midday : hour < 20 ? .evening : .late }
}

/// Complete past days with a calorie goal, split into on-target days (`good` here) and over days by the person's
/// `OnTargetRule`, and what sets them apart. Days under a within-percent range aren't compared, only counted. Timing only uses food logged on the day it belongs to (backfilled food carries the time it
/// was entered); a macro counts for a day only when every food that day has it.
struct HabitInsights {
    struct Day {
        let date: Date
        let calories: Double
        let goal: Double
        let outcome: OnTargetRule.Outcome
        var good: Bool { outcome == .onTarget }
        /// Minutes after midnight of the first and last food logged as it was eaten.
        let firstMinute: Int?
        let lastMinute: Int?
        let foods: Int
        /// Calories by part of the day, from food logged as it was eaten; nil when none was.
        let periods: [HabitPeriod: Double]?
        let macros: [MacroKind: Double]
        let names: Set<String>
    }
    struct Side {
        let days: Int
        let averageCalories: Double?
        let firstMinute: Int?
        let lastMinute: Int?
        let windowHours: Double?
        let foodsPerDay: Double?
        /// Average calories in each part of the day.
        let periods: [HabitPeriod: Double]
        /// Average grams on days with a value.
        let macros: [MacroKind: Double]
        /// Average share of calories (0–1).
        let macroShares: [MacroKind: Double]

        init(_ days: [Day]) {
            self.days = days.count
            averageCalories = ProgressStats(values: days.map(\.calories)).average
            firstMinute = HabitInsights.median(days.compactMap(\.firstMinute))
            lastMinute = HabitInsights.median(days.compactMap(\.lastMinute))
            let windows = days.compactMap { day in day.firstMinute.flatMap { first in day.lastMinute.map { Double($0 - first) / 60 } } }
            windowHours = HabitInsights.median(windows)
            foodsPerDay = ProgressStats(values: days.map { Double($0.foods) }).average
            let timed = days.compactMap(\.periods)
            periods = Dictionary(uniqueKeysWithValues: HabitPeriod.allCases.map { period in
                (period, ProgressStats(values: timed.map { $0[period] ?? 0 }).average ?? 0)
            })
            var macros: [MacroKind: Double] = [:], shares: [MacroKind: Double] = [:]
            for kind in MacroKind.primary {
                let known = days.filter { $0.macros[kind] != nil }
                macros[kind] = ProgressStats(values: known.compactMap { $0.macros[kind] }).average
                let perGram = kind == .fat ? 9.0 : 4.0
                shares[kind] = ProgressStats(values: known.filter { $0.calories > 0 }.map { min(1, ($0.macros[kind] ?? 0) * perGram / $0.calories) }).average
            }
            self.macros = macros
            macroShares = shares
        }
    }
    struct FoodLean: Identifiable {
        let name: String
        let goodShare: Double
        let overShare: Double
        var id: String { name }
        var lean: Double { overShare - goodShare }
    }
    struct WeekdayCount: Identifiable {
        let weekday: Int
        let good: Int
        let over: Int
        var id: Int { weekday }
    }
    struct Finding: Identifiable {
        let id: String
        let symbol: String
        let text: String
        let strength: Double
    }

    static let minimumDays = 3
    let range: ProgressTrendRange
    let rule: OnTargetRule
    /// Complete days under a within-percent range: left out of the comparison.
    let underDays: Int
    let good: Side
    let over: Side
    let goodFoods: [FoodLean]
    let overFoods: [FoodLean]
    let weekdays: [WeekdayCount]
    let currentStreak: Int
    let medianGoal: Double?
    let findings: [Finding]
    var enoughData: Bool { good.days >= Self.minimumDays && over.days >= Self.minimumDays }

    init(foods: [HabitFood], data: ProgressData, goal: (Date) -> Double?, range: ProgressTrendRange,
         rule: OnTargetRule = OnTargetRule()) {
        let calendar = data.dates.calendar
        self.range = range
        self.rule = rule
        let start = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: data.today) }
        let complete = data.completedTotalsByDay.filter { $0.key < data.today }
        let foodsByDay = Dictionary(grouping: foods, by: { calendar.startOfDay(for: $0.timestamp) })
        var spellings: [String: [String: Int]] = [:]

        var days: [Day] = []
        for (date, total) in complete where start.map({ date >= $0 }) ?? true {
            guard let goal = goal(date), goal > 0 else { continue }
            let logged = foodsByDay[date] ?? []
            let timed = logged.filter { calendar.isDate($0.createdAt, inSameDayAs: $0.timestamp) }
            let minutes = timed.map { calendar.component(.hour, from: $0.timestamp) * 60 + calendar.component(.minute, from: $0.timestamp) }
            var periods: [HabitPeriod: Double]?
            if !timed.isEmpty {
                var sums: [HabitPeriod: Double] = [:]
                for food in timed { sums[HabitPeriod.of(hour: calendar.component(.hour, from: food.timestamp)), default: 0] += max(0, food.calories.rounded()) }
                periods = sums
            }
            var macros: [MacroKind: Double] = [:]
            for kind in MacroKind.primary {
                let values = logged.compactMap { $0.macros?[keyPath: kind.keyPath] }
                if !logged.isEmpty, values.count == logged.count { macros[kind] = values.reduce(0, +) }
            }
            var names = Set<String>()
            for food in logged {
                let key = Self.normalized(food.name)
                guard !key.isEmpty else { continue }
                names.insert(key)
                spellings[key, default: [:]][food.name.trimmingCharacters(in: .whitespacesAndNewlines), default: 0] += 1
            }
            days.append(Day(date: date, calories: total, goal: goal, outcome: rule.outcome(calories: total, goal: goal),
                            firstMinute: minutes.min(), lastMinute: minutes.max(),
                            foods: logged.count, periods: periods, macros: macros, names: names))
        }
        underDays = days.filter { $0.outcome == .under }.count
        days.removeAll { $0.outcome == .under }
        let goodDays = days.filter(\.good), overDays = days.filter { !$0.good }
        good = Side(goodDays)
        over = Side(overDays)
        medianGoal = Self.median(days.map(\.goal))

        // Foods that lean toward one kind of day: on at least 3 days, and 15 points more common on one side.
        var leans: [FoodLean] = []
        if !goodDays.isEmpty, !overDays.isEmpty {
            let allNames = Set(days.flatMap(\.names))
            for key in allNames {
                let onGood = goodDays.filter { $0.names.contains(key) }.count, onOver = overDays.filter { $0.names.contains(key) }.count
                guard onGood + onOver >= 3 else { continue }
                let name = spellings[key]?.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? key
                leans.append(FoodLean(name: name, goodShare: Double(onGood) / Double(goodDays.count), overShare: Double(onOver) / Double(overDays.count)))
            }
        }
        goodFoods = Array(leans.filter { $0.lean <= -0.15 }.sorted { ($0.lean, $0.name) < ($1.lean, $1.name) }.prefix(4))
        overFoods = Array(leans.filter { $0.lean >= 0.15 }.sorted { ($0.lean, $1.name) > ($1.lean, $0.name) }.prefix(4))

        weekdays = (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let matching = days.filter { calendar.component(.weekday, from: $0.date) == weekday }
            return WeekdayCount(weekday: weekday, good: matching.filter(\.good).count, over: matching.filter { !$0.good }.count)
        }

        // On-target days in a row, ending yesterday (any range).
        var streak = 0, day = calendar.date(byAdding: .day, value: -1, to: data.today)!
        while let total = complete[day], let target = goal(day), target > 0, rule.outcome(calories: total, goal: target) == .onTarget {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        currentStreak = streak

        findings = Self.findings(good: good, over: over, goodFoods: goodFoods, overFoods: overFoods,
                                 weekdays: weekdays, calendar: calendar)
    }

    /// Plain-language differences, strongest first. Each needs a real gap so noise doesn't read as a habit.
    private static func findings(good: Side, over: Side, goodFoods: [FoodLean], overFoods: [FoodLean],
                                 weekdays: [WeekdayCount], calendar: Calendar) -> [Finding] {
        var found: [Finding] = []
        if let g = good.firstMinute, let o = over.firstMinute, abs(o - g) >= 30 {
            let text = o > g
                ? "On-target days start eating around \(time(g)), \(duration(o - g)) earlier than over days (\(time(o)))."
                : "Over days start earlier: first food around \(time(o)), vs \(time(g)) for on-target days."
            found.append(Finding(id: "start", symbol: "sunrise", text: text, strength: Double(abs(o - g)) / 60))
        }
        if let g = good.lastMinute, let o = over.lastMinute, abs(o - g) >= 30 {
            let text = o > g
                ? "Over days run later: last food around \(time(o)), vs \(time(g)) for on-target days."
                : "On-target days end later (\(time(g)) vs \(time(o))), so a later dinner isn't the problem."
            found.append(Finding(id: "end", symbol: "moon.stars", text: text, strength: Double(abs(o - g)) / 60))
        }
        if let g = good.windowHours, let o = over.windowHours, abs(o - g) >= 1 {
            found.append(Finding(id: "window", symbol: "clock",
                text: "Over days span \(hours(o)) of eating; on-target days, \(hours(g)).", strength: abs(o - g) / 1.5))
        }
        let extra = HabitPeriod.allCases.map { ($0, (over.periods[$0] ?? 0) - (good.periods[$0] ?? 0)) }.max { $0.1 < $1.1 }
        if let (period, amount) = extra, amount >= 150 {
            found.append(Finding(id: "period", symbol: "chart.bar",
                text: "Over days eat about \(amount.calorieText) more cals \(period.phrase) than on-target days.", strength: amount / 250))
        }
        let morning = (good.periods[.morning] ?? 0) - (over.periods[.morning] ?? 0)
        if morning >= 100 {
            found.append(Finding(id: "morning", symbol: "cup.and.saucer",
                text: "On-target days have a bigger start: \((good.periods[.morning] ?? 0).calorieText) cals before 11 AM vs \((over.periods[.morning] ?? 0).calorieText) on over days.",
                strength: morning / 200))
        }
        if let g = good.macroShares[.protein], let o = over.macroShares[.protein], g - o >= 0.03 {
            found.append(Finding(id: "protein", symbol: "fork.knife",
                text: "Protein makes up \(percent(g)) of calories for on-target days vs \(percent(o)) for over days.", strength: (g - o) * 25))
        }
        for (kind, symbol) in [(MacroKind.fat, "drop"), (.totalCarbs, "leaf")] {
            if let g = good.macroShares[kind], let o = over.macroShares[kind], o - g >= 0.04 {
                found.append(Finding(id: kind.rawValue, symbol: symbol,
                    text: "Over days get more of their calories from \(kind.title.lowercased()): \(percent(o)) vs \(percent(g)).", strength: (o - g) * 20))
            }
        }
        if let g = good.foodsPerDay, let o = over.foodsPerDay, o - g >= 1.5 {
            found.append(Finding(id: "foods", symbol: "list.bullet",
                text: "Over days have more foods logged: \(o.formatted(.number.precision(.fractionLength(0...1)))) vs \(g.formatted(.number.precision(.fractionLength(0...1)))). Extra snacks add up.",
                strength: (o - g) / 2))
        }
        if let food = overFoods.first {
            found.append(Finding(id: "overFood", symbol: "exclamationmark.circle",
                text: "\(food.name) shows up on \(percent(food.overShare)) of over days but \(percent(food.goodShare)) of on-target days.", strength: food.lean * 2))
        }
        if let food = goodFoods.first {
            found.append(Finding(id: "goodFood", symbol: "checkmark.circle",
                text: "\(food.name) shows up on \(percent(food.goodShare)) of on-target days but \(percent(food.overShare)) of over days.", strength: -food.lean * 2))
        }
        if let day = weekdays.filter({ $0.good + $0.over >= 3 && $0.over >= 2 })
            .max(by: { Double($0.over) / Double($0.good + $0.over) < Double($1.over) / Double($1.good + $1.over) }) {
            let share = Double(day.over) / Double(day.good + day.over)
            if share >= 0.6 {
                found.append(Finding(id: "weekday", symbol: "calendar",
                    text: "\(calendar.weekdaySymbols[day.weekday - 1])s go over most: \(day.over) of \(day.good + day.over).", strength: share * 1.5))
            }
        }
        return found.sorted { $0.strength > $1.strength }
    }

    static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func median<T: BinaryInteger>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    /// "8:10 AM"
    static func time(_ minute: Int) -> String {
        var components = DateComponents(); components.hour = minute / 60; components.minute = minute % 60
        return (Calendar.current.date(from: components) ?? .now).formatted(date: .omitted, time: .shortened)
    }
    /// "1 hr 20 min"
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
    static func hours(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(0...1)))) hours" }
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// What Cave Coach gets: this comparison, never diary entries. Nil values are sent as nulls.
    func coachPayload(calendar: Calendar = .current) -> [String: Any] {
        func value(_ number: Double?) -> Any { number.map { ($0 * 10).rounded() / 10 } ?? NSNull() }
        func side(_ side: Side) -> [String: Any] {
            [
                "days": side.days,
                "averageCalories": value(side.averageCalories),
                "firstFood": side.firstMinute.map(Self.time) ?? NSNull(),
                "lastFood": side.lastMinute.map(Self.time) ?? NSNull(),
                "eatingWindowHours": value(side.windowHours.map { min(24, $0) }),
                "foodsPerDay": value(side.foodsPerDay),
                "caloriesByTime": Dictionary(uniqueKeysWithValues: HabitPeriod.allCases.map { ($0.rawValue, value(side.periods[$0])) }),
                "macros": ["protein": value(side.macros[.protein]), "carbs": value(side.macros[.totalCarbs]), "fat": value(side.macros[.fat])],
            ]
        }
        func label(_ text: String) -> String {
            String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init).prefix(80))
                .trimmingCharacters(in: .whitespaces)
        }
        let foods: [[String: Any]] = (overFoods + goodFoods).compactMap { food in
            let name = label(food.name)
            guard !name.isEmpty else { return nil }
            return ["name": name, "goodShare": (food.goodShare * 100).rounded() / 100, "overShare": (food.overShare * 100).rounded() / 100]
        }
        return [
            "range": range.statName,
            "definition": "on target means " + rule.summary.replacingOccurrences(of: "your goal", with: "the daily calorie goal"),
            "underDays": underDays,
            "dailyGoal": value(medianGoal),
            "good": side(good),
            "over": side(over),
            "foods": Array(foods.prefix(20)),
            "weekdays": weekdays.map { ["day": calendar.weekdaySymbols[$0.weekday - 1], "goodDays": $0.good, "overDays": $0.over] },
            "currentStreak": currentStreak,
            "findings": findings.prefix(12).map { String($0.text.prefix(240)) },
        ]
    }
}

/// Cave Coach's three tips. Also reads the backend's earlier write-up (its "Try this" list becomes the tips), so
/// the app works before the backend that writes tips only is deployed.
struct CoachResult: Codable, Equatable {
    struct Tip: Codable, Equatable, Hashable {
        let title: String
        let detail: String
    }
    let tips: [Tip]

    init(tips: [Tip]) { self.tips = tips }
    private enum CodingKeys: String, CodingKey { case tips, tryThis }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tips = try container.decodeIfPresent([Tip].self, forKey: .tips) {
            self.tips = tips
        } else {
            tips = try container.decode([String].self, forKey: .tryThis).map { Tip(title: $0, detail: "") }
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tips, forKey: .tips)
    }
}

/// The last write-up, kept on this iPhone only so reopening Progress doesn't ask again.
struct CoachCache: Codable {
    let result: CoachResult
    let date: Date
    let range: String
    static let key = "caveCoach.v2"
    /// UI tests and screenshots keep it in memory, so runs never leave a write-up behind.
    @MainActor private static var memory: Self?
    private static var usesMemory: Bool {
        ProcessInfo.processInfo.arguments.contains { $0 == "--uitesting" || $0 == "--screenshots" }
    }
    @MainActor static func load() -> Self? {
        if usesMemory { return memory }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    @MainActor func save() {
        if Self.usesMemory { Self.memory = self; return }
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: Views

/// Progress → On-Target vs. Over Days.
struct ProgressHabitsCard: View {
    let data: ProgressData
    let foods: [HabitFood]
    let goal: (Date) -> Double?
    @Environment(AppStore.self) private var store
    @State private var showsAllFindings = false
    @State private var editingRule = false
    /// Synced with the other Progress settings.
    private var range: ProgressTrendRange { store.progressSettings.habitsRange }
    private var rule: OnTargetRule { store.progressSettings.onTarget }
    private static let goodColor = Color.caveOrange
    private static let overColor = Color(red: 0.55, green: 0.32, blue: 0.16)

    var body: some View {
        let habits = HabitInsights(foods: foods, data: data, goal: goal, range: range, rule: rule)
        VStack(alignment: .leading, spacing: 14) {
            Text("On-Target vs. Over Days").font(.cave(.title2)).bold()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("On target: \(rule.summary)")
                    .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("habitsRuleSummary")
                Spacer(minLength: 8)
                Button("Change") { editingRule = true }
                    .font(.cave(.subheadline)).foregroundStyle(Color.caveOrange)
                    .frame(minHeight: 44)
                    .hapticButtonStyle(.plain)
                    .accessibilityLabel("Change what counts as on target")
                    .accessibilityIdentifier("habitsChangeRule")
            }
            if habits.underDays > 0 {
                Text("\(habits.underDays) \(habits.underDays == 1 ? "day" : "days") under the range \(habits.underDays == 1 ? "isn't" : "aren't") compared.")
                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
                    .accessibilityIdentifier("habitsUnderDays")
            }
            Picker("Range", selection: Binding(get: { range }, set: { value in
                var settings = store.progressSettings
                settings.habitsRange = value
                store.saveProgressSettings(settings)
            })) {
                ForEach(ProgressTrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).hapticSelection(on: range)
            .accessibilityIdentifier("habitsRange")
            summary(habits)
            if habits.enoughData {
                findings(habits)
                periodChart(habits)
                typicalDay(habits)
                foodLists(habits)
                CaveCoachSection(habits: habits)
            } else {
                Text("Comparing needs at least \(HabitInsights.minimumDays) on-target days and \(HabitInsights.minimumDays) over days with a calorie goal in this range. So far: \(habits.good.days) on target, \(habits.over.days) over.")
                    .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("habitsNotEnough")
            }
        }
        .progressCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressHabits")
        .onChange(of: range) { _, new in
            showsAllFindings = false
            UsageStats.shared.event("progress.habits", ["range": new.statName])
        }
        .sheet(isPresented: $editingRule) { OnTargetRuleSheet(goal: store.goal(Date())) }
    }

    // MARK: Summary

    private func summary(_ habits: HabitInsights) -> some View {
        let total = habits.good.days + habits.over.days
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                tile("On-target days", count: habits.good.days, total: total, average: habits.good.averageCalories, color: Self.goodColor, id: "habitsGood")
                tile("Over days", count: habits.over.days, total: total, average: habits.over.averageCalories, color: Self.overColor, id: "habitsOver")
            }
            if habits.currentStreak > 0 {
                Label {
                    Text("\(habits.currentStreak) on-target \(habits.currentStreak == 1 ? "day" : "days") in a row")
                } icon: {
                    Image(systemName: "flame.fill").foregroundStyle(Color.caveOrange)
                }
                .font(.cave(.subheadline))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(habits.currentStreak) on-target \(habits.currentStreak == 1 ? "day" : "days") in a row")
                .accessibilityIdentifier("habitsStreak")
            }
        }
    }

    private func tile(_ title: String, count: Int, total: Int, average: Double?, color: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.cave(.caption)).foregroundStyle(Color.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)").font(.cave(.title)).foregroundStyle(color)
                if total > 0 {
                    Text("of \(total)").font(.cave(.caption)).foregroundStyle(Color.secondary)
                }
            }
            Text(average.map { "avg \($0.calorieText) cals" } ?? " ").font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count) of \(total)" + (average.map { ", average \($0.calorieText) calories" } ?? ""))
        .accessibilityIdentifier(id)
    }

    // MARK: Findings

    @ViewBuilder private func findings(_ habits: HabitInsights) -> some View {
        if habits.findings.isEmpty {
            Text("No clear differences yet. Your on-target and over days look alike so far.")
                .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("What's different").font(.cave(.headline))
                ForEach(showsAllFindings ? habits.findings : Array(habits.findings.prefix(4))) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.symbol).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.caveOrange).frame(width: 22)
                            .accessibilityHidden(true)
                        Text(finding.text).font(.cave(.subheadline)).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("habitFinding-\(finding.id)")
                }
                if habits.findings.count > 4 {
                    Button(showsAllFindings ? "Show fewer" : "Show all \(habits.findings.count)") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllFindings.toggle() }
                    }
                    .font(.cave(.subheadline)).foregroundStyle(Color.caveOrange)
                    .frame(minHeight: 44)
                    .hapticButtonStyle(.plain)
                    .accessibilityIdentifier("habitsShowAll")
                }
            }
        }
    }

    // MARK: Time of day

    private func periodChart(_ habits: HabitInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calories by time of day").font(.cave(.headline))
            Chart {
                ForEach(HabitPeriod.allCases) { period in
                    BarMark(x: .value("Time", period.title), y: .value("Calories", habits.good.periods[period] ?? 0))
                        .foregroundStyle(by: .value("Day", "On target"))
                        .position(by: .value("Day", "On target"))
                        .accessibilityLabel("\(period.title), on-target days")
                        .accessibilityValue("\((habits.good.periods[period] ?? 0).calorieText) calories")
                    BarMark(x: .value("Time", period.title), y: .value("Calories", habits.over.periods[period] ?? 0))
                        .foregroundStyle(by: .value("Day", "Over"))
                        .position(by: .value("Day", "Over"))
                        .accessibilityLabel("\(period.title), over days")
                        .accessibilityValue("\((habits.over.periods[period] ?? 0).calorieText) calories")
                }
            }
            .chartForegroundStyleScale(["On target": Self.goodColor, "Over": Self.overColor])
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 170)
            .accessibilityIdentifier("habitsPeriodChart")
            Text("Average per day. Morning is before 11 AM, midday until 4 PM, evening until 8 PM, late after. Food added on a later day is left out.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Typical day

    private func typicalRows(_ habits: HabitInsights) -> [(String, String, String)] {
        func time(_ minute: Int?) -> String { minute.map(HabitInsights.time) ?? "—" }
        func hours(_ value: Double?) -> String { value.map(HabitInsights.hours) ?? "—" }
        func count(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—" }
        func grams(_ value: Double?) -> String { value.map { "\($0.formatted(.number.precision(.fractionLength(0)))) g" } ?? "—" }
        let good = habits.good, over = habits.over
        var rows: [(String, String, String)] = []
        rows.append(("First food", time(good.firstMinute), time(over.firstMinute)))
        rows.append(("Last food", time(good.lastMinute), time(over.lastMinute)))
        rows.append(("Eating window", hours(good.windowHours), hours(over.windowHours)))
        rows.append(("Foods logged", count(good.foodsPerDay), count(over.foodsPerDay)))
        for kind in MacroKind.primary { rows.append((kind.title, grams(good.macros[kind]), grams(over.macros[kind]))) }
        return rows
    }

    private func typicalDay(_ habits: HabitInsights) -> some View {
        let rows = typicalRows(habits)
        return VStack(alignment: .leading, spacing: 6) {
            Text("A typical day").font(.cave(.headline))
            HStack {
                Spacer()
                Text("On target").frame(width: 92, alignment: .trailing).foregroundStyle(Self.goodColor)
                Text("Over").frame(width: 92, alignment: .trailing).foregroundStyle(Self.overColor)
            }
            .font(.cave(.caption))
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(Color.secondary)
                    Spacer(minLength: 8)
                    Text(row.1).frame(width: 92, alignment: .trailing)
                    Text(row.2).frame(width: 92, alignment: .trailing)
                }
                .font(.cave(.subheadline)).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.0): on-target days \(row.1), over days \(row.2)")
            }
            Text("Times are medians. Macros use days where every food has that macro.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habitsTypicalDay")
    }

    // MARK: Foods

    @ViewBuilder private func foodLists(_ habits: HabitInsights) -> some View {
        if !habits.goodFoods.isEmpty || !habits.overFoods.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !habits.goodFoods.isEmpty {
                    foodList("More common on target", habits.goodFoods, color: Self.goodColor, good: true)
                }
                if !habits.overFoods.isEmpty {
                    foodList("More common on over days", habits.overFoods, color: Self.overColor, good: false)
                }
                Text("Foods on at least 3 days, with a 15-point difference or more.")
                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
            }
        }
    }

    private func foodList(_ title: String, _ foods: [HabitInsights.FoodLean], color: Color, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.cave(.headline))
            ForEach(foods) { food in
                HStack(alignment: .firstTextBaseline) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(food.name).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(good ? "\(HabitInsights.percent(food.goodShare)) vs \(HabitInsights.percent(food.overShare))"
                              : "\(HabitInsights.percent(food.overShare)) vs \(HabitInsights.percent(food.goodShare))")
                        .foregroundStyle(Color.secondary)
                }
                .font(.cave(.subheadline))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(food.name): on \(HabitInsights.percent(food.goodShare)) of on-target days and \(HabitInsights.percent(food.overShare)) of over days")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(good ? "habitsGoodFoods" : "habitsOverFoods")
    }
}

/// Cave Coach (Cave Cals+): three tips for healthier eating habits from the comparison summary (never the diary).
/// "Get new tips" replaces them with three different ones. The last tips stay on this iPhone.
struct CaveCoachSection: View {
    let habits: HabitInsights
    @Environment(AppStore.self) private var store
    @State private var subscriptions = AISubscriptions()
    @State private var cached = CoachCache.load()
    @State private var asking = false
    @State private var error: String?
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.caveOrange)
                Text("Cave Coach").font(.cave(.title3)).bold()
                Spacer(minLength: 8)
                Text("Cave Cals+").font(.cave(.caption)).foregroundStyle(Color.secondary)
            }
            if let cached {
                tips(cached)
            } else {
                Text("Get three tips for healthier eating habits, based on your on-target and over days.")
                    .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await ask() } } label: {
                HStack(spacing: 6) {
                    if asking { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                    Text(asking ? "Coach thinking…" : cached == nil ? "Get coach tips" : "Get new tips")
                }
                .font(.cave(.subheadline)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.caveOrange, in: Capsule())
                .opacity(asking ? 0.8 : 1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .hapticButtonStyle(.plain)
            .disabled(asking)
            .accessibilityIdentifier("askCoach")
            if let error {
                Text(error).font(.cave(.footnote)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachError")
            }
            Text("AI suggestions, not medical advice.")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
        .padding(14)
        .background(Color.caveOrange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .navigationDestination(isPresented: $showPaywall) {
            AIUpgradePaywall(subscriptions: subscriptions, trigger: .coach,
                             onAccessGranted: { Task { await ask(checkedAccess: true) } },
                             onDismissRequested: { showPaywall = false })
        }
    }

    /// "Based on your last 30 days, here are 3 tips for healthier eating habits:" then the numbered tips.
    private func tips(_ cache: CoachCache) -> some View {
        let span = switch cache.range {
        case "30": "your last 30 days"
        case "90": "your last 90 days"
        default: "everything you’ve logged"
        }
        let count = cache.result.tips.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Based on \(span), here \(count == 1 ? "is 1 tip" : "are \(count) tips") for healthier eating habits:")
                .font(.cave(.subheadline)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachIntro")
            ForEach(Array(cache.result.tips.enumerated()), id: \.element) { index, tip in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.cave(.subheadline)).bold().foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.caveOrange, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).font(.cave(.subheadline)).bold().fixedSize(horizontal: false, vertical: true)
                        if !tip.detail.isEmpty {
                            Text(tip.detail).font(.cave(.subheadline)).foregroundStyle(Color.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coachTip-\(index)")
            }
            Text("From \(cache.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.cave(.caption)).foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachResult")
    }

    /// Cave Cals+ is checked first (like Import a recipe), so nothing is sent before the paywall. New tips replace
    /// the old ones, which go along so the coach suggests different ones.
    private func ask(checkedAccess: Bool = false) async {
        guard !asking else { return }
        error = nil
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        if !checkedAccess && !testing {
            await subscriptions.refresh(regularLogCount: store.regularLogCount)
            if let account = subscriptions.account, !account.active, subscriptions.offering != nil {
                showPaywall = true
                return
            }
        }
        asking = true
        defer { asking = false }
        UsageStats.shared.event("coach.asked", ["range": habits.range.statName, "again": String(cached != nil)])
        do {
            let previous = cached?.result.tips.map { $0.detail.isEmpty ? $0.title : "\($0.title): \($0.detail)" } ?? []
            let result = try await AIBackend.shared.coach(habits.coachPayload(), previousTips: previous)
            let cache = CoachCache(result: result, date: Date(), range: habits.range.statName)
            cache.save()
            withAnimation(.easeInOut(duration: 0.25)) { cached = cache }
            Haptics.play(.success)
        } catch let failure as AIServiceError where failure.code == "subscription_required" && subscriptions.offering != nil {
            showPaywall = true
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            UsageStats.shared.error(.coach, error)
        }
    }
}

/// Progress → On-Target vs. Over Days → Change: three choices, the numbers editable in place. Saved with the
/// other Progress settings, so every device shows the same.
struct OnTargetRuleSheet: View {
    /// Today's goal, for the example ranges.
    let goal: Double?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: OnTargetRule.Kind?
    @State private var text = ""
    private var rule: OnTargetRule { store.progressSettings.onTarget }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick what an on-target day means to you. Progress compares those days with days that went over.")
                        .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    option(.atOrUnder) { Text("At or under my goal") }
                    option(.withinPercent) {
                        HStack(spacing: 5) {
                            Text("Within")
                            editable(rule.percentText, kind: .withinPercent)
                            Text("of my goal")
                        }
                    }
                    option(.overBy) {
                        HStack(spacing: 5) {
                            Text("Up to")
                            editable(rule.overByText, kind: .overBy)
                            Text("over is fine")
                        }
                    }
                    Text("Within a percentage counts either way. Days below that range aren't compared.")
                        .font(.cave(.caption)).foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .caveScreenBackground()
            .navigationTitle("On-Target Days").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.hapticButtonStyle(.automatic).accessibilityIdentifier("onTargetDone")
                }
            }
            .alert(editing == .withinPercent ? "Within what percent?" : "How many calories over?",
                   isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField(editing == .withinPercent ? "5" : "100", text: $text)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("onTargetValue")
                // Alert buttons may skip the haptic button style, so they play their own feel.
                Button("Save") { Haptics.play(.success); saveValue() }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: {
                Text(editing == .withinPercent ? "Either way of your goal, 1 to 50%." : "Calories past your goal that still count, 10 to 2,000.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A choice row: tap anywhere to pick it. Not a Button, so the editable number inside gets its own taps.
    private func option<Label: View>(_ kind: OnTargetRule.Kind, @ViewBuilder label: () -> Label) -> some View {
        let selected = rule.kind == kind
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                label().font(.cave(.body)).foregroundStyle(Color.primary)
                if let example = example(kind) {
                    Text(example).font(.cave(.caption)).foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.caveOrange : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(selected ? Color.caveOrange.opacity(0.1) : Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            guard rule.kind != kind else { return }
            Haptics.play(.selection)
            select(kind)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(kind) }
        .accessibilityIdentifier("onTarget-\(kind.rawValue)")
    }

    /// The orange, underlined number; tapping it picks the row and asks for a new value.
    private func editable(_ value: String, kind: OnTargetRule.Kind) -> some View {
        Button {
            select(kind)
            text = kind == .withinPercent ? rule.percent.formatted(.number.precision(.fractionLength(0...1))) : String(Int(rule.overBy))
            editing = kind
        } label: {
            Text(value).underline().foregroundStyle(Color.caveOrange)
        }
        .hapticButtonStyle(.plain)
        .accessibilityLabel(kind == .withinPercent ? "Percent, \(value)" : "Calories over, \(value)")
        .accessibilityHint("Edit")
        .accessibilityIdentifier("onTargetEdit-\(kind.rawValue)")
    }

    /// "1,995–2,205 cals with your 2,100 goal"
    private func example(_ kind: OnTargetRule.Kind) -> String? {
        guard let goal, goal > 0 else { return nil }
        var sample = rule
        sample.kind = kind
        guard let range = sample.range(goal: goal) else { return nil }
        let span = kind == .withinPercent ? "\(range.lowerBound.calorieText)–\(range.upperBound.calorieText)" : "Up to \(range.upperBound.calorieText)"
        return "\(span) cals with your \(goal.calorieText) goal"
    }

    private func select(_ kind: OnTargetRule.Kind) {
        guard rule.kind != kind else { return }
        var settings = store.progressSettings
        settings.onTarget.kind = kind
        store.saveProgressSettings(settings)
        UsageStats.shared.event("progress.onTarget", ["rule": kind.rawValue])
    }

    private func saveValue() {
        guard let kind = editing, let number = Double(text.filter(\.isNumber)) else { return }
        var settings = store.progressSettings
        settings.onTarget.kind = kind
        if kind == .withinPercent { settings.onTarget.percent = OnTargetRule.percents.clamp(number) }
        else { settings.onTarget.overBy = OnTargetRule.overAmounts.clamp(number) }
        store.saveProgressSettings(settings)
    }
}
