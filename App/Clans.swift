import SwiftUI
import UserNotifications
import UIKit

// Clans (Documentation/Clans.md): groups that keep each other on track with accountability and challenges.
// Signing in (Apple or Google) is only needed here. The diary never leaves the iPhone: `ClanReporter` sends one
// small report per day (logged, full day, % of goal), and the server works out every mark from it.

// MARK: Days

/// Calendar days as the server writes them ("2026-10-13"), in this iPhone's time zone.
enum ClanDay {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func adding(_ days: Int, to day: String, calendar: Calendar = .current) -> String {
        guard let date = date(day, calendar: calendar), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return day }
        return string(moved, calendar: calendar)
    }
    /// "Mon, Oct 13"
    static func label(_ day: String) -> String {
        date(day)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? day
    }
    static func weekdayLetter(_ day: String) -> String {
        date(day).map { String($0.formatted(.dateTime.weekday(.narrow))) } ?? ""
    }
}

// MARK: Models (the backend's JSON; see backend/src/server/clan-api.ts)

struct ClanProfile: Decodable, Equatable {
    var personId: String
    var displayName: String
    var photoId: String?
    var birthYear: Int?
    var birthMonth: Int?
    var alertPrefs: [String: Bool]
    var needsName: Bool
    /// From Apple or Google; Apple's may be a private relay address. Missing from older servers.
    var email: String?
    var emailPrivate: Bool?
    /// "Email me Cave Cals news".
    var newsOptIn: Bool?
}
struct ClanRule: Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable { case atOrUnder, withinPercent, upToPercentOver }
    var kind: Kind = .atOrUnder
    var percent: Int = 5
    static let percents = 1...50
    /// "at or under your goal", "within 5% of your goal", "up to 5% over your goal"
    var summary: String {
        switch kind {
        case .atOrUnder: "at or under your goal"
        case .withinPercent: "within \(percent)% of your goal"
        case .upToPercentOver: "up to \(percent)% over your goal"
        }
    }
    var shortTitle: String {
        switch kind {
        case .atOrUnder: "At or under goal"
        case .withinPercent: "Within \(percent)%"
        case .upToPercentOver: "Up to \(percent)% over"
        }
    }
    var json: [String: Any] { ["kind": kind.rawValue, "percent": percent] }
}
struct ClanStreak: Decodable, Equatable { var length: Int; var brokeOn: String?; var record: Int? }
struct ClanTeam: Decodable, Equatable { var total: Int; var target: Int; var reached: Bool }
enum ChallengeKind: String, Codable, CaseIterable, Identifiable {
    case streak, loggingDays, onTargetDays, survivor, teamTotal, weightLoss
    var id: String { rawValue }
    var title: String {
        switch self {
        case .loggingDays: "Logging days"
        case .onTargetDays: "On-target days"
        case .teamTotal: "Clan goal"
        case .survivor: "Survivor"
        case .streak: "Streak"
        case .weightLoss: "Weight loss"
        }
    }
    var pitch: String {
        switch self {
        case .streak: "Keep the fire lit together. How many days in a row can the clan go?"
        case .loggingDays: "A point for every full day logged. Most points wins."
        case .onTargetDays: "A point for every full day in your range. Most points wins."
        case .survivor: "Miss a day without a life left and you’re out. Last one standing wins."
        case .teamTotal: "Pick a number of days for the whole clan to reach together, like 100 in 3 weeks. Every day someone logs adds one. Hit it before time runs out."
        case .weightLoss: "Whoever loses the biggest % of their weight wins."
        }
    }
    /// Collabs: everyone works together. Competitions: one winner (or a tie).
    var isCollab: Bool { self == .streak || self == .teamTotal }
    var symbol: String {
        switch self {
        case .streak: "flame"
        case .loggingDays: "calendar"
        case .onTargetDays: "target"
        case .survivor: "figure.run"
        case .teamTotal: "person.3"
        case .weightLoss: "scalemass"
        }
    }
}
struct ClanChallengeSettings: Decodable, Equatable {
    var basis: String
    var anyFood: Bool
    var rule: ClanRule?
    var streakMode: String
    var streakPercent: Int
    var teamTarget: Int
}
/// One challenge as the clan list shows it (and the Home strip uses).
struct ClanChallengeSummary: Decodable, Equatable, Identifiable {
    var id: String
    var kind: ChallengeKind
    var name: String
    var status: String
    var dayNumber: Int
    var totalDays: Int?
    var joined: Bool
    var canJoin: Bool
    var startsOn: String
    var myStatus: String?
    var myRank: Int?
    var myLivesLeft: Int?
    var myLossPct: Double?
    var madeToday: Bool
    var inToday: Int
    var inCount: Int
    var streak: ClanStreak?
    var team: ClanTeam?
    var endsOn: String? { totalDays.map { ClanDay.adding($0 - 1, to: startsOn) } }
}
struct ClanListItem: Decodable, Equatable, Identifiable {
    var id: String
    var name: String
    var memberCount: Int
    var role: String
    var unread: Int
    var challenge: ClanChallengeSummary?
}
struct ClanList: Decodable {
    /// A clan this person asked to join, waiting for an admin.
    struct Pending: Decodable, Equatable, Identifiable { var clanId: String; var name: String; var id: String { clanId } }
    var clans: [ClanListItem]
    var pending: [Pending]?
    var unread: Int
}
/// Someone who asked to join; admins see their real name and photo.
struct ClanJoinRequest: Decodable, Equatable, Identifiable {
    var personId: String
    var name: String
    var photoId: String?
    var requestedAt: String
    var id: String { personId }
}
struct ClanMember: Decodable, Equatable, Identifiable, Hashable {
    var personId: String
    var name: String
    var photoId: String?
    var anonymous: Bool
    var blocked: Bool
    var role: String
    var isMe: Bool
    var joinedAt: String
    var id: String { personId }
    var isAdmin: Bool { role == "owner" || role == "admin" }
}
struct ClanCell: Decodable, Equatable {
    /// today = not locked yet; none, partial, full once locked.
    var state: String
    var logged: Bool
    var percent: Int?
    var inRange: Bool?
}
struct ClanAccountability: Decodable, Equatable {
    struct Weekly: Decodable, Equatable { var logged: Int; var full: Int; var averagePercent: Int? }
    var mode: String
    var rule: ClanRule
    var ruleChoice: String
    var days: [String]
    var cells: [String: [String: ClanCell?]]
    var weekly: [String: Weekly]
}
struct ClanEntrant: Decodable, Equatable, Identifiable {
    var personId: String
    var name: String
    var photoId: String?
    var anonymous: Bool
    var blocked: Bool
    var isMe: Bool
    var status: String
    var points: Int
    var livesLeft: Int?
    var rank: Int?
    var outOn: String?
    var creditedLossPct: Double?
    var madeToday: Bool
    var recent: [String: String?]
    var id: String { personId }
}
struct ClanBoard: Decodable, Equatable, Identifiable {
    var id: String
    var kind: ChallengeKind
    var name: String
    var settings: ClanChallengeSettings
    var savesCount: Int
    var savesPeriod: String
    var startsOn: String
    var endsOn: String?
    var status: String
    var dayNumber: Int
    var totalDays: Int?
    var joined: Bool
    var canJoin: Bool
    var entrants: [ClanEntrant]
    var winners: [String]
    var endedOn: String?
    var streak: ClanStreak?
    var team: ClanTeam?
    var inToday: Int
    var inCount: Int
}
struct ClanHistoryItem: Decodable, Equatable, Identifiable {
    struct Result: Decodable, Equatable { var winnerNames: [String]?; var streak: ClanStreak?; var team: ClanTeam?; var record: Bool? }
    var id: String
    var kind: ChallengeKind
    var name: String
    var startsOn: String
    var endsOn: String?
    var endedAt: String?
    var result: Result?
}
struct ClanDetail: Decodable, Equatable {
    struct Info: Decodable, Equatable {
        var id: String
        var name: String
        var inviteCode: String
        var accountability: String
        var rule: ClanRule
        var ruleChoice: String
        var bestStreak: Int
        /// approval (an admin lets people in) or open (the code is enough). Missing from older servers.
        var joinMode: String?
    }
    struct Me: Decodable, Equatable { var role: String; var anonymous: Bool; var muted: Bool; var rule: ClanRule?; var today: String }
    var clan: Info
    var me: Me
    var hasPlus: Bool?
    var members: [ClanMember]
    var accountability: ClanAccountability?
    var challenge: ClanBoard?
    /// The challenge that just ended, shown with its final standings for three days.
    var lastChallenge: ClanBoard?
    /// People waiting to be let in (admins only).
    var requests: [ClanJoinRequest]?
    var history: [ClanHistoryItem]
    var isAdmin: Bool { me.role == "owner" || me.role == "admin" }
}
struct ClanPreview: Decodable, Equatable {
    var clanId: String; var name: String; var memberCount: Int; var alreadyMember: Bool; var full: Bool
    /// An admin has to let you in (missing from older servers, which let everyone in).
    var needsApproval: Bool?
    /// You already asked.
    var pending: Bool?
}
struct ClanAlert: Decodable, Equatable, Identifiable { var id: String; var clanId: String?; var clanName: String?; var kind: String; var createdAt: String; var read: Bool }

