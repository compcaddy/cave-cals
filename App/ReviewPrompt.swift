import Foundation

/// Cave Cals' App Store and support pages.
enum CaveCalsLinks {
    static let appStoreID = "6809208501"
    /// Opens the App Store's write-a-review page directly.
    static let rate = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    static let share = URL(string: "https://apps.apple.com/app/cave-cals-ai-calorie-tracker/id\(appStoreID)")!
    static let feedback = URL(string: "https://ascbuddy.com/support/\(appStoreID)")!
}

/// "Cave Cals good?" appears once someone seems committed: the fifth food logged on one day, or tapping
/// Done eating (the first day of use counts). "Yes! Me like" hands off to Apple's rating prompt, which Apple
/// may still decline to show; "Not really" offers the feedback page. At most once every 120 days, on this iPhone.
enum ReviewPrompt {
    static let lastAskedKey = "reviewPromptLastAsked.v1"
    static let entriesPerDay = 5
    static let cooldownDays = 120

    /// Whether a day with this many foods logged is committed enough to ask.
    static func isMoment(entriesThatDay: Int) -> Bool { entriesThatDay >= entriesPerDay }

    static func isDue(lastAsked: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastAsked else { return true }
        guard let next = calendar.date(byAdding: .day, value: cooldownDays, to: lastAsked) else { return false }
        return now >= next
    }

    static var lastAsked: Date? { UserDefaults.standard.object(forKey: lastAskedKey) as? Date }
    static func recordAsked(_ now: Date = Date()) { UserDefaults.standard.set(now, forKey: lastAskedKey) }
    static var isDueNow: Bool { optedInForTesting || isDue(lastAsked: lastAsked) }

    /// UI tests and screenshots never ask, unless a DEBUG UI test opts in with `--review-prompt`.
    static var isAllowed: Bool {
        optedInForTesting || !ProcessInfo.processInfo.arguments.contains { $0 == "--uitesting" || $0 == "--screenshots" }
    }
    /// Also skips the cooldown, since the last-asked date outlives each test run.
    private static var optedInForTesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--review-prompt")
        #else
        false
        #endif
    }
}
