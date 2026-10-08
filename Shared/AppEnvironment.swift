import Foundation

/// One source tree, two installed apps. These values are compiled into both app and widget.
enum AppEnvironment {
    #if CAVE_CALS_DEV
    static let isDevelopment = true
    static let appID = "com.philstarkovich.cavecals.dev"
    static let urlScheme = "cavecals-dev"
    static let widgetGroup = "group.com.philstarkovich.cavecals.dev"
    #else
    static let isDevelopment = false
    static let appID = "com.philstarkovich.cavecals"
    static let urlScheme = "cavecals"
    static let widgetGroup = "group.com.philstarkovich.cavecals"
    #endif
}
