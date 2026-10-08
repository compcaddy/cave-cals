import SwiftUI
import PhotosUI

/// Opens the camera or the photo library for a day. One photo a day is free; a second photo that day asks for
/// Cave Cals+ first (a library photo is checked when saving, since its own date can file it under another day).
@MainActor @Observable final class ProgressPhotoAdder {
    struct CameraRoute: Identifiable {
        let id = UUID()
        let day: Date
    }
    struct Import: Identifiable {
        let id = UUID()
        let data: Data
        let preview: UIImage
        /// When the photo was taken, from its metadata.
        let taken: Date?
        /// The day picked when the library was opened, used when the photo has no date of its own.
        let day: Date
    }

    let subscriptions = AISubscriptions()
    /// Nil until checked.
    private(set) var plus: Bool?
    private(set) var checking = false
    var camera: CameraRoute?
    var showLibrary = false
    var libraryItem: PhotosPickerItem?
    var importing: Import?
    var showPaywall = false
    var problem: String?
    @ObservationIgnored var regularLogCount = 0
    @ObservationIgnored private(set) var libraryDay = Date()
    @ObservationIgnored private var resume: (() -> Void)?
    @ObservationIgnored private var pendingCheck: Task<Bool, Never>?

    /// Checks Cave Cals+ once per screen, sharing a check already under way.
    func checkPlus() async -> Bool {
        if let plus { return plus }
        if let pendingCheck { return await pendingCheck.value }
        checking = true
        let task = Task { await ProgressPhotoAccess.isPlus(subscriptions, regularLogCount: regularLogCount) }
        pendingCheck = task
        let value = await task.value
        plus = value
        checking = false
        pendingCheck = nil
        return value
    }

    func takePhoto(on day: Date, photosThatDay: Int) {
        whenAllowed(photosThatDay: photosThatDay) { [weak self] in self?.camera = CameraRoute(day: day) }
    }

    func chooseFromLibrary(for day: Date) {
        libraryDay = day
        showLibrary = true
    }

    /// Runs `action` right away for a day's first photo or for members; otherwise shows the paywall and runs it
    /// afterward if they join.
    func whenAllowed(photosThatDay: Int, _ action: @escaping () -> Void) {
        guard photosThatDay >= ProgressPhotoQuota.freePerDay, plus != true else { action(); return }
        Task {
            if await checkPlus() { action() } else {
                resume = action
                showPaywall = true
            }
        }
    }

    func accessGranted() {
        plus = true
        ProgressPhotoAccess.remember(true)
    }

    func paywallDismissed() {
        let action = plus == true ? resume : nil
        resume = nil
        action?()
    }
}

extension View {
    /// The camera, photo library, save sheet, and paywall behind a screen's Take Photo / From Library buttons.
    func progressPhotoAdding(_ adder: ProgressPhotoAdder, saved: @escaping (ProgressPhoto) -> Void = { _ in }) -> some View {
        modifier(ProgressPhotoAdding(adder: adder, saved: saved))
    }
}

private struct ProgressPhotoAdding: ViewModifier {
    @Bindable var adder: ProgressPhotoAdder
    @Environment(AppStore.self) private var store
    let saved: (ProgressPhoto) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $adder.camera) { route in
                ProgressPhotoCamera(day: route.day, adder: adder, onSaved: saved)
            }
            .photosPicker(isPresented: $adder.showLibrary, selection: $adder.libraryItem, matching: .images,
                          preferredItemEncoding: .current)
            .onChange(of: adder.libraryItem) { _, item in if let item { load(item) } }
            .sheet(item: $adder.importing) { draft in
                ProgressPhotoDetailsSheet(importing: draft, adder: adder, onSaved: saved)
            }
            .sheet(isPresented: $adder.showPaywall, onDismiss: adder.paywallDismissed) {
                AIUpgradePaywall(subscriptions: adder.subscriptions, trigger: .progressPhotos,
                                 onAccessGranted: adder.accessGranted, onDismissRequested: { adder.showPaywall = false })
            }
            .alert("Couldn’t add photo", isPresented: Binding(get: { adder.problem != nil }, set: { if !$0 { adder.problem = nil } })) {
                Button("OK") { Haptics.play(.tap) }.hapticFeel(.none)
            } message: {
                Text(adder.problem ?? "")
            }
            .onAppear { adder.regularLogCount = store.regularLogCount }
    }

    private func load(_ item: PhotosPickerItem) {
        adder.libraryItem = nil
        let day = adder.libraryDay
        let picked = Date()
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ProgressPhotoError.unreadable }
                let (preview, taken) = await Task.detached(priority: .userInitiated) {
                    (ProgressPhotoImage.preview(data, pixels: 1200), ProgressPhotoImage.captureDate(data))
                }.value
                guard let preview else { throw ProgressPhotoError.unreadable }
                // A sheet can't open while the picker is still sliding away.
                let settle = 0.6 - Date().timeIntervalSince(picked)
                if settle > 0 { try? await Task.sleep(for: .seconds(settle)) }
                adder.importing = .init(data: data, preview: preview, taken: taken, day: day)
            } catch {
                adder.problem = ProgressPhotoError.unreadable.errorDescription
                UsageStats.shared.error(.progressPhotos, error)
            }
        }
    }
}

