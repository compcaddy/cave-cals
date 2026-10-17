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
    func testWeekPickerAlwaysStartsSundayAcrossYearAndDST() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let newYear = WeightWeek.days(containing: date(2026, 1, 1), calendar: mondayFirst)
        XCTAssertEqual(newYear.first, date(2025, 12, 28, 0))
        XCTAssertEqual(newYear.last, date(2026, 1, 3, 0))
        let spring = WeightWeek.days(containing: date(2026, 3, 10), calendar: calendar)
        XCTAssertEqual(spring.count, 7)
        XCTAssertEqual(spring.first, date(2026, 3, 8, 0))
        XCTAssertEqual(spring.last, date(2026, 3, 14, 0))
        XCTAssertEqual(spring.map { calendar.component(.hour, from: $0) }, Array(repeating: 0, count: 7))
        XCTAssertEqual(spring[1].timeIntervalSince(spring[0]), 23 * 60 * 60)
    }

    func testWeighInDialStartsFromNearestEarlierThenLaterWeighIn() {
        let early = WeightRecord(date: date(2026, 9, 10, 7), kilograms: 80)
        let middle = WeightRecord(date: date(2026, 9, 14, 7), kilograms: 81)
        let late = WeightRecord(date: date(2026, 9, 18, 7), kilograms: 82)
        let records = [late, early, middle]
        XCTAssertNil(WeighInStart.reference(for: date(), in: [], calendar: calendar))
        XCTAssertEqual(WeighInStart.reference(for: date(2026, 9, 18, 20), in: records, calendar: calendar), late)
        XCTAssertEqual(WeighInStart.reference(for: date(2026, 9, 16), in: records, calendar: calendar), middle)
        XCTAssertEqual(WeighInStart.reference(for: date(2026, 9, 30), in: records, calendar: calendar), late)
        XCTAssertEqual(WeighInStart.reference(for: date(2026, 9, 1), in: records, calendar: calendar), early)
        XCTAssertEqual(WeighInStart.tenths(around: [early, late], including: nil, unit: .kilograms), 500...1120)
        XCTAssertEqual(WeighInStart.tenths(around: [WeightRecord(date: date(), kilograms: 2)], including: nil, unit: .kilograms), 10...320)
        XCTAssertEqual(WeighInStart.tenths(around: [], including: nil, unit: .kilograms), 10...7000)
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
    func testProgressWeightChartUsesRecordedDaysAndWeeklyAverages() {
        let records = [WeightRecord(date: date(2026, 8, 1), kilograms: 90), WeightRecord(date: date(2026, 9, 16), kilograms: 80), WeightRecord(date: date(), kilograms: 82)]
        let data = ProgressData(drafts: [], records: records, now: date(), calendar: calendar)
        let weekly = data.buckets(.week, containing: date())
        XCTAssertEqual(weekly.compactMap(\.weight), [80, 82])
        let yearly = data.buckets(.year, containing: date()).filter { $0.weight != nil }
        XCTAssertEqual(yearly.compactMap(\.weight), [90, 81])
        XCTAssertEqual(yearly.map(\.weighIns), [1, 2])
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

    // MARK: Apple Health import

    private func reading(_ day: Int, _ hour: Int, _ kilograms: Double, source: String = "Withings", id: UUID = UUID()) -> HealthWeighIn {
        HealthWeighIn(id: id, date: date(2026, 9, day, hour), kilograms: kilograms, source: source)
    }
    private func merge(_ samples: [HealthWeighIn], into records: [WeightRecord] = [], ignoring: Set<UUID> = []) -> WeightHealthImport.Result {
        WeightHealthImport.merge(samples, into: records, ignoring: ignoring, now: date(2026, 9, 18, 20), calendar: calendar)
    }
    func testImportTakesEachDaysFirstReadingAndNeverReplacesOneLoggedHere() {
        let typed = WeightRecord(date: date(2026, 9, 16, 9), kilograms: 80, revision: 2, exportedRevision: 2)
        let result = merge([reading(16, 7, 79), reading(17, 18, 81), reading(17, 6, 80.5), reading(18, 6, 80.2)], into: [typed])
        XCTAssertEqual(result.added, 2)
        let byDay = Dictionary(uniqueKeysWithValues: result.records.map { (calendar.component(.day, from: $0.date), $0) })
        XCTAssertEqual(byDay[16], typed, "A weigh-in logged in Cave Cals wins its day")
        XCTAssertEqual(byDay[17]?.kilograms, 80.5, "The day's first reading")
        XCTAssertEqual(byDay[17]?.healthSource, "Withings")
        XCTAssertTrue(byDay[17]?.fromOtherApp == true)
        // Never written back: nothing pending for Health.
        XCTAssertTrue(result.records.allSatisfy { $0.revision == $0.exportedRevision })
    }
    func testLateEarlierReadingReplacesAndDeletedReadingGivesWayOrLeaves() throws {
        let morning = reading(17, 7, 80), evening = reading(17, 19, 81), other = reading(16, 7, 79)
        let first = merge([evening, other])
        let shown = try XCTUnwrap(first.records.first { $0.healthSampleID == evening.id })
        // A 7 AM reading syncs in after the evening one: it takes the day, same weigh-in.
        let second = merge([evening, other, morning], into: first.records)
        let replaced = try XCTUnwrap(second.records.first { $0.id == shown.id })
        XCTAssertEqual(replaced.healthSampleID, morning.id); XCTAssertEqual(replaced.kilograms, 80)
        XCTAssertEqual(second.added, 0)
        // The morning reading is deleted in Apple Health: the evening one comes back.
        let third = merge([evening, other], into: second.records)
        XCTAssertEqual(third.records.first { $0.id == shown.id }?.healthSampleID, evening.id)
        // Both deleted: the day empties.
        let fourth = merge([other], into: third.records)
        XCTAssertNil(fourth.records.first { $0.id == shown.id })
        XCTAssertEqual(fourth.records.count, 1)
    }
    func testEmptyAnswerRemovesNothingBecauseReadingMayBeOff() {
        let imported = merge([reading(17, 7, 80)]).records
        let own = HealthWeighIn(id: UUID(), date: date(2026, 9, 16, 7), kilograms: 80, source: "Cave Cals", ownID: UUID(), ownRevision: 1)
        XCTAssertEqual(merge([], into: imported).records, imported)
        XCTAssertEqual(merge([own], into: imported).records.filter(\.fromOtherApp), imported, "Only Cave Cals' own came back")
    }
    func testRemovedReadingStaysOutButTheNextOneThatDayComesIn() {
        let wrong = reading(17, 7, 40), retry = reading(17, 7, 80)
        let result = merge([wrong, retry, reading(16, 7, 79)], ignoring: [wrong.id])
        XCTAssertEqual(result.records.first { calendar.component(.day, from: $0.date) == 17 }?.healthSampleID, retry.id)
        XCTAssertTrue(merge([wrong, reading(16, 7, 79)], ignoring: [wrong.id]).records.allSatisfy { calendar.component(.day, from: $0.date) == 16 })
    }
    func testOwnSamplesComeBackAsTheSameWeighInsAndBeatAScaleReading() throws {
        let id = UUID(), deletedID = UUID()
        let scale = merge([reading(17, 6, 79)]).records
        let tombstone = WeightRecord(id: deletedID, date: .distantPast, kilograms: 0, revision: 3, exportedRevision: 2, deleted: true)
        let samples = [
            HealthWeighIn(id: UUID(), date: date(2026, 9, 17, 8), kilograms: 80, source: "Cave Cals", ownID: id, ownRevision: 4),
            HealthWeighIn(id: UUID(), date: date(2026, 9, 15, 8), kilograms: 81, source: "Cave Cals", ownID: deletedID, ownRevision: 2),
            reading(17, 6, 79),
        ]
        let result = merge(samples, into: scale + [tombstone])
        let restored = try XCTUnwrap(result.records.first { $0.id == id })
        XCTAssertEqual(restored.revision, 4); XCTAssertEqual(restored.exportedRevision, 4)
        XCTAssertFalse(restored.fromOtherApp); XCTAssertTrue(restored.readFromHealth)
        XCTAssertEqual(restored.syncIdentifier, "com.philstarkovich.cavecals.weight.\(id.uuidString)")
        XCTAssertEqual(WeightRecord.id(fromSyncIdentifier: restored.syncIdentifier), id)
        XCTAssertFalse(result.records.contains { $0.fromOtherApp }, "Someone's own weigh-in wins over the scale's")
        XCTAssertFalse(result.records.contains { !$0.deleted && $0.id == deletedID }, "A pending deletion isn't brought back")
    }
    func testImportSkipsFutureAndImpossibleReadings() {
        let result = merge([HealthWeighIn(id: UUID(), date: date(2026, 9, 19, 7), kilograms: 80, source: "Scale"), reading(17, 7, 0.2), reading(16, 7, 900)])
        XCTAssertTrue(result.records.isEmpty)
    }
    func testStoreImportsOnlyAfterReadingWasAskedAndNeverExportsImports() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Sharing turned on in an older version, which asked only to write.
        let health = FakeWeightHealth(); health.readAsked = false; health.asksRead = false
        health.samples = [reading(17, 7, 80), reading(16, 7, 79)]
        let store = WeightStore(fileURL: url, health: health)
        store.setTracking(true)
        await store.setHealthSharing(true)
        XCTAssertEqual(store.healthReadRequested, false)
        XCTAssertTrue(store.records.isEmpty); XCTAssertFalse(health.backgroundDelivery)
        health.asksRead = true
        await store.allowHealthImport()
        XCTAssertEqual(store.healthReadRequested, true)
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.healthMessage, "Brought in 2 weigh-ins from Apple Health.")
        XCTAssertTrue(health.backgroundDelivery)
        XCTAssertEqual(store.pendingCount, 0); XCTAssertTrue(health.saved.isEmpty)
        // Kept across a relaunch.
        let reopened = WeightStore(fileURL: url, health: health)
        XCTAssertEqual(reopened.records.map(\.healthSampleID), store.records.map(\.healthSampleID))
        await reopened.setHealthSharing(false)
        XCTAssertFalse(health.backgroundDelivery)
    }
    func testEditingAnImportMakesItYoursAndDeletingOneKeepsItOut() async throws {
        let health = FakeWeightHealth()
        let scale = reading(17, 7, 80), other = reading(16, 7, 79)
        health.samples = [scale, other]
        let store = WeightStore(inMemory: true, health: health)
        store.setTracking(true)
        await store.setHealthSharing(true)
        let imported = try XCTUnwrap(store.records.first { $0.healthSampleID == scale.id })
        // Saved unchanged, it stays an import.
        XCTAssertTrue(store.save(kilograms: 80, date: imported.date, id: imported.id, now: date(2026, 9, 18, 20)))
        XCTAssertEqual(store.records.first { $0.id == imported.id }, imported)
        XCTAssertTrue(store.save(kilograms: 79.5, date: imported.date, id: imported.id, now: date(2026, 9, 18, 20)))
        await store.syncHealth()
        let edited = try XCTUnwrap(store.records.first { $0.id == imported.id })
        XCTAssertFalse(edited.fromOtherApp); XCTAssertFalse(edited.readFromHealth)
        XCTAssertEqual(health.saved.map(\.id), [imported.id], "Edited, it's shared like any weigh-in logged here")
        XCTAssertEqual(edited.kilograms, 79.5, "The scale's reading doesn't replace it")
        // Deleting another app's reading never touches Health, and it doesn't come back.
        let otherRecord = try XCTUnwrap(store.records.first { $0.healthSampleID == other.id })
        XCTAssertTrue(store.delete(otherRecord.id))
        await store.syncHealth()
        XCTAssertNil(store.records.first { $0.healthSampleID == other.id })
        XCTAssertTrue(health.deleted.isEmpty)
    }
}

