import SwiftUI
import SwiftData
import CloudKit
import CoreData
import WidgetKit

@MainActor @Observable final class AppStore {
    private static let regularEntryIDsKey = "regularEntryIDs.v1"
    private(set) var regularLogCount = 0
    private var regularEntryIDs: Set<String> = []
    private let persistsUsage: Bool
    private static let pinnedFoodIDsKey = "pinnedFoodIDs.v1"
    private static let pinnedMealIDsKey = "pinnedMealIDs.v1"
    private static let hiddenQuickAddKey = "hiddenQuickAddFoods.v1"
    /// Hiding is a snooze: long enough for the food's recency weight to fade, short enough not to be forgotten.
    static let quickAddHideDuration: TimeInterval = 14 * 86_400
    let container: ModelContainer
    let context: ModelContext
    let cloudEnabled: Bool
    private let publishesWidget: Bool
    @ObservationIgnored private let preferences: UserDefaults
    var profiles: [UserProfile] = []
    var entries: [CalorieEntry] = []
    var goals: [DailyGoal] = []
    var meals: [SavedMeal] = []
    var barcodes: [BarcodeFood] = []
    private(set) var commonFoodDefaults: [String: CommonFoodDefault] =
        UserDefaults.standard.data(forKey: "commonFoodDefaults.v1")
            .flatMap { try? JSONDecoder().decode([String: CommonFoodDefault].self, from: $0) } ?? [:]
    private(set) var pinnedFoodIDs: [String]
    private(set) var pinnedMealIDs: [String]
    private(set) var hiddenQuickAddFoods: [HiddenQuickAddFood]
    var error: String?
    var toast: String?
    var lastAddedID: UUID?
    var syncStatus = "Stored on this iPhone"
    private var undoAction: (() -> Void)?
    private var toastTask: Task<Void, Never>?
    var profile: UserProfile? { profiles.sorted { $0.updatedAt > $1.updatedAt }.first }