// MARK: Progress card

/// Progress Photos on the Progress page, below Weight history: the latest photo day, Take Photo / From Library,
/// All photos, and Compare once an angle has two photos.
struct ProgressPhotosCard: View {
    @Environment(ProgressPhotoStore.self) private var photos
    @State private var adder = ProgressPhotoAdder()
    @State private var deleting: ProgressPhoto?
    let firstWeekday: Int

    var body: some View {
        let latest = photos.days().first
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress Photos").font(.cave(.title2)).bold()
            if let latest {
                NavigationLink { ProgressPhotosView(day: latest, firstWeekday: firstWeekday).hapticOnPush() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Calendar.current.isDateInToday(latest) ? "Today" : ProgressPhotoFormat.day(latest))
                            .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                        HStack(spacing: 8) {
                            ForEach(photos.photos(on: latest).prefix(4)) { photo in
                                ProgressPhotoThumbnail(photo: photo, cornerRadius: 10).frame(maxWidth: 76)
                                    .progressPhotoDeleteMenu(photo, deleting: $deleting)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Latest photos, \(latest.formatted(date: .long, time: .omitted))")
                .accessibilityIdentifier("progressPhotosLatest")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    CaveIcon(.camera, size: 44).foregroundStyle(Color.caveOrange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No cave paintings yet.").font(.cave(.headline))
                        Text("See changes over time.")
                            .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ProgressPhotoAddButtons(adder: adder, day: Date())
            VStack(spacing: 0) {
                NavigationLink { ProgressPhotosView(firstWeekday: firstWeekday).hapticOnPush() } label: {
                    HStack { Text("View Previous Photos"); Spacer(); CaveIcon(.chevronRight, size: 16) }
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("progressPhotosAll")
                if !photos.comparableTags.isEmpty {
                    NavigationLink { ProgressPhotoCompareView().hapticOnPush() } label: {
                        HStack { Text("Compare"); Spacer(); CaveIcon(.chevronRight, size: 16) }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("progressPhotosCompare")
                }
            }
            if let error = photos.error {
                Text(error).font(.cave(.footnote)).foregroundStyle(.red)
            }
        }
        .progressCard()
        .progressPhotoAdding(adder)
        .confirmsProgressPhotoDelete($deleting)
        .onAppear { photos.loadIfNeeded() }
    }
}

extension View {
    /// Long-press → Delete for a photo thumbnail; the deletion itself waits for `confirmsProgressPhotoDelete`.
    func progressPhotoDeleteMenu(_ photo: ProgressPhoto, deleting: Binding<ProgressPhoto?>) -> some View {
        contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
                Button(role: .destructive) { deleting.wrappedValue = photo } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityIdentifier("deleteProgressPhotoMenu")
            }
    }
    /// The same permanent-delete question as the photo viewer's Delete.
    func confirmsProgressPhotoDelete(_ deleting: Binding<ProgressPhoto?>) -> some View {
        modifier(ProgressPhotoDeleteConfirmation(deleting: deleting))
    }
}

private struct ProgressPhotoDeleteConfirmation: ViewModifier {
    @Environment(ProgressPhotoStore.self) private var photos
    @Binding var deleting: ProgressPhoto?
    func body(content: Content) -> some View {
        content.confirmationDialog("Delete this photo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                   titleVisibility: .visible, presenting: deleting) { photo in
            // Dialog buttons may skip the haptic button style, so they play their own feel.
            Button("Delete Photo", role: .destructive) {
                Haptics.play(.warning)
                photos.delete(photo.id)
            }.hapticFeel(.none)
            Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
        } message: { _ in
            Text("It’s removed from this iPhone and can’t be brought back.")
        }
    }
}

/// Take Photo / From Library for a day, with the free limit spelled out once it applies.
private struct ProgressPhotoAddButtons: View {
    @Environment(ProgressPhotoStore.self) private var photos
    let adder: ProgressPhotoAdder
    let day: Date

    var body: some View {
        let count = photos.photos(on: day).count
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { takeButton(count); libraryButton }
                VStack(spacing: 10) { takeButton(count); libraryButton }
            }
            .font(.cave(.headline))
            .disabled(adder.checking)
            if count >= ProgressPhotoQuota.freePerDay && adder.plus == false {
                Text("One photo a day is free. More angles with Cave Cals+.")
                    .font(.cave(.footnote)).foregroundStyle(Color.secondary)
                    .accessibilityIdentifier("progressPhotoFreeLimit")
            }
        }
        // Knowing ahead of time keeps the second photo's Take Photo instant for members.
        .task(id: count >= ProgressPhotoQuota.freePerDay) {
            if count >= ProgressPhotoQuota.freePerDay { _ = await adder.checkPlus() }
        }
    }

    private func takeButton(_ count: Int) -> some View {
        Button { adder.takePhoto(on: day, photosThatDay: count) } label: {
            HStack(spacing: 8) {
                if adder.checking { ProgressView().tint(.white) } else { CaveIcon(.camera, size: 20) }
                Text("Take Photo")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .hapticButtonStyle(.borderedProminent)
        .tint(.caveOrange)
        .accessibilityIdentifier("progressPhotoTake")
    }

    private var libraryButton: some View {
        Button { adder.chooseFromLibrary(for: day) } label: {
            HStack(spacing: 8) {
                CaveIcon(.phone, size: 20)
                Text("From Library")
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .hapticButtonStyle(.bordered)
        .accessibilityIdentifier("progressPhotoLibrary")
    }
}

struct ProgressPhotoThumbnail: View {
    @Environment(ProgressPhotoStore.self) private var photos
    let photo: ProgressPhoto
    var cornerRadius: CGFloat = 12
    @State private var image: UIImage?

    var body: some View {
        Color.primary.opacity(0.06)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: photo.id) { image = await photos.thumbnail(photo) }
            .accessibilityHidden(true)
    }
}

// MARK: All photos

/// Every progress photo: pick a day on the week strip (today to start), add photos to it, or jump to any photo day.
struct ProgressPhotosView: View {
    @Environment(ProgressPhotoStore.self) private var photos
    @Environment(WeightStore.self) private var weights
    @State private var day: Date
    @State private var adder = ProgressPhotoAdder()
    @State private var viewing: ProgressPhoto?
    @State private var deleting: ProgressPhoto?
    let firstWeekday: Int

    init(day: Date = Date(), firstWeekday: Int) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.firstWeekday = firstWeekday
    }

    var body: some View {
        let dayPhotos = photos.photos(on: day)
        let days = photos.days()
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProgressPhotoWeekPicker(day: day, firstWeekday: firstWeekday, select: select)
                        .progressCard()
                        .id("top")
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                .font(.cave(.title3)).bold()
                            Spacer(minLength: 8)
                            if let weight = ProgressPhotoWeight.near(day, in: weights.records) {
                                Text(ProgressPhotoFormat.weight(weight, unit: weights.unit))
                                    .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                            }
                        }
                        if dayPhotos.isEmpty {
                            Text(Calendar.current.isDateInToday(day) ? "No photos yet today." : "No photos this day.")
                                .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                                ForEach(dayPhotos) { photo in
                                    Button { viewing = photo } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ProgressPhotoThumbnail(photo: photo)
                                            Text(photo.tag).font(.cave(.subheadline)).foregroundStyle(Color.primary).lineLimit(1)
                                        }
                                    }
                                    .hapticButtonStyle(.plain)
                                    .progressPhotoDeleteMenu(photo, deleting: $deleting)
                                    .accessibilityLabel("\(photo.tag) photo")
                                    .accessibilityIdentifier("progressPhoto-\(photo.tag)")
                                }
                            }
                        }
                        ProgressPhotoAddButtons(adder: adder, day: day)
                    }
                    .progressCard()
                    if !days.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo days").font(.cave(.title3)).bold().padding(.bottom, 6)
                            ForEach(days, id: \.self) { photoDay in
                                Button {
                                    select(photoDay)
                                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                                } label: { dayRow(photoDay) }
                                .hapticButtonStyle(.plain).hapticFeel(.selection)
                                .accessibilityIdentifier("photoDayRow-\(Day.key(photoDay))")
                            }
                        }
                        .progressCard()
                    }
                    Text("Photos stay on this iPhone. Never uploaded. Included in your iPhone backup.")
                        .font(.cave(.footnote)).foregroundStyle(Color.secondary)
                }
                .padding(20)
            }
        }
        .background(Color.caveBackground)
        .navigationTitle("Progress Photos").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !photos.comparableTags.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { ProgressPhotoCompareView().hapticOnPush() } label: { Text("Compare") }
                        .accessibilityIdentifier("progressPhotosCompareToolbar")
                }
            }
        }
        .sheet(item: $viewing) { photo in ProgressPhotoViewer(start: photo, adder: adder) }
        .confirmsProgressPhotoDelete($deleting)
        .progressPhotoAdding(adder) { select($0.date) }
        .onAppear { photos.loadIfNeeded() }
    }

    private func select(_ date: Date) { day = Calendar.current.startOfDay(for: date) }

    private func dayRow(_ photoDay: Date) -> some View {
        let selected = Calendar.current.isDate(photoDay, inSameDayAs: day)
        let dayPhotos = photos.photos(on: photoDay)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(photoDay, format: .dateTime.month(.abbreviated).day().year())
                    .font(.cave(.body)).foregroundStyle(selected ? Color.caveOrange : Color.primary)
                Text(dayPhotos.count == 1 ? "1 photo" : "\(dayPhotos.count) photos")
                    .font(.cave(.caption)).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            ForEach(dayPhotos.prefix(4)) { photo in
                ProgressPhotoThumbnail(photo: photo, cornerRadius: 6).frame(width: 36)
            }
            CaveIcon(.chevronRight, size: 14).foregroundStyle(Color.secondary)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// A week of days, like the weigh-in editor's, showing each day's photo count. Follows the Progress week start.
private struct ProgressPhotoWeekPicker: View {
    @Environment(ProgressPhotoStore.self) private var photos
    let day: Date
    let firstWeekday: Int
    let select: (Date) -> Void
    private var dates: ProgressCalendar { ProgressCalendar(firstWeekday: firstWeekday) }
    private var week: DateInterval { dates.interval(.week, containing: day) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { move(-1) } label: { CaveIcon(.chevronLeft, size: 18).frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous week").accessibilityIdentifier("previousPhotoWeek")
                Spacer(minLength: 0)
                Text(dates.label(week)).font(.cave(.subheadline)).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { move(1) } label: { CaveIcon(.chevronRight, size: 18).frame(width: 44, height: 44) }
                    .disabled(week.end > today)
                    .accessibilityLabel("Next week").accessibilityIdentifier("nextPhotoWeek")
            }
            .hapticButtonStyle(.plain).hapticFeel(.selection).foregroundStyle(Color.accentColor)
            ViewThatFits(in: .horizontal) {
                dayButtons
                ScrollView(.horizontal) { dayButtons }.scrollIndicators(.hidden)
            }
        }
    }

    private var dayButtons: some View {
        HStack(spacing: 4) {
            ForEach(dates.days(in: week), id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: day)
                let count = photos.photos(on: date).count
                Button { select(date) } label: {
                    VStack(spacing: 5) {
                        Text(date, format: .dateTime.weekday(.abbreviated)).font(.cave(.caption))
                        Text(date, format: .dateTime.day()).font(.cave(.body))
                        HStack(spacing: 2) {
                            if count > 0 { CaveIcon(.camera, size: 12); Text("\(count)") } else { Text("--") }
                        }
                        .font(.cave(.caption)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(minWidth: 44, maxWidth: .infinity).padding(.vertical, 10)
                    .foregroundStyle(date > today ? Color.secondary.opacity(0.45) : Color.primary)
                    .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5) }
                    .contentShape(Rectangle())
                }
                .hapticButtonStyle(.plain).hapticFeel(.selection).disabled(date > today)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .accessibilityValue(count == 0 ? "No photos" : count == 1 ? "1 photo" : "\(count) photos")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("photoDay-\(Day.key(date))")
            }
        }
    }

    private func move(_ direction: Int) {
        select(min(dates.move(day, by: direction, period: .week), today))
    }
}

