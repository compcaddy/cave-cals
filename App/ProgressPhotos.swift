import Foundation
import Observation
import UIKit
import ImageIO
import StoreKit
import CoreTransferable
import UniformTypeIdentifiers

/// A progress photo. Its image files sit beside a small index in Application Support. They're never uploaded or
/// synced, but unlike weigh-ins they're included in the iPhone's own backups, so moving to a new iPhone keeps them.
struct ProgressPhoto: Codable, Identifiable, Equatable, Hashable {
    enum Source: String, Codable { case frontCamera, backCamera, library }
    var id = UUID()
    /// The day it's filed under: when it was taken, or that day at the time it was saved when filed under another day.
    var date: Date
    /// Front, Back, Left Side, Right Side, or a typed label.
    var tag: String
    var source: Source
    /// When it was added; orders two photos with the same label on one day.
    var added = Date()
}

/// Angle labels. The standard four come first; anything typed under Other is remembered by being used.
enum ProgressPhotoTag {
    static let standard = ["Front", "Back", "Left Side", "Right Side"]
    static let maxLength = 24

    /// Labels match regardless of case or accents, so “front” files with “Front”.
    static func key(_ tag: String) -> String { tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }

    /// A typed label, trimmed and capped, spelled like a label already in use when only the case differs.
    static func clean(_ text: String, known: [String] = []) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let capped = String(words.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        guard !capped.isEmpty else { return nil }
        return (standard + known).first { same($0, capped) } ?? capped
    }

    /// The standard four first, in their usual order, then typed labels alphabetically.
    static func rank(_ tag: String) -> Int { standard.firstIndex { same($0, tag) } ?? standard.count }

    static func sorted(_ photos: [ProgressPhoto]) -> [ProgressPhoto] {
        photos.sorted {
            let (a, b) = (rank($0.tag), rank($1.tag))
            if a != b { return a < b }
            if !same($0.tag, $1.tag) { return $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
            return $0.added < $1.added
        }
    }

    /// Labels to offer: the standard four, then typed labels, most recently used first.
    static func choices(from photos: [ProgressPhoto]) -> [String] {
        var result = standard
        for photo in photos.sorted(by: { $0.added > $1.added }) where !result.contains(where: { same($0, photo.tag) }) {
            result.append(photo.tag)
        }
        return result
    }

    /// The next standard angle not yet taken that day, so a whole set can be shot in one go.
    /// Stays on `current` once all four are taken.
    static func next(after current: String, taken: [String]) -> String {
        let start = min((standard.firstIndex { same($0, current) } ?? -1) + 1, standard.count)
        let order = standard[start...] + standard[..<start]
        return order.first { tag in !taken.contains { same($0, tag) } } ?? current
    }
}

/// One photo a day is free. More angles (or more photos) on the same day need Cave Cals+.
enum ProgressPhotoQuota {
    static let freePerDay = 1
    static func needsPlus(photosThatDay: Int, isPlus: Bool) -> Bool { !isPlus && photosThatDay >= freePerDay }
}

/// Whether someone has Cave Cals+, for more than one photo a day. The backend decides when it can be reached;
/// otherwise StoreKit's on-device record of a current subscription does, so members aren't blocked offline.
@MainActor enum ProgressPhotoAccess {
    private static var remembered: (plus: Bool, at: Date)?
    static func remember(_ plus: Bool) { remembered = (plus, Date()) }

    static func isPlus(_ subscriptions: AISubscriptions, regularLogCount: Int) async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        // UI tests use this to try the free limit; otherwise tests and previews have every angle.
        if arguments.contains("--photos-free") { return false }
        #endif
        if arguments.contains("--uitesting") || arguments.contains("--screenshots") || ProgressPreferences.isPreview { return true }
        // Only a membership is remembered, so someone who just joined elsewhere is never told they haven't.
        if let remembered, remembered.plus, Date().timeIntervalSince(remembered.at) < 600 { return true }
        await subscriptions.refresh(regularLogCount: regularLogCount)
        let plus: Bool
        if let account = subscriptions.account { plus = account.active } else { plus = await hasStoreSubscription() }
        remember(plus)
        return plus
    }

