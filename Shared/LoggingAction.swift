import Foundation
import AppIntents
import Observation
import UIKit

/// Shared by the app and widget so their URLs and destinations stay in sync.
enum LoggingAction: String, CaseIterable, Identifiable {
    case barcode, voice, image, add

    var id: String { rawValue }
    var title: String {
        switch self {
        case .barcode: "Barcode Scan"
        case .voice: "Voice Log"
        case .image: "Meal Scan"
        case .add: "Search/Add"
        }
    }
    var symbol: String {
        switch self {
        case .barcode: "barcode.viewfinder"
        case .voice: "mic"
        case .image: "photo"
        case .add: "plus"
        }
    }
    var url: URL { URL(string: "\(AppEnvironment.urlScheme)://log/\(rawValue)")! }
    var shortcutType: String { "\(AppEnvironment.appID).log.\(rawValue)" }

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == AppEnvironment.urlScheme, parts.host == "log",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              let action = Self.allCases.first(where: { parts.path == "/\($0.rawValue)" }) else { return nil }
        self = action
    }

    init?(shortcutType: String) {
        guard let action = Self.allCases.first(where: { $0.shortcutType == shortcutType }) else { return nil }
        self = action
    }
}

// Shared target membership lets foreground widget intents use the same pending request as app links.
@MainActor @Observable final class LoggingActionRouter {
    static let shared = LoggingActionRouter()
    struct Request: Equatable {
        let id = UUID()
        /// nil is an explicit Home request; no pending request is represented by pending == nil.
        let action: LoggingAction?
    }
    static let homeURL = URL(string: "\(AppEnvironment.urlScheme)://home")!
    private(set) var pending: Request?

    func open(_ action: LoggingAction) { pending = Request(action: action) }
    @discardableResult func open(url: URL) -> Bool {
        if url == Self.homeURL {
            pending = Request(action: nil)
            return true
        }
        guard let action = LoggingAction(url: url) else { return false }
        open(action)
        return true
    }
    @discardableResult func open(shortcut: UIApplicationShortcutItem) -> Bool {
        guard let action = LoggingAction(shortcutType: shortcut.type) else { return false }
        open(action)
        return true
    }
    func consume() -> Request? {
        defer { pending = nil }
        return pending
    }
}

extension LoggingAction: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Logging action"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .barcode: "Barcode Scan", .voice: "Voice Log", .image: "Meal Scan", .add: "Search/Add"
    ]
}

/// Explicit buttons support independent taps even in the small widget on iOS 17.
/// With openAppWhenRun, perform runs in the app and can retain the request through cold launch/setup.
struct OpenWidgetLoggingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open logging action"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Action") var action: LoggingAction

    init() { }
    init(action: LoggingAction) { self.action = action }

    @MainActor func perform() async throws -> some IntentResult {
        LoggingActionRouter.shared.open(action)
        return .result()
    }
}
