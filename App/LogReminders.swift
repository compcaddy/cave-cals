import SwiftUI
import UserNotifications
#if DEBUG
import os
#endif

enum LogReminderMode: String, CaseIterable, Identifiable {
    case learned, fixed
    var id: String { rawValue }
    var title: String { self == .learned ? "Learn from my log" : "At a set time" }
}

/// When to send the morning "nothing logged yet" reminder. Pure, so the timing rules are testable.
struct LogReminderPlan {
    struct Log {
        let timestamp: Date
        let createdAt: Date
    }

    /// Until enough days are learned.
    static let defaultMinutes = 10 * 60
    static let minimumDays = 5
    static let windowDays = 21
    static let buffer = 60
    static let earliest = 6 * 60
    static let latest = 21 * 60
    /// Reminders pause after this many days in a row without logging, until the next log.
    static let idleDays = 3

    /// Learned reminder times (minutes after midnight); nil until there's enough history.
    let weekday: Int?
    let weekend: Int?

    /// Learns from the first log of each recent day, counting only entries logged on the day they belong to, so
    /// filling in yesterday tonight doesn't look like a late start.
    init(logs: [Log], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -Self.windowDays, to: today)!
        var first: [Date: Date] = [:]
        for log in logs where log.createdAt >= start && log.createdAt < today
            && calendar.isDate(log.createdAt, inSameDayAs: log.timestamp) {
            let day = calendar.startOfDay(for: log.createdAt)
            first[day] = min(first[day] ?? log.createdAt, log.createdAt)
        }
        func minutes(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        let all = first.map { (weekend: calendar.isDateInWeekend($0.key), minutes: minutes($0.value)) }
        guard all.count >= Self.minimumDays else { weekday = nil; weekend = nil; return }
        let weekdays = all.filter { !$0.weekend }.map(\.minutes), weekends = all.filter(\.weekend).map(\.minutes)
        // Weekends learn separately only when both have a few days and really start at different times.
        if weekdays.count >= 3, weekends.count >= 3, abs(Self.median(weekdays) - Self.median(weekends)) >= 45 {
            weekday = Self.reminderMinutes(weekdays)
            weekend = Self.reminderMinutes(weekends)
        } else {
            weekday = Self.reminderMinutes(all.map(\.minutes))
            weekend = weekday
        }
    }

    var isLearning: Bool { weekday == nil }

    func minutes(on day: Date, calendar: Calendar = .current) -> Int {
        (calendar.isDateInWeekend(day) ? weekend : weekday) ?? Self.defaultMinutes
    }

    /// An hour after the usual first log, but never earlier than most recent days' first logs.
    static func reminderMinutes(_ samples: [Int]) -> Int {
        let sorted = samples.sorted()
        let late = sorted[Int((Double(sorted.count) * 0.8).rounded(.up)) - 1]
        let raw = max(Int(median(sorted).rounded()) + buffer, late)
        let rounded = (raw + 4) / 5 * 5
        return min(max(rounded, earliest), latest)
    }

    static func median(_ samples: [Int]) -> Double {
        let sorted = samples.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? Double(sorted[middle - 1] + sorted[middle]) / 2 : Double(sorted[middle])
    }

    /// Reminders for today and the next three days: none on a day that already has food logged, none once the
    /// time has passed, and none at all after `idleDays` days in a row without logging. Scheduling only a few
    /// days ahead means someone who stops opening the app gets at most three reminders.
    static func reminderDates(logs: [Log], mode: LogReminderMode, fixedMinutes: Int,
                              now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let idleStart = calendar.date(byAdding: .day, value: -idleDays, to: today)!
        guard logs.contains(where: { $0.createdAt >= idleStart }) else { return [] }
        let plan = mode == .learned ? LogReminderPlan(logs: logs, now: now, calendar: calendar) : nil
        let loggedToday = logs.contains { calendar.isDate($0.timestamp, inSameDayAs: now) }
        return (0...3).compactMap { offset in
            if offset == 0 && loggedToday { return nil }
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let minutes = plan?.minutes(on: day, calendar: calendar) ?? fixedMinutes
            guard let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  date > now else { return nil }
            return date
        }
    }

    /// "8:55 AM" for Settings.
    static func timeText(_ minutes: Int, calendar: Calendar = .current) -> String {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
            .formatted(date: .omitted, time: .shortened)
    }
}

/// The morning reminder to log: at most one a day, only while nothing is logged yet, an hour after the person
/// usually starts (or at a set time). Local to this iPhone; iOS's permission prompt appears on its own after a
/// few days of logging.
@MainActor @Observable final class LogReminders {
    static let shared = LogReminders()
    /// Settings → "Remind me to log" (on once notifications are allowed).
    static let enabledKey = "logReminders.v1"
    static let modeKey = "logReminderMode.v1"
    static let timeKey = "logReminderTime.v1"
    static let defaultFixedMinutes = 9 * 60
    private static let identifierPrefix = "logReminder."

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// The latest diary, kept so Settings changes can reschedule without the store.
    private(set) var logs: [LogReminderPlan.Log] = []
    @ObservationIgnored private var scheduling: Task<Void, Never>?

    private var defaults: UserDefaults { .standard }
    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    var mode: LogReminderMode { defaults.string(forKey: Self.modeKey).flatMap(LogReminderMode.init) ?? .learned }
    var fixedMinutes: Int { defaults.object(forKey: Self.timeKey) as? Int ?? Self.defaultFixedMinutes }
    var isAllowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var isActive: Bool { isEnabled && isAllowed }

