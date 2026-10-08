import Foundation

/// One meal type's block of the day, as minutes after midnight. An `end` before `start` runs past midnight
/// (8:00 PM – 4:00 AM). `start` is included and `end` isn't, so blocks can meet without overlapping.
struct MealTime: Codable, Equatable, Hashable {
    static let minutesInDay = 24 * 60
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = Self.wrapped(start)
        self.end = Self.wrapped(end)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try container.decode(Int.self, forKey: .start), end: try container.decode(Int.self, forKey: .end))
    }

    static func wrapped(_ minute: Int) -> Int { ((minute % minutesInDay) + minutesInDay) % minutesInDay }
    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    /// A block must have some length; a whole day isn't a meal time.
    var isValid: Bool { start != end }
    var crossesMidnight: Bool { end < start }
    /// Minutes in the block.
    var length: Int { start < end ? end - start : Self.minutesInDay - start + end }
    func contains(_ minute: Int) -> Bool {
        let minute = Self.wrapped(minute)
        return start < end ? (start..<end).contains(minute) : (minute >= start || minute < end)
    }
    /// Two blocks share a minute exactly when one of them starts inside the other.
    func overlaps(_ other: MealTime) -> Bool { contains(other.start) || other.contains(start) }

    /// "5:00 AM – 9:00 AM"
    var text: String { "\(Self.text(start)) – \(Self.text(end))" }
    static func text(_ minute: Int) -> String {
        date(minute).formatted(date: .omitted, time: .shortened)
    }
    /// Today at that minute, for time pickers and formatting.
    static func date(_ minute: Int, on day: Date = Date(), calendar: Calendar = .current) -> Date {
        let minute = wrapped(minute)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }
}

/// A meal food can be logged under: Breakfast, Lunch, or one the person adds. Entries point to it by `id`,
/// so renaming keeps history. Every type has at most one block of time (a second snack is its own type).
struct MealType: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var time: MealTime?
    /// Deleted in Settings, but food already logged under it keeps its name.
    var removed = false

    init(id: String = UUID().uuidString, name: String, time: MealTime? = nil, removed: Bool = false) {
        self.id = id; self.name = name; self.time = time; self.removed = removed
    }
    // Every field but the id and name is optional, so a meal list saved by a newer version still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        time = try container.decodeIfPresent(MealTime.self, forKey: .time)
        removed = try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
    }

    static let maxNameLength = 30
    /// Ready-made types. Their fixed ids mean two iPhones setting up meal types never create duplicates.
    static let defaults: [MealType] = [
        MealType(id: "breakfast", name: "Breakfast", time: MealTime(start: 5 * 60, end: 9 * 60)),
        MealType(id: "morningSnack", name: "Morning Snack", time: MealTime(start: 9 * 60, end: 11 * 60)),
        MealType(id: "lunch", name: "Lunch", time: MealTime(start: 11 * 60, end: 14 * 60)),
        MealType(id: "afternoonSnack", name: "Afternoon Snack", time: MealTime(start: 14 * 60, end: 16 * 60)),
        MealType(id: "dinner", name: "Dinner", time: MealTime(start: 16 * 60, end: 20 * 60)),
        MealType(id: "dessert", name: "Dessert"),
        MealType(id: "eveningSnack", name: "Evening Snack", time: MealTime(start: 20 * 60, end: 4 * 60)),
    ]
}

/// Settings → Meal types. Stored on the profile, so every iPhone on the same iCloud account sorts food the same way.
struct MealSettings: Codable, Equatable {
    /// "Track meal type". Off by default, which leaves the log exactly as it was before meal types.
    var tracks = false
    /// "Set meal by time of day". Off, adding food asks which meal instead.
    var byTime = true
    /// In the order Home lists them, including removed types (kept for the names of food logged under them).
    var types = MealType.defaults

    init(tracks: Bool = false, byTime: Bool = true, types: [MealType] = MealType.defaults) {
        self.tracks = tracks; self.byTime = byTime; self.types = types
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent(Bool.self, forKey: .tracks) ?? false
        byTime = try container.decodeIfPresent(Bool.self, forKey: .byTime) ?? true
        types = try container.decodeIfPresent([MealType].self, forKey: .types) ?? MealType.defaults
    }

    static func decode(_ data: Data?) -> MealSettings {
        data.flatMap { try? JSONDecoder().decode(MealSettings.self, from: $0) } ?? MealSettings()
    }
    var encoded: Data? { try? JSONEncoder().encode(self) }

    /// The types someone can pick, in order.
    var visibleTypes: [MealType] { types.filter { !$0.removed } }
    /// Any type food may be logged under, including removed ones.
    func type(id: String?) -> MealType? {
        guard let id else { return nil }
        return types.first { $0.id == id }
    }
    /// Adding food opens the editor to pick a meal (tracking on, time of day off).
    var asks: Bool { tracks && !byTime }
    /// For the usage stats: "off", "time" (set by time of day), or "ask".
    var statsMode: String { !tracks ? "off" : byTime ? "time" : "ask" }

    /// The visible type whose time covers this moment, if any.
    func meal(at date: Date, calendar: Calendar = .current) -> String? {
        let minute = MealTime.minute(of: date, calendar: calendar)
        return visibleTypes.first { $0.time?.contains(minute) == true }?.id
    }
    /// The meal a newly logged food gets: none while tracking is off; otherwise the one picked, else (by time
    /// of day) the meal whose time it's logged in. Food logged outside every meal's time has no meal.
    func assignedMeal(chosen: String?, at timestamp: Date, calendar: Calendar = .current) -> String? {
        guard tracks else { return nil }
        if let chosen, let type = type(id: chosen), !type.removed { return chosen }
        return byTime ? meal(at: timestamp, calendar: calendar) : nil
    }

