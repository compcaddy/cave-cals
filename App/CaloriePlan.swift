import Foundation

// A starting estimate, not a prediction of an individual's weight trajectory.
// See Documentation/Onboarding.md for sources, limits, and product assumptions.
enum PlanGender: String, Codable, CaseIterable, Identifiable {
    case female = "Female", male = "Male", another = "Another option", undisclosed = "Prefer not to say"
    var id: String { rawValue }
    /// Shown in setup. The calculator needs one of these two, so “No Say” (`undisclosed`) is hidden for now
    /// (September 30, 2026); it and `another` stay decodable so previously saved plans still load.
    static let choices: [PlanGender] = [.male, .female]
    /// Setup's wording; raw values stay unchanged because saved plans store them.
    var title: String {
        switch self { case .female: return "Woman"; case .male: return "Man"; case .undisclosed: return "No Say"; case .another: return rawValue }
    }
    var coefficient: Double? {
        switch self { case .female: return -161; case .male: return 5; default: return nil }
    }
    var minimumCalories: Double { self == .female ? 1200 : 1500 }
}

enum PlanActivity: String, Codable, CaseIterable, Identifiable {
    case low = "Mostly sitting", light = "Lightly active", moderate = "Active", high = "Very active"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .low: return "Little exercise or walking"
        case .light: return "Some walking or light exercise"
        case .moderate: return "Regular exercise, 3–5 days/week"
        case .high: return "Physical work or daily training"
        }
    }
    // Conservative starting heuristics; these are not measured energy expenditure.
    var multiplier: Double {
        switch self { case .low: return 1.2; case .light: return 1.375; case .moderate: return 1.55; case .high: return 1.725 }
    }
}

enum PlanIntent: String, Codable, CaseIterable, Identifiable {
    case lose = "Lose weight", maintain = "Maintain weight", gain = "Gain weight"
    var id: String { rawValue }
    /// Setup's short labels; raw values stay unchanged because saved plans store them.
    var title: String {
        switch self { case .lose: return "Lose"; case .maintain: return "Maintain"; case .gain: return "Gain" }
    }
    /// Lose and Gain have a goal weight and a weekly pace; Maintain has neither.
    var hasGoalWeight: Bool { self != .maintain }
    /// lose / maintain / gain, for usage stats.
    var statName: String { title.lowercased() }
    /// Pace levels offered in setup (turtle, dog, rabbit). Gaining stays slower so most of it can be muscle.
    var paceLevels: [Int] { self == .gain ? [0, 1] : [0, 1, 2] }
}

/// Weekly paces scale with body weight (October 7, 2026): about 0.26%, 0.52%, and 0.78% of today's weight,
/// so a 192 lb person sees 0.5, 1, and 1.5 lb a week. Each is rounded to what's shown (0.1 lb or 0.05 kg),
/// so the label is the pace used.
enum PlanPace {
    static let shares = [0.0026, 0.0052, 0.0078]
    static func weeklyKG(level: Int, weightKG: Double, unit: WeightUnit) -> Double {
        let share = shares[min(max(level, 0), shares.count - 1)]
        let step = unit == .kilograms ? 0.05 : 0.1
        let shown = max(step, (unit.display(weightKG * share) / step).rounded() * step)
        return unit.kilograms(shown)
    }
    /// The level closest to a saved plan's pace.
    static func level(for weeklyKG: Double, weightKG: Double, unit: WeightUnit, in levels: [Int]) -> Int {
        levels.min { abs(Self.weeklyKG(level: $0, weightKG: weightKG, unit: unit) - weeklyKG)
                   < abs(Self.weeklyKG(level: $1, weightKG: weightKG, unit: unit) - weeklyKG) } ?? 0
    }
}

struct CaloriePlanInput: Codable, Equatable {
    var gender: PlanGender
    var age: Int
    var heightCM: Double
    var weightKG: Double
    var goalKG: Double
    var activity: PlanActivity
    var intent: PlanIntent
    /// The weekly change in either direction: loss for Lose, gain for Gain (name kept for saved plans).
    var weeklyLossKG: Double
}

struct CaloriePlanEstimate: Equatable {
    /// Resting burn (Mifflin–St Jeor) before activity.
    var resting: Double = 0
    let maintenance: Double
    let calories: Double
    let weeklyLossKG: Double
    let paceLimited: Bool
}

enum CaloriePlanner {
    static func validationMessage(_ input: CaloriePlanInput, clinicianSupport: Bool = false) -> String? {
        guard !clinicianSupport else { return "A clinician can help set a target that fits your needs. You can still log food here." }
        guard (18...80).contains(input.age) else { return "This estimate is for adults 18–80. Use a target from your clinician instead." }
        guard input.gender.coefficient != nil else { return "This equation uses female or male reference values. You can set your own target instead." }
        guard input.heightCM.isFinite, (120...230).contains(input.heightCM),
              input.weightKG.isFinite, (35...300).contains(input.weightKG),
              input.goalKG.isFinite, (35...300).contains(input.goalKG),
              input.weeklyLossKG.isFinite, (0.04...2.5).contains(input.weeklyLossKG) else {
            return "Check your height, weight, and pace. If they’re outside this calculator’s range, use a clinician’s target."
        }
        let heightSquared = pow(input.heightCM / 100, 2)
        // Gaining from a low weight is a sensible goal, so only Lose and Maintain need a healthy starting BMI.
        if input.intent != .gain {
            guard input.weightKG / heightSquared >= 18.5 else { return "A clinician can help choose a suitable target at your current weight." }
        }
        if input.intent == .gain {
            guard input.goalKG > input.weightKG else { return "For weight gain, choose a goal above your current weight, or select Maintain." }
        }
        if input.intent == .lose {
            guard input.goalKG < input.weightKG else { return "For weight loss, choose a goal below your current weight, or select Maintain weight." }
            guard input.goalKG / heightSquared >= 18.5 else { return "That goal may be too low for your height. Choose a higher goal or use a clinician’s advice." }
        }
        return nil
    }

