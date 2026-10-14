import XCTest
@testable import CaveCals

@MainActor final class ClanTests: XCTestCase {
    func testDailyReportCountsFullDaysByTheProgressRule() {
        // 70% of a 2,000 goal is 1,400.
        let full = ClanDayReport.make(day: "2026-10-13", total: 1400, entries: 3, goal: 2000, reference: nil, doneEating: false, minimumGoal: 1200)
        XCTAssertEqual(full, ClanDayReport(day: "2026-10-13", logged: true, fullDay: true, percentOfGoal: 70, goalOk: true, doneEating: false))
        let partial = ClanDayReport.make(day: "2026-10-13", total: 600, entries: 1, goal: 2000, reference: nil, doneEating: false, minimumGoal: 1200)
        XCTAssertFalse(partial.fullDay)
        XCTAssertTrue(partial.logged)
        XCTAssertEqual(partial.percentOfGoal, 30)
        // Done eating makes even a light day full.
        XCTAssertTrue(ClanDayReport.make(day: "d", total: 600, entries: 1, goal: 2000, reference: nil, doneEating: true, minimumGoal: 1200).fullDay)
        // Nothing logged is never full, even when marked done.
        XCTAssertFalse(ClanDayReport.make(day: "d", total: 0, entries: 0, goal: 2000, reference: nil, doneEating: true, minimumGoal: 1200).fullDay)
    }

    func testDaysWithoutAGoalUseTheUsualDay() {
        let report = ClanDayReport.make(day: "d", total: 1300, entries: 2, goal: nil, reference: 2000, doneEating: false, minimumGoal: 1200)
        XCTAssertFalse(report.fullDay)
        XCTAssertNil(report.percentOfGoal)
        XCTAssertFalse(report.goalOk)
        XCTAssertTrue(ClanDayReport.make(day: "d", total: 1500, entries: 2, goal: nil, reference: 2000, doneEating: false, minimumGoal: 1200).fullDay)
        // With nothing to compare against yet, a logged day counts.
        XCTAssertTrue(ClanDayReport.make(day: "d", total: 300, entries: 1, goal: nil, reference: nil, doneEating: false, minimumGoal: 1200).fullDay)
    }

    func testGoalsBelowTheHealthyMinimumCantBeOnTarget() {
        XCTAssertFalse(ClanDayReport.make(day: "d", total: 1000, entries: 2, goal: 1100, reference: nil, doneEating: false, minimumGoal: 1200).goalOk)
        XCTAssertFalse(ClanDayReport.make(day: "d", total: 1400, entries: 2, goal: 1400, reference: nil, doneEating: false, minimumGoal: 1500).goalOk)
        XCTAssertTrue(ClanDayReport.make(day: "d", total: 1400, entries: 2, goal: 1500, reference: nil, doneEating: false, minimumGoal: 1500).goalOk)
    }

    func testTheReportSendsNoCaloriesOrGoal() {
        let json = ClanDayReport.make(day: "2026-10-13", total: 1850, entries: 4, goal: 2000, reference: nil, doneEating: false, minimumGoal: 1200).json
        XCTAssertEqual(Set(json.keys), ["day", "logged", "fullDay", "percentOfGoal", "goalOk", "doneEating"])
        XCTAssertEqual(json["percentOfGoal"] as? Int, 93)
        XCTAssertTrue(ClanDayReport.make(day: "d", total: 0, entries: 0, goal: nil, reference: nil, doneEating: false, minimumGoal: 1200).json["percentOfGoal"] is NSNull)
    }

    func testWeightChangeUsesThreeDayAveragesAndOnlyPercentages() {
        let weights = ["2026-10-01": 100.0, "2026-10-02": 99.0, "2026-10-03": 98.0, "2026-10-10": 97.0, "2026-10-12": 96.5, "2026-10-14": 96.0]
        // Start: average of days 1–3 = 99. Mid-challenge: latest (Oct 10) = 97 → −2.02%.
        let mid = ClanWeightReport.make(weights: weights, startsOn: "2026-10-01", endsOn: "2026-10-14", today: "2026-10-10")
        XCTAssertTrue(mid.startReady)
        XCTAssertEqual(mid.changePct, -2.02)
        XCTAssertNil(mid.finalPct)
        XCTAssertFalse(mid.endReady)
        // Final: average of the last 3 days (Oct 12–14) = 96.25 → −2.78%.
        let end = ClanWeightReport.make(weights: weights, startsOn: "2026-10-01", endsOn: "2026-10-14", today: "2026-10-14")
        XCTAssertEqual(end.finalPct, -2.78)
        XCTAssertTrue(end.endReady)
        // No weigh-in in the first three days: nothing to compare.
        let late = ClanWeightReport.make(weights: ["2026-10-05": 90], startsOn: "2026-10-01", endsOn: "2026-10-14", today: "2026-10-10")
        XCTAssertFalse(late.startReady)
        XCTAssertNil(late.changePct)
    }

