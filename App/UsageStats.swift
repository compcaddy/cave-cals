import Foundation
import UIKit
import WidgetKit

/// How a food got into the log, for the stats' logging-method breakdown.
enum LogMethod: String, CaseIterable {
    case quickAdd, searchHistory, searchBuiltIn, searchOnline, manual, meal, barcode, mealScan, voice, siri, copy, other
    /// The method implied by the source an entry stores (copies and Siri are passed explicitly instead).
    init(source: String) {
        switch source {
        case "suggestion": self = .quickAdd
        case "historical": self = .searchHistory
        case "common": self = .searchBuiltIn
        case "foodSearch": self = .searchOnline
        case "manual": self = .manual
        case "savedMeal": self = .meal
        case "barcode": self = .barcode
        case "aiPhoto": self = .mealScan
        case "aiVoice": self = .voice
        default: self = .other
        }
    }
}

/// A capture that returned a result; one scan can log several items.
/// `recipe` is a link import; `recipePhoto` and `recipeText` are recipe photos and pasted recipe text.
enum ScanKind: String {
    case mealScan, voice, barcode, recipe, recipePhoto, recipeText, siri
    /// Voice Log's "Type instead": a typed or pasted description.
    case voiceTyped
}

/// What put the Cave Cals+ paywall on screen.
enum PaywallTrigger: String {
    case onboarding, settings, aboutYou, siri
    case mealScanOpen, mealScanAnalyze, voiceOpen, voiceAnalyze
    case newMealPhotoOpen, newMealPhotoAnalyze, newMealVoiceOpen, newMealVoiceAnalyze
    case recipeImportOpen, recipeImport
    /// A second progress photo on one day (more angles are Cave Cals+).
    case progressPhotos
    /// Progress → Good Days vs. Over Days → Cave Coach.
    case coach
}

/// Where an error reached someone, so the admin page can show how often each feature fails.
enum StatsErrorArea: String {
    case mealScan, voice, barcode, recipe, siri, search, macroEstimate, subscription, save, iCloud, appleHealth, weights, progressPhotos
    /// Checking a discount code failed (not a code that doesn't work).
    case discountCode
    /// Cave Coach couldn't write insights.
    case coach
}

enum UsageCounter: String {
    case opens, searches, searchesAbandoned, edits, deletes, undos, doneEating, progressViews, weighIns, feedbackTaps, reminderTaps
    /// Progress photos saved, and times the Compare screen opened.
    case progressPhotos, photoCompares
    /// Logged food moved to another meal type (long-press Move to, or the editor's meal row).
    case mealMoves
}

/// Anonymous usage counts and error reports for the admin page (`backend/src/app/admin`).
///
/// Counts are kept per local calendar day in a small file and sent in one batch when the app goes to the
/// background (or on opening, if it's been a while). Nothing here touches the diary beyond counting entries;
/// food names, calories, weights, and Health data never leave the iPhone. The only typed text sent is a
/// search that found nothing anywhere, the "Other" answer to "Where did you hear about Cave Cals?", and a discount
/// code that worked. Settings → "Share anonymous usage stats" turns all of it off.
@MainActor final class UsageStats {
    static let shared = UsageStats()
    /// Settings → "Share anonymous usage stats" (on by default).
    static let sharingKey = "shareUsageStats.v1"

    struct Event: Codable, Equatable {
        var id = UUID()
        var name: String
        var at: Date
        var props: [String: String]
    }
    struct ErrorReport: Codable, Equatable {
        var id = UUID()
        var area: String
        var code: String
        var message: String
        var location: String
        var detail: String
        var at: Date
    }
    struct Pending: Codable, Equatable {
        /// Local day ("2026-10-03") → metric → count.
        var days: [String: [String: Int]] = [:]
        var events: [Event] = []
        var errors: [ErrorReport] = []
        var isEmpty: Bool { days.isEmpty && events.isEmpty && errors.isEmpty }
    }
    struct Batch: Codable, Equatable {
        /// The server applies each batch once, so a retry after a lost response never counts twice.
        var id = UUID()
        var pending: Pending
        var backfill = false
    }
    struct State: Codable, Equatable {
        /// When stats started on this iPhone. Diary entries from before it are the one-time backfill.
        var firstLaunch: Date
        var hadDataAtFirstLaunch = false
        var backfillSent = false
        var plus: Bool?
        var open = Pending()
        var sending: Batch?
        var lastSent: Date?
    }

