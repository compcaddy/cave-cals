import SwiftUI
import UIKit
import AppIntents

@MainActor @Observable final class LoggingActionRouter {
    static let shared = LoggingActionRouter()
    struct Request: Equatable {
        let id = UUID()
        let action: LoggingAction
        var quickCalories = false
    }
    private(set) var pending: Request?

    func open(_ action: LoggingAction) { pending = Request(action: action) }
    func openQuickCalories() { pending = Request(action: .add, quickCalories: true) }
    @discardableResult func open(url: URL) -> Bool {
        guard let action = LoggingAction(url: url) else { return false }
        open(action)
        return true
    }
    @discardableResult func open(shortcut: UIApplicationShortcutItem) -> Bool {
        guard let action = LoggingAction(shortcutType: shortcut.type) else { return false }
        open(action)
        return true
    }
    func consume() -> LoggingAction? {
        defer { pending = nil }
        return pending?.action
    }
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
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
    case voice, meal, barcode, quickCalories
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Logging option"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .voice: "Voice Log",
        .meal: "Scan Meal",
        .barcode: "Scan Barcode",
        .quickCalories: "Quick Calories"
    ]

    @MainActor func open(using router: LoggingActionRouter = .shared) {
        switch self {
        case .voice: router.open(.voice)
        case .meal: router.open(.image)
        case .barcode: router.open(.barcode)
        case .quickCalories: router.openQuickCalories()
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
            intent: ChooseCalorieLoggingIntent(),
            phrases: ["Log food with \(.applicationName)", "Open \(.applicationName)"],
            shortTitle: "Open Cave Cals",
            systemImageName: "square.grid.2x2"
        )
    }
}
