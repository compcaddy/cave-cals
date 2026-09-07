import SwiftUI

private struct GuideArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let tip = CGPoint(x: rect.midX, y: rect.maxY - 1)
            path.move(to: CGPoint(x: rect.midX - 4, y: rect.minY + 1))
            path.addQuadCurve(to: tip, control: CGPoint(x: rect.midX + 5, y: rect.midY))
            path.move(to: CGPoint(x: tip.x - 5, y: tip.y - 6))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: tip.x + 5, y: tip.y - 6))
        }
    }
}

enum MainSheet: Identifiable {
    case entry(EntryDraft), searchEntry(EntryDraft), namedEntry(EntryDraft), quickEntry(EntryDraft), settings, barcode(Date), meal(UUID, Date), photo, voice, search, calendar
    var id: String {
        switch self {
        case .entry(let draft): "entry-\(draft.id)"
        case .searchEntry(let draft): "search-entry-\(draft.id)"
        case .namedEntry(let draft): "named-entry-\(draft.id)"
        case .quickEntry(let draft): "quick-entry-\(draft.id)"
        case .settings: "settings"
        case .barcode: "barcode"
        case .meal(let id, _): "meal-\(id)"
        case .photo: "photo"
        case .voice: "voice"
        case .search: "search"
        case .calendar: "calendar"
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(LoggingActionRouter.self) private var actionRouter
    @Environment(\.scenePhase) private var phase
    @State private var selected = Date()
    @State private var today = Date()
    @State private var query = ""
    @State private var search = FoodSearchState()
    @State private var sheet: MainSheet?
    @State private var openedInitially = false
    @State private var wasBackgrounded = false
    @FocusState private var searching: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var summarySize = 68.0
    private var loggingDate: Date { Day.loggingDate(selected) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySelector(selected: $selected, today: today, openCalendar: { sheet = .calendar })
                    .padding(.horizontal, 20).padding(.top, 8)
                summary.padding(.horizontal, 20)
                Divider().padding(.horizontal, 20)
            ScrollViewReader { proxy in
                List {
                        Section {
                            ForEach(store.dayEntries(selected)) { entry in
                                Button { searching = false; sheet = .entry(EntryDraft(entry)) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        Text(entry.timestamp, format: .dateTime.hour().minute()).font(.custom("Schoolbell-Regular", size: 14, relativeTo: .caption)).foregroundStyle(.secondary).frame(width: 67, alignment: .leading)
                                        Text(entry.name).font(.custom("Schoolbell-Regular", size: 20, relativeTo: .body)).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.totalCalories.calorieText)
                                            .font(.custom("Schoolbell-Regular", size: 20, relativeTo: .body)).foregroundStyle(.primary)
                                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                                    }.padding(.horizontal, 8).padding(.vertical, 14).frame(minHeight: 48).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(entry.id)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(.separator)).frame(height: 0.5).allowsHitTesting(false)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                                .accessibilityIdentifier("entry-\(entry.id)")
                                .accessibilityLabel("\(entry.name.isEmpty ? "Entry" : entry.name), \(entry.totalCalories.calorieText) calories, \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                                .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { store.delete(entry) } }
                            }
                        }.listSectionSeparator(.hidden)
                }
                .listStyle(.plain).scrollDismissesKeyboard(.interactively)
                .onChange(of: store.lastAddedID) { _, value in
                    guard let value else { return }
                    query = ""; searching = false
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
            .task(id: cleanQuery) { await search.search(cleanQuery) }
            .task {
                guard !openedInitially else { return }
                openedInitially = true
                if !openPendingAction() { openSearch() }
            }
            .onChange(of: actionRouter.pending) { _, request in
                if request != nil { _ = openPendingAction() }
            }
            .onChange(of: phase) { _, value in
                if value == .background { wasBackgrounded = true }
                if value == .active {
                    resetToday()
                    if !openPendingAction(), wasBackgrounded, sheet == nil { openSearch() }
                    wasBackgrounded = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in resetToday() }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                if !Calendar.current.isDate(now, inSameDayAs: today) { resetToday() }
            }
        }
    }
    @discardableResult private func openPendingAction() -> Bool {
        guard let action = actionRouter.consume() else { return false }
        openedInitially = true
        // External logging always starts today, even if a past day was selected.
        selected = Date()
        today = selected
        searching = false
        query = ""
        switch action {
        case .barcode: sheet = .barcode(loggingDate)
        case .voice: sheet = .voice
        case .image: sheet = .photo
        case .add: openSearch()
        }
        return true
    }
    // The route changes the contents, not the presentation identity. Moving from
    // search to an editor keeps the existing drawer on screen.
    private var drawerPresented: Binding<Bool> {
        Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
    }
    @ViewBuilder private var drawerContent: some View {
        switch sheet {
        case .entry(let draft):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true).id(draft.id)
        case .searchEntry(let draft):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true, onCancel: { sheet = .search }).id(draft.id)
        case .namedEntry(let draft):
            EntryEditorSheet(draft: draft, focusCaloriesOnOpen: true, blankCaloriesOnOpen: true, onCancel: { sheet = .search }).id(draft.id)
        case .quickEntry(let draft):
            EntryEditorSheet(draft: draft, focusNameOnOpen: true, onCancel: { sheet = .search }).id(draft.id)
        case .settings: SettingsView()
        case .barcode(let date): BarcodeSheet(date: date)
        case .meal(let id, let date): MealAddSheet(mealID: id, date: date)
        case .photo: AIInputSheet(mode: .photo, date: loggingDate).id("photo")
        case .voice: AIInputSheet(mode: .voice, date: loggingDate).id("voice")
        case .search: searchDrawer
        case .calendar: CalorieCalendarSheet(selected: $selected, today: today)
        case nil: EmptyView()
        }
    }
    private var summary: some View {
        let total = store.total(selected), goal = store.goal(selected)
        return VStack(alignment: .center, spacing: 10) {
            VStack(spacing: 2) {
                Text(total.calorieText)
                    .font(.custom("Schoolbell-Regular", fixedSize: summarySize))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let goal {
                    Text("/ \(goal.calorieText)").font(.custom("Schoolbell-Regular", size: 20, relativeTo: .body)).foregroundStyle(.secondary)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(goal.map { "\(total.calorieText) of \($0.calorieText) calories" } ?? "\(total.calorieText) calories")
                .accessibilityIdentifier("calorieSummary")
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 20)
    }
    private var searchSection: some View {
        Group {
        if Double(cleanQuery) == nil {
            Button {
                searching = false
                sheet = .namedEntry(EntryDraft(name: cleanQuery, timestamp: loggingDate))
            } label: {
                HStack {
                    Text("Add \(cleanQuery)").font(.cave(.subheadline)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CaveIcon(.pencil, size: 22).font(.cave(.body).weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.accentColor, in: Circle())
                        .frame(width: 44, height: 48)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Add \(cleanQuery), enter calories")
        }
        Section("Results") {
            ForEach(CommonFoods.search(cleanQuery)) { food in
                let draft = store.applyingCommonDefault(to: food.draft)
                FoodRow(name: food.name, calories: draft.calories, detail: draft.servingDescription,
                        add: { add(draft) }, edit: { edit(draft) })
            }
            if let amount = Double(cleanQuery), amount >= 0, amount <= 100_000 {
                FoodRow(name: "Add \(amount.calorieText) calories", calories: nil,
                        add: { add(EntryDraft(calories: amount)) }, edit: { edit(EntryDraft(calories: amount), focusName: true) })
            }
            let local = FoodHistory.search(cleanQuery, entries: store.entries)
            ForEach(local) { food in
                let draft = store.applyingCommonDefault(to: food.draft)
                FoodRow(name: draft.name, calories: draft.calories, add: { add(draft) }, edit: { edit(draft) })
            }
            ForEach(store.meals.filter { normalizedFoodName($0.name).contains(normalizedFoodName(cleanQuery)) }) { meal in
                FoodRow(name: meal.name, calories: meal.calories, meal: true, add: {
                    if store.addMeal(meal, date: loggingDate) { closeSearch() }
                }, edit: { searching = false; sheet = .meal(meal.id, loggingDate) })
            }
            ForEach(search.results.filter { result in !local.contains { $0.draft.externalID == result.id } }) { result in
                FoodRow(name: result.draft.name, calories: result.calories, detail: result.servingDescription,
                        add: { add(result.draft) }, edit: { edit(result.draft) })
            }
            if search.loading { HStack { ProgressView(); Text("Searching foods…").foregroundStyle(.secondary) } }
            if let message = search.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
            if !search.results.isEmpty { Text("Food data: Open Food Facts · ODbL").font(.cave(.caption2)).foregroundStyle(.secondary) }
        }
        }
    }
    private var emptyDayGuide: some View {
        // Match the footer's columns so arrows stay centered over their actions.
        HStack(alignment: .bottom, spacing: 10) {
            Color.clear.frame(width: 44, height: 1)
            guideLabel("Scan a\nbarcode").frame(width: 44)
            guideLabel("Voice\nLog").frame(width: 44)
            guideLabel("Meal\nScan").frame(width: 44)
            guideLabel("Search/\nManual Add")
                .frame(maxWidth: .infinity).padding(.leading, 8)
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 2)
        .background(Color(.systemBackground))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func guideLabel(_ title: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.custom("Schoolbell-Regular", size: 16, relativeTo: .footnote))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            GuideArrow().stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 25)
        }
        .foregroundStyle(.secondary)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let toast = store.toast {
                HStack {
                    Text(toast).font(.cave(.subheadline)).lineLimit(2)
                    Spacer(minLength: 10)
                    Button("Undo") { store.undo() }.font(.cave(.subheadline).bold()).frame(minHeight: 44)
                }.padding(.horizontal, 20).background(Color.accentColor.opacity(0.1)).accessibilityIdentifier("undoBanner")
            }
            if store.dayEntries(selected).isEmpty { emptyDayGuide }
            HStack(spacing: 10) {
                Button { sheet = .settings } label: {
                    CaveIcon(.gear, size: 22).font(.cave(.title2)).frame(width: 44, height: 48)
                }.accessibilityLabel("Settings")
                Button { sheet = .barcode(loggingDate) } label: {
                    CaveIcon(.barcode, size: 28).frame(width: 44, height: 48)
                }.accessibilityLabel("Scan barcode")
                Button { sheet = .voice } label: {
                    CaveIcon(.voice, size: 28).frame(width: 44, height: 48)
                }.accessibilityLabel("Voice entry")
                Button { sheet = .photo } label: {
                    CaveIcon(.meal, size: 28).frame(width: 44, height: 48)
                }.accessibilityLabel("Photo entry")
                Button(action: openSearch) {
                    CaveSearchAddIcon(size: 22).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("openSearch")
                    .accessibilityLabel("Search or add food")
                    .padding(.leading, 8)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.background(.bar)
    }
    private var searchDrawer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    CaveIcon(.search, size: 20).foregroundStyle(.secondary)
                    DrawerSearchField(text: $query)
                }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                Button(action: closeSearch) {
                    CaveIcon(.plus, size: 19).rotationEffect(.degrees(45)).font(.cave(.body).weight(.bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.red, in: Circle())
                        .frame(width: 44, height: 48)
                }.accessibilityLabel("Close search")
            }.padding(.horizontal, 16).padding(.top, 24)
            List {
                if cleanQuery.isEmpty {
                    let suggestions = FoodHistory.suggestions(entries: store.entries, date: loggingDate)
                    if suggestions.isEmpty {
                        Text("CaveCal will give you smart suggestions once it learns your eating habits.")
                            .font(.custom("Schoolbell-Regular", size: 19, relativeTo: .body)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(suggestions) { food in
                                let draft = store.applyingCommonDefault(to: food.draft)
                                FoodRow(name: draft.name, calories: draft.calories, suggestionLayout: true,
                                        add: { add(draft, source: "suggestion") },
                                        edit: { edit(draft, source: "suggestion") })
                                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                            }
                        } header: {
                            Text("Suggestions").font(.cave(.caption)).textCase(nil).padding(.vertical, 2)
                        }
                    }
                } else { searchSection }
            }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
                .contentMargins(.top, 0, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, 44)
                .environment(\.defaultMinListHeaderHeight, 20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(stride(from: 25, through: 1000, by: 25)), id: \.self) { amount in
                            Button {
                                searching = false
                                sheet = .quickEntry(EntryDraft(calories: Double(amount), timestamp: loggingDate))
                            } label: {
                                Text(amount.formatted()).font(.cave(.subheadline).weight(.semibold)).monospacedDigit()
                                    .padding(.horizontal, 16).frame(minWidth: 60, minHeight: 44)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }.accessibilityLabel("Add \(amount) calories")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }.accessibilityIdentifier("quickCalorieAmounts")
            HStack {
                Spacer()
                Button { searching = false; sheet = .barcode(loggingDate) } label: {
                    CaveIcon(.barcode, size: 28).frame(width: 60, height: 48)
                }.accessibilityLabel("Scan barcode")
                Spacer()
                Button { searching = false; sheet = .voice } label: {
                    CaveIcon(.voice, size: 28).frame(width: 60, height: 48)
                }.accessibilityLabel("Voice entry")
                Spacer()
                Button { searching = false; sheet = .photo } label: {
                    CaveIcon(.meal, size: 28).frame(width: 60, height: 48)
                }.accessibilityLabel("Photo entry")
                Spacer()
            }.padding(.vertical, 8)
            }.background(.bar)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onDisappear { searching = false }
    }
    private func openSearch() { query = ""; sheet = .search }
    private func closeSearch() { searching = false; query = ""; sheet = nil }
    private func resetToday() { today = Date(); selected = today }
    private func add(_ input: EntryDraft, source: String? = nil) {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        if store.add([draft]) { closeSearch() }
    }
    private func edit(_ input: EntryDraft, source: String? = nil, focusName: Bool = false) {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        searching = false; sheet = focusName ? .quickEntry(draft) : .searchEntry(draft)
    }
}

private struct DrawerSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Search food or enter calories…", text: $text)
            .focused($focused).submitLabel(.search).autocorrectionDisabled()
            .accessibilityIdentifier("foodSearch")
            .task {
                // Focus belongs to the presented view, after the drawer enters the window.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                focused = true
            }
            .onDisappear { focused = false }
    }
}

