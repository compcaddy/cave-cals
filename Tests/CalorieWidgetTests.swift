import XCTest
@testable import CaveCals

final class CalorieWidgetTests: XCTestCase {
    func testCountAndGoalWithMidnightRollover() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)))
        let snapshot = CalorieWidgetSnapshot(day: day, total: 500, goal: 2100)
        XCTAssertEqual(snapshot.label(on: day, calendar: calendar), "500/2100")
        XCTAssertEqual(snapshot.label(on: nextDay.addingTimeInterval(-1), calendar: calendar), "500/2100")
        XCTAssertEqual(snapshot.label(on: nextDay, calendar: calendar), "0/2100")
    }
    func testNoGoalAndOverGoalTotals() {
        let day = Date()
        XCTAssertEqual(CalorieWidgetSnapshot(day: day, total: 500, goal: nil).label(on: day), "500 cal")
        XCTAssertEqual(CalorieWidgetSnapshot(day: day, total: 2500, goal: 2100).label(on: day), "2500/2100")
    }
    func testSharedSnapshotChangesOnlyWhenDisplayedDataChanges() throws {
        let suite = "widget-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = Calendar.current.startOfDay(for: .now)
        let first = CalorieWidgetSnapshot(day: day, total: 500, goal: 2100)
        XCTAssertNil(CalorieWidgetStorage.read(from: defaults))
        XCTAssertTrue(CalorieWidgetStorage.write(first, to: defaults))
        XCTAssertEqual(CalorieWidgetStorage.read(from: defaults), first)
        XCTAssertFalse(CalorieWidgetStorage.write(first, to: defaults))
        let edited = CalorieWidgetSnapshot(day: day, total: 350, goal: nil)
        XCTAssertTrue(CalorieWidgetStorage.write(edited, to: defaults))
        XCTAssertEqual(CalorieWidgetStorage.read(from: defaults), edited)
    }
}
