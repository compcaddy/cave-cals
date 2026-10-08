import Foundation

enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: Self { self }
    var component: Calendar.Component { switch self { case .week: .weekOfYear; case .month: .month; case .year: .year } }
}

enum ProgressPreferences {
    static var isPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--progress-preview")
        #else
        false
        #endif
    }
    // Preview and UI tests must not overwrite the person's local week-start preference.
    static let defaults: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let defaults = UserDefaults(suiteName: "com.philstarkovich.cavecals.progress-uitests")!
            defaults.set(2, forKey: ProgressCalendar.weekStartKey)
            return defaults
        }
        if isPreview { return UserDefaults(suiteName: "com.philstarkovich.cavecals.progress-preview")! }
        return .standard
    }()
}

struct ProgressCalendar {
    static let weekStartKey = "progressWeekStart.v1"
    var calendar: Calendar
    init(firstWeekday: Int = 2, calendar: Calendar = .current) {
        self.calendar = calendar
        self.calendar.firstWeekday = (1...7).contains(firstWeekday) ? firstWeekday : 2
        self.calendar.minimumDaysInFirstWeek = 1
    }
    func interval(_ period: ProgressPeriod, containing date: Date) -> DateInterval {
        calendar.dateInterval(of: period.component, for: date)!
    }
    func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = [], day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }
    func move(_ date: Date, by amount: Int, period: ProgressPeriod) -> Date {
        calendar.date(byAdding: period.component, value: amount, to: date)!
    }
    func lastCompletedWeek(now: Date) -> Date {
        move(interval(.week, containing: now).start, by: -1, period: .week)
    }
    func label(_ interval: DateInterval) -> String {
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + end.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

enum ProgressDayStatus: String {
    case complete, incomplete, missing, inProgress, future
    var label: String {
        switch self {
        case .complete: "Included"
        case .incomplete: "Incomplete"
        case .missing: "Not logged"
        case .inProgress: "In progress"
        case .future: "Upcoming"
        }
    }
}

struct ProgressStats {
    let values: [Double]
    var count: Int { values.count }
    var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    var min: Double? { values.min() }
    var max: Double? { values.max() }
    func change(from previous: Self) -> Double? {
        guard let average, let old = previous.average else { return nil }
        return average - old
    }
}

/// Stacked calories are approximate; the diary's logged calorie total always wins.
struct ProgressEnergy {
    var protein = 0.0, carbs = 0.0, fat = 0.0, unknown = 0.0
    var total: Double { protein + carbs + fat + unknown }
    init() { }
    init(_ draft: EntryDraft) {
        let calories = max(0, draft.calories.rounded())
        let macros = draft.totalMacros
        protein = max(0, macros?.protein ?? 0) * 4
        carbs = max(0, macros?.totalCarbs ?? 0) * 4
        fat = max(0, macros?.fat ?? 0) * 9
        let sum = protein + carbs + fat
        // Label rounding/fiber/etc. can make 4/4/9 exceed the recorded total. Scale only the chart.
        if sum > calories, sum > 0 {
            let scale = calories / sum
            protein *= scale; carbs *= scale; fat *= scale
        }
        unknown = max(0, calories - protein - carbs - fat)
    }
    mutating func add(_ other: Self) {
        protein += other.protein; carbs += other.carbs; fat += other.fat; unknown += other.unknown
    }
    func divided(by count: Int) -> Self {
        guard count > 0 else { return Self() }
        var result = self; let n = Double(count)
        result.protein /= n; result.carbs /= n; result.fat /= n; result.unknown /= n
        return result
    }
}

struct ProgressDay: Identifiable {
    let date: Date
    let calories: Double?
    let energy: ProgressEnergy
    let macros: MacroSummary
    let weight: Double?
    let status: ProgressDayStatus
    let referenceAverage: Double?
    var id: Date { date }
}

struct ProgressWeek: Identifiable {
    let interval: DateInterval
    let days: [ProgressDay]
    var id: Date { interval.start }
    var calories: ProgressStats { ProgressStats(values: days.filter { $0.status == .complete }.compactMap(\.calories)) }
    var weight: ProgressStats { ProgressStats(values: days.compactMap(\.weight)) }
    var incompleteCount: Int { days.filter { $0.status == .incomplete }.count }
}

struct ProgressBucket: Identifiable {
    let start: Date
    let end: Date
    let calories: Double?
    let energy: ProgressEnergy
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let weight: Double?
    let includedDays: Int
    let weighIns: Int
    let status: ProgressDayStatus
    let partialMacros: Bool
    let macroDayCounts: [MacroKind: Int]
    var id: Date { start }
    var center: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    func grams(_ kind: MacroKind) -> Double? {
        switch kind { case .protein: protein; case .totalCarbs: carbs; case .fat: fat; case .fiber: nil }
    }
}

struct ProgressData {
    let dates: ProgressCalendar
    let today: Date
    private let foods: [Date: [EntryDraft]]
    private let totals: [Date: Double]
    private let weights: [Date: Double]
    private let completedTotals: [Date: Double]
    /// Days the person marked done eating: complete however low, including today.
    private let finished: Set<Date>
    /// A past day counts as complete at 70% of that day's calorie goal (1,400 of 2,000); without a goal, at 70% of
    /// the prior 28 complete days' average. Days marked done eating always count. (60% of the average until
    /// October 8, 2026.)
    static let completeShare = 0.7

    init(drafts: [EntryDraft], records: [WeightRecord], finishedDays: Set<Date> = [], firstWeekday: Int = 2,
         goal: ((Date) -> Double?)? = nil, now: Date = Date(), calendar: Calendar = .current) {
        dates = ProgressCalendar(firstWeekday: firstWeekday, calendar: calendar)
        today = calendar.startOfDay(for: now)
        foods = Dictionary(grouping: drafts.filter { $0.timestamp <= now }, by: { calendar.startOfDay(for: $0.timestamp) })
        totals = foods.mapValues { $0.reduce(0) { $0 + $1.calories.rounded() } }
        let finished = Set(finishedDays.map { calendar.startOfDay(for: $0) }.filter { [today] in $0 <= today })
        self.finished = finished
        // Classify chronologically: previously incomplete days never lower a later day's baseline.
        var completed: [Date: Double] = [:]
        for date in totals.keys.sorted() where date < today || finished.contains(date) {
            let total = totals[date]!
            if finished.contains(date) { completed[date] = total; continue }
            if let target = goal?(date), target > 0 {
                if total >= target * Self.completeShare { completed[date] = total }
                continue
            }
            let lower = calendar.date(byAdding: .day, value: -28, to: date)!
            let prior = completed.filter { $0.key >= lower && $0.key < date }.map(\.value)
            let average = ProgressStats(values: prior).average
            if average.map({ total >= $0 * Self.completeShare }) ?? true { completed[date] = total }
        }
        completedTotals = completed
        // Normally unique by day; choose the latest revision defensively when reading old data.
        weights = Dictionary(grouping: records.filter { !$0.deleted && $0.date <= now }, by: { calendar.startOfDay(for: $0.date) })
            .compactMapValues { $0.max { $0.revision < $1.revision }?.kilograms }
    }

    /// Days whose calories count toward averages (the same rule as everywhere in Progress), with their totals.
    /// Today is in it only once marked done eating.
    var completedTotalsByDay: [Date: Double] { completedTotals }

    /// A historical day's reference never includes that day, incomplete days, today, or future data.
    func referenceAverage(before day: Date) -> Double? {
        let lower = dates.calendar.date(byAdding: .day, value: -28, to: day)!
        let candidates = completedTotals.filter { $0.key >= lower && $0.key < day }.map(\.value)
        return ProgressStats(values: candidates).average
    }

    func day(_ date: Date) -> ProgressDay {
        let date = dates.calendar.startOfDay(for: date)
        let entries = foods[date] ?? []
        let calories = totals[date]
        let baseline = referenceAverage(before: date)
        let status: ProgressDayStatus
        if date > today { status = .future }
        else if calories != nil, finished.contains(date) { status = .complete }
        else if date == today { status = .inProgress }
        else if calories != nil { status = completedTotals[date] != nil ? .complete : .incomplete }
        else { status = .missing }
        var energy = ProgressEnergy()
        entries.forEach { energy.add(ProgressEnergy($0)) }
        return ProgressDay(date: date, calories: calories, energy: energy, macros: MacroSummary(entries),
                           weight: weights[date], status: status, referenceAverage: baseline)
    }
    func week(containing date: Date) -> ProgressWeek {
        let interval = dates.interval(.week, containing: date)
        return ProgressWeek(interval: interval, days: dates.days(in: interval).map(day))
    }
    var currentWeekStart: Date { dates.interval(.week, containing: today).start }
    func fiveWeeks(endingAt date: Date) -> [ProgressWeek] {
        let last = min(dates.interval(.week, containing: date).start, currentWeekStart)
        return (0..<5).reversed().map { week(containing: dates.move(last, by: -$0, period: .week)) }
    }
    func buckets(_ period: ProgressPeriod, containing date: Date) -> [ProgressBucket] {
        let interval = dates.interval(period, containing: date)
        if period != .year {
            return dates.days(in: interval).map { bucket(days: [day($0)], start: $0,
                end: dates.calendar.date(byAdding: .day, value: 1, to: $0)!, average: false) }
        }
        var buckets: [ProgressBucket] = [], start = interval.start
        while start < interval.end {
            let end = min(dates.interval(.week, containing: start).end, interval.end)
            buckets.append(bucket(days: dates.days(in: DateInterval(start: start, end: end)).map(day), start: start, end: end, average: true))
            start = end
        }
        return buckets
    }
    private func bucket(days: [ProgressDay], start: Date, end: Date, average: Bool) -> ProgressBucket {
        let included = average ? days.filter { $0.status == .complete } : days.filter { $0.calories != nil }
        var energy = ProgressEnergy(); included.forEach { energy.add($0.energy) }
        let values = included.compactMap(\.calories)
        func macro(_ kind: MacroKind) -> Double? {
            let values = included.compactMap { $0.macros.total(kind).grams }
            return average ? ProgressStats(values: values).average : values.first
        }
        return ProgressBucket(start: start, end: end,
            calories: average ? ProgressStats(values: values).average : values.first,
            energy: average ? energy.divided(by: values.count) : energy,
            protein: macro(.protein), carbs: macro(.totalCarbs), fat: macro(.fat),
            weight: ProgressStats(values: days.compactMap(\.weight)).average,
            includedDays: included.filter { $0.status == .complete }.count,
            weighIns: days.compactMap(\.weight).count,
            status: average ? (values.isEmpty ? .missing : .complete) : days[0].status,
            partialMacros: included.contains { $0.macros.incomplete },
            macroDayCounts: Dictionary(uniqueKeysWithValues: MacroKind.primary.map { kind in
                (kind, included.filter { $0.macros.total(kind).grams != nil }.count)
            }))
    }
}

/// What counts as an on-target day for Progress → On-Target vs. Over Days (October 8, 2026): at or under the
/// goal, within a percentage of it either way, or up to some calories over it.
struct OnTargetRule: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case atOrUnder, withinPercent, overBy }
    enum Outcome { case onTarget, over, under }
    var kind: Kind = .atOrUnder
    /// Either way, for `withinPercent`.
    var percent: Double = 5
    /// Calories past the goal that still count, for `overBy`.
    var overBy: Double = 100
    static let percents = 1.0...50.0
    static let overAmounts = 10.0...2000.0

    func outcome(calories: Double, goal: Double) -> Outcome {
        guard let range = range(goal: goal) else { return .onTarget }
        if calories > range.upperBound { return .over }
        return calories < range.lowerBound ? .under : .onTarget
    }
    /// The on-target calories for a goal (no lower end except within a percentage).
    func range(goal: Double) -> ClosedRange<Double>? {
        guard goal > 0 else { return nil }
        switch kind {
        case .atOrUnder: return 0...goal
        case .withinPercent: return goal * (1 - percent / 100)...goal * (1 + percent / 100)
        case .overBy: return 0...(goal + overBy)
        }
    }
    var percentText: String { "\(percent.formatted(.number.precision(.fractionLength(0...1))))%" }
    var overByText: String { overBy.calorieText }
    /// "at or under your goal", "within 5% of your goal", "up to 100 over your goal"
    var summary: String {
        switch kind {
        case .atOrUnder: "at or under your goal"
        case .withinPercent: "within \(percentText) of your goal"
        case .overBy: "up to \(overByText) over your goal"
        }
    }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .atOrUnder
        percent = Self.percents.clamp((try? container.decode(Double.self, forKey: .percent)) ?? 5)
        overBy = Self.overAmounts.clamp((try? container.decode(Double.self, forKey: .overBy)) ?? 100)
    }
}

extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

/// Progress settings, saved on the synced profile (`UserProfile.progressSettingsData`) so every iPhone and iPad on
/// the same iCloud account shows the same week start, on-target rule, and chart ranges (October 8, 2026).
struct ProgressSettings: Codable, Equatable {
    var firstWeekday = 2
    var onTarget = OnTargetRule()
    var trendsRange = ProgressTrendRange.days30
    var habitsRange = ProgressTrendRange.days90

    init() {}
    init(firstWeekday: Int) { self.firstWeekday = firstWeekday }
    /// Unknown or missing values fall back to their defaults, so older and newer app versions read each other.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let weekday = (try? container.decode(Int.self, forKey: .firstWeekday)) ?? 2
        firstWeekday = (1...7).contains(weekday) ? weekday : 2
        onTarget = (try? container.decode(OnTargetRule.self, forKey: .onTarget)) ?? OnTargetRule()
        trendsRange = (try? container.decode(ProgressTrendRange.self, forKey: .trendsRange)) ?? .days30
        habitsRange = (try? container.decode(ProgressTrendRange.self, forKey: .habitsRange)) ?? .days90
    }
    var encoded: Data? { try? JSONEncoder().encode(self) }
    /// Before anything is saved to the profile, the week start this iPhone used to keep on its own.
    static func decode(_ data: Data?, localWeekday: Int) -> Self {
        if let data, let settings = try? JSONDecoder().decode(Self.self, from: data) { return settings }
        return Self(firstWeekday: (1...7).contains(localWeekday) ? localWeekday : 2)
    }
}