    private static func hasStoreSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productType == .autoRenewable,
               transaction.revocationDate == nil { return true }
        }
        return false
    }
}

/// The weigh-in to show beside a photo.
enum ProgressPhotoWeight {
    /// The weigh-in that day, else the closest one within three days (the earlier one on a tie).
    /// `sameDay` is false for a nearby weigh-in, which is shown as approximate.
    static func near(_ date: Date, in records: [WeightRecord], calendar: Calendar = .current) -> (record: WeightRecord, sameDay: Bool)? {
        let day = calendar.startOfDay(for: date)
        if let same = records.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) { return (same, true) }
        let nearby = records.compactMap { record -> (record: WeightRecord, days: Int)? in
            guard let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: record.date)).day,
                  abs(days) <= 3 else { return nil }
            return (record, days)
        }
        return nearby.min { abs($0.days) != abs($1.days) ? abs($0.days) < abs($1.days) : $0.days < $1.days }
            .map { ($0.record, false) }
    }
}

enum ProgressPhotoFormat {
    static func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }

    /// A nearby (not same-day) weigh-in is marked approximate.
    static func weight(_ near: (record: WeightRecord, sameDay: Bool), unit: WeightUnit) -> String {
        (near.sameDay ? "" : "≈ ") + unit.text(near.record.kilograms)
    }

    /// How far apart two photos are, in the unit that reads best.
    static func span(days: Int) -> String {
        let days = abs(days)
        switch days {
        case 0: return "Same day"
        case 1: return "1 day apart"
        case ..<14: return "\(days) days apart"
        case ..<70: return "\(Int((Double(days) / 7).rounded())) weeks apart"
        default:
            let months = Int((Double(days) / 30.44).rounded())
            return months == 1 ? "1 month apart" : "\(months) months apart"
        }
    }

    /// “12 weeks apart · ↓ 8.4 lb”: the gap between two photos, and the weight change when both have a weigh-in nearby.
    static func comparison(_ before: ProgressPhoto, _ after: ProgressPhoto, records: [WeightRecord], unit: WeightUnit,
                           calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: before.date),
                                           to: calendar.startOfDay(for: after.date)).day ?? 0
        var parts = [span(days: days)]
        if let first = ProgressPhotoWeight.near(before.date, in: records, calendar: calendar),
           let last = ProgressPhotoWeight.near(after.date, in: records, calendar: calendar),
           first.record.id != last.record.id {
            let change = unit.display(last.record.kilograms) - unit.display(first.record.kilograms)
            let amount = abs(change).formatted(.number.precision(.fractionLength(1)))
            parts.append(abs(change) < 0.05 ? "same weight" : "\(change < 0 ? "↓" : "↑") \(amount) \(unit.rawValue)")
        }
        return parts.joined(separator: " · ")
    }
}

/// A JPEG handed to the share sheet as-is.
struct ProgressPhotoShareFile: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }.suggestedFileName { $0.name + ".jpg" }
    }
}

enum ProgressPhotoError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This photo couldn’t be read. Try a JPEG, PNG, or HEIC photo." }
}

enum ProgressPhotoImage {
    static let fullPixels = 2048, thumbnailPixels = 480