    init(container: ModelContainer, cloudEnabled: Bool = false, publishesWidget: Bool = true, persistsUsage: Bool = true, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.persistsUsage = persistsUsage
        pinnedFoodIDs = preferences.stringArray(forKey: Self.pinnedFoodIDsKey) ?? []
        pinnedMealIDs = preferences.stringArray(forKey: Self.pinnedMealIDsKey) ?? []
        hiddenQuickAddFoods = preferences.data(forKey: Self.hiddenQuickAddKey)
            .flatMap { try? JSONDecoder().decode([HiddenQuickAddFood].self, from: $0) } ?? []
        self.publishesWidget = publishesWidget
        self.container = container; context = container.mainContext
        self.cloudEnabled = cloudEnabled; context.autosaveEnabled = false
        refresh()
    }
    func refresh() {
        do {
            profiles = try context.fetch(FetchDescriptor<UserProfile>())
            entries = try context.fetch(FetchDescriptor<CalorieEntry>(sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.componentOrder), SortDescriptor(\.createdAt)]))
            // Remember up to the eligibility threshold, including deleted entries. Imported
            // iCloud rows and edits are deduplicated by entry ID; AI results do not count.
            var seen = regularEntryIDs
            if persistsUsage { seen.formUnion(preferences.stringArray(forKey: Self.regularEntryIDsKey) ?? []) }
            if seen.count < 100 {
                for entry in entries where !entry.sourceType.hasPrefix("ai") {
                    seen.insert(entry.id.uuidString)
                    if seen.count >= 100 { break }
                }
                if persistsUsage { preferences.set(Array(seen), forKey: Self.regularEntryIDsKey) }
            }
            regularEntryIDs = seen
            regularLogCount = min(100, seen.count)
            goals = try context.fetch(FetchDescriptor<DailyGoal>())
            meals = try context.fetch(FetchDescriptor<SavedMeal>(sortBy: [SortDescriptor(\.name)]))
            barcodes = try context.fetch(FetchDescriptor<BarcodeFood>())
            if publishesWidget {
                let now = Date()
                let snapshot = CalorieWidgetSnapshot(day: Calendar.current.startOfDay(for: now), total: total(now), goal: goal(now))
                if CalorieWidgetStorage.write(snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetStorage.kind) }
            }
        } catch { self.error = "Your saved data couldn’t be loaded. Please try reopening the app. \(error.localizedDescription)" }
    }
    @discardableResult func commit() -> Bool {
        do { try context.save(); refresh(); return true }
        catch { context.rollback(); refresh(); self.error = "Changes couldn’t be saved. Please try again. \(error.localizedDescription)"; return false }
    }
    func commonDefault(for food: CommonFood) -> CommonFoodDefault {
        commonFoodDefaults[food.id] ?? CommonFoodDefault(food.draft)
    }
    func applyingCommonDefault(to draft: EntryDraft) -> EntryDraft {
        guard let food = CommonFoods.matching(draft.name),
              draft.barcode == nil,
              draft.externalID == nil || draft.externalID == "common:\(food.id)",
              let saved = commonFoodDefaults[food.id] else { return draft }
        return saved.applying(to: draft)
    }
    func saveCommonDefault(_ draft: EntryDraft, for food: CommonFood) {
        guard draft.isValid else { return }
        var updated = commonFoodDefaults
        updated[food.id] = CommonFoodDefault(draft)
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: "commonFoodDefaults.v1")
        commonFoodDefaults = updated
    }
    func isPinned(_ foodID: String) -> Bool { pinnedFoodIDs.contains(foodID) }
    func setPinned(_ pinned: Bool, foodID: String) {
        updatePin(originalID: foodID, replacementID: foodID, pinned: pinned)
    }
    func updatePin(originalID: String, replacementID: String, pinned: Bool) {
        guard !originalID.isEmpty, !replacementID.isEmpty else { return }
        var updated = pinnedFoodIDs
        let originalIndex = updated.firstIndex(of: originalID)
        updated.removeAll { $0 == originalID || $0 == replacementID }
        if pinned {
            updated.insert(replacementID, at: min(originalIndex ?? updated.count, updated.count))
        }
        guard updated != pinnedFoodIDs else { return }
        preferences.set(updated, forKey: Self.pinnedFoodIDsKey)
        pinnedFoodIDs = updated
    }
    /// Foods currently kept off Quick Add. A snooze ends after two weeks, or as soon as the food is logged again.
    func activeHiddenQuickAddFoods(at now: Date = Date()) -> [HiddenQuickAddFood] {
        hiddenQuickAddFoods.filter { hidden in
            now < hidden.returnsAt && !entries.contains {
                $0.createdAt > hidden.hiddenAt && FoodHistory.foodID(for: $0) == hidden.id
            }
        }
    }
    func hiddenQuickAddIDs(at now: Date = Date()) -> Set<String> { Set(activeHiddenQuickAddFoods(at: now).map(\.id)) }
    func hideFromQuickAdd(foodID: String, name: String, now: Date = Date()) {
        guard !foodID.isEmpty else { return }
        let wasPinned = isPinned(foodID)
        if wasPinned { setPinned(false, foodID: foodID) }
        var updated = activeHiddenQuickAddFoods(at: now).filter { $0.id != foodID }
        updated.append(HiddenQuickAddFood(id: foodID, name: name, hiddenAt: now))
        saveHiddenQuickAddFoods(updated)
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        feedback("\(label.isEmpty ? "Food" : label) hidden for 2 weeks") { [weak self] in
            guard let self else { return }
            self.unhideQuickAdd(foodID)
            if wasPinned { self.setPinned(true, foodID: foodID) }
        }
    }
    func unhideQuickAdd(_ foodID: String) {
        saveHiddenQuickAddFoods(hiddenQuickAddFoods.filter { $0.id != foodID })
    }
    private func saveHiddenQuickAddFoods(_ foods: [HiddenQuickAddFood]) {
        // Expired and already-restored snoozes are dropped whenever the list changes.
        let live = foods.filter { hidden in
            Date() < hidden.returnsAt && !entries.contains { $0.createdAt > hidden.hiddenAt && FoodHistory.foodID(for: $0) == hidden.id }
        }
        guard live != hiddenQuickAddFoods else { return }
        preferences.set(try? JSONEncoder().encode(live), forKey: Self.hiddenQuickAddKey)
        hiddenQuickAddFoods = live
    }
    func isMealPinned(_ mealID: UUID) -> Bool { pinnedMealIDs.contains(mealID.uuidString) }
    func setMealPinned(_ pinned: Bool, mealID: UUID) {
        let id = mealID.uuidString
        var updated = pinnedMealIDs.filter { $0 != id }
        if pinned { updated.append(id) }
        guard updated != pinnedMealIDs else { return }
        preferences.set(updated, forKey: Self.pinnedMealIDsKey)
        pinnedMealIDs = updated
    }
    func dayEntries(_ date: Date) -> [CalorieEntry] { entries.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) } }
    func total(_ date: Date) -> Double { dayEntries(date).reduce(0) { $0 + $1.totalCalories.rounded() } }
    func goal(_ date: Date) -> Double? {
        let key = Day.key(date)
        let sorted = goals.sorted { $0.day == $1.day ? $0.updatedAt > $1.updatedAt : $0.day > $1.day }
        let storedValue = sorted.first(where: { $0.day <= key })?.calorieGoal ?? sorted.last?.calorieGoal ?? profile?.currentDailyGoal ?? 0
        return storedValue > 0 ? storedValue : nil
    }
    var tracksMacros: Bool { profile?.tracksMacros ?? true }
    var macroGoals: MacroNutrients { MacroNutrients.decode(profile?.macroGoalsData) ?? MacroNutrients() }
    func macroGoals(_ date: Date) -> MacroNutrients {
        let key = Day.key(date)
        let sorted = goals.sorted { $0.day == $1.day ? $0.updatedAt > $1.updatedAt : $0.day > $1.day }
        // An older record without macros intentionally has no macro goals.
        if let record = sorted.first(where: { $0.day <= key }) ?? sorted.last {
            return MacroNutrients.decode(record.macroGoalsData) ?? MacroNutrients()
        }
        return macroGoals
    }
    @discardableResult func setTracksMacros(_ enabled: Bool) -> Bool {
        guard let profile else { return false }
        profile.tracksMacros = enabled; profile.updatedAt = Date()
        return commit()
    }
    @discardableResult func saveMacroGoals(_ values: MacroNutrients) -> Bool {
        guard values.isValidGoal, let profile else { return false }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) { retainGoal(yesterday) }
        retainGoal(Date())
        profile.macroGoalsData = values.encoded; profile.updatedAt = Date()
        if let record = goals.filter({ $0.day == Day.key(Date()) }).max(by: { $0.updatedAt < $1.updatedAt }) {
            record.macroGoalsData = values.encoded; record.updatedAt = Date()
        }
        return commit()
    }
    func retainGoal(_ date: Date) {
        guard !goals.contains(where: { $0.day == Day.key(date) }) else { return }
        let record = DailyGoal(day: Day.key(date), goal: goal(date) ?? 0)
        record.macroGoalsData = macroGoals(date).encoded
        context.insert(record); goals.append(record)
    }
    @discardableResult func saveGoal(_ value: Double?) -> Bool {
        if let value, !value.isFinite || value < 1 || value > 9999 { return false }
        let storedValue = value ?? 0
        // Retain yesterday even if it had no entries, before changing today's default.
        if profile != nil, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) { retainGoal(yesterday) }
        if let profile { profile.currentDailyGoal = storedValue; profile.updatedAt = Date() }
        else { context.insert(UserProfile(goal: storedValue)) }
        let today = Day.key(Date())
        if let record = goals.filter({ $0.day == today }).max(by: { $0.updatedAt < $1.updatedAt }) {
            record.calorieGoal = storedValue; record.updatedAt = Date()
        } else {
            let record = DailyGoal(day: today, goal: storedValue)
            record.macroGoalsData = macroGoals.encoded
            context.insert(record)
        }
        return commit()
    }
    func cacheBarcode(_ draft: EntryDraft) {
        guard let code = draft.barcode, !code.isEmpty else { return }
        if let existing = barcodes.filter({ $0.barcode == code }).max(by: { $0.updatedAt < $1.updatedAt }) {
            existing.payload = (try? JSONEncoder().encode(draft)) ?? existing.payload; existing.updatedAt = Date()
        } else { let food = BarcodeFood(barcode: code, draft: draft); context.insert(food); barcodes.append(food) }
    }
    @discardableResult func add(_ drafts: [EntryDraft], message: String? = nil) -> Bool {
        guard !drafts.isEmpty, drafts.allSatisfy(\.isValid) else { error = "Please enter valid calories, servings, and a date no later than now."; return false }
        let added = drafts.map { draft -> CalorieEntry in
            retainGoal(draft.timestamp)
            let entry = CalorieEntry(draft: draft); context.insert(entry); cacheBarcode(draft); return entry
        }
        let ids = added.map(\.id)
        guard commit() else { return false }
        lastAddedID = ids.last
        feedback(message ?? "\(drafts.first!.name.isEmpty ? "Entry" : drafts.first!.name) added · \(drafts.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal") { [weak self] in
            guard let self else { return }; self.entries.filter { ids.contains($0.id) }.forEach(self.context.delete); self.commit()
        }
        return true
    }
    func update(_ draft: EntryDraft) -> Bool {
        guard draft.isValid, let entry = entries.first(where: { $0.id == draft.entryID }) else { return false }
        retainGoal(draft.timestamp); entry.apply(draft); cacheBarcode(draft)
        return commit()
    }
    func delete(_ entry: CalorieEntry) {
        let draft = EntryDraft(entry), id = entry.id, created = entry.createdAt
        context.delete(entry)
        guard commit() else { return }
        feedback("Entry deleted") { [weak self] in
            guard let self, !self.entries.contains(where: { $0.id == id }) else { return }
            let restored = CalorieEntry(draft: draft); restored.id = id; restored.createdAt = created
            self.context.insert(restored); self.commit()
        }
    }
    func feedback(_ message: String, undo: @escaping () -> Void) {
        toastTask?.cancel(); toast = message; undoAction = undo
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }; self?.toast = nil; self?.undoAction = nil
        }
    }
    func undo() { toastTask?.cancel(); let action = undoAction; undoAction = nil; toast = nil; action?() }
    @discardableResult func saveMeal(_ existing: SavedMeal?, name: String, items: [EntryDraft]) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !items.isEmpty, items.allSatisfy(\.isValid) else { return false }
        if let existing {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.componentsData = (try? JSONEncoder().encode(items)) ?? existing.componentsData; existing.updatedAt = Date()
        } else { context.insert(SavedMeal(name: name.trimmingCharacters(in: .whitespacesAndNewlines), items: items)) }
        return commit()
    }
    func addMeal(_ meal: SavedMeal, factor: Double = 1, date: Date) -> Bool {
        guard factor.isFinite, factor > 0 else { return false }
        return add(meal.items.enumerated().map { $0.element.scaled(factor, at: date, meal: meal.id, order: $0.offset) }, message: "\(meal.name) added")
    }
    func deleteMeal(_ meal: SavedMeal) {
        let wasPinned = isMealPinned(meal.id)
        setMealPinned(false, mealID: meal.id)
        context.delete(meal)
        guard commit() else {
            if wasPinned { setMealPinned(true, mealID: meal.id) }
            return
        }
    }
    func localBarcode(_ code: String) -> EntryDraft? { barcodes.filter { $0.barcode == code }.max { $0.updatedAt < $1.updatedAt }?.draft }
    func checkCloud() async {
        guard cloudEnabled else { syncStatus = "Stored on this iPhone"; return }
        do {
            switch try await CKContainer(identifier: Persistence.cloudID).accountStatus() {
            case .available: if !syncStatus.contains("synced") { syncStatus = "iCloud available · sync is automatic" }
            case .noAccount: syncStatus = "Sign in to iCloud in iPhone Settings"
            case .restricted: syncStatus = "iCloud access is restricted"
            default: syncStatus = "iCloud temporarily unavailable · saved locally"
            }
        } catch { syncStatus = "iCloud unavailable · saved locally" }
    }
    func cloudEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
        if event.error != nil { syncStatus = "Sync paused · saved locally" }
        else if event.endDate == nil { syncStatus = "Syncing with iCloud…" }
        else if event.succeeded, event.type != .setup { syncStatus = "Last synced \(event.endDate!.formatted(date: .omitted, time: .shortened))"; refresh() }
    }
}

