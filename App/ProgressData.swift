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

    init(drafts: [EntryDraft], records: [WeightRecord], finishedDays: Set<Date> = [], firstWeekday: Int = 2,
         now: Date = Date(), calendar: Calendar = .current) {
        dates = ProgressCalendar(firstWeekday: firstWeekday, calendar: calendar)
        today = calendar.startOfDay(for: now)
        foods = Dictionary(grouping: drafts.filter { $0.timestamp <= now }, by: { calendar.startOfDay(for: $0.timestamp) })
        totals = foods.mapValues { $0.reduce(0) { $0 + $1.calories.rounded() } }
        let finished = Set(finishedDays.map { calendar.startOfDay(for: $0) }.filter { [today] in $0 <= today })
        self.finished = finished
        // Classify chronologically: previously incomplete days never lower a later day's baseline.
        var completed: [Date: Double] = [:]
        for date in totals.keys.sorted() where date < today || finished.contains(date) {
            let lower = calendar.date(byAdding: .day, value: -28, to: date)!
            let prior = completed.filter { $0.key >= lower && $0.key < date }.map(\.value)
            let average = ProgressStats(values: prior).average
            let total = totals[date]!
            if finished.contains(date) || average.map({ total >= $0 * 0.6 }) ?? true { completed[date] = total }
        }
        completedTotals = completed
        // Normally unique by day; choose the latest revision defensively when reading old data.
        weights = Dictionary(grouping: records.filter { !$0.deleted && $0.date <= now }, by: { calendar.startOfDay(for: $0.date) })
            .compactMapValues { $0.max { $0.revision < $1.revision }?.kilograms }
    }

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
        else if let calories { status = baseline.map { calories < 0.6 * $0 } == true ? .incomplete : .complete }
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
    func sixWeeks(endingAt date: Date) -> [ProgressWeek] {
        let last = min(dates.interval(.week, containing: date).start, currentWeekStart)
        return (0..<6).reversed().map { week(containing: dates.move(last, by: -$0, period: .week)) }
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

#if DEBUG
/// Deterministic, local-only history for UI verification; never mixed into the user's diary.
enum ProgressPreview {
    static func drafts(now: Date = Date()) -> [EntryDraft] {
        let calendar = Calendar.current
        return (1...110).filter { $0 % 19 != 0 }.map { ago in
            let calories = ago % 13 == 0 ? 600.0 : 1850 + Double(ago % 7) * 55
            var draft = EntryDraft(name: "Sample day", calories: calories,
                timestamp: calendar.date(byAdding: .day, value: -ago, to: now)!)
            if ago % 5 != 0 { draft.macrosPerServing = MacroNutrients(protein: 125, totalCarbs: 180, fat: 65) }
            return draft
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
