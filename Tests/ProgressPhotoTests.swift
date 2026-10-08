import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import CaveCals

@MainActor final class ProgressPhotoTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProgressPhotoTests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A small JPEG with a capture date and a location, like one from the Photos library.
    private func sampleJPEG(taken: String? = "2026:09:01 08:30:00", width: Int = 3000, height: Int = 4000) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N"]]
        if let taken { properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: taken] }
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    // MARK: Labels

    func testTypedLabelsAreTrimmedCappedAndMatchKnownSpellings() {
        XCTAssertEqual(ProgressPhotoTag.clean("  front  "), "Front")
        XCTAssertEqual(ProgressPhotoTag.clean("LEFT   side"), "Left Side")
        XCTAssertEqual(ProgressPhotoTag.clean("flexing", known: ["Flexing"]), "Flexing")
        XCTAssertEqual(ProgressPhotoTag.clean("  Waist\n close-up "), "Waist close-up")
        XCTAssertNil(ProgressPhotoTag.clean("   \n "))
        XCTAssertEqual(ProgressPhotoTag.clean(String(repeating: "a", count: 40))?.count, ProgressPhotoTag.maxLength)
        XCTAssertTrue(ProgressPhotoTag.same("Côté", "cote"))
    }

    func testDayPhotosSortStandardAnglesFirstThenTypedLabels() {
        let day = date(9, 1)
        let photos = [("Waist", 0), ("Back", 1), ("Arms", 2), ("Front", 3), ("Front", 4)].map { tag, minute in
            ProgressPhoto(date: day, tag: tag, source: .frontCamera, added: day.addingTimeInterval(Double(minute) * 60))
        }
        XCTAssertEqual(ProgressPhotoTag.sorted(photos).map(\.tag), ["Front", "Front", "Back", "Arms", "Waist"])
        XCTAssertEqual(ProgressPhotoTag.sorted(photos).first?.added, day.addingTimeInterval(180))
    }

    func testChoicesOfferStandardAnglesThenTypedLabelsMostRecentFirst() {
        let photos = [
            ProgressPhoto(date: date(9, 1), tag: "Arms", source: .library, added: date(9, 1)),
            ProgressPhoto(date: date(9, 2), tag: "Waist", source: .library, added: date(9, 2)),
            ProgressPhoto(date: date(9, 3), tag: "arms", source: .library, added: date(9, 3)),
            ProgressPhoto(date: date(9, 3), tag: "front", source: .library, added: date(9, 3)),
        ]
        XCTAssertEqual(ProgressPhotoTag.choices(from: photos), ["Front", "Back", "Left Side", "Right Side", "arms", "Waist"])
    }

    func testNextAngleSkipsTakenOnesAndStaysPutWhenAllAreTaken() {
        XCTAssertEqual(ProgressPhotoTag.next(after: "", taken: []), "Front")
        XCTAssertEqual(ProgressPhotoTag.next(after: "Front", taken: ["Front"]), "Back")
        XCTAssertEqual(ProgressPhotoTag.next(after: "Front", taken: ["Front", "Back"]), "Left Side")
        XCTAssertEqual(ProgressPhotoTag.next(after: "Right Side", taken: ["Right Side"]), "Front")
        XCTAssertEqual(ProgressPhotoTag.next(after: "Waist", taken: ["Front"]), "Back")
        XCTAssertEqual(ProgressPhotoTag.next(after: "Back", taken: ProgressPhotoTag.standard), "Back")
    }

    // MARK: Free limit, weights, and wording

    func testOnePhotoADayIsFreeAndMembersHaveNoLimit() {
        XCTAssertFalse(ProgressPhotoQuota.needsPlus(photosThatDay: 0, isPlus: false))
        XCTAssertTrue(ProgressPhotoQuota.needsPlus(photosThatDay: 1, isPlus: false))
        XCTAssertTrue(ProgressPhotoQuota.needsPlus(photosThatDay: 4, isPlus: false))
        XCTAssertFalse(ProgressPhotoQuota.needsPlus(photosThatDay: 4, isPlus: true))
    }

    func testWeightNearAPhotoPrefersTheSameDayThenTheClosestWithinThreeDays() {
        let records = [
            WeightRecord(date: date(9, 1, hour: 7), kilograms: 80),
            WeightRecord(date: date(9, 4, hour: 7), kilograms: 79),
            WeightRecord(date: date(9, 6, hour: 7), kilograms: 78.5),
        ]
        let same = ProgressPhotoWeight.near(date(9, 4, hour: 20), in: records, calendar: calendar)
        XCTAssertEqual(same?.record.kilograms, 79); XCTAssertEqual(same?.sameDay, true)
        // Sept 5 is one day from both the 4th and the 6th; the earlier wins.
        let tie = ProgressPhotoWeight.near(date(9, 5), in: records, calendar: calendar)
        XCTAssertEqual(tie?.record.kilograms, 79); XCTAssertEqual(tie?.sameDay, false)
        XCTAssertEqual(ProgressPhotoWeight.near(date(9, 9), in: records, calendar: calendar)?.record.kilograms, 78.5)
        XCTAssertNil(ProgressPhotoWeight.near(date(9, 10), in: records, calendar: calendar))
    }

    func testComparisonWordingCoversSpanAndWeightChange() {
        XCTAssertEqual(ProgressPhotoFormat.span(days: 0), "Same day")
        XCTAssertEqual(ProgressPhotoFormat.span(days: 1), "1 day apart")
        XCTAssertEqual(ProgressPhotoFormat.span(days: -10), "10 days apart")
        XCTAssertEqual(ProgressPhotoFormat.span(days: 14), "2 weeks apart")
        XCTAssertEqual(ProgressPhotoFormat.span(days: 69), "10 weeks apart")
        XCTAssertEqual(ProgressPhotoFormat.span(days: 70), "2 months apart")
        XCTAssertEqual(ProgressPhotoFormat.span(days: 365), "12 months apart")
        let before = ProgressPhoto(date: date(7, 1), tag: "Front", source: .frontCamera)
        let after = ProgressPhoto(date: date(9, 23), tag: "Front", source: .frontCamera)
        let records = [WeightRecord(date: date(7, 1), kilograms: WeightUnit.pounds.kilograms(190)),
                       WeightRecord(date: date(9, 22), kilograms: WeightUnit.pounds.kilograms(181.6))]
        XCTAssertEqual(ProgressPhotoFormat.comparison(before, after, records: records, unit: .pounds, calendar: calendar),
                       "3 months apart · ↓ 8.4 lb")
        XCTAssertEqual(ProgressPhotoFormat.comparison(before, after, records: [], unit: .pounds, calendar: calendar), "3 months apart")
        XCTAssertEqual(ProgressPhotoFormat.weight((records[1], false), unit: .pounds), "≈ 181.6 lb")
    }

    // MARK: Images

    func testPreparingAPhotoShrinksItAndDropsItsMetadata() throws {
        let original = try sampleJPEG()
        let prepared = try ProgressPhotoImage.prepare(original)
        let full = try XCTUnwrap(pixelSize(prepared.full)), thumbnail = try XCTUnwrap(pixelSize(prepared.thumbnail))
        XCTAssertEqual(max(full.width, full.height), ProgressPhotoImage.fullPixels)
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), ProgressPhotoImage.thumbnailPixels)
        XCTAssertGreaterThan(full.height, full.width, "Portrait stays portrait")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.full as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary], "Location never stays with a saved photo")
        XCTAssertNil(ProgressPhotoImage.captureDate(prepared.full))
        XCTAssertThrowsError(try ProgressPhotoImage.prepare(Data("not a photo".utf8)))
    }

    func testCaptureDateComesFromThePhotosOwnMetadata() throws {
        let taken = try XCTUnwrap(ProgressPhotoImage.captureDate(try sampleJPEG(width: 30, height: 40)))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: taken)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 9, 1, 8, 30])
        XCTAssertNil(ProgressPhotoImage.captureDate(try sampleJPEG(taken: nil, width: 30, height: 40)))
    }

    // MARK: Store

    func testSavedPhotosReloadEditAndDeleteWithTheirFiles() async throws {
        let store = ProgressPhotoStore(folder: folder)
        let now = Date()
        let front = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 300, height: 400), date: now, tag: "Front", source: .frontCamera))
        let side = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 300, height: 400), date: now, tag: "Left Side", source: .backCamera))
        XCTAssertEqual(store.photos(on: now).map(\.tag), ["Front", "Left Side"])
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(names, ["photos-v1.json", "\(front.id.uuidString).jpg", "\(front.id.uuidString)-thumb.jpg",
                               "\(side.id.uuidString).jpg", "\(side.id.uuidString)-thumb.jpg"])
        let backups = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(backups.isExcludedFromBackup, false, "Photos stay in iPhone backups so a new iPhone keeps them")

        let reopened = ProgressPhotoStore(folder: folder)
        reopened.loadIfNeeded()
        XCTAssertEqual(reopened.photos.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
                       [front.id, side.id].sorted(by: { $0.uuidString < $1.uuidString }))
        let thumbnail = await reopened.thumbnail(front)
        XCTAssertNotNil(thumbnail)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(reopened.update(side.id, tag: "Waist", date: yesterday, now: now))
        XCTAssertEqual(reopened.photos(on: yesterday).map(\.tag), ["Waist"])
        XCTAssertEqual(reopened.photos(on: now).map(\.tag), ["Front"])
        XCTAssertTrue(reopened.update(front.id, tag: "Back", date: now, now: now))
        XCTAssertEqual(reopened.photos(on: now).first?.date, front.date, "Relabeling on the same day keeps its time")

        XCTAssertTrue(reopened.delete(side.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(side.id.uuidString).jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(side.id.uuidString)-thumb.jpg").path))
        let again = ProgressPhotoStore(folder: folder); again.loadIfNeeded()
        XCTAssertEqual(again.photos.map(\.tag), ["Back"])
    }

    func testGhostIsTheLatestPhotoAtThatAnglePreferringTheSameCamera() async throws {
        let store = ProgressPhotoStore(inMemory: true)
        let now = Date()
        func day(_ ago: Int) -> Date { Calendar.current.date(byAdding: .day, value: -ago, to: now)! }
        let oldFront = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 30, height: 40), date: day(14), tag: "Front", source: .frontCamera))
        let mirror = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 30, height: 40), date: day(7), tag: "front", source: .backCamera))
        _ = await store.add(try sampleJPEG(width: 30, height: 40), date: day(1), tag: "Back", source: .frontCamera)
        XCTAssertEqual(store.ghost(for: "Front", source: .frontCamera)?.id, oldFront.id)
        XCTAssertEqual(store.ghost(for: "Front", source: .backCamera)?.id, mirror.id)
        XCTAssertEqual(store.ghost(for: "Front", source: .library)?.id, mirror.id, "Otherwise the latest at that angle")
        XCTAssertNil(store.ghost(for: "Left Side", source: .frontCamera))
        XCTAssertEqual(store.comparableTags, ["Front"])
        XCTAssertEqual(store.series("FRONT").map(\.id), [oldFront.id, mirror.id])
        XCTAssertEqual(store.days().count, 3)
    }

    func testUnreadableIndexIsNeverOverwrittenAndStrayImagesAreCleared() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = folder.appendingPathComponent("photos-v1.json")
        try Data("{broken".utf8).write(to: index)
        let broken = ProgressPhotoStore(folder: folder)
        broken.loadIfNeeded()
        XCTAssertNotNil(broken.error)
        let refused = await broken.add(try sampleJPEG(width: 30, height: 40), date: Date(), tag: "Front", source: .library)
        XCTAssertNil(refused)
        XCTAssertEqual(try Data(contentsOf: index), Data("{broken".utf8))

        // A saved index with an image left behind by an interrupted save.
        try FileManager.default.removeItem(at: folder)
        let store = ProgressPhotoStore(folder: folder)
        let kept = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 30, height: 40), date: Date(), tag: "Front", source: .library))
        let stray = folder.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data("orphan".utf8).write(to: stray)
        let reopened = ProgressPhotoStore(folder: folder)
        reopened.loadIfNeeded()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(kept.id.uuidString).jpg").path))
    }

    func testFutureDatesAreHeldToNow() async throws {
        let store = ProgressPhotoStore(inMemory: true)
        let now = Date()
        let photo = try await XCTUnwrapAsync(await store.add(try sampleJPEG(width: 30, height: 40), date: now.addingTimeInterval(86_400 * 3),
                                                              tag: "Front", source: .library, now: now))
        XCTAssertEqual(photo.date, now)
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
