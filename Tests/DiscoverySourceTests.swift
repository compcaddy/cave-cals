import XCTest
@testable import CaveCals

final class DiscoverySourceTests: XCTestCase {
    func testAnswersKeepTheirStatsNames() {
        XCTAssertEqual(DiscoverySource.allCases.map(\.rawValue), ["trainer", "social", "friend", "appStore", "google", "ai", "other"],
                       "Raw values are what the admin page groups answers by")
    }
}
