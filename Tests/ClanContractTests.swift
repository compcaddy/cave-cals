import XCTest
@testable import CaveCals

/// The app decodes real backend responses. Refresh the samples with
/// `SAVE_CLAN_SAMPLES=1 NODE_ENV=development npx tsx --test backend-tests/integration/clans.test.ts`.
final class ClanContractTests: XCTestCase {
    private func sample<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/clans/\(name).json")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func testProfileAndPreview() throws {
        XCTAssertEqual(try sample("me", as: ClanProfile.self).displayName, "Ana")
        let preview = try sample("preview", as: ClanPreview.self)
        XCTAssertEqual(preview.name, "The Cavemen")
        XCTAssertFalse(preview.alreadyMember)
    }
    func testListWithARunningChallenge() throws {
        let list = try sample("list", as: ClanList.self)
        let challenge = try XCTUnwrap(list.clans.first?.challenge)
        XCTAssertEqual(challenge.kind, .streak)
        XCTAssertTrue(challenge.joined)
        XCTAssertNotNil(challenge.streak)
    }
    func testClanPageWithAccountabilityAndBoard() throws {
        let detail = try sample("get", as: ClanDetail.self)
        XCTAssertEqual(detail.members.count, 3)
        XCTAssertEqual(detail.members.last?.name, "Cave person")
        let accountability = try XCTUnwrap(detail.accountability)
        XCTAssertEqual(accountability.mode, "percent")
        XCTAssertEqual(accountability.days.count, 7)
        XCTAssertEqual(accountability.rule.kind, .withinPercent)
        let board = try XCTUnwrap(detail.challenge)
        XCTAssertEqual(board.entrants.count, 2)
        XCTAssertEqual(board.settings.streakMode, "everyone")
    }
    func testHistoryAndAlerts() throws {
        let detail = try sample("get-history", as: ClanDetail.self)
        XCTAssertNil(detail.challenge)
        XCTAssertEqual(detail.history.first?.kind, .streak)
        struct Alerts: Decodable { let unread: Int; let alerts: [ClanAlert] }
        XCTAssertTrue(try sample("alerts", as: Alerts.self).alerts.contains { $0.kind == "nudge" })
    }
}
