import Foundation
import HealthKit

/// One diary entry as written to Apple Health: its calories plus any known macros (grams).
struct NutritionExport: Equatable {
    enum Nutrient: String, CaseIterable { case energy, protein, carbohydrates, fat, fiber }
    var id: UUID
    var date: Date
    var name: String
    /// Increases with every edit, so HealthKit replaces the older copy of the same entry.
    var version: Int64
    var values: [Nutrient: Double]

    init(_ entry: CalorieEntry) {
        id = entry.id; date = entry.timestamp; name = entry.foodDisplayName
        version = Int64((entry.updatedAt.timeIntervalSince1970 * 1000).rounded())
        let macros = MacroNutrients.decode(entry.macrosPerServingData)?.scaled(entry.servings)
        let amounts: [Nutrient: Double?] = [.energy: entry.totalCalories.rounded(), .protein: macros?.protein,
                                            .carbohydrates: macros?.totalCarbs, .fat: macros?.fat, .fiber: macros?.fiber]
        values = amounts.compactMapValues { $0 }.filter { $0.value.isFinite && $0.value >= 0 }
    }
}

@MainActor protocol NutritionHealthWriting {
    var available: Bool { get }
    var authorized: Bool { get }
    func authorize() async throws
    /// Saves the entry's nutrients; `replacing` also clears nutrients an earlier version had.
    func write(_ export: NutritionExport, replacing: Bool) async throws
    func delete(_ id: UUID) async throws
}

enum NutritionHealthError: LocalizedError {
    case unavailable, permission, failed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device. Your food log is still saved in Cave Cals."
        case .permission: "Calorie sharing wasn’t allowed. You can enable Dietary Energy for Cave Cals in Apple Health. Your food log is still saved here."
        case .failed: "Apple Health couldn’t complete the request. Please try again."
        }
    }
}

@MainActor final class NutritionHealthWriter: NutritionHealthWriting {
    private let store = HKHealthStore()
    private static let types: [NutritionExport.Nutrient: (type: HKQuantityType, unit: HKUnit)] = [
        .energy: (HKQuantityType(.dietaryEnergyConsumed), .kilocalorie()),
        .protein: (HKQuantityType(.dietaryProtein), .gram()),
        .carbohydrates: (HKQuantityType(.dietaryCarbohydrates), .gram()),
        .fat: (HKQuantityType(.dietaryFatTotal), .gram()),
        .fiber: (HKQuantityType(.dietaryFiber), .gram()),
    ]
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorized: Bool { available && allowed(.energy) }
    private func allowed(_ nutrient: NutritionExport.Nutrient) -> Bool {
        store.authorizationStatus(for: Self.types[nutrient]!.type) == .sharingAuthorized
    }
    func authorize() async throws {
        guard available else { throw NutritionHealthError.unavailable }
        // Export only. Never ask to read Health data.
        try await store.requestAuthorization(toShare: Set(Self.types.values.map(\.type)), read: [])
    }
    static func syncIdentifier(_ id: UUID, _ nutrient: NutritionExport.Nutrient) -> String {
        "cavecals.entry.\(id.uuidString).\(nutrient.rawValue)"
    }
    func write(_ export: NutritionExport, replacing: Bool) async throws {
        guard authorized else { throw NutritionHealthError.permission }
        var samples: [HKObject] = []
        var cleared: [NutritionExport.Nutrient] = []
        // Nutrients the person declined in Health are skipped rather than failing the whole entry.
        for nutrient in NutritionExport.Nutrient.allCases where allowed(nutrient) {
            guard let value = export.values[nutrient], value > 0 else {
                if replacing { cleared.append(nutrient) }
                continue
            }
            let (type, unit) = Self.types[nutrient]!
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: Self.syncIdentifier(export.id, nutrient),
                HKMetadataKeySyncVersion: NSNumber(value: export.version),
            ]
            if !export.name.isEmpty { metadata[HKMetadataKeyFoodType] = export.name }
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: export.date, end: export.date, metadata: metadata))
        }
        // HealthKit keeps the highest version of each sync identifier, so retries and a second iPhone never duplicate.
        if !samples.isEmpty { try await store.save(samples) }
        for nutrient in cleared { try await delete(export.id, nutrient) }
    }
    func delete(_ id: UUID) async throws {
        for nutrient in NutritionExport.Nutrient.allCases where allowed(nutrient) { try await delete(id, nutrient) }
    }
    private func delete(_ id: UUID, _ nutrient: NutritionExport.Nutrient) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [Self.syncIdentifier(id, nutrient)]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: Self.types[nutrient]!.type, predicate: predicate) { success, _, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: NutritionHealthError.failed) }
            }
        }
    }
}

