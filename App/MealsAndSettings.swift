import SwiftUI

struct SettingsView: View {
    @State private var aiSubscriptions = AISubscriptions()
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adjustingGoal = false
    @State private var planningCalories = false
    @State private var showingPaywall = false
    @State private var weightEditor: WeightEditorRoute?
    @Environment(WeightStore.self) private var weights

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { adjustingGoal = true } label: {
                        HStack(spacing: 12) {
                            Text("Daily calorie goal").foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            CaveIcon(.pencil, size: 22).foregroundStyle(.blue)
                            Text(store.profile?.dailyGoal?.calorieText ?? "Not set")
                                .font(.cave(.title3))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: true, vertical: false)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("adjustGoal")
                    .accessibilityLabel("Daily calorie goal")
                    .accessibilityValue(store.profile?.dailyGoal?.calorieText ?? "Not set")
                    .accessibilityHint("Edit daily calorie goal")
                }
                Section {
                    Button(weights.caloriePlan == nil ? "Build a calorie plan" : "Update calorie plan") { planningCalories = true }
                        .accessibilityIdentifier("caloriePlan")
                }
                MacroSettingsSection()
                WeightProfileSections(editor: $weightEditor)
                AISubscriptionSection(subscriptions: aiSubscriptions) { showingPaywall = true }
                if AIConfiguration.developerSettingsAvailable {
                    Section { NavigationLink("Developer settings") { AIDeveloperSettings() } }
                }
                Section("iCloud") {
                    Label { Text(store.syncStatus) } icon: { CaveIcon(store.cloudEnabled ? .cloud : .phone, size: 24) }
                    Text("Your food entries are saved on this iPhone. With iCloud enabled, they also sync to your other iPhones using the same Apple Account. Weight history stays on this device, with optional sharing to Apple Health.").font(.cave(.footnote)).foregroundStyle(.secondary)
                }
                Section("About") {
                    Text(appVersionLabel)
                    Link("Powered by fatsecret Platform API", destination: URL(string: "https://platform.fatsecret.com")!)
                    Link("FatSecret Terms of Use", destination: URL(string: "https://platform.fatsecret.com/terms")!)
                    Link("Barcode data by Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("Open Database License (ODbL)", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Text("Food searches are sent through our backend to FatSecret; scanned barcodes are sent to Open Food Facts. Your diary is not sent to either provider. Your profile and food diary stay on your devices and in your private iCloud account. When you choose AI photo or voice logging, the selected media is sent to our backend and OpenAI for processing. When you request macro estimates, that food’s name, portion and calories are sent to our backend and OpenAI. When you import a meal from a link, that public URL is sent to our backend and OpenAI. Temporary media is deleted after processing; estimates are retained briefly to support retries. Product serving sizes and calories can vary; you can edit them before adding.").font(.cave(.footnote)).foregroundStyle(.secondary)
                }
                legalLinks
            }
            .navigationTitle("You").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $adjustingGoal) {
                SetupView(goal: store.profile?.dailyGoal, isAdjustingGoal: true)
            }
            .fullScreenCover(isPresented: $planningCalories) { OnboardingView(isRevising: true) }
            .sheet(item: $weightEditor) { route in
                WeightEditorSheet(record: route.record, unit: weights.unit)
            }
            .navigationDestination(isPresented: $showingPaywall) {
                AIUpgradePaywall(
                    subscriptions: aiSubscriptions,
                    onDismissRequested: { showingPaywall = false }
                )
            }
            .task { await store.checkCloud(); await aiSubscriptions.refresh(regularLogCount: store.regularLogCount) }
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "Cave Cals · \(version)" : "Cave Cals · \(version) (\(build))"
    }

    @ViewBuilder private var legalLinks: some View {
        if let base = AIConfiguration.baseURL {
            Section {
                HStack(spacing: 14) {
                    Spacer()
                    Link("Terms of Use", destination: base.appendingPathComponent("terms"))
                    Text("·").foregroundStyle(.tertiary)
                    Link("Privacy Policy", destination: base.appendingPathComponent("privacy"))
                    Spacer()
                }
                .font(.cave(.footnote))
            }
        }
    }
}

struct MealRoute: Identifiable {
    let id = UUID()
    var meal: SavedMeal?
    var fromToday = false
    var initialName = ""
    var initialItems: [EntryDraft] = []

    init(meal: SavedMeal? = nil, fromToday: Bool = false, name: String = "", items: [EntryDraft] = []) {
        self.meal = meal
        self.fromToday = fromToday
        initialName = name
        initialItems = items
    }
}

enum NewMealStart {
    case today, photo, voice, link, manual
}

