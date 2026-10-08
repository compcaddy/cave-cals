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
    private static let homeQuickAddKey = "homeQuickAddDay.v1"
    private static let commonFoodDefaultsKey = "commonFoodDefaults.v1"
    private static let resetCommonFoodIDsKey = "resetCommonFoodIDs.v1"
    /// Settings → "Show Quick Start on new days" (on by default).
    static let showsHomeQuickAddKey = "showsHomeQuickAdd.v1"
    private static let finishedDaysKey = "finishedEatingDays.v1"
    private static let finishPromptHiddenKey = "finishDayPromptHidden.v1"
    /// Settings → "Show “Done eating” button" (on by default).
    static let showsFinishDayKey = "showsFinishDay.v1"
    /// Hiding is a snooze: long enough for the food's recency weight to fade, short enough not to be forgotten.
    static let quickAddHideDuration: TimeInterval = 14 * 86_400
    let container: ModelContainer
    let context: ModelContext
    let cloudEnabled: Bool
    private let publishesWidget: Bool
    private let persistsFoodDefaults: Bool
    @ObservationIgnored private let preferences: UserDefaults
    var profiles: [UserProfile] = []
    var entries: [CalorieEntry] = []
    var goals: [DailyGoal] = []
    var meals: [SavedMeal] = []
    var barcodes: [BarcodeFood] = []
    private(set) var commonFoodDefaults: [String: CommonFoodDefault]
    private var resetCommonFoodIDs: Set<String>
    private(set) var pinnedFoodIDs: [String]
    private(set) var pinnedMealIDs: [String]
    private(set) var hiddenQuickAddFoods: [HiddenQuickAddFood]
    private(set) var homeQuickAdd: HomeQuickAddDay?
    /// Day key → when that day was marked done eating. Local to this iPhone.
    private(set) var finishedDays: [String: Date]
    private(set) var finishPromptHiddenDay: String?
    /// Meal types and their times, decoded from the profile on every reload.
    private(set) var mealSettings = MealSettings()
    /// Week start, on-target rule, and chart ranges, synced on the profile.
    private(set) var progressSettings = ProgressSettings()
    var error: String?
    var toast: String?
    var lastAddedID: UUID?
    var syncStatus = "Stored on this iPhone"
    /// Bumped whenever the diary is reloaded, so derived data (like the search index) knows to rebuild.
    @ObservationIgnored private(set) var entriesRevision = 0
    /// Called after every successful reload of the diary (local saves, iCloud imports, Siri).
    @ObservationIgnored var entriesDidChange: (([CalorieEntry]) -> Void)?
    private var undoAction: (() -> Void)?
    private var toastTask: Task<Void, Never>?
    var profile: UserProfile? { profiles.sorted { $0.updatedAt > $1.updatedAt }.first }

    init(container: ModelContainer, cloudEnabled: Bool = false, publishesWidget: Bool = true, persistsUsage: Bool = true, preferences: UserDefaults = .standard, persistsFoodDefaults: Bool = true) {
        self.preferences = preferences
        self.persistsUsage = persistsUsage
        self.persistsFoodDefaults = persistsFoodDefaults
        commonFoodDefaults = persistsFoodDefaults ? preferences.data(forKey: Self.commonFoodDefaultsKey)
            .flatMap { try? JSONDecoder().decode([String: CommonFoodDefault].self, from: $0) } ?? [:] : [:]
        resetCommonFoodIDs = persistsFoodDefaults ? Set(preferences.stringArray(forKey: Self.resetCommonFoodIDsKey) ?? []) : []
        pinnedFoodIDs = preferences.stringArray(forKey: Self.pinnedFoodIDsKey) ?? []
        pinnedMealIDs = preferences.stringArray(forKey: Self.pinnedMealIDsKey) ?? []
        hiddenQuickAddFoods = preferences.data(forKey: Self.hiddenQuickAddKey)
            .flatMap { try? JSONDecoder().decode([HiddenQuickAddFood].self, from: $0) } ?? []
        homeQuickAdd = persistsUsage ? preferences.data(forKey: Self.homeQuickAddKey)
            .flatMap { try? JSONDecoder().decode(HomeQuickAddDay.self, from: $0) } : nil
        finishedDays = persistsUsage ? preferences.data(forKey: Self.finishedDaysKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:] : [:]
        finishPromptHiddenDay = persistsUsage ? preferences.string(forKey: Self.finishPromptHiddenKey) : nil
        self.publishesWidget = publishesWidget
        self.container = container; context = container.mainContext
        self.cloudEnabled = cloudEnabled; context.autosaveEnabled = false
        refresh()
    }
    func refresh() {
        do {
            profiles = try context.fetch(FetchDescriptor<UserProfile>())
            mealSettings = MealSettings.decode(profile?.mealSettingsData)
            progressSettings = ProgressSettings.decode(profile?.progressSettingsData,
                localWeekday: ProgressPreferences.defaults.object(forKey: ProgressCalendar.weekStartKey) as? Int ?? 2)
            entries = try context.fetch(FetchDescriptor<CalorieEntry>(sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.componentOrder), SortDescriptor(\.createdAt)]))
            entriesRevision &+= 1
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
            entriesDidChange?(entries)
            if publishesWidget {
                let now = Date()
                let snapshot = CalorieWidgetSnapshot(day: Calendar.current.startOfDay(for: now), total: total(now), goal: goal(now))
                if CalorieWidgetStorage.write(snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetStorage.kind) }
            }
        } catch { self.error = "Your saved data couldn’t be loaded. Please try reopening the app. \(error.localizedDescription)" }
    }
    @discardableResult func commit() -> Bool {
        do { try context.save(); refresh(); return true }
        catch {
            context.rollback(); refresh(); self.error = "Changes couldn’t be saved. Please try again. \(error.localizedDescription)"
            UsageStats.shared.error(.save, error)
            return false
        }
    }
    func commonDefault(for food: CommonFood) -> CommonFoodDefault {
        commonFoodDefaults[food.id] ?? CommonFoodDefault(food.draft)
    }
    func applyingCommonDefault(to draft: EntryDraft) -> EntryDraft {
        guard let food = CommonFoods.matching(draft.name),
              draft.barcode == nil,
              draft.externalID == nil || draft.externalID == "common:\(food.id)" else { return draft }
        if let saved = commonFoodDefaults[food.id] { return saved.applying(to: draft) }
        // History keeps its original values. Reusing a reset food must not resurrect
        // its old custom nutrition from those diary snapshots.
        if resetCommonFoodIDs.contains(food.id) { return CommonFoodDefault(food.draft).applying(to: draft) }
        return draft
    }
    func saveCommonDefault(_ draft: EntryDraft, for food: CommonFood) {
        guard draft.isValid else { return }
        var updated = commonFoodDefaults
        updated[food.id] = CommonFoodDefault(draft)
        guard let data = try? JSONEncoder().encode(updated) else { return }
        if persistsFoodDefaults { preferences.set(data, forKey: Self.commonFoodDefaultsKey) }
        commonFoodDefaults = updated
        resetCommonFoodIDs.remove(food.id)
        if persistsFoodDefaults { preferences.set(Array(resetCommonFoodIDs).sorted(), forKey: Self.resetCommonFoodIDsKey) }
    }
    /// Removes only explicitly saved common-food overrides. Never edits diary or meal snapshots.
    func resetSavedNutrition() {
        guard !commonFoodDefaults.isEmpty else { return }
        resetCommonFoodIDs.formUnion(commonFoodDefaults.keys)
        if persistsFoodDefaults {
            preferences.set(Array(resetCommonFoodIDs).sorted(), forKey: Self.resetCommonFoodIDsKey)
            preferences.removeObject(forKey: Self.commonFoodDefaultsKey)
        }
        commonFoodDefaults = [:]
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
    /// Home's Quick Add picks show on an empty day and stay while they're being used, until
    /// another way of logging (search, voice, meal scan, barcode) is used that day.
    func showsHomeQuickAdd(on date: Date) -> Bool {
        let state = homeQuickAdd?.day == Day.key(date) ? homeQuickAdd : nil
        if state?.dismissed == true { return false }
        return state?.used == true || dayEntries(date).isEmpty
    }
    func markHomeQuickAddUsed(on date: Date) { updateHomeQuickAdd(on: date) { $0.used = true } }
    func dismissHomeQuickAdd(on date: Date) { updateHomeQuickAdd(on: date) { $0.dismissed = true } }
    private func updateHomeQuickAdd(on date: Date, _ change: (inout HomeQuickAddDay) -> Void) {
        let day = Day.key(date)
        var state = homeQuickAdd?.day == day ? homeQuickAdd! : HomeQuickAddDay(day: day)
        change(&state)
        guard state != homeQuickAdd else { return }
        homeQuickAdd = state
        if persistsUsage { preferences.set(try? JSONEncoder().encode(state), forKey: Self.homeQuickAddKey) }
    }
    /// "Done eating" closes a day's logging. Logging anything more that same day reopens it; edits, deletes,
    /// and later backfills don't, so a settled day stays complete for Progress.
    func isFinished(_ date: Date) -> Bool {
        guard let finishedAt = finishedDays[Day.key(date)] else { return false }
        return !dayEntries(date).contains { reopens($0, finishedAt: finishedAt) }
    }
    /// Start of each day that is still marked done, for Progress.
    func finishedDates(calendar: Calendar = .current) -> Set<Date> {
        var closed: [Date: Date] = [:]
        for finishedAt in finishedDays.values { closed[calendar.startOfDay(for: finishedAt)] = finishedAt }
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            if let finishedAt = closed[day], reopens(entry, finishedAt: finishedAt, calendar: calendar) { closed[day] = nil }
        }
        return Set(closed.keys)
    }
    private func reopens(_ entry: CalorieEntry, finishedAt: Date, calendar: Calendar = .current) -> Bool {
        entry.createdAt > finishedAt && calendar.isDate(entry.createdAt, inSameDayAs: finishedAt)
    }
    func finishDay(_ now: Date = Date()) {
        saveFinishedDays { $0[Day.key(now)] = now }
        UsageStats.shared.count(.doneEating, now: now)
    }
    func reopenDay(_ date: Date = Date()) { saveFinishedDays { $0[Day.key(date)] = nil } }
    private func saveFinishedDays(_ change: (inout [String: Date]) -> Void) {
        var updated = finishedDays
        change(&updated)
        guard updated != finishedDays else { return }
        finishedDays = updated
        if persistsUsage { preferences.set(try? JSONEncoder().encode(updated), forKey: Self.finishedDaysKey) }
    }
    func finishPromptHidden(on date: Date) -> Bool { finishPromptHiddenDay == Day.key(date) }
    func hideFinishPrompt(on date: Date) {
        finishPromptHiddenDay = Day.key(date)
        if persistsUsage { preferences.set(finishPromptHiddenDay, forKey: Self.finishPromptHiddenKey) }
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
    /// `newMacroGoals` (a calculated plan's suggested targets) replaces the macro goals from today, in the same save.
    @discardableResult func saveGoal(_ value: Double?, tracksMacros: Bool? = nil, macroGoals newMacroGoals: MacroNutrients? = nil) -> Bool {
        if let value, !value.isFinite || value < 1 || value > 9999 { return false }
        if let newMacroGoals, !newMacroGoals.isValidGoal { return false }
        let storedValue = value ?? 0
        // Retain yesterday even if it had no entries, before changing today's default.
        if profile != nil, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) { retainGoal(yesterday) }
        let todaysMacroGoals = newMacroGoals ?? macroGoals
        if let profile {
            profile.currentDailyGoal = storedValue; profile.updatedAt = Date()
            if let tracksMacros { profile.tracksMacros = tracksMacros }
            if let newMacroGoals { profile.macroGoalsData = newMacroGoals.encoded }
        } else {
            let profile = UserProfile(goal: storedValue)
            if let tracksMacros { profile.tracksMacros = tracksMacros }
            profile.macroGoalsData = newMacroGoals?.encoded
            context.insert(profile)
        }
        let today = Day.key(Date())
        if let record = goals.filter({ $0.day == today }).max(by: { $0.updatedAt < $1.updatedAt }) {
            record.calorieGoal = storedValue; record.updatedAt = Date()
            if let newMacroGoals { record.macroGoalsData = newMacroGoals.encoded }
        } else {
            let record = DailyGoal(day: today, goal: storedValue)
            record.macroGoalsData = todaysMacroGoals.encoded
            context.insert(record)
        }
        return commit()
    }
    func cacheBarcode(_ draft: EntryDraft) {
        guard let code = draft.barcode, !code.isEmpty else { return }
        // The product is remembered, not the meal it was eaten at.
        var draft = draft; draft.mealType = nil
        if let existing = barcodes.filter({ $0.barcode == code }).max(by: { $0.updatedAt < $1.updatedAt }) {
            existing.payload = (try? JSONEncoder().encode(draft)) ?? existing.payload; existing.updatedAt = Date()
        } else { let food = BarcodeFood(barcode: code, draft: draft); context.insert(food); barcodes.append(food) }
    }
    /// `method` overrides the one implied by the drafts' source, for copies and Siri.
    @discardableResult func add(_ drafts: [EntryDraft], message: String? = nil, method: LogMethod? = nil) -> Bool {
        guard !drafts.isEmpty, drafts.allSatisfy(\.isValid) else { error = "Please enter valid calories, servings, and a date no later than now."; return false }
        let meals = mealSettings
        let added = drafts.map { draft -> CalorieEntry in
            var draft = draft
            draft.mealType = meals.assignedMeal(chosen: draft.mealType, at: draft.timestamp)
            retainGoal(draft.timestamp)
            let entry = CalorieEntry(draft: draft); context.insert(entry); cacheBarcode(draft); return entry
        }
        let ids = added.map(\.id)
        guard commit() else { return false }
        let method = method ?? LogMethod(source: drafts[0].source)
        UsageStats.shared.itemsAdded(drafts.count, method: method)
        lastAddedID = ids.last
        feedback(message ?? "\(drafts.first!.name.isEmpty ? "Entry" : drafts.first!.name) added · \(drafts.reduce(0) { $0 + $1.calories.rounded() }.calorieText) cal") { [weak self] in
            guard let self else { return }; self.entries.filter { ids.contains($0.id) }.forEach(self.context.delete)
            if self.commit() { UsageStats.shared.itemsUndone(drafts.count, method: method) }
        }
        return true
    }
    func update(_ draft: EntryDraft) -> Bool {
        guard draft.isValid, let entry = entries.first(where: { $0.id == draft.entryID }) else { return false }
        let movedMeal = entry.mealType != draft.mealType
        retainGoal(draft.timestamp); entry.apply(draft); cacheBarcode(draft)
        guard commit() else { return false }
        UsageStats.shared.count(.edits)
        if movedMeal { UsageStats.shared.count(.mealMoves) }
        return true
    }
    /// After a food's macros are set (Home's macro sheet or the editor), the same food logged on other days gets
    /// them too, scaled by calories (a double portion gets double), so it's complete everywhere and adding it again
    /// from Quick Add or history carries them. Only blanks, AI estimates, and amounts still matching the source's
    /// `previous` values (filled from it before, now corrected) change; other typed amounts never do. Returns how
    /// many other entries changed.
    @discardableResult func shareMacros(from source: CalorieEntry, previous: MacroNutrients? = nil) -> Int {
        guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.totalCalories > 0,
              let macros = MacroNutrients.decode(source.macrosPerServingData)?.scaled(source.servings) else { return 0 }
        let food = FoodHistory.foodID(for: source)
        var changed = 0
        for entry in entries where entry.id != source.id && entry.totalCalories > 0 && FoodHistory.foodID(for: entry) == food {
            var draft = EntryDraft(entry)
            var totals = draft.totalMacros ?? MacroNutrients()
            var updated = false
            for kind in MacroKind.allCases {
                guard let value = macros[keyPath: kind.keyPath] else { continue }
                let ratio = entry.totalCalories / source.totalCalories
                let current = totals[keyPath: kind.keyPath]
                var wasShared = false
                if let old = previous?[keyPath: kind.keyPath], let current {
                    let oldScaled: Double = (old * ratio * 10).rounded() / 10
                    wasShared = abs(current - oldScaled) < 0.05
                }
                guard current == nil || totals[keyPath: kind.estimateKeyPath] == true || wasShared else { continue }
                let scaled = (value * ratio * 10).rounded() / 10
                guard current != scaled else { continue }
                totals[keyPath: kind.keyPath] = scaled
                totals[keyPath: kind.estimateKeyPath] = macros[keyPath: kind.estimateKeyPath]
                updated = true
            }
            guard updated, totals.isValid else { continue }
            draft.macrosPerServing = totals.scaled(1 / max(draft.servings, 0.0001))
            entry.apply(draft)
            changed += 1
        }
        guard changed > 0 else { return 0 }
        return commit() ? changed : 0
    }
    /// Home's long-press "Move to": files a logged food under another meal (or none) without opening the editor.
    @discardableResult func setMealType(_ mealType: String?, for entry: CalorieEntry) -> Bool {
        guard entry.mealType != mealType else { return true }
        entry.mealType = mealType; entry.updatedAt = Date()
        guard commit() else { return false }
        UsageStats.shared.count(.mealMoves)
        return true
    }
    /// Saves Settings → Meal types on the profile, so it syncs with the diary.
    @discardableResult func saveMealSettings(_ settings: MealSettings) -> Bool {
        guard settings != mealSettings, let profile, let data = settings.encoded else { return settings == mealSettings }
        let before = mealSettings
        profile.mealSettingsData = data; profile.updatedAt = Date()
        guard commit() else { return false }
        if before.tracks != settings.tracks || before.byTime != settings.byTime {
            UsageStats.shared.event("mealTypes.mode", ["mode": settings.statsMode])
        }
        return true
    }
    /// Saves Progress settings on the profile, so they sync like the diary. Without a profile they last until relaunch.
    @discardableResult func saveProgressSettings(_ settings: ProgressSettings) -> Bool {
        guard settings != progressSettings else { return true }
        progressSettings = settings
        guard let profile, let data = settings.encoded else { return false }
        profile.progressSettingsData = data; profile.updatedAt = Date()
        return commit()
    }
    /// Whether any logged food (on any day) is filed under this meal type.
    func mealTypeInUse(_ id: String) -> Bool { entries.contains { $0.mealType == id } }
    func delete(_ entry: CalorieEntry) {
        let draft = EntryDraft(entry), id = entry.id, created = entry.createdAt
        context.delete(entry)
        guard commit() else { return }
        UsageStats.shared.count(.deletes)
        feedback("Entry deleted") { [weak self] in
            guard let self, !self.entries.contains(where: { $0.id == id }) else { return }
            let restored = CalorieEntry(draft: draft); restored.id = id; restored.createdAt = created
            self.context.insert(restored)
            if self.commit() { UsageStats.shared.count(.undos) }
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
        // A saved meal is a template; built from today's log, its foods don't keep that day's meal type.
        let items = items.map { item -> EntryDraft in var item = item; item.mealType = nil; return item }
        if let existing {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.componentsData = (try? JSONEncoder().encode(items)) ?? existing.componentsData; existing.updatedAt = Date()
        } else { context.insert(SavedMeal(name: name.trimmingCharacters(in: .whitespacesAndNewlines), items: items)) }
        return commit()
    }
    /// `mealType` is the meal picked for it, when adding asks for one.
    func addMeal(_ meal: SavedMeal, factor: Double = 1, date: Date, method: LogMethod = .meal, mealType: String? = nil) -> Bool {
        guard factor.isFinite, factor > 0 else { return false }
        let drafts = meal.items.enumerated().map { item -> EntryDraft in
            var draft = item.element.scaled(factor, at: date, meal: meal.id, order: item.offset)
            draft.mealType = mealType
            return draft
        }
        return add(drafts, message: "\(meal.name) added", method: method)
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
        guard cloudEnabled else { syncStatus = AppEnvironment.isDevelopment ? "Dev · saved only on this device" : "Stored on this iPhone"; return }
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
        if let error = event.error { syncStatus = "Sync paused · saved locally"; UsageStats.shared.error(.iCloud, error) }
        else if event.endDate == nil { syncStatus = "Syncing with iCloud…" }
        else if event.succeeded, event.type != .setup { syncStatus = "Last synced \(event.endDate!.formatted(date: .omitted, time: .shortened))"; refresh() }
    }
}

