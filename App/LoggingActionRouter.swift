import SwiftUI
import UserNotifications
import UIKit
import AppIntents

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes so tapping a reminder can cold-launch into search.
        UNUserNotificationCenter.current().delegate = LogReminderNotificationDelegate.shared
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Capture a cold-launch shortcut before SwiftUI creates the root view.
        if let shortcut = options.shortcutItem { LoggingActionRouter.shared.open(shortcut: shortcut) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(LoggingActionRouter.shared.open(shortcut: shortcutItem))
    }
}


// A fixed menu keeps the Action button useful without requiring users to build a shortcut.
enum CalorieLoggingChoice: String, AppEnum {
    case voice, meal, barcode
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Logging option"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .voice: "Voice Log",
        .meal: "Scan Meal",
        .barcode: "Scan Barcode"
    ]

    @MainActor func open(using router: LoggingActionRouter? = nil) {
        let router = router ?? .shared
        switch self {
        case .voice: router.open(.voice)
        case .meal: router.open(.image)
        case .barcode: router.open(.barcode)
        }
    }
}

// Keep the intent identity so existing Action button assignments continue to work.
struct ChooseCalorieLoggingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cave Cals"
    static let description = IntentDescription("Open Cave Cals.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct CaveCalsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food with \(.applicationName)",
                "Log food in \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log calories in \(.applicationName)",
                "Add food to \(.applicationName)",
                "Track food in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: ChooseCalorieLoggingIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Cave Cals",
            systemImageName: "square.grid.2x2"
        )
    }
}
