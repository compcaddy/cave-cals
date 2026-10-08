import SwiftUI

/// Person icon: the user's own goals and tracking choices.
struct ProfileView: View {
    @State private var aiSubscriptions = AISubscriptions()
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adjustingGoal = false
    @State private var planningCalories = false
    @State private var showingPaywall = false
    @State private var weightEditor: WeightEditorRoute?
    @Environment(WeightStore.self) private var weights
    private var planTitle: String { weights.caloriePlan == nil ? "Build a calorie plan" : "Update calorie plan" }

    /// Under the goal: "Help me decide" for a hand-set goal, or "Update calorie plan" while weight isn't tracked
    /// (otherwise the Goal Weight row opens the calculator).
    @ViewBuilder private var goalFooter: some View {
        if store.profile?.dailyGoal != nil {
            // With weight tracked, the plan's goal weight and pace live in the Goal Weight row (October 7, 2026).
            if weights.caloriePlan != nil && weights.tracking {
                EmptyView()
            } else {
                Button(weights.caloriePlan == nil ? "Help me decide" : "Update calorie plan") { planningCalories = true }
                    .hapticButtonStyle(.plain).font(.cave(.subheadline)).foregroundStyle(Color.caveOrange)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    .accessibilityIdentifier("caloriePlan")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    var body: some View {
        NavigationStack {
            HapticForm {
                // With no goal yet, the calculator leads About You. Once a goal exists it lives under the goal.
                if store.profile?.dailyGoal == nil {
                Section {
                    Button { planningCalories = true } label: {
                        HStack(spacing: 12) {
                            CaveIcon(.meals, size: 26).foregroundStyle(Color.caveOrange)
                            Text(planTitle).foregroundStyle(Color.caveOrange)
                            Spacer(minLength: 8)
                            CaveIcon(.chevronRight, size: 16).foregroundStyle(Color.secondary)
                        }.contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(planTitle)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("caloriePlan")
                }
                }
                Section {
                    Button { adjustingGoal = true } label: {
                        HStack(spacing: 12) {
                            Text("Daily calorie goal").foregroundStyle(Color.primary)
                            Spacer(minLength: 8)
                            HStack(spacing: 6) {
                                CaveIcon(.pencil, size: 22).foregroundStyle(Color.caveOrange)
                                Text(store.profile?.dailyGoal?.calorieText ?? "Set")
                                    .font(.cave(.title3))
                                    .foregroundStyle(Color.caveOrange)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.trailing, 8)
                        }.contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("adjustGoal")
                    .accessibilityLabel("Daily calorie goal")
                    .accessibilityValue(store.profile?.dailyGoal?.calorieText ?? "Not set")
                    .accessibilityHint("Edit daily calorie goal")
                } footer: { goalFooter }
                MacroSettingsSection()
                WeightProfileSections(editor: $weightEditor) { planningCalories = true }
                if AppEnvironment.isDevelopment { DevTestDataSection() }
                AISubscriptionSection(subscriptions: aiSubscriptions) { showingPaywall = true }
            }.caveScreenBackground()
            // Every row, whether a button, switch or link, shares one height; whole rows are the tap targets.
            .environment(\.defaultMinListRowHeight, 60)
            .navigationTitle("About You").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) } }
            .fullScreenCover(isPresented: $adjustingGoal) {
                SetupView(goal: store.profile?.dailyGoal, isAdjustingGoal: true)
            }
            .fullScreenCover(isPresented: $planningCalories) { OnboardingView(isRevising: true) }
            .sheet(item: $weightEditor) { route in
                WeightEditorSheet(record: route.record, unit: weights.unit)
            }
            .navigationDestination(isPresented: $showingPaywall) {
                AIUpgradePaywall(subscriptions: aiSubscriptions, trigger: .aboutYou, onDismissRequested: { showingPaywall = false })
            }
            .task { await aiSubscriptions.refresh(regularLogCount: store.regularLogCount) }
        }
    }
}

/// Cog icon: app-wide settings, sync status, and credits.
struct SettingsView: View {
    @State private var aiSubscriptions = AISubscriptions()
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppStore.showsHomeQuickAddKey) private var showsHomeQuickAdd = true
    @AppStorage(AppStore.showsFinishDayKey) private var showsFinishDay = true
    @State private var showsHiddenQuickAdd = false
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            HapticForm {
                if AppEnvironment.isDevelopment { DevTestDataSection() }
                AISubscriptionSection(subscriptions: aiSubscriptions) { showingPaywall = true }
                if AIConfiguration.developerSettingsAvailable {
                    Section { NavigationLink("Developer settings") { AIDeveloperSettings().hapticOnPush() } }
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .hapticSelection(on: appearance)
                    .accessibilityIdentifier("appearancePicker")
                }
                Section {
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                        .accessibilityIdentifier("hapticFeedback")
                } footer: {
                    Text("Taps as you use the app, and a rumble as calories count up after you log food.").font(.cave(.caption2))
                }
                Section {
                    Toggle("Show Quick Start on new days", isOn: $showsHomeQuickAdd)
                        .accessibilityIdentifier("showHomeQuickAdd")
                    Toggle("Show “Done eating” button", isOn: $showsFinishDay)
                        .accessibilityIdentifier("showFinishDay")
                } header: { Text("Home") } footer: {
                    Text("Quick Start shows your usual first foods until you log another way that day. “Done eating for today” appears from 6 pm or at 90% of your goal; a day marked done counts as complete in Progress.").font(.cave(.caption2))
                }
                MealTypeSettingsSection()
                LogReminderSettingsSection()
                if AppEnvironment.isDevelopment {
                    Section("Apple Health") { Text("Disabled in Cave Cals Dev. Test food and weigh-ins stay out of Apple Health.") }
                } else { AppleHealthSection() }
                SavedNutritionSettingsSection()
                let hidden = store.activeHiddenQuickAddFoods()
                if !hidden.isEmpty {
                    Section {
                        // Collapsed by default; the list can get long.
                        DisclosureGroup(isExpanded: $showsHiddenQuickAdd) {
                        ForEach(hidden) { food in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name.isEmpty ? "Unnamed food" : food.name).lineLimit(2)
                                    Text("Back \(food.returnsAt.formatted(.dateTime.month(.abbreviated).day()))")
                                        .font(.cave(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("Unhide") { store.unhideQuickAdd(food.id) }
                                    .hapticButtonStyle(.bordered).tint(.caveOrange)
                                    .accessibilityLabel("Unhide \(food.name)")
                            }
                        }
                        } label: {
                            Text("\(hidden.count) hidden \(hidden.count == 1 ? "food" : "foods")").foregroundStyle(Color.primary)
                        }
                        .accessibilityIdentifier("hiddenQuickAddList")
                    } header: {
                        Text("Hidden from Quick Add")
                    } footer: {
                        Text("Hidden foods return after two weeks, or sooner if you log them again.").font(.cave(.caption2))
                    }
                }
                Section("iCloud") {
                    Label { Text(store.syncStatus) } icon: { CaveIcon(store.cloudEnabled ? .cloud : .phone, size: 24) }
                    Text(AppEnvironment.isDevelopment ? "iCloud is disabled in Cave Cals Dev. Test data stays on this device, separate from your normal app." : "Your food entries are saved on this iPhone. With iCloud enabled, they also sync to your other iPhones using the same Apple Account. Weight history stays on this device. Food and weigh-ins can optionally be shared to Apple Health.").font(.cave(.footnote)).foregroundStyle(.secondary)
                }
                if !AppEnvironment.isDevelopment { UsageStatsSettingsSection() }
                TellTheTribeSection()
                Section("About") {
                    Text(appVersionLabel)
                    Link("Powered by fatsecret Platform API", destination: URL(string: "https://platform.fatsecret.com")!)
                    Link("FatSecret Terms of Use", destination: URL(string: "https://platform.fatsecret.com/terms")!)
                    Link("Barcode data by Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("Open Database License (ODbL)", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Text("Food searches are sent through our backend to FatSecret; scanned barcodes are sent to Open Food Facts. Your diary is not sent to either provider. Your profile and food diary stay on your devices and in your private iCloud account, and in Apple Health only if you turn on sharing. When you choose AI photo or voice logging, the selected media is sent to our backend and OpenAI for processing. When you request macro estimates, that food’s name, portion and calories are sent to our backend and OpenAI. When you import a meal from a link, that public URL is sent to our backend and OpenAI. Temporary media is deleted after processing; estimates are retained briefly to support retries. Product serving sizes and calories can vary; you can edit them before adding.").font(.cave(.footnote)).foregroundStyle(.secondary)
                }
                legalLinks
            }.caveScreenBackground()
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) } }
            .navigationDestination(isPresented: $showingPaywall) {
                AIUpgradePaywall(subscriptions: aiSubscriptions, trigger: .settings, onDismissRequested: { showingPaywall = false })
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

/// Rate, share, and feedback links. Rating opens the App Store's write-review page directly (the system
/// `requestReview` prompt may not appear when someone asks for it).
private struct TellTheTribeSection: View {
    var body: some View {
        Section("Tell the tribe") {
            Link(destination: CaveCalsLinks.rate) { Label("Rate Cave Cals", systemImage: "star") }
                .accessibilityIdentifier("rateApp")
            ShareLink(item: CaveCalsLinks.share, subject: Text("Cave Cals"), message: Text("You eat. App track. Weight drop. Try Cave Cals:")) {
                Label("Share Cave Cals", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("shareApp")
            Link(destination: CaveCalsLinks.feedback) { Label("Send feedback", systemImage: "envelope") }
                .accessibilityIdentifier("sendFeedback")
                .environment(\.openURL, OpenURLAction { _ in UsageStats.shared.count(.feedbackTaps); return .systemAction })
        }
    }
}

/// Settings → Usage stats: anonymous counts and error reports, on by default.
private struct UsageStatsSettingsSection: View {
    @AppStorage(UsageStats.sharingKey) private var sharing = true
    var body: some View {
        Section {
            Toggle("Share anonymous usage stats", isOn: $sharing)
                .accessibilityIdentifier("shareUsageStats")
                .onChange(of: sharing) { _, _ in UsageStats.shared.sharingChanged() }
        } header: {
            Text("Usage stats")
        } footer: {
            Text("Sends counts like how many foods you log and which features you use, error reports, and searches that found nothing, so Cave Cals can get better. Never your diary, calories, weight, or Health data, and it isn’t linked to you.")
                .font(.cave(.caption2))
        }
    }
}

private struct SavedNutritionSettingsSection: View {
    @Environment(AppStore.self) private var store
    @State private var confirmingReset = false
    @State private var didReset = false

    var body: some View {
        Section {
            Button("Reset Saved Nutrition", role: .destructive) { confirmingReset = true }
                .disabled(store.commonFoodDefaults.isEmpty)
                .accessibilityIdentifier("resetSavedNutrition")
        } header: {
            Text("Saved food nutrition")
        } footer: {
            Text(store.commonFoodDefaults.isEmpty
                 ? (didReset ? "Saved nutrition reset. Your daily logs are unchanged." : "No custom food defaults saved.")
                 : "Restore built-in calories, serving sizes, and macros for foods you customized with Save as default.")
                .font(.cave(.caption2))
        }
        .alert("Reset saved nutrition?", isPresented: $confirmingReset) {
            // Alert buttons may skip the haptic button style, so they play their own feel.
            Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            Button("Reset", role: .destructive) {
                Haptics.play(.warning)
                store.resetSavedNutrition()
                didReset = true
            }.hapticFeel(.none)
        } message: {
            Text("Removes the custom calories, serving sizes, and macros saved with Save as default on this device. Those foods will use their built-in nutrition for future adds.\n\nYour daily logs, saved meals, barcode foods, goals, and weigh-ins stay unchanged. This cannot be undone.")
        }
    }
}

struct MealRoute: Identifiable {
    let id = UUID()
    var meal: SavedMeal?
    /// Build the meal by ticking foods already logged on this day (plus any extra foods).
    var fromDay: Date?
    var selectAllFromDay = false
    var initialName = ""
    var initialItems: [EntryDraft] = []
    /// How many servings `initialItems` make together (an imported recipe's yield).
    var initialServings = 1

    init(meal: SavedMeal? = nil, fromDay: Date? = nil, selectAll: Bool = false, name: String = "", items: [EntryDraft] = [], servings: Int = 1) {
        self.meal = meal
        self.fromDay = fromDay
        selectAllFromDay = selectAll
        initialName = name
        initialItems = items
        initialServings = servings
    }

    /// A time-of-day name ("Lunch", "Lunch 2") so a new meal can be saved without typing. With meal types on,
    /// it's the meal type for now (Morning Snack, or one the person added).
    static func suggestedName(existing: [String], at date: Date = Date(), mealTypes: MealSettings = MealSettings()) -> String {
        let current = mealTypes.tracks ? mealTypes.type(id: mealTypes.meal(at: date))?.name : nil
        let base = current ?? Day.mealName(at: date)
        let taken = Set(existing.map { normalizedFoodName($0) })
        guard taken.contains(normalizedFoodName(base)) else { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains(normalizedFoodName($0)) }!
    }
}

enum NewMealStart {
    case today, photo, voice, recipe(RecipeImportSource), manual
}

struct NewMealStartSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let select: (NewMealStart) -> Void
    @State private var choosingRecipeSource = false

    var body: some View {
        let hasToday = !store.dayEntries(Date()).isEmpty
        NavigationStack {
            choices {
                option("From today’s log", hasToday ? "Tick foods you already logged today" : "Log some foods first, then save them together",
                       glyph: .check, id: "newMealToday", enabled: hasToday) { select(.today) }
                option("Snap your meal", "Scan your plate; each food becomes an item", glyph: .meal, id: "newMealPhoto") { select(.photo) }
                option("Say what’s in it", "Describe the meal out loud", glyph: .voice, id: "newMealVoice") { select(.voice) }
                option("Import a recipe", "Link, photo, or copied recipe", glyph: .cloud, id: "newMealLink") { choosingRecipeSource = true }
                option("Build it yourself", "Search foods or add your own", glyph: .pencil, id: "newMealManual") { select(.manual) }
            }
            .navigationTitle("New Meal")
            .navigationDestination(isPresented: $choosingRecipeSource) {
                choices {
                    option("From link", "Paste recipe link. Cave read page.", glyph: .cloud, id: "recipeFromLink") { select(.recipe(.link)) }
                    option("From photo", "Snap cookbook page or pick screenshots. Up to 5 pages.", glyph: .camera, id: "recipeFromPhoto") { select(.recipe(.photo)) }
                    option("From clipboard", "Copy recipe words or picture. Cave paste.", glyph: .phone, id: "recipeFromClipboard") { select(.recipe(.clipboard)) }
                }
                .navigationTitle("Import Recipe")
            }
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
    }

    private func choices<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 10) { content() }
                .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color.caveBackground)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CaptureCancelButton { dismiss() }
        }
    }

    private func option(_ title: String, _ detail: String, glyph: CaveGlyph, id: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CaveIcon(glyph, size: 32)
                    .foregroundStyle(enabled ? Color.caveOrange : Color.secondary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.cave(.headline)).foregroundStyle(.primary)
                    Text(detail).font(.cave(.footnote)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                CaveIcon(.chevronRight, size: 14).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .hapticButtonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityIdentifier(id)
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
    /// How many servings the foods make together; saving stores one serving's share (see `RecipeServings`).
    @State private var recipeServings = 1
    var body: some View {
        NavigationStack {
            HapticList {
                Section("Meal name") {
                    TextField(suggestedName, text: $name).accessibilityIdentifier("mealName")
                }
                if let day = route.fromDay {
                    let entries = store.dayEntries(day)
                    Section {
                        ForEach(entries) { entry in
                            Button {
                                if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    CaveIcon(selection.contains(entry.id) ? .check : .circle, size: 24)
                                        .foregroundStyle(selection.contains(entry.id) ? Color.caveOrange : Color.secondary)
                                    Text(entry.name.isEmpty ? "\(entry.totalCalories.calorieText) calories" : entry.name).foregroundStyle(.primary)
                                    Spacer(); Text(entry.totalCalories.calorieText).foregroundStyle(.secondary)
                                }.padding(.vertical, 5).contentShape(Rectangle())
                            }.hapticButtonStyle(.plain).hapticFeel(.selection)
                            .accessibilityLabel("Select \(entry.name.isEmpty ? entry.totalCalories.calorieText + " calories" : entry.name)")
                            .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
                        }
                    } header: {
                        HStack {
                            Text(Calendar.current.isDateInToday(day) ? "From today’s log" : "From \(monthDayLabel(day))")
                            Spacer()
                            if !entries.isEmpty {
                                let all = entries.allSatisfy { selection.contains($0.id) }
                                Button(all ? "Clear" : "Select All") {
                                    selection = all ? [] : Set(entries.map(\.id))
                                }.hapticFeel(.selection)
                                .font(.cave(.caption).bold()).foregroundStyle(Color.caveOrange).textCase(nil)
                                .accessibilityIdentifier("mealSelectAll")
                            }
                        }
                    }
                }
                Section(route.fromDay != nil ? "Other foods" : splitsRecipe ? "Foods · whole recipe" : "Foods") {
                    ForEach(items) { item in
                        Button { component = item } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(item.name.isEmpty ? "Unnamed food" : item.name); Spacer(); Text("\(item.calories.calorieText) cal").foregroundStyle(.secondary) }
                                if store.tracksMacros { MacroLine(summary: MacroSummary([item])) }
                            }
                        }.foregroundStyle(.primary)
                    }.onDelete { items.remove(atOffsets: $0) }
                    Button { showFoodPicker = true } label: {
                        Label { Text("Add food") } icon: { CaveIcon(.plus, size: 18) }
                            .foregroundStyle(Color.caveOrange)
                    }
                    .accessibilityIdentifier("addMealFood")
                }
                if showsServings {
                    Section {
                        RecipeServingsControl(count: $recipeServings)
                    } footer: {
                        Text(splitsRecipe ? "Foods above feed \(recipeServings). Each add logs 1 serving." : "Cook for whole tribe? Set servings. Each add logs one.")
                    }
                }
                Section {
                    if splitsRecipe {
                        HStack { Text("Whole recipe"); Spacer(); Text("\(chosenItems.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal").foregroundStyle(.secondary) }
                        HStack { Text("Per serving"); Spacer(); Text("\(savedItems.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal").fontWeight(.semibold) }
                            .accessibilityIdentifier("mealPerServing")
                    } else {
                        HStack { Text("Total"); Spacer(); Text("\(chosenItems.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal").fontWeight(.semibold) }
                    }
                    if store.tracksMacros { DailyMacrosView(summary: MacroSummary(savedItems), goals: MacroNutrients()) }
                } footer: {
                    if chosenItems.isEmpty {
                        Text(route.fromDay == nil ? "Add at least one food to save this meal." : "Tick or add at least one food to save this meal.")
                    }
                }
                if chosenItems.contains(where: { $0.externalID?.hasPrefix("fatsecret:") == true }) {
                    Section { FatSecretAttribution() }
                }
            }.caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle(route.meal == nil ? "New Meal" : "Edit Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if store.saveMeal(route.meal, name: savedName, items: savedItems) { dismiss() }
                    } label: {
                        Label("Save Meal", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                    }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange).hapticFeel(.success)
                    .disabled(chosenItems.isEmpty)
                }
            }
            .onAppear {
                if !initialized {
                    name = route.meal?.name ?? route.initialName
                    items = route.meal?.recipeItems ?? route.initialItems
                    recipeServings = route.meal?.recipeServings ?? route.initialServings
                    if let day = route.fromDay, route.selectAllFromDay { selection = Set(store.dayEntries(day).map(\.id)) }
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
    private var suggestedName: String {
        MealRoute.suggestedName(existing: store.meals.filter { $0.id != route.meal?.id }.map(\.name), mealTypes: store.mealSettings)
    }
    private var savedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? suggestedName : typed
    }
    private var chosenItems: [EntryDraft] {
        let fromDay = route.fromDay.map { day in store.dayEntries(day).filter { selection.contains($0.id) }.map { EntryDraft($0) } } ?? []
        return fromDay + items
    }
    /// Foods ticked from a day's log are already what was eaten, so only other meals can be split into servings.
    private var showsServings: Bool { route.fromDay == nil }
    private var splitsRecipe: Bool { showsServings && recipeServings > 1 }
    /// One serving's share: what the meal saves, and what each add logs.
    private var savedItems: [EntryDraft] { RecipeServings.share(chosenItems, servings: showsServings ? recipeServings : 1) }
}

