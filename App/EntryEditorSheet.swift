import SwiftUI

struct EntryEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: EntryDraft
    var onSaveComponent: ((EntryDraft) -> Void)? = nil
    @State private var details = false
    @FocusState private var caloriesFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CALORIES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("0", value: Binding(get: { draft.calories }, set: { draft.changeCalories($0) }), format: .number.precision(.fractionLength(0...2)))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).keyboardType(.decimalPad).focused($caloriesFocused)
                            .accessibilityIdentifier("entryCalories").accessibilityLabel("Calories")
                    }.padding(.vertical, 10)
                    TextField("Name (optional)", text: $draft.name).accessibilityIdentifier("entryName")
                }
                Section {
                    DisclosureGroup("More Details", isExpanded: $details) {
                        ServingControl(value: Binding(get: { draft.servings }, set: { draft.changeServings($0) }))
                        HStack {
                            Text("Calories per serving")
                            Spacer()
                            TextField("0", value: Binding(get: { draft.perServing }, set: { draft.changePerServing($0) }), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110).accessibilityIdentifier("caloriesPerServing")
                        }
                        TextField("Serving description (e.g. 1 cup)", text: $draft.servingDescription).accessibilityLabel("Serving description")
                        if onSaveComponent == nil {
                            DatePicker("Date and time", selection: $draft.timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        }
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
            .navigationTitle(onSaveComponent != nil ? "Meal item" : draft.entryID == nil ? "Add calories" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.entryID == nil ? "Add" : "Save Changes") { save() }.fontWeight(.semibold).disabled(!draft.isValid).accessibilityIdentifier("saveEntry")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { caloriesFocused = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func save() {
        if draft.perServing == 0, draft.calories > 0 { draft.perServing = draft.calories / draft.servings }
        if let onSaveComponent { onSaveComponent(draft); dismiss() }
        else if draft.entryID != nil { if store.update(draft) { dismiss() } }
        else if store.add([draft]) { dismiss() }
    }
}

struct ServingControl: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var value: Double
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading) { Text("Servings"); controls }
        } else {
            HStack { Text("Servings"); Spacer(); controls }
        }
    }
    private var controls: some View {
        HStack {
            Button { value = max(0.5, value - 0.5) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.buttonStyle(.borderless).disabled(value <= 0.5).accessibilityLabel("Decrease servings")
            TextField("1", value: $value, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 62).accessibilityIdentifier("servingCount").accessibilityLabel("Number of servings")
            Button { value += 0.5 } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Increase servings")
        }
    }
}
