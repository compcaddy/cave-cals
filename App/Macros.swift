import Foundation

/// Grams for one serving. Nil means unknown; zero is a known zero.
struct MacroNutrients: Codable, Equatable, Sendable {
    var protein: Double?
    var netCarbs: Double?
    var fat: Double?
    // Preserve estimate provenance independently when a user edits another nutrient.
    var estimatedProtein: Bool? = nil
    var estimatedNetCarbs: Bool? = nil
    var estimatedFat: Bool? = nil

    var isValid: Bool { [protein, netCarbs, fat].allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 100_000) } }
    var isValidGoal: Bool {
        isValid && [protein, netCarbs, fat].compactMap { $0 }.allSatisfy { $0 > 0 && $0 <= 9999 }
    }
    var hasValues: Bool { protein != nil || netCarbs != nil || fat != nil }
    var isComplete: Bool { protein != nil && netCarbs != nil && fat != nil }
    var hasEstimates: Bool { estimatedProtein == true || estimatedNetCarbs == true || estimatedFat == true }
    func scaled(_ factor: Double) -> Self {
        var copy = self
        copy.protein = protein.map { $0 * factor }; copy.netCarbs = netCarbs.map { $0 * factor }; copy.fat = fat.map { $0 * factor }
        return copy
    }
    func markedEstimated() -> Self {
        var copy = self
        copy.estimatedProtein = protein != nil; copy.estimatedNetCarbs = netCarbs != nil; copy.estimatedFat = fat != nil
        return copy
    }
    func fillingMissing(from other: Self) -> Self {
        var copy = self
        if protein == nil { copy.protein = other.protein; copy.estimatedProtein = other.estimatedProtein }
        if netCarbs == nil { copy.netCarbs = other.netCarbs; copy.estimatedNetCarbs = other.estimatedNetCarbs }
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
    case protein, netCarbs, fat
    var id: String { rawValue }
    var title: String { switch self { case .protein: "Protein"; case .netCarbs: "Net carbs"; case .fat: "Fat" } }
    var shortTitle: String { switch self { case .protein: "P"; case .netCarbs: "C"; case .fat: "F" } }
    var keyPath: WritableKeyPath<MacroNutrients, Double?> {
        switch self { case .protein: \.protein; case .netCarbs: \.netCarbs; case .fat: \.fat }
    }
    var estimateKeyPath: WritableKeyPath<MacroNutrients, Bool?> {
        switch self { case .protein: \.estimatedProtein; case .netCarbs: \.estimatedNetCarbs; case .fat: \.estimatedFat }
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
        MacroKind.allCases.map { "\($0.shortTitle) \(total($0).text)" }.joined(separator: " · ") + " g"
    }
    var accessibilityText: String {
        MacroKind.allCases.map { kind in
            let amount = total(kind)
            return "\(kind.title), \(amount.grams.map { "\($0.macroText) grams" } ?? "unknown")\(amount.incomplete ? ", incomplete" : "")\(amount.estimated ? ", estimated" : "")"
        }.joined(separator: "; ")
    }
    var incomplete: Bool { MacroKind.allCases.contains { total($0).incomplete } }
}

extension Double {
    var macroText: String { formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
}