@MainActor private final class FakeWeightHealth: WeightHealthExporting {
    var available = true
    var authorized = true
    var readAsked = true
    /// False stands in for older versions, which asked only to write.
    var asksRead = true
    var fail = false
    var saved: [WeightRecord] = []
    var deleted: [UUID] = []
    var live: [UUID: WeightRecord] = [:]
    var samples: [HealthWeighIn] = []
    var backgroundDelivery = false
    var onSave: ((WeightRecord) -> Void)?
    func authorize() async throws { if asksRead { readAsked = true } }
    func save(_ record: WeightRecord) async throws {
        if fail { throw WeightHealthError.failed }
        saved.append(record)
        let hook = onSave; onSave = nil; hook?(record)
        if record.revision > (live[record.id]?.revision ?? 0) { live[record.id] = record }
    }
    func delete(_ record: WeightRecord) async throws {
        if fail { throw WeightHealthError.failed }
        deleted.append(record.id)
        live.removeValue(forKey: record.id)
    }
    func readRequested() async -> Bool { readAsked }
    func weighIns() async throws -> [HealthWeighIn] { samples }
    func observe(_ changed: @escaping @MainActor () async -> Void) {}
    func setBackgroundDelivery(_ enabled: Bool) async throws { backgroundDelivery = enabled }
}
