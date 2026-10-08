import SwiftUI
import AVFoundation
import AudioToolbox

enum ProgressCameraProblem: Equatable {
    case denied, unavailable
    var message: String {
        switch self {
        case .denied: "Camera is off for Cave Cals. Turn it on in Settings, or add a photo from your library."
        case .unavailable: "Camera unavailable. Add a photo from your library instead."
        }
    }
}

/// Full-screen camera for progress photos: angle pills, a see-through ghost of the last photo at that angle with an
/// opacity slider, an optional 10-second timer, and front/back cameras. Photos file under the day it opened for.
/// Cave Cals+ members stay in the camera for the next angle; otherwise it closes after one photo.
struct ProgressPhotoCamera: View {
    @Environment(ProgressPhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: Date
    let adder: ProgressPhotoAdder
    var onSaved: (ProgressPhoto) -> Void = { _ in }

    @AppStorage("progressPhotoTimer.v1", store: ProgressPreferences.defaults) private var timerOn = true
    @AppStorage("progressPhotoGhost.v1", store: ProgressPreferences.defaults) private var ghostOpacity = 0.35
    @AppStorage("progressPhotoFrontCamera.v1", store: ProgressPreferences.defaults) private var front = true
    /// Empty until a pill is tapped; until then the first angle not yet taken that day is selected.
    @State private var tag = ""
    @State private var typedTags: [String] = []
    @State private var ghostPhoto: ProgressPhoto?
    @State private var ghost: UIImage?
    @State private var ready = false
    @State private var problem: ProgressCameraProblem?
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var captureRequest = 0
    @State private var shot: Data?
    @State private var shotImage: UIImage?
    @State private var saving = false
    @State private var saved = 0
    @State private var notice: String?
    @State private var flash = false
    @State private var naming = false
    @State private var typedTag = ""

    private var takenThatDay: [String] { photos.photos(on: day).map(\.tag) }
    private var selectedTag: String {
        guard tag.isEmpty else { return tag }
        let next = ProgressPhotoTag.next(after: "", taken: takenThatDay)
        return next.isEmpty ? ProgressPhotoTag.standard[0] : next
    }
    private var source: ProgressPhoto.Source { front ? .frontCamera : .backCamera }
    private var reviewing: Bool { shotImage != nil }
    private var pills: [String] {
        var result = photos.tagChoices
        for typed in typedTags where !result.contains(where: { ProgressPhotoTag.same($0, typed) }) { result.append(typed) }
        return result
    }
    private var ghostKey: String { "\(ProgressPhotoTag.key(selectedTag))|\(source.rawValue)|\(photos.count)" }

    var body: some View {
        VStack(spacing: 0) {
            anglePills
            viewfinder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            controls
            if saved > 0 {
                Button { dismiss() } label: {
                    Text("Done").font(.cave(.headline)).foregroundStyle(Color.caveOrange)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .hapticButtonStyle(.plain)
                .padding(.horizontal, 20).padding(.vertical, 4)
                .background(Color.caveSurface)
                .accessibilityIdentifier("progressPhotoDone")
            } else {
                CaptureCancelButton { cancelCountdown(); dismiss() }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .alert("Name this angle", isPresented: $naming) {
            TextField("Flexing, Waist, Legs…", text: $typedTag)
            Button("Use") { Haptics.play(.tap); useTypedTag() }.hapticFeel(.none)
            Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
        } message: {
            Text("Up to \(ProgressPhotoTag.maxLength) letters.")
        }
        // Positioning for a timed photo can take a while; keep the screen awake meanwhile.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; cancelCountdown() }
        // Members stay in the camera for the next angle; ask now so it's known by the first save.
        .task { _ = await adder.checkPlus() }
        .task(id: ghostKey) { await loadGhost() }
    }

    // MARK: Angles

    private var anglePills: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pills, id: \.self) { pill in
                        let selected = ProgressPhotoTag.same(pill, selectedTag)
                        let taken = takenThatDay.contains { ProgressPhotoTag.same($0, pill) }
                        Button { tag = pill } label: {
                            HStack(spacing: 5) {
                                if taken { CaveIcon(.check, size: 13) }
                                Text(pill).lineLimit(1)
                            }
                            .pillLabel(selected: selected)
                        }
                        .hapticButtonStyle(.plain).hapticFeel(.selection)
                        .accessibilityLabel(pill)
                        .accessibilityValue(taken ? "Taken" : "")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("progressPhotoAngle-\(pill)")
                        .id(pill)
                    }
                    Button { typedTag = ""; naming = true } label: {
                        Text("Other…").pillLabel(selected: false)
                    }
                    .hapticButtonStyle(.plain)
                    .accessibilityIdentifier("progressPhotoOtherAngle")
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selectedTag) { _, value in
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(value, anchor: .center) }
            }
        }
        .frame(height: 56)
        .disabled(countdown != nil || reviewing || saving)
        .opacity(reviewing ? 0.4 : 1)
    }

    private func useTypedTag() {
        guard let clean = ProgressPhotoTag.clean(typedTag, known: pills) else { return }
        if !pills.contains(where: { ProgressPhotoTag.same($0, clean) }) { typedTags.append(clean) }
        tag = clean
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            Color(white: 0.1)
            feed
            if let ghost, !reviewing, ghostOpacity > 0.01 {
                fill(ghost).opacity(ghostOpacity).allowsHitTesting(false).accessibilityHidden(true)
            }
            if let shotImage { fill(shotImage).accessibilityLabel("Photo just taken") }
            if let problem { problemView(problem) }
            if let countdown {
                Text("\(countdown)")
                    .font(.custom("Schoolbell-Regular", size: 150, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("\(countdown) seconds")
                    .accessibilityIdentifier("progressPhotoCountdown")
            }
            if flash { Color.white.allowsHitTesting(false) }
            VStack {
                if !Calendar.current.isDateInToday(day) {
                    Text("For " + ProgressPhotoFormat.day(day)).cameraBadge()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                if let notice { Text(notice).cameraBadge().transition(.opacity).accessibilityIdentifier("progressPhotoNotice") }
            }
            .padding(12)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var feed: some View {
        #if targetEnvironment(simulator)
        SimulatorCameraFeed(captureRequest: captureRequest, onReady: { ready = true }, onCapture: received)
        #else
        ProgressCameraFeed(front: front, captureRequest: captureRequest,
                           onReady: { ready = true; problem = nil }, onCapture: received, onProblem: { problem = $0 })
        #endif
    }

    private func fill(_ image: UIImage) -> some View {
        Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
    }

    private func problemView(_ problem: ProgressCameraProblem) -> some View {
        VStack(spacing: 14) {
            CaveIcon(.camera, size: 44)
            Text(problem.message).font(.cave(.headline)).multilineTextAlignment(.center)
            if problem == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .hapticButtonStyle(.borderedProminent).tint(.caveOrange)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if reviewing { reviewButtons } else { ghostSlider; shutterRow }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        .frame(minHeight: 150)
        .foregroundStyle(.white)
    }

    /// Takes the same space whether or not there's a ghost, so the viewfinder doesn't jump between angles.
    private var ghostSlider: some View {
        ZStack {
            ghostControls(caption: " ").hidden().accessibilityHidden(true)
            if let ghostPhoto {
                ghostControls(caption: "Line up with your \(selectedTag) from \(ProgressPhotoFormat.day(ghostPhoto.date)).")
                    .disabled(countdown != nil)
            }
        }
    }

    private func ghostControls(caption: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Text("Ghost").font(.cave(.subheadline))
                Slider(value: $ghostOpacity, in: 0...0.8)
                    .tint(.caveOrange)
                    .accessibilityLabel("Ghost of last \(selectedTag) photo")
                    .accessibilityValue("\(Int((ghostOpacity * 100).rounded())) percent")
                    .accessibilityIdentifier("progressPhotoGhost")
                Text("\(Int((ghostOpacity * 100).rounded()))%")
                    .font(.cave(.subheadline)).monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            Text(caption)
                .font(.cave(.caption)).foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shutterRow: some View {
        HStack {
            Button { timerOn.toggle() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "timer").font(.system(size: 22, weight: .semibold))
                    Text(timerOn ? "10s" : "Off").font(.cave(.caption))
                }
                .foregroundStyle(timerOn ? Color.caveOrange : Color.white)
                .frame(width: 64, height: 64).contentShape(Rectangle())
            }
            .hapticButtonStyle(.plain).hapticFeel(.selection)
            .disabled(countdown != nil)
            .accessibilityLabel("10-second timer")
            .accessibilityValue(timerOn ? "On" : "Off")
            .accessibilityIdentifier("progressPhotoTimer")
            Spacer()
            Button(action: shutter) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                    if countdown != nil {
                        RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 28, height: 28)
                    } else {
                        Circle().fill(.white).frame(width: 64, height: 64)
                    }
                }
                .frame(width: 82, height: 82).contentShape(Circle())
            }
            .hapticButtonStyle(.plain)
            .disabled(!ready || saving)
            .accessibilityLabel(countdown != nil ? "Stop timer" : timerOn ? "Take photo in 10 seconds" : "Take photo")
            .accessibilityIdentifier("progressPhotoShutter")
            Spacer()
            Button { front.toggle() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 64).contentShape(Rectangle())
            }
            .hapticButtonStyle(.plain)
            .disabled(countdown != nil)
            .accessibilityLabel(front ? "Switch to back camera" : "Switch to front camera")
            .accessibilityIdentifier("progressPhotoFlip")
        }
    }

    private var reviewButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button(action: retake) {
                    Text("Retake").frame(maxWidth: .infinity, minHeight: 44)
                }
                .hapticButtonStyle(.bordered).tint(.white)
                .disabled(saving)
                .accessibilityIdentifier("progressPhotoRetake")
                Button(action: save) {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(.white) } else { Image(systemName: "checkmark") }
                        Text("Use Photo")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .hapticButtonStyle(.borderedProminent).tint(.caveOrange)
                // The success feel plays once the photo is really saved.
                .hapticFeel(.none)
                .disabled(saving)
                .accessibilityIdentifier("progressPhotoUse")
            }
            .font(.cave(.headline))
            Text("\(selectedTag) · \(Calendar.current.isDateInToday(day) ? "Today" : ProgressPhotoFormat.day(day))")
                .font(.cave(.footnote)).foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: Taking photos

    private func loadGhost() async {
        let match = photos.ghost(for: selectedTag, source: source)
        guard match?.id != ghostPhoto?.id || (match != nil && ghost == nil) else { return }
        ghostPhoto = match
        ghost = nil
        if let match { ghost = await photos.image(match) }
    }

    private func shutter() {
        if countdown != nil { cancelCountdown(); return }
        guard ready, !saving, !reviewing else { return }
        guard timerOn else { capture(); return }
        countdownTask = Task { @MainActor in
            for remaining in stride(from: 10, through: 1, by: -1) {
                withAnimation(reduceMotion ? nil : .snappy) { countdown = remaining }
                // Ticks for someone standing back from the phone (silent when the ringer is off).
                AudioServicesPlaySystemSound(1057)
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: "\(remaining)")
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            countdown = nil
            countdownTask = nil
            capture()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func capture() {
        captureRequest += 1
        guard !reduceMotion else { return }
        flash = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.3)) { flash = false }
        }
    }

    private func received(_ data: Data?) {
        guard let data else { showNotice("Photo didn’t take. Try again."); return }
        Task {
            let preview = await Task.detached(priority: .userInitiated) { ProgressPhotoImage.preview(data) }.value
            guard let preview else { showNotice("Photo didn’t take. Try again."); return }
            shot = data
            shotImage = preview
        }
    }

    private func retake() {
        shot = nil
        shotImage = nil
    }

    private func save() {
        guard let shot, !saving else { return }
        saving = true
        let tag = selectedTag
        Task {
            defer { saving = false }
            guard let photo = await photos.add(shot, date: Day.loggingDate(day), tag: tag, source: source) else {
                Haptics.play(.warning)
                showNotice(photos.error ?? "This photo couldn’t be saved. Please try again.")
                return
            }
            Haptics.play(.success)
            UsageStats.shared.event("progressPhoto.saved", [
                "source": source.rawValue, "timer": String(timerOn), "ghost": String(ghostPhoto != nil),
                "angle": ProgressPhotoTag.rank(tag) < ProgressPhotoTag.standard.count ? "standard" : "custom",
            ])
            saved += 1
            onSaved(photo)
            // One photo a day is free, so without Cave Cals+ the camera's job is done.
            guard adder.plus == true else { dismiss(); return }
            retake()
            self.tag = ProgressPhotoTag.next(after: tag, taken: takenThatDay)
            showNotice("\(tag) saved")
        }
    }

    private func showNotice(_ text: String) {
        withAnimation(reduceMotion ? nil : .default) { notice = text }
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: text) }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if notice == text { withAnimation(reduceMotion ? nil : .default) { notice = nil } }
        }
    }
}

