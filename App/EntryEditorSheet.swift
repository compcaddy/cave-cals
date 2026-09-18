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
    @FocusState private var nameFocused: Bool
    @FocusState private var servingSizeFocused: Bool
    @FocusState private var perServingFocused: Bool
    @State private var showingTime = false
    @State private var saveAsCommonDefault = false
    @State private var pinOnQuickAdd = false
    @ScaledMetric(relativeTo: .largeTitle) private var calorieFieldHeight = 54
    private let servingSizes = ["1 serving", "1 piece", "1 cup", "1/2 cup", "1 tbsp", "1 tsp", "1 oz", "100 g"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CALORIES").font(.cave(.caption).weight(.semibold)).foregroundStyle(.secondary)
                        CalorieAmountField(value: Binding(get: { draft.calories }, set: { draft.changeCalories($0) }), focusOnOpen: focusCaloriesOnOpen, blankOnOpen: blankCaloriesOnOpen)
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
                                }.buttonStyle(.borderless).accessibilityLabel("Use name \(name)")
                            }
                        }
                    }
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
                                        }.buttonStyle(.borderless)
                                    }
                                }
                            }.frame(height: 176).padding(.top, 8)
                        }
                        }
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
                                }.buttonStyle(.plain).accessibilityLabel("Time").accessibilityValue(draft.timestamp.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        if let food = changedCommonFood, onSaveComponent == nil {
                            Toggle("Save as default for '\(food.name)'", isOn: $saveAsCommonDefault)
                                .font(.cave(.subheadline))
                                .accessibilityIdentifier("saveCommonFoodDefault")
                        }
                    }.editorRowInsets()
                }
                if pinFoodID != nil, onSaveComponent == nil {
                    Section {
                        Toggle("Pin on Quick Add", isOn: $pinOnQuickAdd)
                            .font(.cave(.subheadline))
                            .accessibilityIdentifier("pinOnQuickAdd")
                    }
                }
                if draft.entryID != nil, onSaveComponent == nil {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            if let entry = store.entries.first(where: { $0.id == draft.entryID }) { store.delete(entry) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(onSaveComponent != nil ? "Meal item" : draft.entryID == nil ? "Add Calories" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTime) {
                NavigationStack {
                    DatePicker("Time", selection: timeOfDay, in: ...Date(), displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.wheel).labelsHidden().padding(.horizontal)
                        .navigationTitle("Time").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTime = false } } }
                }.presentationDetents([.height(300)]).presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel { onCancel() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label(draft.entryID == nil ? "Add" : "Save Changes", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .fontWeight(.semibold).disabled(!draft.isValid)
                    .accessibilityIdentifier("saveEntry")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { nameFocused = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
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
                draft.timestamp = updated
            }
        })
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
            let saved = draft.entryID != nil ? store.update(draft) : store.add([draft])
            if saved {
                if let foodToUpdate { store.saveCommonDefault(draft, for: foodToUpdate) }
                if let pinFoodID {
                    let replacementID = FoodHistory.identifier(for: draft) ?? pinFoodID
                    store.updatePin(originalID: pinFoodID, replacementID: replacementID, pinned: pinOnQuickAdd)
                }
                dismiss()
            }
        }
    }
}

private extension View {
    func selectValueOnFocus(identifier: String) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            guard let field = notification.object as? UITextField,
                  field.accessibilityIdentifier == identifier else { return }
            DispatchQueue.main.async {
                guard field.isFirstResponder else { return }
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }
    }
    func selectValueOnTap(focus: FocusState<Bool>.Binding) -> some View {
        contentShape(Rectangle())
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
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, initiallyBlank: blankOnOpen) }
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
        let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 0
            return formatter
        }()
        init(value: Binding<Double>, initiallyBlank: Bool) {
            self.value = value
            self.initiallyBlank = initiallyBlank
        }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            string.allSatisfy { $0.isWholeNumber }
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                guard textField.isFirstResponder else { return }
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
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
                        }.buttonStyle(.borderless).accessibilityLabel("Use \(preset.formatted()) servings")
                    }
                }
            }.frame(height: 176).padding(.top, 8)
        }
        }
    }
    private var controls: some View {
        TextField("1", value: $value, format: .number.precision(.fractionLength(0...3)))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
            .focused($editing).accessibilityIdentifier("servingCount").accessibilityLabel("Number of servings")
            .selectValueOnFocus(identifier: "servingCount")
    }
}
