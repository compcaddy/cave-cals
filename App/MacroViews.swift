import SwiftUI

extension View {
    /// Cream screen background in place of the default system list/grouped background.
    func caveScreenBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.caveBackground)
    }

    /// A lighter rounded card behind a list row instead of separator lines.
    func caveCardRow(opacity: Double = 1) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.caveSurface)
                    .padding(.horizontal, 16).padding(.vertical, 3)
                    .opacity(opacity)
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
            // Matches the serving rows above: lowercase, smaller, lighter label.
            Text(title.lowercased()).font(.cave(.subheadline)).opacity(0.65)
            if estimated { Text("≈").foregroundStyle(.secondary).accessibilityLabel("Estimated") }
            Spacer(minLength: 16)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 110).focused($focused)
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
        .editorRowInsets()
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
                Text("net carbs (calculated)").font(.cave(.subheadline)).opacity(0.65)
                Spacer()
                Text(draft.totalMacros?.netCarbs.map { "\(draft.totalMacros?.estimatedNetCarbs == true ? "≈" : "")\($0.macroText) g" } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("calculatedNetCarbs")
            .editorRowInsets()
            if let macros = draft.totalMacros, let carbs = macros.totalCarbs, let fiber = macros.fiber, fiber > carbs {
                Text("Fiber cannot exceed total carbohydrates.").font(.cave(.caption)).foregroundStyle(.red)
            }
            if !(draft.totalMacros?.isComplete ?? false) {
                Button {
                    estimating = true; message = nil
                } label: {
                    HStack {
                        Text(estimating ? "Estimating…" : "Estimate values using AI")
                        if estimating { Spacer(); ProgressView().controlSize(.small) }
                    }.font(.cave(.subheadline))
                }
                .editorRowInsets()
                .disabled(estimating || !draft.isValid || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                .accessibilityIdentifier("estimateMacros")
            }
            if let message { Text(message).font(.cave(.caption)).foregroundStyle(.secondary) }
        } header: {
            Text("Macros · total")
        } footer: {
            if draft.totalMacros?.hasEstimates == true { Text("≈ Estimated") }
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
                    message = "Food changed. Tap Estimate values using AI again."; return
                }
                let totals = (draft.totalMacros ?? MacroNutrients()).fillingMissing(from: estimate)
                guard totals.isValid else {
                    message = "Estimate conflicts with your carbohydrates or fiber. Check those values and try again."; return
                }
                draft.macrosPerServing = totals.scaled(1 / draft.servings)
                if !estimate.hasValues { message = "Try a more specific food name." }
            } catch is CancellationError { }
            catch { message = error.localizedDescription; UsageStats.shared.error(.macroEstimate, error) }
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
                NavigationLink("Macro goals") { MacroGoalsView(goals: store.macroGoals).hapticOnPush() }
                    .accessibilityIdentifier("macroGoals")
            }
        }
    }
}

struct MacroGoalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    @State var goals: MacroNutrients
    @State private var usedSuggestion = false
    /// From the saved calorie plan and today's calorie goal, when the calculator can suggest them.
    private var suggestion: MacroNutrients? {
        guard let plan = weights.caloriePlan, let calories = store.profile?.dailyGoal else { return nil }
        return MacroPlanner.suggest(plan.input, calories: calories)
    }
    var body: some View {
        HapticForm {
            Section {
                ForEach(MacroKind.primary) { kind in
                    MacroAmountField(title: kind.title, value: Binding(get: { goals[keyPath: kind.keyPath] }, set: { goals[keyPath: kind.keyPath] = $0 }), placeholder: "None", identifier: "goal-\(kind.rawValue)")
                }
            } footer: { Text("Daily goals. Leave blank for none.") }
            if let suggestion {
                let applied = goals.sameGoals(as: suggestion)
                Section {
                    Button {
                        for kind in MacroKind.primary { goals[keyPath: kind.keyPath] = suggestion[keyPath: kind.keyPath] }
                        usedSuggestion = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(applied ? "Using suggested targets" : "Use suggested targets")
                                .foregroundStyle(applied ? Color.secondary : Color.caveOrange)
                            Text(Self.summary(suggestion)).font(.cave(.caption)).foregroundStyle(Color.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .disabled(applied)
                    .accessibilityIdentifier("suggestMacroGoals")
                } footer: {
                    Text("From your calorie plan and daily calorie goal: protein from your goal weight, fat about 30% of calories, carbs the rest.")
                }
            }
        }.caveScreenBackground()
        .tapOutsideClosesKeyboard()
        .navigationTitle("Macro goals").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard store.saveMacroGoals(goals) else { return }
                    if usedSuggestion, let suggestion, goals.sameGoals(as: suggestion) { UsageStats.shared.event("macroTargets.saved", ["from": "goals"]) }
                    dismiss()
                }
                    .hapticButtonStyle(.automatic).hapticFeel(.success)
                    .disabled(!goals.isValidGoal)
                    .accessibilityIdentifier("saveMacroGoals")
            }
        }
    }
    /// "At least 130 g protein · up to 235 g carbs · up to 65 g fat"
    private static func summary(_ macros: MacroNutrients) -> String {
        func grams(_ value: Double?) -> String { (value ?? 0).formatted(.number.precision(.fractionLength(0))) }
        return "At least \(grams(macros.protein)) g protein · up to \(grams(macros.totalCarbs)) g carbs · up to \(grams(macros.fat)) g fat"
    }
}

