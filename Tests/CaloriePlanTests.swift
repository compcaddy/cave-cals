import XCTest
@testable import CaveCals

@MainActor final class CaloriePlanTests: XCTestCase {
    private func input(gender: PlanGender = .male, age: Int = 35, height: Double = 180, weight: Double = 90, goal: Double = 80, activity: PlanActivity = .light, intent: PlanIntent = .lose, pace: Double = 0.5) -> CaloriePlanInput {
        CaloriePlanInput(gender: gender, age: age, heightCM: height, weightKG: weight, goalKG: goal, activity: activity, intent: intent, weeklyLossKG: pace)
    }
    func testGainAddsAModestSurplusAndNeedsAHigherGoal() throws {
        let result = try XCTUnwrap(CaloriePlanner.estimate(input(goal: 95, intent: .gain, pace: 0.25)))
        XCTAssertEqual(result.maintenance, 2550.625, accuracy: 0.001)
        XCTAssertEqual(result.resting, 2550.625 / 1.375, accuracy: 0.001)
        XCTAssertEqual(result.calories, 2800) // + 275, rounded down to 50
        XCTAssertFalse(result.paceLimited)
        // The surplus is capped at 550 calories or 20% of maintenance.
        let faster = try XCTUnwrap(CaloriePlanner.estimate(input(goal: 95, intent: .gain, pace: 0.75)))
        XCTAssertEqual(faster.calories, 3050) // 20% of maintenance (510) caps it first
        XCTAssertTrue(faster.paceLimited)
        XCTAssertNil(CaloriePlanner.estimate(input(goal: 85, intent: .gain)), "Gain needs a goal above today's weight")
        // A low starting weight is fine when gaining.
        XCTAssertNotNil(CaloriePlanner.estimate(input(weight: 55, goal: 62, intent: .gain)))
        XCTAssertNil(CaloriePlanner.estimate(input(weight: 55, goal: 50)))
        let macros = try XCTUnwrap(MacroPlanner.suggest(input(goal: 95, intent: .gain), calories: 2800))
        XCTAssertEqual(macros.protein, 130, "Protein from today's weight, capped at a healthy weight")
    }
    private func hundredths(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    func testPacesFollowBodyWeightAndMatchTheirLabels() {
        // 192 lb: 0.5, 1, and 1.5 lb a week.
        let pounds = WeightUnit.pounds
        let me = pounds.kilograms(192)
        XCTAssertEqual([0, 1, 2].map { hundredths(pounds.display(PlanPace.weeklyKG(level: $0, weightKG: me, unit: pounds))) },
                       [0.5, 1.0, 1.5])
        // 90 lb lighter: smaller steps.
        XCTAssertEqual([0, 1, 2].map { hundredths(pounds.display(PlanPace.weeklyKG(level: $0, weightKG: pounds.kilograms(102), unit: pounds))) },
                       [0.3, 0.5, 0.8])
        // Kilograms round to 0.05.
        XCTAssertEqual([0, 1, 2].map { hundredths(PlanPace.weeklyKG(level: $0, weightKG: 90, unit: .kilograms)) }, [0.25, 0.45, 0.7])
        // Never zero, even at a very low weight.
        XCTAssertGreaterThan(PlanPace.weeklyKG(level: 0, weightKG: 15, unit: pounds), 0)
        // Saved plans from before map to the nearest level.
        XCTAssertEqual(PlanPace.level(for: 0.5, weightKG: 90, unit: .kilograms, in: [0, 1, 2]), 1)
        XCTAssertEqual(PlanPace.level(for: 0.75, weightKG: 90, unit: .kilograms, in: [0, 1]), 1)
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
        XCTAssertNil(CaloriePlanner.estimate(input(pace: 3)))
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
    func testSuggestedMacrosStartFromGoalWeightProtein() throws {
        // 180 cm with an 80 kg goal: 1.6 × 80 = 128 → 130 g protein. Fat takes 29.6% so carbs keep 45%
        // (67.5 g, rounded to 70 g), and carbs get the rest: (2,050 − 520 − 630) / 4 = 225 g.
        let macros = try XCTUnwrap(MacroPlanner.suggest(input(), calories: 2050))
        XCTAssertEqual(macros.protein, 130)
        XCTAssertEqual(macros.fat, 70)
        XCTAssertEqual(macros.totalCarbs, 225)
        XCTAssertNil(macros.fiber)
        XCTAssertTrue(macros.isValidGoal)
        // Calories follow the typed target.
        let higher = try XCTUnwrap(MacroPlanner.suggest(input(), calories: 2500))
        XCTAssertEqual(higher.protein, 130)
        XCTAssertEqual(higher.fat, 85)
        XCTAssertEqual(higher.totalCarbs, 305)
    }
    func testSuggestedProteinUsesHealthyWeightWhenLowerAndCurrentWeightWhenMaintaining() throws {
        // A 100 kg goal at 180 cm is past the healthy-weight cap (25 × 1.8² = 81 kg): 1.6 × 81 → 130 g, not 160 g.
        XCTAssertEqual(MacroPlanner.suggest(input(weight: 130, goal: 100), calories: 2400)?.protein, 130)
        // Maintaining at 70 kg uses today's weight: 1.6 × 70 = 112 → 110 g.
        XCTAssertEqual(MacroPlanner.suggest(input(weight: 70, goal: 70, intent: .maintain), calories: 2300)?.protein, 110)
    }
    func testSuggestedProteinIsCappedAtThirtyFivePercent() throws {
        // 200 cm with a 95 kg goal wants 152 g, but at 1,500 calories protein stops at 35% (131 g → 130 g).
        let macros = try XCTUnwrap(MacroPlanner.suggest(input(height: 200, weight: 110, goal: 95), calories: 1500))
        XCTAssertEqual(macros.protein, 130)
        XCTAssertEqual(macros.fat, 35)
        XCTAssertEqual(macros.totalCarbs, 165)
    }
    func testSuggestedMacrosAddUpAndStayInHealthyRanges() throws {
        for gender in [PlanGender.female, .male] {
            for height in [150.0, 170, 195] {
                for weight in [55.0, 80, 120, 170] {
                    for activity in PlanActivity.allCases {
                        for intent in PlanIntent.allCases {
                            let value = input(gender: gender, height: height, weight: weight, goal: intent == .lose ? weight - 5 : intent == .gain ? weight + 5 : weight, activity: activity, intent: intent)
                            guard let calories = CaloriePlanner.estimate(value)?.calories else { continue }
                            let macros = try XCTUnwrap(MacroPlanner.suggest(value, calories: calories))
                            let protein = try XCTUnwrap(macros.protein), carbs = try XCTUnwrap(macros.totalCarbs), fat = try XCTUnwrap(macros.fat)
                            XCTAssertTrue(macros.isValidGoal)
                            // Only the carbs' 5 g rounding separates the macros from the calories.
                            XCTAssertEqual(protein * 4 + carbs * 4 + fat * 9, calories, accuracy: 10)
                            XCTAssertLessThanOrEqual(protein * 4 / calories, 0.35 + 10 / calories)
                            XCTAssertGreaterThanOrEqual(fat * 9 / calories, 0.2 - 22.5 / calories)
                            XCTAssertLessThanOrEqual(fat * 9 / calories, 0.3 + 22.5 / calories)
                            XCTAssertGreaterThanOrEqual(carbs * 4 / calories, 0.45 - 45 / calories)
                            XCTAssertEqual(protein.truncatingRemainder(dividingBy: 5), 0)
                        }
                    }
                }
            }
        }
    }
    func testNoSuggestedMacrosWhereTheCalculatorGivesNoEstimate() {
        XCTAssertNil(MacroPlanner.suggest(input(age: 16), calories: 2000))
        XCTAssertNil(MacroPlanner.suggest(input(gender: .undisclosed), calories: 2000))
        XCTAssertNil(MacroPlanner.suggest(input(goal: 45), calories: 2000))
        XCTAssertNil(MacroPlanner.suggest(input(gender: .female), calories: 1100))
        XCTAssertNil(MacroPlanner.suggest(input(), calories: 1400))
        XCTAssertNil(MacroPlanner.suggest(input(), calories: 6500))
        XCTAssertNil(MacroPlanner.suggest(input(), calories: .nan))
    }
    func testSameGoalsComparesOnlyProteinCarbsAndFat() {
        let goals = MacroNutrients(protein: 130, totalCarbs: 235, fat: 65)
        XCTAssertTrue(goals.sameGoals(as: MacroNutrients(protein: 130, totalCarbs: 235, fiber: 30, fat: 65)))
        XCTAssertFalse(goals.sameGoals(as: MacroNutrients(protein: 130, totalCarbs: 235)))
        XCTAssertTrue(MacroNutrients().sameGoals(as: MacroNutrients()))
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
