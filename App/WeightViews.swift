import SwiftUI
import Charts

struct WeightEditorRoute: Identifiable {
    let id = UUID()
    var record: WeightRecord?
}

struct WeightProfileSections: View {
    @Environment(WeightStore.self) private var weights
    @Binding var editor: WeightEditorRoute?
    var body: some View {
        Group {
            Section {
                Toggle("Track weight", isOn: Binding(get: { weights.tracking }, set: { weights.setTracking($0) }))
                    .accessibilityIdentifier("trackWeight")
                if weights.tracking {
                    Picker("Weight unit", selection: Binding(get: { weights.unit }, set: { Haptics.play(.selection); weights.setUnit($0) })) {
                        Text("Pounds (lb)").tag(WeightUnit.pounds)
                        Text("Kilograms (kg)").tag(WeightUnit.kilograms)
                    }.accessibilityIdentifier("weightUnit")
                    Button { editor = WeightEditorRoute(record: weights.record(on: Date())) } label: {
                        HStack(spacing: 12) {
                            // A concrete color: `.primary` inside a list button resolves to the orange tint.
                            Text("Today’s weight").foregroundStyle(Color.primary)
                            Spacer(minLength: 8)
                            HStack(spacing: 6) {
                                CaveIcon(.pencil, size: 22).foregroundStyle(Color.caveOrange)
                                Text(weights.record(on: Date()).map { weights.unit.text($0.kilograms) } ?? "Log")
                                    .font(.cave(.title3))
                                    .foregroundStyle(weights.record(on: Date()) == nil ? Color.caveOrange : Color.primary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.trailing, 8)
                        }.contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("todayWeight")
                }
            }
            if let error = weights.error { Section { Text(error).foregroundStyle(.red) } }
        }
    }
}

/// Settings → Apple Health: food (calories & macros) and weigh-ins. Weight tracking itself stays in About You.
struct AppleHealthSection: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(NutritionHealthSync.self) private var nutrition
    var body: some View {
        Section {
            Toggle("Calories & macros", isOn: Binding(get: { nutrition.enabled }, set: { enabled in
                Task { await nutrition.setEnabled(enabled, entries: store.entries) }
            }))
            .disabled(nutrition.connecting || !nutrition.available)
            .accessibilityIdentifier("shareNutritionHealth")
            if nutrition.connecting || nutrition.syncing { ProgressView(nutrition.connecting ? "Connecting…" : "Sharing food…") }
            if let message = nutrition.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
            Toggle("Weigh-ins", isOn: Binding(get: { weights.healthSharing }, set: { enabled in
                Task { await weights.setHealthSharing(enabled) }
            }))
            .disabled(!weights.tracking || weights.connecting || !weights.healthAvailable)
            .accessibilityIdentifier("shareWeightHealth")
            if weights.connecting || weights.syncing { ProgressView(weights.connecting ? "Connecting…" : "Sharing weigh-ins…") }
            if let message = weights.healthMessage { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
            if !weights.healthAvailable { Text("Apple Health is unavailable on this device.").font(.cave(.footnote)).foregroundStyle(.secondary) }
            if weights.tracking && weights.healthSharing && weights.pendingCount > 0 {
                Button("Retry sharing") { Task { await weights.syncHealth() } }.disabled(weights.syncing)
            }
        } header: { Text("Apple Health") } footer: {
            Text("Calories & macros shares the calories, protein, carbs, fat and fiber of foods you log from the day you turn it on, and keeps them updated when you edit or delete. Weigh-ins shares all your weigh-ins"
                 + (weights.tracking ? "." : " once Track weight is on in About You.")
                 + " Cave Cals never reads your Health data. Pausing sharing leaves what’s already in Apple Health.")
                .font(.cave(.caption2))
        }
    }
}

struct WeightEditorSheet: View {
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    let record: WeightRecord?
    let unit: WeightUnit
    @State private var amount: String
    @State private var date: Date
    @State private var confirmingDelete = false
    @State private var pendingDate: Date?
    @State private var confirmingDayChange = false
    @FocusState private var focused: Bool

    init(record: WeightRecord? = nil, unit: WeightUnit) {
        self.record = record; self.unit = unit
        _date = State(initialValue: record?.date ?? Date())
        _amount = State(initialValue: record.map { unit.editingText($0.kilograms) } ?? "")
    }
    private var selectedRecord: WeightRecord? { weights.record(on: date) }
    private var hasChanges: Bool { amount != selectedRecord.map { unit.editingText($0.kilograms) } ?? "" }
    private var kilograms: Double? {
        // Preserve precision when the displayed weight has not been edited.
        if let record = selectedRecord, amount == unit.editingText(record.kilograms) { return record.kilograms }
        return WeightUnit.parse(amount).map { unit.kilograms($0) }
    }
    private var valid: Bool { kilograms.map(WeightStore.valid) == true && date <= Date() }
    var body: some View {
        NavigationStack {
            HapticForm {
                Section {
                    WeightWeekPicker(date: date, unit: unit, select: selectDay)
                }.listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Weight", text: $amount)
                            .keyboardType(.decimalPad).focused($focused)
                            .font(.cave(.largeTitle)).accessibilityIdentifier("weightAmount")
                            .accessibilityLabel("Weight in \(unit == .pounds ? "pounds" : "kilograms")")
                        Text(unit.rawValue).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    .keyboardInputArea { focused = true }
                } header: {
                    Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                }
                if let error = weights.error { Section { Text(error).foregroundStyle(.red) } }
                if selectedRecord != nil {
                    Section {
                        Button("Delete weigh-in", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("deleteWeight")
                    }
                }
            }.caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if saveSelectedDay() { dismiss() }
                    } label: { Label("Save", systemImage: "checkmark").foregroundStyle(.white) }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange).hapticFeel(.success).disabled(!valid)
                    .accessibilityIdentifier("saveWeight")
                }
            }
            .confirmationDialog("Delete this weigh-in?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                // Dialog buttons may skip the haptic button style, so they play their own feel.
                Button("Delete weigh-in", role: .destructive) {
                    Haptics.play(.warning)
                    if let record = selectedRecord, weights.delete(record.id) { dismiss() }
                }.hapticFeel(.none)
            } message: {
                Text(weights.healthSharing ? "It will also be removed from Apple Health when sharing completes." : "If previously shared, its Apple Health copy will be removed when you resume sharing.")
            }
            .confirmationDialog("Save changes?", isPresented: $confirmingDayChange, titleVisibility: .visible) {
                Button("Save and switch") {
                    Haptics.play(.success)
                    if saveSelectedDay(), let pendingDate { loadDay(pendingDate) }
                    pendingDate = nil
                }.disabled(!valid).hapticFeel(.none)
                Button("Discard changes", role: .destructive) {
                    Haptics.play(.warning)
                    if let pendingDate { loadDay(pendingDate) }
                    pendingDate = nil
                }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap); pendingDate = nil }.hapticFeel(.none)
            }
            .task {
                guard record == nil else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }; focused = true
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func saveSelectedDay() -> Bool {
        guard valid, let kilograms else { return false }
        // Week navigation edits the selected day; it never moves the original record.
        return weights.save(kilograms: kilograms, date: selectedRecord?.date ?? date, id: selectedRecord?.id)
    }
    private func selectDay(_ day: Date) {
        guard day <= Date(), !Calendar.current.isDate(day, inSameDayAs: date) else { return }
        focused = false
        if hasChanges {
            pendingDate = day
            confirmingDayChange = true
        } else { loadDay(day) }
    }
    private func loadDay(_ day: Date) {
        date = day
        amount = weights.record(on: day).map { unit.editingText($0.kilograms) } ?? ""
    }
}

