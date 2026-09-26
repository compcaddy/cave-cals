import Foundation

/// Grams for one serving. Nil means unknown; zero is a known zero.
struct MacroNutrients: Codable, Equatable, Sendable {
    var protein: Double?
    var totalCarbs: Double?
    var fiber: Double?
    var fat: Double?
    // Preserve estimate provenance independently when a user edits another nutrient.
    var estimatedProtein: Bool? = nil
    var estimatedTotalCarbs: Bool? = nil
    var estimatedFiber: Bool? = nil
    var estimatedFat: Bool? = nil

    var isValid: Bool {
        let validAmounts = [protein, totalCarbs, fiber, fat].allSatisfy {
            $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 100_000)
        }
        guard validAmounts else { return false }
        if let totalCarbs, let fiber { return fiber <= totalCarbs }
        return true
    }
    /// Unknown fiber is never treated as zero.
    var netCarbs: Double? {
        guard isValid, let totalCarbs, let fiber else { return nil }
        return totalCarbs - fiber
    }
    var estimatedNetCarbs: Bool { estimatedTotalCarbs == true || estimatedFiber == true }
    var isValidGoal: Bool {
        isValid && [protein, totalCarbs, fiber, fat].compactMap { $0 }.allSatisfy { $0 > 0 && $0 <= 9999 }
    }
    var hasValues: Bool { protein != nil || totalCarbs != nil || fiber != nil || fat != nil }
    var isComplete: Bool { protein != nil && totalCarbs != nil && fiber != nil && fat != nil }
    var hasEstimates: Bool { estimatedProtein == true || estimatedTotalCarbs == true || estimatedFiber == true || estimatedFat == true }
    func scaled(_ factor: Double) -> Self {
        var copy = self
        copy.protein = protein.map { $0 * factor }; copy.totalCarbs = totalCarbs.map { $0 * factor }; copy.fiber = fiber.map { $0 * factor }; copy.fat = fat.map { $0 * factor }
        return copy
    }
    func markedEstimated() -> Self {
        var copy = self
        copy.estimatedProtein = protein != nil; copy.estimatedTotalCarbs = totalCarbs != nil; copy.estimatedFiber = fiber != nil; copy.estimatedFat = fat != nil
        return copy
    }
    func fillingMissing(from other: Self) -> Self {
        var copy = self
        if protein == nil { copy.protein = other.protein; copy.estimatedProtein = other.estimatedProtein }
        if totalCarbs == nil { copy.totalCarbs = other.totalCarbs; copy.estimatedTotalCarbs = other.estimatedTotalCarbs }
        if fiber == nil { copy.fiber = other.fiber; copy.estimatedFiber = other.estimatedFiber }
        if fat == nil { copy.fat = other.fat; copy.estimatedFat = other.estimatedFat }
        return copy
    }
    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum MacroKind: String, CaseIterable, Identifiable {
    case protein, totalCarbs, fiber, fat
    static let primary: [Self] = [.protein, .totalCarbs, .fat]
    var id: String { rawValue }
    var title: String { switch self { case .protein: "Protein"; case .totalCarbs: "Carbs"; case .fiber: "Fiber"; case .fat: "Fat" } }
    var editorTitle: String { self == .totalCarbs ? "Carbohydrates" : title }
    var shortTitle: String { switch self { case .protein: "P"; case .totalCarbs: "C"; case .fiber: "Fiber"; case .fat: "F" } }
    var keyPath: WritableKeyPath<MacroNutrients, Double?> {
        switch self { case .protein: \.protein; case .totalCarbs: \.totalCarbs; case .fiber: \.fiber; case .fat: \.fat }
    }
    var estimateKeyPath: WritableKeyPath<MacroNutrients, Bool?> {
        switch self { case .protein: \.estimatedProtein; case .totalCarbs: \.estimatedTotalCarbs; case .fiber: \.estimatedFiber; case .fat: \.estimatedFat }
    }
}

struct MacroTotal {
    var grams: Double?
    var incomplete: Bool
    var estimated: Bool
    var text: String {
        guard let grams else { return "—" }
        return "\(estimated ? "≈" : "")\(grams.macroText)\(incomplete ? "+" : "")"
    }
}

struct MacroSummary {
    let values: [MacroNutrients?]
    init(_ drafts: [EntryDraft]) { values = drafts.map(\.totalMacros) }
    func total(_ kind: MacroKind) -> MacroTotal {
        let known = values.compactMap { $0?[keyPath: kind.keyPath] }
        return MacroTotal(grams: values.isEmpty ? 0 : known.isEmpty ? nil : known.reduce(0, +),
                          incomplete: known.count < values.count,
                          estimated: values.contains { $0?[keyPath: kind.estimateKeyPath] == true })
    }
    var compactText: String {
        MacroKind.primary.map { "\($0.shortTitle) \(total($0).text)" }.joined(separator: " · ") + " g"
    }
    var accessibilityText: String {
        MacroKind.primary.map { kind in
            let amount = total(kind)
            return "\(kind.title), \(amount.grams.map { "\($0.macroText) grams" } ?? "unknown")\(amount.incomplete ? ", incomplete" : "")\(amount.estimated ? ", estimated" : "")"
        }.joined(separator: "; ")
    }
    var incomplete: Bool { MacroKind.primary.contains { total($0).incomplete } }
}

extension Double {
    var macroText: String { formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
}
