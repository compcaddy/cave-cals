import Foundation
import HealthKit
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
    /// The Apple Health sample another app saved (a scale, say) that this weigh-in shows. Nil for weigh-ins logged
    /// in Cave Cals. These are never written back to Health.
    var healthSampleID: UUID? = nil
    /// Who saved it in Apple Health, for any weigh-in read from there. Editing a weigh-in makes it yours again.
    var healthSource: String? = nil
    var syncIdentifier: String { Self.syncPrefix + id.uuidString }
    /// Came from another app through Apple Health.
    var fromOtherApp: Bool { healthSampleID != nil }
    /// Read from Apple Health (another app's, or Cave Cals' own brought back after a reinstall). Clans leave these out.
    var readFromHealth: Bool { healthSource != nil }
    private static let syncPrefix = "com.philstarkovich.cavecals.weight."
    static func id(fromSyncIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(syncPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(syncPrefix.count)))
    }
}

private struct WeightFile: Codable {
    var version = 1
    var tracking = false
    var unit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms
    var dismissedDay: String?
    var healthSharing = false
    var caloriePlan: SavedCaloriePlan?
    var records: [WeightRecord] = []
    /// Other apps' Health readings removed in Cave Cals, so they aren't brought back.
    var ignoredHealthSamples: [UUID]?
}