/// Progress → Trends over the last 30 or 90 days, or all time (ending yesterday).
enum ProgressTrendRange: String, CaseIterable, Identifiable, Codable {
    case days30 = "30 days", days90 = "90 days", all = "All time"
    var id: Self { self }
    var days: Int? { switch self { case .days30: 30; case .days90: 90; case .all: nil } }
    var statName: String { switch self { case .days30: "30"; case .days90: "90"; case .all: "all" } }
}

/// Progress → Trends: average calories by weekday, and when in the day food is eaten. Both use only complete
/// past days (Progress's usual rule). The hour chart also skips food logged on a later day than it belongs to,
/// because backfilled food gets the clock time it was entered, not when it was eaten. See Documentation/Progress.md.
struct ProgressTrends {
    struct Food {
        let timestamp: Date
        let createdAt: Date
        let calories: Double
    }
    struct Weekday: Identifiable {
        /// Calendar weekday, 1 = Sunday.
        let weekday: Int
        let average: Double?
        let days: Int
        var id: Int { weekday }
    }
    struct Hour: Identifiable {
        let hour: Int
        /// Average calories eaten in this hour on a counted day.
        let calories: Double
        /// This hour's share of all counted calories (the 24 add up to 1).
        let share: Double
        var id: Int { hour }
    }
    /// In the Progress week-start order.
    let weekdays: [Weekday]
    let hours: [Hour]
    let weekdayDays: Int
    let hourDays: Int