/// Keeps Apple Health's Nutrition data matching the diary from the day sharing was turned on.
/// Per-iPhone and local: the ledger of what was written is never synced or backed up.
@MainActor @Observable final class NutritionHealthSync {
    private struct Ledger: Codable {
        var enabled = false
        var since: Date?
        var exported: [UUID: Int64] = [:]
    }
    private var ledger = Ledger()
    private let fileURL: URL?
    private let writer: any NutritionHealthWriting
    private var queued: [NutritionExport]?
    private(set) var syncing = false
    private(set) var connecting = false
    private(set) var message: String?
    var enabled: Bool { ledger.enabled }
    var available: Bool { writer.available }

    init(inMemory: Bool = false, fileURL: URL? = nil, writer: (any NutritionHealthWriting)? = nil) {
        self.writer = writer ?? NutritionHealthWriter()
        self.fileURL = inMemory ? nil : (fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AppleHealth", isDirectory: true).appendingPathComponent("nutrition-v1.json"))
        if let url = self.fileURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Ledger.self, from: data) { ledger = saved }
    }

    func setEnabled(_ enabled: Bool, entries: [CalorieEntry], now: Date = Date()) async {
        guard !connecting else { return }
        guard enabled else {
            // Pausing keeps the ledger, so resuming fills the gap and still removes entries deleted meanwhile.
            ledger.enabled = false; persist()
            message = "Sharing paused. Food already in Apple Health stays there."
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            try await writer.authorize()
            guard writer.authorized else { throw NutritionHealthError.permission }
            ledger.enabled = true
            ledger.since = ledger.since ?? Calendar.current.startOfDay(for: now)
            persist()
            await sync(entries)
        } catch { message = error.localizedDescription }
    }

    /// Called after every diary change; bursts coalesce and the newest snapshot wins.
    func entriesChanged(_ entries: [CalorieEntry]) {
        guard enabled else { return }
        Task { await sync(entries) }
    }

    func sync(_ entries: [CalorieEntry]) async {
        guard enabled else { return }
        let since = ledger.since ?? Calendar.current.startOfDay(for: Date())
        queued = entries.filter { $0.timestamp >= since }.map(NutritionExport.init)
        guard !syncing else { return }
        guard writer.available, writer.authorized else {
            message = "Your food log is saved here. Allow Cave Cals to write Dietary Energy in Apple Health to resume sharing."
            return
        }
        syncing = true
        defer { syncing = false }
        do {
            while let snapshot = queued {
                queued = nil
                // The newest version of an entry wins if an iCloud hiccup ever duplicates it.
                let desired = Dictionary(snapshot.map { ($0.id, $0) }) { $0.version >= $1.version ? $0 : $1 }
                for export in desired.values.sorted(by: { $0.date < $1.date }) where ledger.exported[export.id] != export.version {
                    try await writer.write(export, replacing: ledger.exported[export.id] != nil)
                    guard enabled else { return }
                    ledger.exported[export.id] = export.version
                    persist()
                }
                // Deleted entries (here or on another iPhone) and entries moved before the start day leave Health too.
                for id in ledger.exported.keys where desired[id] == nil {
                    try await writer.delete(id)
                    guard enabled else { return }
                    ledger.exported[id] = nil
                    persist()
                }
            }
            message = "Food is up to date in Apple Health."
        } catch {
            message = "Saved in Cave Cals. Apple Health sharing couldn’t finish. It will retry when you next open the app."
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            var folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try folder.setResourceValues(resources)
            try JSONEncoder().encode(ledger).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = "Apple Health sharing settings couldn’t be saved. Please try again." }
    }
}