private extension View {
    func pillLabel(selected: Bool) -> some View {
        font(.cave(.subheadline))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.85))
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(selected ? Color.caveOrange : Color.white.opacity(0.14), in: Capsule())
            .frame(minHeight: 44).contentShape(Rectangle())
    }

    func cameraBadge() -> some View {
        font(.cave(.subheadline)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

#if targetEnvironment(simulator)
/// The simulator has no camera, so it shows a stand-in figure and "captures" it.
private struct SimulatorCameraFeed: View {
    private static let image = ProgressPhotoSample.image(slimming: 1, side: false)
    let captureRequest: Int
    let onReady: () -> Void
    let onCapture: (Data?) -> Void

    var body: some View {
        Color.clear
            .overlay { Image(uiImage: Self.image).resizable().scaledToFill() }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text("Simulator camera").font(.cave(.caption)).foregroundStyle(.black.opacity(0.5)).padding(10)
            }
            .onAppear(perform: onReady)
            .onChange(of: captureRequest) { _, _ in onCapture(Self.image.jpegData(compressionQuality: 0.9)) }
    }
}
#else
private final class ProgressCameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    /// The angle that shows the camera in use upright. Reapplied on every layout too, since the preview's
    /// connection can appear after the angle is known.
    var rotationAngle: CGFloat = 90 { didSet { orientPreview() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        orientPreview()
    }
    func orientPreview() {
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(rotationAngle),
           connection.videoRotationAngle != rotationAngle {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

private struct ProgressCameraFeed: UIViewRepresentable {
    let front: Bool
    let captureRequest: Int
    let onReady: () -> Void
    let onCapture: (Data?) -> Void
    let onProblem: (ProgressCameraProblem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(request: captureRequest, front: front) }

    func makeUIView(context: Context) -> ProgressCameraSurface {
        let view = ProgressCameraSurface()
        view.preview.session = context.coordinator.session
        view.preview.videoGravity = .resizeAspectFill
        context.coordinator.handlers(self)
        context.coordinator.start(surface: view)
        return view
    }

    func updateUIView(_ view: ProgressCameraSurface, context: Context) {
        let coordinator = context.coordinator
        coordinator.handlers(self)
        if front != coordinator.front { coordinator.switchTo(front: front) }
        if captureRequest != coordinator.lastRequest {
            coordinator.lastRequest = captureRequest
            coordinator.capture()
        }
    }

    static func dismantleUIView(_ view: ProgressCameraSurface, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()
        private let queue = DispatchQueue(label: "cavecals.progress-camera")
        var lastRequest: Int
        /// The camera last asked for, on the main thread.
        private(set) var front: Bool
        /// The camera to use, on `queue`.
        private var wantsFront: Bool
        private var input: AVCaptureDeviceInput?
        private var stopped = false
        /// On `queue`: the live view's angle, given to every photo so it saves exactly as it looked on screen.
        private var photoAngle: CGFloat = 90
        /// Main thread. Front and back cameras (and iPad cameras) are mounted differently, so Apple's rotation
        /// coordinator works out the angle for whichever camera is in use rather than assuming one.
        private weak var surface: ProgressCameraSurface?
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var onReady: () -> Void = {}
        private var onCapture: (Data?) -> Void = { _ in }
        private var onProblem: (ProgressCameraProblem) -> Void = { _ in }

        init(request: Int, front: Bool) {
            lastRequest = request
            self.front = front
            wantsFront = front
        }

        func handlers(_ feed: ProgressCameraFeed) {
            onReady = feed.onReady
            onCapture = feed.onCapture
            onProblem = feed.onProblem
        }

        func start(surface: ProgressCameraSurface) {
            self.surface = surface
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                self.queue.async {
                    guard !self.stopped else { return }
                    guard allowed else { self.report(.denied); return }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    let added = self.session.canAddOutput(self.output)
                    if added { self.session.addOutput(self.output) }
                    let device = added ? self.attach(front: self.wantsFront) : nil
                    self.session.commitConfiguration()
                    guard let device else { self.report(.unavailable); return }
                    self.orientPhotos()
                    self.session.startRunning()
                    DispatchQueue.main.async { self.track(device); self.onReady() }
                }
            }
        }

        func switchTo(front: Bool) {
            self.front = front
            queue.async {
                self.wantsFront = front
                // Before the session starts, `start` picks up the camera asked for.
                guard !self.stopped, self.session.isRunning else { return }
                self.session.beginConfiguration()
                let device = self.attach(front: front)
                self.session.commitConfiguration()
                guard let device else { self.report(.unavailable); return }
                self.orientPhotos()
                DispatchQueue.main.async { self.track(device) }
            }
        }

        /// On `queue`, inside a configuration. Returns the camera now in use.
        private func attach(front: Bool) -> AVCaptureDevice? {
            if let input { session.removeInput(input); self.input = nil }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return nil }
            session.addInput(input)
            self.input = input
            return device
        }

        /// On `queue`. Photos get the live view's angle, and front-camera photos are mirrored as previewed, so a
        /// saved photo (and a ghost made from it) lines up with the live view. Applied after each configuration
        /// is committed and again just before every photo, since the photo connection can be rebuilt in between.
        private func orientPhotos() {
            guard let connection = output.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(photoAngle) { connection.videoRotationAngle = photoAngle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = wantsFront
            }
        }

        /// Main thread: follows the rotation coordinator for this camera.
        private func track(_ device: AVCaptureDevice) {
            guard let surface, !stopped else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: surface.preview)
            rotation = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { self?.use(angle) }
            }
        }

        /// Main thread.
        private func use(_ angle: CGFloat) {
            surface?.rotationAngle = angle
            queue.async {
                self.photoAngle = angle
                self.orientPhotos()
            }
        }

        func capture() {
            queue.async {
                guard !self.stopped, self.session.isRunning, self.input != nil else {
                    DispatchQueue.main.async { self.onCapture(nil) }
                    return
                }
                self.orientPhotos()
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }

        func stop() {
            rotationObservation = nil
            rotation = nil
            queue.async { self.stopped = true; self.session.stopRunning() }
        }

        private func report(_ problem: ProgressCameraProblem) { DispatchQueue.main.async { self.onProblem(problem) } }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            DispatchQueue.main.async { self.onCapture(data) }
        }
    }
}
#endif