    init(foods: [Food], data: ProgressData, range: ProgressTrendRange) {
        let calendar = data.dates.calendar
        let start = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: data.today) }
        let totals = data.completedTotalsByDay.filter { day, _ in day < data.today && start.map { day >= $0 } ?? true }

        var byWeekday: [Int: [Double]] = [:]
        for (day, total) in totals { byWeekday[calendar.component(.weekday, from: day), default: []].append(total) }
        weekdays = (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let values = byWeekday[weekday] ?? []
            return Weekday(weekday: weekday, average: ProgressStats(values: values).average, days: values.count)
        }
        weekdayDays = totals.count

        var sums = Array(repeating: 0.0, count: 24), counted = Set<Date>()
        for food in foods {
            let day = calendar.startOfDay(for: food.timestamp)
            guard totals[day] != nil, calendar.isDate(food.createdAt, inSameDayAs: food.timestamp) else { continue }
            sums[calendar.component(.hour, from: food.timestamp)] += max(0, food.calories.rounded())
            counted.insert(day)
        }
        hourDays = counted.count
        let all = sums.reduce(0, +), days = Double(max(counted.count, 1))
        hours = (0..<24).map { Hour(hour: $0, calories: sums[$0] / days, share: all > 0 ? sums[$0] / all : 0) }
    }
}

