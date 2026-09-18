import SwiftUI
import CoreData

@main struct CaveCalsApp: App {
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    @State private var store: AppStore?
    @State private var failure: String?
    init() {
        let navFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont(name: "Schoolbell-Regular", size: 20)!)
        UINavigationBar.appearance().titleTextAttributes = [.font: navFont]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(name: "Schoolbell-Regular", size: 36)!)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: navFont], for: .normal)
        do {
            var screenshots = false
            #if DEBUG && targetEnvironment(simulator)
            screenshots = ProcessInfo.processInfo.arguments.contains("--screenshots")
            #endif
            let store = try Persistence.make(inMemory: screenshots || ProcessInfo.processInfo.arguments.contains("--uitesting"))
            #if DEBUG && targetEnvironment(simulator)
            if screenshots {
                store.saveGoal(2100)
                for (name, calories, minutes) in [("Scrambled eggs", 180.0, 150), ("Sourdough toast", 160.0, 148), ("Greek yogurt", 130.0, 45), ("Blueberries", 85.0, 43)] {
                    let draft = EntryDraft(name: name, calories: calories, timestamp: Date().addingTimeInterval(-Double(minutes) * 60))
                    store.context.insert(CalorieEntry(draft: draft))
                }
                for day in 1...7 {
                    for (name, calories) in [("Banana", 105.0), ("Chicken breast", 230.0), ("Brown rice", 215.0), ("Almonds", 164.0)] {
                        let date = Calendar.current.date(byAdding: .day, value: -day, to: Date())!
                        store.context.insert(CalorieEntry(draft: EntryDraft(name: name, calories: calories, timestamp: date)))
                    }
                }
                store.context.insert(SavedMeal(name: "My breakfast", items: [EntryDraft(name: "Scrambled eggs", calories: 180), EntryDraft(name: "Sourdough toast", calories: 160)]))
                store.context.insert(SavedMeal(name: "Chicken & rice bowl", items: [EntryDraft(name: "Chicken breast", calories: 230), EntryDraft(name: "Brown rice", calories: 215), EntryDraft(name: "Broccoli", calories: 55)]))
                store.context.insert(SavedMeal(name: "Yogurt & berries", items: [EntryDraft(name: "Greek yogurt", calories: 130), EntryDraft(name: "Blueberries", calories: 85)]))
                store.commit()
            }
            #endif
            _store = State(initialValue: store)
        }
        catch { _failure = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        WindowGroup {
            if let store {
                RootView().font(.cave(.body)).environment(store).environment(LoggingActionRouter.shared)
                    .modelContainer(store.container).tint(.blue).accentColor(.blue)
                    .onOpenURL { LoggingActionRouter.shared.open(url: $0) }
            } else {
                ContentUnavailableView { Label { Text("Unable to open your data") } icon: { CaveIcon(.warning, size: 48) } } description: { Text(failure ?? "Please try reopening the app.") }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    var body: some View {
        @Bindable var store = store
        Group {
            if store.profile == nil { SetupView() } else { MainView() }
        }
        .alert("Couldn’t save changes", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .task { await store.checkCloud() }
        .task { await AISubscriptions.listenForPurchases() }
        .onChange(of: phase) { _, value in if value == .active { store.refresh(); Task { await store.checkCloud() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)) { store.cloudEvent($0) }
    }
}

struct SetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var goal: String
    @FocusState private var editingGoal: Bool
    let isAdjustingGoal: Bool
    @ScaledMetric(relativeTo: .title) private var goalFontSize = 76.0
    init(goal: Double? = 2100, isAdjustingGoal: Bool = false) {
        _goal = State(initialValue: goal.map(Self.formattedGoal) ?? "")
        self.isAdjustingGoal = isAdjustingGoal
    }
    var body: some View {
        GeometryReader { geometry in
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !isAdjustingGoal {
                        Image("SetupAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(120, geometry.size.height * 0.17))
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                    VStack(spacing: -12) {
                        headlineLine("You Eat.", width: geometry.size.width - 64, height: geometry.size.height)
                        headlineLine("App Track.", width: geometry.size.width - 64, height: geometry.size.height)
                        headlineLine("Weight Drop.", width: geometry.size.width - 64, height: geometry.size.height)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, -12)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        Text("daily calorie goal").font(.custom("Schoolbell-Regular", size: 24, relativeTo: .title3))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        TextField("—", text: $goal)
                            .focused($editingGoal)
                            .onChange(of: editingGoal) { _, editing in
                                let digits = goal.replacingOccurrences(of: ",", with: "")
                                if editing { goal = digits }
                                else if let value = Double(digits), value.isFinite {
                                    goal = Self.formattedGoal(value)
                                }
                            }
                            .keyboardType(.numberPad)
                            .font(.custom("Schoolbell-Regular", fixedSize: goalFontSize))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, -8)
                            .frame(width: min(goalFieldWidth, geometry.size.width - 48))
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 1) }
                            .accessibilityLabel("daily calorie goal").accessibilityIdentifier("profileGoal")
                    }.frame(maxWidth: .infinity).padding(.top, isAdjustingGoal ? 28 : 0)
                    VStack(spacing: 8) {
                        Button { startTracking() } label: {
                            HStack(spacing: 10) {
                                Text(isAdjustingGoal ? "Save Changes" : "Me Start Now")
                                if !isAdjustingGoal {
                                    CaveIcon(.arrowRight, size: 22).accessibilityHidden(true)
                                }
                            }.font(.cave(.title3).weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        }.buttonStyle(.borderedProminent)
                        Button("Me have no calorie goal") { saveGoal(nil) }
                            .font(.cave(.footnote)).frame(minHeight: 44)
                            .accessibilityIdentifier("skipGoal")
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
                .toolbar(isAdjustingGoal ? .visible : .hidden, for: .navigationBar)
                .task {
                    guard isAdjustingGoal else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    editingGoal = true
                }
                .toolbar {
                    if isAdjustingGoal {
                        ToolbarItem(placement: .cancellationAction) { Button("Me Go Back") { dismiss() } }
                    }
                }
        }
        }
    }

    private var goalFieldWidth: CGFloat {
        let font = UIFont(name: "Schoolbell-Regular", size: goalFontSize) ?? UIFont.systemFont(ofSize: goalFontSize)
        let widestDigit = (0...9).map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return widestDigit * 4 + ("," as NSString).size(withAttributes: [.font: font]).width + 32
    }

    private static func formattedGoal(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(0)))
    }

    private func startTracking() {
        let text = goal.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { saveGoal(nil); return }
        guard let value = Double(text), value.isFinite, value >= 1, value <= 9999 else {
            store.error = "Goal need 1 to 9,999 calories. Or pick “Me have no calorie goal”."
            return
        }
        saveGoal(value)
    }

    private func saveGoal(_ value: Double?) {
        if store.saveGoal(value), isAdjustingGoal { dismiss() }
    }

    private func headlineLine(_ text: String, width: CGFloat, height: CGFloat) -> some View {
        // Fit each line to the width and reserve room for controls on short phones.
        var lower: CGFloat = 1
        var upper: CGFloat = min(85, max(44, height * 0.105))
        for _ in 0..<14 {
            let size = (lower + upper) / 2
            let font = UIFont(name: "Schoolbell-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
            let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
            if measuredWidth <= max(1, width - 1) { lower = size } else { upper = size }
        }
        return Text(text)
            .font(.custom("Schoolbell-Regular", fixedSize: lower))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
