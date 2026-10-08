import SwiftUI

struct EntryEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: EntryDraft
    var onSaveComponent: ((EntryDraft) -> Void)? = nil
    var focusNameOnOpen = false
    var focusCaloriesOnOpen = false
    var blankCaloriesOnOpen = false
    var onCancel: (() -> Void)? = nil
    var pinFoodID: String? = nil
    /// Opened by a one-tap add while adding asks for a meal: everything else is filled in, so the meal
    /// choice shows and scrolls into view without bringing up the keyboard.
    var choosesMeal = false
    /// How the food is being logged, for the stats, when its source doesn't say (copies).
    var method: LogMethod? = nil
    @FocusState private var nameFocused: Bool
    @FocusState private var servingSizeFocused: Bool
    @FocusState private var perServingFocused: Bool
    @State private var showingTime = false
    @State private var saveAsCommonDefault = false
    @State private var pinOnQuickAdd = false
    /// Nil until someone taps the meal row; until then it follows `mealStartsExpanded`.
    @State private var mealExpanded: Bool?
    private static let mealRowID = "mealTypeRow"
    @ScaledMetric(relativeTo: .largeTitle) private var calorieFieldHeight = 54
    private let servingSizes = ["1 serving", "1 piece", "1 cup", "1/2 cup", "1 tbsp", "1 tsp", "1 oz", "100 g"]
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            HapticForm {
                Section {
                    Group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CALORIES").font(.cave(.caption).weight(.semibold)).foregroundStyle(.secondary)
                        CalorieAmountField(value: Binding(get: { draft.calories }, set: { draft.changeCalories($0) }), focusOnOpen: focusCaloriesOnOpen, blankOnOpen: blankCaloriesOnOpen,
                                           selectOnOpen: draft.entryID != nil)
                            .frame(height: calorieFieldHeight)
                    }.padding(.top, 10)
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Name (optional)", text: $draft.name).focused($nameFocused)
                            .autocorrectionDisabled().accessibilityIdentifier("entryName")
                        if nameFocused, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ForEach(nameSuggestions, id: \.self) { name in
                                Button {
                                    draft.name = name
                                    nameFocused = false
                                } label: {
                                    HStack {
                                        Text(name).foregroundStyle(.primary)
                                        Spacer()
                                        CaveIcon(.arrowUpLeft, size: 22).foregroundStyle(.secondary)
                                    }.padding(.vertical, 12)
                                }.hapticButtonStyle(.borderless).accessibilityLabel("Use name \(name)")
                            }
                        }
                    }.keyboardInputArea()
                    }.editorRowInsets()
                }
                Section {
                    Group {
                        VStack(spacing: 0) {
                        HStack {
                            Text("serving size").font(.cave(.subheadline)).opacity(0.65)
                            Spacer(minLength: 16)
                            TextField("e.g. 1 cup", text: $draft.servingDescription)
                                .focused($servingSizeFocused)
                                .multilineTextAlignment(.trailing).accessibilityLabel("Serving size").accessibilityIdentifier("servingSize")
                                .selectValueOnFocus(identifier: "servingSize")
                        }
                        .selectValueOnTap(focus: $servingSizeFocused)
                        if servingSizeFocused, draft.servingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(servingSizes, id: \.self) { size in
                                        Button {
                                            draft.servingDescription = size
                                            servingSizeFocused = false
                                        } label: {
                                            Text(size).frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 44)
                                        }.hapticButtonStyle(.borderless)
                                    }
                                }
                            }.frame(height: 176).padding(.top, 8)
                        }
                        }.keyboardInputArea()
                        HStack {
                            Text("cals / serving").font(.cave(.subheadline)).opacity(0.65)
                            Spacer()
                            TextField("0", value: Binding(get: { draft.perServing.rounded() }, set: { draft.changePerServing($0) }), format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 110).accessibilityIdentifier("caloriesPerServing")
                                .focused($perServingFocused)
                                .selectValueOnFocus(identifier: "caloriesPerServing")
                        }
                        .selectValueOnTap(focus: $perServingFocused)
                        ServingControl(value: Binding(get: { draft.servings }, set: { draft.changeServings($0) }))
                        if showsMeal { mealRow.id(Self.mealRowID) }
                        if onSaveComponent == nil {
                            HStack {
                                Text("time").font(.cave(.subheadline)).opacity(0.65)
                                Spacer()
                                Button {
                                    nameFocused = false; servingSizeFocused = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    showingTime = true
                                } label: {
                                    Text(draft.timestamp, format: .dateTime.hour().minute())
                                        .foregroundStyle(.primary).frame(minHeight: 32)
                                }.hapticButtonStyle(.plain).accessibilityLabel("Time").accessibilityValue(draft.timestamp.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        if let food = changedCommonFood, onSaveComponent == nil {
                            Toggle("Save as default for '\(food.name)'", isOn: $saveAsCommonDefault)
                                .font(.cave(.subheadline))
                                .accessibilityIdentifier("saveCommonFoodDefault")
                        }
                    }.editorRowInsets()
                }
                if store.tracksMacros { MacroEditorSection(draft: $draft) }
                if pinFoodID != nil, onSaveComponent == nil {
                    Section {
                        Toggle("Pin on Quick Add", isOn: $pinOnQuickAdd)
                            .font(.cave(.subheadline))
                            .accessibilityIdentifier("pinOnQuickAdd")
                    }
                }
                if draft.externalID?.hasPrefix("fatsecret:") == true {
                    Section { FatSecretAttribution() }
                }
                if draft.entryID != nil, onSaveComponent == nil {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            if let entry = store.entries.first(where: { $0.id == draft.entryID }) { store.delete(entry) }
                            dismiss()
                        }
                    }
                }
            }.caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .task {
                guard choosesMeal, showsMeal else { return }
                // Once laid out, and while the sheet is still sliding up, scroll only as far as it takes to show
                // the meal choice (not at all on a tall screen), so nothing moves under a finger reaching for it.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(Self.mealRowID)
            }
            }
            .navigationTitle(onSaveComponent != nil ? "Meal item" : draft.entryID == nil ? "Add Calories" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTime) {
                NavigationStack {
                    DatePicker("Time", selection: timeOfDay, in: ...Date(), displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.wheel).labelsHidden().padding(.horizontal)
                        .navigationTitle("Time").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTime = false }.hapticButtonStyle(.automatic) } }
                }.presentationDetents([.height(300)]).presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel { onCancel() } else { dismiss() }
                    }.hapticButtonStyle(.automatic)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label(draft.entryID == nil ? "Add" : "Save Changes", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                    }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange).hapticFeel(.success)
                    .fontWeight(.semibold).disabled(!draft.isValid)
                    .accessibilityIdentifier("saveEntry")
                }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .onChange(of: changedCommonFood?.id) { _, _ in saveAsCommonDefault = false }
            .task {
                if let pinFoodID { pinOnQuickAdd = store.isPinned(pinFoodID) }
                guard focusNameOnOpen else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                nameFocused = true
            }
    }
    private var timeOfDay: Binding<Date> {
        Binding(get: { draft.timestamp }, set: { value in
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: value)
            if let updated = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: draft.timestamp),
               calendar.isDate(updated, inSameDayAs: draft.timestamp), updated <= Date() {
                let before = draft.timestamp
                draft.timestamp = updated
                followMealTime(from: before)
            }
        })
    }
    /// Meal types show for logged food being edited (so it can move), and for new food while adding asks
    /// for a meal. Set by time of day, new food gets its meal when it's added, so adding looks as it always did.
    private var showsMeal: Bool {
        let settings = store.mealSettings
        guard settings.tracks, onSaveComponent == nil else { return false }
        return draft.entryID != nil || settings.asks
    }
    private var mealStartsExpanded: Bool { draft.entryID == nil }
    private var mealRow: some View {
        let settings = store.mealSettings
        let expanded = mealExpanded ?? mealStartsExpanded
        let current = settings.type(id: draft.mealType)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { mealExpanded = !expanded }
            } label: {
                HStack(spacing: 8) {
                    Text("meal type").font(.cave(.subheadline)).opacity(0.65)
                    Spacer(minLength: 16)
                    Text(current?.name ?? (draft.entryID == nil ? "Choose" : "None"))
                        .foregroundStyle(current == nil && draft.entryID == nil ? Color.caveOrange : Color.primary)
                    CaveIcon(.chevronRight, size: 13).foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(minHeight: 32).contentShape(Rectangle())
            }
            .hapticButtonStyle(.plain)
            .accessibilityLabel("Meal type")
            .accessibilityValue(current?.name ?? "None")
            .accessibilityHint(expanded ? "Hides the meal choices" : "Shows the meal choices")
            .accessibilityIdentifier("mealTypeRow")
            if expanded {
                MealTypePicker(types: settings.visibleTypes, selection: $draft.mealType, allowsNone: draft.entryID != nil)
                    .padding(.top, 8)
            }
        }
    }
    /// Editing logged food's time, set by time of day: a meal that matched the old time follows to the new one.
    private func followMealTime(from before: Date) {
        let settings = store.mealSettings
        guard settings.tracks, settings.byTime, draft.entryID != nil,
              draft.mealType == settings.meal(at: before) else { return }
        draft.mealType = settings.meal(at: draft.timestamp)
    }
    private var nameSuggestions: [String] {
        var seen = Set<String>()
        return FoodHistory.search(draft.name, entries: store.entries).compactMap { food in
            let name = food.draft.name
            return seen.insert(normalizedFoodName(name)).inserted ? name : nil
        }.prefix(5).map { $0 }
    }
    private var changedCommonFood: CommonFood? {
        guard let food = CommonFoods.matching(draft.name),
              CommonFoodDefault(draft) != store.commonDefault(for: food) else { return nil }
        return food
    }
    private func save() {
        if draft.perServing == 0, draft.calories > 0 { draft.perServing = (draft.calories / draft.servings).rounded() }
        if let onSaveComponent { onSaveComponent(draft); dismiss() }
        else {
            let foodToUpdate = saveAsCommonDefault ? changedCommonFood : nil
            let original = draft.entryID.flatMap { id in store.entries.first { $0.id == id } }
            let macrosBefore = original.flatMap { MacroNutrients.decode($0.macrosPerServingData) }
            let totalsBefore = original.flatMap { entry in macrosBefore?.scaled(entry.servings) }
            let saved = draft.entryID != nil ? store.update(draft) : store.add([draft], method: method)
            if saved {
                if let foodToUpdate { store.saveCommonDefault(draft, for: foodToUpdate) }
                // New macros on a logged food fill the same food's blanks on other days too.
                if let original, draft.macrosPerServing != macrosBefore { store.shareMacros(from: original, previous: totalsBefore) }
                if let pinFoodID {
                    let replacementID = FoodHistory.identifier(for: draft) ?? pinFoodID
                    store.updatePin(originalID: pinFoodID, replacementID: replacementID, pinned: pinOnQuickAdd)
                }
                dismiss()
            }
        }
    }
}