// MARK: Links

enum ClanLinks {
    static let site = "cavecals.com"
    static func inviteURL(_ code: String) -> URL { URL(string: "https://\(site)/join/\(code)")! }
    /// CaveCals.com/join/<CODE> (a Universal Link) or cavecals://join/<CODE>.
    static func code(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let scheme = url.scheme?.lowercased()
        let candidate: String?
        if scheme == "https", let host = url.host?.lowercased(), host == site || host == "www.\(site)",
           parts.count == 2, parts[0].lowercased() == "join" { candidate = parts[1] }
        else if scheme == AppEnvironment.urlScheme, url.host?.lowercased() == "join", parts.count == 1 { candidate = parts[0] }
        else { candidate = nil }
        guard let code = candidate.map(normalize), code.count == 6 else { return nil }
        return code
    }
    static func normalize(_ text: String) -> String {
        text.uppercased().filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }
}

/// Invite links and clan notifications open the campfire on Home.
@MainActor @Observable final class ClanRouter {
    static let shared = ClanRouter()
    struct Request: Equatable { let id = UUID(); var joinCode: String?; var clanId: String? }
    private(set) var pending: Request?
    func join(code: String) { pending = Request(joinCode: code) }
    func open(clanId: String?) { pending = Request(clanId: clanId) }
    func consume() -> Request? { defer { pending = nil }; return pending }
    /// Returns true for clan links.
    @discardableResult func handle(url: URL) -> Bool {
        guard let code = ClanLinks.code(from: url) else { return false }
        join(code: code)
        return true
    }
}

