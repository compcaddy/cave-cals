import XCTest
@testable import CaveCals

@MainActor final class DevIsolationTests: XCTestCase {
    func testResetClearsContentsWithoutRemovingSandboxDirectories() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let directories = ["Application Support", "Caches", "Documents"].map { root.appendingPathComponent($0) }
        let protectedFiles = ProtectedResetDirectories(directories: directories)
        for directory in directories {
            let nested = directory.appendingPathComponent("nested")
            try files.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("test data".utf8).write(to: nested.appendingPathComponent("data.json"))
            try Data("hidden data".utf8).write(to: directory.appendingPathComponent(".hidden"))
            try DevTestData.clearContents(of: directory, using: protectedFiles)
            XCTAssertTrue(files.fileExists(atPath: directory.path))
            XCTAssertTrue(try files.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testResetCanRetryAfterAPartialOlderReset() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support") // Already removed by the old reset.
        let caches = root.appendingPathComponent("Caches")
        try files.createDirectory(at: caches, withIntermediateDirectories: true)
        let leftover = caches.appendingPathComponent("cache.json")
        try Data("test cache".utf8).write(to: leftover)
        try DevTestData.clearContents(of: support)
        // A genuine child-file error must still fail the reset rather than silently keep old data.
        XCTAssertThrowsError(try DevTestData.clearContents(of: caches, using: ProtectedResetDirectories(directories: [leftover])))
        XCTAssertTrue(files.fileExists(atPath: leftover.path))
        try DevTestData.clearContents(of: caches)
        try DevTestData.clearContents(of: caches) // Repeating a successful cleanup is harmless.
        XCTAssertTrue(files.fileExists(atPath: caches.path))
        XCTAssertTrue(try files.contentsOfDirectory(atPath: caches.path).isEmpty)
    }

    func testBuildIdentityAndLinksStayTogether() {
        #if CAVE_CALS_DEV
        XCTAssertTrue(AppEnvironment.isDevelopment)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.philstarkovich.cavecals.dev")
        XCTAssertEqual(CalorieWidgetStorage.groupID, "group.com.philstarkovich.cavecals.dev")
        XCTAssertNil(LoggingAction(url: URL(string: "cavecals://log/add")!))
        XCTAssertFalse(LoggingActionRouter().open(url: URL(string: "cavecals://home")!))
        #else
        XCTAssertFalse(AppEnvironment.isDevelopment)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.philstarkovich.cavecals")
        XCTAssertEqual(CalorieWidgetStorage.groupID, "group.com.philstarkovich.cavecals")
        XCTAssertNil(LoggingAction(url: URL(string: "cavecals-dev://log/add")!))
        #endif
        for action in LoggingAction.allCases {
            XCTAssertEqual(LoggingAction(url: action.url), action)
            XCTAssertEqual(LoggingAction(shortcutType: action.shortcutType), action)
        }
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        XCTAssertEqual(types?.first?["CFBundleURLSchemes"] as? [String], [AppEnvironment.urlScheme])
    }

    func testDevCannotExportHealthOrPurchase() async throws {
        try XCTSkipUnless(AppEnvironment.isDevelopment)
        XCTAssertFalse(WeightHealthExporter().available)
        XCTAssertFalse(NutritionHealthWriter().available)
        XCTAssertFalse(UsageStats.recordingAllowed)
        let subscription = AISubscriptions()
        let result = await subscription.restore()
        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        let store = try Persistence.make(inMemory: true)
        XCTAssertFalse(store.cloudEnabled)
        XCTAssertEqual(store.container.configurations.first?.name, "CaveCalsDev")
    }
}

/// Reproduces a device's protected container directories even on a permissive simulator.
private final class ProtectedResetDirectories: FileManager, @unchecked Sendable {
    private let protectedPaths: Set<String>
    init(directories: [URL]) {
        protectedPaths = Set(directories.map { $0.standardizedFileURL.path })
        super.init()
    }
    override func removeItem(at URL: URL) throws {
        if protectedPaths.contains(URL.standardizedFileURL.path) { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
    }
}
