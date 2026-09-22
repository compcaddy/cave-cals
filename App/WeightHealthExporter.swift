import Foundation
import HealthKit

@MainActor protocol WeightHealthExporting {
    var available: Bool { get }
    var authorized: Bool { get }
    func authorize() async throws
    func save(_ record: WeightRecord) async throws
    func delete(_ record: WeightRecord) async throws
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
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorized: Bool { available && store.authorizationStatus(for: type) == .sharingAuthorized }
    func authorize() async throws {
        guard available else { throw WeightHealthError.unavailable }
        // Export only. Never ask to read unrelated health data.
        try await store.requestAuthorization(toShare: [type], read: [])
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
}