@MainActor @Observable final class WeightStore {
    private var data = WeightFile()
    private let fileURL: URL?
    private let health: any WeightHealthExporting
    private var loadFailed = false
    private(set) var syncing = false
    private(set) var importing = false
    /// Asked to import while an import was running; it runs once more with the newest Health data.
    private var importAgain = false
    private(set) var connecting = false
    /// Whether Apple's sheet has asked to read weight; nil until checked. People who turned sharing on before
    /// Cave Cals read weigh-ins haven't been asked yet.
    private(set) var healthReadRequested: Bool?
    var error: String?
    private(set) var healthMessage: String?
    var caloriePlan: SavedCaloriePlan? { data.caloriePlan }
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
                Task { @MainActor in UsageStats.shared.error(.weights, error) }
            }
        }
        // Set up as the app starts, so Apple Health can wake it in the background with a new weigh-in.
        if self.fileURL != nil && data.healthSharing {
            observeHealth()
            Task { await startHealthUpdates() }
        }
    }

    nonisolated static func valid(_ kilograms: Double) -> Bool { kilograms.isFinite && kilograms >= 1 && kilograms <= 700 }
    func record(on date: Date, calendar: Calendar = .current) -> WeightRecord? {
        records.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func shouldPrompt(on now: Date = Date(), calendar: Calendar = .current) -> Bool {
        tracking && !loadFailed && record(on: now, calendar: calendar) == nil && data.dismissedDay != Day.key(now, calendar: calendar)
    }
    func dismissToday(_ now: Date = Date(), calendar: Calendar = .current) {
        var next = data; next.dismissedDay = Day.key(now, calendar: calendar); _ = persist(next)
    }
    @discardableResult func saveCaloriePlan(_ plan: SavedCaloriePlan, unit: WeightUnit, trackWeight: Bool, now: Date = Date()) -> Bool {
        guard CaloriePlanner.estimate(plan.input) != nil,
              plan.calorieGoal.isFinite, plan.calorieGoal >= plan.input.gender.minimumCalories, plan.calorieGoal <= 6000 else {
            error = "Check your plan before saving."; return false
        }
        var next = data
        next.caloriePlan = plan; next.unit = unit; next.tracking = trackWeight
        if trackWeight && record(on: now) == nil {
            next.records.append(WeightRecord(date: now, kilograms: plan.input.weightKG))
        }
        guard persist(next) else { return false }
        // Existing Health authorization is respected; onboarding never requests it.
        Task { await syncHealth() }
        return true
    }

    @discardableResult func setTracking(_ enabled: Bool) -> Bool {
        var next = data; next.tracking = enabled
        return persist(next)
    }
    func setUnit(_ unit: WeightUnit) { var next = data; next.unit = unit; _ = persist(next) }
    @discardableResult func forgetCaloriePlan() -> Bool {
        var next = data; next.caloriePlan = nil
        return persist(next)
    }

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
            // Saved unchanged, it stays as it was (one from Apple Health stays one).
            if next.records[index].kilograms == kilograms && next.records[index].date == date { error = nil; return true }
            next.records[index].kilograms = kilograms
            next.records[index].date = date
            next.records[index].revision += 1
            // Edited, it's yours: shared to Health like any weigh-in logged here, and never replaced by a reading.
            next.records[index].healthSampleID = nil
            next.records[index].healthSource = nil
        } else { next.records.append(WeightRecord(date: date, kilograms: kilograms)) }
        guard persist(next) else { return false }
        if id == nil && sameDay == nil { UsageStats.shared.count(.weighIns) }
        Task { await syncHealth() }
        return true
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        var next = data
        guard let index = next.records.firstIndex(where: { $0.id == id }) else { return false }
        if let sample = next.records[index].healthSampleID {
            // Another app's reading stays in Apple Health; Cave Cals just won't bring it back.
            next.records.remove(at: index)
            next.ignoredHealthSamples = (next.ignoredHealthSamples ?? []) + [sample]
            return persist(next)
        }
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
            if persist(next) { healthMessage = "Sync paused. Weigh-ins already in Apple Health stay there, and so do the ones brought in here." }
            try? await health.setBackgroundDelivery(false)
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            try await health.authorize()
            guard health.authorized else { throw WeightHealthError.permission }
            var next = data; next.healthSharing = true
            guard persist(next) else { return }
            await startHealthUpdates()
            await syncHealth()
        } catch {
            healthMessage = error.localizedDescription
            if case WeightHealthError.permission = error {} else { UsageStats.shared.error(.appleHealth, error) }
        }
    }

    /// Shares what's pending, then brings in weigh-ins from other apps.
    func syncHealth() async {
        await exportToHealth()
        await importFromHealth()
    }

    /// For people who turned sharing on before Cave Cals read weigh-ins: Apple's sheet asks about reading weight.
    func allowHealthImport() async {
        guard !connecting, healthSharing else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await health.authorize()
            await startHealthUpdates()
            await importFromHealth()
        } catch {
            healthMessage = error.localizedDescription
            UsageStats.shared.error(.appleHealth, error)
        }
    }

    /// Brings in weigh-ins other apps saved to Apple Health (see `WeightHealthImport` for the rules), plus Cave
    /// Cals' own from before a reinstall or from another iPhone. Runs on opening, from Sync now, and whenever
    /// Apple Health gets a new weight, in the background too.
    func importFromHealth(now: Date = Date(), calendar: Calendar = .current) async {
        guard healthSharing, tracking, !loadFailed, health.available else { return }
        guard !importing else { importAgain = true; return }
        importing = true
        defer { importing = false }
        repeat {
            importAgain = false
            let requested = await health.readRequested()
            healthReadRequested = requested
            guard requested else { return }
            do {
                let samples = try await health.weighIns()
                // Turned off meanwhile, or edits made while waiting: merge into what's current.
                guard healthSharing, tracking else { return }
                let result = WeightHealthImport.merge(samples, into: data.records, ignoring: Set(data.ignoredHealthSamples ?? []),
                                                      now: now, calendar: calendar)
                guard result.records != data.records else { continue }
                var next = data; next.records = result.records
                guard persist(next) else { return }
                if result.added > 0 {
                    healthMessage = result.added == 1 ? "Brought in 1 weigh-in from Apple Health."
                        : "Brought in \(result.added.formatted()) weigh-ins from Apple Health."
                    UsageStats.shared.event("health.weightImport", ["added": String(result.added)])
                }
            } catch {
                // Apple Health is locked with the iPhone; the next opening or new weigh-in tries again.
                if (error as? HKError)?.code != .errorDatabaseInaccessible { UsageStats.shared.error(.appleHealth, error) }
                return
            }
        } while importAgain
    }

    private func observeHealth() {
        health.observe { [self] in await importFromHealth() }
    }
    /// Watches Apple Health for new weights, and lets iOS wake Cave Cals for them once reading was asked.
    private func startHealthUpdates() async {
        observeHealth()
        guard await health.readRequested() else { return }
        do { try await health.setBackgroundDelivery(true) }
        catch { UsageStats.shared.error(.appleHealth, error) }
    }

    private func exportToHealth() async {
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
            UsageStats.shared.error(.appleHealth, error)
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
            UsageStats.shared.error(.weights, error)
            return false
        }
    }
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

