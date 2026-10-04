import XCTest
@testable import CaveCals

@MainActor final class UsageStatsTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("UsageStatsTests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "UsageStatsTests-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func makeStats(now: Date = Date()) -> UsageStats {
        UsageStats(fileURL: folder.appendingPathComponent("state.json"), defaults: defaults, recording: true, now: now)
    }

    func testLogMethodsFollowTheSourceEachEntryStores() {
        XCTAssertEqual(LogMethod(source: "suggestion"), .quickAdd)
        XCTAssertEqual(LogMethod(source: "historical"), .searchHistory)
        XCTAssertEqual(LogMethod(source: "common"), .searchBuiltIn)
        XCTAssertEqual(LogMethod(source: "foodSearch"), .searchOnline)
        XCTAssertEqual(LogMethod(source: "manual"), .manual)
        XCTAssertEqual(LogMethod(source: "savedMeal"), .meal)
        XCTAssertEqual(LogMethod(source: "barcode"), .barcode)
        XCTAssertEqual(LogMethod(source: "aiPhoto"), .mealScan)
        XCTAssertEqual(LogMethod(source: "aiVoice"), .voice)
        XCTAssertEqual(LogMethod(source: "something new"), .other)
    }

    func testDaysAreGregorianCalendarDaysInThePersonsTimeZone() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-04T05:30:00Z")!
        XCTAssertEqual(UsageStats.dayKey(instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-10-03")
        XCTAssertEqual(UsageStats.dayKey(instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-10-04")
    }

    func testBackfillCountsOnlyEntriesFromBeforeStatsStartedByDayAndMethod() {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        func at(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let days = UsageStats.backfill([
            (at(3, 8), "suggestion"), (at(3, 12), "suggestion"), (at(3, 19), "aiPhoto"),
            (at(4, 7), "manual"),
            (at(5, 8), "barcode"),   // before stats started that morning
            (at(5, 10), "barcode"),  // after: counted live instead
        ], before: start)
        XCTAssertEqual(days["2026-10-03"], ["items.quickAdd": 2, "items.mealScan": 1])
        XCTAssertEqual(days["2026-10-04"], ["items.manual": 1])
        XCTAssertEqual(days["2026-10-05"], ["items.barcode": 1])
    }

    func testCountsAddUpPerDayAndUndoTakesItemsBackOut() {
        let stats = makeStats()
        let now = Date()
        stats.itemsAdded(3, method: .quickAdd, now: now)
        stats.itemsAdded(1, method: .barcode, now: now)
        stats.itemsUndone(1, method: .quickAdd, now: now)
        stats.scan(.barcode, now: now)
        let day = stats.pending.days[UsageStats.dayKey(now)]
        XCTAssertEqual(day?["items.quickAdd"], 2)
        XCTAssertEqual(day?["items.barcode"], 1)
        XCTAssertEqual(day?["undos"], 1)
        XCTAssertEqual(day?["scans.barcode"], 1)
    }

    func testARetriedBatchKeepsItsIDAndNewCountsWaitForTheNextOne() throws {
        let stats = makeStats()
        stats.count(.opens)
        let first = try XCTUnwrap(stats.nextBatch())
        XCTAssertTrue(stats.pending.isEmpty, "Counts move into the batch being sent")
        stats.count(.opens)
        // Until the server acknowledges it, the same batch (same ID) is offered again, so a retry never double counts.
        XCTAssertEqual(stats.nextBatch()?.id, first.id)
        XCTAssertEqual(stats.pending.days.values.first?["opens"], 1)
    }

    func testStateSurvivesRelaunch() throws {
        let stats = makeStats()
        stats.count(.searches)
        stats.event("rating", ["answer": "yes"])
        _ = stats.nextBatch()
        // Starting a batch saves right away; read the file back as the next launch would.
        UsageStats.waitForPendingWrites()
        let relaunched = makeStats()
        XCTAssertEqual(relaunched.currentState.sending, stats.currentState.sending)
        XCTAssertEqual(relaunched.currentState.firstLaunch.timeIntervalSince1970, stats.currentState.firstLaunch.timeIntervalSince1970, accuracy: 1)
    }

    func testTurningSharingOffDiscardsAnythingUnsentAndStopsRecording() {
        let stats = makeStats()
        stats.count(.opens)
        stats.event("rating", ["answer": "no"])
        _ = stats.nextBatch()
        stats.count(.edits)
        defaults.set(false, forKey: UsageStats.sharingKey)
        stats.sharingChanged()
        XCTAssertTrue(stats.pending.isEmpty)
        XCTAssertNil(stats.currentState.sending)
        stats.count(.opens)
        stats.error(.mealScan, code: "x", message: "y")
        XCTAssertTrue(stats.pending.isEmpty)
        XCTAssertNil(stats.nextBatch())
    }

    func testRepeatingErrorsAreReportedOnceAMinuteAndExpectedOnesNotAtAll() {
        let stats = makeStats()
        let now = Date()
        // One call site failing again and again, as it would in a loop.
        for seconds in [0.0, 30, 61] { stats.error(.search, URLError(.notConnectedToInternet), now: now.addingTimeInterval(seconds)) }
        XCTAssertEqual(stats.pending.errors.count, 2)
        XCTAssertEqual(stats.pending.errors.first?.code, "URLError.-1009")
        XCTAssertTrue(stats.pending.errors.first?.location.contains("UsageStatsTests.swift:") ?? false)
        XCTAssertNil(UsageStats.describe(CancellationError()))
        XCTAssertNil(UsageStats.describe(URLError(.cancelled)))
        XCTAssertNil(UsageStats.describe(AIServiceError(code: "subscription_required", message: "Upgrade")))
        XCTAssertEqual(UsageStats.describe(AIServiceError(code: "no_estimate", message: "No food found."))?.code, "no_estimate")
        // Only the path of a failing URL is kept; the query can hold what someone searched for.
        let failing = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://example.com/api/v1/foods/search?q=secret")!])
        XCTAssertEqual(UsageStats.describe(failing)?.detail, "path /api/v1/foods/search")
    }

    func testSearchesThatFoundNothingAreTrimmedLowercasedAndCapped() {
        let stats = makeStats()
        stats.searchFoundNothing("  Grandma's LASAGNA ")
        stats.searchFoundNothing("x")
        stats.searchFoundNothing(String(repeating: "a", count: 300))
        XCTAssertEqual(stats.pending.events.map { $0.props["query"]?.count }, [17, 100])
        XCTAssertEqual(stats.pending.events.first?.props["query"], "grandma's lasagna")
    }

    func testReportsMatchTheBackendFormat() throws {
        let stats = makeStats()
        stats.traits = { ["goal": "true", "intent": "lose", "empty": ""] }
        stats.itemsAdded(2, method: .manual)
        stats.paywallShown(.mealScanOpen)
        stats.error(.barcode, code: "camera", message: "Camera unavailable.")
        let batch = try XCTUnwrap(stats.nextBatch())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: stats.payload(for: batch)) as? [String: Any])
        XCTAssertEqual(json["batch"] as? String, batch.id.uuidString.lowercased())
        XCTAssertNotNil(UUID(uuidString: json["install"] as? String ?? ""))
        XCTAssertEqual(json["existingUser"] as? Bool, false)
        XCTAssertEqual(json["backfill"] as? Bool, false)
        XCTAssertEqual((json["startedDay"] as? String)?.count, 10)
        XCTAssertTrue((json["startedAt"] as? String)?.hasSuffix("Z") ?? false)
        let app = try XCTUnwrap(json["app"] as? [String: String])
        XCTAssertEqual(app["environment"], "debug")
        XCTAssertNotNil(app["version"]); XCTAssertNotNil(app["os"]); XCTAssertNotNil(app["device"])
        let traits = try XCTUnwrap(json["traits"] as? [String: String])
        XCTAssertEqual(traits["goal"], "true")
        XCTAssertNil(traits["empty"], "Empty traits are left out")
        XCTAssertNotNil(traits["timeZone"])
        let days = try XCTUnwrap(json["days"] as? [[String: Any]])
        XCTAssertEqual((days.first?["counts"] as? [String: Int])?["items.manual"], 2)
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.first?["name"] as? String, "paywall.shown")
        XCTAssertEqual((events.first?["props"] as? [String: String])?["trigger"], "mealScanOpen")
        let errors = try XCTUnwrap(json["errors"] as? [[String: Any]])
        XCTAssertEqual(errors.first?["area"] as? String, "barcode")
        XCTAssertEqual(Set(errors.first?.keys.map { $0 } ?? []), ["id", "area", "code", "message", "location", "detail", "at"])
    }
}