    /// Re-encodes a photo as JPEG at a sensible size, upright. Re-encoding also drops its metadata, including location.
    nonisolated static func prepare(_ data: Data) throws -> (full: Data, thumbnail: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ProgressPhotoError.unreadable }
        func jpeg(_ pixels: Int, quality: CGFloat) throws -> Data {
            guard let image = downsample(source, pixels: pixels),
                  let bytes = UIImage(cgImage: image).jpegData(compressionQuality: quality) else { throw ProgressPhotoError.unreadable }
            return bytes
        }
        return (try jpeg(fullPixels, quality: 0.82), try jpeg(thumbnailPixels, quality: 0.75))
    }

    /// A screen-sized copy to show before saving, decoded without loading the whole photo.
    nonisolated static func preview(_ data: Data, pixels: Int = 1600) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downsample(source, pixels: pixels) else { return nil }
        return UIImage(cgImage: image)
    }

    /// When the photo was taken, from its own metadata, so a library photo files under the right day.
    nonisolated static func captureDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized]
                          ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    nonisolated private static func downsample(_ source: CGImageSource, pixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ] as CFDictionary)
    }
}

/// Progress photos on this iPhone: an index file plus a full-size and a thumbnail JPEG per photo.
@MainActor @Observable final class ProgressPhotoStore {
    private struct Index: Codable {
        var version = 1
        var photos: [ProgressPhoto] = []
    }

    private var index = Index()
    private let folder: URL?
    private var loaded = false
    private var loadFailed = false
    /// Image bytes for in-memory stores (UI tests and previews).
    @ObservationIgnored private var memory: [String: Data] = [:]
    @ObservationIgnored private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    var error: String?

    /// Every photo, newest first.
    var photos: [ProgressPhoto] { index.photos.sorted { $0.date > $1.date } }
    var count: Int { index.photos.count }
    var tagChoices: [String] { ProgressPhotoTag.choices(from: index.photos) }