extension View {
    /// Selects the field's whole value when editing begins, so typing replaces it. Apply it to the TextField itself.
    func selectValueOnFocus(identifier: String) -> some View {
        background(SelectValueOnFocusAnchor(identifier: identifier))
    }
    func selectValueOnTap(focus: FocusState<Bool>.Binding) -> some View {
        keyboardInputArea()
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                focus.wrappedValue = true
                // Wait for SwiftUI to focus the field and finish placing the insertion point.
                DispatchQueue.main.async {
                    guard focus.wrappedValue else { return }
                    UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                }
            })
    }
    func editorRowInsets() -> some View {
        self.listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
    }
}

private struct CalorieAmountField: UIViewRepresentable {
    @Binding var value: Double
    let focusOnOpen: Bool
    let blankOnOpen: Bool
    /// Editing a logged entry opens with the amount selected so typing replaces it.
    var selectOnOpen = false
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, initiallyBlank: blankOnOpen, selectOnFirstFocus: selectOnOpen && focusOnOpen) }
    func makeUIView(context: Context) -> AmountTextField {
        let field = AmountTextField()
        field.focusOnOpen = focusOnOpen
        field.keyboardType = .numberPad
        field.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(name: "Schoolbell-Regular", size: 44) ?? .systemFont(ofSize: 44))
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = blankOnOpen ? nil : "0"
        field.accessibilityIdentifier = "entryCalories"
        field.accessibilityLabel = "Calories"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: AmountTextField, context: Context) {
        context.coordinator.value = $value
        if !field.isFirstResponder {
            field.text = context.coordinator.initiallyBlank && value == 0
                ? "" : context.coordinator.formatter.string(from: NSNumber(value: value.rounded()))
        }
    }
    final class AmountTextField: UITextField {
        var focusOnOpen = false
        private var focusedInitially = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, focusOnOpen, !focusedInitially else { return }
            focusedInitially = true
            DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
        }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>
        var initiallyBlank: Bool
        var selectOnFirstFocus: Bool
        let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 0
            return formatter
        }()
        init(value: Binding<Double>, initiallyBlank: Bool, selectOnFirstFocus: Bool) {
            self.value = value
            self.initiallyBlank = initiallyBlank
            self.selectOnFirstFocus = selectOnFirstFocus
        }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            string.allSatisfy { $0.isWholeNumber }
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            let selectAll = selectOnFirstFocus
            selectOnFirstFocus = false
            DispatchQueue.main.async {
                guard textField.isFirstResponder else { return }
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: selectAll ? textField.beginningOfDocument : end, to: end)
            }
        }
        @objc func changed(_ field: UITextField) {
            initiallyBlank = false
            let text = field.text ?? ""
            value.wrappedValue = text.isEmpty ? 0 : (formatter.number(from: text)?.doubleValue ?? .nan)
        }
    }
}

