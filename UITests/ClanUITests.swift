import XCTest

/// Clans against the DEBUG `--clans-fixture` (a pretend server): Home's campfire, a clan, and its challenge.
final class ClanUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed-goal", "2100", "--clans-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["clans"].waitForExistence(timeout: 10))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testCampfireOpensClanAndChallengeBoard() {
        XCTAssertTrue(app.buttons["clanStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["clanStatus"].label.contains("Fire lit 18 days"))
        app.buttons["clans"].tap()
        let card = app.buttons["clanCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["inviteToClan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["accountabilityGrid"].firstMatch.exists)
        capture("Clan page")
        app.buttons["challengeCard"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Streak"].waitForExistence(timeout: 5))
        capture("Challenge board")
    }
    func testStatusStripOpensTheClan() {
        let strip = app.buttons["clanStatus"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()
        XCTAssertTrue(app.buttons["inviteToClan"].waitForExistence(timeout: 5))
    }
}
