import XCTest
@testable import CaveCals

@MainActor final class CaloriePlanTests: XCTestCase {
    private func input(gender: PlanGender = .male, age: Int = 35, height: Double = 180, weight: Double = 90, goal: Double = 80, activity: PlanActivity = .light, intent: PlanIntent = .lose, pace: Double = 0.5) -> CaloriePlanInput {
        CaloriePlanInput(gender: gender, age: age, heightCM: height, weightKG: weight, goalKG: goal, activity: activity, intent: intent, weeklyLossKG: pace)
    }
    func testReferenceEquationAndRounding() throws {
        let result = try XCTUnwrap(CaloriePlanner.estimate(input()))
        XCTAssertEqual(result.maintenance, 2550.625, accuracy: 0.001)
        XCTAssertEqual(result.calories, 2050)
        XCTAssertEqual(result.weeklyLossKG, 500.625 * 7 / 7700, accuracy: 0.001)
        XCTAssertFalse(result.paceLimited)
        let female = try XCTUnwrap(CaloriePlanner.estimate(input(gender: .female)))
        XCTAssertEqual(female.maintenance, 2322.375, accuracy: 0.001)
        XCTAssertEqual(female.calories, 1800)
    }
    func testFloorsAndDeficitCapsAcrossSupportedInputs() throws {
        for gender in [PlanGender.female, .male] {
            for age in [18, 40, 65, 80] {
                for weight in [50.0, 75, 110, 180] {
                    for activity in PlanActivity.allCases {
                        let value = input(gender: gender, age: age, height: 160, weight: weight, goal: weight - 2, activity: activity, pace: 0.75)
                        guard let result = CaloriePlanner.estimate(value) else { continue }
                        XCTAssertGreaterThanOrEqual(result.calories, gender.minimumCalories)
                        XCTAssertLessThanOrEqual(result.maintenance - result.calories, 750.001)
                        XCTAssertLessThanOrEqual(result.maintenance - result.calories, result.maintenance * 0.25 + 0.001)
                        XCTAssertGreaterThanOrEqual(result.weeklyLossKG, 0)
                        XCTAssertLessThanOrEqual(result.weeklyLossKG, value.weeklyLossKG)
                    }
                }
            }
        }
    }
    func testManualOnlyCasesNeverReturnAnEstimate() {
        for age in [12, 17, 81, 120] { XCTAssertNil(CaloriePlanner.estimate(input(age: age))) }
        for gender in [PlanGender.another, .undisclosed] { XCTAssertNil(CaloriePlanner.estimate(input(gender: gender))) }
        XCTAssertNil(CaloriePlanner.estimate(input(), clinicianSupport: true))
        XCTAssertNil(CaloriePlanner.estimate(input(weight: 45, goal: 40)))
        XCTAssertNil(CaloriePlanner.estimate(input(goal: 45)))
        XCTAssertNil(CaloriePlanner.estimate(input(goal: 95)))
        XCTAssertNil(CaloriePlanner.estimate(input(weight: .nan)))
        XCTAssertNil(CaloriePlanner.estimate(input(height: .infinity)))
        XCTAssertNil(CaloriePlanner.estimate(input(pace: -1)))
        XCTAssertNil(CaloriePlanner.estimate(input(pace: 2)))
    }
    func testMaintenanceDoesNotApplyDeficit() throws {
        let result = try XCTUnwrap(CaloriePlanner.estimate(input(goal: 90, intent: .maintain)))
        XCTAssertEqual(result.calories, 2600)
        XCTAssertEqual(result.weeklyLossKG, 0)
        XCTAssertFalse(result.paceLimited)
    }
    func testRequestedFastPaceIsReducedForSmallerPerson() throws {
        let result = try XCTUnwrap(CaloriePlanner.estimate(input(gender: .female, age: 40, height: 160, weight: 60, goal: 55, activity: .low, pace: 0.75)))
        XCTAssertEqual(result.calories, 1200)
        XCTAssertTrue(result.paceLimited)
        XCTAssertLessThan(result.weeklyLossKG, 0.3)
    }
    func testPlanPersistsWithoutReplacingTodaysWeightOrEnablingHealth() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("weights.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WeightStore(fileURL: url)
        XCTAssertTrue(store.save(kilograms: 89, date: Date()))
        let id = try XCTUnwrap(store.records.first?.id)
        let plan = SavedCaloriePlan(input: input(), calorieGoal: 2050)
        XCTAssertTrue(store.saveCaloriePlan(plan, unit: .kilograms, trackWeight: true))
        let reopened = WeightStore(fileURL: url)
        XCTAssertEqual(reopened.caloriePlan, plan)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.records.first?.id, id)
        XCTAssertEqual(reopened.records.first?.kilograms, 89)
        XCTAssertTrue(reopened.tracking)
        XCTAssertFalse(reopened.healthSharing)
    }
    func testPlanCanOptOutOfWeightAndRejectsInvalidTarget() {
        let store = WeightStore(inMemory: true)
        XCTAssertTrue(store.saveCaloriePlan(SavedCaloriePlan(input: input(), calorieGoal: 2050), unit: .pounds, trackWeight: false))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(store.tracking)
        XCTAssertFalse(store.saveCaloriePlan(SavedCaloriePlan(input: input(), calorieGoal: 400), unit: .pounds, trackWeight: true))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.caloriePlan?.calorieGoal, 2050)
    }
    func testLegacyWeightFileLoadsWithoutPlan() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("weights.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"tracking":true,"unit":"lb","healthSharing":false,"records":[]}"#.utf8).write(to: url)
        let store = WeightStore(fileURL: url)
        XCTAssertNil(store.error)
        XCTAssertNil(store.caloriePlan)
        XCTAssertTrue(store.tracking)
    }
    func testForgettingPlanRemovesAnswersButPreservesWeightAndPreferences() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("weights.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WeightStore(fileURL: url)
        XCTAssertTrue(store.saveCaloriePlan(SavedCaloriePlan(input: input(), calorieGoal: 2050), unit: .kilograms, trackWeight: true))
        let records = store.records
        XCTAssertTrue(store.forgetCaloriePlan())
        let reopened = WeightStore(fileURL: url)
        XCTAssertNil(reopened.caloriePlan)
        XCTAssertEqual(reopened.records, records)
        XCTAssertEqual(reopened.unit, .kilograms)
        XCTAssertTrue(reopened.tracking)
        XCTAssertFalse(reopened.healthSharing)
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("heightCM"))
        XCTAssertFalse(json.contains("goalKG"))
    }
}
