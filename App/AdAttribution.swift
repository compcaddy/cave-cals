import Foundation
import StoreKit

/// The value Apple's private ad measurement reports for an install that came from an ad.
///
/// After someone installs from an ad on Meta, TikTok, Google/YouTube, X, or another network, iOS sends that network
/// a delayed, anonymous postback carrying the conversion value the app last set in each of three windows. The first
/// window can carry the 6-bit `fine` value (when enough people installed from the same ad); every window carries the
/// low/medium/high `coarse` value. No identifier, diary entry, calorie, weight, or Health data is involved, and iOS
/// ignores the update for installs that didn't come from an ad. The schema is in `Documentation/AdAttribution.md`;
/// an ad network (or attribution partner) needs it to read the values.
struct AdConversion: Codable, Equatable {
    /// iOS's three postback windows, counted from the first launch: the first 2 days, days 3–7, and days 8–35.
    enum Window: Int, Codable { case first = 1, second, third }
    enum Coarse: String, Codable { case low, medium, high }

    /// The fine value's bits.
    struct Milestones: OptionSet {
        let rawValue: Int
        static let finishedSetup = Milestones(rawValue: 1)
        static let loggedFood = Milestones(rawValue: 2)
        /// Food logged on two different calendar days.
        static let loggedOnTwoDays = Milestones(rawValue: 4)
        /// Food logged from a Meal Scan or Voice Log.
        static let scannedFood = Milestones(rawValue: 8)
        static let joinedPlus = Milestones(rawValue: 16)
        static let joinedPlusYearly = Milestones(rawValue: 32)
    }

    /// A logged food: when it was entered (not the day it belongs to, so backfills and iCloud history from an earlier
    /// install don't count as activity) and its source.
    struct Log: Equatable {
        let createdAt: Date
        let source: String
    }

    /// Cave Cals+ as far as this install knows: nil before joining; `yearly` is nil when the plan isn't known.
    struct Membership: Codable, Equatable { var yearly: Bool? }

    static let windowEnds: [TimeInterval] = [2, 7, 35].map { $0 * 86_400 }

    var window: Window
    var fine: Int
    var coarse: Coarse

    /// Nil once the last window has closed: no postback can change after day 35.
    static func window(installedAt: Date, now: Date) -> Window? {
        let elapsed = now.timeIntervalSince(installedAt)
        if elapsed < windowEnds[0] { return .first }
        if elapsed < windowEnds[1] { return .second }
        return elapsed < windowEnds[2] ? .third : nil
    }

    static func make(installedAt: Date, now: Date, finishedSetup: Bool, logs: [Log], membership: Membership?,
                     calendar: Calendar = .current) -> AdConversion? {
        guard let window = window(installedAt: installedAt, now: now) else { return nil }
        let sinceInstall = logs.filter { $0.createdAt >= installedAt && $0.createdAt <= now }
        func days(_ logs: [Log]) -> Int { Set(logs.map { calendar.startOfDay(for: $0.createdAt) }).count }

        var milestones: Milestones = []
        if finishedSetup { milestones.insert(.finishedSetup) }
        if !sinceInstall.isEmpty { milestones.insert(.loggedFood) }
        if days(sinceInstall) >= 2 { milestones.insert(.loggedOnTwoDays) }
        if sinceInstall.contains(where: { $0.source == "aiPhoto" || $0.source == "aiVoice" }) { milestones.insert(.scannedFood) }
        if let membership {
            milestones.insert(.joinedPlus)
            if membership.yearly == true { milestones.insert(.joinedPlusYearly) }
        }

        // Coarse values are all small campaigns get, and the only value after day 2, so they describe this window:
        // still logging (on 2+ days after the first window) or a member.
        let coarse: Coarse
        if membership != nil {
            coarse = .high
        } else if window == .first {
            coarse = sinceInstall.isEmpty ? .low : .medium
        } else {
            let start = installedAt.addingTimeInterval(windowEnds[window.rawValue - 2])
            coarse = days(sinceInstall.filter { $0.createdAt >= start }) >= 2 ? .medium : .low
        }
        return AdConversion(window: window, fine: milestones.rawValue, coarse: coarse)
    }
}