/// The number of servings a meal's foods make together: a typed whole number with − / + steps.
struct RecipeServingsControl: View {
    @Binding var count: Int
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Servings")
            Spacer(minLength: 8)
            TextField("1", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.cave(.title3))
                .frame(width: 60, height: 36)
                .background(Color.caveBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .focused($editing)
                .accessibilityIdentifier("recipeServings")
                .accessibilityLabel("Servings the recipe makes")
                .selectValueOnFocus(identifier: "recipeServings")
            Stepper("Servings", value: Binding(get: { count }, set: { value in
                count = value
                Haptics.play(.selection)
            }), in: RecipeServings.range)
                .labelsHidden()
                .accessibilityIdentifier("recipeServingsStepper")
                .accessibilityLabel("Servings the recipe makes")
        }
        .frame(minHeight: 44)
        .onAppear { text = String(count) }
        .onChange(of: count) { _, value in
            if Int(text) != value { text = String(value) }
        }
        .onChange(of: text) { _, value in
            let digits = String(value.filter(\.isASCII).filter(\.isNumber).prefix(3))
            guard digits == value else { text = digits; return }
            guard let typed = Int(digits), typed >= RecipeServings.range.lowerBound else { return }
            count = min(typed, RecipeServings.range.upperBound)
            if typed > RecipeServings.range.upperBound { text = String(count) }
        }
        // Leaving the field blank or at zero keeps the last good number.
        .onChange(of: editing) { _, focused in
            if !focused { text = String(count) }
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
    @State private var addedKeys = Set<String>()
    @State private var addedCount = 0
    var body: some View {
        NavigationStack {
            HapticList {
                Button { editor = EntryDraft(name: Double(query) == nil ? query : "", calories: Double(query) ?? 0) } label: {
                    Label { Text("Create manual item") } icon: { CaveIcon(.pencil, size: 18) }
                        .foregroundStyle(Color.caveOrange)
                }
                Section("Your foods") {
                    ForEach(FoodHistory.search(query, entries: store.entries)) { food in row(store.applyingCommonDefault(to: food.draft)) }
                }
                Section("Food search") {
                    ForEach(search.results) { food in row(food.draft, detail: food.searchDetail) }
                    if search.loading { ProgressView("Searching foods…") }
                    if let message = search.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
                }
                if !search.results.isEmpty || FoodHistory.search(query, entries: store.entries)
                    .contains(where: { $0.draft.externalID?.hasPrefix("fatsecret:") == true }) {
                    FatSecretAttribution()
                }
            }.caveScreenBackground()
            .searchable(text: $query, prompt: "Search food or enter calories")
            .navigationTitle(addedCount == 0 ? "Add foods" : "\(addedCount) added").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The picker stays open so a whole meal can be added in one visit.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.hapticButtonStyle(.automatic).fontWeight(.semibold).accessibilityIdentifier("mealPickerDone")
                }
            }
            .task(id: query) { await search.search(query) }
            .sheet(item: $editor) { draft in
                EntryEditorSheet(draft: draft) { selected($0); addedCount += 1 }
            }
        }
    }
    private func key(_ draft: EntryDraft) -> String {
        draft.externalID ?? "name:\(normalizedFoodName(draft.name))"
    }
    private func row(_ draft: EntryDraft, detail: String? = nil) -> some View {
        FoodRow(name: draft.name, calories: draft.calories, detail: detail ?? draft.servingDescription, macros: MacroSummary([draft]),
                added: addedKeys.contains(key(draft)), keepsAddedState: true,
                add: {
                    var copy = draft; copy.id = UUID(); copy.entryID = nil
                    selected(copy); addedKeys.insert(key(draft)); addedCount += 1
                },
                edit: { var copy = draft; copy.id = UUID(); copy.entryID = nil; editor = copy })
    }
}

struct MealAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealID: UUID
    let date: Date
    @State private var factor: Double = 1
    /// Picked here when adding asks for a meal type; by time of day, the meal comes from when it's added.
    @State private var mealType: String?
    private var meal: SavedMeal? { store.meals.first { $0.id == mealID } }
    var body: some View {
        NavigationStack {
            HapticForm {
                if let meal {
                    Section { ServingControl(value: $factor) } footer: {
                        if meal.recipeServings > 1 { Text("Recipe makes \(meal.recipeServings) servings.") }
                    }
                    if store.mealSettings.asks {
                        Section("Meal type") {
                            MealTypePicker(types: store.mealSettings.visibleTypes, selection: $mealType)
                                .padding(.vertical, 4)
                        }
                    }
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
            }.caveScreenBackground()
            .navigationTitle(meal?.name ?? "Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let meal, store.addMeal(meal, factor: factor, date: date, mealType: mealType) { dismiss() }
                    } label: {
                        Label("Add Meal", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                    }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange).hapticFeel(.success)
                    .disabled(factor <= 0 || !factor.isFinite || meal == nil)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
