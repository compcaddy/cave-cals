import SwiftUI
import UserNotifications
import WidgetKit

/// Runs at cold launch, before any store or background writer opens a file.
/// The pending flag stays set if any deletion fails, so partial resets never open the diary.
enum DevTestData {
    static let pendingKey = "dev.resetTestData.pending.v1"

    static func prepareForLaunch() throws {
        guard AppEnvironment.isDevelopment else { return }
        guard Bundle.main.bundleIdentifier == "com.philstarkovich.cavecals.dev" else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingKey) else { return }
        let files = FileManager.default
        // These are exclusively Dev's sandbox directories. Never follow the widget group or iCloud.
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory, .documentDirectory] {
            if let url = files.urls(for: directory, in: .userDomainMask).first {
                try clearContents(of: url, using: files)
            }
        }
        try KeychainValue.save(nil, key: "discount.code.v1")
        // Keep developer connection/access credentials; resetting a diary must not reset server quotas.
        let connection = defaults.string(forKey: "ai.debug.url")
        let testing = defaults.bool(forKey: "ai.test.enabled")
        let upgraded = defaults.bool(forKey: "ai.test.upgraded")
        UserDefaults(suiteName: AppEnvironment.widgetGroup)?.removePersistentDomain(forName: AppEnvironment.widgetGroup)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        defaults.removePersistentDomain(forName: AppEnvironment.appID)
        if let connection { defaults.set(connection, forKey: "ai.debug.url") }
        defaults.set(testing, forKey: "ai.test.enabled")
        defaults.set(upgraded, forKey: "ai.test.upgraded")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// iOS owns the sandbox's standard directories; the app may delete their contents,
    /// but removing a directory such as Library/Caches itself can fail on a device.
    /// Missing directories are expected when retrying an older, partially completed reset.
    static func clearContents(of directory: URL, using files: FileManager = .default) throws {
        let children: [URL]
        do {
            children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return
        }
        for child in children {
            try files.removeItem(at: child)
        }
    }
}

struct DevTestDataSection: View {
    @AppStorage(DevTestData.pendingKey) private var pending = false
    @State private var confirming = false

    var body: some View {
        Section {
            Text("Separate test data · iCloud and Apple Health off")
                .font(.cave(.footnote)).foregroundStyle(Color.secondary)
            Button("Reset Test Data", role: .destructive) { confirming = true }
                .accessibilityIdentifier("resetTestData")
        } header: { Text("Cave Cals Dev") } footer: {
            Text("Reset clears Dev’s diary, meals, goals, weigh-ins, photos, and settings when you close and reopen it. Your normal Cave Cals data stays untouched. Developer access settings and system permissions are kept.")
        }
        .alert("Reset Dev test data?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            Button("Reset Test Data", role: .destructive) {
                Haptics.play(.warning)
                pending = true
            }.hapticFeel(.none)
        } message: {
            Text("After confirming, close Cave Cals Dev from the app switcher and open it again. Its test data will be permanently deleted and setup will start again.")
        }
    }
}

struct DevResetPendingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Close and reopen Cave Cals Dev", systemImage: "arrow.clockwise")
        } description: {
            Text("Swipe up from the bottom and pause to open the app switcher. Swipe Cave Cals Dev away, then open it again. Your test data will be cleared before setup starts.")
        }
        .font(.cave(.body)).caveScreenBackground()
        .accessibilityIdentifier("devResetPending")
    }
}
