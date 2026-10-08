import XCTest
import PDFKit
import SwiftData
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
    private func habitFoods() -> [HabitFood] {
        func food(_ day: Int, _ hour: Int, _ minute: Int, _ name: String, _ cals: Double, protein: Double, loggedLater: Bool = false) -> HabitFood {
            let time = calendar.date(byAdding: .minute, value: minute, to: date(day, hour: hour))!
            return HabitFood(timestamp: time, createdAt: loggedLater ? date(day + 1, hour: 7) : time, calories: cals, name: name,
                             macros: MacroNutrients(protein: protein, totalCarbs: cals / 10, fat: cals / 30))
        }
        var foods: [HabitFood] = []
        for day in [14, 15, 16] {  // good: 1,800 of 2,000
            foods += [food(day, 8, 0, "Greek yogurt", 300, protein: 25), food(day, 12, 0, "Lunch", 800, protein: 50),
                      food(day, 18, 0, "Dinner", 700, protein: 45, loggedLater: day == 15)]
        }
        for day in [17, 18, 21] {  // over: 2,400
            foods += [food(day, 9, 30, "Breakfast", 300, protein: 10), food(day, 13, 0, "Lunch", 900, protein: 40),
                      food(day, 19, 30, "Dinner", 800, protein: 40), food(day, 21, 30, "tortilla  Chips", 400, protein: 4)]
        }
        return foods
    }
    func testHabitsCompareGoodAndOverDays() throws {
        let drafts = [14, 15, 16].map { food($0, 1800) } + [17, 18, 21].map { food($0, 2400) }
        let data = ProgressData(drafts: drafts, records: [], now: date(28), calendar: calendar)
        let habits = HabitInsights(foods: habitFoods(), data: data, goal: { _ in 2000 }, range: .days30)
        XCTAssertEqual(habits.good.days, 3)
        XCTAssertEqual(habits.over.days, 3)
        XCTAssertTrue(habits.enoughData)
        XCTAssertEqual(habits.good.firstMinute, 8 * 60)
        XCTAssertEqual(habits.over.firstMinute, 9 * 60 + 30)
        // Sep 15's dinner was logged the next morning, so it doesn't count toward timing; the median holds.
        XCTAssertEqual(habits.good.lastMinute, 18 * 60)
        XCTAssertEqual(habits.over.lastMinute, 21 * 60 + 30)
        XCTAssertEqual(habits.over.periods[.late], 400)
        XCTAssertEqual(habits.good.periods[.late], 0)
        XCTAssertEqual(habits.good.macros[.protein], 120)
        XCTAssertEqual(habits.over.macros[.protein], 94)
        let ids = habits.findings.map(\.id)
        for id in ["start", "end", "period", "protein", "overFood", "goodFood"] { XCTAssertTrue(ids.contains(id), "\(id) in \(ids)") }
        // Breakfast and the chips only appear on over days; ties sort by name.
        XCTAssertEqual(habits.overFoods.map(\.name), ["Breakfast", "tortilla  Chips"])
        XCTAssertEqual(habits.overFoods.first?.overShare, 1)
        XCTAssertEqual(habits.goodFoods.first?.name, "Greek yogurt")
        XCTAssertEqual(habits.currentStreak, 0, "Nothing logged yesterday")
        // The coach gets the comparison as JSON, with nulls rather than missing keys.
        let payload = habits.coachPayload(calendar: calendar)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertEqual(payload["range"] as? String, "30")
        let good = try XCTUnwrap(payload["good"] as? [String: Any])
        XCTAssertNotNil(good["firstFood"] as? String)
        XCTAssertEqual((payload["foods"] as? [[String: Any]])?.count, 3)
    }
    func testHabitsNeedBothKindsOfDaysAndCountTheStreak() {
        let drafts = [14, 15, 16].map { food($0, 1800) } + [food(13, 2400)]
        let data = ProgressData(drafts: drafts, records: [], now: date(17), calendar: calendar)
        let habits = HabitInsights(foods: [], data: data, goal: { _ in 2000 }, range: .all)
        XCTAssertFalse(habits.enoughData)
        XCTAssertEqual(habits.currentStreak, 3, "Sep 14–16 are good; Sep 13 went over")
        // Days without a goal aren't compared.
        XCTAssertEqual(HabitInsights(foods: [], data: data, goal: { _ in nil }, range: .all).good.days, 0)
    }
    func testTrendsAverageCompleteDaysByWeekdayInRange() {
        // Mon Sep 14 and 21, Tue Sep 15; Tue Sep 22 is incomplete (under 60% of its usual); today (Mon 28) is in progress.
        let drafts = [food(14, 2000), food(15, 1800), food(21, 2200), food(22, 900), food(28, 500),
                      EntryDraft(name: "Old", calories: 2000, timestamp: date(2026, 8, 1))]
        let data = ProgressData(drafts: drafts, records: [], firstWeekday: 2, now: date(28, hour: 20), calendar: calendar)
        let all = ProgressTrends(foods: [], data: data, range: .all)
        XCTAssertEqual(all.weekdays.map(\.weekday), [2, 3, 4, 5, 6, 7, 1], "Follows the Progress week start")
        XCTAssertEqual(all.weekdays[0].average, 2100)
        XCTAssertEqual(all.weekdays[0].days, 2)
        XCTAssertEqual(all.weekdays[1].average, 1800, "The incomplete Tuesday is left out")
        XCTAssertEqual(all.weekdayDays, 4, "Aug 1 counts in all time")
        XCTAssertEqual(ProgressTrends(foods: [], data: data, range: .days30).weekdayDays, 3, "Aug 1 is outside 30 days")
        let sunday = ProgressData(drafts: drafts, records: [], firstWeekday: 1, now: date(28, hour: 20), calendar: calendar)
        XCTAssertEqual(ProgressTrends(foods: [], data: sunday, range: .all).weekdays.first?.weekday, 1)
    }
    func testTrendsHoursSkipFoodLoggedOnALaterDay() {
        let drafts = [food(14, 2000), food(21, 2200)]
        let data = ProgressData(drafts: drafts, records: [], now: date(28), calendar: calendar)
        let foods = [
            ProgressTrends.Food(timestamp: date(14, hour: 8), createdAt: date(14, hour: 8), calories: 500),
            ProgressTrends.Food(timestamp: date(14, hour: 12), createdAt: date(14, hour: 13), calories: 1500),
            ProgressTrends.Food(timestamp: date(21, hour: 8), createdAt: date(21, hour: 9), calories: 1000),
            // Backfilled the next morning: its time isn't when it was eaten.
            ProgressTrends.Food(timestamp: date(21, hour: 18), createdAt: date(22, hour: 7), calories: 1200),
        ]
        let trends = ProgressTrends(foods: foods, data: data, range: .all)
        XCTAssertEqual(trends.hourDays, 2)
        XCTAssertEqual(trends.hours[8].calories, 750)
        XCTAssertEqual(trends.hours[12].calories, 750)
        XCTAssertEqual(trends.hours[18].calories, 0)
        XCTAssertEqual(trends.hours[8].share, 0.5)
        XCTAssertEqual(trends.hours.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
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
    func testCompleteDaysNeedSeventyPercentOfThatDaysGoal() {
        // A 2,000 goal needs 1,400; a done day counts however low; days without a goal use the average rule.
        let goals: [Int: Double] = [14: 2000, 15: 2000, 16: 2000, 17: 3000]
        let data = ProgressData(drafts: [food(14, 1399), food(15, 1400), food(16, 900), food(17, 2000)],
                                records: [], finishedDays: [date(16)], goal: { day in goals[self.calendar.component(.day, from: day)] },
                                now: date(28), calendar: calendar)
        XCTAssertEqual(data.day(date(14)).status, .incomplete)
        XCTAssertEqual(data.day(date(15)).status, .complete)
        XCTAssertEqual(data.day(date(16)).status, .complete, "Marked done eating")
        XCTAssertEqual(data.day(date(17)).status, .incomplete, "2,000 is under 70% of 3,000")
    }
    func testOnTargetRulesAndUnderDays() {
        var rule = OnTargetRule()
        XCTAssertEqual(rule.outcome(calories: 2000, goal: 2000), .onTarget)
        XCTAssertEqual(rule.outcome(calories: 2001, goal: 2000), .over)
        XCTAssertEqual(rule.outcome(calories: 900, goal: 2000), .onTarget)
        rule.kind = .withinPercent; rule.percent = 5
        XCTAssertEqual(rule.outcome(calories: 2100, goal: 2000), .onTarget)
        XCTAssertEqual(rule.outcome(calories: 2101, goal: 2000), .over)
        XCTAssertEqual(rule.outcome(calories: 1899, goal: 2000), .under)
        XCTAssertEqual(rule.summary, "within 5% of your goal")
        rule.kind = .overBy; rule.overBy = 500
        XCTAssertEqual(rule.outcome(calories: 2500, goal: 2000), .onTarget)
        XCTAssertEqual(rule.outcome(calories: 2501, goal: 2000), .over)
        XCTAssertEqual(rule.summary, "up to 500 over your goal")
        // Within a percentage, days under the range are counted, not compared.
        // 1,700 is complete (over 70% of the 2,200 average) but under 1,900, the bottom of 5% around 2,000.
        let drafts = [14, 15, 16].map { food($0, 2000) } + [17, 18, 21].map { food($0, 2400) } + [food(22, 1700)]
        let data = ProgressData(drafts: drafts, records: [], now: date(28), calendar: calendar)
        var within = OnTargetRule(); within.kind = .withinPercent
        let habits = HabitInsights(foods: [], data: data, goal: { _ in 2000 }, range: .all, rule: within)
        XCTAssertEqual(habits.good.days, 3)
        XCTAssertEqual(habits.over.days, 3)
        XCTAssertEqual(habits.underDays, 1)
        XCTAssertEqual(habits.coachPayload(calendar: calendar)["definition"] as? String, "on target means within 5% of the daily calorie goal")
    }
    func testProgressSettingsDecodeSafelyAndKeepTheOldWeekStart() throws {
        XCTAssertEqual(ProgressSettings.decode(nil, localWeekday: 1).firstWeekday, 1, "This iPhone's old local week start")
        XCTAssertEqual(ProgressSettings.decode(nil, localWeekday: 9).firstWeekday, 2)
        var settings = ProgressSettings()
        settings.firstWeekday = 7; settings.onTarget.kind = .overBy; settings.onTarget.overBy = 250; settings.habitsRange = .all
        let decoded = ProgressSettings.decode(settings.encoded, localWeekday: 2)
        XCTAssertEqual(decoded, settings)
        // Newer or damaged values fall back field by field.
        let odd = Data(#"{"firstWeekday":12,"onTarget":{"kind":"someday","percent":90},"trendsRange":"weekly"}"#.utf8)
        let fallback = ProgressSettings.decode(odd, localWeekday: 3)
        XCTAssertEqual(fallback.firstWeekday, 2)
        XCTAssertEqual(fallback.onTarget.kind, .atOrUnder)
        XCTAssertEqual(fallback.onTarget.percent, 50)
        XCTAssertEqual(fallback.trendsRange, .days30)
    }
    func testProgressSettingsSaveOnTheSyncedProfile() throws {
        let container = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(container: container, publishesWidget: false, persistsUsage: false, persistsFoodDefaults: false)
        XCTAssertTrue(store.saveGoal(2000))
        var settings = store.progressSettings
        settings.firstWeekday = 1; settings.onTarget.kind = .withinPercent; settings.onTarget.percent = 8
        XCTAssertTrue(store.saveProgressSettings(settings))
        XCTAssertNotNil(store.profile?.progressSettingsData)
        let reopened = AppStore(container: container, publishesWidget: false, persistsUsage: false, persistsFoodDefaults: false)
        XCTAssertEqual(reopened.progressSettings.firstWeekday, 1)
        XCTAssertEqual(reopened.progressSettings.onTarget.percent, 8)
    }
    func testIncompleteThresholdBoundaryAndIndependentWeighIns() {
        // Without a goal: 70% of the prior complete days' average (2,000) is 1,400.
        let data = ProgressData(drafts: [food(18, 2000), food(19, 2000), food(21, 1399), food(22, 1400), food(24, 2100)],
            records: [WeightRecord(date: date(21), kilograms: 80), WeightRecord(date: date(23), kilograms: 79)], now: date(28), calendar: calendar)
        XCTAssertEqual(data.day(date(21)).status, .incomplete)
        XCTAssertEqual(data.day(date(22)).status, .complete)
        XCTAssertEqual(data.day(date(22)).referenceAverage, 2000)
        XCTAssertEqual(data.day(date(23)).status, .missing)
        let week = data.week(containing: date(24))
        XCTAssertEqual(week.calories.count, 2)
        XCTAssertEqual(week.calories.average!, 1750, accuracy: 0.001)
        XCTAssertEqual(week.calories.min, 1400)
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
        let currentReport = ProgressPrintDocument(weeks: sunday.fiveWeeks(endingAt: sunday.currentWeekStart),
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
        let report = ProgressPrintDocument(weeks: monday.fiveWeeks(endingAt: date(27)), dates: monday.dates, unit: .pounds)
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
    func testFiveWeekReportIncludesSelectedWeekAndPreservesMissingStats() {
        let data = ProgressData(drafts: [], records: [], now: date(28), calendar: calendar)
        let weeks = data.fiveWeeks(endingAt: date(28))
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.last!.interval.start, date(28, hour: 0))
        XCTAssertEqual(weeks.last!.interval.end, date(2026, 10, 5, hour: 0))
        XCTAssertEqual(data.fiveWeeks(endingAt: date(2026, 10, 12)).last!.interval.start, data.currentWeekStart)
        XCTAssertEqual(data.fiveWeeks(endingAt: date(21)).last!.interval.end, date(28, hour: 0))
        XCTAssertNil(weeks.last!.calories.average)
        XCTAssertNil(weeks.last!.weight.change(from: weeks[3].weight))
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
        let pdf = ProgressPrintDocument(weeks: data.fiveWeeks(endingAt: date(28)), dates: data.dates, unit: .kilograms).pdf()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("No comparison yet") == true)
        XCTAssertTrue(document.string?.contains("0/7 completed calorie days") == true)
    }
    func testOnePagePDFIncludesLatestWeekComparisonAndFiveWeekStatistics() throws {
        let today = date(28)
        var drafts: [EntryDraft] = [], records: [WeightRecord] = []
        for day in 1...27 {
            drafts.append(food(day, day > 20 ? 1800 : 2000))
            records.append(WeightRecord(date: date(day), kilograms: day > 20 ? 79 : 80))
        }
        let data = ProgressData(drafts: drafts, records: records, now: today, calendar: calendar)
        let report = ProgressPrintDocument(weeks: data.fiveWeeks(endingAt: data.dates.lastCompletedWeek(now: today)), dates: data.dates, unit: .pounds, dailyGoal: 2100)
        let pdf = report.pdf()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Weekly Recap"))
        XCTAssertTrue(text.contains("Five-Week Trends"))
        XCTAssertFalse(text.contains("MOST RECENT COMPLETED WEEK"))
        XCTAssertFalse(text.contains("Missing days are excluded"))
        XCTAssertTrue(text.contains("Monday, September 21st"))
        XCTAssertTrue(text.contains("Sunday, September 27th"))
        XCTAssertTrue(text.contains("1,800"))
        XCTAssertTrue(text.contains("300 cals below goal (2,100)"))
        XCTAssertFalse(text.contains("Daily goal:"))
        XCTAssertFalse(text.contains("Compared with"))
        XCTAssertFalse(text.contains("Six-Week Trends"))
        XCTAssertFalse(text.contains("200 cals vs prior week"))
        XCTAssertTrue(text.contains("-200"))
        XCTAssertTrue(text.contains("Calorie min–max"))
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("progress-test-preview.pdf")
        try pdf.write(to: path)
    }
}
