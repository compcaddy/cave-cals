import XCTest
import UIKit
@testable import CaveCals

@MainActor final class LoggingActionTests: XCTestCase {
    func testCaveIconAssetsAreBundledAndLoadable() {
        for glyph in CaveGlyph.allCases {
            let image = UIImage(named: glyph.rawValue)
            XCTAssertNotNil(image, "Missing cave icon: \(glyph.rawValue)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
            XCTAssertGreaterThan(image?.size.height ?? 0, 0)
        }
    }

    func testAllWidgetLinksAndQuickActionsResolve() {
        for action in LoggingAction.allCases {
            XCTAssertEqual(LoggingAction(url: action.url), action)
            XCTAssertEqual(LoggingAction(shortcutType: action.shortcutType), action)
        }
    }

    func testRejectsUnknownOrMalformedLinks() {
        for value in ["https://log/voice", "cavecals://other/voice", "cavecals://log/delete",
                      "cavecals://log/voice/extra", "cavecals://log/voice?x=1",
                      "cavecals://log/voice#extra", "cavecals://user@log/voice"] {
            XCTAssertNil(LoggingAction(url: URL(string: value)!), value)
        }
        XCTAssertNil(LoggingAction(shortcutType: "voice"))
    }

    func testPendingActionSurvivesUntilConsumedAndCanRepeat() {
        let router = LoggingActionRouter()
        XCTAssertTrue(router.open(url: LoggingAction.voice.url))
        let first = router.pending
        XCTAssertEqual(first?.action, .voice)
        XCTAssertEqual(router.consume(), .voice)
        XCTAssertNil(router.consume())
        XCTAssertTrue(router.open(shortcut: UIApplicationShortcutItem(type: LoggingAction.voice.shortcutType, localizedTitle: "Voice Log")))
        XCTAssertNotEqual(first?.id, router.pending?.id)
        XCTAssertFalse(router.open(url: URL(string: "cavecals://log/unknown")!))
        XCTAssertEqual(router.consume(), .voice)
    }

    func testInstalledShortcutDefinitionsMatchRouter() throws {
        let items = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: String]])
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(Set(items.compactMap { $0["UIApplicationShortcutItemType"] }), Set(LoggingAction.allCases.map(\.shortcutType)))
        for item in items {
            let action = try XCTUnwrap(LoggingAction(shortcutType: try XCTUnwrap(item["UIApplicationShortcutItemType"])))
            XCTAssertEqual(item["UIApplicationShortcutItemTitle"], action.title)
            XCTAssertEqual(item["UIApplicationShortcutItemIconSymbolName"], action.symbol)
        }
    }
}