    /// Supplies setup and feature state (goal, tracking choices, Health sharing…) with each report.
    var traits: @MainActor () -> [String: String] = { [:] }
    private weak var store: AppStore?
    private var state: State
    private let fileURL: URL?
    private let defaults: UserDefaults
    private let recording: Bool
    private var saveScheduled = false
    private var sendTask: Task<Void, Never>?
    private var recentErrors: [String: Date] = [:]
    private var widgetInstalled: Bool?
    private var lastActive: Date?
    nonisolated private static let diskQueue = DispatchQueue(label: "com.philstarkovich.cavecals.usage-stats", qos: .utility)
    private static let maxEvents = 400, maxErrors = 80

    init(fileURL: URL? = UsageStats.defaultFileURL, defaults: UserDefaults = .standard, recording: Bool = UsageStats.recordingAllowed, now: Date = Date()) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.recording = recording
        state = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(State.self, from: $0) }
            ?? State(firstLaunch: now)
    }

    /// UI tests, screenshots, previews, and unit tests never record or send anything.
    nonisolated static var recordingAllowed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return !AppEnvironment.isDevelopment && !arguments.contains("--uitesting") && !arguments.contains("--screenshots") && !ProgressPreferences.isPreview
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("UsageStats", isDirectory: true).appendingPathComponent("state-v1.json")
    }
    var isSharing: Bool { defaults.object(forKey: Self.sharingKey) as? Bool ?? true }
    private var active: Bool { recording && isSharing }
    /// What's waiting to be sent; for tests.
    var pending: Pending { state.open }
    var currentState: State { state }

    /// Called once the diary has loaded, so a first launch can tell a new person from someone who had the app before stats.
    func attach(_ store: AppStore) {
        self.store = store
        if fileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            state.hadDataAtFirstLaunch = store.profile != nil || !store.entries.isEmpty
            persistSoon()
        }
    }

    /// Turning sharing off discards anything not yet sent.
    func sharingChanged() {
        guard !isSharing else { return }
        sendTask?.cancel(); sendTask = nil
        state.open = Pending(); state.sending = nil
        persistNow()
    }

    // MARK: Recording

    func count(_ counter: UsageCounter, by amount: Int = 1, now: Date = Date()) { count(counter.rawValue, by: amount, now: now) }
    func itemsAdded(_ count: Int, method: LogMethod, now: Date = Date()) { self.count("items.\(method.rawValue)", by: count, now: now) }
    /// Undo right after adding takes the items back out of the counts.
    func itemsUndone(_ count: Int, method: LogMethod, now: Date = Date()) {
        self.count("items.\(method.rawValue)", by: -count, now: now)
        self.count(.undos, now: now)
    }
    func scan(_ kind: ScanKind, now: Date = Date()) { count("scans.\(kind.rawValue)", now: now) }
    /// `code` is the discount code applied at the time, so the admin page can count purchases per code.
    func paywallShown(_ trigger: PaywallTrigger, code: String? = nil) {
        var props = ["trigger": trigger.rawValue]
        if let code { props["code"] = code }
        event("paywall.shown", props)
    }
    /// `result` is closed, trial, purchased, restored, or unavailable.
    func paywallResult(_ trigger: PaywallTrigger, _ result: String, product: String? = nil, code: String? = nil) {
        var props = ["trigger": trigger.rawValue, "result": result]
        if let product { props["product"] = String(product.prefix(100)) }
        if let code { props["code"] = code }
        event("paywall.result", props)
    }
    /// A search that found nothing in past foods, saved meals, built-in foods, or online.
    func searchFoundNothing(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count >= 2 else { return }
        event("search.missing", ["query": String(text.prefix(100))])
    }

    func count(_ metric: String, by amount: Int = 1, now: Date = Date()) {
        guard active, amount != 0 else { return }
        state.open.days[Self.dayKey(now), default: [:]][metric, default: 0] += amount
        persistSoon()
    }

    func event(_ name: String, _ props: [String: String] = [:], now: Date = Date()) {
        guard active else { return }
        state.open.events.append(Event(name: name, at: now, props: props))
        if state.open.events.count > Self.maxEvents { state.open.events.removeFirst(state.open.events.count - Self.maxEvents) }
        persistSoon()
    }

    /// Records an error someone ran into. Cancellations and the paywall's own refusals aren't errors.
    func error(_ area: StatsErrorArea, _ error: Error, file: String = #fileID, line: Int = #line, now: Date = Date()) {
        guard let report = Self.describe(error) else { return }
        self.error(area, code: report.code, message: report.message, detail: report.detail, file: file, line: line, now: now)
    }

    func error(_ area: StatsErrorArea, code: String, message: String, detail: String = "", file: String = #fileID, line: Int = #line, now: Date = Date()) {
        guard active else { return }
        let location = "\(file):\(line)"
        // One failure repeating in a loop (every keystroke offline, say) is reported once a minute.
        let key = "\(area.rawValue)|\(code)|\(location)"
        if let last = recentErrors[key], now.timeIntervalSince(last) < 60 { return }
        recentErrors[key] = now
        state.open.errors.append(ErrorReport(area: area.rawValue, code: String(code.prefix(80)), message: String(message.prefix(500)),
                                             location: String(location.prefix(120)), detail: String(detail.prefix(2000)), at: now))
        if state.open.errors.count > Self.maxErrors { state.open.errors.removeFirst(state.open.errors.count - Self.maxErrors) }
        persistSoon()
    }

    /// Remembers Cave Cals+ membership from the latest account check, for the setup-and-features breakdown.
    func noteMembership(_ active: Bool) {
        guard recording, state.plus != active else { return }
        state.plus = active
        persistSoon()
    }

    nonisolated static func describe(_ error: Error) -> (code: String, message: String, detail: String)? {
        if error is CancellationError { return nil }
        if let error = error as? AIServiceError {
            guard !["subscription_required", "busy"].contains(error.code) else { return nil }
            return (error.code, error.message, "")
        }
        if let error = error as? URLError {
            guard error.code != .cancelled else { return nil }
            // The path only: query strings can hold what someone searched for.
            return ("URLError.\(error.code.rawValue)", error.localizedDescription, error.failingURL.map { "path \($0.path)" } ?? "")
        }
        if let error = error as? DecodingError {
            let context: DecodingError.Context? = switch error {
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c): c
            @unknown default: nil
            }
            let path = context?.codingPath.map(\.stringValue).joined(separator: ".") ?? ""
            return ("DecodingError", error.localizedDescription, "at \(path.isEmpty ? "root" : path): \(context?.debugDescription ?? "")")
        }
        let ns = error as NSError
        // HealthKit refuses writes while the iPhone is locked; sharing retries on its own.
        if ns.domain == "com.apple.healthkit" && ns.code == 6 { return nil }
        var detail = "\(String(reflecting: type(of: error))) \(ns.domain) \(ns.code)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            detail += "; underlying \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
        }
        return ("\(ns.domain).\(ns.code)", ns.localizedDescription, detail)
    }

    // MARK: Sending

    /// Counts an app open and sends if nothing has gone out for a while (people who never background the app).
    func appBecameActive(now: Date = Date()) {
        // Launch can report becoming active twice in a row.
        if let lastActive, now.timeIntervalSince(lastActive) < 5 { return }
        lastActive = now
        count(.opens, now: now)
        if state.lastSent.map({ now.timeIntervalSince($0) > 6 * 3600 }) ?? true { send() }
    }

    func send() {
        guard active, sendTask == nil, let base = Self.baseURL else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            // Finishing after the app leaves the screen; if iOS needs the time back, the unsent batch waits for next time.
            let background = BackgroundAssertion(name: "Usage stats") { [weak self] in self?.sendTask?.cancel() }
            defer { sendTask = nil; background.end() }
            if widgetInstalled == nil { widgetInstalled = await Self.hasWidget() }
            // History first, then what's built up since; at most a few requests per send.
            for _ in 0..<3 {
                guard !Task.isCancelled, let batch = nextBatch(), let body = try? payload(for: batch) else { return }
                switch await post(body, to: base) {
                case .sent, .rejected:
                    // A rejected report would never succeed, so it's dropped rather than retried forever.
                    if state.sending?.id == batch.id { state.sending = nil }
                    state.lastSent = Date()
                    persistNow()
                case .retryLater:
                    return
                }
            }
        }
    }

    /// The batch waiting to go: one already in flight, then the diary backfill, then everything recorded since.
    func nextBatch(now: Date = Date()) -> Batch? {
        if let sending = state.sending { return sending }
        if !state.backfillSent, let store {
            state.backfillSent = true
            let days = Self.backfill(store.entries.map { ($0.createdAt, $0.sourceType) }, before: state.firstLaunch)
            if !days.isEmpty {
                state.sending = Batch(pending: Pending(days: days), backfill: true)
                persistNow()
                return state.sending
            }
        }
        guard !state.open.isEmpty else { return nil }
        state.sending = Batch(pending: state.open)
        state.open = Pending()
        persistNow()
        return state.sending
    }

    /// Daily item counts for entries logged before stats started, by method.
    nonisolated static func backfill(_ entries: [(createdAt: Date, source: String)], before cutoff: Date) -> [String: [String: Int]] {
        var days: [String: [String: Int]] = [:]
        for entry in entries where entry.createdAt < cutoff {
            days[dayKey(entry.createdAt), default: [:]]["items.\(LogMethod(source: entry.source).rawValue)", default: 0] += 1
        }
        return days
    }

    private struct Payload: Encodable {
        struct App: Encodable { let version, build, os, device, environment: String }
        struct Day: Encodable { let day: String; let counts: [String: Int] }
        struct Event: Encodable { let id: String; let name: String; let at: Date; let props: [String: String] }
        struct Failure: Encodable { let id, area, code, message, location, detail: String; let at: Date }
        let install, batch: String
        let app: App
        let startedAt: Date
        let startedDay: String
        let existingUser: Bool
        let traits: [String: String]
        let backfill: Bool
        let days: [Day]
        let events: [Event]
        let errors: [Failure]
    }

    func payload(for batch: Batch) throws -> Data {
        let earliest = store?.entries.lazy.map(\.createdAt).min()
        // Diary entries from well before this iPhone's first launch mean the app was used before (here or via iCloud).
        let existing = state.hadDataAtFirstLaunch || (earliest.map { $0 < state.firstLaunch.addingTimeInterval(-3600) } ?? false)
        let started = existing ? min(earliest ?? state.firstLaunch, state.firstLaunch) : state.firstLaunch
        var traits = traits()
        traits["timeZone"] = TimeZone.current.identifier
        traits["model"] = Self.model
        if let plus = state.plus { traits["plus"] = String(plus) }
        if let widgetInstalled { traits["widget"] = String(widgetInstalled) }
        let info = Bundle.main.infoDictionary
        let body = Payload(
            install: Self.installID, batch: batch.id.uuidString.lowercased(),
            app: .init(version: info?["CFBundleShortVersionString"] as? String ?? "?", build: info?["CFBundleVersion"] as? String ?? "",
                       os: UIDevice.current.systemVersion, device: Self.device, environment: Self.environment),
            startedAt: started, startedDay: Self.dayKey(started), existingUser: existing,
            traits: traits.filter { !$0.value.isEmpty }.mapValues { String($0.prefix(200)) },
            backfill: batch.backfill,
            days: batch.pending.days.sorted { $0.key < $1.key }.map { .init(day: $0.key, counts: $0.value.filter { $0.value != 0 }) },
            events: batch.pending.events.map { .init(id: $0.id.uuidString.lowercased(), name: $0.name, at: $0.at, props: $0.props) },
            errors: batch.pending.errors.map {
                .init(id: $0.id.uuidString.lowercased(), area: $0.area, code: $0.code, message: $0.message, location: $0.location, detail: $0.detail, at: $0.at)
            })
        return try Self.makeEncoder().encode(body)
    }

    private enum Outcome { case sent, rejected, retryLater }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    private func post(_ body: Data, to base: URL) async -> Outcome {
        var request = URLRequest(url: base.appendingPathComponent("api/v1/stats"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await Self.session.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return .sent }
            // Only a malformed report is dropped; a missing endpoint, limit, or outage waits for the next send.
            return status == 400 || status == 413 ? .rejected : .retryLater
        } catch { return .retryLater }
    }

    // MARK: Storage

    private func persistSoon() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.saveScheduled = false
            self?.persistNow()
        }
    }
    private func persistNow() {
        guard recording, let fileURL else { return }
        let snapshot = state
        Self.diskQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            var folder = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
            }
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    /// Waits for queued writes (tests reopen the file right away).
    nonisolated static func waitForPendingWrites() { diskQueue.sync {} }

    // MARK: Helpers

    private static var baseURL: URL? {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator checks can send to a local backend: --stats-url http://127.0.0.1:3000
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--stats-url"), arguments.indices.contains(index + 1) { return URL(string: arguments[index + 1]) }
        #endif
        return AIConfiguration.baseURL
    }

    nonisolated static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    /// A random ID in the Keychain, so reinstalling the app on this iPhone isn't a new person.
    private static let installID: String = {
        if let saved = KeychainValue.read("stats.install"), UUID(uuidString: saved) != nil { return saved.lowercased() }
        let id = UUID().uuidString.lowercased()
        try? KeychainValue.save(id, key: "stats.install")
        return id
    }()
    private static let environment: String = {
        #if DEBUG
        return "debug"
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore"
        #endif
    }()
    private static var device: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
    private static let model: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()
    /// Reports carry ISO 8601 times; the state file keeps exact ones.
    private static func makeEncoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static func hasWidget() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { continuation.resume(returning: ((try? $0.get()) ?? []).isEmpty == false) }
        }
    }
}

/// Keeps the app running briefly after it leaves the screen, ending early if iOS asks for the time back.
@MainActor private final class BackgroundAssertion {
    private var id = UIBackgroundTaskIdentifier.invalid
    init(name: String, onExpiry: @escaping @MainActor () -> Void) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            onExpiry()
            self?.end()
        }
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
