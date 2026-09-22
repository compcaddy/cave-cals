import Foundation
import Observation

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case pounds = "lb", kilograms = "kg"
    var id: String { rawValue }
    func display(_ kilograms: Double) -> Double { self == .pounds ? kilograms / 0.45359237 : kilograms }
    func kilograms(_ value: Double) -> Double { self == .pounds ? value * 0.45359237 : value }
    func editingText(_ kilograms: Double) -> String {
        display(kilograms).formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }
    func text(_ kilograms: Double) -> String {
        display(kilograms).formatted(.number.precision(.fractionLength(1))) + " " + rawValue
    }
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.wholeNumberValue != nil || String($0) == separator }),
              cleaned.components(separatedBy: separator).count <= 2 else { return nil }
        return Double(cleaned.map { String($0) == separator ? "." : String($0.wholeNumberValue!) }.joined())
    }
}

struct WeightRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kilograms: Double
    var revision = 1
    var exportedRevision = 0
    // A durable deletion is retained until HealthKit acknowledges it.
    var deleted = false
    var syncIdentifier: String { "com.philstarkovich.cavecals.weight.\(id.uuidString)" }
}

private struct WeightFile: Codable {
    var version = 1
    var tracking = false
    var unit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms
    var dismissedDay: String?
    var healthSharing = false
    var records: [WeightRecord] = []
}

@MainActor @Observable final class WeightStore {
    private var data = WeightFile()
    private let fileURL: URL?
    private let health: any WeightHealthExporting
    private var loadFailed = false
    private(set) var syncing = false
    private(set) var connecting = false
    var error: String?
    private(set) var healthMessage: String?
    var tracking: Bool { data.tracking }
    var unit: WeightUnit { data.unit }
    var healthSharing: Bool { data.healthSharing }
    var healthAvailable: Bool { health.available }
    var records: [WeightRecord] { data.records.filter { !$0.deleted }.sorted { $0.date > $1.date } }
    var pendingCount: Int { data.records.filter { $0.deleted || $0.revision != $0.exportedRevision }.count }

    init(inMemory: Bool = false, fileURL: URL? = nil, health: (any WeightHealthExporting)? = nil) {
        self.health = health ?? WeightHealthExporter()
        self.fileURL = inMemory ? nil : (fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WeightTracking", isDirectory: true).appendingPathComponent("weights-v1.json"))
        if let url = self.fileURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let loaded = try JSONDecoder().decode(WeightFile.self, from: Data(contentsOf: url))
                guard loaded.version == 1, loaded.records.allSatisfy({ ($0.deleted || Self.valid($0.kilograms)) && $0.revision > 0 }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                data = loaded
            } catch {
                loadFailed = true
                self.error = "Your weigh-ins couldn’t be opened. Reopen Cave Cals to try again. Your saved file has not been changed."
            }
        }
    }

