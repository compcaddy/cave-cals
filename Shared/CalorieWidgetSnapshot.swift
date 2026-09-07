import Foundation

struct CalorieWidgetSnapshot: Codable, Equatable {
    let day: Date
    let total: Double
    let goal: Double?

    func total(on date: Date, calendar: Calendar = .current) -> Double {
        calendar.isDate(day, inSameDayAs: date) ? total : 0
    }
    func label(on date: Date, calendar: Calendar = .current) -> String {
        let count = total(on: date, calendar: calendar).formatted(.number.grouping(.never).precision(.fractionLength(0)))
        if let goal, goal > 0 {
            return count + "/" + goal.formatted(.number.grouping(.never).precision(.fractionLength(0)))
        }
        return count + " cal"
    }
}

enum CalorieWidgetStorage {
    static let groupID = "group.com.philstarkovich.cavecals"
    static let kind = "QuickLogWidget"
    private static let key = "calorieWidget.snapshot.v1"
    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: groupID)) -> CalorieWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CalorieWidgetSnapshot.self, from: data)
    }
    @discardableResult static func write(_ snapshot: CalorieWidgetSnapshot, to defaults: UserDefaults? = UserDefaults(suiteName: groupID)) -> Bool {
        guard let defaults, read(from: defaults) != snapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
