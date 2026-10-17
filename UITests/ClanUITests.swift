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

    // MARK: Walkthrough screenshots (fixture scenarios)

    private func relaunch(_ extra: [String]) {
        app.terminate()
        app.launchArguments = ["--uitesting", "--seed-goal", "2100", "--clans-fixture"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["clans"].waitForExistence(timeout: 10))
    }
    private func openClan() {
        app.buttons["clans"].tap()
        let card = app.buttons["clanCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["inviteToClan"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.4)
    }
    private func scrollDown() { app.swipeUp(velocity: .slow); Thread.sleep(forTimeInterval: 0.6) }
    private func scrollUp() { app.swipeDown(velocity: .fast); Thread.sleep(forTimeInterval: 0.4) }

    /// Every challenge type at its start, partway, and at the end, for the owner to look over.
    func testWalkthroughChallengeStages() {
        for type in ["streak", "team", "survivor", "weight", "logging"] {
            for stage in ["start", "mid", "end"] {
                relaunch(["--clans-scenario", "\(type)-\(stage)"])
                if stage == "mid" { Thread.sleep(forTimeInterval: 1); capture("\(type) \(stage) 0 home strip") }
                openClan()
                capture("\(type) \(stage) 1 clan page")
                app.buttons["challengeCard"].firstMatch.tap()
                XCTAssertTrue(app.buttons["inviteToClan"].waitForNonExistence(timeout: 5))
                Thread.sleep(forTimeInterval: 0.8)
                capture("\(type) \(stage) 2 board")
            }
        }
    }

    /// The empty campfire, starting a clan, the clan page before any challenge (with people asking to join),
    /// both new-challenge sheets, Survivor's end date, settings, and asking to join someone else's clan.
    func testWalkthroughClanSetup() {
        relaunch(["--clans-scenario", "empty"])
        app.buttons["clans"].tap()
        XCTAssertTrue(app.buttons["startClan"].waitForExistence(timeout: 5))
        capture("setup 01 no clans")
        app.buttons["startClan"].tap()
        XCTAssertTrue(app.textFields["newClanName"].waitForExistence(timeout: 5))
        capture("setup 02 start a clan")
        Thread.sleep(forTimeInterval: 2.6)
        capture("setup 03 start a clan, next name idea")
        app.buttons["Cancel"].tap()

        relaunch(["--clans-scenario", "new", "--clans-needs-plus"])
        openClan()
        capture("setup 04 clan page, no challenge yet")
        scrollDown()
        capture("setup 05 accountability and members")
        scrollUp()
        app.buttons["approveRequest"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture("setup 06 letting in a third person")
        app.alerts.buttons["Not now"].tap()
        app.buttons["startCollab"].tap()
        XCTAssertTrue(app.buttons["challengeKind-streak"].waitForExistence(timeout: 5))
        capture("setup 07 new collab")
        app.buttons["challengeKind-teamTotal"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        capture("setup 08 clan goal")
        app.buttons["Back"].tap(); app.buttons["Cancel"].tap()
        app.buttons["startCompetition"].tap()
        XCTAssertTrue(app.buttons["challengeKind-logging"].waitForExistence(timeout: 5))
        capture("setup 09 new competition")
        app.buttons["challengeKind-logging"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        capture("setup 10 logging")
        app.buttons["Back"].tap()
        app.buttons["challengeKind-survivor"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        capture("setup 11 survivor")
        let endDate = app.switches["survivorEndDate"]
        for _ in 0..<4 where !endDate.isHittable { app.swipeUp(velocity: .slow) }
        (endDate.switches.firstMatch.exists ? endDate.switches.firstMatch : endDate).tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.swipeUp(velocity: .slow)
        capture("setup 12 survivor with an end date")
        app.buttons["Back"].tap(); app.buttons["Cancel"].tap()
        app.buttons["clanSettings"].tap()
        XCTAssertTrue(app.switches["clanAnonymous"].waitForExistence(timeout: 5))
        capture("setup 13 clan settings")
        app.swipeUp(velocity: .slow)
        capture("setup 14 clan settings, joining")

        relaunch([])
        app.buttons["clans"].tap()
        XCTAssertTrue(app.buttons["joinWithCode"].waitForExistence(timeout: 5))
        app.buttons["joinWithCode"].tap()
        let code = app.textFields["joinCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("GYM4ME")
        app.buttons["findClan"].tap()
        XCTAssertTrue(app.buttons["joinClan"].waitForExistence(timeout: 5))
        capture("setup 15 ask to join")
        app.buttons["joinClan"].tap()
        XCTAssertTrue(app.buttons["joinRequestDone"].waitForExistence(timeout: 5))
        capture("setup 16 request sent")
        app.buttons["joinRequestDone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pendingClan"].firstMatch.waitForExistence(timeout: 5))
        capture("setup 17 waiting for an admin")
    }
}
