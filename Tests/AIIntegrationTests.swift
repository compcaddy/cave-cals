import XCTest
import UIKit
import DeviceCheck
@testable import CaveCals

@MainActor final class AIIntegrationTests: XCTestCase {
    func testPaywallDismissalGateRunsOnlyOnce() {
        let gate = PaywallDismissalGate()
        var dismissals = 0
        gate.request { dismissals += 1 }
        gate.request { dismissals += 1 }
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(gate.hasRequestedDismissal)
    }

    func testDeviceKeyRecoveryOnlyRetriesRecoverableFailures() {
        XCTAssertTrue(AIBackend.needsNewDeviceKey(NSError(domain: DCError.errorDomain, code: DCError.invalidInput.rawValue)))
        XCTAssertTrue(AIBackend.needsNewDeviceKey(NSError(domain: DCError.errorDomain, code: DCError.invalidKey.rawValue)))
        XCTAssertTrue(AIBackend.needsNewDeviceKey(AIServiceError(code: "unknown_device", message: "Missing")))
        XCTAssertFalse(AIBackend.needsNewDeviceKey(NSError(domain: NSURLErrorDomain, code: DCError.invalidKey.rawValue)))
        XCTAssertFalse(AIBackend.needsNewDeviceKey(AIServiceError(code: "subscription_required", message: "Upgrade")))
        XCTAssertFalse(AIBackend.needsNewDeviceKey(NSError(domain: DCError.errorDomain, code: DCError.serverUnavailable.rawValue)))
    }
    func testDeviceCheckFailuresUseCustomerFacingMessages() {
        let invalidInput = AIBackend.customerFacingError(NSError(domain: DCError.errorDomain, code: DCError.invalidInput.rawValue))
        XCTAssertEqual(invalidInput.localizedDescription, "Cave Cals+ couldn’t verify this device right now. Please try again.")
        XCTAssertFalse(invalidInput.localizedDescription.contains("Developer Settings"))
        XCTAssertFalse(invalidInput.localizedDescription.contains(DCError.errorDomain))

        let unavailable = AIBackend.customerFacingError(NSError(domain: DCError.errorDomain, code: DCError.serverUnavailable.rawValue))
        XCTAssertTrue(unavailable.localizedDescription.contains("Check your internet connection"))
    }
    func testEmptyDeveloperTokenAlwaysSelectsProduction() {
        XCTAssertEqual(AIConfiguration.selectedURL(token: nil, override: "http://127.0.0.1:3000"), AIConfiguration.productionURL)
        XCTAssertEqual(AIConfiguration.selectedURL(token: "  ", override: "https://stale.example"), AIConfiguration.productionURL)
        XCTAssertEqual(AIConfiguration.selectedURL(token: "local-token", override: "http://127.0.0.1:3000")?.host, "127.0.0.1")
    }
    func testEstimatePreservesPortionsAndSelectedDayUntilUserSaves() throws {
        let json=Data(#"{"items":[{"name":"Eggs","calories":160,"portion":"2 large eggs","servingSize":"1 large egg","servings":2,"confidence":"medium"}],"notes":"Oil not included","transcript":"I ate two eggs"}"#.utf8)
        let result=try JSONDecoder().decode(AIResult.self,from:json)
        let date=Date(timeIntervalSince1970:1_700_000_000)
        var drafts=result.drafts(at:date,source:"aiVoice")
        let store=try Persistence.make(inMemory:true)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(drafts[0].timestamp,date)
        XCTAssertEqual(drafts[0].servingDescription,"1 large egg")
        XCTAssertEqual(drafts[0].servings,2)
        XCTAssertEqual(drafts[0].perServing,80)
        drafts[0].changeCalories(190)
        XCTAssertTrue(store.add(drafts))
        XCTAssertEqual(store.entries[0].totalCalories,190)
        XCTAssertEqual(store.entries[0].sourceType,"aiVoice")
        XCTAssertEqual(store.entries[0].timestamp,date)
    }
    func testOldEstimateFallsBackToWholePortionAsOneServing() throws {
        let json=Data(#"{"items":[{"name":"Rice","calories":300,"portion":"1.5 cups cooked rice","confidence":"medium"}],"notes":""}"#.utf8)
        let draft=try XCTUnwrap(JSONDecoder().decode(AIResult.self,from:json).drafts(at:Date(),source:"aiPhoto").first)
        XCTAssertEqual(draft.servingDescription,"1.5 cups cooked rice")
        XCTAssertEqual(draft.servings,1)
        XCTAssertEqual(draft.perServing,300)
    }
    func testMalformedMicroscopicServingFallsBackToWholePortion() throws {
        let json=Data(#"{"items":[{"name":"Rice","calories":300,"portion":"1.5 cups cooked rice","servingSize":"1 grain of rice","servings":3000,"confidence":"low"}],"notes":""}"#.utf8)
        let draft=try XCTUnwrap(JSONDecoder().decode(AIResult.self,from:json).drafts(at:Date(),source:"aiPhoto").first)
        XCTAssertEqual(draft.servingDescription,"1.5 cups cooked rice")
        XCTAssertEqual(draft.servings,1)
        XCTAssertEqual(draft.perServing,300)
    }
    func testBackendURLRequiresHTTPSOutsideLocalDevelopment() {
        XCTAssertNil(AIConfiguration.validURL("http://example.com",allowLocal:false))
        XCTAssertNil(AIConfiguration.validURL("https://user:password@example.com",allowLocal:false))
        XCTAssertNil(AIConfiguration.validURL("https://example.com/api?token=secret",allowLocal:false))
        XCTAssertNotNil(AIConfiguration.validURL("https://example.com",allowLocal:false))
        XCTAssertNotNil(AIConfiguration.validURL("http://127.0.0.1:3000",allowLocal:true))
        XCTAssertNil(AIConfiguration.validURL("http://127.0.0.1:3000",allowLocal:false))
    }
    func testLargePhotoIsDownsampledBeforeUploading() throws {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(size:CGSize(width:4000,height:3000),format:format).image {ctx in
            UIColor.orange.setFill();ctx.fill(CGRect(x:0,y:0,width:4000,height:3000))
        }
        let data=try AIInputSheet.preparePhoto(XCTUnwrap(image.pngData()))
        XCTAssertLessThanOrEqual(data.count,2*1024*1024)
        let prepared=try XCTUnwrap(UIImage(data:data))
        XCTAssertLessThanOrEqual(prepared.size.width,2048)
        XCTAssertThrowsError(try AIInputSheet.preparePhoto(Data("invalid image".utf8)))
    }
    func testDetailedPhotoShrinksFurtherWhenCompressionAloneExceedsBudget() throws {
        // Deterministic noise is deliberately difficult to compress, unlike a solid-color fixture.
        let side = 512
        var seed: UInt32 = 12345
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for index in pixels.indices where index % 4 != 3 {
            seed = 1664525 &* seed &+ 1013904223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let cgImage = try XCTUnwrap(CGImage(width: side, height: side, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let image = UIImage(cgImage: cgImage)
        let budget = 32 * 1024
        XCTAssertGreaterThan(try XCTUnwrap(image.jpegData(compressionQuality: 0.5)).count, budget)
        let output = try AIInputSheet.preparePhoto(XCTUnwrap(image.pngData()), maximumBytes: budget)
        XCTAssertLessThanOrEqual(output.count, budget)
        let prepared = try XCTUnwrap(UIImage(data: output))
        XCTAssertLessThan(prepared.size.width, CGFloat(side))
        XCTAssertEqual(prepared.size.width, prepared.size.height)
    }

}