#if DEBUG
/// Deterministic, local-only history for UI verification; never mixed into the user's diary.
enum ProgressPreview {
    /// Each sample day is meals at different times (so Trends and Good Days vs. Over Days have something to
    /// show): days over the 2,100 goal start later, eat dinner later, and add a late snack. The day's calories
    /// and macros add up to the same totals as before.
    static func drafts(now: Date = Date()) -> [EntryDraft] {
        let calendar = Calendar.current
        typealias Meal = (name: String, hour: Int, minute: Int, share: Double)
        let goodDay: [Meal] = [("Greek yogurt", 7, 45, 0.25), ("Lunch", 12, 20, 0.4), ("Dinner", 18, 15, 0.35)]
        let overDay: [Meal] = [("Breakfast", 9, 20, 0.15), ("Lunch", 13, 10, 0.35), ("Dinner", 19, 30, 0.35), ("Tortilla chips", 21, 30, 0.15)]
        return (1...110).filter { $0 % 19 != 0 }.flatMap { ago -> [EntryDraft] in
            let calories = ago % 13 == 0 ? 600.0 : 1850 + Double(ago % 7) * 55
            let meals = calories > 2100 ? overDay : goodDay
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -ago, to: now)!)
            var left = calories
            return meals.enumerated().map { index, meal in
                let part = index == meals.count - 1 ? left : (calories * meal.share).rounded()
                left -= part
                var draft = EntryDraft(name: meal.name, calories: part,
                    timestamp: calendar.date(bySettingHour: meal.hour, minute: meal.minute, second: 0, of: day)!)
                if ago % 5 != 0 {
                    draft.macrosPerServing = MacroNutrients(protein: 125, totalCarbs: 180, fat: 65).scaled(part / calories)
                }
                return draft
            }
        }
    }
    @MainActor static func weights(now: Date = Date()) -> WeightStore {
        let store = WeightStore(inMemory: true); store.setTracking(true); store.setUnit(.pounds)
        for ago in 1...110 where ago % 9 != 0 {
            store.save(kilograms: 78 + Double(ago) * 0.025 + sin(Double(ago)) * 0.15,
                       date: Calendar.current.date(byAdding: .day, value: -ago, to: now)!)
        }
        return store
    }
}
#endif