    init(inMemory: Bool = false, folder: URL? = nil) {
        self.folder = inMemory ? nil : (folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProgressPhotos", isDirectory: true))
        loaded = inMemory
    }

    /// Reads the index the first time photos are needed, so nothing is read at launch.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = indexURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let file = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
            guard file.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            index = file
            removeStrayFiles()
        } catch {
            loadFailed = true
            self.error = "Your progress photos couldn’t be opened. Reopen Cave Cals to try again. Nothing has been changed."
            UsageStats.shared.error(.progressPhotos, error)
        }
    }

    /// That day's photos: Front, Back, Left Side, Right Side, then typed labels.
    func photos(on date: Date, calendar: Calendar = .current) -> [ProgressPhoto] {
        ProgressPhotoTag.sorted(index.photos.filter { calendar.isDate($0.date, inSameDayAs: date) })
    }

    /// Days with photos, newest first.
    func days(calendar: Calendar = .current) -> [Date] {
        Set(index.photos.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)
    }

    /// Every photo with a label, oldest first.
    func series(_ tag: String) -> [ProgressPhoto] {
        index.photos.filter { ProgressPhotoTag.same($0.tag, tag) }.sorted { $0.date < $1.date }
    }

    /// Labels with at least two photos, ready to compare, in the usual label order.
    var comparableTags: [String] {
        let counts = Dictionary(grouping: index.photos) { ProgressPhotoTag.key($0.tag) }.mapValues(\.count)
        return tagChoices.filter { (counts[ProgressPhotoTag.key($0)] ?? 0) >= 2 }
    }

    /// The photo to line up with: the latest with the same label, preferring one from the same camera.
    func ghost(for tag: String, source: ProgressPhoto.Source) -> ProgressPhoto? {
        let matching = photos.filter { ProgressPhotoTag.same($0.tag, tag) }
        return matching.first { $0.source == source } ?? matching.first
    }

    /// Prepares and saves a photo off the main thread. Returns nil, with `error` set, if it couldn't be saved.
    func add(_ data: Data, date: Date, tag: String, source: ProgressPhoto.Source, now: Date = Date()) async -> ProgressPhoto? {
        loadIfNeeded()
        guard !loadFailed else { return nil }
        let photo = ProgressPhoto(date: min(date, now), tag: tag, source: source, added: now)
        let folder = self.folder
        do {
            let images = try await Task.detached(priority: .userInitiated) {
                let images = try ProgressPhotoImage.prepare(data)
                if let folder { try Self.write(images, for: photo.id, in: folder) }
                return images
            }.value
            if folder == nil {
                memory[Self.fileName(photo.id, thumbnail: false)] = images.full
                memory[Self.fileName(photo.id, thumbnail: true)] = images.thumbnail
            }
            var next = index
            next.photos.append(photo)
            guard persist(next) else { removeFiles(photo.id); return nil }
            error = nil
            UsageStats.shared.count(.progressPhotos)
            return photo
        } catch {
            self.error = "This photo couldn’t be saved. Please try again."
            UsageStats.shared.error(.progressPhotos, error)
            return nil
        }
    }

    /// Changes a photo's label, or moves it to another day (keeping its time when the day is unchanged).
    @discardableResult func update(_ id: UUID, tag: String, date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let position = index.photos.firstIndex(where: { $0.id == id }) else { return false }
        var next = index
        next.photos[position].tag = tag
        if !calendar.isDate(next.photos[position].date, inSameDayAs: date) {
            next.photos[position].date = min(Day.loggingDate(date, now: now, calendar: calendar), now)
        }
        return persist(next)
    }

    @discardableResult func delete(_ id: UUID) -> Bool {
        var next = index
        next.photos.removeAll { $0.id == id }
        guard persist(next) else { return false }
        removeFiles(id)
        return true
    }

    /// The full photo, decoded off the main thread.
    func image(_ photo: ProgressPhoto) async -> UIImage? { await load(Self.fileName(photo.id, thumbnail: false)) }
    /// The saved JPEG itself, for sharing (it carries no location or other metadata).
    func jpegData(_ photo: ProgressPhoto) async -> Data? {
        let name = Self.fileName(photo.id, thumbnail: false)
        if let bytes = memory[name] { return bytes }
        guard let url = folder?.appendingPathComponent(name) else { return nil }
        return await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    }
    func thumbnail(_ photo: ProgressPhoto) async -> UIImage? { await load(Self.fileName(photo.id, thumbnail: true)) }

    private func load(_ name: String) async -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let bytes = memory[name], url = folder?.appendingPathComponent(name)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = bytes ?? url.flatMap({ try? Data(contentsOf: $0) }) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: name as NSString, cost: cost)
        }
        return image
    }

    private var indexURL: URL? { folder?.appendingPathComponent("photos-v1.json") }
    nonisolated private static func fileName(_ id: UUID, thumbnail: Bool) -> String {
        id.uuidString + (thumbnail ? "-thumb" : "") + ".jpg"
    }

    nonisolated private static func write(_ images: (full: Data, thumbnail: Data), for id: UUID, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The most private thing Cave Cals keeps: readable only while the iPhone is unlocked.
        try images.full.write(to: folder.appendingPathComponent(fileName(id, thumbnail: false)), options: [.atomic, .completeFileProtection])
        try images.thumbnail.write(to: folder.appendingPathComponent(fileName(id, thumbnail: true)), options: [.atomic, .completeFileProtection])
    }

    private func persist(_ next: Index) -> Bool {
        guard !loadFailed else { return false }
        do {
            if let folder, let indexURL {
                // Unlike weigh-ins, the folder stays in iPhone backups so a new iPhone keeps the photos.
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            index = next
            return true
        } catch {
            self.error = "Your photo changes couldn’t be saved. Please try again."
            UsageStats.shared.error(.progressPhotos, error)
            return false
        }
    }

    private func removeFiles(_ id: UUID) {
        for thumbnail in [false, true] {
            let name = Self.fileName(id, thumbnail: thumbnail)
            memory[name] = nil
            cache.removeObject(forKey: name as NSString)
            if let folder { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }

    /// Removes images left behind when saving was interrupted, so no photo stays on the iPhone unseen.
    private func removeStrayFiles() {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let kept = Set(index.photos.flatMap { [Self.fileName($0.id, thumbnail: false), Self.fileName($0.id, thumbnail: true)] })
        for name in names where name.hasSuffix(".jpg") && !kept.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    #if targetEnvironment(simulator)
    /// Sample photos for `--progress-preview`: a front and side photo each week for eight weeks, slimming a little.
    func addSamples(now: Date = Date(), calendar: Calendar = .current) {
        for week in 1...8 {
            guard let date = calendar.date(byAdding: .day, value: -7 * week, to: calendar.startOfDay(for: now))
                .flatMap({ calendar.date(bySettingHour: 7, minute: 30, second: 0, of: $0) }) else { continue }
            for (tag, side) in [("Front", false), ("Left Side", true)] {
                let slimming = Double(8 - week) / 7
                guard let data = ProgressPhotoSample.jpeg(slimming: slimming, side: side),
                      let images = try? ProgressPhotoImage.prepare(data) else { continue }
                let photo = ProgressPhoto(date: date, tag: tag, source: .frontCamera, added: date)
                memory[Self.fileName(photo.id, thumbnail: false)] = images.full
                memory[Self.fileName(photo.id, thumbnail: true)] = images.thumbnail
                index.photos.append(photo)
            }
        }
    }
    #endif
}

#if targetEnvironment(simulator)
/// A plain stand-in figure for the simulator's camera and the progress preview, which have no real photos.
enum ProgressPhotoSample {
    /// `slimming` from 0 to 1 narrows the waist; `side` turns the figure sideways.
    static func image(slimming: Double, side: Bool, size: CGSize = CGSize(width: 900, height: 1200)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let c = context.cgContext
            UIColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.83, green: 0.76, blue: 0.67, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: size.height * 0.86, width: size.width, height: size.height * 0.14))
            let x = size.width / 2, unit = size.height / 12
            let skin = UIColor(red: 0.78, green: 0.55, blue: 0.40, alpha: 1)
            let cloth = UIColor(red: 0.29, green: 0.35, blue: 0.44, alpha: 1)
            skin.setFill()
            c.fillEllipse(in: CGRect(x: x - unit * 0.7, y: unit * 1.2, width: unit * 1.4, height: unit * 1.7))
            let shoulders = side ? unit * 1.5 : unit * 3
            let waist = (side ? unit * 1.9 : unit * 2.7) * (1 - 0.25 * slimming)
            let torso = UIBezierPath()
            torso.move(to: CGPoint(x: x - shoulders / 2, y: unit * 3.1))
            torso.addLine(to: CGPoint(x: x + shoulders / 2, y: unit * 3.1))
            torso.addQuadCurve(to: CGPoint(x: x + waist / 2, y: unit * 6.6), controlPoint: CGPoint(x: x + waist * 0.62, y: unit * 4.8))
            torso.addLine(to: CGPoint(x: x - waist / 2, y: unit * 6.6))
            torso.addQuadCurve(to: CGPoint(x: x - shoulders / 2, y: unit * 3.1), controlPoint: CGPoint(x: x - waist * 0.62, y: unit * 4.8))
            torso.close()
            skin.setFill(); torso.fill()
            cloth.setFill()
            c.fill(CGRect(x: x - waist / 2, y: unit * 6.4, width: waist, height: unit * 1.2))
            let leg = side ? unit * 0.8 : unit * 0.9
            for offset in side ? [CGFloat(0)] : [-unit * 0.6, unit * 0.6] {
                skin.setFill()
                c.fill(CGRect(x: x + offset - leg / 2, y: unit * 7.5, width: leg, height: unit * 2.9))
            }
            skin.setFill()
            for offset in side ? [CGFloat(0)] : [-(shoulders / 2 + unit * 0.3), shoulders / 2 + unit * 0.3] {
                c.fill(CGRect(x: x + offset - unit * 0.3, y: unit * 3.3, width: unit * 0.6, height: unit * 3.2))
            }
        }
    }

    static func jpeg(slimming: Double, side: Bool) -> Data? {
        image(slimming: slimming, side: side).jpegData(compressionQuality: 0.9)
    }
}
#endif
