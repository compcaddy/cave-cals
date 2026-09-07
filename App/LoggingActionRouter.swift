import SwiftUI
import UIKit

@MainActor @Observable final class LoggingActionRouter {
    static let shared = LoggingActionRouter()
    struct Request: Equatable {
        let id = UUID()
        let action: LoggingAction
    }
    private(set) var pending: Request?

    func open(_ action: LoggingAction) { pending = Request(action: action) }
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