    func entriesChanged(_ entries: [CalorieEntry]) {
        logs = entries.map { LogReminderPlan.Log(timestamp: $0.timestamp, createdAt: $0.createdAt) }
        reschedule()
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        reschedule()
    }

    /// Shows iOS's permission prompt; reminders start on if it's allowed.
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { defaults.set(true, forKey: Self.enabledKey) }
        await refreshAuthorization()
    }

    /// Ask once someone has logged on a few days, so the permission prompt comes with context.
    func shouldOffer(entries: [CalorieEntry], calendar: Calendar = .current) -> Bool {
        guard authorization == .notDetermined else { return false }
        var days = Set<Date>()
        for entry in entries.reversed() where calendar.isDate(entry.createdAt, inSameDayAs: entry.timestamp) {
            days.insert(calendar.startOfDay(for: entry.createdAt))
            if days.count >= 3 { return true }
        }
        return false
    }

    func reschedule(now: Date = Date()) {
        let dates = isActive ? LogReminderPlan.reminderDates(logs: logs, mode: mode, fixedMinutes: fixedMinutes, now: now) : []
        scheduling?.cancel()
        scheduling = Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            // Once today has food, clear a reminder that's already showing.
            if logs.contains(where: { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }) {
                center.removeDeliveredNotifications(withIdentifiers: [Self.identifierPrefix + Day.key(now)])
            }
            for date in dates {
                try? await center.add(Self.request(for: date))
            }
            #if DEBUG
            Logger(subsystem: "com.philstarkovich.cavecals", category: "reminders")
                .info("scheduled \(dates.map { $0.formatted(date: .abbreviated, time: .shortened) }, privacy: .public)")
            #endif
        }
    }

    private static func request(for date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let meal = Day.mealName(at: date)
        content.title = "Nothing logged yet"
        content.body = "Cave empty today. Log your \(meal == "Snack" ? "first meal" : meal.lowercased())?"
        content.sound = .default
        content.threadIdentifier = "logReminder"
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: identifierPrefix + Day.key(date), content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    static func isReminder(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix(identifierPrefix)
    }
}

/// Tapping a reminder opens search, ready to type. It stays quiet while the app is already open.
final class LogReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LogReminderNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await LogReminders.isReminder(notification) ? [] : [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard await LogReminders.isReminder(response.notification) else { return }
        await MainActor.run { LoggingActionRouter.shared.open(.add) }
    }
}

/// Settings → Reminders: on/off, learned or set time, and what it has learned.
struct LogReminderSettingsSection: View {
    @AppStorage(LogReminders.enabledKey) private var enabled = true
    @AppStorage(LogReminders.modeKey) private var mode: LogReminderMode = .learned
    @AppStorage(LogReminders.timeKey) private var fixedMinutes = LogReminders.defaultFixedMinutes
    private var reminders: LogReminders { .shared }

    var body: some View {
        Section {
            Toggle("Remind me to log", isOn: Binding(get: { enabled && reminders.isAllowed }, set: { turnOn in
                if turnOn && reminders.authorization == .notDetermined {
                    Task { await reminders.requestPermission() }
                } else {
                    enabled = turnOn
                    reminders.reschedule()
                }
            }))
            .disabled(reminders.authorization == .denied)
            .accessibilityIdentifier("logReminders")
            if reminders.authorization == .denied {
                Button("Allow notifications in iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                .accessibilityIdentifier("openNotificationSettings")
            } else if enabled && reminders.isAllowed {
                Picker("When", selection: $mode) {
                    ForEach(LogReminderMode.allCases) { Text($0.title).tag($0) }
                }
                .hapticSelection(on: mode)
                .accessibilityIdentifier("logReminderMode")
                if mode == .fixed {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("logReminderTime")
                }
            }
        } header: { Text("Reminders") } footer: {
            Text(footer).font(.cave(.caption2))
        }
        .onChange(of: mode) { reminders.reschedule() }
        .onChange(of: fixedMinutes) { reminders.reschedule() }
    }

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: fixedMinutes / 60, minute: fixedMinutes % 60, second: 0, of: Date())! },
                set: { value in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                    fixedMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
                })
    }

    private var footer: String {
        let onlyIf = "Only if nothing’s logged yet that day."
        if reminders.authorization == .denied { return "Notifications are off for Cave Cals." }
        guard enabled && reminders.isAllowed else { return "One reminder in the morning if nothing’s logged yet." }
        if mode == .fixed { return "One reminder at \(LogReminderPlan.timeText(fixedMinutes)). \(onlyIf)" }
        let plan = LogReminderPlan(logs: reminders.logs)
        guard let weekday = plan.weekday, let weekend = plan.weekend else {
            return "\(LogReminderPlan.timeText(LogReminderPlan.defaultMinutes)) until a few more days are logged, then about an hour after you usually start. \(onlyIf)"
        }
        if weekday == weekend { return "Around \(LogReminderPlan.timeText(weekday)), about an hour after you usually start. \(onlyIf)" }
        return "Around \(LogReminderPlan.timeText(weekday)) on weekdays and \(LogReminderPlan.timeText(weekend)) on weekends, about an hour after you usually start. \(onlyIf)"
    }
}
