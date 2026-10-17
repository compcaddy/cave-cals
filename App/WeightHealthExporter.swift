import Foundation
import HealthKit

/// A weight sample read from Apple Health. `ownID` is set when Cave Cals saved it (from its sync identifier),
/// on this iPhone or another, so those come back as the same weigh-in rather than as another app's reading.
struct HealthWeighIn: Equatable {
    var id: UUID
    var date: Date
    var kilograms: Double
    /// The app or device that saved it, as Apple Health names it ("Withings", "Health").
    var source: String
    var ownID: UUID? = nil
    var ownRevision: Int? = nil
}

@MainActor protocol WeightHealthExporting {
    var available: Bool { get }
    var authorized: Bool { get }
    /// Asks to write weight and to read it (Apple shows one sheet with both).
    func authorize() async throws
    func save(_ record: WeightRecord) async throws
    func delete(_ record: WeightRecord) async throws
    /// True once Apple's sheet has asked about reading weight. iOS never says whether reading was allowed.
    func readRequested() async -> Bool
    /// Every weight sample Cave Cals may read, oldest first. With reading declined, only Cave Cals' own come back.
    func weighIns() async throws -> [HealthWeighIn]
    /// Calls `changed` whenever Apple Health gets a new or deleted weight. With background delivery on, iOS also
    /// wakes the app for it (at most hourly).
    func observe(_ changed: @escaping @MainActor () async -> Void)
    func setBackgroundDelivery(_ enabled: Bool) async throws
}

enum WeightHealthError: LocalizedError {
    case unavailable, permission, failed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device. You can still track weight in Cave Cals."
        case .permission: "Weight sharing wasn’t allowed. You can enable it for Cave Cals in Apple Health. Your weigh-ins are still saved here."
        case .failed: "Apple Health couldn’t complete the request. Please try again."
        }
    }
}

@MainActor final class WeightHealthExporter: WeightHealthExporting {
    private let store = HKHealthStore()
    private let type = HKQuantityType(.bodyMass)
    private var observer: HKObserverQuery?
    var available: Bool { !AppEnvironment.isDevelopment && HKHealthStore.isHealthDataAvailable() }
    var authorized: Bool { available && store.authorizationStatus(for: type) == .sharingAuthorized }
    func authorize() async throws {
        guard available else { throw WeightHealthError.unavailable }
        // Weight only, both ways. Never ask to read anything else.
        try await store.requestAuthorization(toShare: [type], read: [type])
    }
    func save(_ record: WeightRecord) async throws {
        guard authorized else { throw WeightHealthError.permission }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: record.kilograms),
            start: record.date, end: record.date, metadata: [
                HKMetadataKeyWasUserEntered: true,
                HKMetadataKeySyncIdentifier: record.syncIdentifier,
                HKMetadataKeySyncVersion: record.revision
            ])
        // HealthKit replaces older versions with the same identifier; retries are idempotent.
        try await store.save(sample)
    }
    func delete(_ record: WeightRecord) async throws {
        guard authorized else { throw WeightHealthError.permission }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [record.syncIdentifier]),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: type, predicate: predicate) { success, _, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WeightHealthError.failed) }
            }
        }
    }
    func readRequested() async -> Bool {
        guard available else { return false }
        return (try? await store.statusForAuthorizationRequest(toShare: [type], read: [type])) == .unnecessary
    }
    func weighIns() async throws -> [HealthWeighIn] {
        guard available else { return [] }
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type)], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await query.result(for: store).map { sample in
            let own = (sample.metadata?[HKMetadataKeySyncIdentifier] as? String).flatMap(WeightRecord.id(fromSyncIdentifier:))
            return HealthWeighIn(id: sample.uuid, date: sample.startDate,
                                 kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                                 source: sample.sourceRevision.source.name, ownID: own,
                                 ownRevision: (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue)
        }
    }
    func observe(_ changed: @escaping @MainActor () async -> Void) {
        guard available, observer == nil else { return }
        // HealthKit can launch the app in the background for this; the store sets it up as the app starts.
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await changed()
                completion()
            }
        }
        observer = query
        store.execute(query)
    }
    func setBackgroundDelivery(_ enabled: Bool) async throws {
        guard available else { return }
        if enabled { try await store.enableBackgroundDelivery(for: type, frequency: .hourly) }
        else { try await store.disableBackgroundDelivery(for: type) }
    }
}
