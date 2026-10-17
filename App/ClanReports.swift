import Foundation
import UIKit

/// The only diary-derived data that leaves the iPhone for clans: one small report per day. Never calories, the
/// goal itself, food, or weight.
struct ClanDayReport: Codable, Equatable {
    var day: String
    var logged: Bool
    /// A complete day by Progress's rule: 70% of the goal, or of the usual complete day without one, or Done eating.
    var fullDay: Bool
    /// Calories as a whole % of the goal; nil without a goal.
    var percentOfGoal: Int?
    /// The goal is at least the healthy minimum (1,200 women / 1,500 men); lower goals can't earn on-target days.
    var goalOk: Bool
    var doneEating: Bool

    var json: [String: Any] {
        ["day": day, "logged": logged, "fullDay": fullDay, "percentOfGoal": percentOfGoal as Any? ?? NSNull(),
         "goalOk": goalOk, "doneEating": doneEating]
    }

    /// - Parameters:
    ///   - total: the day's calories; `entries` how many foods.
    ///   - reference: the usual complete day before it (Progress's 28-day average), for days without a goal.
    static func make(day: String, total: Double, entries: Int, goal: Double?, reference: Double?, doneEating: Bool, minimumGoal: Double) -> ClanDayReport {
        let logged = entries > 0
        let full: Bool
        if !logged { full = false }
        else if doneEating { full = true }
        else if let goal, goal > 0 { full = total >= goal * ProgressData.completeShare }
        else if let reference { full = total >= reference * ProgressData.completeShare }
        // With nothing to compare against yet, a logged day counts (Progress does the same).
        else { full = true }
        let percent = goal.flatMap { $0 > 0 ? Int((total / $0 * 100).rounded()) : nil }
        return ClanDayReport(day: day, logged: logged, fullDay: full, percentOfGoal: percent,
                             goalOk: (goal ?? 0) >= minimumGoal, doneEating: doneEating)
    }
}

/// Weight challenges: the phone works out the % change from weigh-ins logged in Cave Cals (which never leave it).
struct ClanWeightReport: Equatable {
    var startReady: Bool
    var changePct: Double?
    var finalPct: Double?
    var endReady: Bool
    var json: [String: Any] {
        ["startReady": startReady, "changePct": changePct as Any? ?? NSNull(), "finalPct": finalPct as Any? ?? NSNull(), "endReady": endReady]
    }
    /// Start: the average of weigh-ins on days 1–3. Final: the average on the last 3 days. Between, the latest.
    static func make(weights: [String: Double], startsOn: String, endsOn: String, today: String) -> ClanWeightReport {
        func average(_ from: String, _ to: String) -> Double? {
            let values = weights.filter { $0.key >= from && $0.key <= to }.map(\.value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let start = average(startsOn, ClanDay.adding(2, to: startsOn))
        let latest = weights.filter { $0.key >= startsOn && $0.key <= min(today, endsOn) }.max { $0.key < $1.key }?.value
        let final = today >= ClanDay.adding(-2, to: endsOn) ? average(ClanDay.adding(-2, to: endsOn), endsOn) : nil
        func pct(_ value: Double?) -> Double? {
            guard let start, start > 0, let value else { return nil }
            return ((value - start) / start * 100 * 100).rounded() / 100
        }
        return ClanWeightReport(startReady: start != nil, changePct: pct(latest), finalPct: pct(final), endReady: final != nil)
    }
}

/// Sends today's and yesterday's reports (yesterday stays open until 9 AM) when the diary or Done eating
/// changes, on opening, and on going to the background. Only while signed in to a clan; only what changed.
@MainActor final class ClanReporter {
    static let shared = ClanReporter()
    private static let sentKey = "clanReportsSent.v1"
    private var store: AppStore?
    private var weights: WeightStore?
    private var pending: Task<Void, Never>?
    private var clans: [ClanListItem] = []
    private var sentWeights: [String: ClanWeightReport] = [:]

    func attach(_ store: AppStore, weights: WeightStore) { self.store = store; self.weights = weights }
    func clansChanged(_ clans: [ClanListItem]) {
        self.clans = clans
        sendWeights()
    }
    /// Debounced, so a burst of adds sends once.
    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.sendNow()
        }
    }
    func reports(now: Date = Date()) -> [ClanDayReport] {
        guard let store else { return [] }
        let calendar = Calendar.current
        let data = ProgressData(drafts: store.entries.map(EntryDraft.init), records: [], finishedDays: store.finishedDates(),
                                goal: { store.goal($0) }, now: now)
        let minimum = weights?.caloriePlan?.input.gender.minimumCalories ?? 1200
        return [0, 1].map { back in
            let date = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now))!
            let entries = store.dayEntries(date)
            return ClanDayReport.make(day: ClanDay.string(date), total: store.total(date), entries: entries.count,
                                      goal: store.goal(date), reference: data.referenceAverage(before: date),
                                      doneEating: store.isFinished(date), minimumGoal: minimum)
        }
    }
    func sendNow(force: Bool = false) {
        guard ClanStore.shared.signedIn, store != nil else { return }
        let reports = reports()
        var sent = (UserDefaults.standard.dictionary(forKey: Self.sentKey) as? [String: Data]) ?? [:]
        let changed = reports.filter { force || sent[$0.day] != (try? JSONEncoder().encode($0)) }
        guard !changed.isEmpty else { return }
        Task {
            do {
                struct Accepted: Decodable { let accepted: [String] }
                let result: Accepted = try await ClanClient.shared.call("clan/days", ["timeZone": TimeZone.current.identifier, "days": changed.map(\.json)])
                for report in changed where result.accepted.contains(report.day) { sent[report.day] = try? JSONEncoder().encode(report) }
                // Keep a week of what was sent.
                let oldest = ClanDay.string(Date().addingTimeInterval(-7 * 86_400))
                sent = sent.filter { $0.key >= oldest }
                UserDefaults.standard.set(sent, forKey: Self.sentKey)
            } catch {
                ClanStore.shared.handle(error)
            }
        }
        sendWeights()
    }
    private func sendWeights() {
        guard let weights, weights.tracking else { return }
        // Weigh-ins read from Apple Health never leave the iPhone, so only ones logged in Cave Cals count.
        let byDay = Dictionary(grouping: weights.records.filter { !$0.deleted && !$0.readFromHealth }, by: { ClanDay.string($0.date) })
            .compactMapValues { $0.max { $0.revision < $1.revision }?.kilograms }
        let today = ClanDay.string(Date())
        for clan in clans {
            guard let c = clan.challenge, c.kind == .weightLoss, c.joined, c.myStatus == "in", let endsOn = c.endsOn, today >= c.startsOn else { continue }
            let report = ClanWeightReport.make(weights: byDay, startsOn: c.startsOn, endsOn: endsOn, today: today)
            guard sentWeights[c.id] != report else { continue }
            sentWeights[c.id] = report
            var json = report.json; json["challengeId"] = c.id
            let fields = json
            Task { let _: [String: Bool]? = try? await ClanClient.shared.call("clan/challenge/weight", fields) }
        }
    }
}