struct FoodRow: View {
    let name: String
    var calories: Double?
    var detail: String? = nil
    var meal = false
    var suggestionLayout = false
    let add: () -> Void
    let edit: () -> Void
    private var actionName: String { calories == nil && name.hasPrefix("Add ") ? String(name.dropFirst(4)) : name }
    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if meal { CaveIcon(.meal, size: 18) }
                            Text("\(name)\(suggestionLayout ? "" : (calories.map { " · \($0.calorieText) cal" } ?? ""))").font(.cave(.subheadline)).lineLimit(2)
                        }
                        if let detail, !detail.isEmpty { Text(detail).font(.cave(.caption)).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if suggestionLayout, let calories {
                        Text(calories.calorieText).font(.cave(.body).weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 6)
                    }
                }.frame(maxWidth: .infinity, minHeight: suggestionLayout ? 64 : 48, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("Add \(actionName)")
            Button(action: edit) { CaveIcon(.pencil, size: 22).frame(width: 44, height: suggestionLayout ? 64 : 48) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Edit \(actionName)")
            Button(action: add) {
                CaveIcon(.plus, size: 17).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Color.accentColor, in: Circle())
                    .frame(width: 44, height: suggestionLayout ? 64 : 48)
            }.buttonStyle(.borderless).accessibilityLabel("Add \(actionName)")
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
            }.buttonStyle(.borderless).accessibilityLabel("Previous day")
            Button(action: openCalendar) {
                Text(dateLabel).font(.custom("Schoolbell-Regular", size: 18, relativeTo: .subheadline))
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        let months = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sept.", "Oct.", "Nov.", "Dec."]
        let month = months[Calendar.current.component(.month, from: selected) - 1]
        let day = Calendar.current.component(.day, from: selected)
        let ordinal = NumberFormatter()
        ordinal.locale = Locale(identifier: "en_US")
        ordinal.numberStyle = .ordinal
        return "\(formatter.string(from: selected)), \(month) \(ordinal.string(from: NSNumber(value: day)) ?? String(day))"
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
            .mapValues { $0.reduce(0) { $0 + $1.totalCalories } }
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