/// Where the weigh-in dial starts for a day without its own weigh-in.
enum WeighInStart {
    /// The day's own weigh-in, else the latest one before it, else the earliest one after it.
    /// Nil only when there are no weigh-ins at all, so the first one is typed.
    static func reference(for date: Date, in records: [WeightRecord], calendar: Calendar = .current) -> WeightRecord? {
        let day = calendar.startOfDay(for: date)
        if let same = records.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) { return same }
        let before = records.filter { $0.date < day }.max { $0.date < $1.date }
        return before ?? records.filter { $0.date > day }.min { $0.date < $1.date }
    }
    /// The dial's span in tenths of the display unit: 30 units around every weigh-in, within valid weights.
    static func tenths(around records: [WeightRecord], including value: Int?, unit: WeightUnit) -> ClosedRange<Int> {
        let shown = records.map { Int((unit.display($0.kilograms) * 10).rounded()) } + [value].compactMap { $0 }
        let lowest = Int((unit.display(1) * 10).rounded(.up)), highest = Int((unit.display(700) * 10).rounded(.down))
        guard let low = shown.min(), let high = shown.max() else { return lowest...highest }
        return max(lowest, low - 300)...min(highest, high + 300)
    }
}

/// Brings Apple Health weigh-ins into the records, one a day:
/// - A weigh-in logged in Cave Cals always wins its day.
/// - Otherwise the day shows its first reading from another app (a scale, say). An earlier reading that syncs in
///   later takes its place, and so does the next one when the shown reading is deleted in Apple Health.
/// - A reading removed in Cave Cals never comes back (`ignored`).
/// - Cave Cals' own samples, from before a reinstall or from another iPhone, come back as the same weigh-ins.
enum WeightHealthImport {
    struct Result: Equatable {
        var records: [WeightRecord]
        /// Days that gained a weigh-in.
        var added: Int
    }

    static func merge(_ samples: [HealthWeighIn], into existing: [WeightRecord], ignoring ignored: Set<UUID>,
                      now: Date = Date(), calendar: Calendar = .current) -> Result {
        func day(_ date: Date) -> String { Day.key(date, calendar: calendar) }
        var records = existing
        var removed = Set<UUID>()
        var live: [String: Int] = [:]
        for (index, record) in records.enumerated() where !record.deleted && live[day(record.date)] == nil {
            live[day(record.date)] = index
        }
        let usable = samples.filter { WeightStore.valid($0.kilograms) && $0.date <= now }
        var known = Set(records.map(\.id))

        // Cave Cals' own first: someone logged them, so they win over another app's reading.
        for sample in usable {
            guard let id = sample.ownID, !known.contains(id) else { continue }
            let key = day(sample.date)
            if let index = live[key] {
                guard records[index].fromOtherApp else { continue }
                removed.insert(records[index].id)
            }
            let revision = max(sample.ownRevision ?? 1, 1)
            live[key] = records.count
            records.append(WeightRecord(id: id, date: sample.date, kilograms: sample.kilograms, revision: revision,
                                        exportedRevision: revision, healthSource: sample.source))
            known.insert(id)
        }

        let others = usable.filter { $0.ownID == nil && !ignored.contains($0.id) }
        let byDay = Dictionary(grouping: others) { day($0.date) }
        for key in byDay.keys.sorted() {
            let readings = byDay[key]!
            let first = readings.min { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }!
            if let index = live[key] {
                guard let shown = records[index].healthSampleID, shown != first.id,
                      first.date < records[index].date || !readings.contains(where: { $0.id == shown }) else { continue }
                records[index].date = first.date
                records[index].kilograms = first.kilograms
                records[index].healthSampleID = first.id
                records[index].healthSource = first.source
            } else {
                live[key] = records.count
                records.append(WeightRecord(date: first.date, kilograms: first.kilograms, revision: 1, exportedRevision: 1,
                                            healthSampleID: first.id, healthSource: first.source))
            }
        }

        // A reading deleted in Apple Health leaves with it. iOS answers "nothing" when reading isn't allowed too,
        // so nothing is removed unless other apps' weigh-ins came back at all.
        if samples.contains(where: { $0.ownID == nil }) {
            let present = Set(samples.map(\.id))
            for record in records where !record.deleted {
                if let sample = record.healthSampleID, !present.contains(sample) { removed.insert(record.id) }
            }
        }
        records.removeAll { removed.contains($0.id) }

        let before = Set(existing.filter { !$0.deleted }.map { day($0.date) })
        let after = Set(records.filter { !$0.deleted }.map { day($0.date) })
        return Result(records: records, added: after.subtracting(before).count)
    }
}