enum Persistence {
    static let cloudID = "iCloud.com.philstarkovich.cavecals"
    static let schema = Schema([UserProfile.self, DailyGoal.self, CalorieEntry.self, SavedMeal.self, BarcodeFood.self])
    @MainActor static func make(inMemory: Bool = false) throws -> AppStore {
        #if targetEnvironment(simulator)
        let cloud = false
        #else
        let cloud = !inMemory
        #endif
        return try makeConfigured(inMemory: inMemory, cloud: cloud)
    }
    @MainActor private static func makeConfigured(inMemory: Bool, cloud: Bool) throws -> AppStore {
        let config = ModelConfiguration("CaveCals", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloud ? .private(cloudID) : .none)
        do { return AppStore(container: try ModelContainer(for: schema, configurations: [config]), cloudEnabled: cloud, publishesWidget: !inMemory, persistsUsage: !inMemory) }
        catch {
            guard cloud else { throw error }
            let local = ModelConfiguration("CaveCals", schema: schema, cloudKitDatabase: .none)
            let store = AppStore(container: try ModelContainer(for: schema, configurations: [local]), publishesWidget: !inMemory, persistsUsage: !inMemory)
            store.syncStatus = "iCloud unavailable · saved locally"
            return store
        }
    }
}

struct HiddenQuickAddFood: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let hiddenAt: Date
    var returnsAt: Date { hiddenAt.addingTimeInterval(AppStore.quickAddHideDuration) }
}
