#if DEBUG
import Foundation

/// `--clans-fixture` (DEBUG): a pretend clan server for UI tests and previews, so nothing reaches the backend.
/// Add `--clans-signed-out` to start at the sign-in screen.
enum ClanFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--clans-fixture") }
    nonisolated(unsafe) static var signedIn = !ProcessInfo.processInfo.arguments.contains("--clans-signed-out")
    nonisolated(unsafe) private static var anonymous = false
    nonisolated(unsafe) private static var joinedChallenge = true
    nonisolated(unsafe) private static var extraClans: [[String: Any]] = []

    static func respond<T: Decodable>(_ path: String, _ fields: [String: Any]) async throws -> T {
        try await Task.sleep(for: .milliseconds(150))
        let value: Any
        switch path {
        case "clan/me", "clan/me/update": value = me
        case "clan/list": value = ["clans": [listItem] + extraClans, "unread": 2]
        case "clan/get": value = detail
        case "clan/preview": value = ["clanId": "fixture-2", "name": "Gym Crew", "memberCount": 3, "alreadyMember": false, "full": false]
        case "clan/join":
            extraClans = [["id": "fixture-2", "name": "Gym Crew", "memberCount": 4, "role": "member", "unread": 0, "challenge": NSNull()]]
            value = ["clanId": "fixture-2"]
        case "clan/create":
            extraClans.append(["id": "fixture-3", "name": fields["name"] as? String ?? "New clan", "memberCount": 1, "role": "owner", "unread": 0, "challenge": NSNull()])
            value = ["clanId": "fixture-3"]
        case "clan/member/settings":
            if let a = fields["anonymous"] as? Bool { anonymous = a }
            value = ["updated": true]
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

    private static var today: String { ClanDay.string(Date()) }
    private static func day(_ back: Int) -> String { ClanDay.adding(-back, to: today) }
    private static var me: [String: Any] {
        ["personId": "me", "displayName": "Phil", "photoId": NSNull(), "birthYear": NSNull(), "birthMonth": NSNull(), "alertPrefs": [String: Bool](), "needsName": false,
         "email": "phil@example.com", "emailPrivate": false, "newsOptIn": true]
    }
    private static var summary: [String: Any] {
        ["id": "fixture-challenge", "kind": "streak", "name": "Streak", "status": "active", "dayNumber": 19, "totalDays": NSNull(),
         "joined": joinedChallenge, "canJoin": false, "startsOn": day(18), "myStatus": joinedChallenge ? "in" : NSNull(), "myRank": NSNull(),
         "myLivesLeft": 1, "myLossPct": NSNull(), "madeToday": false, "inToday": 4, "inCount": 6,
         "streak": ["length": 18, "brokeOn": NSNull(), "record": 23], "team": NSNull()]
    }
    private static var listItem: [String: Any] {
        ["id": "fixture-1", "name": "The Cavemen", "memberCount": 6, "role": "owner", "unread": 2, "challenge": summary]
    }
    private static let people: [(String, String, Bool)] = [("me", "Phil", false), ("ana", "Ana", false), ("ben", "Ben", false), ("cal", "Cal", false), ("anon", "Cave person", true), ("dee", "Dee", false)]
    private static var members: [[String: Any]] {
        people.enumerated().map { index, p in
            let isMe = p.0 == "me"
            return ["personId": p.0, "name": isMe && anonymous ? "Cave person (you)" : p.1, "photoId": NSNull(), "anonymous": p.2 || (isMe && anonymous),
                    "blocked": false, "role": index == 0 ? "owner" : index == 1 ? "admin" : "member", "isMe": isMe, "joinedAt": "2026-09-01T00:00:00Z"]
        }
    }
    private static var detail: [String: Any] {
        let days = (0..<7).reversed().map(day)
        let percents: [String: [Int?]] = [
            "me": [97, 102, 88, 99, 104, 95, nil], "ana": [92, 99, 100, 97, 93, 101, 60], "ben": [110, 96, nil, 98, 99, 100, nil],
            "cal": [99, 100, 97, 94, 98, 99, 72], "anon": [90, 95, 99, 100, 96, nil, nil], "dee": [101, 98, 105, 96, 99, 97, 85],
        ]
        var cells: [String: [String: Any]] = [:]
        var weekly: [String: Any] = [:]
        for (id, values) in percents {
            var row: [String: Any] = [:]
            for (i, d) in days.enumerated() {
                let p = values[i]
                if d == today { row[d] = ["state": "today", "logged": p != nil] }
                else if let p { row[d] = ["state": p >= 70 ? "full" : "partial", "logged": true, "percent": p, "inRange": p <= 100] }
                else { row[d] = ["state": "none", "logged": false] }
            }
            cells[id] = row
            weekly[id] = ["logged": values.dropLast().compactMap { $0 }.count, "full": values.dropLast().compactMap { $0 }.count, "averagePercent": 98]
        }
        let entrants: [[String: Any]] = people.map { p in
            ["personId": p.0, "name": p.1, "photoId": NSNull(), "anonymous": p.2, "blocked": false, "role": "member", "isMe": p.0 == "me", "joinedAt": "",
             "status": "in", "points": 18, "livesLeft": 1, "rank": NSNull(), "outOn": NSNull(), "creditedLossPct": NSNull(),
             "madeToday": ["ana", "cal", "dee", "anon"].contains(p.0), "recent": Dictionary(uniqueKeysWithValues: days.map { ($0, $0 == today ? NSNull() as Any : "made" as Any) })]
        }
        return [
            "clan": ["id": "fixture-1", "name": "The Cavemen", "inviteCode": "X7K2QM", "accountability": "percent", "rule": ["kind": "withinPercent", "percent": 5],
                     "ruleChoice": "clan", "bestStreak": 23, "createdAt": "2026-09-01T00:00:00Z"],
            "me": ["role": "owner", "anonymous": anonymous, "muted": false, "rule": NSNull(), "today": today],
            "hasPlus": true,
            "members": members,
            "accountability": ["mode": "percent", "rule": ["kind": "withinPercent", "percent": 5], "ruleChoice": "clan", "days": days, "cells": cells, "weekly": weekly],
            "challenge": [
                "id": "fixture-challenge", "kind": "streak", "name": "Streak",
                "settings": ["basis": "logging", "anyFood": false, "streakMode": "everyone", "streakPercent": 80, "teamTarget": 100],
                "savesCount": 1, "savesPeriod": "week", "startsOn": day(18), "endsOn": NSNull(), "status": "active", "dayNumber": 19, "totalDays": NSNull(),
                "joined": joinedChallenge, "canJoin": false, "entrants": entrants, "winners": [String](), "endedOn": NSNull(),
                "streak": ["length": 18, "brokeOn": NSNull(), "record": 23], "team": NSNull(), "inToday": 4, "inCount": 6,
            ],
            "history": [["id": "h1", "kind": "survivor", "name": "Survivor", "startsOn": "2026-09-01", "endsOn": NSNull(), "endedAt": "2026-09-20T16:00:00Z",
                         "result": ["winnerNames": ["Ana"], "streak": NSNull(), "team": NSNull(), "record": false]]],
        ]
    }
}
#endif
