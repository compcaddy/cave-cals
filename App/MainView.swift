import SwiftUI

enum HomeListMode: String, CaseIterable {
    case logged
    case quickAdd
    case meals
}

struct FatSecretAttribution: View {
    var body: some View {
        Link("Powered by fatsecret Platform API", destination: URL(string: "https://platform.fatsecret.com")!)
            .font(.cave(.caption2))
            .frame(minHeight: 44)
            .accessibilityIdentifier("fatSecretAttribution")
    }
}

enum MainSheet: Identifiable {
    case entry(EntryDraft), searchEntry(EntryDraft, String?), namedEntry(EntryDraft), quickEntry(EntryDraft), settings, barcode(Date), meal(UUID, Date), photo, voice, calendar
    case weighIn
    case newMeal, mealEditor(MealRoute), mealCapture(AIInputSheet.Mode), mealImport
    var id: String {
        switch self {
        case .entry(let draft): "entry-\(draft.id)"
        case .searchEntry(let draft, _): "search-entry-\(draft.id)"
        case .namedEntry(let draft): "named-entry-\(draft.id)"
        case .quickEntry(let draft): "quick-entry-\(draft.id)"
        case .settings: "settings"
        case .weighIn: "weigh-in"
        case .barcode: "barcode"
        case .meal(let id, _): "meal-\(id)"
        case .photo: "photo"
        case .voice: "voice"
        case .calendar: "calendar"
        case .newMeal: "new-meal"
        case .mealEditor(let route): "meal-editor-\(route.id)"
        case .mealCapture(let mode): "meal-capture-\(mode == .photo ? "photo" : "voice")"
        case .mealImport: "meal-import"
        }
    }
}

struct CalorieProgressSegments: Equatable {
    let blue: Double
    let orange: Double
    let red: Double

