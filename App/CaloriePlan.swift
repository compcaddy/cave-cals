import Foundation

// A starting estimate, not a prediction of an individual's weight trajectory.
// See Documentation/Onboarding.md for sources, limits, and product assumptions.
enum PlanGender: String, Codable, CaseIterable, Identifiable {
    case female = "Female", male = "Male", another = "Another option", undisclosed = "Prefer not to say"
    var id: String { rawValue }
    /// Shown in setup. `another` stays decodable so previously saved plans still load.
    static let choices: [PlanGender] = [.female, .male, .undisclosed]
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
        case .moderate: return "Regular exercise, 3–5 days a week"
        case .high: return "Physical work or hard daily training"
        }
    }
    // Conservative starting heuristics; these are not measured energy expenditure.
    var multiplier: Double {
        switch self { case .low: return 1.2; case .light: return 1.375; case .moderate: return 1.55; case .high: return 1.725 }
    }
}

enum PlanIntent: String, Codable, CaseIterable, Identifiable {
    case lose = "Lose weight", maintain = "Maintain weight"
    var id: String { rawValue }
}

struct CaloriePlanInput: Codable, Equatable {
    var gender: PlanGender
    var age: Int
    var heightCM: Double
    var weightKG: Double
    var goalKG: Double
    var activity: PlanActivity
    var intent: PlanIntent
    var weeklyLossKG: Double
}

struct CaloriePlanEstimate: Equatable {
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
              input.weeklyLossKG.isFinite, (0.1...0.75).contains(input.weeklyLossKG) else {
            return "Check your height, weight, and pace. If they’re outside this calculator’s range, use a clinician’s target."
        }
        let heightSquared = pow(input.heightCM / 100, 2)
        guard input.weightKG / heightSquared >= 18.5 else { return "A clinician can help choose a suitable target at your current weight." }
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
        let requested = input.intent == .lose ? input.weeklyLossKG * 7700 / 7 : 0
        let deficit = min(requested, 750, maintenance * 0.25, maintenance - input.gender.minimumCalories)
        // Round upward so rounding never increases the allowed deficit or crosses a floor.
        let calories = ((maintenance - deficit) / 50).rounded(.up) * 50
        let actualDeficit = max(0, maintenance - calories)
        return CaloriePlanEstimate(maintenance: maintenance, calories: calories,
                                   weeklyLossKG: actualDeficit * 7 / 7700,
                                   paceLimited: input.intent == .lose && requested - actualDeficit > 55)
    }
}

struct SavedCaloriePlan: Codable, Equatable {
    var input: CaloriePlanInput
    var calorieGoal: Double
    var createdAt = Date()
}