private struct WeightWeekPicker: View {
    @Environment(WeightStore.self) private var weights
    let date: Date
    let unit: WeightUnit
    let select: (Date) -> Void
    private var days: [Date] { WeightWeek.days(containing: date) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var nextWeek: Date { Calendar.current.date(byAdding: .day, value: 7, to: days[0])! }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { move(-1) } label: { CaveIcon(.chevronLeft, size: 18).frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous week").accessibilityIdentifier("previousWeightWeek")
                Spacer(minLength: 0)
                Text(days[0].formatted(.dateTime.month(.abbreviated).day()) + " – " + days[6].formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.cave(.subheadline)).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { move(1) } label: { CaveIcon(.chevronRight, size: 18).frame(width: 44, height: 44) }
                    .disabled(nextWeek > today)
                    .accessibilityLabel("Next week").accessibilityIdentifier("nextWeightWeek")
            }.hapticButtonStyle(.plain).hapticFeel(.selection).foregroundStyle(Color.accentColor)
            ViewThatFits(in: .horizontal) {
                dayButtons
                ScrollView(.horizontal) { dayButtons }.scrollIndicators(.hidden)
            }
        }
    }
    private var dayButtons: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: date)
                let record = weights.record(on: day)
                Button { select(day) } label: {
                    VStack(spacing: 5) {
                        Text(day, format: .dateTime.weekday(.abbreviated)).font(.cave(.caption))
                        Text(day, format: .dateTime.day()).font(.cave(.body))
                        Text(record.map { unit.display($0.kilograms).formatted(.number.grouping(.never).precision(.fractionLength(1))) } ?? "--")
                            .font(.cave(.caption)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(minWidth: 44, maxWidth: .infinity).padding(.vertical, 10)
                    .foregroundStyle(day > today ? Color.secondary.opacity(0.45) : Color.primary)
                    .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5) }
                    .contentShape(Rectangle())
                }
                .hapticButtonStyle(.plain).hapticFeel(.selection).disabled(day > today)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .accessibilityValue(record.map { unit.text($0.kilograms) } ?? "No weigh-in")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("weightDay-\(Day.key(day))")
            }
        }
    }
    private func move(_ direction: Int) {
        let target = Calendar.current.date(byAdding: .day, value: direction * 7, to: date)!
        select(min(target, today))
    }

}

