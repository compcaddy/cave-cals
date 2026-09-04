import SwiftUI

enum MainSheet: Identifiable {
    case entry(EntryDraft), settings, barcode(Date), meal(UUID, Date), photo, voice, search
    var id: String {
        switch self {
        case .entry(let draft): "entry-\(draft.id)"
        case .settings: "settings"
        case .barcode: "barcode"
        case .meal(let id, _): "meal-\(id)"
        case .photo: "photo"
        case .voice: "voice"
        case .search: "search"
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var selected = Date()
    @State private var today = Date()
    @State private var query = ""
    @State private var search = FoodSearchState()
    @State private var sheet: MainSheet?
    @State private var openedInitially = false
    @State private var wasBackgrounded = false
    @FocusState private var searching: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var summarySize = 54.0
    private var loggingDate: Date { Day.loggingDate(selected) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        DaySelector(selected: $selected, today: today)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                            .listRowSeparator(.hidden)
                        summary.listRowSeparator(.hidden)
                    }.listRowBackground(Color.clear)
                        Section {
                            if store.dayEntries(selected).isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "text.badge.plus").font(.title2)
                                    Text("Nothing logged yet").font(.headline)
                                    Text("Search a food or enter calories below.").font(.subheadline)
                                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30).listRowSeparator(.hidden)
                            }
                            ForEach(store.dayEntries(selected)) { entry in
                                Button { searching = false; sheet = .entry(EntryDraft(entry)) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        Text(entry.timestamp, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary).frame(width: 67, alignment: .leading)
                                        Text(entry.name.isEmpty ? "\(entry.totalCalories.calorieText) calories" : entry.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                        if !entry.name.isEmpty { Text(entry.totalCalories.calorieText).fontWeight(.semibold).foregroundStyle(.primary).monospacedDigit() }
                                    }.padding(.vertical, 7).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(entry.id)
                                .accessibilityIdentifier("entry-\(entry.id)")
                                .accessibilityLabel("\(entry.name.isEmpty ? "Entry" : entry.name), \(entry.totalCalories.calorieText) calories, \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                                .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { store.delete(entry) } }
                            }
                        }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { searching = false; sheet = .settings } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .entry(let draft): EntryEditorSheet(draft: draft)
                case .settings: SettingsView()
                case .barcode(let date): BarcodeSheet(date: date)
                case .meal(let id, let date): MealAddSheet(mealID: id, date: date)
                case .photo: PhotoCaptureSheet()
                case .voice: VoicePreviewSheet()
                case .search: searchDrawer
                }
            }
            .task(id: cleanQuery) { await search.search(cleanQuery) }
            .task {
                guard !openedInitially else { return }
                openedInitially = true
                openSearch()
            }
            .onChange(of: phase) { _, value in
                if value == .background { wasBackgrounded = true }
                if value == .active {
                    resetToday()
                    if wasBackgrounded, sheet == nil { openSearch() }
                    wasBackgrounded = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in resetToday() }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                if !Calendar.current.isDate(now, inSameDayAs: today) { resetToday() }
            }
        }
    }
    private var summary: some View {
        let total = store.total(selected), goal = store.goal(selected)
        return VStack(alignment: .center, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(total.calorieText).font(.system(size: summarySize, weight: .semibold, design: .rounded))
                    if let goal { Text("/ \(goal.calorieText)").font(.title2).foregroundStyle(.secondary) }
                }
                VStack(alignment: .center) {
                    Text(total.calorieText).font(.largeTitle.bold())
                    if let goal { Text("of \(goal.calorieText)").foregroundStyle(.secondary) }
                }
            }.monospacedDigit().accessibilityElement(children: .ignore)
                .accessibilityLabel(goal.map { "\(total.calorieText) of \($0.calorieText) calories" } ?? "\(total.calorieText) calories")
                .accessibilityIdentifier("calorieSummary")
            if let goal {
                let remaining = goal - total
                Text("\(abs(remaining).calorieText) \(remaining >= 0 ? "remaining" : "over")")
                    .font(.headline).foregroundStyle(remaining >= 0 ? Color.accentColor : Color.primary)
                GeometryReader { geometry in
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: geometry.size.width * min(max(total / goal, 0), 1)) }
                }.frame(height: 5).accessibilityHidden(true).padding(.top, 5)
            }
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 20)
    }
    private var searchSection: some View {
        Section("Results") {
            if let amount = Double(cleanQuery), amount >= 0, amount <= 100_000 {
                FoodRow(name: "Add \(amount.calorieText) calories", calories: nil,
                        add: { add(EntryDraft(calories: amount)) }, edit: { edit(EntryDraft(calories: amount)) })
            }
            let local = FoodHistory.search(cleanQuery, entries: store.entries)
            ForEach(local) { food in
                FoodRow(name: food.draft.name, calories: food.draft.calories, add: { add(food.draft) }, edit: { edit(food.draft) })
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
            if let message = search.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if !search.results.isEmpty { Text("Food data: Open Food Facts · ODbL").font(.caption2).foregroundStyle(.secondary) }
            Button { sheet = .entry(EntryDraft(name: Double(cleanQuery) == nil ? cleanQuery : "", timestamp: loggingDate)); searching = false } label: {
                Label("Add a food manually", systemImage: "square.and.pencil")
            }.padding(.vertical, 8)
        }
    }
    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let toast = store.toast {
                HStack {
                    Text(toast).font(.subheadline).lineLimit(2)
                    Spacer(minLength: 10)
                    Button("Undo") { store.undo() }.font(.subheadline.bold()).frame(minHeight: 44)
                }.padding(.horizontal, 20).background(Color.accentColor.opacity(0.1)).accessibilityIdentifier("undoBanner")
            }
            HStack(spacing: 10) {
                Button(action: openSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search food or enter calories…")
                        Spacer(minLength: 0)
                    }.foregroundStyle(.secondary).padding(12).frame(minHeight: 48)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("openSearch")
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.background(.bar)
    }
    private var searchDrawer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search food or enter calories…", text: $query)
                        .focused($searching).submitLabel(.search).autocorrectionDisabled()
                        .accessibilityIdentifier("foodSearch")
                }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red)
                        .frame(width: 44, height: 48)
                }.accessibilityLabel("Close search")
            }.padding(.horizontal, 16).padding(.top, 24)
            List {
                if cleanQuery.isEmpty {
                    let suggestions = FoodHistory.suggestions(entries: store.entries, date: loggingDate)
                    if suggestions.isEmpty {
                        Text("Your usual foods will appear here as you log them.")
                            .font(.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden)
                    } else {
                        Section("Suggestions") {
                            ForEach(suggestions) { food in
                                FoodRow(name: food.draft.name, calories: food.draft.calories, prominentAdd: true,
                                        add: { add(food.draft, source: "suggestion") },
                                        edit: { edit(food.draft, source: "suggestion") })
                            }
                        }
                    }
                } else { searchSection }
            }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(stride(from: 25, through: 1000, by: 25)), id: \.self) { amount in
                            Button { add(EntryDraft(calories: Double(amount))) } label: {
                                Text(amount.formatted()).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .padding(.horizontal, 16).frame(minWidth: 60, minHeight: 44)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }.accessibilityLabel("Add \(amount) calories")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }.accessibilityIdentifier("quickCalorieAmounts")
            HStack {
                Spacer()
                Button { searching = false; sheet = .barcode(loggingDate) } label: {
                    Image(systemName: "barcode.viewfinder").font(.title2).frame(width: 60, height: 48)
                }.accessibilityLabel("Scan barcode")
                Spacer()
                Button { searching = false; sheet = .voice } label: {
                    Image(systemName: "mic").font(.title2).frame(width: 60, height: 48)
                }.accessibilityLabel("Voice entry")
                Spacer()
                Button { searching = false; sheet = .photo } label: {
                    Image(systemName: "photo").font(.title2).frame(width: 60, height: 48)
                }.accessibilityLabel("Photo entry")
                Spacer()
            }.padding(.vertical, 8)
            }.background(.bar)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searching = true
        }
        .onDisappear { searching = false }
    }
    private func openSearch() { query = ""; sheet = .search }
    private func closeSearch() { searching = false; query = ""; sheet = nil }
    private func resetToday() { today = Date(); selected = today }
    private func add(_ input: EntryDraft, source: String? = nil) {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        if store.add([draft]) { closeSearch() }
    }
    private func edit(_ input: EntryDraft, source: String? = nil) {
        var draft = input; draft.entryID = nil; draft.timestamp = loggingDate; draft.source = source ?? draft.source
        searching = false; sheet = .entry(draft)
    }
}