    init(total: Double, goal: Double) {
        guard total.isFinite, goal.isFinite, goal > 0 else {
            blue = 0; orange = 0; red = 0
            return
        }
        let progress = max(0, total / goal)
        if progress <= 1 {
            blue = min(progress, 0.8)
            orange = min(max(progress - 0.8, 0), 0.2)
            red = 0
        } else {
            // Keep the final 20% as the warning band. Each percentage over goal
            // replaces the same amount of blue with red from the right edge.
            red = min(progress - 1, 0.8)
            orange = 0.2
            blue = max(0, 0.8 - red)
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(LoggingActionRouter.self) private var actionRouter
    @Environment(\.scenePhase) private var phase
    @State private var selected = Date()
    @State private var today = Date()
    @State private var query = ""
    @State private var showingQuickCalories = false
    @State private var listMode: HomeListMode = .quickAdd
    @State private var revealNextAddedEntry = false
    @State private var quickAmount: Int?
    @State private var quickName = ""
    @State private var suggestedFoods: [HistoricalFood] = []
    @State private var localSearchFoods: [HistoricalFood] = []
    @State private var search = FoodSearchState()
    @State private var sheet: MainSheet?
    @State private var openedInitially = false
    @State private var backgroundedAt: Date?
    @FocusState private var searching: Bool
    @FocusState private var quickNameFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var summarySize = 32.0
    private var loggingDate: Date { Day.loggingDate(selected) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsFatSecretAttribution: Bool {
        if !cleanQuery.isEmpty {
            return !search.results.isEmpty
                || localSearchFoods.contains { $0.draft.externalID?.hasPrefix("fatsecret:") == true }
                || store.meals.contains {
                    normalizedFoodName($0.name).contains(normalizedFoodName(cleanQuery))
                        && $0.items.contains { $0.externalID?.hasPrefix("fatsecret:") == true }
                }
        }
        switch listMode {
        case .logged: return store.dayEntries(selected).contains { $0.externalID?.hasPrefix("fatsecret:") == true }
        case .quickAdd: return suggestedFoods.contains { $0.draft.externalID?.hasPrefix("fatsecret:") == true }
        case .meals: return store.meals.contains { $0.items.contains { $0.externalID?.hasPrefix("fatsecret:") == true } }
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cleanQuery.isEmpty {
                    homeHeader
                }
            ScrollViewReader { proxy in
                List {
                    if !cleanQuery.isEmpty {
                        searchSection
                    } else if listMode == .quickAdd {
                        suggestionRows
                    } else if listMode == .meals {
                        mealRows
                    } else {
                        if store.dayEntries(selected).isEmpty {
                            Text("No food logged for this day.")
                                .font(.cave(.body)).foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                        }
                        Section {
                            ForEach(store.dayEntries(selected)) { entry in
                                Button { searching = false; sheet = .entry(EntryDraft(entry)) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.timestamp, format: .dateTime.hour().minute()).font(.custom("Schoolbell-Regular", size: 14, relativeTo: .caption)).foregroundStyle(.secondary).frame(width: 55, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.foodDisplayName).font(.custom("Schoolbell-Regular", size: 18, relativeTo: .body)).foregroundStyle(Color.primary.opacity(0.92))
                                                .lineLimit(1).truncationMode(.tail)
                                            if store.tracksMacros { MacroLine(summary: MacroSummary([EntryDraft(entry)])) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.totalCalories.calorieText)
                                            .font(.custom("Schoolbell-Regular", size: 18, relativeTo: .body)).foregroundStyle(Color.primary.opacity(0.92))
                                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                                    }.padding(.horizontal, 8).padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(entry.id)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(.separator)).frame(height: 0.5).allowsHitTesting(false)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                                .accessibilityIdentifier("entry-\(entry.id)")
                                .accessibilityValue(store.tracksMacros ? MacroSummary([EntryDraft(entry)]).accessibilityText : "")
                                .accessibilityLabel("\(entry.name.isEmpty ? "Entry" : entry.name), \(entry.totalCalories.calorieText) calories, \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                                .contextMenu {
                                    Button {
                                        searching = false
                                        sheet = .entry(EntryDraft(entry))
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) { store.delete(entry) }
                                        .tint(.red)
                                }
                            }
                        }.listSectionSeparator(.hidden)
                    }
                    if showsFatSecretAttribution {
                        FatSecretAttribution().listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain).scrollDismissesKeyboard(.interactively)
                .onChange(of: store.lastAddedID) { _, value in
                    guard let value else { return }
                    let source = store.entries.first(where: { $0.id == value })?.sourceType
                    let cameFromScan = ["aiPhoto", "aiVoice", "barcode"].contains(source)
                    if revealNextAddedEntry || cameFromScan {
                        revealNextAddedEntry = false
                        showLogged()
                    }
                    guard listMode == .logged, cleanQuery.isEmpty else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation { proxy.scrollTo(value, anchor: .bottom) }
                    }
                }
            }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .sheet(isPresented: drawerPresented) {
                drawerContent
            }
            .task(id: cleanQuery) {
                localSearchFoods = FoodHistory.search(cleanQuery, entries: store.entries)
                await search.search(cleanQuery)
            }
            .task {
                guard !openedInitially else { return }
                openedInitially = true
                if !openPendingAction() { openSearch() }
            }
            .onChange(of: selected) { _, _ in
                refreshSuggestions()
            }
            .onChange(of: listMode) { _, mode in
                if mode == .quickAdd { refreshSuggestions() }
            }
            .onChange(of: store.pinnedFoodIDs) { _, _ in
                if listMode == .quickAdd { refreshSuggestions() }
            }
            .onChange(of: cleanQuery) { _, value in
                if !value.isEmpty { showingQuickCalories = false }
            }
            .onChange(of: actionRouter.pending) { _, request in
                if request != nil { _ = openPendingAction() }
            }
            .onChange(of: phase) { _, value in
                if value == .background { backgroundedAt = Date() }
                if value == .active {
                    let now = Date()
                    if !Calendar.current.isDate(now, inSameDayAs: today) { resetToday() }
                    if !openPendingAction(), sheet == nil,
                       let backgroundedAt, now.timeIntervalSince(backgroundedAt) >= 30 * 60 {
                        resetToday()
                        openSearch()
                    }
                    backgroundedAt = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in resetToday() }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                if !Calendar.current.isDate(now, inSameDayAs: today) { resetToday() }
            }
        }
    }

    @ViewBuilder private var homeHeader: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                DaySelector(selected: $selected, today: today, openCalendar: { sheet = .calendar })
                    .frame(width: geometry.size.width * 0.75)
                Spacer(minLength: 0)
                Button { sheet = .settings } label: {
                    CaveIcon(.person, size: 26).frame(width: 44, height: 44)
                }.accessibilityLabel("You").accessibilityIdentifier("Settings")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20).padding(.top, 8)
        summary.padding(.horizontal, 20)
        foodListPicker
            .padding(.horizontal, 20).padding(.bottom, 12)
        Divider().padding(.horizontal, 20)
    }

    private var foodListPicker: some View {
        HStack(spacing: 0) {
            foodListButton("Logged", glyph: .check, mode: .logged)
            foodListButton("Quick Add", glyph: .lightning, mode: .quickAdd)
            foodListButton("Meals", glyph: .meals, mode: .meals)
        }
        .padding(3)
        .background(Color(.secondarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foodListPicker")
    }

    private func foodListButton(_ title: String, glyph: CaveGlyph, mode: HomeListMode) -> some View {
        let selected = listMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { listMode = mode }
        } label: {
            HStack(spacing: 6) {
                CaveIcon(glyph, size: 16)
                Text(title)
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                if selected {
                    Capsule()
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    @discardableResult private func openPendingAction() -> Bool {
        let quickCalories = actionRouter.pending?.quickCalories == true
        guard let action = actionRouter.consume() else { return false }
        openedInitially = true
        // External logging always starts today, even if a past day was selected.
        selected = Date()
        today = selected
        searching = false
        query = ""
        switch action {
        case .barcode:
            revealNextAddedEntry = true
            sheet = .barcode(loggingDate)
        case .voice:
            revealNextAddedEntry = true
            sheet = .voice
        case .image:
            revealNextAddedEntry = true
            sheet = .photo
        case .add:
            openSearch()
            showingQuickCalories = quickCalories
        }
        return true
    }
    private var drawerPresented: Binding<Bool> {
        Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
    }
    @ViewBuilder private var drawerContent: some View {
        switch sheet {
        case .entry(let draft):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true).id(draft.id)
        case .searchEntry(let draft, let pinFoodID):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true, onCancel: { sheet = nil }, pinFoodID: pinFoodID).id(draft.id)
        case .namedEntry(let draft):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true, blankCaloriesOnOpen: true, onCancel: { sheet = nil }).id(draft.id)
        case .quickEntry(let draft):
            EntryEditorSheet(draft: draft, focusNameOnOpen: true, onCancel: { sheet = nil }).id(draft.id)
        case .settings: SettingsView()
        case .weighIn: WeightEditorSheet(record: weights.record(on: Date()), unit: weights.unit)
        case .barcode(let date): BarcodeSheet(date: date)
        case .meal(let id, let date): MealAddSheet(mealID: id, date: date)
        case .photo: AIInputSheet(mode: .photo, date: loggingDate).id("photo")
        case .voice: AIInputSheet(mode: .voice, date: loggingDate).id("voice")
        case .calendar: CalorieCalendarSheet(selected: $selected, today: today)
        case .newMeal:
            NewMealStartSheet { start in openMealStart(start) }
        case .mealEditor(let route):
            MealEditorSheet(route: route)
        case .mealCapture(let mode):
            AIInputSheet(mode: mode, date: loggingDate) { drafts in
                sheet = .mealEditor(MealRoute(items: drafts))
            }.id("meal-\(mode == .photo ? "photo" : "voice")")
        case .mealImport:
            MealLinkImportSheet { name, drafts in
                sheet = .mealEditor(MealRoute(name: name, items: drafts))
            }
        case nil: EmptyView()
        }
    }
    private var summary: some View {
        let total = store.total(selected), goal = store.goal(selected)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(total.calorieText)
                        .font(.custom("CaveCount-Regular", fixedSize: summarySize * 1.5))
                    if let goal {
                        Text("/ \(goal.calorieText)")
                            .font(.custom("Schoolbell-Regular", size: 20, relativeTo: .body))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let goal {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(abs(goal - total).calorieText)
                            .font(.custom("Schoolbell-Regular", size: 28, relativeTo: .title2))
                        Text(total > goal ? "over" : "left")
                            .font(.custom("Schoolbell-Regular", size: 20, relativeTo: .body))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(goal.map { "\(total.calorieText) of \($0.calorieText) calories" } ?? "\(total.calorieText) calories")
            .accessibilityIdentifier("calorieSummary")
            if let goal {
                let segments = CalorieProgressSegments(total: total, goal: goal)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        HStack(spacing: 0) {
                            Color.accentColor.frame(width: geometry.size.width * segments.blue)
                            Color.orange.frame(width: geometry.size.width * segments.orange)
                            Color.red.frame(width: geometry.size.width * segments.red)
                            Spacer(minLength: 0)
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 9)
                .animation(.easeInOut(duration: 0.25), value: segments)
                .accessibilityLabel("Goal progress")
                .accessibilityValue("\((max(total / goal, 0) * 100).calorieText) percent")
            }
            if store.tracksMacros {
                DailyMacrosView(summary: MacroSummary(store.dayEntries(selected).map(EntryDraft.init)), goals: store.macroGoals(selected))
            }
        }.frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 12)
    }

    private var searchSection: some View {
        Group {
        if let amount = Double(cleanQuery), amount >= 0, amount <= 100_000 {
            FoodRow(name: "Add \(amount.calorieText) calories", calories: nil,
                    add: { addFromSearch(EntryDraft(calories: amount)) },
                    edit: { edit(EntryDraft(calories: amount), focusName: true, revealAfterSave: true) })
        }
        Group {
            if Double(cleanQuery) == nil {
            Text("Results").font(.cave(.caption2)).foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 16)
            }
            let local = localSearchFoods
            ForEach(local) { food in
                let draft = store.applyingCommonDefault(to: food.draft)
                FoodRow(name: draft.name, calories: draft.calories, detail: draft.servingDescription, macros: MacroSummary([draft]),
                        add: { addFromSearch(draft) }, edit: { edit(draft, revealAfterSave: true) })
            }
            ForEach(store.meals.filter { normalizedFoodName($0.name).contains(normalizedFoodName(cleanQuery)) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { meal in
                FoodRow(name: meal.name, calories: meal.calories, macros: MacroSummary(meal.items), add: {
                    revealNextAddedEntry = true
                    if store.addMeal(meal, date: loggingDate) {
                        showLogged()
                    } else {
                        revealNextAddedEntry = false
                    }
                }, edit: {
                    searching = false
                    revealNextAddedEntry = true
                    sheet = .meal(meal.id, loggingDate)
                })
            }
            ForEach(CommonFoods.search(cleanQuery).filter { food in
                !local.contains { normalizedFoodName($0.draft.name) == normalizedFoodName(food.name) }
            }) { food in
                let draft = store.applyingCommonDefault(to: food.draft)
                FoodRow(name: food.name, calories: draft.calories, detail: draft.servingDescription, macros: MacroSummary([draft]),
                        add: { addFromSearch(draft) }, edit: { edit(draft, revealAfterSave: true) })
            }
            ForEach(search.results.filter { result in !local.contains { $0.draft.externalID == result.id } }) { result in
                FoodRow(name: result.draft.name, calories: result.calories, detail: result.servingDescription, macros: MacroSummary([result.draft]),
                        add: { addFromSearch(result.draft) },
                        edit: { edit(result.draft, revealAfterSave: true) })
            }
            if search.loading {
                HStack(spacing: 12) {
                    ProgressView().frame(width: 24, height: 24)
                    Text("Searching foods…").foregroundStyle(.secondary)
                }
            }
            if let message = search.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
        }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
    private var suggestionRows: some View {
        Group {
            if suggestedFoods.isEmpty {
                Text("\nYou eat.\n\nApp remember.\n\nSoon, app help you log food fast.")
                    .font(.custom("Schoolbell-Regular", size: 19, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(suggestedFoods) { food in
                    let draft = store.applyingCommonDefault(to: food.draft)
                    let pinned = store.isPinned(food.id)
                    FoodRow(name: draft.name, calories: draft.calories, macros: MacroSummary([draft]), suggestionLayout: true, pinned: pinned,
                            add: {
                                revealNextAddedEntry = false
                                add(draft, source: "suggestion")
                            },
                            edit: { edit(draft, source: "suggestion", pinFoodID: food.id, revealAfterSave: false) })
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                        .contextMenu {
                            Button {
                                edit(draft, source: "suggestion", pinFoodID: food.id, revealAfterSave: false)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                revealNextAddedEntry = false
                                add(draft, source: "suggestion")
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            Button {
                                store.setPinned(!pinned, foodID: food.id)
                            } label: {
                                Label(pinned ? "Un-Pin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                            }
                        }
                }
            }
        }
    }
    private var mealRows: some View {
        Group {
            Button {
                sheet = .newMeal
            } label: {
                HStack(spacing: 8) {
                    CaveIcon(.plus, size: 18)
                    Text("New Meal")
                }
                .font(.cave(.subheadline).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("newMeal")

            if store.meals.isEmpty {
                Text("Save foods you often eat together.")
                    .font(.cave(.body)).foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(orderedMeals) { meal in
                    let pinned = store.isMealPinned(meal.id)
                    FoodRow(name: meal.name, calories: meal.calories, macros: MacroSummary(meal.items), suggestionLayout: true, pinned: pinned, add: {
                        revealNextAddedEntry = true
                        sheet = .meal(meal.id, loggingDate)
                    }, edit: {
                        sheet = .mealEditor(MealRoute(meal: meal))
                    })
                    .overlay(alignment: .top) {
                        if meal.id == orderedMeals.first?.id {
                            Rectangle().fill(Color(.separator)).frame(height: 0.5)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                    .contextMenu {
                        Button {
                            sheet = .mealEditor(MealRoute(meal: meal))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.deleteMeal(meal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            store.setMealPinned(!pinned, mealID: meal.id)
                        } label: {
                            Label(pinned ? "Un-Pin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { store.deleteMeal(meal) }
                            .tint(.red)
                    }
                }
            }
        }
    }
    private var orderedMeals: [SavedMeal] {
        let byID = Dictionary(uniqueKeysWithValues: store.meals.map { ($0.id.uuidString, $0) })
        let pinned = store.pinnedMealIDs.compactMap { byID[$0] }
        let pinnedSet = Set(pinned.map(\.id))
        return pinned + store.meals.filter { !pinnedSet.contains($0.id) }
    }
    private var bottomBar: some View {
            VStack(spacing: 0) {
                if showingQuickCalories { quickCalorieGrid }
                if let toast = store.toast {
                    HStack {
                        Text(toast).font(.cave(.subheadline)).lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Undo") { store.undo() }.font(.cave(.subheadline).bold())
                            .frame(minHeight: 44)
                    }.padding(.horizontal, 20).background(Color.accentColor.opacity(0.1))
                        .accessibilityIdentifier("searchUndoBanner")
                }
                if weights.shouldPrompt(on: today), Calendar.current.isDateInToday(selected),
                   !searching, !quickNameFocused, cleanQuery.isEmpty, !showingQuickCalories {
                    HStack(spacing: 0) {
                        Button { sheet = .weighIn } label: {
                            HStack(spacing: 8) {
                                CaveIcon(.person, size: 20)
                                Text("Log today’s weight").font(.cave(.subheadline))
                                Spacer()
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("weighInReminder")
                        Button { weights.dismissToday() } label: {
                            CaveIcon(.plus, size: 15).rotationEffect(.degrees(45)).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Hide weigh-in reminder for today").accessibilityIdentifier("dismissWeighIn")
                    }.padding(.leading, 20).padding(.trailing, 8)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        CaveIcon(.search, size: 20).foregroundStyle(.secondary)
                        TextField("search food or enter cals", text: $query)
                            .focused($searching).submitLabel(.search).autocorrectionDisabled()
                            .accessibilityIdentifier("foodSearch")
                        if searching || !query.isEmpty {
                            Button {
                                query = ""
                                searching = false
                                showingQuickCalories = false
                                refreshSuggestions()
                            } label: {
                                CaveIcon(.plus, size: 17).rotationEffect(.degrees(45))
                                    .foregroundStyle(.red).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Clear search")
                        }
                    }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
                if !cleanQuery.isEmpty {
                    if Double(cleanQuery) == nil {
                        manualSearchEntryButton
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                } else {
                    entryShortcutBar
                }
            }.background(.bar)
    }
    private var entryShortcutBar: some View {
        HStack {
            Spacer()
            Button {
                searching = false
                withAnimation(.easeInOut(duration: 0.2)) { showingQuickCalories.toggle() }
            } label: {
                QuickCaloriesIcon().frame(width: 28, height: 28).frame(width: 60, height: 48)
            }.accessibilityIdentifier("searchQuickCalories").accessibilityLabel("Select Calories").accessibilityValue(showingQuickCalories ? "Expanded" : "Collapsed")
            Spacer()
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .voice
            } label: {
                CaveIcon(.voice, size: 28).frame(width: 60, height: 48)
            }.accessibilityLabel("Voice entry")
            Spacer()
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .barcode(loggingDate)
            } label: {
                CaveIcon(.barcode, size: 28).frame(width: 60, height: 48)
            }.accessibilityLabel("Scan barcode")
            Spacer()
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .photo
            } label: {
                CaveIcon(.meal, size: 28).frame(width: 60, height: 48)
            }.accessibilityLabel("Photo entry")
            Spacer()
        }.padding(.vertical, 8)
    }
    private var manualSearchEntryButton: some View {
        Button {
            searching = false
            revealNextAddedEntry = true
            sheet = .namedEntry(EntryDraft(name: cleanQuery, timestamp: loggingDate))
        } label: {
            HStack(spacing: 12) {
                Text("Add \"\(cleanQuery)\"")
                    .font(.cave(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CaveIcon(.pencil, size: 22)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \"\(cleanQuery)\", enter calories")
        .accessibilityIdentifier("manualSearchEntry")
    }
    private var quickCalorieGrid: some View {
        VStack(spacing: 6) {
            Text("Select Calories").font(.cave(.subheadline))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Array(stride(from: 50, through: 1000, by: 50)), id: \.self) { amount in
                    Button {
                        quickAmount = amount
                        quickNameFocused = true
                    } label: {
                        Text(amount.formatted()).font(.cave(.subheadline)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(quickAmount == amount ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .foregroundStyle(quickAmount == amount ? Color(.systemBackground) : Color.accentColor)
                        .accessibilityLabel("Select \(amount) calories")
                        .accessibilityAddTraits(quickAmount == amount ? .isSelected : [])

                }
            }
            HStack(spacing: 8) {
                TextField("Name (optional)", text: $quickName)
                    .focused($quickNameFocused)
                    .font(.cave(.subheadline))
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("quickCalorieName")
                    .submitLabel(.done)
                    .onSubmit { addQuickCalories() }
                Button(action: addQuickCalories) {
                    CaveIcon(.plus, size: 18).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor, in: Circle())
                        .opacity(quickAmount == nil ? 0.35 : 1)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain)
                    .disabled(quickAmount == nil)
                    .accessibilityLabel("Add quick calories")
            }.padding(.top, 6)
        }.padding(12)
    }
    private func addQuickCalories() {
        guard let quickAmount else { return }
        let draft = EntryDraft(name: quickName.trimmingCharacters(in: .whitespacesAndNewlines),
                               calories: Double(quickAmount), timestamp: loggingDate)
        revealNextAddedEntry = true
        guard store.add([draft]) else {
            revealNextAddedEntry = false
            return
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        quickNameFocused = false
        self.quickAmount = nil
        quickName = ""
        showLogged()
    }
    private func openSearch(autofocus: Bool = false) {
        searching = autofocus
        listMode = .quickAdd
        query = ""
        showingQuickCalories = false
        quickAmount = nil
        quickName = ""
        // Keep rows stable while logging several foods and showing confirmation.
        refreshSuggestions()
        sheet = nil
    }
    private func resetToday() { today = Date(); selected = today }
    private func showLogged() {
        query = ""
        searching = false
        showingQuickCalories = false
        listMode = .logged
    }
    private func openMealStart(_ start: NewMealStart) {
        switch start {
        case .today: sheet = .mealEditor(MealRoute(fromToday: true))
        case .photo: sheet = .mealCapture(.photo)
        case .voice: sheet = .mealCapture(.voice)
        case .link: sheet = .mealImport
        case .manual: sheet = .mealEditor(MealRoute())
        }
    }
    private func addFromSearch(_ input: EntryDraft) {
        revealNextAddedEntry = true
        if add(input) {
            showLogged()
        } else {
            revealNextAddedEntry = false
        }
    }
    @discardableResult private func add(_ input: EntryDraft, source: String? = nil) -> Bool {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        return store.add([draft])
    }
    private func refreshSuggestions() {
        suggestedFoods = FoodHistory.suggestions(
            entries: store.entries,
            date: loggingDate,
            pinnedIDs: store.pinnedFoodIDs
        )
    }
    private func edit(_ input: EntryDraft, source: String? = nil, focusName: Bool = false, pinFoodID: String? = nil, revealAfterSave: Bool) {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        revealNextAddedEntry = revealAfterSave
        searching = false; sheet = focusName ? .quickEntry(draft) : .searchEntry(draft, pinFoodID)
    }
}

struct FoodRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirming = false
    @State private var rotation = 0.0

    let name: String
    var calories: Double?
    var detail: String? = nil
    var macros: MacroSummary? = nil
    var suggestionLayout = false
    var pinned = false
    var added = false
    var keepsAddedState = false
    let add: () -> Void
    let edit: () -> Void
    private var actionName: String { calories == nil && name.hasPrefix("Add ") ? String(name.dropFirst(4)) : name }
    private var subtitle: String {
        var parts = [detail ?? ""].filter { !$0.isEmpty }
        if !suggestionLayout, let calories { parts.append("\(calories.calorieText) Cals") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 0) {
            Button(action: suggestionLayout ? addWithFeedback : edit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if pinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            Text(name).font(.cave(.subheadline).weight(confirming ? .bold : .regular)).foregroundStyle(confirming ? Color.accentColor : Color.primary).lineLimit(2)
                        }
                        if !subtitle.isEmpty { Text(subtitle).font(.cave(.caption)).foregroundStyle(.secondary).lineLimit(2) }
                        if store.tracksMacros, let macros { MacroLine(summary: macros) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if suggestionLayout, let calories {
                        Text(calories.calorieText).font(.cave(.body).weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 6)
                    }
                }.frame(maxWidth: .infinity, minHeight: suggestionLayout ? 52 : 48, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel(added ? "Added \(actionName)" : "\(suggestionLayout ? "Add" : "Edit") \(actionName)")
                .accessibilityIdentifier("foodDetails-\(actionName)")
                .accessibilityValue([pinned ? "Pinned" : "", store.tracksMacros ? macros?.accessibilityText ?? "" : ""].filter { !$0.isEmpty }.joined(separator: "; "))
                .disabled(added)
            Button(action: edit) { CaveIcon(.pencil, size: 22).frame(width: 44, height: suggestionLayout ? 52 : 48) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Edit \(actionName)")
                .disabled(added)
            Button(action: addWithFeedback) {
                if added {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: suggestionLayout ? 52 : 48)
                } else {
                    FlipAddIcon(angle: rotation, showCheckWithoutMotion: reduceMotion && confirming)
                        .frame(width: 44, height: suggestionLayout ? 52 : 48)
                }
            }.buttonStyle(.borderless).accessibilityLabel(added ? "Added \(actionName)" : "Add \(actionName)")
                .disabled(added)
        }
        .task(id: confirming) {
            guard confirming else { return }
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                rotation = reduceMotion ? 0 : 360
            }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            // Reset the equivalent front-facing angle without animating backward.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                rotation = 0
                confirming = false
            }
        }
    }
    private func addWithFeedback() {
        guard !confirming && !added else { return }
        let previous = store.lastAddedID
        add()
        guard store.lastAddedID != previous else { return }
        guard !keepsAddedState else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            confirming = true
            rotation = reduceMotion ? 0 : 180
        }
    }
}

private struct FlipAddIcon: View, Animatable {
    var angle: Double
    var showCheckWithoutMotion: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    var body: some View {
        let showsCheck = showCheckWithoutMotion || (angle >= 90 && angle < 270)
        ZStack {
            CaveIcon(.plus, size: 17).opacity(showsCheck ? 0 : 1)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .rotation3DEffect(.degrees(showCheckWithoutMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(showsCheck ? 1 : 0)
        }
        .foregroundStyle(showsCheck ? Color.primary : Color.white)
        .frame(width: 34, height: 34).background(showsCheck ? Color.clear : Color.accentColor, in: Circle())
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

private struct QuickCaloriesIcon: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for row in 0..<2 {
                for column in 0..<2 {
                    let x = CGFloat(column) * size.width * 0.55 + 1
                    let y = CGFloat(row) * size.height * 0.55 + 1
                    path.move(to: CGPoint(x: x, y: y + 1))
                    path.addLine(to: CGPoint(x: x + size.width * 0.36, y: y))
                    path.addLine(to: CGPoint(x: x + size.width * 0.38, y: y + size.height * 0.37))
                    path.addLine(to: CGPoint(x: x + 1, y: y + size.height * 0.39))
                    path.closeSubpath()
                }
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

struct DaySelector: View {
    @Binding var selected: Date
    var today: Date
    var openCalendar: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button { move(-1) } label: {
                CaveIcon(.chevronLeft, size: 22).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("Previous day")
            Button(action: openCalendar) {
                Text(dateLabel).font(.custom("Schoolbell-Regular", size: 18, relativeTo: .subheadline))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("selectedDate")
                .accessibilityHint("Open calorie calendar")
            Button { move(1) } label: {
                CaveIcon(.chevronRight, size: 22).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("Next day")
                .disabled(Calendar.current.startOfDay(for: selected) >= Calendar.current.startOfDay(for: today))
        }
    }
    private var dateLabel: String {
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thur", "Fri", "Sat"]
        let weekday = weekdays[Calendar.current.component(.weekday, from: selected) - 1]
        let months = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sept.", "Oct.", "Nov.", "Dec."]
        let month = months[Calendar.current.component(.month, from: selected) - 1]
        let day = Calendar.current.component(.day, from: selected)
        let ordinal = NumberFormatter()
        ordinal.locale = Locale(identifier: "en_US")
        ordinal.numberStyle = .ordinal
        return "\(weekday), \(month) \(ordinal.string(from: NSNumber(value: day)) ?? String(day))"
    }
    private func move(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selected),
              Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: today) else { return }
        selected = next
    }
}

private struct CalorieCalendarSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Date
    let today: Date
    @State private var extraMonths = 0
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }
    private var months: [Date] {
        let end = monthStart(today)
        let twoYearsAgo = calendar.date(byAdding: .month, value: -23, to: end)!
        let earliest = min(store.entries.map(\.timestamp).min() ?? selected, selected)
        let start = calendar.date(byAdding: .month, value: -extraMonths, to: min(monthStart(earliest), twoYearsAgo))!
        let count = calendar.dateComponents([.month], from: start, to: end).month ?? 0
        return (0...max(0, count)).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }
    var body: some View {
        let totals = Dictionary(grouping: store.entries, by: { calendar.startOfDay(for: $0.timestamp) })
            .mapValues { $0.reduce(0) { $0 + $1.totalCalories.rounded() } }
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 28) {
                        Button("Earlier months") { extraMonths += 12 }
                            .frame(minHeight: 44)
                        ForEach(months, id: \.self) { month in
                            monthView(month, totals: totals).id(month)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 16)
                }
                .task { proxy.scrollTo(monthStart(selected), anchor: .top) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") { withAnimation { proxy.scrollTo(monthStart(today), anchor: .top) } }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func monthView(_ month: Date, totals: [Date: Double]) -> some View {
        let days = calendar.range(of: .day, in: .month, for: month)!
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return VStack(alignment: .leading, spacing: 12) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.cave(.title2).bold())
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    Text(symbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.cave(.caption)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 64) }
                ForEach(Array(days), id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
                    let total = totals[date, default: 0]
                    let isSelected = calendar.isDate(date, inSameDayAs: selected)
                    let isToday = calendar.isDate(date, inSameDayAs: today)
                    let future = date > calendar.startOfDay(for: today)
                    Button {
                        selected = date
                        dismiss()
                    } label: {
                        VStack(spacing: 7) {
                            Text(day.formatted()).font(.cave(.subheadline).weight(isToday ? .bold : .regular))
                            Text(total == 0 ? "–" : total.calorieText)
                                .font(.cave(.caption).weight(.semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }.frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                if isToday { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 1.5) }
                            }
                            .opacity(future ? 0.3 : 1)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(future)
                        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(total.calorieText) calories")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}