/// Keeps the install's conversion value current. Apple only starts a window's postback once the app has updated the
/// value in it, so this runs on opening as well as when food is logged, setup finishes, or someone joins Cave Cals+.
/// Settings → "Share anonymous usage stats" turns it off, along with Apple Ads attribution in RevenueCat.
@MainActor final class AdAttribution {
    static let shared = AdAttribution()
    static let installedAtKey = "adAttributionInstalledAt.v1"
    static let membershipKey = "adAttributionPlus.v1"
    static let sentKey = "adAttributionSent.v1"
    static let errorReportedKey = "adAttributionErrorReported.v1"

    private let defaults: UserDefaults
    private let allowed: Bool
    private let send: (AdConversion) async throws -> Void
    private var logs: [AdConversion.Log] = []
    private var finishedSetup = false
    private var updateAgain = false
    /// The update on its way to iOS, if any; tests wait on it.
    private(set) var sending: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, allowed: Bool = UsageStats.recordingAllowed,
         send: @escaping (AdConversion) async throws -> Void = AdAttribution.postToApple) {
        self.defaults = defaults
        self.allowed = allowed
        self.send = send
    }

    /// Off in Dev, UI tests, previews, and unit tests, and when usage stats are turned off.
    var isMeasuring: Bool { allowed && (defaults.object(forKey: UsageStats.sharingKey) as? Bool ?? true) }

    func entriesChanged(_ entries: [CalorieEntry], finishedSetup: Bool, now: Date = Date()) {
        guard isMeasuring else { return }
        let installedAt = installedAt(now)
        guard AdConversion.window(installedAt: installedAt, now: now) != nil else { return }
        self.finishedSetup = finishedSetup
        logs = entries.compactMap { $0.createdAt >= installedAt ? AdConversion.Log(createdAt: $0.createdAt, source: $0.sourceType) : nil }
        update(now: now)
    }

    /// Joining is remembered for this install, even if the membership later ends. `yearly` nil: the plan isn't known.
    func joinedPlus(yearly: Bool?, now: Date = Date()) {
        guard isMeasuring else { return }
        let known = membership
        guard known == nil || (known?.yearly == nil && yearly != nil) else { return }
        defaults.set(try? JSONEncoder().encode(AdConversion.Membership(yearly: yearly)), forKey: Self.membershipKey)
        update(now: now)
    }

    func update(now: Date = Date()) {
        guard isMeasuring,
              let value = AdConversion.make(installedAt: installedAt(now), now: now, finishedSetup: finishedSetup, logs: logs, membership: membership),
              value != lastSent else { return }
        guard sending == nil else { updateAgain = true; return }
        // Marked sent whether or not iOS accepted it, so a failing update isn't retried (and reported) on every change.
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.sentKey)
        sending = Task {
            do { try await send(value) } catch {
                // Only the first failure per install: the simulator answers every update with SKANError.unknown.
                if !defaults.bool(forKey: Self.errorReportedKey) {
                    defaults.set(true, forKey: Self.errorReportedKey)
                    UsageStats.shared.error(.adAttribution, error)
                }
            }
            sending = nil
            if updateAgain { updateAgain = false; update() }
        }
    }

    /// Updating SKAdNetwork also updates AdAttributionKit's postbacks (Apple mirrors the call), so one call covers both.
    nonisolated static func postToApple(_ value: AdConversion) async throws {
        let coarse: SKAdNetwork.CoarseConversionValue = switch value.coarse {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
        try await SKAdNetwork.updatePostbackConversionValue(value.fine, coarseValue: coarse, lockWindow: false)
    }

    var membership: AdConversion.Membership? {
        defaults.data(forKey: Self.membershipKey).flatMap { try? JSONDecoder().decode(AdConversion.Membership.self, from: $0) }
    }
    private var lastSent: AdConversion? {
        defaults.data(forKey: Self.sentKey).flatMap { try? JSONDecoder().decode(AdConversion.self, from: $0) }
    }
    /// The first launch since install; app data (and so this) is removed when the app is deleted.
    private func installedAt(_ now: Date) -> Date {
        if let date = defaults.object(forKey: Self.installedAtKey) as? Date { return date }
        defaults.set(now, forKey: Self.installedAtKey)
        return now
    }
}