struct FoodRow: View {
    let name: String
    var calories: Double?
    var detail: String? = nil
    var meal = false
    var prominentAdd = false
    let add: () -> Void
    let edit: () -> Void
    private var actionName: String { calories == nil && name.hasPrefix("Add ") ? String(name.dropFirst(4)) : name }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meal ? "☷ " : "")\(name)\(calories.map { " · \($0.calorieText) cal" } ?? "")").font(.subheadline).lineLimit(2)
                if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !prominentAdd {
                Button(action: add) { Image(systemName: "plus").fontWeight(.semibold).frame(width: 44, height: 48) }
                    .buttonStyle(.borderless).accessibilityLabel("Add \(actionName)")
            }
            Button(action: edit) { Image(systemName: "pencil").frame(width: 44, height: 48) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Edit \(actionName)")
            if prominentAdd {
                Button(action: add) {
                    Image(systemName: "plus").font(.body.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.accentColor, in: Circle())
                        .frame(width: 44, height: 48)
                }.buttonStyle(.borderless).accessibilityLabel("Add \(actionName)")
            }
        }
    }
}

struct DaySelector: View {
    @Binding var selected: Date
    var today: Date
    var body: some View {
        HStack(spacing: 0) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("Previous day")
            Text(dateLabel).font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .accessibilityIdentifier("selectedDate")
            Button { move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("Next day")
                .disabled(Calendar.current.startOfDay(for: selected) >= Calendar.current.startOfDay(for: today))
        }
    }
    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM"
        let day = Calendar.current.component(.day, from: selected)
        let ordinal = NumberFormatter()
        ordinal.locale = Locale(identifier: "en_US")
        ordinal.numberStyle = .ordinal
        return "\(formatter.string(from: selected)) \(ordinal.string(from: NSNumber(value: day)) ?? String(day)), \(Calendar.current.component(.year, from: selected))"
    }
    private func move(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selected),
              Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: today) else { return }
        selected = next
    }
}
