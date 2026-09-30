import StoreKit
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
    case weighIn, progress
    case newMeal, mealEditor(MealRoute), mealCapture(AIInputSheet.Mode), mealImport
    var id: String {
        switch self {
        case .entry(let draft): "entry-\(draft.id)"
        case .searchEntry(let draft, _): "search-entry-\(draft.id)"
        case .namedEntry(let draft): "named-entry-\(draft.id)"
        case .quickEntry(let draft): "quick-entry-\(draft.id)"
        case .settings: "settings"
        case .profile: "profile"
        case .progress: "progress"
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
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var selected = Date()
    @State private var today = Date()
    @State private var query = ""
    @State private var listMode: HomeListMode = .quickAdd
    /// Home shows the day's totals and log; tapping search enters add mode (pills, Quick Add first) until the red X.
    @State private var addMode = false
    @State private var revealNextAddedEntry = false
    /// A search add returns Home with the field still focused, ready for the next food.
    @State private var primeSearchAfterReveal = false
    @State private var searchPrimedOnHome = false
    /// A Home Quick Add pick that was just added stays until its confirmation animation finishes.
    @State private var settlingHomeQuickAddID: String?
    /// Kept here (not in the card) so totals logged from add mode count up when Home comes back.
    @State private var summaryFigures: SummaryFigures?
    @AppStorage(AppStore.showsHomeQuickAddKey) private var showsHomeQuickAddSetting = true
    @AppStorage(AppStore.showsFinishDayKey) private var showsFinishDaySetting = true
    @ScaledMetric(relativeTo: .subheadline) private var quickStartRowHeight: CGFloat = 44
    @State private var suggestedFoods: [HistoricalFood] = []
    @State private var search: FoodSearchState = {
        #if DEBUG && targetEnvironment(simulator)
        if SearchLayoutFixture.isEnabled {
            return FoodSearchState(provider: SearchLayoutFixture(), persistCache: false)
        }
        #endif
        return FoodSearchState()
    }()
    @State private var sheet: MainSheet?
    @State private var openedInitially = false
    @State private var focusSearchAfterDismiss = false
    @State private var backgroundedAt: Date?
    /// A fifth food on one day, or Done eating: ask how it's going once Home is idle.
    @State private var reviewMomentPending = false
    @State private var askingHowItsGoing = false
    @State private var offeringFeedback = false
    /// iOS's notification prompt already interrupted this session; don't follow it with another question.
    @State private var askedForRemindersThisSession = false
    @FocusState private var searching: Bool
    private var loggingDate: Date { Day.loggingDate(selected) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    // Resolve history for the current query synchronously, before any remote response or cache hit.
    private var localSearchFoods: [HistoricalFood] { FoodHistory.search(cleanQuery, entries: store.entries) }
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
                if !addMode {
                    homeHeader
                } else if cleanQuery.isEmpty {
                    addModeHeader
                }
            ScrollViewReader { proxy in
                HapticList {
                    Group {
                    if !cleanQuery.isEmpty {
                        searchSection
                    } else if !addMode {
                        loggedRows
                    } else if listMode == .quickAdd {
                        suggestionRows
                    } else if listMode == .meals {
                        mealRows
                    } else {
                        repeatRows
                    }
                    if showsFatSecretAttribution {
                        FatSecretAttribution().listRowSeparator(.hidden)
                    }
                    }.listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(Color.caveBackground)
                .listStyle(.plain).scrollDismissesKeyboard(.interactively)
                // A new query starts at the top, even when its matching rows have the same IDs.
                // Keep the search field and ScrollViewReader outside this identity change.
                .id(cleanQuery)
                .accessibilityIdentifier("foodList")
                .onChange(of: store.lastAddedID) { _, value in
                    guard let value else { return }
                    let source = store.entries.first(where: { $0.id == value })?.sourceType
                    let cameFromScan = ["aiPhoto", "aiVoice", "barcode"].contains(source)
                    if revealNextAddedEntry || cameFromScan {
                        revealNextAddedEntry = false
                        showLogged()
                        if primeSearchAfterReveal {
                            searchPrimedOnHome = true
                            searching = true
                        }
                    }
                    primeSearchAfterReveal = false
                    guard !addMode || listMode == .logged, cleanQuery.isEmpty else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation { proxy.scrollTo(value, anchor: .bottom) }
                    }
                }
            }
            .clipped()
            // The list owns only the space above the footer; rows cannot draw below it.
            bottomBar
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("loggingFooter")
            }
            .background(Color.caveBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: drawerPresented, onDismiss: {
                if focusSearchAfterDismiss {
                    focusSearchAfterDismiss = false
                    if addMode { searching = true }
                }
            }) {
                drawerContent
            }
            .task(id: cleanQuery) {
                await search.search(cleanQuery)
            }
            .task {
                guard !openedInitially else { return }
                openedInitially = true
                #if DEBUG && targetEnvironment(simulator)
                if ProgressPreferences.isPreview && ProcessInfo.processInfo.arguments.contains("--progress-open") {
                    sheet = .progress
                    return
                }
                #endif
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
                // Typing into the field left ready on Home continues in add mode, so Clear returns to the pills.
                if !value.isEmpty, !addMode {
                    searchPrimedOnHome = false
                    addMode = true
                    listMode = .quickAdd
                }
            }
            // Search, voice, meal scan, or barcode on Today retires Home's Quick Add picks for the day.
            .onChange(of: addMode) { _, adding in if adding { retireHomeQuickAdd() } }
            .onChange(of: sheet?.id) { _, id in
                if ["photo", "voice", "barcode"].contains(id) { retireHomeQuickAdd() }
            }
            .onChange(of: searching) { _, focused in
                if !focused { searchPrimedOnHome = false }
                else if !addMode && !searchPrimedOnHome { enterAddMode() }
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
                    // Home's Quick Add picks follow the time of day; add mode keeps its rows stable.
                    if !addMode { refreshSuggestions() }
                }
            }
            .task(id: readyToAskForReminders) { if readyToAskForReminders { await askForRemindersWhenIdle() } }
            .onChange(of: store.lastAddedID) { _, id in
                guard let id, let entry = store.entries.first(where: { $0.id == id }),
                      ReviewPrompt.isMoment(entriesThatDay: store.dayEntries(entry.timestamp).count) else { return }
                if ReviewPrompt.isDueNow { reviewMomentPending = true }
            }
            .task(id: readyToAskHowItsGoing) { if readyToAskHowItsGoing { await askHowItsGoingWhenIdle() } }
            .alert("Cave Cals good?", isPresented: $askingHowItsGoing) {
                // Alert buttons may skip the haptic button style, so they play their own feel.
                Button("Not really") { Haptics.play(.tap); afterAlert { offeringFeedback = true } }.hapticFeel(.none)
                Button("Yes! Me like") { Haptics.play(.tap); afterAlert { requestReview() } }.hapticFeel(.none)
            }
            .alert("Help fix cave?", isPresented: $offeringFeedback) {
                Button("Not now", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
                Button("Send Feedback") { Haptics.play(.tap); openURL(CaveCalsLinks.feedback) }.hapticFeel(.none)
            } message: {
                Text("We want Cave Cals to get better. Tell us what’s not working.")
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
            Button { sheet = .progress } label: {
                Image("CaveProgress").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 25, height: 25).frame(width: 44, height: 44)
            }.accessibilityLabel("Progress").accessibilityIdentifier("progress")
            Button { sheet = .settings } label: {
                CaveIcon(.gear, size: 26).frame(width: 44, height: 44)
            }.accessibilityLabel("Settings").accessibilityIdentifier("appSettings")
        }
        .frame(height: 44)
        .padding(.horizontal, 20).padding(.top, 8)
        DailySummaryCard(day: selected, calories: store.total(selected), calorieGoal: store.goal(selected),
                         macros: store.tracksMacros ? MacroSummary(store.dayEntries(selected).map(EntryDraft.init)) : nil,
                         macroGoals: store.macroGoals(selected), isVisible: sheet == nil, shown: $summaryFigures)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        if !store.dayEntries(selected).isEmpty {
            Text(Calendar.current.isDate(selected, inSameDayAs: today) ? "Today" : monthDayLabel(selected))
                .font(.cave(.subheadline).bold()).foregroundStyle(Color.caveOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("homeLogHeader")
        }
    }

    @ViewBuilder private var addModeHeader: some View {
        HStack(spacing: 6) {
            // Same as the empty-search Cancel: back to home.
            Button { exitAddMode() } label: {
                CaveIcon(.chevronLeft, size: 20).foregroundStyle(Color.caveOrange)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }.hapticButtonStyle(.plain)
                .accessibilityLabel("Back").accessibilityIdentifier("addModeBack")
            foodListPicker
        }
        .padding(.leading, 10).padding(.trailing, 20).padding(.top, 6).padding(.bottom, 6)
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
        PillRowLayout {
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
            .padding(.horizontal, 10)
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
        .hapticButtonStyle(.plain)
        .accessibilityLabel(mode == .logged ? "Logged, \(title)" : title)
        .accessibilityIdentifier(mode == .logged ? "Logged" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .hapticFeel(.selection)
    }
    @discardableResult private func openPendingAction() -> Bool {
        guard let request = actionRouter.consume() else { return false }
        openedInitially = true
        focusSearchAfterDismiss = false
        // External logging always starts today, even if a past day was selected.
        selected = Date()
        today = selected
        searching = false
        query = ""
        // Starting to log from a widget or shortcut means today isn't done after all.
        if request.action != nil { store.reopenDay(today) }
        switch request.action {
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
            let dismissingSheet = sheet != nil
            openSearch(autofocus: true)
            if dismissingSheet {
                searching = false
                focusSearchAfterDismiss = true
            }
        case nil:
            openSearch()
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
        case .progress: ProgressScreen()
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
            if Double(cleanQuery) == nil, QuickEntryText.parse(cleanQuery)?.name.isEmpty != true {
            Text("Results").font(.cave(.caption2)).foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 16)
            }
            let local = localSearchFoods
            // History always leads, followed by saved meals, built-in foods, then API matches.
            ForEach(local) { food in
                let draft = store.applyingCommonDefault(to: food.draft)
                FoodRow(name: draft.name, calories: draft.calories, detail: draft.servingDescription,
                        add: { addFromSearch(draft) }, edit: { edit(draft, revealAfterSave: true) })
            }
            ForEach(store.meals.filter { normalizedFoodName($0.name).contains(normalizedFoodName(cleanQuery)) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { meal in
                FoodRow(name: meal.name, calories: meal.calories, add: {
                    revealNextAddedEntry = true
                    primeSearchAfterReveal = true
                    if !store.addMeal(meal, date: loggingDate) {
                        revealNextAddedEntry = false
                        primeSearchAfterReveal = false
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
    /// The day's log sits back a little so the totals above lead.
    private static let homeLogOpacity = 0.8
    @ViewBuilder private var loggedRows: some View {
            if store.dayEntries(selected).isEmpty {
                Text(Calendar.current.isDateInToday(selected)
                     ? "No log yet."
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
                        .opacity(Self.homeLogOpacity)
                    }
                    .hapticButtonStyle(.plain).id(entry.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .caveCardRow(opacity: Self.homeLogOpacity)
                    .accessibilityIdentifier("entry-\(entry.id)")
                    .accessibilityLabel("\(entry.name.isEmpty ? "Entry" : entry.name), \(entry.totalCalories.calorieText) calories, \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                    .contextMenu {
                        Button {
                            searching = false
                            sheet = .entry(EntryDraft(entry))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            duplicate(entry)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }.hapticFeel(.success)
                        Button(role: .destructive) {
                            store.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    // A full swipe deletes (rightmost action); Duplicate sits to its left.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) { store.delete(entry) }
                            .tint(.red)
                        Button("Duplicate") { duplicate(entry) }
                            .tint(.gray).hapticFeel(.success)
                    }
                }
            }.listSectionSeparator(.hidden)
            if showsHomeQuickAddSetting, Calendar.current.isDate(selected, inSameDayAs: today), store.showsHomeQuickAdd(on: today),
               !store.isFinished(today) {
                homeQuickAddRows
            }
    }
    /// Home's top Quick Add picks, so the day's first foods are one tap each. A pick leaves once added,
    /// unless it's usually logged more than once a day; the next suggestion takes its place.
    private var homeQuickAddPicks: [HistoricalFood] {
        let logged = Set(store.dayEntries(today).map(FoodHistory.foodID))
        return Array(suggestedFoods.filter { food in
            food.id == settlingHomeQuickAddID || !logged.contains(food.id)
                || FoodHistory.expectsAnotherToday(foodID: food.id, entries: store.entries, date: Date())
        }.prefix(10))
    }
    /// Quick Start shows three rows; half of a fading fourth invites scrolling through the rest.
    private func quickStartHeight(rows count: Int) -> CGFloat {
        let rows = min(Double(count), 3.5)
        return CGFloat(rows) * quickStartRowHeight + 6 * CGFloat(max(0, Int(rows.rounded(.up)) - 1))
    }
    @ViewBuilder private var homeQuickAddRows: some View {
        let picks = homeQuickAddPicks
        if !picks.isEmpty {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    CaveIcon(.lightning, size: 15)
                    Text("Quick Start")
                }
                .font(.cave(.subheadline).bold()).foregroundStyle(Color.caveOrange)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("homeQuickAddHeader")
                Spacer(minLength: 8)
                // Lines up with the rows' + buttons; closes the picks for the rest of today.
                Button { withAnimation { store.dismissHomeQuickAdd(on: today) } } label: {
                    CaveIcon(.plus, size: 15).rotationEffect(.degrees(45)).frame(width: 44, height: 36)
                }.hapticButtonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel("Hide Quick Start for today").accessibilityIdentifier("dismissHomeQuickAdd")
            }
            .padding(.top, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 34, bottom: 0, trailing: 32))
            .listRowSeparator(.hidden)
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(picks) { food in
                        let draft = store.applyingCommonDefault(to: food.draft)
                        FoodRow(name: draft.name, calories: draft.calories, suggestionLayout: true, pinned: store.isPinned(food.id),
                                compact: true,
                                add: { addHomeQuickAdd(draft, foodID: food.id) },
                                edit: {
                                    store.markHomeQuickAddUsed(on: today)
                                    edit(draft, source: "suggestion", pinFoodID: food.id, revealAfterSave: true)
                                })
                            .padding(.leading, 14).padding(.trailing, 4)
                            .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: quickStartHeight(rows: picks.count))
            // Fade the peeking row instead of slicing through its text.
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: picks.count > 3 ? 0.84 : 1),
                                       .init(color: picks.count > 3 ? .clear : .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 28))
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("homeQuickStartList")
        }
    }
    /// Add mode's Today list: log something from today again, or edit a copy before adding it.
    @ViewBuilder private var repeatRows: some View {
        let entries = store.dayEntries(selected)
        if entries.isEmpty {
            Text(Calendar.current.isDateInToday(selected) ? "Nothing logged yet today." : "No food logged for this day.")
                .font(.cave(.body)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 16)
                .listRowSeparator(.hidden)
        } else {
            ForEach(entries) { entry in
                let draft = EntryDraft(entry)
                FoodRow(name: entry.foodDisplayName.isEmpty ? "\(entry.totalCalories.calorieText) calories" : entry.foodDisplayName,
                        calories: entry.totalCalories, suggestionLayout: true,
                        add: { revealNextAddedEntry = false; add(draft) },
                        edit: { edit(draft, revealAfterSave: false) })
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 28))
                    .caveCardRow()
            }
        }
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
                            }.hapticFeel(.success)
                            Button {
                                store.setPinned(!pinned, foodID: food.id)
                            } label: {
                                Label(pinned ? "Un-Pin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                            }
                            Button {
                                store.hideFromQuickAdd(foodID: food.id, name: draft.name)
                            } label: {
                                Label("Remove, No Add Often", systemImage: "eye.slash")
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
        .hapticButtonStyle(.borderedProminent)
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
            if weights.shouldPrompt(on: today), Calendar.current.isDateInToday(selected),
               !addMode, !searching, cleanQuery.isEmpty {
                weighInReminder
            }
            // Re-checked each minute so the card turns up at 6 pm without other activity.
            TimelineView(.everyMinute) { context in
                if offersFinishDay(at: context.date) { finishDayReminder }
            }
            VStack(spacing: 0) {
                if let toast = store.toast {
                    HStack {
                        Text(toast).font(.cave(.subheadline)).lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Undo") { store.undo() }.font(.cave(.subheadline).bold())
                            .frame(minHeight: 44)
                    }.padding(.horizontal, 20).background(Color.accentColor.opacity(0.1))
                        .accessibilityIdentifier("searchUndoBanner")
                }
                if todayIsDone {
                    dayDoneFooter.padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                // The typed-entry action sits directly above the search field, aligned with its magnifier.
                if !cleanQuery.isEmpty {
                    Group {
                        if let amount = Double(cleanQuery), amount >= 0, amount <= 100_000 {
                            FoodRow(name: "Add \(amount.calorieText) calories", calories: nil,
                                    add: { addFromSearch(EntryDraft(calories: amount)) },
                                    edit: { edit(EntryDraft(calories: amount), focusName: true, revealAfterSave: true) })
                        } else if let entry = QuickEntryText.parse(cleanQuery) {
                            // "pizza 300" or "300 cal pizza" logs a named entry in one tap.
                            let draft = EntryDraft(name: entry.name, calories: entry.calories)
                            FoodRow(name: entry.name.isEmpty ? "Add \(entry.calories.calorieText) calories"
                                        : "Add \"\(entry.name)\" · \(entry.calories.calorieText) calories", calories: nil,
                                    add: { addFromSearch(draft) },
                                    edit: { edit(draft, focusName: entry.name.isEmpty, revealAfterSave: true) })
                        } else if Double(cleanQuery) == nil {
                            manualSearchEntryButton
                        }
                    }
                    // Trailing matches the result rows so the pencil lines up with their (+) buttons.
                    .padding(.leading, 31).padding(.trailing, 20).padding(.top, 8).padding(.bottom, 8)
                }
                // Search shares the row with the capture shortcuts; focusing it (or typing) takes the full width.
                HStack(spacing: 4) {
                    HStack(spacing: 8) {
                        CaveIcon(.search, size: 20).foregroundStyle(.secondary)
                        TextField(searchExpanded ? "search food or enter cals" : "search / add", text: $query)
                            .focused($searching).submitLabel(.search).autocorrectionDisabled()
                            // Tapping the field left ready on Home opens add mode, as a first tap would.
                            .simultaneousGesture(TapGesture().onEnded {
                                if searchPrimedOnHome && cleanQuery.isEmpty {
                                    searchPrimedOnHome = false
                                    enterAddMode()
                                }
                            })
                            .accessibilityIdentifier("foodSearch")
                        // With text: "Clear" empties the field and stays in add mode. Empty: "Cancel" returns home.
                        if searchExpanded {
                            let clearing = !query.isEmpty
                            Button {
                                if clearing { query = "" } else { exitAddMode() }
                            } label: {
                                Text(clearing ? "Clear" : "Cancel")
                                    .font(.cave(.subheadline)).foregroundStyle(.red)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.hapticButtonStyle(.plain)
                            .accessibilityIdentifier(clearing ? "clearSearch" : "cancelAddMode")
                        }
                    }.padding(.horizontal, 12).frame(minHeight: 48)
                    .background(Color.caveBackground, in: RoundedRectangle(cornerRadius: 14))
                    if !searchExpanded {
                        entryShortcuts.transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.top, cleanQuery.isEmpty ? 12 : 4).padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.22), value: searchExpanded)
                }
            }.background(Color.caveSurface)
        }
    }
    private var weighInReminder: some View {
        reminderCard(glyph: .person, title: "Log today’s weight", navigates: true,
                     identifier: "weighInReminder", hint: "Opens today’s weigh-in", action: { sheet = .weighIn },
                     dismissLabel: "Hide weigh-in reminder for today", dismissIdentifier: "dismissWeighIn",
                     dismiss: { weights.dismissToday() })
    }
    /// Today is marked done eating: search and capture give way to `dayDoneFooter` until Reopen or another log.
    private var todayIsDone: Bool {
        Calendar.current.isDate(selected, inSameDayAs: today) && store.isFinished(today)
    }
    /// "Done eating for today" shows on Today from 6 pm, or earlier once the day reaches 90% of its calorie goal.
    private func offersFinishDay(at now: Date) -> Bool {
        guard showsFinishDaySetting, Calendar.current.isDate(selected, inSameDayAs: today),
              !addMode, !searching, cleanQuery.isEmpty, !store.dayEntries(today).isEmpty,
              !store.isFinished(today), !store.finishPromptHidden(on: today) else { return false }
        let nearGoal = store.goal(today).map { store.total(today) >= 0.9 * $0 } ?? false
        return Calendar.current.component(.hour, from: now) >= 18 || nearGoal
    }
    private var finishDayReminder: some View {
        reminderCard(glyph: .check, title: "Done eating for today", navigates: false,
                     identifier: "finishDay", hint: "Closes today’s log until you reopen it", feel: .success,
                     action: {
                         withAnimation(.easeInOut(duration: 0.22)) { store.finishDay() }
                         if ReviewPrompt.isDueNow { reviewMomentPending = true }
                     },
                     dismissLabel: "Hide done eating button for today", dismissIdentifier: "dismissFinishDay",
                     dismiss: { store.hideFinishPrompt(on: today) })
    }
    /// After a few days of logging, iOS's notification prompt appears on its own while Home is idle; reminders
    /// then start on (Settings → Reminders turns them off). There's no Home card for it.
    private var readyToAskForReminders: Bool {
        sheet == nil && !addMode && !searching && cleanQuery.isEmpty
            && !ProcessInfo.processInfo.arguments.contains { $0 == "--uitesting" || $0 == "--screenshots" }
            && LogReminders.shared.shouldOffer(entries: store.entries)
    }
    private func askForRemindersWhenIdle() async {
        // Let a count-up or sheet dismissal settle first.
        try? await Task.sleep(for: .seconds(1.5))
        guard readyToAskForReminders else { return }
        askedForRemindersThisSession = true
        await LogReminders.shared.requestPermission()
    }
    /// "Cave Cals good?" waits for the same idle Home as the reminder prompt, and never shares a
    /// session with it.
    private var readyToAskHowItsGoing: Bool {
        reviewMomentPending && ReviewPrompt.isAllowed && !askedForRemindersThisSession && !readyToAskForReminders
            && sheet == nil && !addMode && !searching && cleanQuery.isEmpty
    }
    private func askHowItsGoingWhenIdle() async {
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled, readyToAskHowItsGoing, ReviewPrompt.isDueNow else { return }
        reviewMomentPending = false
        ReviewPrompt.recordAsked()
        askingHowItsGoing = true
    }
    /// Lets the alert finish closing before the next one (or Apple's rating prompt) appears.
    private func afterAlert(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }
    private var dayDoneFooter: some View {
        HStack(spacing: 10) {
            CaveIcon(.check, size: 20).foregroundStyle(Color.caveOrange).accessibilityHidden(true)
            Text("Day done. Cave closed.").font(.cave(.body))
                .accessibilityLabel("Done eating for today")
            Spacer(minLength: 8)
            Button { withAnimation(.easeInOut(duration: 0.22)) { store.reopenDay(today) } } label: {
                Text("Reopen").font(.cave(.subheadline)).foregroundStyle(Color.caveOrange)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.hapticButtonStyle(.plain)
                .accessibilityLabel("Resume logging today").accessibilityIdentifier("reopenDay")
        }
        .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 48)
        .accessibilityElement(children: .contain).accessibilityIdentifier("dayDone")
    }
    /// Sits on the page above the footer as its own outlined card; a chevron marks one that opens something.
    private func reminderCard(glyph: CaveGlyph, title: String, navigates: Bool, identifier: String, hint: String,
                              feel: HapticFeel = .tap, action: @escaping () -> Void, dismissLabel: String, dismissIdentifier: String,
                              dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 10) {
                    CaveIcon(glyph, size: 20)
                    Text(title).font(.cave(.subheadline).weight(.semibold))
                    Spacer(minLength: 8)
                    if navigates { CaveIcon(.chevronRight, size: 16) }
                }
                .foregroundStyle(Color.caveOrange)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.caveOrange.opacity(0.55), lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.hapticButtonStyle(.plain).hapticFeel(feel)
                .accessibilityIdentifier(identifier)
                .accessibilityHint(hint)
            Button(action: dismiss) {
                CaveIcon(.plus, size: 15).rotationEffect(.degrees(45)).frame(width: 44, height: 44)
            }.hapticButtonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(dismissLabel).accessibilityIdentifier(dismissIdentifier)
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.top, 6).padding(.bottom, 8)
        .background(Color.caveBackground)
    }
    private var searchExpanded: Bool { addMode || !query.isEmpty || searching }
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
                // Same (+) as the result rows; it opens the editor to enter calories.
                CaveIcon(.plus, size: 17)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain)
        .accessibilityLabel("Add \"\(cleanQuery)\", enter calories")
        .accessibilityIdentifier("manualSearchEntry")
    }
    private func addHomeQuickAdd(_ draft: EntryDraft, foodID: String) {
        revealNextAddedEntry = false
        store.markHomeQuickAddUsed(on: today)
        settlingHomeQuickAddID = foodID
        guard add(draft, source: "suggestion") else { settlingHomeQuickAddID = nil; return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard settlingHomeQuickAddID == foodID else { return }
            withAnimation(.easeInOut(duration: 0.25)) { settlingHomeQuickAddID = nil }
        }
    }
    /// Backfilling another day leaves today's picks alone.
    private func retireHomeQuickAdd() {
        guard Calendar.current.isDate(selected, inSameDayAs: today) else { return }
        store.dismissHomeQuickAdd(on: today)
    }
    /// Only reached by tapping the search field, which feels like a button.
    private func enterAddMode() {
        Haptics.play(.tap)
        addMode = true
        listMode = .quickAdd
        refreshSuggestions()
    }
    private func exitAddMode() {
        query = ""
        searching = false
        addMode = false
        refreshSuggestions()
    }
    /// Returns to the home screen (totals and the day's log).
    private func openSearch(autofocus: Bool = false) {
        searching = autofocus
        addMode = autofocus
        listMode = autofocus ? .quickAdd : .logged
        query = ""
        // Keep rows stable while logging several foods and showing confirmation.
        refreshSuggestions()
        sheet = nil
    }
    private func resetToday() { today = Date(); selected = today }
    private func showLogged() {
        query = ""
        searching = false
        addMode = false
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
        primeSearchAfterReveal = true
        if !add(input) {
            revealNextAddedEntry = false
            primeSearchAfterReveal = false
        }
    }
    @discardableResult private func add(_ input: EntryDraft, source: String? = nil) -> Bool {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        return store.add([draft])
    }
    /// Logs a fresh copy of an entry on the selected day at the current time.
    private func duplicate(_ entry: CalorieEntry) {
        revealNextAddedEntry = false
        add(EntryDraft(entry))
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
    /// Home's Quick Start: smaller one-line text and + circle, still with 44-point taps.
    var compact = false
    let add: () -> Void
    let edit: () -> Void
    private var rowHeight: CGFloat { compact ? 44 : suggestionLayout ? 52 : 48 }
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
                            Text(name).font((compact ? Font.custom("Schoolbell-Regular", size: 16, relativeTo: .subheadline) : Font.cave(.subheadline)).weight(confirming ? .bold : .regular))
                                .foregroundStyle(confirming ? Color.accentColor : Color.primary).lineLimit(compact ? 1 : 2)
                        }
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.cave(.caption)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        if suggestionLayout, store.tracksMacros, let macros { MacroLine(summary: macros) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    // Wrapped names grow the card instead of touching its edges; one-line rows keep the 52-pt height.
                    .padding(.vertical, compact ? 8 : suggestionLayout ? 12 : 0)
                    if suggestionLayout, let calories {
                        Text(calories.calorieText).font((compact ? Font.custom("Schoolbell-Regular", size: 17, relativeTo: .body) : Font.cave(.body)).weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 6)
                    }
                }.frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }.hapticButtonStyle(.plain).foregroundStyle(.primary).accessibilityLabel(added ? "Added \(actionName)" : "Edit \(actionName)")
                .accessibilityIdentifier("foodDetails-\(actionName)")
                .accessibilityValue(rowValue)
                .disabled(added)
            Button(action: edit) { CaveIcon(.pencil, size: compact ? 19 : 22).frame(width: 44, height: rowHeight) }
                .hapticButtonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Edit \(actionName)")
                .disabled(added)
            Button(action: addWithFeedback) {
                if added {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: rowHeight)
                } else {
                    FlipAddIcon(angle: rotation, showCheckWithoutMotion: reduceMotion && confirming, diameter: compact ? 29 : 34)
                        .frame(width: 44, height: rowHeight)
                }
            }.hapticButtonStyle(.borderless).hapticFeel(.none)
                .accessibilityLabel(added ? "Added \(actionName)" : "Add \(actionName)")
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
        Haptics.play(.success)
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
    var diameter: CGFloat = 34
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    var body: some View {
        let showsCheck = showCheckWithoutMotion || (angle >= 90 && angle < 270)
        ZStack {
            CaveIcon(.plus, size: diameter / 2).opacity(showsCheck ? 0 : 1)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .rotation3DEffect(.degrees(showCheckWithoutMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(showsCheck ? 1 : 0)
        }
        .foregroundStyle(showsCheck ? Color.primary : Color.white)
        .frame(width: diameter, height: diameter).background(showsCheck ? Color.clear : Color.accentColor, in: Circle())
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

/// Sizes each pill to its label, then shares any leftover width evenly, so a longer label
/// ("Quick Add", "Sept. 22nd") gets a wider pill. Labels shrink via their scale factor if space runs short.
private struct PillRowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = ideal.map(\.height).max() ?? 0
        return CGSize(width: proposal.width ?? ideal.reduce(0) { $0 + $1.width }, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = ideal.reduce(0, +)
        // Extra space is shared evenly; a shortfall shrinks pills in proportion to their width.
        let widths = total <= bounds.width
            ? ideal.map { $0 + (bounds.width - total) / CGFloat(subviews.count) }
            : ideal.map { $0 * bounds.width / total }
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
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
            }.hapticButtonStyle(.borderless).hapticFeel(.selection).accessibilityLabel("Previous day")
            Button(action: openCalendar) {
                HStack(alignment: .firstTextBaseline, spacing: relativeDayName == nil ? 6 : 12) {
                    Text(relativeDayName ?? fullDateLabel)
                        .font(.custom("Schoolbell-Regular", size: 18, relativeTo: .subheadline))
                    if relativeDayName != nil {
                        Text(fullDateLabel)
                            .font(.custom("Schoolbell-Regular", size: 13, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                // Today's wider label sits closer to the chevrons.
                .padding(.horizontal, relativeDayName == nil ? 12 : 2).frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }.hapticButtonStyle(.plain).accessibilityIdentifier("selectedDate")
                .accessibilityHint("Open calorie calendar")
            Button { move(1) } label: {
                CaveIcon(.chevronRight, size: 22).frame(width: 44, height: 44)
            }.hapticButtonStyle(.borderless).hapticFeel(.selection).accessibilityLabel("Next day")
                .disabled(Calendar.current.startOfDay(for: selected) >= Calendar.current.startOfDay(for: today))
        }
    }
    /// Only the current day gets the "Today" label beside its full date.
    private var relativeDayName: String? {
        Calendar.current.isDate(selected, inSameDayAs: today) ? "Today" : nil
    }
    private var fullDateLabel: String {
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
                        Button("Today") { withAnimation { proxy.scrollTo(monthStart(today), anchor: .top) } }.hapticButtonStyle(.automatic)
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) }
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
                    }.hapticButtonStyle(.plain).hapticFeel(.selection).disabled(future)
                        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(total.calorieText) calories")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}