    /// Another visible type whose time overlaps this one.
    func conflict(with time: MealTime, excluding id: String?) -> MealType? {
        visibleTypes.first { $0.id != id && $0.time?.overlaps(time) == true }
    }
    /// The other type's time, shortened so it no longer overlaps `time`, when the two overlap at just one end
    /// (moving Lunch's end into Afternoon Snack shortens the snack). Nil when one block would have to split or vanish.
    func trimmedTime(of other: MealType, avoiding time: MealTime) -> MealTime? {
        guard let current = other.time, current.overlaps(time) else { return nil }
        let startsInside = time.contains(current.start), endsInside = time.contains(current.end - 1)
        let trimmed: MealTime
        if startsInside, !endsInside {
            trimmed = MealTime(start: time.end, end: current.end)
        } else if endsInside, !startsInside {
            trimmed = MealTime(start: current.start, end: time.start)
        } else {
            return nil
        }
        guard trimmed.isValid, trimmed.length < current.length, !trimmed.overlaps(time) else { return nil }
        return trimmed
    }
    /// Another visible type already using this name (ignoring case and spacing).
    func duplicate(named name: String, excluding id: String?) -> MealType? {
        let key = normalizedFoodName(name)
        return visibleTypes.first { $0.id != id && normalizedFoodName($0.name) == key }
    }

    /// Adds a new type or replaces one with the same id. A new type with a time slots in among the others by
    /// time (counting the day from 4 AM, so a late-night meal sorts last); one without a time goes at the end.
    func saving(_ type: MealType) -> MealSettings {
        var copy = self
        if let index = copy.types.firstIndex(where: { $0.id == type.id }) {
            copy.types[index] = type
            return copy
        }
        let key = { (time: MealTime) in MealTime.wrapped(time.start - 4 * 60) }
        if let time = type.time,
           let next = copy.types.firstIndex(where: { !$0.removed && $0.time.map { key($0) > key(time) } == true }) {
            copy.types.insert(type, at: next)
        } else {
            copy.types.append(type)
        }
        return copy
    }
    /// Deleting a type food was logged under only hides it, so those days keep their labels.
    func removing(_ id: String, inUse: Bool) -> MealSettings {
        var copy = self
        if inUse {
            if let index = copy.types.firstIndex(where: { $0.id == id }) { copy.types[index].removed = true }
        } else {
            copy.types.removeAll { $0.id == id }
        }
        return copy
    }
    /// Reorders the visible types; removed ones keep their place at the end.
    func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> MealSettings {
        var visible = visibleTypes
        visible.move(fromOffsets: source, toOffset: destination)
        var copy = self
        copy.types = visible + types.filter(\.removed)
        return copy
    }

    /// Stretches of the day no visible type covers, e.g. 4:00 AM – 5:00 AM with the defaults.
    var uncoveredTimes: [MealTime] {
        let timed = visibleTypes.compactMap(\.time)
        guard !timed.isEmpty else { return [] }
        let covered = (0..<MealTime.minutesInDay).map { minute in timed.contains { $0.contains(minute) } }
        var gaps: [MealTime] = []
        var start: Int?
        for minute in 0...MealTime.minutesInDay {
            let free = minute < MealTime.minutesInDay && !covered[minute]
            if free, start == nil { start = minute }
            if !free, let first = start { gaps.append(MealTime(start: first, end: minute)); start = nil }
        }
        // A gap running through midnight is one stretch, not two.
        if gaps.count > 1, gaps.first?.start == 0, gaps.last?.end == 0 {
            let last = gaps.removeLast()
            gaps[0] = MealTime(start: last.start, end: gaps[0].end)
        }
        return gaps.filter(\.isValid)
    }
}

/// One meal's part of a day's log on Home.
struct MealGroup<Item> {
    /// Nil collects food with no meal (or one the meal list no longer has).
    var type: MealType?
    var items: [Item]
    var id: String { type?.id ?? "none" }
    var title: String { type?.name ?? "Other" }
}

enum MealSections {
    /// A day's food grouped by meal, in the order of the meal list, with food that has no meal last. Nil means
    /// show the day as one plain list: meal types are off, or nothing that day has a meal (days logged before
    /// meal types were turned on look as they always did).
    static func group<Item>(_ items: [Item], settings: MealSettings, mealType: (Item) -> String?) -> [MealGroup<Item>]? {
        guard settings.tracks, items.contains(where: { settings.type(id: mealType($0)) != nil }) else { return nil }
        var groups = settings.types.compactMap { type -> MealGroup<Item>? in
            let matching = items.filter { mealType($0) == type.id }
            return matching.isEmpty ? nil : MealGroup(type: type, items: matching)
        }
        let other = items.filter { settings.type(id: mealType($0)) == nil }
        if !other.isEmpty { groups.append(MealGroup(type: nil, items: other)) }
        return groups
    }

    /// Home's grouping. With Set meal by time of day on, food without a meal (logged before meal types, or
    /// copied in) is shown under the meal whose time it was logged in; a picked meal always wins, and food
    /// outside every time goes under Other. Display only: entries are never rewritten.
    static func group(_ entries: [CalorieEntry], settings: MealSettings, calendar: Calendar = .current) -> [MealGroup<CalorieEntry>]? {
        group(entries, settings: settings) { entry in
            if let id = entry.mealType, settings.type(id: id) != nil { return id }
            return settings.byTime ? settings.meal(at: entry.timestamp, calendar: calendar) : nil
        }
    }
}