    static func valid(_ kilograms: Double) -> Bool { kilograms.isFinite && kilograms >= 1 && kilograms <= 700 }
    func record(on date: Date, calendar: Calendar = .current) -> WeightRecord? {
        records.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func shouldPrompt(on now: Date = Date(), calendar: Calendar = .current) -> Bool {
        tracking && !loadFailed && record(on: now, calendar: calendar) == nil && data.dismissedDay != Day.key(now, calendar: calendar)
    }
    func dismissToday(_ now: Date = Date(), calendar: Calendar = .current) {
        var next = data; next.dismissedDay = Day.key(now, calendar: calendar); _ = persist(next)
    }
    func setTracking(_ enabled: Bool) { var next = data; next.tracking = enabled; _ = persist(next) }
    func setUnit(_ unit: WeightUnit) { var next = data; next.unit = unit; _ = persist(next) }

    @discardableResult func save(kilograms: Double, date: Date, id: UUID? = nil, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard Self.valid(kilograms), date <= now else { error = "Enter a valid weight and a date no later than today."; return false }
        let sameDay = record(on: date, calendar: calendar)
        if let id, let sameDay, sameDay.id != id {
            error = "There’s already a weigh-in for that day. Edit that entry instead."; return false
        }
        var next = data
        if let target = id ?? sameDay?.id {
            guard let index = next.records.firstIndex(where: { $0.id == target && !$0.deleted }) else {
                error = "This weigh-in no longer exists."; return false
            }
            next.records[index].kilograms = kilograms
            next.records[index].date = date
            next.records[index].revision += 1
        } else { next.records.append(WeightRecord(date: date, kilograms: kilograms)) }
        guard persist(next) else { return false }
        Task { await syncHealth() }
        return true
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        var next = data
        guard let index = next.records.firstIndex(where: { $0.id == id }) else { return false }
        // Even a failed export may have reached HealthKit before an interruption.
        next.records[index].deleted = true
        // Retain only the identity needed to delete the Health copy, not the measurement.
        next.records[index].kilograms = 0
        next.records[index].date = .distantPast
        next.records[index].revision += 1
        guard persist(next) else { return false }
        Task { await syncHealth() }
        return true
    }

    func setHealthSharing(_ enabled: Bool) async {
        guard !connecting else { return }
        if !enabled {
            var next = data; next.healthSharing = false
            if persist(next) { healthMessage = "Sharing paused. Weigh-ins already in Apple Health stay there." }
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            try await health.authorize()
            guard health.authorized else { throw WeightHealthError.permission }
            var next = data; next.healthSharing = true
            guard persist(next) else { return }
            await syncHealth()
        } catch { healthMessage = error.localizedDescription }
    }

    func syncHealth() async {
        guard healthSharing, !syncing, !loadFailed else { return }
        guard health.available, health.authorized else {
            healthMessage = "Weigh-ins are saved here. Allow Cave Cals to write Weight in Apple Health to resume sharing."
            return
        }
        syncing = true
        defer { syncing = false }
        do {
            while healthSharing, let record = data.records.first(where: { $0.deleted || $0.revision != $0.exportedRevision }) {
                if record.deleted { try await health.delete(record) }
                else { try await health.save(record) }
                var next = data
                // A user may edit/delete this record while the HealthKit operation is suspended.
                if let index = next.records.firstIndex(where: { $0.id == record.id }), next.records[index].revision == record.revision {
                    if record.deleted { next.records.remove(at: index) }
                    else { next.records[index].exportedRevision = record.revision }
                    guard persist(next) else { return }
                }
            }
            if healthSharing { healthMessage = "Weigh-ins are up to date in Apple Health." }
        } catch {
            healthMessage = "Saved in Cave Cals. Apple Health sharing couldn’t finish. Try again when your device is unlocked."
        }
    }

    private func persist(_ next: WeightFile) -> Bool {
        guard !loadFailed else { return false }
        do {
            if let fileURL {
                var folder = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Weight is deliberately separate from the diary's CloudKit-backed store.
                var resources = URLResourceValues(); resources.isExcludedFromBackup = true
                try folder.setResourceValues(resources)
                try JSONEncoder().encode(next).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            data = next; error = nil; return true
        } catch {
            self.error = "Your weigh-in changes couldn’t be saved. Please try again."
            return false
        }
    }
}

enum WeightChartRange: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
    func interval(endingAt date: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: date)
        var end = calendar.date(byAdding: .day, value: 1, to: today)!
        let start: Date
        switch self {
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today)!
        case .year:
            let month = calendar.dateInterval(of: .month, for: today)!
            start = calendar.date(byAdding: .month, value: -11, to: month.start)!
            // Browsing years must include the entire final month, without gaps between periods.
            end = month.end
        }
        return DateInterval(start: start, end: end)
    }
    func points(_ records: [WeightRecord], endingAt date: Date, calendar: Calendar = .current) -> [WeightChartPoint] {
        let range = interval(endingAt: date, calendar: calendar)
        let values = records.filter { !$0.deleted && $0.date >= range.start && $0.date < range.end }
        let groups = Dictionary(grouping: values) {
            self == .year ? calendar.dateInterval(of: .month, for: $0.date)!.start : calendar.startOfDay(for: $0.date)
        }
        return groups.map { day, entries in
            WeightChartPoint(date: day, kilograms: entries.reduce(0) { $0 + $1.kilograms } / Double(entries.count), count: entries.count)
        }.sorted { $0.date < $1.date }
    }
}

struct WeightChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let kilograms: Double
    let count: Int
}

// Calendar arithmetic keeps the Sunday–Saturday picker aligned across DST and year boundaries.
enum WeightWeek {
    static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = calendar.component(.weekday, from: day) - 1
        let sunday = calendar.date(byAdding: .day, value: -offset, to: day)!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: sunday)! }
    }
}
