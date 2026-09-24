import SwiftUI

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
        }
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