// MARK: Viewing and editing

/// One day's photos, swiped through, with Edit, Share, and Delete.
struct ProgressPhotoViewer: View {
    @Environment(ProgressPhotoStore.self) private var photos
    @Environment(WeightStore.self) private var weights
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let adder: ProgressPhotoAdder
    @State private var selection: UUID
    @State private var editing: ProgressPhoto?
    @State private var confirmingDelete = false
    @State private var shareFile: ProgressPhotoShareFile?

    init(start: ProgressPhoto, adder: ProgressPhotoAdder) {
        day = start.date
        self.adder = adder
        _selection = State(initialValue: start.id)
    }

    var body: some View {
        let dayPhotos = photos.photos(on: day)
        let current = dayPhotos.first { $0.id == selection } ?? dayPhotos.first
        NavigationStack {
            VStack(spacing: 10) {
                TabView(selection: $selection) {
                    ForEach(dayPhotos) { photo in
                        ProgressPhotoFullImage(photo: photo).padding(.horizontal, 12).tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: dayPhotos.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                if let current {
                    VStack(spacing: 2) {
                        Text(current.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.cave(.headline))
                        if let weight = ProgressPhotoWeight.near(current.date, in: weights.records) {
                            Text(ProgressPhotoFormat.weight(weight, unit: weights.unit))
                                .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.bottom, 8)
                }
            }
            .background(Color.caveBackground)
            .navigationTitle(current?.tag ?? "Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.hapticButtonStyle(.automatic)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { editing = current } label: { Label("Edit", systemImage: "pencil") }
                        .hapticButtonStyle(.automatic)
                        .accessibilityIdentifier("editProgressPhoto")
                    Spacer()
                    if let shareFile {
                        ShareLink(item: shareFile, preview: SharePreview(shareFile.name)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .hapticButtonStyle(.automatic)
                        .accessibilityIdentifier("shareProgressPhoto")
                    }
                    Spacer()
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .hapticButtonStyle(.automatic)
                        .accessibilityIdentifier("deleteProgressPhoto")
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                // Dialog buttons may skip the haptic button style, so they play their own feel.
                Button("Delete Photo", role: .destructive) {
                    Haptics.play(.warning)
                    if let current { photos.delete(current.id) }
                }.hapticFeel(.none)
                Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
            } message: {
                Text("It’s removed from this iPhone and can’t be brought back.")
            }
            .sheet(item: $editing) { photo in ProgressPhotoDetailsSheet(editing: photo, adder: adder) }
            .task(id: current?.id) {
                shareFile = nil
                guard let current, let data = await photos.jpegData(current) else { return }
                shareFile = ProgressPhotoShareFile(data: data, name: "\(current.tag) \(current.date.formatted(.iso8601.year().month().day()))")
            }
            .onChange(of: dayPhotos.map(\.id)) { _, ids in
                if ids.isEmpty { dismiss() } else if !ids.contains(selection) { selection = ids[0] }
            }
        }
    }
}

private struct ProgressPhotoFullImage: View {
    @Environment(ProgressPhotoStore.self) private var photos
    let photo: ProgressPhoto
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.id) { image = await photos.image(photo) }
        .accessibilityElement()
        .accessibilityLabel("\(photo.tag) photo")
    }
}

/// Saves a library photo, or changes a saved photo's angle and day. Moving a photo onto a day that already has one
/// follows the same one-a-day rule as adding.
struct ProgressPhotoDetailsSheet: View {
    @Environment(ProgressPhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    let adder: ProgressPhotoAdder
    private let importing: ProgressPhotoAdder.Import?
    private let editing: ProgressPhoto?
    private let onSaved: (ProgressPhoto) -> Void
    @State private var tag: String
    @State private var date: Date
    @State private var image: UIImage?
    @State private var saving = false
    @State private var checking = false
    @State private var showPaywall = false

    init(importing: ProgressPhotoAdder.Import, adder: ProgressPhotoAdder, onSaved: @escaping (ProgressPhoto) -> Void) {
        self.importing = importing
        editing = nil
        self.adder = adder
        self.onSaved = onSaved
        // File it under the day it was taken, when the photo says.
        _date = State(initialValue: importing.taken.flatMap { $0 <= Date() ? $0 : nil } ?? importing.day)
        _tag = State(initialValue: "")
        _image = State(initialValue: importing.preview)
    }

    init(editing: ProgressPhoto, adder: ProgressPhotoAdder) {
        importing = nil
        self.editing = editing
        self.adder = adder
        onSaved = { _ in }
        _date = State(initialValue: editing.date)
        _tag = State(initialValue: editing.tag)
    }

    private var others: Int { photos.photos(on: date).filter { $0.id != editing?.id }.count }
    private var movesDay: Bool { editing.map { !Calendar.current.isDate($0.date, inSameDayAs: date) } ?? true }
    private var blocked: Bool { movesDay && ProgressPhotoQuota.needsPlus(photosThatDay: others, isPlus: adder.plus == true) }
    private var cleanTag: String? { ProgressPhotoTag.clean(tag, known: photos.tagChoices) }

    var body: some View {
        NavigationStack {
            HapticForm {
                Section {
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity).frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                Section {
                    ProgressPhotoTagPicker(selection: $tag, choices: photos.tagChoices)
                } header: { Text("Angle") }
                Section {
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                        .hapticSelection(on: Day.key(date))
                        .accessibilityIdentifier("progressPhotoDate")
                } footer: {
                    if blocked {
                        if checking || adder.plus == nil {
                            Text("Checking Cave Cals+…")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("That day has a photo already. One photo a day is free; Cave Cals+ keeps every angle.")
                                Button("Explore Cave Cals+") { showPaywall = true }
                                    .font(.cave(.footnote)).hapticButtonStyle(.borderless)
                                    .accessibilityIdentifier("progressPhotoExplorePlus")
                            }
                        }
                    } else if let taken = importing?.taken, Calendar.current.isDate(taken, inSameDayAs: date) {
                        Text("The day this photo was taken.")
                    }
                }
                if let error = photos.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle(editing == nil ? "Add Photo" : "Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Save", systemImage: "checkmark").foregroundStyle(.white)
                    }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange)
                    // The success feel plays once the photo is really saved.
                    .hapticFeel(.none)
                    .disabled(blocked || saving || cleanTag == nil)
                    .accessibilityIdentifier("saveProgressPhoto")
                }
            }
            .navigationDestination(isPresented: $showPaywall) {
                AIUpgradePaywall(subscriptions: adder.subscriptions, trigger: .progressPhotos,
                                 onAccessGranted: adder.accessGranted, onDismissRequested: { showPaywall = false })
            }
            .onAppear {
                if tag.isEmpty { tag = ProgressPhotoTag.next(after: "", taken: photos.photos(on: date).map(\.tag)) }
                if tag.isEmpty { tag = ProgressPhotoTag.standard[0] }
            }
            .task(id: Day.key(date)) {
                guard movesDay, others >= ProgressPhotoQuota.freePerDay, adder.plus == nil else { return }
                checking = true
                _ = await adder.checkPlus()
                checking = false
            }
            .task {
                if image == nil, let editing { image = await photos.image(editing) }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !blocked, !saving, let clean = cleanTag else { return }
        if let editing {
            if photos.update(editing.id, tag: clean, date: date) {
                Haptics.play(.success)
                dismiss()
            }
            return
        }
        guard let importing else { return }
        saving = true
        Task {
            defer { saving = false }
            // Keep the time it was taken when it's filed under that day.
            let when = importing.taken.flatMap { Calendar.current.isDate($0, inSameDayAs: date) ? $0 : nil } ?? Day.loggingDate(date)
            guard let photo = await photos.add(importing.data, date: when, tag: clean, source: .library) else {
                Haptics.play(.warning)
                return
            }
            Haptics.play(.success)
            UsageStats.shared.event("progressPhoto.saved", [
                "source": ProgressPhoto.Source.library.rawValue,
                "angle": ProgressPhotoTag.rank(clean) < ProgressPhotoTag.standard.count ? "standard" : "custom",
            ])
            onSaved(photo)
            dismiss()
        }
    }
}

/// Front, Back, Left Side, Right Side, earlier typed labels, and Other… to type a new one.
struct ProgressPhotoTagPicker: View {
    @Binding var selection: String
    let choices: [String]
    @State private var typing = false
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var shown: [String] {
        let known = choices.contains { ProgressPhotoTag.same($0, selection) }
        return known || selection.isEmpty || typing ? choices : choices + [selection]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChipFlowLayout(spacing: 8) {
                ForEach(shown, id: \.self) { choice in
                    chip(choice, selected: !typing && ProgressPhotoTag.same(choice, selection)) {
                        typing = false
                        focused = false
                        selection = choice
                    }
                    .accessibilityIdentifier("photoAngle-\(choice)")
                }
                chip("Other…", selected: typing) {
                    typing = true
                    typed = ""
                    selection = ""
                    Task { try? await Task.sleep(for: .milliseconds(150)); focused = true }
                }
                .accessibilityIdentifier("photoAngleOther")
            }
            if typing {
                TextField("Name this angle", text: $typed)
                    .font(.cave(.body))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .onChange(of: typed) { _, value in
                        if value.count > ProgressPhotoTag.maxLength { typed = String(value.prefix(ProgressPhotoTag.maxLength)) }
                        selection = ProgressPhotoTag.clean(typed, known: choices) ?? ""
                    }
                    .frame(minHeight: 44)
                    .keyboardInputArea { focused = true }
                    .accessibilityIdentifier("photoAngleName")
            }
        }
        .padding(.vertical, 6)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.cave(.subheadline)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(selected ? Color.caveOrange : Color.primary.opacity(0.07), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain).hapticFeel(.selection)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps chips onto as many rows as they need.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: Compare

/// Two photos at the same angle, side by side or with a slider, with the time and weight between them.
struct ProgressPhotoCompareView: View {
    enum Arrangement: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side", slider = "Slider"
        var id: Self { self }
    }

