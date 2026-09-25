import SwiftUI

extension View {
    /// Cream screen background in place of the default system list/grouped background.
    func caveScreenBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.caveBackground)
    }

    /// A lighter rounded card behind a list row instead of separator lines.
    func caveCardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.caveSurface)
                    .padding(.horizontal, 16).padding(.vertical, 3)
            )
    }
}

struct MacroLine: View {
    let summary: MacroSummary
    var body: some View {
        Text(summary.compactText)
            .font(.cave(.caption)).foregroundStyle(.secondary)
            .accessibilityLabel(summary.accessibilityText)
    }
}

struct DailyMacrosView: View {
    let summary: MacroSummary
    let goals: MacroNutrients
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(MacroKind.primary) { kind in
                    let title = Text(kind.title + ":").font(.cave(.caption)).foregroundStyle(.secondary)
                    let amount = Text(summary.total(kind).text).font(.cave(.body))
                        + Text(goals[keyPath: kind.keyPath].map { "/\($0.macroText)" } ?? "")
                            .font(.cave(.caption)).foregroundStyle(.secondary)
                        + Text("g").font(.cave(.body))
                    // Large Dynamic Type sizes fall back to the stacked layout instead of truncating.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) { title; amount }
                            .lineLimit(1)
                        VStack(spacing: 2) { title; amount }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dailyMacro-\(kind.rawValue)")
                }
            }
            if summary.incomplete {
                Text("Some macros missing · + means partial")
                    .font(.cave(.caption2)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Keep invalid input visible and invalidate Save rather than silently retaining an old number.
struct MacroAmountField: View {
    let title: String
    @Binding var value: Double?
    var estimated = false
    var placeholder = "—"
    var identifier: String
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            Text(title)
            if estimated { Text("≈").foregroundStyle(.secondary).accessibilityLabel("Estimated") }
            Spacer(minLength: 16)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 110, minHeight: 44).focused($focused)
                .foregroundStyle(value.map { !$0.isFinite || $0 < 0 } == true ? Color.red : Color.primary)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
                .selectValueOnFocus(identifier: identifier)
                .onChange(of: text) { _, text in
                    guard focused else { return }
                    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if input.isEmpty { value = nil }
                    else {
                        let separator = Locale.current.decimalSeparator ?? "."
                        let normalized = input.replacingOccurrences(of: separator, with: ".")
                        value = Double(normalized) ?? .nan
                    }
                }
                .onChange(of: value) { _, _ in if !focused { updateText() } }
                .onChange(of: focused) { _, focused in if !focused { updateText() } }
                .onAppear { updateText() }
            Text("g").foregroundStyle(.secondary)
        }
        .selectValueOnTap(focus: $focused)
    }
    private func updateText() { text = value.flatMap { $0.isFinite ? $0.macroText : nil } ?? (value == nil ? "" : text) }
}