/// Schoolbell has no bold weight; restating the glyphs at tiny offsets thickens the strokes like a heavier pen.
struct InkBoldText: View {
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
            .overlay { ZStack { ForEach(offsets.indices, id: \.self) { Text(text).font(font).offset(offsets[$0]) } }.accessibilityHidden(true) }
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

/// Draws `content` with a number that SwiftUI interpolates when it changes inside an animation, so totals count.
private struct CountingValue<Content: View>: View, Animatable {
    var value: Double
    @ViewBuilder let content: (Double) -> Content
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { content(value) }
}

/// The totals the summary card last showed. Home keeps them while the card is hidden (add mode) or covered by
/// a sheet, so whatever was logged meanwhile counts up once the card can be seen again.
struct SummaryFigures: Equatable {
    var day: Date
    var calories: Double
    var grams: [MacroKind: Double] = [:]
}

/// Home summary: one wide calorie row with its bar, then compact macro columns with thinner bars.
struct DailySummaryCard: View {
    let day: Date
    let calories: Double
    let calorieGoal: Double?
    let macros: MacroSummary?
    let macroGoals: MacroNutrients
    /// False while a sheet covers Home; a new total waits to count until the sheet goes away.
    let isVisible: Bool
    @Binding var shown: SummaryFigures?
    /// Tapping Protein, Carbs, or Fat opens the day's breakdown (`MacroBreakdownSheet`).
    var openMacro: ((MacroKind) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fast at first, then slowing as it settles onto the final number. The rumble reads the same curve.
    private static let countUpCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.22, y: 1), endControlPoint: UnitPoint(x: 0.36, y: 1))
    private static let countUpDuration: TimeInterval = 0.9
    private static let countUp = Animation.timingCurve(countUpCurve, duration: countUpDuration)
    private static let totalFont = Font.custom("Schoolbell-Regular", size: 52, relativeTo: .largeTitle)

    private var target: SummaryFigures {
        var grams: [MacroKind: Double] = [:]
        if let macros { for kind in MacroKind.primary { grams[kind] = macros.total(kind).grams ?? 0 } }
        return SummaryFigures(day: Calendar.current.startOfDay(for: day), calories: calories, grams: grams)
    }

    /// Changes on the same day count from the last shown totals; another day's totals simply appear.
    private func showLatest() {
        let target = target
        guard shown != target else { return }
        if let shown, shown.day == target.day {
            guard isVisible else { return }
            withAnimation(reduceMotion ? nil : Self.countUp) { self.shown = target }
            // Only a rising total rumbles; with Reduce Motion it's just the landing bump.
            Haptics.countUp(by: target.calories - shown.calories, curve: Self.countUpCurve,
                            duration: reduceMotion ? 0 : Self.countUpDuration)
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { self.shown = target }
        }
    }