    @Environment(ProgressPhotoStore.self) private var photos
    @Environment(WeightStore.self) private var weights
    @AppStorage("progressPhotoCompareLayout.v1", store: ProgressPreferences.defaults) private var layout = Arrangement.sideBySide
    @State private var tag: String?
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var split = 0.5
    @State private var images: [UUID: UIImage] = [:]
    @State private var shareImage: UIImage?
    @State private var shareFile: ProgressPhotoShareFile?

    var body: some View {
        let tags = photos.comparableTags
        let tag = tags.first { ProgressPhotoTag.same($0, self.tag ?? "") } ?? tags.first
        let series = tag.map { photos.series($0) } ?? []
        let before = series.first { $0.id == beforeID } ?? series.first
        let after = series.first { $0.id == afterID } ?? series.last
        Group {
            if let tag, let before, let after, series.count >= 2 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if tags.count > 1 { tagChips(tags, selected: tag) }
                        Picker("Layout", selection: $layout) {
                            ForEach(Arrangement.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .hapticSelection(on: layout)
                        .accessibilityIdentifier("compareLayout")
                        if layout == .sideBySide { sideBySide(before, after) } else { slider(before, after) }
                        Text(ProgressPhotoFormat.comparison(before, after, records: weights.records, unit: weights.unit))
                            .font(.cave(.title3)).bold()
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("compareSummary")
                        strip("Before", series, selected: before.id) { beforeID = $0 }
                        strip("After", series, selected: after.id) { afterID = $0 }
                    }
                    .padding(20)
                }
                .task(id: [before.id, after.id]) { await load(before, after) }
            } else {
                ContentUnavailableView {
                    Label { Text("Nothing to compare yet") } icon: { CaveIcon(.camera, size: 48) }
                } description: {
                    Text("Take two photos at the same angle on different days, then compare them here.")
                }
            }
        }
        .background(Color.caveBackground)
        .navigationTitle("Compare").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareImage, let shareFile {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareFile, preview: SharePreview("Progress photos", image: Image(uiImage: shareImage))) {
                        Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                    }
                    .hapticButtonStyle(.automatic)
                    .accessibilityLabel("Share comparison")
                    .accessibilityIdentifier("shareComparison")
                }
            }
        }
        .onAppear { photos.loadIfNeeded(); UsageStats.shared.count(.photoCompares) }
    }

    private func tagChips(_ tags: [String], selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { choice in
                    let isSelected = ProgressPhotoTag.same(choice, selected)
                    Button {
                        tag = choice
                        beforeID = nil
                        afterID = nil
                    } label: {
                        Text(choice).font(.cave(.subheadline)).lineLimit(1)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .background(isSelected ? Color.caveOrange : Color.primary.opacity(0.07), in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .hapticButtonStyle(.plain).hapticFeel(.selection)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("compareAngle-\(choice)")
                }
            }
        }
    }

    private func sideBySide(_ before: ProgressPhoto, _ after: ProgressPhoto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            pane(before, title: "Before")
            pane(after, title: "After")
        }
    }

    private func pane(_ photo: ProgressPhoto, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            framed(photo).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.cave(.caption)).foregroundStyle(Color.secondary).padding(.top, 2)
            Text(photo.date, format: .dateTime.month(.abbreviated).day().year()).font(.cave(.subheadline)).bold()
            if let weight = ProgressPhotoWeight.near(photo.date, in: weights.records) {
                Text(ProgressPhotoFormat.weight(weight, unit: weights.unit))
                    .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func framed(_ photo: ProgressPhoto) -> some View {
        Color.primary.opacity(0.06)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image = images[photo.id] { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() }
            }
            .clipped()
    }

    private func slider(_ before: ProgressPhoto, _ after: ProgressPhoto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                ZStack(alignment: .leading) {
                    framed(after)
                    framed(before).mask(alignment: .leading) { Rectangle().frame(width: width * split) }
                    Rectangle().fill(.white).frame(width: 3).shadow(radius: 2).offset(x: width * split - 1.5)
                    Circle().fill(.white).frame(width: 36, height: 36)
                        .overlay { Image(systemName: "chevron.left.chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.black) }
                        .shadow(radius: 3)
                        .position(x: width * split, y: geometry.size.height / 2)
                    HStack {
                        Text("Before").sliderTag()
                        Spacer()
                        Text("After").sliderTag()
                    }
                    .padding(10)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    split = min(max(value.location.x / width, 0), 1)
                })
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Before and after slider")
            .accessibilityValue("\(Int((split * 100).rounded())) percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(1, split + 0.1)
                case .decrement: split = max(0, split - 0.1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("compareSlider")
            HStack {
                Text(before.date, format: .dateTime.month(.abbreviated).day().year())
                Spacer()
                Text(after.date, format: .dateTime.month(.abbreviated).day().year())
            }
            .font(.cave(.subheadline)).foregroundStyle(Color.secondary)
        }
    }

    private func strip(_ title: String, _ series: [ProgressPhoto], selected: UUID, pick: @escaping (UUID) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.cave(.headline))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(series) { photo in
                            let isSelected = photo.id == selected
                            Button { pick(photo.id) } label: {
                                VStack(spacing: 4) {
                                    ProgressPhotoThumbnail(photo: photo, cornerRadius: 8)
                                        .frame(width: 60)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.caveOrange : .clear, lineWidth: 3)
                                        }
                                    Text(photo.date, format: .dateTime.month(.abbreviated).day())
                                        .font(.cave(.caption))
                                        .foregroundStyle(isSelected ? Color.caveOrange : Color.secondary)
                                }
                            }
                            .hapticButtonStyle(.plain).hapticFeel(.selection)
                            .accessibilityLabel("\(title), \(photo.date.formatted(date: .long, time: .omitted))")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .id(photo.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private func load(_ before: ProgressPhoto, _ after: ProgressPhoto) async {
        // Only the two shown stay decoded here; the store keeps a small cache of its own.
        images = images.filter { $0.key == before.id || $0.key == after.id }
        for photo in [before, after] where images[photo.id] == nil {
            images[photo.id] = await photos.image(photo)
        }
        guard let first = images[before.id], let last = images[after.id] else { return }
        let rendered = ProgressCompareShare.render(
            before: first, beforeCaption: before.date.formatted(.dateTime.month(.abbreviated).day().year()),
            after: last, afterCaption: after.date.formatted(.dateTime.month(.abbreviated).day().year()),
            summary: ProgressPhotoFormat.comparison(before, after, records: weights.records, unit: weights.unit))
        shareImage = rendered
        shareFile = rendered?.jpegData(compressionQuality: 0.9).map { ProgressPhotoShareFile(data: $0, name: "Progress photos") }
    }
}

private extension View {
    func sliderTag() -> some View {
        font(.cave(.caption)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
    }
}

/// The picture shared from Compare: both photos with their dates and what changed, on cream.
@MainActor enum ProgressCompareShare {
    static func render(before: UIImage, beforeCaption: String, after: UIImage, afterCaption: String, summary: String) -> UIImage? {
        let card = VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                pane(before, caption: beforeCaption)
                pane(after, caption: afterCaption)
            }
            Text(summary).font(.custom("Schoolbell-Regular", size: 24))
            Text("Cave Cals").font(.custom("Schoolbell-Regular", size: 15)).foregroundStyle(Color.caveOrange)
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(18)
        .frame(width: 420)
        .background(Color.caveLaunchCream)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private static func pane(_ image: UIImage, caption: String) -> some View {
        VStack(spacing: 6) {
            Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(caption).font(.custom("Schoolbell-Regular", size: 17))
        }
    }
}