    func testInviteLinksAreRecognized() {
        XCTAssertEqual(ClanLinks.code(from: URL(string: "https://cavecals.com/join/X7K2QM")!), "X7K2QM")
        XCTAssertEqual(ClanLinks.code(from: URL(string: "https://www.cavecals.com/join/x7k2qm")!), "X7K2QM")
        XCTAssertEqual(ClanLinks.code(from: URL(string: "\(AppEnvironment.urlScheme)://join/X7K2QM")!), "X7K2QM")
        XCTAssertNil(ClanLinks.code(from: URL(string: "https://cavecals.com/Sarah")!))
        XCTAssertNil(ClanLinks.code(from: URL(string: "https://evil.example.com/join/X7K2QM")!))
        XCTAssertNil(ClanLinks.code(from: URL(string: "https://cavecals.com/join/TOOLONG1")!))
        XCTAssertNil(ClanLinks.code(from: URL(string: "\(AppEnvironment.urlScheme)://log/add")!))
        XCTAssertEqual(ClanLinks.normalize(" x7k-2qm "), "X7K2QM")
    }

    func testHomeStripLines() throws {
        func summary(_ json: String) throws -> ClanChallengeSummary { try JSONDecoder().decode(ClanChallengeSummary.self, from: Data(json.utf8)) }
        let base = #""id":"c","name":"x","status":"active","joined":true,"canJoin":false,"startsOn":"2026-10-01","myStatus":"in","madeToday":false,"inToday":4,"inCount":6"#
        XCTAssertEqual(ClanStatusText.line(try summary(#"{"kind":"streak","dayNumber":19,"streak":{"length":18,"record":23},\#(base)}"#)), "Fire lit 18 days · 4 of 6 in today")
        XCTAssertEqual(ClanStatusText.line(try summary(#"{"kind":"loggingDays","dayNumber":6,"totalDays":14,"myRank":2,\#(base)}"#)), "Day 6 of 14 · You’re 2nd")
        XCTAssertEqual(ClanStatusText.line(try summary(#"{"kind":"survivor","dayNumber":6,"myLivesLeft":2,\#(base)}"#)), "6 left · You have 2 lives")
        XCTAssertEqual(ClanStatusText.line(try summary(#"{"kind":"teamTotal","dayNumber":6,"totalDays":30,"team":{"total":62,"target":100,"reached":false},\#(base)}"#)), "62 of 100 days")
        XCTAssertEqual(ClanStatusText.line(try summary(#"{"kind":"weightLoss","dayNumber":17,"totalDays":28,"myRank":1,"myLossPct":2.4,\#(base)}"#)), "Week 3 · You’re 1st (−2.4%)")
    }

    func testAboutYouAgeAdvancesFromThePlanAndHeightFollowsTheUnit() {
        let input = CaloriePlanInput(gender: .male, age: 30, heightCM: 180.3, weightKG: 90, goalKG: 85, activity: .light, intent: .lose, weeklyLossKG: 0.4)
        let made = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        let plan = SavedCaloriePlan(input: input, calorieGoal: 2100, createdAt: made)
        XCTAssertEqual(plan.currentAge(now: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 28))!), 31)
        XCTAssertEqual(plan.currentAge(now: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!), 32)
        XCTAssertEqual(PlanDetailsSection.height(180.3, unit: .pounds), "5′ 11″")
        XCTAssertEqual(PlanDetailsSection.height(180.3, unit: .kilograms), "180 cm")
        XCTAssertEqual(PlanDetailsSection.height(152.4, unit: .pounds), "5′ 0″")
    }
}
