import XCTest
@testable import CaveCals

@MainActor final class WeightTrackingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 18, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("weights.json")
    }
    func testUnitsValidationAndLocaleInput() {
        XCTAssertEqual(WeightUnit.pounds.kilograms(200), 90.718474, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.pounds.display(90.718474), 200, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.parse("٨٢٫٤", locale: Locale(identifier: "ar_EG")), 82.4)
        XCTAssertEqual(WeightUnit.parse("82,4", locale: Locale(identifier: "de_DE")), 82.4)
        XCTAssertEqual(WeightUnit.parse(" 182.4 ", locale: Locale(identifier: "en_US")), 182.4)
        for value in ["", "-1", "nan", "1.2.3", "100kg", "1,000"] {
            XCTAssertNil(WeightUnit.parse(value, locale: Locale(identifier: "en_US")))
        }
        XCTAssertFalse(WeightStore.valid(.nan)); XCTAssertFalse(WeightStore.valid(.infinity))
        XCTAssertFalse(WeightStore.valid(0)); XCTAssertFalse(WeightStore.valid(701))
    }
    func testDailyReminderDismissalSurvivesReopenAndResetsNextDay() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WeightStore(fileURL: url, health: FakeWeightHealth())
        XCTAssertFalse(store.shouldPrompt(on: date(), calendar: calendar))
        store.setTracking(true)
        XCTAssertTrue(store.shouldPrompt(on: date(), calendar: calendar))
        store.dismissToday(date(), calendar: calendar)
        let reopened = WeightStore(fileURL: url, health: FakeWeightHealth())
        XCTAssertFalse(reopened.shouldPrompt(on: date(), calendar: calendar))
        XCTAssertTrue(reopened.shouldPrompt(on: date(2026, 9, 19), calendar: calendar))
    }
    func testSameDaySaveUpdatesAndTurningOffPreservesHistory() throws {
        let store = WeightStore(inMemory: true, health: FakeWeightHealth())
        store.setTracking(true)
        XCTAssertTrue(store.save(kilograms: 80, date: date(), now: date(), calendar: calendar))
        let id = try XCTUnwrap(store.records.first?.id)
        XCTAssertFalse(store.shouldPrompt(on: date(), calendar: calendar))
        XCTAssertTrue(store.save(kilograms: 81, date: date(2026, 9, 18, 13), now: date(2026, 9, 18, 14), calendar: calendar))
        XCTAssertEqual(store.records.count, 1); XCTAssertEqual(store.records.first?.id, id)
        XCTAssertEqual(store.records.first?.kilograms, 81)
        store.setTracking(false)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertFalse(store.shouldPrompt(on: date(2026, 9, 19), calendar: calendar))
        store.setTracking(true)
        XCTAssertEqual(store.records.first?.kilograms, 81)
    }
    func testHistoricalEditCannotOverwriteAnotherDayAndRejectsFuture() throws {
        let store = WeightStore(inMemory: true, health: FakeWeightHealth())
        store.save(kilograms: 80, date: date(2026, 9, 17), now: date(), calendar: calendar)
        let id = try XCTUnwrap(store.records.first?.id)
        store.save(kilograms: 81, date: date(), now: date(), calendar: calendar)
        XCTAssertFalse(store.save(kilograms: 79, date: date(), id: id, now: date(), calendar: calendar))
        XCTAssertEqual(store.records.count, 2)
        XCTAssertFalse(store.save(kilograms: 80, date: date(2026, 9, 19), now: date(), calendar: calendar))
        XCTAssertTrue(store.save(kilograms: 79, date: date(2026, 9, 16), id: id, now: date(), calendar: calendar))
        XCTAssertEqual(store.record(on: date(2026, 9, 16), calendar: calendar)?.kilograms, 79)
    }
    func testLocalPersistenceAndBackupExclusion() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WeightStore(fileURL: url, health: FakeWeightHealth())
        store.setTracking(true); store.setUnit(.pounds)
        store.save(kilograms: 81.25, date: date(), now: date())
        let reopened = WeightStore(fileURL: url, health: FakeWeightHealth())
        XCTAssertTrue(reopened.tracking); XCTAssertEqual(reopened.unit, .pounds)
        XCTAssertEqual(reopened.records.first?.kilograms, 81.25)
        XCTAssertEqual(try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testCorruptFileIsNeverReplacedWithEmptyHistory() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("unreadable".utf8); try damaged.write(to: url)
        let store = WeightStore(fileURL: url, health: FakeWeightHealth())
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.save(kilograms: 80, date: date(), now: date()))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }
    func testFailedSaveDoesNotChangeMemory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not a directory".utf8).write(to: folder)
        let store = WeightStore(fileURL: folder.appendingPathComponent("weights.json"), health: FakeWeightHealth())
        XCTAssertFalse(store.save(kilograms: 80, date: date(), now: date()))
        XCTAssertTrue(store.records.isEmpty); XCTAssertNotNil(store.error)
    }
    func testChartUsesOnlyRecordedDaysAndMonthlyAverages() {
        let records = [WeightRecord(date: date(2026, 8, 1), kilograms: 90), WeightRecord(date: date(2026, 9, 16), kilograms: 80), WeightRecord(date: date(), kilograms: 82)]
        let weekly = WeightChartRange.week.points(records, endingAt: date(), calendar: calendar)
        XCTAssertEqual(weekly.count, 2)
        XCTAssertEqual(weekly.map(\.kilograms), [80, 82])
        // A chart opened earlier today must include a weigh-in saved later today.
        XCTAssertEqual(WeightChartRange.week.points(records, endingAt: date(2026, 9, 18, 9), calendar: calendar).count, 2)
        let yearly = WeightChartRange.year.points(records, endingAt: date(), calendar: calendar)
        XCTAssertEqual(yearly.map(\.kilograms), [90, 81]); XCTAssertEqual(yearly.map(\.count), [1, 2])
        let previousYear = WeightChartRange.year.interval(endingAt: date(2025, 9, 18), calendar: calendar)
        let currentYear = WeightChartRange.year.interval(endingAt: date(), calendar: calendar)
        XCTAssertEqual(previousYear.end, currentYear.start)
        let lateSeptember = WeightRecord(date: date(2025, 9, 30), kilograms: 85)
        XCTAssertEqual(WeightChartRange.year.points([lateSeptember], endingAt: date(2025, 9, 18), calendar: calendar).count, 1)
        let dst = WeightChartRange.week.interval(endingAt: date(2026, 3, 10), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: dst.start, to: dst.end).day, 7)
    }
    func testHealthDeniedKeepsLocalLoggingWorking() async {
        let health = FakeWeightHealth(); health.authorized = false
        let store = WeightStore(inMemory: true, health: health)
        await store.setHealthSharing(true)
        XCTAssertFalse(store.healthSharing); XCTAssertNotNil(store.healthMessage)
        XCTAssertTrue(store.save(kilograms: 80, date: date(), now: date()))
        await store.syncHealth()
        XCTAssertTrue(health.saved.isEmpty)
    }
    func testHealthRetryCorrectionsAndDeletionAreDurableAndIdempotent() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let health = FakeWeightHealth()
        let store = WeightStore(fileURL: url, health: health)
        store.save(kilograms: 80, date: date(), now: date())
        health.fail = true
        await store.setHealthSharing(true)
        XCTAssertEqual(store.pendingCount, 1)
        let reopened = WeightStore(fileURL: url, health: health)
        health.fail = false
        await reopened.syncHealth()
        XCTAssertEqual(reopened.pendingCount, 0); XCTAssertEqual(health.live.count, 1)
        let id = try XCTUnwrap(reopened.records.first?.id)
        reopened.save(kilograms: 79, date: date(), id: id, now: date())
        await reopened.syncHealth()
        XCTAssertEqual(health.live.count, 1); XCTAssertEqual(health.live[id]?.kilograms, 79)
        await reopened.setHealthSharing(false)
        reopened.delete(id)
        XCTAssertTrue(reopened.records.isEmpty); XCTAssertEqual(health.live.count, 1)
        let afterDelete = WeightStore(fileURL: url, health: health)
        await afterDelete.setHealthSharing(true)
        XCTAssertTrue(health.live.isEmpty); XCTAssertEqual(afterDelete.pendingCount, 0)
    }
    func testEditDuringExportIsNotAcknowledgedAsOldRevision() async {
        let health = FakeWeightHealth()
        let store = WeightStore(inMemory: true, health: health)
        store.save(kilograms: 80, date: date(), now: date())
        health.onSave = { record in
            store.save(kilograms: 79, date: record.date, id: record.id, now: self.date())
        }
        await store.setHealthSharing(true)
        XCTAssertEqual(health.saved.map(\.revision), [1, 2])
        XCTAssertEqual(store.pendingCount, 0); XCTAssertEqual(health.live.values.first?.kilograms, 79)
    }
}

@MainActor private final class FakeWeightHealth: WeightHealthExporting {
    var available = true
    var authorized = true
    var fail = false
    var saved: [WeightRecord] = []
    var live: [UUID: WeightRecord] = [:]
    var onSave: ((WeightRecord) -> Void)?
    func authorize() async throws {}
    func save(_ record: WeightRecord) async throws {
        if fail { throw WeightHealthError.failed }
        saved.append(record)
        let hook = onSave; onSave = nil; hook?(record)
        if record.revision > (live[record.id]?.revision ?? 0) { live[record.id] = record }
    }
    func delete(_ record: WeightRecord) async throws {
        if fail { throw WeightHealthError.failed }
        live.removeValue(forKey: record.id)
    }
}