struct MacroEditorSection: View {
    @Binding var draft: EntryDraft
    @State private var estimating = false
    @State private var message: String?
    var body: some View {
        Section {
            ForEach(MacroKind.allCases) { kind in
                MacroAmountField(title: kind.editorTitle, value: binding(kind), estimated: draft.macrosPerServing?[keyPath: kind.estimateKeyPath] == true, identifier: "macro-\(kind.rawValue)")
            }
            HStack {
                Text("Net carbs").foregroundStyle(.secondary)
                Spacer()
                Text(draft.totalMacros?.netCarbs.map { "\(draft.totalMacros?.estimatedNetCarbs == true ? "≈" : "")\($0.macroText) g" } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("calculatedNetCarbs")
            if let macros = draft.totalMacros, let carbs = macros.totalCarbs, let fiber = macros.fiber, fiber > carbs {
                Text("Fiber cannot exceed total carbohydrates.").font(.cave(.caption)).foregroundStyle(.red)
            }
            if !(draft.totalMacros?.isComplete ?? false) {
                Button {
                    estimating = true; message = nil
                } label: {
                    HStack {
                        Text(estimating ? "Estimating…" : "Estimate missing")
                        if estimating { Spacer(); ProgressView() }
                    }.frame(minHeight: 44)
                }
                .disabled(estimating || !draft.isValid || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                .accessibilityIdentifier("estimateMacros")
            }
            if let message { Text(message).font(.cave(.caption)).foregroundStyle(.secondary) }
        } header: {
            Text("Macros · total")
        } footer: {
            Text(draft.totalMacros?.hasEstimates == true
                 ? "≈ Estimated. Carbohydrates include fiber. Net carbs = carbohydrates − fiber."
                 : "Optional. Carbohydrates include fiber. Net carbs = carbohydrates − fiber. Estimates use AI.")
        }
        .task(id: estimating) {
            guard estimating else { return }
            let snapshot = draft
            defer { estimating = false }
            do {
                let estimate = try await AIBackend.shared.estimateMacros(for: snapshot)
                try Task.checkCancellation()
                // The user may edit the portion or food while the request is running.
                guard draft.name == snapshot.name, draft.calories == snapshot.calories,
                      draft.servings == snapshot.servings, draft.servingDescription == snapshot.servingDescription else {
                    message = "Food changed. Tap Estimate missing again."; return
                }
                let totals = (draft.totalMacros ?? MacroNutrients()).fillingMissing(from: estimate)
                guard totals.isValid else {
                    message = "Estimate conflicts with your carbohydrates or fiber. Check those values and try again."; return
                }
                draft.macrosPerServing = totals.scaled(1 / draft.servings)
                if !estimate.hasValues { message = "Try a more specific food name." }
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
    private func binding(_ kind: MacroKind) -> Binding<Double?> {
        Binding(get: { draft.totalMacros?[keyPath: kind.keyPath] }, set: { value in
            var macros = draft.macrosPerServing ?? MacroNutrients()
            macros[keyPath: kind.keyPath] = value.map { $0 / (draft.servings > 0 ? draft.servings : 1) }
            macros[keyPath: kind.estimateKeyPath] = false
            draft.macrosPerServing = macros
        })
    }
}

struct MacroSettingsSection: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Section {
            Toggle("Track macros", isOn: Binding(get: { store.tracksMacros }, set: { store.setTracksMacros($0) }))
                .accessibilityIdentifier("trackMacros")
            if store.tracksMacros {
                NavigationLink("Macro goals") { MacroGoalsView(goals: store.macroGoals) }
                    .accessibilityIdentifier("macroGoals")
            }
        }
    }
}

struct MacroGoalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var goals: MacroNutrients
    var body: some View {
        Form {
            Section {
                ForEach(MacroKind.primary) { kind in
                    MacroAmountField(title: kind.title, value: Binding(get: { goals[keyPath: kind.keyPath] }, set: { goals[keyPath: kind.keyPath] = $0 }), placeholder: "None", identifier: "goal-\(kind.rawValue)")
                }
            } footer: { Text("Daily goals. Leave blank for none.") }
        }.caveScreenBackground()
        .navigationTitle("Macro goals").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.saveMacroGoals(goals) { dismiss() } }
                    .disabled(!goals.isValidGoal)
                    .accessibilityIdentifier("saveMacroGoals")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
    }
}

/// Schoolbell has no bold weight; restating the glyphs at tiny offsets thickens the strokes like a heavier pen.
private struct InkBoldText: View {
    let text: String
    let font: Font
    var weight: CGFloat = 1.1
    init(_ text: String, font: Font, weight: CGFloat = 1.1) { self.text = text; self.font = font; self.weight = weight }
    var body: some View {
        let offsets: [CGSize] = [.init(width: weight, height: 0), .init(width: -weight, height: 0),
                                 .init(width: 0, height: weight), .init(width: 0, height: -weight),
                                 .init(width: weight * 0.7, height: weight * 0.7), .init(width: -weight * 0.7, height: -weight * 0.7),
                                 .init(width: weight * 0.7, height: -weight * 0.7), .init(width: -weight * 0.7, height: weight * 0.7)]
        Text(text).font(font)
            .overlay { ZStack { ForEach(offsets.indices, id: \.self) { Text(text).font(font).offset(offsets[$0]) } } }
    }
}

private struct SummaryBar: View {
    let fraction: Double
    var height: CGFloat = 10
    /// Only calories turn red when over; going past a macro goal (e.g. protein) is often intended.
    var warnsWhenOver = true
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(fraction > 1 && warnsWhenOver ? Color.red : Color.caveOrange)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Home summary: one wide calorie row with its bar, then compact macro columns with thinner bars.
struct DailySummaryCard: View {
    let calories: Double
    let calorieGoal: Double?
    let macros: MacroSummary?
    let macroGoals: MacroNutrients

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                InkBoldText(calories.calorieText, font: .custom("Schoolbell-Regular", size: 44, relativeTo: .largeTitle))
                Text(calorieGoal.map { "/ \($0.calorieText) cals" } ?? "cals")
                    .font(.cave(.title3)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let calorieGoal {
                    Text(calories > calorieGoal
                         ? "\((calories - calorieGoal).calorieText) over"
                         : "\((calorieGoal - calories).calorieText) left")
                        .font(.cave(.title3))
                        .foregroundStyle(calories > calorieGoal ? Color.red : Color.primary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            // Trim the big font's empty descender space so the bar sits just under the numbers.
            .padding(.bottom, (UIFont(name: "Schoolbell-Regular",
                                      size: UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 44))?.descender ?? 0) + 4)
            if let calorieGoal {
                SummaryBar(fraction: calories / calorieGoal)
            }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(calorieGoal.map { "\(calories.calorieText) of \($0.calorieText) calories" } ?? "\(calories.calorieText) calories")
            .accessibilityValue(calorieGoal.map { "\((max(calories / $0, 0) * 100).calorieText) percent of goal" } ?? "")
            .accessibilityIdentifier("calorieSummary")
            if let macros {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(MacroKind.primary) { kind in
                        macroColumn(kind, total: macros.total(kind), goal: macroGoals[keyPath: kind.keyPath])
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailySummaryCard")
        .fixedSize(horizontal: false, vertical: true)
    }

    private func macroColumn(_ kind: MacroKind, total: MacroTotal, goal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                // Height-only sizing keeps each icon's own width (the wheat is narrow).
                Image(glyph(kind).rawValue).renderingMode(.template).resizable().scaledToFit()
                    .frame(height: 24).foregroundStyle(Color.caveOrange).accessibilityHidden(true)
                Text(kind.title.uppercased()).font(.cave(.caption).bold())
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(wholeGrams(total)).font(.cave(.title2).bold())
                if let goal, goal > 0 {
                    Text("/ \(goal.formatted(.number.precision(.fractionLength(0))))g")
                        .font(.cave(.caption)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.leading, 4)
            if let goal, goal > 0 {
                SummaryBar(fraction: (total.grams ?? 0) / goal, height: 6, warnsWhenOver: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) \(total.text) g" + (goal.flatMap { $0 > 0 ? " of \($0.macroText) g" : nil } ?? ""))
        .accessibilityIdentifier("dailyMacro-\(kind.rawValue)")
    }

    private func wholeGrams(_ total: MacroTotal) -> String {
        guard let grams = total.grams else { return "—" }
        return grams.formatted(.number.precision(.fractionLength(0))) + (total.incomplete ? "+" : "")
    }

    private func glyph(_ kind: MacroKind) -> CaveGlyph {
        switch kind {
        case .protein: .protein
        case .totalCarbs: .carbs
        default: .fat
        }
    }
}