    static func estimate(_ input: CaloriePlanInput, clinicianSupport: Bool = false) -> CaloriePlanEstimate? {
        guard validationMessage(input, clinicianSupport: clinicianSupport) == nil,
              let coefficient = input.gender.coefficient else { return nil }
        let resting = 10 * input.weightKG + 6.25 * input.heightCM - 5 * Double(input.age) + coefficient
        let maintenance = resting * input.activity.multiplier
        guard maintenance.isFinite, maintenance >= input.gender.minimumCalories, maintenance <= 6000 else { return nil }
        if input.intent == .gain {
            // A modest surplus: at most 550 calories or 20% of maintenance, and never past 6,000.
            let requested = input.weeklyLossKG * 7700 / 7
            let surplus = max(0, min(requested, 550, maintenance * 0.2, 6000 - maintenance))
            let calories = ((maintenance + surplus) / 50).rounded(.down) * 50
            let actualSurplus = max(0, calories - maintenance)
            return CaloriePlanEstimate(resting: resting, maintenance: maintenance, calories: calories,
                                       weeklyLossKG: actualSurplus * 7 / 7700, paceLimited: requested - actualSurplus > 55)
        }
        let requested = input.intent == .lose ? input.weeklyLossKG * 7700 / 7 : 0
        let deficit = min(requested, 750, maintenance * 0.25, maintenance - input.gender.minimumCalories)
        // Round upward so rounding never increases the allowed deficit or crosses a floor.
        let calories = ((maintenance - deficit) / 50).rounded(.up) * 50
        let actualDeficit = max(0, maintenance - calories)
        return CaloriePlanEstimate(resting: resting, maintenance: maintenance, calories: calories,
                                   weeklyLossKG: actualDeficit * 7 / 7700,
                                   paceLimited: input.intent == .lose && requested - actualDeficit > 55)
    }
}

/// Suggested daily macro targets to go with a calorie target: protein from body weight first, then fat and carbs
/// share the calories left. Protein is a floor; carbs and fat are limits. See Documentation/Onboarding.md.
enum MacroPlanner {
    /// The top of the 1.2–1.6 g/kg range that helps keep muscle and fullness while losing weight (Leidy et al., 2015); also
    /// within the range that supports muscle gain with training (Morton et al., 2018).
    static let proteinPerKG = 1.6
    /// Acceptable ranges as a share of calories (National Academies): protein at most 35%, fat 20–35%, carbs 45–65%.
    static let maxProteinShare = 0.35, fatShare = 0.30, minFatShare = 0.20, minCarbShare = 0.45

    /// Nil wherever the calorie calculator gives no estimate, or for a target outside its floors and 6,000.
    static func suggest(_ input: CaloriePlanInput, calories: Double) -> MacroNutrients? {
        guard CaloriePlanner.validationMessage(input) == nil, calories.isFinite,
              (input.gender.minimumCalories...6000).contains(calories) else { return nil }
        // Goal weight (today's weight when maintaining), or the top of the healthy BMI range for this height
        // when that's lower, so extra body fat doesn't raise protein past what's useful.
        let healthy = 25 * pow(input.heightCM / 100, 2)
        // Gaining uses today's weight; extra protein past that doesn't add muscle faster.
        let reference = min(input.intent == .lose ? input.goalKG : input.weightKG, healthy)
        let protein = rounded(min(reference * proteinPerKG, calories * maxProteinShare / 4))
        // About 30% fat, less when protein is high so carbs keep at least 45%; fat never drops under 20%.
        let fatShare = max(minFatShare, min(fatShare, 1 - protein * 4 / calories - minCarbShare))
        let fat = rounded(calories * fatShare / 9)
        let carbs = rounded((calories - protein * 4 - fat * 9) / 4)
        return MacroNutrients(protein: protein, totalCarbs: carbs, fat: fat)
    }
    private static func rounded(_ grams: Double) -> Double { (grams / 5).rounded() * 5 }
}

extension MacroNutrients {
    /// Protein, carbs, and fat match (the goals people set; fiber and estimate flags don't count).
    func sameGoals(as other: MacroNutrients) -> Bool {
        MacroKind.primary.allSatisfy { self[keyPath: $0.keyPath] == other[keyPath: $0.keyPath] }
    }
}

struct SavedCaloriePlan: Codable, Equatable {
    var input: CaloriePlanInput
    var calorieGoal: Double
    var createdAt = Date()
}
