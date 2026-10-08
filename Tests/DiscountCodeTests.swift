import XCTest
import RevenueCat
@testable import CaveCals

@MainActor
final class DiscountCodeTests: XCTestCase {
    private let sarah = AppliedDiscount(code: "SARAH", name: "Sarah", offering: "discount", deal: "Half price on Cave Cals+")

    func testCodesIgnoreCapitalsSpacesAndPunctuation() {
        XCTAssertEqual(DiscountCodes.normalize("sarah"), "SARAH")
        XCTAssertEqual(DiscountCodes.normalize(" Sarah-30 "), "SARAH30")
        XCTAssertEqual(DiscountCodes.normalize("ｓａｒａｈ"), "SARAH", "Full-width letters from some keyboards still match")
        XCTAssertEqual(DiscountCodes.normalize("#zog!"), "ZOG")
        XCTAssertEqual(DiscountCodes.normalize("café"), "CAF", "Codes are plain letters and digits, like the backend's")
        XCTAssertEqual(DiscountCodes.normalize(String(repeating: "a", count: 40)).count, 30)
    }

    func testOnlyTrainerAndSocialOpenTheCodeBox() {
        XCTAssertEqual(DiscoverySource.allCases.filter(\.expectsCode), [.trainer, .social])
        XCTAssertEqual(DiscoverySource.allCases.map(\.rawValue), ["trainer", "social", "friend", "appStore", "google", "ai", "other"],
                       "Raw values are what the admin page groups answers by")
    }

    func testTheBackendsAnswerDecodes() throws {
        let json = #"{"code":"SARAH","name":"Sarah","offering":"discount","deal":"Half price on Cave Cals+"}"#
        XCTAssertEqual(try JSONDecoder().decode(AppliedDiscount.self, from: Data(json.utf8)), sarah)
    }

    func testAnAppliedCodeIsKeptAndCanBeRemoved() {
        let saved = DiscountCodes.applied
        defer { DiscountCodes.applied = saved }
        DiscountCodes.applied = sarah
        XCTAssertEqual(DiscountCodes.applied, sarah)
        DiscountCodes.applied = nil
        XCTAssertNil(DiscountCodes.applied)
    }

    func testSubscriptionsShowTheAppliedCode() {
        let saved = DiscountCodes.applied
        defer { DiscountCodes.applied = saved }
        let subscriptions = AISubscriptions()
        subscriptions.apply(sarah)
        XCTAssertEqual(subscriptions.discount, sarah)
        XCTAssertEqual(AISubscriptions().discount, sarah, "Every paywall sees a code applied elsewhere")
        // Without RevenueCat's offerings there's nothing to show yet, and no prices to compare.
        XCTAssertNil(subscriptions.offering)
        XCTAssertEqual(subscriptions.priceComparison(for: "discount"), [])
        subscriptions.apply(nil)
        XCTAssertNil(subscriptions.discount)
    }

    func testMissingDiscountOfferingNeverOffersRegularPrices() {
        let regular = Offering(identifier: "default", serverDescription: "Regular", availablePackages: [], webCheckoutUrl: nil)
        let discounted = Offering(identifier: "discount", serverDescription: "Discount", availablePackages: [], webCheckoutUrl: nil)
        XCTAssertNil(AISubscriptions.selectedOffering(discount: sarah, all: ["default": regular], current: regular))
        XCTAssertTrue(AISubscriptions.selectedOffering(discount: sarah, all: ["discount": discounted], current: regular) === discounted)
        XCTAssertTrue(AISubscriptions.selectedOffering(discount: nil, all: ["discount": discounted], current: regular) === regular)
    }

    func testCheckingWithoutAWorkingCodeFails() async {
        let entry = DiscountCodeEntry()
        entry.code = "x"
        XCTAssertFalse(entry.canApply, "One character isn't a code")
        let result = await entry.apply(from: "setup", preview: true, subscriptions: nil)
        XCTAssertNil(result)
    }
}