enum Persistence {
    static let cloudID = "iCloud.com.philstarkovich.cavecals"
    /// The app's store, shared with App Intents (Siri) running in the same process.
    @MainActor static var shared: AppStore?
    @MainActor static func sharedStore() throws -> AppStore {
        if let shared { return shared }
        let store = try make()
        shared = store
        return store
    }
    static let schema = Schema([UserProfile.self, DailyGoal.self, CalorieEntry.self, SavedMeal.self, BarcodeFood.self])
    @MainActor static func make(inMemory: Bool = false) throws -> AppStore {
        #if targetEnvironment(simulator) || CAVE_CALS_DEV
        let cloud = false
        #else
        let cloud = !inMemory
        #endif
        return try makeConfigured(inMemory: inMemory, cloud: cloud)
    }
    @MainActor private static func makeConfigured(inMemory: Bool, cloud: Bool) throws -> AppStore {
        let config = AppEnvironment.isDevelopment
            ? ModelConfiguration("CaveCalsDev", schema: schema, isStoredInMemoryOnly: inMemory, groupContainer: .none, cloudKitDatabase: .none)
            : ModelConfiguration("CaveCals", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloud ? .private(cloudID) : .none)
        do { return AppStore(container: try ModelContainer(for: schema, configurations: [config]), cloudEnabled: cloud, publishesWidget: !inMemory, persistsUsage: !inMemory, persistsFoodDefaults: !inMemory) }
        catch {
            guard cloud else { throw error }
            let local = ModelConfiguration("CaveCals", schema: schema, cloudKitDatabase: .none)
            let store = AppStore(container: try ModelContainer(for: schema, configurations: [local]), publishesWidget: !inMemory, persistsUsage: !inMemory, persistsFoodDefaults: !inMemory)
            store.syncStatus = "iCloud unavailable · saved locally"
            return store
        }
    }
}

struct HomeQuickAddDay: Codable, Equatable {
    var day: String
    var used = false
    var dismissed = false
}

struct HiddenQuickAddFood: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let hiddenAt: Date
    var returnsAt: Date { hiddenAt.addingTimeInterval(AppStore.quickAddHideDuration) }
}
