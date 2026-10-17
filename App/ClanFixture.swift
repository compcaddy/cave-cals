#if DEBUG
import Foundation

/// `--clans-fixture` (DEBUG): a pretend clan server for UI tests, previews, and screenshots, so nothing reaches the
/// backend. Add `--clans-signed-out` to start at the sign-in screen, and `--clans-scenario <name>` for a set clan:
/// `empty`, `new` (no challenge, two people asking to join), or `<type>-<stage>` with type streak, team, survivor,
/// weight, or logging and stage start (starts tomorrow), mid, or end (just finished). `--clans-needs-plus` makes
/// letting in a third person ask for Cave Cals+. The boards follow the server's scoring rules (clan-rules.ts).
enum ClanFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--clans-fixture") }
    nonisolated(unsafe) static var signedIn = !ProcessInfo.processInfo.arguments.contains("--clans-signed-out")
    nonisolated(unsafe) private static var anonymous = false
    nonisolated(unsafe) private static var joinedChallenge = true
    nonisolated(unsafe) private static var extraClans: [[String: Any]] = []
    nonisolated(unsafe) private static var pending: [[String: Any]] = []
    nonisolated(unsafe) private static var requests: [(id: String, name: String)] = [("grok", "Grok"), ("moss", "Moss")]
    nonisolated(unsafe) private static var letIn: [String] = []
    nonisolated(unsafe) private static var plusBought = false

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var scenario: String? {
        guard let index = arguments.firstIndex(of: "--clans-scenario"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func respond<T: Decodable>(_ path: String, _ fields: [String: Any]) async throws -> T {
        try await Task.sleep(for: .milliseconds(150))
        let value: Any
        switch path {
        case "clan/me", "clan/me/update": value = me
        case "clan/list":
            let base: [[String: Any]] = scenario == "empty" ? [] : [listItem]
            value = ["clans": base + extraClans, "pending": pending, "unread": scenario == "empty" ? 0 : 2]
        case "clan/get": value = detail
        case "clan/preview":
            value = ["clanId": "fixture-2", "name": "Gym Crew", "memberCount": 3, "alreadyMember": false, "full": false,
                     "needsApproval": true, "pending": !pending.isEmpty]
        case "clan/join":
            pending = [["clanId": "fixture-2", "name": "Gym Crew"]]
            value = ["clanId": "fixture-2", "pending": true]
        case "clan/create":
            extraClans.append(["id": "fixture-3", "name": fields["name"] as? String ?? "New clan", "memberCount": 1, "role": "owner", "unread": 0, "challenge": NSNull()])
            value = ["clanId": "fixture-3"]
        case "clan/member/settings":
            if let a = fields["anonymous"] as? Bool { anonymous = a }
            value = ["updated": true]
        case "clan/request/decide":
            let id = fields["personId"] as? String ?? ""
            if fields["approve"] as? Bool == true {
                if arguments.contains("--clans-needs-plus") && !plusBought {
                    throw ClanError(code: "clan_needs_plus", message: "Clans of three or more need an admin with Cave Cals+.")
                }
                letIn.append(id)
            }
            requests.removeAll { $0.id == id }
            value = ["decided": true]
        case "clan/challenge/join": joinedChallenge = true; value = ["joined": true]
        case "clan/challenge/leave": joinedChallenge = false; value = ["left": true]
        case "clan/days": value = ["accepted": ((fields["days"] as? [[String: Any]]) ?? []).compactMap { $0["day"] as? String }]
        case "clan/challenge/create": value = ["challengeId": "fixture-challenge-2"]
        default: value = ["ok": true, "sent": true, "updated": true, "left": true, "deleted": true, "reported": true, "blocked": true,
                          "removed": true, "registered": true, "read": true, "signedOut": true, "saved": true, "ended": true, "joined": true]
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Days and people

    private static var today: String { ClanDay.string(Date()) }
    private static func day(_ offset: Int) -> String { ClanDay.adding(offset, to: today) }
    private static func between(_ from: String, _ to: String) -> Int {
        guard let a = ClanDay.date(from), let b = ClanDay.date(to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
    private static var me: [String: Any] {
        ["personId": "me", "displayName": "Phil", "photoId": NSNull(), "birthYear": NSNull(), "birthMonth": NSNull(), "alertPrefs": [String: Bool](), "needsName": false,
         "email": "phil@example.com", "emailPrivate": false, "newsOptIn": true]
    }
    private static let clanName = "The Fire Keepers"
    private static var people: [(id: String, name: String, anonymous: Bool)] {
        [("me", "Phil", false), ("ana", "Ana", false), ("ben", "Ben", false), ("cal", "Cal", false), ("anon", "Cave person", true), ("dee", "Dee", false)]
            + letIn.compactMap { id in [("grok", "Grok"), ("moss", "Moss")].first { $0.0 == id }.map { ($0.0, $0.1, false) } }
    }
    private static func name(_ id: String) -> String { people.first { $0.id == id }?.name ?? id }
    private static var members: [[String: Any]] {
        people.enumerated().map { index, p in
            let isMe = p.id == "me"
            return ["personId": p.id, "name": isMe && anonymous ? "Cave person (you)" : p.name, "photoId": NSNull(), "anonymous": p.anonymous || (isMe && anonymous),
                    "blocked": false, "role": index == 0 ? "owner" : index == 1 ? "admin" : "member", "isMe": isMe, "joinedAt": "2026-09-01T00:00:00Z"]
        }
    }

    // MARK: Boards

    /// `marks`: one letter per day ending today (m made, s saved, x missed, anything else blank). Days before the
    /// start never show, like the server's board.
    private static func entrant(_ id: String, status: String = "in", points: Int = 0, lives: Int? = nil, rank: Int? = nil, outOn: String? = nil,
                                loss: Double? = nil, madeToday: Bool = false, marks: String = "", startsOn: String) -> [String: Any] {
        let p = people.first { $0.id == id }!
        let letters = Array(marks.suffix(7))
        var recent: [String: Any] = [:]
        for back in 0..<7 {
            let d = day(-back)
            guard d >= startsOn else { continue }
            let index = letters.count - 1 - back
            let letter = index >= 0 ? letters[index] : " "
            recent[d] = letter == "m" ? "made" : letter == "s" ? "saved" : letter == "x" ? "missed" : NSNull() as Any
        }
        return ["personId": id, "name": p.name, "photoId": NSNull(), "anonymous": p.anonymous, "blocked": false, "isMe": id == "me",
                "status": status, "points": points, "livesLeft": lives as Any? ?? NSNull(), "rank": rank as Any? ?? NSNull(),
                "outOn": outOn as Any? ?? NSNull(), "creditedLossPct": loss as Any? ?? NSNull(), "madeToday": madeToday, "recent": recent]
    }
    private struct Board {
        var kind: String, name: String
        var settings: [String: Any] = ["basis": "logging", "anyFood": false, "streakMode": "everyone", "streakPercent": 80, "teamTarget": 100]
        var saves = 0, period = "challenge"
        var startsOn: String, endsOn: String?
        var status: String
        var entrants: [[String: Any]]
        var winners: [String] = [], endedOn: String? = nil
        var streak: [String: Any]? = nil, team: [String: Any]? = nil
        var joined = true, canJoin = false
    }
    private static func json(_ b: Board) -> [String: Any] {
        let inToday = b.entrants.filter { $0["status"] as? String == "in" && $0["madeToday"] as? Bool == true }.count
        let inCount = b.entrants.filter { $0["status"] as? String == "in" }.count
        return ["id": "fixture-\(b.kind)", "kind": b.kind, "name": b.name, "settings": b.settings, "savesCount": b.saves, "savesPeriod": b.period,
                "startsOn": b.startsOn, "endsOn": b.endsOn as Any? ?? NSNull(), "status": b.status,
                "dayNumber": max(0, between(b.startsOn, today) + 1), "totalDays": b.endsOn.map { between(b.startsOn, $0) + 1 } as Any? ?? NSNull(),
                "joined": b.joined, "canJoin": b.canJoin, "entrants": b.entrants, "winners": b.winners, "endedOn": b.endedOn as Any? ?? NSNull(),
                "streak": b.streak as Any? ?? NSNull(), "team": b.team as Any? ?? NSNull(), "inToday": inToday, "inCount": inCount]
    }
    private static func summary(_ board: [String: Any]) -> [String: Any] {
        let mine = (board["entrants"] as? [[String: Any]])?.first { $0["isMe"] as? Bool == true }
        return ["id": board["id"]!, "kind": board["kind"]!, "name": board["name"]!, "status": board["status"]!, "dayNumber": board["dayNumber"]!,
                "totalDays": board["totalDays"]!, "joined": board["joined"]!, "canJoin": board["canJoin"]!, "startsOn": board["startsOn"]!,
                "myStatus": mine?["status"] ?? NSNull(), "myRank": mine?["rank"] ?? NSNull(), "myLivesLeft": mine?["livesLeft"] ?? NSNull(),
                "myLossPct": mine?["creditedLossPct"] ?? NSNull(), "madeToday": mine?["madeToday"] ?? false,
                "inToday": board["inToday"]!, "inCount": board["inCount"]!, "streak": board["streak"]!, "team": board["team"]!]
    }

    /// The scenario's challenge: running (start, mid) or just ended (end).
    private static var scenarioBoard: (board: [String: Any], ended: Bool)? {
        guard let scenario, scenario.contains("-") else { return nil }
        let parts = scenario.split(separator: "-").map(String.init)
        let (type, stage) = (parts[0], parts[1])
        let ended = stage == "end"
        var b: Board
        switch (type, stage) {
        case ("streak", "start"):
            let s = day(1)
            b = Board(kind: "streak", name: "Streak", saves: 1, period: "week", startsOn: s, endsOn: nil, status: "upcoming",
                      entrants: ["me", "ana", "ben", "cal", "anon"].map { entrant($0, lives: 1, startsOn: s) },
                      streak: ["length": 0, "brokeOn": NSNull(), "record": 23])
        case ("streak", "mid"):
            let s = day(-9)
            b = Board(kind: "streak", name: "Streak", saves: 1, period: "week", startsOn: s, endsOn: nil, status: "active", entrants: [
                entrant("me", points: 9, lives: 1, madeToday: false, marks: "mmmmmmm ", startsOn: s),
                entrant("ana", points: 9, lives: 1, madeToday: true, marks: "mmmmmmm ", startsOn: s),
                entrant("ben", points: 8, lives: 0, madeToday: false, marks: "mmmsmmm ", startsOn: s),
                entrant("cal", points: 9, lives: 1, madeToday: true, marks: "mmmmmmm ", startsOn: s),
                entrant("anon", points: 9, lives: 1, madeToday: true, marks: "mmmmmmm ", startsOn: s),
                entrant("dee", points: 9, lives: 1, madeToday: true, marks: "mmmmmmm ", startsOn: s),
            ].map { $0 }, streak: ["length": 9, "brokeOn": NSNull(), "record": 23])
        case ("streak", "end"):
            let s = day(-14)
            b = Board(kind: "streak", name: "Streak", saves: 1, period: "week", startsOn: s, endsOn: nil, status: "ended", entrants: [
                entrant("me", points: 12, lives: 1, marks: "mmmmmm  ", startsOn: s), entrant("ana", points: 12, lives: 1, marks: "mmmmmm  ", startsOn: s),
                entrant("ben", points: 10, lives: 0, marks: "mmsmsx  ", startsOn: s), entrant("cal", points: 12, lives: 1, marks: "mmmmmm  ", startsOn: s),
                entrant("anon", points: 11, lives: 0, marks: "mmmmsm  ", startsOn: s), entrant("dee", points: 12, lives: 1, marks: "mmmmmm  ", startsOn: s),
            ], endedOn: day(-2), streak: ["length": 12, "brokeOn": day(-2), "record": 23])
        case ("team", "start"):
            let s = day(1)
            b = Board(kind: "teamTotal", name: "Clan goal", startsOn: s, endsOn: ClanDay.adding(20, to: s), status: "upcoming",
                      entrants: ["me", "ana", "ben", "cal", "anon", "dee"].map { entrant($0, startsOn: s) },
                      team: ["total": 0, "target": 100, "reached": false])
        case ("team", "mid"):
            let s = day(-10)
            let points = ["me": 10, "ana": 11, "ben": 7, "cal": 10, "anon": 9, "dee": 11]
            b = Board(kind: "teamTotal", name: "Clan goal", startsOn: s, endsOn: ClanDay.adding(20, to: s), status: "active",
                      entrants: ["ana", "dee", "me", "cal", "anon", "ben"].map { id in
                          entrant(id, points: points[id]!, madeToday: ["ana", "dee", "cal"].contains(id), marks: id == "ben" ? "mxmmxmm " : id == "anon" ? "mmmxmmm " : "mmmmmmm ", startsOn: s)
                      }, team: ["total": 58, "target": 100, "reached": false])
        case ("team", "end"):
            let s = day(-19)
            let points = ["me": 17, "ana": 18, "ben": 14, "cal": 17, "anon": 16, "dee": 18]
            b = Board(kind: "teamTotal", name: "Clan goal", startsOn: s, endsOn: ClanDay.adding(20, to: s), status: "ended",
                      entrants: ["ana", "dee", "me", "cal", "anon", "ben"].map { entrant($0, points: points[$0]!, marks: "mmmmm   ", startsOn: s) },
                      winners: ["ana", "dee", "me", "cal", "anon", "ben"], endedOn: day(-3), team: ["total": 100, "target": 100, "reached": true])
        case ("survivor", "start"):
            let s = day(1)
            b = Board(kind: "survivor", name: "Survivor", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "upcoming",
                      entrants: ["me", "ana", "ben", "cal", "anon", "dee"].map { entrant($0, lives: 0, startsOn: s) })
        case ("survivor", "mid"):
            let s = day(-6)
            b = Board(kind: "survivor", name: "Survivor", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "active", entrants: [
                entrant("ana", lives: 0, madeToday: true, marks: "mmmmmm ", startsOn: s),
                entrant("me", lives: 0, madeToday: false, marks: "mmmmmm ", startsOn: s),
                entrant("cal", lives: 0, madeToday: true, marks: "mmmmmm ", startsOn: s),
                entrant("dee", lives: 0, madeToday: true, marks: "mmmmmm ", startsOn: s),
                entrant("ben", status: "out", lives: 0, outOn: day(-3), marks: "mmx    ", startsOn: s),
                entrant("anon", status: "out", lives: 0, outOn: day(-5), marks: "x      ", startsOn: s),
            ])
        case ("survivor", "end"):
            let s = day(-11)
            // Ana was the last one standing on day 10, four days before the end date, so it ended right then.
            b = Board(kind: "survivor", name: "Survivor", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "ended", entrants: [
                entrant("ana", lives: 0, marks: "mmmmm   ", startsOn: s),
                entrant("dee", status: "out", lives: 0, outOn: day(-2), marks: "mmmmx   ", startsOn: s),
                entrant("me", status: "out", lives: 0, outOn: day(-3), marks: "mmmx    ", startsOn: s),
                entrant("cal", status: "out", lives: 0, outOn: day(-4), marks: "mmx     ", startsOn: s),
                entrant("ben", status: "out", lives: 0, outOn: day(-8), marks: "        ", startsOn: s),
                entrant("anon", status: "out", lives: 0, outOn: day(-10), marks: "        ", startsOn: s),
            ], winners: ["ana"], endedOn: day(-2))
        case ("weight", "start"):
            let s = day(1)
            b = Board(kind: "weightLoss", name: "Weight loss", startsOn: s, endsOn: ClanDay.adding(27, to: s), status: "upcoming",
                      entrants: ["ana", "dee", "cal"].map { entrant($0, startsOn: s) }, joined: false, canJoin: true)
        case ("weight", "mid"):
            let s = day(-11)
            b = Board(kind: "weightLoss", name: "Weight loss", startsOn: s, endsOn: ClanDay.adding(27, to: s), status: "active", entrants: [
                entrant("ana", rank: 1, loss: 1.6, startsOn: s), entrant("me", rank: 2, loss: 1.2, startsOn: s),
                entrant("dee", rank: 3, loss: 0.9, startsOn: s), entrant("cal", rank: 4, loss: 0.4, startsOn: s), entrant("ben", startsOn: s),
            ])
        case ("weight", "end"):
            let s = day(-29)
            b = Board(kind: "weightLoss", name: "Weight loss", startsOn: s, endsOn: ClanDay.adding(27, to: s), status: "ended", entrants: [
                entrant("ana", rank: 1, loss: 3.4, startsOn: s), entrant("me", rank: 2, loss: 2.9, startsOn: s),
                entrant("dee", rank: 3, loss: 2.1, startsOn: s), entrant("cal", rank: 4, loss: 0.8, startsOn: s), entrant("ben", startsOn: s),
            ], winners: ["ana"], endedOn: day(-2))
        case ("logging", "start"):
            let s = day(1)
            b = Board(kind: "loggingDays", name: "Logging days", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "upcoming",
                      entrants: ["me", "ana", "ben", "cal", "dee"].map { entrant($0, startsOn: s) })
        case ("logging", "mid"):
            let s = day(-8)
            b = Board(kind: "loggingDays", name: "Logging days", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "active", entrants: [
                entrant("ana", points: 8, rank: 1, madeToday: true, marks: "mmmmmmm ", startsOn: s),
                entrant("me", points: 7, rank: 2, marks: "mmmxmmm ", startsOn: s),
                entrant("dee", points: 7, rank: 2, madeToday: true, marks: "mmmmxmm ", startsOn: s),
                entrant("cal", points: 6, rank: 4, marks: "mxmmmxm ", startsOn: s),
                entrant("ben", points: 4, rank: 5, marks: "xmxmxmx ", startsOn: s),
            ])
        default: // logging-end
            let s = day(-15)
            b = Board(kind: "loggingDays", name: "Logging days", startsOn: s, endsOn: ClanDay.adding(13, to: s), status: "ended", entrants: [
                entrant("me", points: 13, rank: 1, marks: "mmmmm   ", startsOn: s), entrant("ana", points: 13, rank: 1, marks: "mmmmm   ", startsOn: s),
                entrant("dee", points: 12, rank: 3, marks: "mmxmm   ", startsOn: s), entrant("cal", points: 10, rank: 4, marks: "mxmmm   ", startsOn: s),
                entrant("ben", points: 7, rank: 5, marks: "xmxmx   ", startsOn: s),
            ], winners: ["me", "ana"], endedOn: day(-2))
        }
        return (json(b), ended)
    }

    // MARK: List and clan page

    private static var defaultBoard: [String: Any] {
        let s = day(-18)
        var b = Board(kind: "streak", name: "Streak", saves: 1, period: "week", startsOn: s, endsOn: nil, status: "active",
                      entrants: people.prefix(6).map { p in
                          entrant(p.id, points: 18, lives: 1, madeToday: ["ana", "cal", "dee", "anon"].contains(p.id), marks: "mmmmmm ", startsOn: s)
                      }, streak: ["length": 18, "brokeOn": NSNull(), "record": 23])
        b.joined = joinedChallenge
        return json(b)
    }
    private static var currentBoard: [String: Any]? {
        if scenario == "new" || scenario == "empty" { return nil }
        guard let found = scenarioBoard else { return defaultBoard }
        return found.ended ? nil : found.board
    }
    private static var listItem: [String: Any] {
        ["id": "fixture-1", "name": clanName, "memberCount": people.count, "role": "owner", "unread": 2,
         "challenge": currentBoard.map(summary) as Any? ?? NSNull()]
    }
    private static var detail: [String: Any] {
        let days = (0..<7).reversed().map { day(-$0) }
        // Full days (f), partial (p), nothing (-); today's letter is whether anything's logged yet.
        let rows: [String: String] = ["me": "fffpff-", "ana": "fffffff", "ben": "ff-fpf-", "cal": "ffffffp", "anon": "fffpf--", "dee": "fffffff",
                                      "grok": "------", "moss": "------"]
        var cells: [String: [String: Any]] = [:]
        var weekly: [String: Any] = [:]
        for p in people {
            let letters = Array(rows[p.id] ?? "-------")
            var row: [String: Any] = [:]
            for (i, d) in days.enumerated() {
                let letter = i < letters.count ? letters[i] : "-"
                if d == today { row[d] = ["state": "today", "logged": letter != "-"] }
                else { row[d] = ["state": letter == "f" ? "full" : letter == "p" ? "partial" : "none", "logged": letter != "-"] }
            }
            cells[p.id] = row
            weekly[p.id] = ["logged": letters.filter { $0 != "-" }.count, "full": letters.filter { $0 == "f" }.count, "averagePercent": NSNull()]
        }
        let ended = scenarioBoard.flatMap { $0.ended ? $0.board : nil }
        var history: [[String: Any]] = [["id": "h1", "kind": "survivor", "name": "Survivor", "startsOn": "2026-09-01", "endsOn": NSNull(), "endedAt": "2026-09-20T16:00:00Z",
                                          "result": ["winnerNames": ["Ana"], "streak": NSNull(), "team": NSNull(), "record": false]]]
        if let ended {
            let winnerNames = (ended["winners"] as? [String] ?? []).map(name)
            history.insert(["id": "h-latest", "kind": ended["kind"]!, "name": ended["name"]!, "startsOn": ended["startsOn"]!, "endsOn": ended["endsOn"]!,
                            "endedAt": "\(ended["endedOn"] as? String ?? today)T17:00:00Z",
                            "result": ["winnerNames": winnerNames, "streak": ended["streak"]!, "team": ended["team"]!, "record": false]], at: 0)
        }
        return [
            "clan": ["id": "fixture-1", "name": clanName, "inviteCode": "X7K2QM", "accountability": "logged", "rule": ["kind": "withinPercent", "percent": 5],
                     "ruleChoice": "clan", "bestStreak": 23, "createdAt": "2026-09-01T00:00:00Z", "joinMode": "approval"],
            "me": ["role": "owner", "anonymous": anonymous, "muted": false, "rule": NSNull(), "today": today],
            "hasPlus": !arguments.contains("--clans-needs-plus") || plusBought,
            "members": members,
            "accountability": ["mode": "logged", "rule": ["kind": "withinPercent", "percent": 5], "ruleChoice": "clan", "days": days, "cells": cells, "weekly": weekly],
            "challenge": currentBoard as Any? ?? NSNull(),
            "lastChallenge": ended as Any? ?? NSNull(),
            "requests": scenario == "new" ? requests.map { ["personId": $0.id, "name": $0.name, "photoId": NSNull(), "requestedAt": "2026-10-17T15:00:00Z"] } : [],
            "history": history,
        ]
    }
}
#endif
