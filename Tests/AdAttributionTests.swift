import XCTest
@testable import CaveCals

@MainActor final class AdAttributionTests: XCTestCase {
    private var calendar: Calendar!
    private var installed: Date!
    private var defaults: UserDefaults!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        installed = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20))!
        defaults = UserDefaults(suiteName: "AdAttributionTests-\(UUID().uuidString)")
    }

    private func hours(_ h: Double) -> Date { installed.addingTimeInterval(h * 3_600) }
    private func log(_ h: Double, _ source: String = "manual") -> AdConversion.Log { AdConversion.Log(createdAt: hours(h), source: source) }
    private func value(at h: Double, setup: Bool = true, logs: [AdConversion.Log] = [], membership: AdConversion.Membership? = nil) -> AdConversion? {
        AdConversion.make(installedAt: installed, now: hours(h), finishedSetup: setup, logs: logs, membership: membership, calendar: calendar)
    }

    func testWindowsFollowApplesTwoSevenAndThirtyFiveDays() {
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(0)), .first)
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(47.9)), .first)
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(48)), .second)
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(7 * 24 - 1)), .second)
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(7 * 24)), .third)
        XCTAssertEqual(AdConversion.window(installedAt: installed, now: hours(35 * 24 - 1)), .third)
        XCTAssertNil(AdConversion.window(installedAt: installed, now: hours(35 * 24)))
        XCTAssertNil(value(at: 35 * 24))
    }

    func testFirstLaunchReportsZeroSoTheWindowStarts() {
        XCTAssertEqual(value(at: 0, setup: false), AdConversion(window: .first, fine: 0, coarse: .low))
        XCTAssertEqual(value(at: 0.1), AdConversion(window: .first, fine: 1, coarse: .low))
    }

    func testFineValueAddsUpTheMilestones() {
        // Evening install, food that night and the next morning (two calendar days), one from a Meal Scan.
        let logs = [log(1), log(13, "aiPhoto")]
        XCTAssertEqual(value(at: 14, logs: logs), AdConversion(window: .first, fine: 1 + 2 + 4 + 8, coarse: .medium))
        XCTAssertEqual(value(at: 14, logs: [log(1), log(2, "aiVoice")])?.fine, 1 + 2 + 8)
        XCTAssertEqual(value(at: 14, logs: logs, membership: .init(yearly: false)), AdConversion(window: .first, fine: 31, coarse: .high))
        XCTAssertEqual(value(at: 14, logs: logs, membership: .init(yearly: true))?.fine, 63)
        XCTAssertEqual(value(at: 14, setup: false, logs: [], membership: .init(yearly: nil))?.fine, 16)
    }

    func testOnlyFoodEnteredSinceInstallCounts() {
        // iCloud history from an earlier install, and a backfill entered now for last week.
        let history = AdConversion.Log(createdAt: installed.addingTimeInterval(-5 * 86_400), source: "manual")
        XCTAssertEqual(value(at: 1, logs: [history]), AdConversion(window: .first, fine: 1, coarse: .low))
        XCTAssertEqual(value(at: 1, logs: [history, log(0.5)])?.fine, 1 + 2)
    }

    func testLaterWindowsAreMediumOnlyWhenStillLoggingOnTwoDaysInThatWindow() {
        let firstDays = [log(1), log(13)]
        XCTAssertEqual(value(at: 60, logs: firstDays), AdConversion(window: .second, fine: 7, coarse: .low))
        XCTAssertEqual(value(at: 60, logs: firstDays + [log(50)])?.coarse, .low)
        XCTAssertEqual(value(at: 80, logs: firstDays + [log(50), log(75)])?.coarse, .medium)
        // Days 8–35 start fresh.
        XCTAssertEqual(value(at: 200, logs: firstDays + [log(50), log(75)])?.coarse, .low)
        XCTAssertEqual(value(at: 400, logs: firstDays + [log(190), log(390)]), AdConversion(window: .third, fine: 7, coarse: .medium))
        XCTAssertEqual(value(at: 400, logs: [], membership: .init(yearly: nil))?.coarse, .high)
    }

    func testSendsOnlyChangesAndRemembersJoiningForThisInstall() async {
        var sent: [AdConversion] = []
        let attribution = AdAttribution(defaults: defaults, allowed: true) { sent.append($0) }
        attribution.entriesChanged([], finishedSetup: false, now: hours(0))
        await attribution.sending?.value
        attribution.entriesChanged([], finishedSetup: false, now: hours(0.5))
        await attribution.sending?.value
        XCTAssertEqual(sent, [AdConversion(window: .first, fine: 0, coarse: .low)])

        attribution.joinedPlus(yearly: nil, now: hours(1))
        await attribution.sending?.value
        attribution.joinedPlus(yearly: true, now: hours(1))
        await attribution.sending?.value
        attribution.joinedPlus(yearly: false, now: hours(1))
        await attribution.sending?.value
        XCTAssertEqual(attribution.membership, .init(yearly: true))
        XCTAssertEqual(sent.map(\.fine), [0, 16, 48])
        XCTAssertEqual(sent.last?.coarse, .high)
    }

    func testTurningOffUsageStatsStopsMeasuring() async {
        var sent: [AdConversion] = []
        defaults.set(false, forKey: UsageStats.sharingKey)
        let attribution = AdAttribution(defaults: defaults, allowed: true) { sent.append($0) }
        XCTAssertFalse(attribution.isMeasuring)
        attribution.entriesChanged([], finishedSetup: true, now: hours(0))
        attribution.joinedPlus(yearly: true, now: hours(0))
        await attribution.sending?.value
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(AdAttribution(defaults: UserDefaults(suiteName: "AdAttributionTests-\(UUID().uuidString)")!, allowed: false).isMeasuring)
    }
}