struct NewMealStartSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let select: (NewMealStart) -> Void

    var body: some View {
        NavigationStack {
            List {
                startButton("Create from Today's Entries", start: .today)
                    .disabled(store.dayEntries(Date()).isEmpty)
                startButton("Create from Meal Scan", start: .photo)
                startButton("Create from Voice Log", start: .voice)
                startButton("Import from Link/Website", start: .link)
                startButton("Manually Add Meal Items", start: .manual)
            }
            .navigationTitle("New Meal")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CaptureCancelButton { dismiss() }
            }
        }
        .presentationDetents([.fraction(0.68)])
        .presentationDragIndicator(.visible)
    }

    private func startButton(_ title: String, start: NewMealStart) -> some View {
        Button {
            select(start)
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                CaveIcon(.chevronRight, size: 16).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                                    CaveIcon(selection.contains(entry.id) ? .check : .circle, size: 24)
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
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack { Text(item.name.isEmpty ? "Unnamed food" : item.name); Spacer(); Text("\(item.calories.calorieText) cal").foregroundStyle(.secondary) }
                                    if store.tracksMacros { MacroLine(summary: MacroSummary([item])) }
                                }
                            }.foregroundStyle(.primary)
                        }.onDelete { items.remove(atOffsets: $0) }
                        Button { showFoodPicker = true } label: { Label { Text("Add food") } icon: { CaveIcon(.plus, size: 18) } }
                    }
                }
                Section {
                    HStack { Text("Total"); Spacer(); Text("\(chosenItems.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal").fontWeight(.semibold) }
                    if store.tracksMacros { DailyMacrosView(summary: MacroSummary(chosenItems), goals: MacroNutrients()) }
                }
                if (route.fromToday ? store.dayEntries(Date()).map(EntryDraft.init) : items)
                    .contains(where: { $0.externalID?.hasPrefix("fatsecret:") == true }) {
                    Section { FatSecretAttribution() }
                }
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
                if !initialized {
                    name = route.meal?.name ?? route.initialName
                    items = route.meal?.items ?? route.initialItems
                    initialized = true
                }
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

struct MealLinkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let imported: (String, [EntryDraft]) -> Void
    @State private var subscriptions = AISubscriptions()
    @State private var link = ""
    @State private var working = false
    @State private var error: String?
    @State private var showPaywall = false
    @State private var retryAfterPurchase = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/recipe", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mealImportLink")
                } header: {
                    Text("Recipe or meal link")
                } footer: {
                    Text("Paste a public recipe, restaurant, or food page. You can review every imported item before saving the meal.")
                }
                Section {
                    Button {
                        importLink()
                    } label: {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(.white) }
                            else { CaveIcon(.arrowRight, size: 18) }
                            Text(working ? "Importing…" : "Import Meal")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validURL == nil || working)
                    .accessibilityIdentifier("importMeal")
                }
                .listRowBackground(Color.clear)
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Import Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(isPresented: $showPaywall) {
                AIUpgradePaywall(
                    subscriptions: subscriptions,
                    onAccessGranted: { retryAfterPurchase = true },
                    onDismissRequested: closePaywall
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var validURL: URL? {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    private func importLink() {
        guard let url = validURL, !working else { return }
        working = true; error = nil
        Task { @MainActor in
            defer { working = false }
            await subscriptions.refresh()
            guard let account = subscriptions.account else {
                error = subscriptions.message ?? "Could not check access. Please try again."
                return
            }
            guard account.active else {
                if subscriptions.offering != nil { showPaywall = true }
                else { error = subscriptions.message ?? "Subscriptions could not load. Please try again." }
                return
            }
            do {
                let result = try await AIBackend.shared.importMeal(from: url)
                let drafts = result.drafts(at: Date(), source: "aiLink")
                guard !drafts.isEmpty else {
                    error = "No meal items were found at that link."
                    return
                }
                imported(result.mealName, drafts)
            } catch {
                self.error = error.localizedDescription
                if let service = error as? AIServiceError,
                   service.code == "subscription_required", subscriptions.offering != nil {
                    showPaywall = true
                }
            }
        }
    }

    private func closePaywall() {
        showPaywall = false
        guard retryAfterPurchase else { return }
        retryAfterPurchase = false
        Task { @MainActor in
            await Task.yield()
            importLink()
        }
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
                    if let message = search.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
                }
                if !search.results.isEmpty || FoodHistory.search(query, entries: store.entries)
                    .contains(where: { $0.draft.externalID?.hasPrefix("fatsecret:") == true }) {
                    FatSecretAttribution()
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
        FoodRow(name: draft.name, calories: draft.calories, detail: draft.servingDescription, macros: MacroSummary([draft]), add: { var copy = draft; copy.id = UUID(); copy.entryID = nil; selected(copy); dismiss() }, edit: { var copy = draft; copy.id = UUID(); copy.entryID = nil; editor = copy })
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
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(item.name.isEmpty ? "Unnamed food" : item.name); Spacer(); Text("\((item.calories * factor).calorieText) cal") }
                                if store.tracksMacros { MacroLine(summary: MacroSummary([item.scaled(factor, at: date, meal: meal.id, order: item.order)])) }
                            }
                        }
                    }
                    Section {
                        HStack { Text("Total"); Spacer(); Text("\(meal.items.reduce(0) { $0 + ($1.calories * factor).rounded() }.calorieText) cal").bold() }
                        if store.tracksMacros {
                            DailyMacrosView(summary: MacroSummary(meal.items.map { $0.scaled(factor, at: date, meal: meal.id, order: $0.order) }), goals: MacroNutrients())
                        }
                    }
                    if meal.items.contains(where: { $0.externalID?.hasPrefix("fatsecret:") == true }) {
                        Section { FatSecretAttribution() }
                    }
                }
            }
            .navigationTitle(meal?.name ?? "Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let meal, store.addMeal(meal, factor: factor, date: date) { dismiss() }
                    } label: {
                        Label("Add Meal", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .disabled(factor <= 0 || !factor.isFinite || meal == nil)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