struct ServingControl: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var value: Double
    @FocusState private var editing: Bool
    private let presets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4, 5]
    var body: some View {
        VStack(spacing: 0) {
        Group {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading) { Text("# of servings").font(.cave(.subheadline)).opacity(0.65); controls }
        } else {
            HStack { Text("# of servings").font(.cave(.subheadline)).opacity(0.65); Spacer(); controls }
        }
        }.selectValueOnTap(focus: $editing)
        if editing {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            value = preset
                            editing = false
                        } label: {
                            Text(preset.formatted(.number.precision(.fractionLength(0...2))))
                                .frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 44)
                        }.hapticButtonStyle(.borderless).accessibilityLabel("Use \(preset.formatted()) servings")
                    }
                }
            }.caveScreenBackground().frame(height: 176).padding(.top, 8)
        }
        // The presets belong to the servings field.
        }.keyboardInputArea()
    }
    private var controls: some View {
        TextField("1", value: $value, format: .number.precision(.fractionLength(0...3)))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
            .focused($editing).accessibilityIdentifier("servingCount").accessibilityLabel("Number of servings")
            .selectValueOnFocus(identifier: "servingCount")
    }
}

/// Sits behind a text field and selects its value when editing begins. It finds the field by its identifier or,
/// failing that, by the field sitting right over it: SwiftUI hands accessibility identifiers to UIKit only while an
/// accessibility client is running (as in UI tests), so on an iPhone without one the identifier alone never matched.
private struct SelectValueOnFocusAnchor: UIViewRepresentable {
    let identifier: String
    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.identifier = identifier
        return view
    }
    func updateUIView(_ view: AnchorView, context: Context) { view.identifier = identifier }

    final class AnchorView: UIView {
        var identifier = ""
        private var observer: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
                return
            }
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification,
                                                              object: nil, queue: .main) { [weak self] notification in
                guard let field = notification.object as? UITextField else { return }
                MainActor.assumeIsolated { self?.beganEditing(field) }
            }
        }

        private func beganEditing(_ field: UITextField) {
            guard let window, field.window === window else { return }
            let mine = convert(bounds, to: nil).insetBy(dx: -2, dy: -2)
            let theirs = field.convert(field.bounds, to: nil)
            guard field.accessibilityIdentifier == identifier || mine.contains(CGPoint(x: theirs.midX, y: theirs.midY)) else { return }
            let original = field.text
            let selectAll = {
                // Only while nothing has been typed yet, so a fast typist's digits are never selected.
                guard field.isFirstResponder, field.text == original else { return }
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
            DispatchQueue.main.async(execute: selectAll)
            // A tap right on the digits places the insertion point after editing begins, undoing the first
            // selection, so select again once that tap has finished.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: selectAll)
        }
    }
}