struct WeightHistoryView: View {
    @Environment(WeightStore.self) private var weights
    @State private var editor: WeightEditorRoute?
    var body: some View {
        HapticList {
            if weights.records.isEmpty { Text("Your weigh-ins will appear here.").foregroundStyle(.secondary) }
            ForEach(weights.records) { record in
                Button { editor = WeightEditorRoute(record: record) } label: {
                    HStack {
                        Text(record.date, format: .dateTime.month(.abbreviated).day().year())
                        Spacer()
                        Text(weights.unit.text(record.kilograms))
                        CaveIcon(.pencil, size: 18).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).frame(minHeight: 44)
                }.accessibilityIdentifier("weight-\(record.id)")
            }
        }.caveScreenBackground()
        .navigationTitle("Weigh-ins")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button("Add weigh-in") { editor = WeightEditorRoute() }.hapticButtonStyle(.automatic).accessibilityIdentifier("addHistoricalWeight")
        } }
        .sheet(item: $editor) { route in WeightEditorSheet(record: route.record, unit: weights.unit) }
    }
}


/// A one-time drawer offering Apple Health sharing once someone has a reason to want it: right after a
/// weigh-in, the first time they tap Done eating, or on a later day after logging food on an earlier one.
/// Shown at most once per iPhone; Settings → Apple Health keeps the same switches.
enum AppleHealthOffer {
    static let shownKey = "appleHealthOfferShown.v1"

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: shownKey) && !optedInForTesting }
    static func recordShown() { UserDefaults.standard.set(true, forKey: shownKey) }

    /// Food logged on the day it belongs to, on a day before today (backfilling doesn't count).
    static func loggedOnEarlierDay(_ entries: [CalorieEntry], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        return entries.contains { $0.createdAt < today && calendar.isDate($0.createdAt, inSameDayAs: $0.timestamp) }
    }

    /// UI tests and screenshots never see it, unless a DEBUG UI test opts in with `--health-offer`.
    static var isAllowed: Bool {
        optedInForTesting || !ProcessInfo.processInfo.arguments.contains { $0 == "--uitesting" || $0 == "--screenshots" }
    }
    private static var optedInForTesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--health-offer")
        #else
        false
        #endif
    }
}

struct AppleHealthOfferSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(WeightStore.self) private var weights
    @Environment(NutritionHealthSync.self) private var nutrition
    @Environment(\.dismiss) private var dismiss
    /// The drawer opens exactly as tall as its content, so the switches are never below the fold on a
    /// small iPhone or with large text.
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        VStack(spacing: 18) {
            Text("Sync with Apple Health").font(.cave(.title)).accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
            Text("Share what you track with Apple Health and apps that use it.")
                .font(.cave(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                row("Calories & macros", isOn: nutritionBinding, busy: nutrition.connecting,
                    id: "offerShareNutritionHealth") {
                    HStack(spacing: 10) {
                        ForEach([CaveGlyph.protein, .carbs, .fat], id: \.self) { CaveIcon($0, size: 32) }
                    }.foregroundStyle(Color.caveOrange)
                }
                if weights.tracking {
                    Divider()
                    row("Weigh-ins", isOn: weightBinding, busy: weights.connecting, id: "offerShareWeightHealth") {
                        Image("TrackWeightScale").resizable().scaledToFit().frame(width: 44, height: 44)
                    }
                }
            }.padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
            if let message = nutrition.message ?? weights.healthMessage {
                Text(message).font(.cave(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity).padding(.vertical, 8)
            }.hapticButtonStyle(.borderedProminent).accessibilityIdentifier("closeHealthOffer")
                .padding(.top, 6)
            Text("You can change these anytime in Settings.").font(.cave(.footnote)).foregroundStyle(.secondary)
        }
        .font(.cave(.body))
        .padding(.horizontal, 24).padding(.bottom, 12)
        .frame(maxWidth: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .caveScreenBackground()
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
    }

    private var nutritionBinding: Binding<Bool> {
        Binding(get: { nutrition.enabled }, set: { enabled in
            Task { await nutrition.setEnabled(enabled, entries: store.entries) }
        })
    }
    private var weightBinding: Binding<Bool> {
        Binding(get: { weights.healthSharing }, set: { enabled in
            Task { await weights.setHealthSharing(enabled) }
        })
    }

    /// Scroll views and sheets swallow quick taps on a bare switch, so the whole row flips it.
    private func row<Art: View>(_ title: String, isOn: Binding<Bool>, busy: Bool, id: String,
                                @ViewBuilder art: () -> Art) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).foregroundStyle(Color.primary)
                    art().accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                if busy { ProgressView() }
                Toggle(title, isOn: isOn).labelsHidden().allowsHitTesting(false)
            }.padding(.vertical, 10).frame(minHeight: 44).contentShape(Rectangle())
        }.hapticButtonStyle(.plain).hapticFeel(.selection)
            .disabled(busy)
            .accessibilityRepresentation { Toggle(title, isOn: isOn) }
            .accessibilityIdentifier(id)
    }
}
