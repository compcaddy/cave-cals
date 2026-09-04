import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adjustingGoal = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Adjust Daily Calorie Goal") { adjustingGoal = true }
                        .accessibilityIdentifier("adjustGoal")
                }
                Section("Saved Meals") { NavigationLink { MealsView() } label: { Label("Meals", systemImage: "square.stack.3d.up") } }
                Section("iCloud") {
                    Label(store.syncStatus, systemImage: store.cloudEnabled ? "icloud" : "iphone")
                    Text("Your entries are saved on this iPhone. With iCloud enabled, they also sync to your other iPhones using the same Apple Account.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    Text("Easiest Calorie Counter · 1.0")
                    Link("Food data by Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("Open Database License (ODbL)", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Text("Search terms and scanned barcodes are sent to Open Food Facts to find products. Your profile and food diary stay on your devices and in your private iCloud account. Product serving sizes and calories can vary; you can edit them before adding.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $adjustingGoal) {
                SetupView(goal: store.profile?.dailyGoal, isAdjustingGoal: true)
            }
            .task { await store.checkCloud() }
        }
    }
}

struct MealRoute: Identifiable {
    let id = UUID()
    var meal: SavedMeal?
    var fromToday = false
}

struct MealsView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: MealRoute?
    @State private var adding: SavedMeal?
    var body: some View {
        List {
            Section {
                Button("Create from Today’s Entries") { editor = MealRoute(fromToday: true) }.disabled(store.dayEntries(Date()).isEmpty)
                Button("Create from Scratch") { editor = MealRoute() }
            }
            Section("Your meals") {
                if store.meals.isEmpty { Text("Save foods you often eat together.").foregroundStyle(.secondary) }
                ForEach(store.meals) { meal in
                    FoodRow(name: meal.name, calories: meal.calories, meal: true, add: { adding = meal }, edit: { editor = MealRoute(meal: meal) })
                        .swipeActions { Button("Delete", role: .destructive) { store.context.delete(meal); store.commit() } }
                }
            }
        }.navigationTitle("Meals").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { route in MealEditorSheet(route: route) }
            .sheet(item: $adding) { meal in MealAddSheet(mealID: meal.id, date: Date()) }
    }
}

struct MealEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let route: MealRoute
    @State private var name = ""
    @State private var items: [EntryDraft] = []
    @State private var selection = Set<UUID>()
    @State private var component: EntryDraft?
    @State private var showFoodPicker = false
    @State private var initialized = false
    var body: some View {
        NavigationStack {
            List {
                Section("Meal name") { TextField("My Breakfast", text: $name).accessibilityIdentifier("mealName") }
                if route.fromToday {
                    Section("Choose today’s entries") {
                        ForEach(store.dayEntries(Date())) { entry in
                            Button {
                                if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    Text(entry.name.isEmpty ? "\(entry.totalCalories.calorieText) calories" : entry.name).foregroundStyle(.primary)
                                    Spacer(); Text(entry.totalCalories.calorieText).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }.accessibilityLabel("Select \(entry.name.isEmpty ? entry.totalCalories.calorieText + " calories" : entry.name)")
                                .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
                        }
                    }
                } else {
                    Section("Foods") {
                        ForEach(items) { item in
                            Button { component = item } label: {
                                HStack { Text(item.name.isEmpty ? "Unnamed food" : item.name); Spacer(); Text("\(item.calories.calorieText) cal").foregroundStyle(.secondary) }
                            }.foregroundStyle(.primary)
                        }.onDelete { items.remove(atOffsets: $0) }
                        Button { showFoodPicker = true } label: { Label("Add food", systemImage: "plus") }
                    }
                }
                Section { HStack { Text("Total"); Spacer(); Text("\(chosenItems.reduce(0) { $0 + $1.calories }.calorieText) cal").fontWeight(.semibold) } }
            }
            .navigationTitle(route.meal == nil ? "New Meal" : "Edit Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Meal") { if store.saveMeal(route.meal, name: name, items: chosenItems) { dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chosenItems.isEmpty)
                }
            }
            .onAppear {
                if !initialized { name = route.meal?.name ?? ""; items = route.meal?.items ?? []; initialized = true }
            }
            .sheet(item: $component) { draft in
                EntryEditorSheet(draft: draft) { updated in
                    if let index = items.firstIndex(where: { $0.id == updated.id }) { items[index] = updated }
                    else { items.append(updated) }
                }
            }
            .sheet(isPresented: $showFoodPicker) { MealFoodPicker { items.append($0) } }
        }
    }
    private var chosenItems: [EntryDraft] {
        route.fromToday ? store.dayEntries(Date()).filter { selection.contains($0.id) }.map { EntryDraft($0) } : items
    }
}

struct MealFoodPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var selected: (EntryDraft) -> Void
    @State private var query = ""
    @State private var search = FoodSearchState()
    @State private var editor: EntryDraft?
    var body: some View {
        NavigationStack {
            List {
                Button("Create manual item") { editor = EntryDraft(name: Double(query) == nil ? query : "", calories: Double(query) ?? 0) }
                Section("Your foods") {
                    ForEach(FoodHistory.search(query, entries: store.entries)) { food in row(food.draft) }
                }
                Section("Food search") {
                    ForEach(search.results) { food in row(food.draft) }
                    if search.loading { ProgressView("Searching foods…") }
                    if let message = search.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $query, prompt: "Search food or enter calories")
            .navigationTitle("Add food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) { await search.search(query) }
            .sheet(item: $editor) { draft in EntryEditorSheet(draft: draft) { selected($0); dismiss() } }
        }
    }
    private func row(_ draft: EntryDraft) -> some View {
        FoodRow(name: draft.name, calories: draft.calories, add: { var copy = draft; copy.id = UUID(); copy.entryID = nil; selected(copy); dismiss() }, edit: { var copy = draft; copy.id = UUID(); copy.entryID = nil; editor = copy })
    }
}

struct MealAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealID: UUID
    let date: Date
    @State private var factor: Double = 1
    private var meal: SavedMeal? { store.meals.first { $0.id == mealID } }
    var body: some View {
        NavigationStack {
            Form {
                if let meal {
                    Section { ServingControl(value: $factor) }
                    Section("Foods") {
                        ForEach(meal.items) { item in
                            HStack { Text(item.name.isEmpty ? "Unnamed food" : item.name); Spacer(); Text("\((item.calories * factor).calorieText) cal") }
                        }
                    }
                    Section { HStack { Text("Total"); Spacer(); Text("\((meal.calories * factor).calorieText) cal").bold() } }
                }
            }
            .navigationTitle(meal?.name ?? "Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Meal") { if let meal, store.addMeal(meal, factor: factor, date: date) { dismiss() } }.disabled(factor <= 0 || !factor.isFinite || meal == nil)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
