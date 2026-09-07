import Foundation

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
    var url: URL { URL(string: "cavecals://log/\(rawValue)")! }
    var shortcutType: String { "com.philstarkovich.cavecals.log.\(rawValue)" }

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "cavecals", parts.host == "log",
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
