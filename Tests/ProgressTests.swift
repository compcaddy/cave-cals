import XCTest
import PDFKit
@testable import CaveCals

@MainActor final class ProgressTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func date(_ day: Int, hour: Int = 12) -> Date { date(2026, 9, day, hour: hour) }
    private func food(_ day: Int, _ cals: Double, macros: MacroNutrients? = nil) -> EntryDraft {
        var draft = EntryDraft(name: "Test food", calories: cals, timestamp: date(day)); draft.macrosPerServing = macros; return draft
    }
    func testCalendarPeriodsAndCustomWeekStart() {
        let monday = ProgressCalendar(firstWeekday: 2, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: monday.interval(.week, containing: date(23)).start), 21)
        let sunday = ProgressCalendar(firstWeekday: 1, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: sunday.interval(.week, containing: date(23)).start), 20)
        XCTAssertEqual(monday.days(in: monday.interval(.month, containing: date(2024, 2, 10))).count, 29)
        XCTAssertEqual(monday.days(in: monday.interval(.month, containing: date(2026, 1, 10))).count, 31)
        let dst = monday.interval(.week, containing: date(2026, 3, 8))
        XCTAssertEqual(monday.days(in: dst).count, 7)
        XCTAssertEqual(dst.duration, 7 * 86400 - 3600)
        XCTAssertEqual(monday.lastCompletedWeek(now: date(2026, 1, 1)), date(2025, 12, 22, hour: 0))
    }
    func testIncompleteThresholdBoundaryAndIndependentWeighIns() {
        let data = ProgressData(drafts: [food(18, 2000), food(19, 2000), food(21, 1199), food(22, 1200), food(24, 2100)],
            records: [WeightRecord(date: date(21), kilograms: 80), WeightRecord(date: date(23), kilograms: 79)], now: date(28), calendar: calendar)
        XCTAssertEqual(data.day(date(21)).status, .incomplete)
        XCTAssertEqual(data.day(date(22)).status, .complete)
        XCTAssertEqual(data.day(date(22)).referenceAverage, 2000)
        XCTAssertEqual(data.day(date(23)).status, .missing)
        let week = data.week(containing: date(24))
        XCTAssertEqual(week.calories.count, 2)
        XCTAssertEqual(week.calories.average!, 1650, accuracy: 0.001)
        XCTAssertEqual(week.calories.min, 1200)
        XCTAssertEqual(week.calories.max, 2100)
        XCTAssertEqual(week.weight.count, 2)
        XCTAssertEqual(week.weight.average, 79.5)
    }
    func testFirstWeekOfWeighInsShowsAverageAndRangeWithoutPreviousWeek() throws {
        let pounds = [194.8, 193.8, 193.4, 192.0, 192.6, 193.0, 193.8]
        let records = pounds.enumerated().map { index, value in
            WeightRecord(date: date(21 + index), kilograms: WeightUnit.pounds.kilograms(value))
        }
        let sunday = ProgressData(drafts: [], records: records, now: date(27), calendar: calendar)
        let current = sunday.week(containing: date(27))
        let previous = sunday.week(containing: date(20))
        XCTAssertEqual(current.weight.count, 7)
        XCTAssertEqual(WeightUnit.pounds.display(try XCTUnwrap(current.weight.average)), 193.342857, accuracy: 0.00001)
        XCTAssertEqual(WeightUnit.pounds.display(try XCTUnwrap(current.weight.min)), 192.0, accuracy: 0.00001)
        XCTAssertEqual(WeightUnit.pounds.display(try XCTUnwrap(current.weight.max)), 194.8, accuracy: 0.00001)
        XCTAssertNil(previous.weight.average)
        XCTAssertEqual(ProgressFormat.change(current.weight.change(from: previous.weight), unit: .pounds), "No comparison yet")
        XCTAssertEqual(sunday.currentWeekStart, date(21, hour: 0))
        let currentReport = ProgressPrintDocument(weeks: sunday.sixWeeks(endingAt: sunday.currentWeekStart),
            dates: sunday.dates, unit: .pounds, isInProgress: true)
        let currentPDF = try XCTUnwrap(PDFDocument(data: currentReport.pdf()))
        XCTAssertEqual(currentPDF.pageCount, 1)
        let currentText = try XCTUnwrap(currentPDF.string)
        XCTAssertTrue(currentText.contains("Monday, September 21st"))
        XCTAssertTrue(currentText.contains("193.3 lb"))
        XCTAssertTrue(currentText.contains("Min 192.0"))
        XCTAssertTrue(currentText.contains("Max 194.8"))
        XCTAssertTrue(currentText.contains("No comparison yet"))
        XCTAssertTrue(currentText.contains("In progress"))
        let previewURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("current-week-test-preview.pdf")
        try currentReport.pdf().write(to: previewURL)
        let monday = ProgressData(drafts: [], records: records, now: date(28), calendar: calendar)
        let report = ProgressPrintDocument(weeks: monday.sixWeeks(endingAt: date(27)), dates: monday.dates, unit: .pounds)
        let pdf = try XCTUnwrap(PDFDocument(data: report.pdf()))
        XCTAssertEqual(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("193.3 lb"))
        XCTAssertTrue(text.contains("Min 192.0"))
        XCTAssertTrue(text.contains("Max 194.8"))
        XCTAssertTrue(text.contains("No comparison yet"))
    }
    func testLowLogsAreRemovedFromReferenceAndNoFutureLeakage() {
        let data = ProgressData(drafts: [food(18, 2000), food(19, 2000), food(20, 200), food(21, 1000), food(28, 9000)],
            records: [], now: date(28), calendar: calendar)
        XCTAssertEqual(data.referenceAverage(before: calendar.startOfDay(for: date(21)))!, 2000, accuracy: 0.001)
        XCTAssertEqual(data.day(date(21)).status, .incomplete)
        XCTAssertEqual(data.day(date(28)).status, .inProgress)
        XCTAssertEqual(data.day(date(29)).status, .future)
        XCTAssertEqual(data.day(date(18)).status, .complete) // Bootstrap: no earlier baseline.
    }
    func testReferenceExpiresAfter28Days() {
        let data = ProgressData(drafts: [food(1, 2500), food(30, 500)], records: [], now: date(2026, 10, 2), calendar: calendar)
        XCTAssertNil(data.day(date(30)).referenceAverage)
        XCTAssertEqual(data.day(date(30)).status, .complete)
    }
    func testMacroSplitKeepsLoggedTotalAndUnknownRemainder() {
        let known = ProgressEnergy(food(18, 500, macros: MacroNutrients(protein: 25, totalCarbs: 50, fat: 10)))
        XCTAssertEqual(known.protein, 100); XCTAssertEqual(known.carbs, 200); XCTAssertEqual(known.fat, 90)
        XCTAssertEqual(known.unknown, 110); XCTAssertEqual(known.total, 500)
        let inconsistent = ProgressEnergy(food(18, 100, macros: MacroNutrients(protein: 100, fat: 100)))
        XCTAssertEqual(inconsistent.total, 100, accuracy: 0.0001)
        XCTAssertEqual(inconsistent.unknown, 0, accuracy: 0.0001)
        let unknown = ProgressEnergy(food(18, 300))
        XCTAssertEqual(unknown.unknown, 300)
    }
    func testDoneDaysCountAsCompleteEvenWhenLowIncludingToday() {
        let drafts = [food(18, 2000), food(19, 2000), food(21, 400), food(22, 400), food(28, 900)]
        let data = ProgressData(drafts: drafts, records: [],
                                finishedDays: [date(21, hour: 21), date(23, hour: 21), date(28, hour: 20)],
                                now: date(28, hour: 22), calendar: calendar)
        XCTAssertEqual(data.day(date(21)).status, .complete)
        // The low done day becomes part of later references; an unmarked low day still uses the 60% rule.
        XCTAssertEqual(data.day(date(22)).referenceAverage!, 4400 / 3, accuracy: 0.001)
        XCTAssertEqual(data.day(date(22)).status, .incomplete)
        XCTAssertEqual(data.day(date(23)).status, .missing)
        XCTAssertEqual(data.day(date(28)).status, .complete)
        XCTAssertEqual(data.week(containing: date(28)).calories.average, 900)
        let unmarked = ProgressData(drafts: drafts, records: [], now: date(28, hour: 22), calendar: calendar)
        XCTAssertEqual(unmarked.day(date(21)).status, .incomplete)
        XCTAssertEqual(unmarked.day(date(28)).status, .inProgress)
        XCTAssertNil(unmarked.week(containing: date(28)).calories.average)
    }
    func testYearAveragesOnlyCompleteDaysAndClipsBoundaryWeeks() {
        let data = ProgressData(drafts: [food(18, 2000), food(19, 2000), food(21, 400), food(22, 2200)],
                                records: [], now: date(28), calendar: calendar)
        let buckets = data.buckets(.year, containing: date(28))
        XCTAssertEqual(buckets.first!.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(buckets.last!.end, date(2027, 1, 1, hour: 0))
        for pair in zip(buckets, buckets.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start) }
        let bucket = buckets.first { $0.start <= date(22) && $0.end > date(22) }!
        XCTAssertEqual(bucket.calories, 2200); XCTAssertEqual(bucket.includedDays, 1)
        XCTAssertNil(bucket.protein)
    }
    func testSixWeekReportIncludesSelectedWeekAndPreservesMissingStats() {
        let data = ProgressData(drafts: [], records: [], now: date(28), calendar: calendar)
        let weeks = data.sixWeeks(endingAt: date(28))
        XCTAssertEqual(weeks.count, 6)
        XCTAssertEqual(weeks.last!.interval.start, date(28, hour: 0))
        XCTAssertEqual(weeks.last!.interval.end, date(2026, 10, 5, hour: 0))
        XCTAssertEqual(data.sixWeeks(endingAt: date(2026, 10, 12)).last!.interval.start, data.currentWeekStart)
        XCTAssertEqual(data.sixWeeks(endingAt: date(21)).last!.interval.end, date(28, hour: 0))
        XCTAssertNil(weeks.last!.calories.average)
        XCTAssertNil(weeks.last!.weight.change(from: weeks[4].weight))
        XCTAssertEqual(ProgressFormat.change(-0.45359237, unit: .pounds), "↓ 1.0 lb vs prior week")
    }
    func testIndividualMacroAverageUsesKnownDaysAndReportsCoverage() {
        let data = ProgressData(drafts: [food(18, 2000), food(21, 400, macros: MacroNutrients(protein: 20)),
            food(22, 2000), food(23, 1800, macros: MacroNutrients(protein: 125))], records: [], now: date(28), calendar: calendar)
        let week = data.buckets(.year, containing: date(28)).first { $0.start <= date(23) && $0.end > date(23) }!
        XCTAssertEqual(week.protein, 125)
        XCTAssertEqual(week.includedDays, 2)
        XCTAssertEqual(week.macroDayCounts[.protein], 1)
        XCTAssertEqual(week.calories, 1900)
    }
    func testGoalAndPriorWeekComparisonFormatting() {
        XCTAssertEqual(ProgressFormat.goalChange(average: 2200, goal: 2100), "↑ 100 cals above goal")
        XCTAssertEqual(ProgressFormat.goalChange(average: 2100, goal: 2100), "On goal")
        XCTAssertEqual(ProgressFormat.goalChange(average: 2000, goal: nil), "No daily goal set")
        XCTAssertEqual(ProgressFormat.goalChange(average: nil, goal: 2100), "No completed calorie days")
        XCTAssertEqual(ProgressFormat.signedChange(-100, unit: nil), "-100")
        XCTAssertEqual(ProgressFormat.signedChange(WeightUnit.pounds.kilograms(0.7), unit: .pounds), "+0.7")
        XCTAssertEqual(ProgressFormat.signedChange(-0.01, unit: .kilograms), "0.0")
    }
    func testEmptyReportIsStillOnePageWithoutInventedAverages() throws {
        let data = ProgressData(drafts: [], records: [], now: date(28), calendar: calendar)
        let pdf = ProgressPrintDocument(weeks: data.sixWeeks(endingAt: date(28)), dates: data.dates, unit: .kilograms).pdf()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("No comparison yet") == true)
        XCTAssertTrue(document.string?.contains("0/7 completed calorie days") == true)
    }
    func testOnePagePDFIncludesLatestWeekComparisonAndSixWeekStatistics() throws {
        let today = date(28)
        var drafts: [EntryDraft] = [], records: [WeightRecord] = []
        for day in 1...27 {
            drafts.append(food(day, day > 20 ? 1800 : 2000))
            records.append(WeightRecord(date: date(day), kilograms: day > 20 ? 79 : 80))
        }
        let data = ProgressData(drafts: drafts, records: records, now: today, calendar: calendar)
        let report = ProgressPrintDocument(weeks: data.sixWeeks(endingAt: data.dates.lastCompletedWeek(now: today)), dates: data.dates, unit: .pounds, dailyGoal: 2100)
        let pdf = report.pdf()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Weekly Recap"))
        XCTAssertTrue(text.contains("Six-Week Trends"))
        XCTAssertFalse(text.contains("MOST RECENT COMPLETED WEEK"))
        XCTAssertFalse(text.contains("Missing days are excluded"))
        XCTAssertTrue(text.contains("Monday, September 21st"))
        XCTAssertTrue(text.contains("Sunday, September 27th"))
        XCTAssertTrue(text.contains("1,800"))
        XCTAssertTrue(text.contains("300 cals below goal"))
        XCTAssertFalse(text.contains("200 cals vs prior week"))
        XCTAssertTrue(text.contains("-200"))
        XCTAssertTrue(text.contains("Calorie min–max"))
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("progress-test-preview.pdf")
        try pdf.write(to: path)
    }
}
