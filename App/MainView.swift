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
    case entry(EntryDraft), searchEntry(EntryDraft, String?), namedEntry(EntryDraft), quickEntry(EntryDraft), settings, profile, barcode(Date), meal(UUID, Date), photo, voice, calendar
    case weighIn
    case newMeal, mealEditor(MealRoute), mealCapture(AIInputSheet.Mode), mealImport
    var id: String {
        switch self {
        case .entry(let draft): "entry-\(draft.id)"
        case .searchEntry(let draft, _): "search-entry-\(draft.id)"
        case .namedEntry(let draft): "named-entry-\(draft.id)"
        case .quickEntry(let draft): "quick-entry-\(draft.id)"
        case .settings: "settings"
        case .profile: "profile"
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

/// "Sept. 22nd" — shared by the date header and the Logged list pill.
func monthDayLabel(_ date: Date) -> String {
    let months = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sept.", "Oct.", "Nov.", "Dec."]
    let month = months[Calendar.current.component(.month, from: date) - 1]
    let day = Calendar.current.component(.day, from: date)
    let ordinal = NumberFormatter()
    ordinal.locale = Locale(identifier: "en_US")
    ordinal.numberStyle = .ordinal
    return "\(month) \(ordinal.string(from: NSNumber(value: day)) ?? String(day))"
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
        // Home lists stay clean; the credit lives under search results and in You → About.
        return false
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cleanQuery.isEmpty {
                    homeHeader
                }
            ScrollViewReader { proxy in
                List {
                    Group {
                    if !cleanQuery.isEmpty {
                        searchSection
                    } else if listMode == .quickAdd {
                        suggestionRows
                    } else if listMode == .meals {
                        mealRows
                    } else {
                        if store.dayEntries(selected).isEmpty {
                            Text(Calendar.current.isDateInToday(selected)
                                 ? "You haven't logged anything yet today."
                                 : "No food logged for this day.")
                                .font(.cave(.body)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)
                                .listRowSeparator(.hidden)
                        }
                        Section {
                            ForEach(store.dayEntries(selected)) { entry in
                                Button { searching = false; sheet = .entry(EntryDraft(entry)) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.timestamp, format: .dateTime.hour().minute()).font(.custom("Schoolbell-Regular", size: 14, relativeTo: .caption)).foregroundStyle(.secondary).frame(width: 55, alignment: .leading)
                                        Text(entry.foodDisplayName).font(.custom("Schoolbell-Regular", size: 18, relativeTo: .body)).foregroundStyle(Color.primary.opacity(0.92))
                                            .lineLimit(1).truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.totalCalories.calorieText)
                                            .font(.custom("Schoolbell-Regular", size: 18, relativeTo: .body)).foregroundStyle(Color.primary.opacity(0.92))
                                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                                        CaveIcon(.pencil, size: 22).foregroundStyle(.secondary).padding(.leading, 6)
                                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                                            .accessibilityHidden(true)
                                    }.padding(.horizontal, 8).padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(entry.id)
                                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                                .caveCardRow()
                                .accessibilityIdentifier("entry-\(entry.id)")
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
                    }.listRowBackground(Color.clear)
                }.caveScreenBackground()
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
            .background(Color.caveBackground)
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
            .onChange(of: store.hiddenQuickAddFoods) { _, _ in
                if listMode == .quickAdd { withAnimation { refreshSuggestions() } }
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
        HStack(spacing: 0) {
            DaySelector(selected: $selected, today: today, openCalendar: { sheet = .calendar })
            Spacer(minLength: 0)
            Button { sheet = .profile } label: {
                CaveIcon(.person, size: 26).frame(width: 44, height: 44)
            }.accessibilityLabel("About You").accessibilityIdentifier("profile")
            Button { sheet = .settings } label: {
                CaveIcon(.gear, size: 26).frame(width: 44, height: 44)
            }.accessibilityLabel("Settings").accessibilityIdentifier("appSettings")
        }
        .frame(height: 44)
        .padding(.horizontal, 20).padding(.top, 8)
        DailySummaryCard(calories: store.total(selected), calorieGoal: store.goal(selected),
                         macros: store.tracksMacros ? MacroSummary(store.dayEntries(selected).map(EntryDraft.init)) : nil,
                         macroGoals: store.macroGoals(selected))
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        foodListPicker
            .padding(.horizontal, 20).padding(.bottom, 12)
        // Card rows need no rule under the pills; keep it only above an empty list.
        Divider().padding(.horizontal, 20).opacity(listHasRows ? 0 : 1)
    }

    private var listHasRows: Bool {
        switch listMode {
        case .logged: !store.dayEntries(selected).isEmpty
        case .quickAdd: !suggestedFoods.isEmpty
        case .meals: !store.meals.isEmpty
        }
    }

    private var foodListPicker: some View {
        HStack(spacing: 0) {
            foodListButton(Calendar.current.isDate(selected, inSameDayAs: today) ? "Today" : monthDayLabel(selected),
                           glyph: .check, mode: .logged)
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
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.caveOrange)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .logged ? "Logged, \(title)" : title)
        .accessibilityIdentifier(mode == .logged ? "Logged" : title)
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
        case .profile: ProfileView()
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
    private var searchSection: some View {
        Group {
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
                FoodRow(name: draft.name, calories: draft.calories, detail: draft.servingDescription,
                        add: { addFromSearch(draft) }, edit: { edit(draft, revealAfterSave: true) })
            }
            ForEach(store.meals.filter { normalizedFoodName($0.name).contains(normalizedFoodName(cleanQuery)) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { meal in
                FoodRow(name: meal.name, calories: meal.calories, add: {
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
                FoodRow(name: food.name, calories: draft.calories, detail: draft.servingDescription,
                        add: { addFromSearch(draft) }, edit: { edit(draft, revealAfterSave: true) })
            }
            ForEach(search.results.filter { result in !local.contains { $0.draft.externalID == result.id } }) { result in
                FoodRow(name: result.displayName, calories: result.calories, detail: result.searchDetail,
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
                Text("\nYou eat.\n\nApp remember.\n\nQuick Add show smart suggestions.")
                    .font(.custom("Schoolbell-Regular", size: 19, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(suggestedFoods) { food in
                    let draft = store.applyingCommonDefault(to: food.draft)
                    let pinned = store.isPinned(food.id)
                    FoodRow(name: draft.name, calories: draft.calories, suggestionLayout: true, pinned: pinned,
                            add: {
                                revealNextAddedEntry = false
                                add(draft, source: "suggestion")
                            },
                            edit: { edit(draft, source: "suggestion", pinFoodID: food.id, revealAfterSave: false) })
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 28))
                        .caveCardRow()
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
                            Button {
                                store.hideFromQuickAdd(foodID: food.id, name: draft.name)
                            } label: {
                                Label("Hide for 2 weeks", systemImage: "eye.slash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Hide") { store.hideFromQuickAdd(foodID: food.id, name: draft.name) }
                                .tint(.gray)
                        }
                }
            }
        }
    }
    private var newMealButton: some View {
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
        .tint(.caveOrange)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("newMeal")
    }
    private var mealRows: some View {
        Group {
            if store.meals.isEmpty {
                // With no meals the prompt comes first (in the spot it had below the button), then the button.
                Text("Save foods you often eat together.")
                    .font(.cave(.body)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 70)
                    .listRowSeparator(.hidden)
                newMealButton
            } else {
                newMealButton
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
                // The typed-entry action sits directly above the search field, aligned with its magnifier.
                if !cleanQuery.isEmpty {
                    Group {
                        if let amount = Double(cleanQuery), amount >= 0, amount <= 100_000 {
                            FoodRow(name: "Add \(amount.calorieText) calories", calories: nil,
                                    add: { addFromSearch(EntryDraft(calories: amount)) },
                                    edit: { edit(EntryDraft(calories: amount), focusName: true, revealAfterSave: true) })
                        } else if Double(cleanQuery) == nil {
                            manualSearchEntryButton
                        }
                    }
                    .padding(.leading, 31).padding(.trailing, 18).padding(.top, 8)
                }
                // Search shares the row with the capture shortcuts; focusing it (or typing) takes the full width.
                HStack(spacing: 4) {
                    HStack(spacing: 8) {
                        CaveIcon(.search, size: 20).foregroundStyle(.secondary)
                        TextField(searchExpanded ? "search food or enter cals" : "search / add", text: $query)
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
                    }.padding(.horizontal, 12).frame(minHeight: 48)
                    .background(Color.caveBackground, in: RoundedRectangle(cornerRadius: 14))
                    if !searchExpanded {
                        entryShortcuts.transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.top, cleanQuery.isEmpty ? 12 : 4).padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.22), value: searchExpanded)
            }.background(Color.caveSurface)
    }
    private var searchExpanded: Bool { searching || !query.isEmpty }
    private var entryShortcuts: some View {
        HStack(spacing: 0) {
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .voice
            } label: {
                CaveIcon(.voice, size: 36).frame(width: 63, height: 48)
            }.accessibilityLabel("Voice entry")
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .barcode(loggingDate)
            } label: {
                CaveIcon(.barcode, size: 36).frame(width: 63, height: 48)
            }.accessibilityLabel("Scan barcode")
            Button {
                searching = false
                revealNextAddedEntry = true
                sheet = .photo
            } label: {
                CaveIcon(.meal, size: 36).frame(width: 63, height: 48)
            }.accessibilityLabel("Photo entry")
        }
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
                    .background(Color.caveBackground, in: RoundedRectangle(cornerRadius: 10))
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
        case .today: sheet = .mealEditor(MealRoute(fromDay: Date()))
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
            pinnedIDs: store.pinnedFoodIDs,
            hiddenIDs: store.hiddenQuickAddIDs()
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
        if !suggestionLayout, store.tracksMacros, let macros { parts.append(macros.compactText) }
        return parts.joined(separator: " · ")
    }
    private var rowValue: String {
        [pinned ? "Pinned" : "", store.tracksMacros ? macros?.accessibilityText ?? "" : ""].filter { !$0.isEmpty }.joined(separator: "; ")
    }
    var body: some View {
        HStack(spacing: 0) {
            // Only the + button adds; tapping the name or calories opens the editor.
            Button(action: edit) {
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
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.cave(.caption)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        if suggestionLayout, store.tracksMacros, let macros { MacroLine(summary: macros) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    // Wrapped names grow the card instead of touching its edges; one-line rows keep the 52-pt height.
                    .padding(.vertical, suggestionLayout ? 12 : 0)
                    if suggestionLayout, let calories {
                        Text(calories.calorieText).font(.cave(.body).weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 6)
                    }
                }.frame(maxWidth: .infinity, minHeight: suggestionLayout ? 52 : 48, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel(added ? "Added \(actionName)" : "Edit \(actionName)")
                .accessibilityIdentifier("foodDetails-\(actionName)")
                .accessibilityValue(rowValue)
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
                .accessibilityValue(rowValue)
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
                    .padding(.horizontal, 12).frame(minHeight: 44)
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
        return "\(weekday), \(monthDayLabel(selected))"
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
                }.caveScreenBackground()
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
                            .background(isSelected ? Color.accentColor : Color.caveSurface, in: RoundedRectangle(cornerRadius: 12))
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
