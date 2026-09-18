import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO

struct CaptureCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .cancel, action: action) {
            Text("Go Back")
                .font(.cave(.body))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(.bar)
        .accessibilityIdentifier("captureCancel")
    }
}

struct AIInputSheet: View {
    enum Mode: Equatable { case photo, voice }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let mode: Mode
    let date: Date
    var onMealDrafts: (([EntryDraft]) -> Void)? = nil
    @State private var subscriptions = AISubscriptions()
    @State private var recorder = FoodRecorder()
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var media: Data?
    @State private var uploadId: String?
    @State private var result: AIResult?
    @State private var drafts: [EntryDraft] = []
    @State private var addedDraftIDs: Set<UUID> = []
    @State private var undoDraftID: UUID?
    @State private var showScanDetails = false
    @State private var editing: EntryDraft?
    @State private var error: String?
    @State private var cameraError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var working = false
    @State private var preparingPhoto = false
    @State private var startingRecording = false
    @State private var started = false
    @State private var cameraReady = false
    @State private var capturing = false
    @State private var captureRequest = 0
    @State private var showPaywall = false
    @State private var resumeAfterPurchase = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if result == nil {
                    if mode == .photo {
                        Section { photoControls }
                            .listRowSeparator(.hidden, edges: .all)
                    } else {
                        Section { voiceControls }
                            .listRowSeparator(.hidden, edges: .all)
                    }
                } else { review }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("aiError") } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    reviewUndoBanner
                    CaptureCancelButton(action: cancel)
                }
            }
            .navigationTitle(result == nil ? (mode == .photo ? "Meal Scan" : "Speak Food") : "Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard !started else { return }
                started = true
            }
            .task(id: photo) {
                guard let photo else { return }
                preparingPhoto = true
                defer { preparingPhoto = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw AIServiceError(code: "photo", message: "The selected photo could not be loaded.")
                    }
                    try Task.checkCancellation()
                    try selectPhoto(data)
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
            .navigationDestination(isPresented: $showPaywall) {
                AIUpgradePaywall(
                    subscriptions: subscriptions,
                    onAccessGranted: { resumeAfterPurchase = true },
                    onDismissRequested: closePaywall
                )
            }
            .sheet(item: $editing) { draft in
                EntryEditorSheet(draft: draft) { updated in
                    if let index = drafts.firstIndex(where: { $0.id == updated.id }) { drafts[index] = updated }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Preserve interrupted recordings locally, without uploading in the background.
                if phase != .active && recorder.recording { finishRecording(analyzeAfter: false) }
            }
            .onChange(of: recorder.finished) { _, done in
                if done { finishRecording(analyzeAfter: false) }
            }
            .onDisappear { operation?.cancel(); recorder.cancel() }
        }.presentationDetents([.large])
    }

    @ViewBuilder private var photoControls: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Selected food photo")
                Button {
                    self.image = nil; media = nil; photo = nil; uploadId = nil; error = nil
                    cameraReady = false; cameraError = nil
                } label: {
                    CaveIcon(.plus, size: 18).rotationEffect(.degrees(45)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.black.opacity(0.65), in: Circle())
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Remove photo").disabled(working || preparingPhoto)
            } else if let cameraError {
                VStack(spacing: 16) {
                    CaveIcon(.camera, size: 56)
                    Text(cameraError).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 220).foregroundStyle(.secondary)
            } else {
                MealCameraPreview(captureRequest: captureRequest, isCapturing: capturing, onReady: { cameraReady = true }, onCapture: { data in
                    capturing = false
                    do { try selectPhoto(data); requestAnalysis() }
                    catch { self.error = error.localizedDescription }
                }, onError: { message in capturing = false; cameraReady = false; cameraError = message })
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Meal camera preview")
            }
        }
        if working {
            ProgressView("Scanning Photo…")
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("aiProcessing")
        } else {
            Button {
                if media != nil { requestAnalysis() }
                else { capturing = true; captureRequest += 1 }
            } label: {
                Text(capturing ? "Capturing…" : image == nil ? "Capture Meal" : "Scan and Analyze")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
                .disabled(preparingPhoto || capturing || (media == nil && !cameraReady))
                .accessibilityIdentifier("aiAnalyze")
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Text("or, Use Photo").frame(maxWidth: .infinity, minHeight: 44)
            }.disabled(capturing || preparingPhoto).accessibilityIdentifier("aiPhotoPicker")
        }
        if preparingPhoto { ProgressView("Preparing photo…") }
    }

    @ViewBuilder private var voiceControls: some View {
        VStack(spacing: 18) {
            CaveIcon(.voice, size: 72)
                .foregroundStyle(Color.accentColor)
                .opacity(recorder.recording && !reduceMotion ? 0 : 1)
                .animation(reduceMotion ? nil : recorder.recording ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default, value: recorder.recording)
            Text(recorder.recording ? "Listening…" : working ? "Analyzing your meal…" : media != nil ? "Recording saved" : "You Talk. App Listen.")
                .font(.cave(.title))
            Text(working ? "Finding foods and calories." : media != nil && !recorder.recording ? "Tap Analyze Recording to continue." : "Tell what you eat and how much.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
        if working {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("aiProcessing")
        } else {
            Button {
                if recorder.recording { finishRecording(analyzeAfter: true) }
                else if media != nil { requestAnalysis() }
                else { startRecording() }
            } label: {
                Text(startingRecording ? "Starting microphone…" : recorder.recording ? "Done Talking" : media != nil ? "Analyze Recording" : "Talk Now")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.recording ? .red : .blue)
            .disabled(startingRecording)
            .accessibilityIdentifier("aiRecord")
            if media != nil && !recorder.recording {
                Button("Record again") { startRecording() }.disabled(startingRecording)
            }
        }
    }

    @ViewBuilder private var review: some View {
        if let result {
            Section {
                ForEach(drafts) { draft in
                    FoodRow(
                        name: draft.name,
                        calories: draft.calories,
                        detail: draft.servingDescription,
                        suggestionLayout: true,
                        added: addedDraftIDs.contains(draft.id),
                        keepsAddedState: true,
                        add: { add(draft) },
                        edit: { editing = draft }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }.onDelete(perform: removeDrafts)
                if drafts.isEmpty { Text("No foods to add. Try a clearer photo or description.") }
            }
            if drafts.count > 1 {
                Section {
                    Button {
                        addRemainingDrafts()
                    } label: {
                        HStack(spacing: 10) {
                            CaveIcon(.check, size: 22)
                            Text("Add All")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(remainingDrafts.isEmpty || !remainingDrafts.allSatisfy(\.isValid))
                    .accessibilityIdentifier("aiAdd")
                    .accessibilityLabel("Add All")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                scanDetailsDisclosure(result)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func scanDetailsDisclosure(_ result: AIResult) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showScanDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("view scan details")
                    CaveIcon(.chevronRight, size: 15)
                        .rotationEffect(.degrees(showScanDetails ? -90 : 90))
                }
                .font(.cave(.subheadline))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanDetailsToggle")
            .accessibilityLabel("View Scan Details")
            .accessibilityValue(showScanDetails ? "Expanded" : "Collapsed")

            if showScanDetails {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.notes.isEmpty {
                        Text(result.notes).font(.cave(.subheadline)).foregroundStyle(.secondary)
                    }
                    if let transcript = result.transcript {
                        Text("You said: \(transcript)").font(.cave(.subheadline)).foregroundStyle(.secondary)
                    }
                    if result.notes.isEmpty, result.transcript == nil {
                        Text("No additional scan details.").font(.cave(.subheadline)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, drafts.count > 1 ? 10 : 2)
        .animation(.easeInOut(duration: 0.22), value: showScanDetails)
    }

    private var remainingDrafts: [EntryDraft] {
        drafts.filter { !addedDraftIDs.contains($0.id) }
    }

    @ViewBuilder private var reviewUndoBanner: some View {
        if result != nil, let undoDraftID, addedDraftIDs.contains(undoDraftID), let toast = store.toast {
            HStack {
                Text(toast).font(.cave(.subheadline)).lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") { undoLastIndividualAdd() }
                    .font(.cave(.subheadline).bold())
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .background(Color.accentColor.opacity(0.1))
            .accessibilityIdentifier("scanUndoBanner")
        }
    }

    private func add(_ draft: EntryDraft) {
        guard !addedDraftIDs.contains(draft.id), draft.isValid else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.add([draft], message: "\(name.isEmpty ? "Food" : name) added") else { return }
        addedDraftIDs.insert(draft.id)
        undoDraftID = draft.id
        if drafts.count == 1 { dismiss() }
    }

    private func undoLastIndividualAdd() {
        guard let draftID = undoDraftID else { return }
        store.undo()
        addedDraftIDs.remove(draftID)
        undoDraftID = nil
    }

    private func addRemainingDrafts() {
        let remaining = remainingDrafts
        guard !remaining.isEmpty, remaining.allSatisfy(\.isValid) else { return }
        guard store.add(remaining, message: "Added estimated foods") else { return }
        addedDraftIDs.formUnion(remaining.map(\.id))
        dismiss()
    }

    private func removeDrafts(at offsets: IndexSet) {
        let removable = IndexSet(offsets.filter { !addedDraftIDs.contains(drafts[$0].id) })
        drafts.remove(atOffsets: removable)
    }

    private func cancel() {
        operation?.cancel()
        recorder.cancel()
        dismiss()
    }

    private func selectPhoto(_ data: Data) throws {
        let prepared = try Self.preparePhoto(data)
        image = UIImage(data: prepared); media = prepared; uploadId = nil; error = nil
    }
    private func startRecording() {
        guard !startingRecording && !working else { return }
        startingRecording = true
        operation = Task { @MainActor in
            defer { startingRecording = false }
            do { try await recorder.start(); media = nil; uploadId = nil; error = nil }
            catch is CancellationError { recorder.cancel() } catch { recorder.cancel(); self.error = error.localizedDescription }
        }
    }
    private func finishRecording(analyzeAfter: Bool) {
        guard recorder.recording || recorder.finished else { return }
        do {
            media = try recorder.stop(); uploadId = nil; error = nil
            if analyzeAfter { requestAnalysis() }
        } catch { self.error = error.localizedDescription }
    }
    private func requestAnalysis() {
        guard let media, !working else { return }
        working = true; error = nil
        operation = Task { @MainActor in
            defer { working = false }
            await subscriptions.refresh()
            guard !Task.isCancelled else { return }
            guard let account = subscriptions.account else {
                error = subscriptions.message ?? "Could not check access. Please try again."
                return
            }
            guard account.active else {
                if subscriptions.offering != nil { showPaywall = true }
                else { error = subscriptions.message ?? "Subscriptions could not load. Your \(mode == .photo ? "photo" : "recording") is ready; please try again." }
                return
            }
            do {
                let response = try await AIBackend.shared.identify(data: media, kind: mode == .photo ? "image" : "audio", mime: mode == .photo ? "image/jpeg" : "audio/mp4", existingUpload: uploadId, onUpload: { id in await MainActor.run { uploadId = id } })
                try Task.checkCancellation()
                let generatedDrafts = response.drafts(at: date, source: mode == .photo ? "aiPhoto" : "aiVoice")
                if let onMealDrafts {
                    self.media = nil; image = nil
                    onMealDrafts(generatedDrafts)
                    return
                }
                result = response
                drafts = generatedDrafts
                addedDraftIDs.removeAll()
                undoDraftID = nil
                self.media = nil; image = nil
            } catch is CancellationError {} catch {
                self.error = error.localizedDescription
                if let service = error as? AIServiceError {
                    if service.code == "subscription_required", subscriptions.offering != nil { showPaywall = true }
                    if ["failed", "not_found", "ai_unavailable", "invalid_image", "invalid_audio", "no_speech", "no_estimate", "invalid_estimate", "file_mismatch"].contains(service.code) { uploadId = nil }
                }
            }
        }
    }

    private func closePaywall() {
        showPaywall = false
        guard resumeAfterPurchase else { return }
        resumeAfterPurchase = false
        Task { @MainActor in
            await Task.yield()
            requestAnalysis()
        }
    }

    static func preparePhoto(_ data: Data, maximumBytes: Int = 2 * 1024 * 1024) throws -> Data {
        guard maximumBytes > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AIServiceError(code: "photo", message: "This photo could not be read.")
        }
        var maximumDimension = 2048
        while true {
            // Always resize from the original, avoiding repeated JPEG compression artifacts.
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension
            ] as CFDictionary) else {
                throw AIServiceError(code: "photo", message: "This photo could not be read.")
            }
            let image = UIImage(cgImage: thumbnail)
            for quality in [0.85, 0.7, 0.5] {
                guard let bytes = image.jpegData(compressionQuality: quality) else {
                    throw AIServiceError(code: "photo", message: "This photo could not be converted. Please try another photo.")
                }
                if bytes.count <= maximumBytes { return bytes }
            }
            let longestSide = max(thumbnail.width, thumbnail.height)
            guard longestSide > 1 else {
                throw AIServiceError(code: "photo", message: "This photo could not be converted. Please try another photo.")
            }
            maximumDimension = max(1, Int(Double(min(maximumDimension, longestSide)) * 0.8))
        }
    }
}

@MainActor @Observable final class FoodRecorder: NSObject, AVAudioRecorderDelegate {
    var recording=false
    var finished=false
    private var recorder:AVAudioRecorder?
    private var url:URL?
    func start() async throws {
        let allowed=await AVAudioApplication.requestRecordPermission()
        guard allowed else {throw AIServiceError(code:"microphone",message:"Allow microphone access in iPhone Settings to record food.")}
        try Task.checkCancellation()
        cancel();finished=false
        let audio=AVAudioSession.sharedInstance()
        try audio.setCategory(.record,mode:.measurement);try audio.setActive(true)
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        let r=try AVAudioRecorder(url:path,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:22050,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000])
        r.delegate=self;url=path;recorder=r
        guard r.record(forDuration:60) else {cancel();throw AIServiceError(code:"recording",message:"Recording could not start.")}
        recording=true
    }
    func stop() throws -> Data {
        recorder?.delegate=nil;recorder?.stop();recording=false
        defer {cancel()}
        guard let url else {throw AIServiceError(code:"recording",message:"No recording was captured.")}
        let data=try Data(contentsOf:url)
        guard data.count>1000 else {throw AIServiceError(code:"recording",message:"Record a little longer and try again.")}
        return data
    }
    func cancel() {
        recorder?.delegate=nil;recorder?.stop();recorder=nil;recording=false;finished=false
        if let url {try? FileManager.default.removeItem(at:url)};url=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder:AVAudioRecorder,successfully flag:Bool) {Task{@MainActor in self.finished=true}}
}


private final class MealPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var captureAngle: CGFloat {
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(captureAngle) {
            connection.videoRotationAngle = captureAngle
        }
    }
}

private struct MealCameraPreview: UIViewRepresentable {
    let captureRequest: Int
    let isCapturing: Bool
    let onReady: () -> Void
    let onCapture: (Data) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(request: captureRequest, onReady: onReady, onCapture: onCapture, onError: onError)
    }
    func makeUIView(context: Context) -> MealPreviewSurface {
        let view = MealPreviewSurface()
        view.preview.session = context.coordinator.session
        view.preview.videoGravity = .resizeAspectFill
        if let connection = view.preview.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        context.coordinator.start()
        return view
    }
    func updateUIView(_ view: MealPreviewSurface, context: Context) {
        // Freeze the displayed frame immediately, without stopping the session
        // or disabling the separate photo-output connection needed for capture.
        // Re-enable it if preparation fails and this preview remains on screen.
        view.preview.connection?.isEnabled = !isCapturing
        if captureRequest != context.coordinator.lastRequest {
            context.coordinator.lastRequest = captureRequest
            let angle = view.captureAngle
            if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            context.coordinator.capture(angle: angle, aspectRatio: view.bounds.width / max(view.bounds.height, 1))
        }
    }
    static func dismantleUIView(_ view: MealPreviewSurface, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        let queue = DispatchQueue(label: "cavecals.meal-camera")
        var lastRequest: Int
        private var stopped = false
        private let onReady: () -> Void
        private let onCapture: (Data) -> Void
        private let onError: (String) -> Void
        init(request: Int, onReady: @escaping () -> Void, onCapture: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
            lastRequest = request; self.onReady = onReady; self.onCapture = onCapture; self.onError = onError
        }
        func start() {
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                self.queue.async {
                    guard !self.stopped else { return }
                    guard allowed else { self.fail("Camera unavailable\nChoose a photo or screenshot below."); return }
                    do {
                        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                            self.fail("Camera unavailable\nChoose a photo or screenshot below."); return
                        }
                        let input = try AVCaptureDeviceInput(device: device)
                        self.session.beginConfiguration()
                        self.session.sessionPreset = .photo
                        guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                            self.session.commitConfiguration(); self.fail("Camera unavailable\nChoose a photo or screenshot below."); return
                        }
                        self.session.addInput(input); self.session.addOutput(self.output)
                        self.session.commitConfiguration()
                        // Portrait camera orientation is independent of the horizontal preview frame.
                        if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                            connection.videoRotationAngle = 90
                        }
                        self.session.startRunning()
                        DispatchQueue.main.async { self.onReady() }
                    } catch { self.fail("Camera unavailable\nChoose a photo or screenshot below.") }
                }
            }
        }
        private var captureAspectRatio: CGFloat = 4.0 / 3.0
        func capture(angle: CGFloat, aspectRatio: CGFloat) {
            queue.async {
                guard !self.stopped, self.session.isRunning else { self.fail("Camera is not ready. Please try again."); return }
                self.captureAspectRatio = aspectRatio
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .speed
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
        func stop() { queue.async { self.stopped = true; self.session.stopRunning() } }
        private func fail(_ message: String) { DispatchQueue.main.async { self.onError(message) } }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard error == nil, let data = photo.fileDataRepresentation() else { fail("The photo could not be captured. Please try again."); return }
            let aspectRatio = captureAspectRatio
            DispatchQueue.main.async {
                guard let image = UIImage(data: data),
                      let cropped = MealPhotoCrop.jpeg(image, aspectRatio: aspectRatio) else {
                    self.onError("The photo could not be prepared. Please try again."); return
                }
                self.onCapture(cropped)
            }
        }
    }
}

// Draw through UIImage to apply EXIF orientation before matching resizeAspectFill.
enum MealPhotoCrop {
    static func jpeg(_ image: UIImage, aspectRatio: CGFloat) -> Data? {
        guard image.size.width > 0, image.size.height > 0, aspectRatio.isFinite, aspectRatio > 0 else { return nil }
        let width = min(image.size.width, image.size.height * aspectRatio)
        let size = CGSize(width: width, height: width / aspectRatio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(x: (size.width - image.size.width) / 2,
                                  y: (size.height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
        }.jpegData(compressionQuality: 0.95)
    }
}