// MARK: Client

struct ClanError: LocalizedError, Equatable {
    var code: String
    var message: String
    var errorDescription: String? { message }
    static let signedOut = ClanError(code: "signed_out", message: "Sign in to use clans.")
}

/// Clan requests carry the session token from sign-in instead of an App Attest assertion each time.
actor ClanClient {
    static let shared = ClanClient()
    private let session: URLSession
    private var photoCache: [String: Data] = [:]
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }
    nonisolated static func sessionKey(_ base: URL) -> String { "clan.session." + base.absoluteString }
    nonisolated static var savedSession: String? {
        #if DEBUG
        if ClanFixture.isEnabled { return ClanFixture.signedIn ? "fixture" : nil }
        #endif
        guard let base = AIConfiguration.baseURL else { return nil }
        return KeychainValue.read(sessionKey(base))
    }
    nonisolated static func saveSession(_ token: String?) {
        #if DEBUG
        if ClanFixture.isEnabled { ClanFixture.signedIn = token != nil; return }
        #endif
        guard let base = AIConfiguration.baseURL else { return }
        try? KeychainValue.save(token, key: sessionKey(base))
    }

    func call<T: Decodable>(_ path: String, _ fields: [String: Any] = [:]) async throws -> T {
        #if DEBUG
        if ClanFixture.isEnabled { return try await ClanFixture.respond(path, fields) }
        #endif
        guard let base = AIConfiguration.baseURL, let token = Self.savedSession else { throw ClanError.signedOut }
        var request = URLRequest(url: base.appendingPathComponent("api/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Clan-Session")
        // The local backend also wants the developer token (it's never sent anywhere else).
        if let developer = AIConfiguration.developerToken { request.setValue("Bearer \(developer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        return try Self.decode(data, response)
    }
    private struct Failure: Decodable { struct Detail: Decodable { let code: String; let message: String }; let error: Detail }
    nonisolated static func decode<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                if failure.error.code == "signed_out" { saveSession(nil) }
                throw ClanError(code: failure.error.code, message: failure.error.message)
            }
            throw ClanError(code: "server", message: "The cave is unreachable right now. Please try again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    /// Profile photos, kept in memory once loaded (a photo ID never changes content).
    func photo(_ id: String) async -> Data? {
        if let cached = photoCache[id] { return cached }
        #if DEBUG
        if ClanFixture.isEnabled { return nil }
        #endif
        guard let base = AIConfiguration.baseURL, let token = Self.savedSession else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("api/v1/clan-photo/\(id)"))
        request.setValue(token, forHTTPHeaderField: "X-Clan-Session")
        if let developer = AIConfiguration.developerToken { request.setValue("Bearer \(developer)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        photoCache[id] = data
        return data
    }
}

// MARK: Store

@MainActor @Observable final class ClanStore {
    static let shared = ClanStore()
    /// Settings → Home → "Show clan status" (on by default).
    static let showsStatusKey = "showsClanStatus.v1"
    private(set) var signedIn = ClanClient.savedSession != nil
    private(set) var me: ClanProfile?
    private(set) var clans: [ClanListItem] = []
    private(set) var pending: [ClanList.Pending] = []
    private(set) var unread = 0
    private(set) var loaded = false
    var error: String?

    func refresh() async {
        signedIn = ClanClient.savedSession != nil
        guard signedIn else { clans = []; pending = []; unread = 0; me = nil; return }
        do {
            async let list: ClanList = ClanClient.shared.call("clan/list")
            async let profile: ClanProfile = ClanClient.shared.call("clan/me")
            let (l, p) = try await (list, profile)
            clans = l.clans; pending = l.pending ?? []; unread = l.unread; me = p; loaded = true; error = nil
            ClanReporter.shared.clansChanged(l.clans)
        } catch {
            handle(error)
        }
    }
    func handle(_ error: Error) {
        if (error as? ClanError) == .signedOut || (error as? ClanError)?.code == "signed_out" { signedOut() }
        else if (error as? ClanError) == nil && (error as? URLError) == nil { UsageStats.shared.error(.clans, error) }
    }
    func didSignIn(session: String) async {
        ClanClient.saveSession(session)
        signedIn = true
        await refresh()
        ClanReporter.shared.sendNow(force: true)
    }
    func signedOut() {
        ClanClient.saveSession(nil)
        signedIn = false; me = nil; clans = []; unread = 0; loaded = false
    }
    func setProfile(_ profile: ClanProfile) { me = profile }

    /// The challenge the Home strip shows: one that still needs you today, else any you're in.
    var stripItem: (clan: ClanListItem, challenge: ClanChallengeSummary)? {
        let running = clans.compactMap { clan in clan.challenge.map { (clan: clan, challenge: $0) } }
            .filter { $0.challenge.joined && $0.challenge.status == "active" }
        return running.first { $0.challenge.myStatus == "in" && !$0.challenge.madeToday } ?? running.first
    }

    /// Asks for notification permission the first time someone creates or joins a clan, then registers for pushes.
    func requestPushPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        if await center.notificationSettings().authorizationStatus == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }
    func registerPush(token: Data) {
        guard signedIn else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task { let _: [String: Bool]? = try? await ClanClient.shared.call("clan/push/register", ["token": hex, "environment": environment]) }
    }
}

// MARK: Strip text

enum ClanStatusText {
    /// The one-line Home strip: "Fire lit 18 days · 4 of 6 in today".
    static func line(_ c: ClanChallengeSummary) -> String {
        switch c.kind {
        case .streak:
            let days = c.streak?.length ?? 0
            return "Fire lit \(days) \(days == 1 ? "day" : "days") · \(c.inToday) of \(c.inCount) in today"
        case .loggingDays, .onTargetDays:
            return [dayOf(c), c.myRank.map { "You’re \(ordinal($0))" }].compactMap { $0 }.joined(separator: " · ")
        case .survivor:
            if c.myStatus == "out" { return "You’re out · \(c.inCount) left" }
            let lives = c.myLivesLeft ?? 0
            if lives == 0 { return "\(c.inCount) left · You’re still in" }
            return "\(c.inCount) left · You have \(lives) \(lives == 1 ? "life" : "lives")"
        case .teamTotal:
            return c.team.map { "\($0.total) of \($0.target) days" } ?? dayOf(c) ?? ""
        case .weightLoss:
            let week = max(1, (c.dayNumber + 6) / 7)
            var line = "Week \(week)"
            if let rank = c.myRank { line += " · You’re \(ordinal(rank))" }
            if let loss = c.myLossPct { line += " (\(loss >= 0 ? "−" : "+")\(abs(loss).formatted(.number.precision(.fractionLength(0...1))))%)" }
            return line
        }
    }
    static func dayOf(_ c: ClanChallengeSummary) -> String? {
        guard let total = c.totalDays else { return "Day \(max(1, c.dayNumber))" }
        return "Day \(min(max(1, c.dayNumber), total)) of \(total)"
    }
    static func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .ordinal; formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