    var body: some View {
        let target = target
        let figures = shown.flatMap { $0.day == target.day ? $0 : nil } ?? target
        VStack(alignment: .leading, spacing: 10) {
            CountingValue(value: figures.calories) { counted in
            VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The final total holds the width so "/ 2,100 cals" stays put while the digits count.
                ZStack(alignment: .leading) {
                    InkBoldText(calories.calorieText, font: Self.totalFont).hidden()
                    InkBoldText(counted.calorieText, font: Self.totalFont)
                }
                Text(calorieGoal.map { "/ \($0.calorieText) cals" } ?? "cals")
                    .font(.cave(.title3)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let calorieGoal {
                    Text(counted > calorieGoal
                         ? "\((counted - calorieGoal).calorieText) over"
                         : "\((calorieGoal - counted).calorieText) left")
                        .font(.cave(.title3))
                        .foregroundStyle(counted > calorieGoal ? Color.red : Color.primary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            // Pull the larger numeral into the font's spare top space to balance the card's bottom inset.
            .padding(.top, -UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 8))
            // Trim the big font's empty descender space so the bar sits just under the numbers.
            .padding(.bottom, (UIFont(name: "Schoolbell-Regular",
                                      size: UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 52))?.descender ?? 0) + 4)
            if let calorieGoal {
                SummaryBar(fraction: counted / calorieGoal)
            }
            }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(calorieGoal.map { "\(calories.calorieText) of \($0.calorieText) calories" } ?? "\(calories.calorieText) calories")
            .accessibilityValue(calorieGoal.map { "\((max(calories / $0, 0) * 100).calorieText) percent of goal" } ?? "")
            .accessibilityIdentifier("calorieSummary")
            if let macros {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(MacroKind.primary) { kind in
                        let total = macros.total(kind)
                        Button { openMacro?(kind) } label: {
                            CountingValue(value: figures.grams[kind] ?? total.grams ?? 0) { grams in
                                macroColumn(kind, total: total, shownGrams: grams, goal: macroGoals[keyPath: kind.keyPath])
                            }
                            .contentShape(Rectangle())
                        }
                        .hapticButtonStyle(.plain)
                        .disabled(openMacro == nil)
                        .accessibilityHint("Shows each food's \(kind.title.lowercased())")
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
        .onAppear(perform: showLatest)
        .onChange(of: target) { showLatest() }
        .onChange(of: isVisible) { showLatest() }
    }

    /// `shownGrams` is the counting amount; `total` keeps the real one for the unknown dash and accessibility.
    private func macroColumn(_ kind: MacroKind, total: MacroTotal, shownGrams: Double, goal: Double?) -> some View {
        let icon = glyph(kind).rawValue
        let iconSize = UIImage(named: icon)?.size ?? CGSize(width: 1, height: 1)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                // Height-only sizing keeps each icon's own width (the wheat is narrow). Only half of it
                // counts toward centering, so the name sits a little left and the icon hangs out.
                Image(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(height: 24).foregroundStyle(Color.caveOrange).accessibilityHidden(true)
                    .padding(.leading, -12 * iconSize.width / iconSize.height)
                // Closer to the 24-pt icons beside them.
                Text(kind.title.uppercased()).font(.cave(.subheadline).bold())
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ZStack {
                    Text(wholeGrams(total, grams: total.grams)).hidden()
                    Text(wholeGrams(total, grams: shownGrams))
                }
                .font(.cave(.title2).bold())
                if let goal, goal > 0 {
                    Text("/ \(goal.formatted(.number.precision(.fractionLength(0))))g")
                        .font(.cave(.caption)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            if let goal, goal > 0 {
                SummaryBar(fraction: (total.grams == nil ? 0 : shownGrams) / goal, height: 6, warnsWhenOver: false)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) \(total.text) g" + (goal.flatMap { $0 > 0 ? " of \($0.macroText) g" : nil } ?? ""))
        .accessibilityIdentifier("dailyMacro-\(kind.rawValue)")
    }

    private func wholeGrams(_ total: MacroTotal, grams: Double?) -> String {
        guard total.grams != nil, let grams else { return "—" }
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

/// Home's macro breakdown, opened from Protein, Carbs, or Fat: the day's foods with their grams, blank where a food
/// has no amount (that's what the "+" on Home means), each editable in place. A tapped box selects its value and
/// tints its row; an edit saves when the box loses focus or the sheet closes, and a typed amount isn't an estimate.
struct MacroBreakdownSheet: View {
    let day: Date
    let title: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [Cell: String] = [:]
    /// The box being typed in, kept past the focus change so closing the sheet still saves it.
    @State private var editing: Cell?
    /// What the focused box held when it was tapped: unchanged means nothing to save, and it can still be refreshed.
    @State private var focusStart: (cell: Cell, text: String)?
    @State private var message: String?
    /// "Also filled 3 other Banana entries."
    @State private var note: String?
    /// Foods waiting on an AI estimate (requests run one at a time through `AIBackend`'s gate).
    @State private var estimating: Set<UUID> = []
    @FocusState private var focused: Cell?

    struct Cell: Hashable { let entry: UUID; let kind: MacroKind }
    private static let columnWidth: CGFloat = 60, columnSpacing: CGFloat = 6
    private static var boxesWidth: CGFloat { columnWidth * 3 + columnSpacing * 2 }


    private var entries: [CalorieEntry] { store.dayEntries(day).sorted { $0.timestamp < $1.timestamp } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                // The estimate button and column labels stay put; only the foods scroll.
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !estimating.isEmpty || entries.contains(where: hasBlanks) { estimateAllButton }
                        header
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                    .background(Color.caveBackground)
                    .zIndex(1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if entries.isEmpty {
                            Text("Nothing logged on this day yet.").font(.cave(.subheadline)).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    row(entry, index: index).id(entry.id)
                                }
                            }
                            totals
                        }
                        if let message {
                            Text(message).font(.cave(.footnote)).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("macroBreakdownMessage")
                        }
                        if let note {
                            Text(note).font(.cave(.footnote)).foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("macroBreakdownNote")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                }
                .onChange(of: focused) { old, new in
                    if let old { commit(old) }
                    editing = new
                    focusStart = new.map { ($0, texts[$0] ?? "") }
                    guard let new else { return }
                    // Once the keyboard is up, bring the row being edited into view.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation { proxy.scrollTo(new.entry, anchor: .center) }
                    }
                }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { if let editing { commit(editing) }; dismiss() }
                        .hapticButtonStyle(.automatic).accessibilityIdentifier("macroBreakdownDone")
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear { if let editing { commit(editing) } }
    }

    /// Fills every blank box with AI estimates. Requests start together and finish one by one.
    private var estimateAllButton: some View {
        let busy = !estimating.isEmpty
        return Button { estimate(entries.filter(hasBlanks).map(\.id), scope: "all") } label: {
            // A solid orange button, a little tighter than usual.
            HStack(spacing: 6) {
                Text(busy ? "Estimating…" : "Estimate all missing values")
                if busy { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "sparkles") }
            }
            .font(.cave(.subheadline)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.caveOrange, in: Capsule())
            .opacity(busy ? 0.8 : 1)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Estimating" : "Estimate all missing values with AI")
        .accessibilityIdentifier("macroEstimateAll")
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Self.columnSpacing) {
            Spacer(minLength: 0)
            // Column labels with Home's glyphs; no column is highlighted.
            ForEach(MacroKind.primary) { kind in
                VStack(spacing: 2) {
                    CaveIcon(Self.glyph(kind), size: 22).foregroundStyle(Color.caveOrange)
                    Text(kind.title).font(.cave(.caption)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: Self.columnWidth, height: 44)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("macroBreakdownColumn-\(kind.rawValue)")
            }
        }
        .padding(.horizontal, 12)
    }

    private func row(_ entry: CalorieEntry, index: Int) -> some View {
        let active = editing?.entry == entry.id
        return VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: Self.columnSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                // Calories typed into search have no name; Home leaves them blank.
                Text(entry.foodDisplayName.isEmpty ? "Quick calories" : entry.foodDisplayName)
                    .font(.cave(.body)).lineLimit(2)
                    .foregroundStyle(entry.foodDisplayName.isEmpty ? Color.secondary : Color.primary)
                Text("\(entry.timestamp.formatted(date: .omitted, time: .shortened)) · \(entry.totalCalories.calorieText) cals")
                    .font(.cave(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(MacroKind.primary) { kind in cell(entry, kind: kind, index: index) }
        }
        if estimating.contains(entry.id) || hasBlanks(entry) { estimateButton(entry, index: index) }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(active ? Color.caveOrange.opacity(0.12) : Color.caveSurface, in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    /// Small, centered under the boxes: fills this food's blanks with an AI estimate from its name and calories.
    private func estimateButton(_ entry: CalorieEntry, index: Int) -> some View {
        let busy = estimating.contains(entry.id)
        return Button { estimate([entry.id], scope: "row") } label: {
            HStack(spacing: 4) {
                Text(busy ? "Estimating…" : "Estimate missing")
                if busy { ProgressView().controlSize(.mini).tint(Color.caveOrange) } else { Image(systemName: "sparkles") }
            }
            .font(.cave(.caption)).foregroundStyle(Color.caveOrange)
            .frame(width: Self.boxesWidth, height: 28).contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Estimating" : "Estimate missing values with AI")
        .accessibilityIdentifier("macroEstimate-\(index)")
    }

    private func cell(_ entry: CalorieEntry, kind: MacroKind, index: Int) -> some View {
        let cell = Cell(entry: entry.id, kind: kind)
        let identifier = "macroCell-\(kind.rawValue)-\(index)"
        return TextField("", text: Binding(get: { texts[cell] ?? "" }, set: { texts[cell] = Self.clean($0) }))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.cave(.body))
            .focused($focused, equals: cell)
            // A tap selects the whole value, so typing replaces it.
            .selectValueOnFocus(identifier: identifier)
            .accessibilityLabel("\(kind.title) grams, \(entry.foodDisplayName)")
            .accessibilityIdentifier(identifier)
            .frame(width: Self.columnWidth, height: 40)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                // Only the box being typed in is outlined.
                RoundedRectangle(cornerRadius: 10).strokeBorder(focused == cell ? Color.caveOrange : .clear, lineWidth: 2)
            }
            .keyboardInputArea { focused = cell }
    }

    /// Follows the boxes as they're typed in, before anything is saved.
    private var totals: some View {
        HStack(spacing: Self.columnSpacing) {
            Text("Total").font(.cave(.headline)).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(MacroKind.primary) { kind in
                let known = entries.compactMap { typedAmount($0, kind) }
                Text(known.isEmpty ? "" : known.reduce(0, +).macroText + (known.count < entries.count ? "+" : ""))
                    .font(.cave(.headline)).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: Self.columnWidth)
                    .accessibilityIdentifier("macroBreakdownTotal-\(kind.rawValue)")
            }
        }
        .padding(.horizontal, 12).padding(.top, 4)
    }

    /// Grams for the whole entry (per serving × servings), or nil when unknown.
    private func amount(_ entry: CalorieEntry, _ kind: MacroKind) -> Double? {
        MacroNutrients.decode(entry.macrosPerServingData)?[keyPath: kind.keyPath].map { $0 * entry.servings }
    }

    /// What its box shows now (typed, maybe not saved yet), falling back to the saved amount before loading.
    private func typedAmount(_ entry: CalorieEntry, _ kind: MacroKind) -> Double? {
        guard let text = texts[Cell(entry: entry.id, kind: kind)] else { return amount(entry, kind) }
        return Self.parse(text)
    }

    private func hasBlanks(_ entry: CalorieEntry) -> Bool {
        MacroKind.primary.contains { typedAmount(entry, $0) == nil }
    }

    /// Asks for estimates for these foods and fills only their blanks; amounts already there (or typed meanwhile) stay.
    private func estimate(_ ids: [UUID], scope: String) {
        let ids = ids.filter { !estimating.contains($0) }
        guard !ids.isEmpty else { return }
        // Save what's being typed first, so it isn't treated as blank.
        if let editing { commit(editing) }
        focused = nil
        message = nil
        estimating.formUnion(ids)
        UsageStats.shared.event("macros.estimate", ["scope": scope, "foods": String(ids.count)])
        for id in ids {
            Task { @MainActor in
                defer { estimating.remove(id) }
                guard let entry = store.entries.first(where: { $0.id == id }) else { return }
                let snapshot = EntryDraft(entry)
                do {
                    let estimate = try await AIBackend.shared.estimateMacros(for: snapshot)
                    fill(id, with: estimate, from: snapshot)
                } catch is CancellationError {
                } catch {
                    message = error.localizedDescription
                    UsageStats.shared.error(.macroEstimate, error)
                }
            }
        }
    }

    private func fill(_ id: UUID, with estimate: MacroNutrients, from snapshot: EntryDraft) {
        guard let entry = store.entries.first(where: { $0.id == id }) else { return }
        var draft = EntryDraft(entry)
        let name = entry.foodDisplayName.isEmpty ? "this food" : entry.foodDisplayName
        // The food may have been edited while the request ran.
        guard draft.name == snapshot.name, draft.calories == snapshot.calories, draft.servings == snapshot.servings else {
            message = "\(name) changed while estimating. Try again."; return
        }
        let totals = (draft.totalMacros ?? MacroNutrients()).fillingMissing(from: estimate)
        guard totals.isValid else { message = "The estimate for \(name) conflicts with its carbs or fiber."; return }
        guard totals != draft.totalMacros else {
            if !estimate.hasValues { message = "Couldn’t estimate \(name). Try a more specific name." }
            return
        }
        draft.macrosPerServing = totals.scaled(1 / max(draft.servings, 0.0001))
        let before = EntryDraft(entry).totalMacros
        guard store.update(draft) else { message = store.error ?? "Couldn’t save the estimate. Try again."; return }
        share(from: entry, previous: before)
    }

    /// The same food on other days gets these macros too (blanks and estimates only); boxes refresh to match.
    private func share(from entry: CalorieEntry, previous: MacroNutrients?) {
        let others = store.shareMacros(from: entry, previous: previous)
        if others > 0 {
            let name = entry.foodDisplayName.isEmpty ? "this food" : entry.foodDisplayName
            note = "Also filled \(others) other \(name) \(others == 1 ? "entry" : "entries")."
        }
        for entry in entries {
            for kind in MacroKind.primary {
                let cell = Cell(entry: entry.id, kind: kind)
                let text = Self.text(amount(entry, kind))
                if focused != cell || focusStart?.cell != cell {
                    texts[cell] = text
                } else if texts[cell] == focusStart?.text {
                    // Focused but not typed in yet: show the shared value and treat it as the starting point.
                    texts[cell] = text
                    focusStart = (cell, text)
                }
            }
        }
    }

    private func load() {
        for entry in entries {
            for kind in MacroKind.primary {
                let cell = Cell(entry: entry.id, kind: kind)
                if texts[cell] == nil { texts[cell] = Self.text(amount(entry, kind)) }
            }
        }
    }

    /// Saves a box's grams as that food's amount, spread back over its servings. An emptied box clears it.
    private func commit(_ cell: Cell) {
        guard let entry = store.entries.first(where: { $0.id == cell.entry }) else { return }
        let stored = amount(entry, cell.kind)
        let typed = texts[cell] ?? ""
        // Untouched since it was tapped (it may have been filled from another entry meanwhile).
        if let focusStart, focusStart.cell == cell, focusStart.text == typed { return }
        guard typed != Self.text(stored) else { return }
        let grams: Double?
        if typed.isEmpty { grams = nil }
        else {
            guard let parsed = Self.parse(typed), parsed.isFinite, parsed >= 0, parsed <= 10_000 else {
                texts[cell] = Self.text(stored); message = "Enter grams from 0 to 10,000."; return
            }
            grams = parsed
        }
        var draft = EntryDraft(entry)
        var macros = draft.macrosPerServing ?? MacroNutrients()
        macros[keyPath: cell.kind.keyPath] = grams.map { $0 / max(entry.servings, 0.0001) }
        // Typed by hand, so no longer an estimate.
        macros[keyPath: cell.kind.estimateKeyPath] = nil
        guard macros.isValid else {
            texts[cell] = Self.text(stored)
            message = "Carbs can’t be less than this food’s fiber. Edit the food to change its fiber."
            return
        }
        draft.macrosPerServing = macros.hasValues ? macros : nil
        let before = EntryDraft(entry).totalMacros
        if store.update(draft) {
            message = nil
            texts[cell] = Self.text(amount(entry, cell.kind))
            share(from: entry, previous: before)
        } else {
            texts[cell] = Self.text(stored)
            message = store.error ?? "Couldn’t save that amount. Try again."
        }
    }

    private static func text(_ grams: Double?) -> String { grams?.macroText ?? "" }
    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
    }
    /// Digits and one decimal mark, at most one decimal place.
    private static func clean(_ text: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        var result = "", seenSeparator = false, decimals = 0
        for character in text {
            if character.isNumber {
                if seenSeparator { guard decimals < 1 else { continue }; decimals += 1 }
                result.append(character)
            } else if String(character) == separator || character == ".", !seenSeparator {
                seenSeparator = true; result += separator
            }
        }
        return String(result.prefix(7))
    }
    private static func glyph(_ kind: MacroKind) -> CaveGlyph {
        switch kind { case .protein: .protein; case .totalCarbs: .carbs; default: .fat }
    }
}
