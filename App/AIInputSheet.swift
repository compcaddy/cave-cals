import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO

struct CaptureCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .cancel, action: action) {
            Text("Cancel")
                .font(.cave(.body))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .hapticButtonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Color.caveSurface)
        .accessibilityIdentifier("captureCancel")
    }
}

/// How much was eaten, in one phrase. One countable thing becomes the total ("1 slice" eaten twice reads
/// "2 slices"); a measured serving keeps its size and the count ("1 cup (240 ml) × 2", "100 g × 1.5"), since
/// adding those up would hide the unit the estimate was based on. One serving shows just the serving.
enum ServingCount {
    static func text(serving: String, servings: Double) -> String {
        let count = servings.formatted(.number.precision(.fractionLength(0...2)))
        let serving = serving.trimmingCharacters(in: .whitespacesAndNewlines)
        if serving.isEmpty { return servings == 1 ? "1 serving" : "\(count) servings" }
        if servings == 1 { return serving }
        if let unit = countableUnit(serving) { return "\(count) \(plural(unit))" }
        return "\(serving) × \(count)"
    }
    /// "slice" from "1 slice": a short name of one thing, with no amounts, sizes in parentheses, or units of measure.
    private static func countableUnit(_ serving: String) -> String? {
        guard serving.hasPrefix("1 ") else { return nil }
        let unit = String(serving.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let words = unit.split(separator: " ")
        guard !unit.isEmpty, words.count <= 4, unit.rangeOfCharacter(from: .decimalDigits) == nil,
              unit.rangeOfCharacter(from: CharacterSet(charactersIn: "()/,")) == nil,
              let first = words.first, !measures.contains(first.lowercased()) else { return nil }
        return unit
    }
    /// Units whose totals would read oddly or mean something else ("2 g" is not two servings of a gram).
    private static let measures: Set<String> = [
        "g", "gram", "grams", "kg", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "ml", "l", "liter",
        "litre", "fl", "tbsp", "tsp", "tablespoon", "teaspoon", "cup", "cups", "pint", "quart", "serving",
    ]
    /// Pluralizes the thing counted: the word before "of" ("slices of pizza"), else the last word ("side salads").
    static func plural(_ unit: String) -> String {
        var words = unit.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let head = words.firstIndex { $0.lowercased() == "of" }.map { $0 - 1 } ?? words.count - 1
        guard words.indices.contains(head) else { return unit }
        words[head] = pluralWord(words[head])
        return words.joined(separator: " ")
    }
    private static let irregular = ["leaf": "leaves", "loaf": "loaves", "half": "halves", "knife": "knives",
                                    "potato": "potatoes", "tomato": "tomatoes", "fish": "fish", "piece": "pieces"]
    private static func pluralWord(_ word: String) -> String {
        let lower = word.lowercased()
        if let plural = irregular[lower] { return word.first?.isUppercase == true ? plural.capitalized : plural }
        if ["ss", "sh", "ch"].contains(where: lower.hasSuffix) || lower.hasSuffix("x") || lower.hasSuffix("z") { return word + "es" }
        // Already plural ("fries", "chips").
        if lower.hasSuffix("s") { return word }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) { return word.dropLast() + "ies" }
        return word + "s"
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
    /// The meal picked for this scan's foods, when adding asks for one.
    @State private var mealType: String?
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
    @State private var mealRoute: MealRoute?
    @State private var gatedOnOpen = false
    @State private var paywallTrigger = PaywallTrigger.mealScanOpen
    /// Voice Log's "Type instead": a typed or pasted description replaces the recording, for places
    /// where speaking out loud doesn't work. "Record voice instead" switches back and starts listening.
    @State private var typing = false
    @State private var typedText = ""
    @State private var resultWasTyped = false
    @FocusState private var typedFocused: Bool
    /// The backend's `food/describe` limit, in UTF-16 units like its JavaScript check.
    static let typedLimit = 2000
    private var statsArea: StatsErrorArea { mode == .photo ? .mealScan : .voice }

    var body: some View {
        NavigationStack {
            HapticList {
                if result == nil {
                    if mode == .photo {
                        Section { photoControls }
                            .listRowSeparator(.hidden, edges: .all)
                    } else {
                        Section { voiceControls } footer: { voiceSwitch }
                            .listRowSeparator(.hidden, edges: .all)
                    }
                } else { review }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("aiError") } }
            }.caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    reviewUndoBanner
                    CaptureCancelButton(action: cancel)
                }
            }
            .navigationTitle(result == nil ? (mode == .photo ? "Meal Scan" : typing ? "Type Food" : "Speak Food") : "Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .task { autoStartRecordingIfReady() }
            .task { await gateAccessOnOpen() }
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
                } catch is CancellationError {} catch {
                    self.error = error.localizedDescription
                    UsageStats.shared.error(.mealScan, error)
                }
            }
            .navigationDestination(isPresented: $showPaywall) {
                AIUpgradePaywall(
                    subscriptions: subscriptions,
                    trigger: paywallTrigger,
                    onAccessGranted: { resumeAfterPurchase = true },
                    onDismissRequested: closePaywall
                )
            }
            .sheet(item: $mealRoute) { route in MealEditorSheet(route: route) }
            .sheet(item: $editing) { draft in
                EntryEditorSheet(draft: draft) { updated in
                    if let index = drafts.firstIndex(where: { $0.id == updated.id }) { drafts[index] = updated }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Preserve interrupted recordings locally, without uploading in the background.
                if phase != .active && recorder.recording { finishRecording(analyzeAfter: false) }
                if phase == .active { autoStartRecordingIfReady() }
            }
            .onChange(of: recorder.finished) { _, done in
                if done { finishRecording(analyzeAfter: false) }
            }
            .onDisappear { operation?.cancel(); recorder.cancel() }
            #if DEBUG && targetEnvironment(simulator)
            .task { showReviewFixtureIfRequested() }
            #endif
        }.presentationDetents([.large])
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `--review-scan-fixture` opens straight to Review Scan with two foods, for UI tests without the AI backend.
    private func showReviewFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--review-scan-fixture"), onMealDrafts == nil, result == nil else { return }
        let fixture = AIResult(items: [
            AIFoodEstimate(name: "Grilled chicken", calories: 280, portion: "1 breast", confidence: "high"),
            AIFoodEstimate(name: "Side salad", calories: 90, portion: "1 bowl", confidence: "medium"),
        ], notes: "Sample scan.")
        result = fixture
        drafts = fixture.drafts(at: date, source: mode == .photo ? "aiPhoto" : "aiVoice")
    }
    #endif

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
                }.hapticButtonStyle(.plain).accessibilityLabel("Remove photo").disabled(working || preparingPhoto)
            } else if let cameraError {
                VStack(spacing: 16) {
                    CaveIcon(.camera, size: 56)
                    Text(cameraError).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 220).foregroundStyle(.secondary)
            } else {
                MealCameraPreview(captureRequest: captureRequest, isCapturing: capturing, onReady: { cameraReady = true }, onCapture: { data in
                    capturing = false
                    do { try selectPhoto(data); requestAnalysis() }
                    catch { self.error = error.localizedDescription; UsageStats.shared.error(.mealScan, error) }
                }, onError: { message in
                    capturing = false; cameraReady = false; cameraError = message
                    UsageStats.shared.error(.mealScan, code: "camera", message: message)
                })
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
            }.hapticButtonStyle(.borderedProminent)
                .disabled(preparingPhoto || capturing || (media == nil && !cameraReady))
                .accessibilityIdentifier("aiAnalyze")
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Text("or, Use Photo").frame(maxWidth: .infinity, minHeight: 44)
            }.disabled(capturing || preparingPhoto).accessibilityIdentifier("aiPhotoPicker")
        }
        if preparingPhoto { ProgressView("Preparing photo…") }
    }

    @ViewBuilder private var voiceControls: some View {
        if typing { typedControls } else { spokenControls }
    }

    /// Small, centered, right below the card: switches between speaking and typing.
    @ViewBuilder private var voiceSwitch: some View {
        if !working {
            Button {
                if typing { switchToVoice() } else { switchToTyping() }
            } label: {
                Text(typing ? "Record voice instead" : "Type instead")
                    .font(.cave(.subheadline)).foregroundStyle(Color.caveOrange)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .hapticButtonStyle(.plain)
            .accessibilityHint(typing ? "Stops typing and starts recording" : "Stops recording so you can type or paste what you ate")
            .accessibilityIdentifier(typing ? "recordVoiceInstead" : "typeInstead")
        }
    }

    @ViewBuilder private var typedControls: some View {
        VStack(spacing: 14) {
            CaveIcon(.pencil, size: 56).foregroundStyle(Color.accentColor)
            Text(working ? "Analyzing your meal…" : "You Type. App Read.").font(.cave(.title))
            Text(working ? "Finding foods and calories." : "Tell what you eat and how much.").foregroundStyle(.secondary)
            // A text editor, not a vertical text field: Return adds a line and pasted lists keep theirs.
            TextEditor(text: $typedText)
                .font(.cave(.body))
                .focused($typedFocused)
                .disabled(working)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 220)
                .overlay(alignment: .topLeading) {
                    if typedText.isEmpty {
                        Text("Two scrambled eggs, toast with butter, and a coffee with milk.")
                            .font(.cave(.body)).foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.caveBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .keyboardInputArea { typedFocused = true }
                .accessibilityLabel("What you ate")
                .accessibilityIdentifier("aiTypedText")
                .onChange(of: typedText) { _, text in
                    if text.utf16.count > Self.typedLimit { typedText = Self.trimmed(text, to: Self.typedLimit) }
                }
            if typedText.utf16.count > Self.typedLimit - 200 {
                Text("\(typedText.utf16.count.formatted()) / \(Self.typedLimit.formatted())")
                    .font(.cave(.caption)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 8)
        if working {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("aiProcessing")
        } else {
            Button { requestTextAnalysis() } label: {
                Text("Analyze").frame(maxWidth: .infinity, minHeight: 44)
            }
            .hapticButtonStyle(.borderedProminent)
            .tint(.caveOrange)
            .disabled(typedDescription.count < 2)
            .accessibilityIdentifier("aiAnalyzeText")
        }
    }

    @ViewBuilder private var spokenControls: some View {
        VStack(spacing: 18) {
            CaveIcon(.voice, size: 72)
                .foregroundStyle(Color.accentColor)
                .opacity(recorder.recording && !reduceMotion ? 0 : 1)
                .animation(reduceMotion ? nil : recorder.recording ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default, value: recorder.recording)
            Text(recorder.recording ? "Listening…" : working ? "Analyzing your meal…" : media != nil ? "Recording saved" : "You Talk. App Listen.")
                .font(.cave(.title))
            Text(working ? "Finding foods and calories." : media != nil && !recorder.recording ? "Tap Analyze Recording to continue." : "Tell what you eat and how much.").foregroundStyle(.secondary)
            if recorder.recording, let startedAt = recorder.startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let elapsed = min(context.date.timeIntervalSince(startedAt), FoodRecorder.maxDuration)
                    Text("\(clock(elapsed)) / \(clock(FoodRecorder.maxDuration))")
                        .font(.cave(.headline)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("\(Int(elapsed)) seconds recorded")
                }
            } else if !working && media == nil {
                Text("Try: “Two scrambled eggs, toast with butter, and a coffee with milk.”")
                    .font(.cave(.footnote)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
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
            .hapticButtonStyle(.borderedProminent)
            .tint(recorder.recording ? .red : .caveOrange)
            .disabled(startingRecording)
            .accessibilityIdentifier("aiRecord")
            if media != nil && !recorder.recording {
                Button("Record again") { startRecording() }.disabled(startingRecording)
            }
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// Adding asks for a meal type (and this scan is being logged, not building a saved meal).
    private var choosesMeal: Bool { store.mealSettings.asks && onMealDrafts == nil }

    static func servingDetail(_ draft: EntryDraft) -> String {
        ServingCount.text(serving: draft.servingDescription, servings: draft.servings)
    }

    @ViewBuilder private var review: some View {
        if let result {
            if choosesMeal, !drafts.isEmpty {
                // One scan is usually one meal, so its foods share the choice.
                Section("Meal type") {
                    MealTypePicker(types: store.mealSettings.visibleTypes, selection: $mealType)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(drafts) { draft in
                    FoodRow(
                        name: draft.name,
                        calories: draft.calories,
                        detail: Self.servingDetail(draft),
                        macros: MacroSummary([draft]),
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
            // Always shown, even for one food: one big button adds whatever is listed and moves on.
            if !drafts.isEmpty {
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
                    .hapticButtonStyle(.borderedProminent)
                    .tint(.caveOrange)
                    .hapticFeel(.success)
                    .disabled(remainingDrafts.isEmpty || !remainingDrafts.allSatisfy(\.isValid))
                    .accessibilityIdentifier("aiAdd")
                    .accessibilityLabel("Add All")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if drafts.count > 1 {
                    Button {
                        mealRoute = MealRoute(items: drafts)
                    } label: {
                        HStack(spacing: 8) {
                            CaveIcon(.meals, size: 20)
                            Text("Save as Meal")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .hapticButtonStyle(.bordered)
                    .tint(.caveOrange)
                    .disabled(drafts.isEmpty || !drafts.allSatisfy(\.isValid))
                    .accessibilityIdentifier("aiSaveMeal")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    }
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
            .hapticButtonStyle(.plain)
            .accessibilityIdentifier("scanDetailsToggle")
            .accessibilityLabel("View Scan Details")
            .accessibilityValue(showScanDetails ? "Expanded" : "Collapsed")

            if showScanDetails {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.notes.isEmpty {
                        Text(result.notes).font(.cave(.subheadline)).foregroundStyle(.secondary)
                    }
                    if let transcript = result.transcript {
                        Text("\(resultWasTyped ? "You wrote" : "You said"): \(transcript)").font(.cave(.subheadline)).foregroundStyle(.secondary)
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
        var draft = draft
        draft.mealType = choosesMeal ? mealType : nil
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
        let chosen = choosesMeal ? mealType : nil
        guard store.add(remaining.map { var draft = $0; draft.mealType = chosen; return draft }, message: remaining.count == 1 ? "\(remaining[0].name.isEmpty ? "Food" : remaining[0].name) added" : "Added estimated foods") else { return }
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
    // Widget cold launches can present the sheet before the scene is active; recording then would be stopped immediately.
    private func autoStartRecordingIfReady() {
        guard mode == .voice, !started, scenePhase == .active,
              !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        started = true
        startRecording()
    }
    /// Stops listening (dropping anything recorded) and opens the keyboard for a typed description.
    private func switchToTyping() {
        operation?.cancel()
        recorder.cancel(); media = nil; uploadId = nil; error = nil
        typing = true
        UsageStats.shared.event("voice.typeInstead")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if typing { typedFocused = true }
        }
    }
    /// Back to speaking: the typed text stays for a later switch, and listening starts right away.
    private func switchToVoice() {
        typedFocused = false
        typing = false; error = nil
        // UI tests skip starting the microphone, as they do when the screen opens.
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") { startRecording() }
    }
    /// What's sent: trimmed, with stray control characters (not line breaks or tabs) turned into spaces.
    private var typedDescription: String {
        String(String.UnicodeScalarView(typedText.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) && !"\n\r\t".unicodeScalars.contains(scalar) ? " " : scalar
        })).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Drops whole characters from the end until the text fits `limit` UTF-16 units.
    nonisolated static func trimmed(_ text: String, to limit: Int) -> String {
        var result = text
        while result.utf16.count > limit { result.removeLast() }
        return result
    }
    private func startRecording() {
        guard !startingRecording && !working else { return }
        startingRecording = true
        operation = Task { @MainActor in
            defer { startingRecording = false }
            do { try await recorder.start(); media = nil; uploadId = nil; error = nil }
            catch is CancellationError { recorder.cancel() } catch {
                recorder.cancel(); self.error = error.localizedDescription
                UsageStats.shared.error(.voice, error)
            }
        }
    }
    private func finishRecording(analyzeAfter: Bool) {
        guard recorder.recording || recorder.finished else { return }
        do {
            media = try recorder.stop(); uploadId = nil; error = nil
            if analyzeAfter { requestAnalysis() }
        } catch { self.error = error.localizedDescription; UsageStats.shared.error(.voice, error) }
    }
    private func requestAnalysis() {
        guard let media, !working else { return }
        working = true; error = nil
        operation = Task { @MainActor in
            defer { working = false }
            await subscriptions.refresh(regularLogCount: store.regularLogCount)
            guard !Task.isCancelled else { return }
            guard let account = subscriptions.account else {
                error = subscriptions.message ?? "Could not check access. Please try again."
                return
            }
            // A completed upload can always be retrieved, including the tenth free scan.
            guard account.canScan || uploadId != nil else {
                if subscriptions.offering != nil { openPaywall(onOpen: false) }
                else {
                    error = subscriptions.message ?? "Subscriptions could not load. Your \(mode == .photo ? "photo" : "recording") is ready; please try again."
                    UsageStats.shared.error(statsArea, code: "paywall_unavailable", message: error ?? "")
                }
                return
            }
            do {
                let response = try await AIBackend.shared.identify(data: media, kind: mode == .photo ? "image" : "audio", mime: mode == .photo ? "image/jpeg" : "audio/mp4", existingUpload: uploadId, regularLogCount: store.regularLogCount, onUpload: { id in await MainActor.run { uploadId = id } })
                try Task.checkCancellation()
                UsageStats.shared.scan(mode == .photo ? .mealScan : .voice)
                present(response, typed: false)
            } catch is CancellationError {} catch {
                self.error = error.localizedDescription
                UsageStats.shared.error(statsArea, error)
                if let service = error as? AIServiceError {
                    if service.code == "subscription_required", subscriptions.offering != nil { openPaywall(onOpen: false) }
                    if ["failed", "not_found", "ai_unavailable", "invalid_image", "invalid_audio", "no_speech", "no_estimate", "invalid_estimate", "file_mismatch"].contains(service.code) { uploadId = nil }
                }
            }
        }
    }

    /// Typed descriptions go to `food/describe`, which charges one scan like a recording.
    private func requestTextAnalysis() {
        let text = typedDescription
        guard text.count >= 2, !working else { return }
        typedFocused = false
        working = true; error = nil
        operation = Task { @MainActor in
            defer { working = false }
            await subscriptions.refresh(regularLogCount: store.regularLogCount)
            guard !Task.isCancelled else { return }
            guard let account = subscriptions.account else {
                error = subscriptions.message ?? "Could not check access. Please try again."
                return
            }
            guard account.canScan else {
                if subscriptions.offering != nil { openPaywall(onOpen: false) }
                else {
                    error = subscriptions.message ?? "Subscriptions could not load. What you typed is still here; please try again."
                    UsageStats.shared.error(.voice, code: "paywall_unavailable", message: error ?? "")
                }
                return
            }
            do {
                let response = try await AIBackend.shared.describe(text: text, regularLogCount: store.regularLogCount)
                try Task.checkCancellation()
                UsageStats.shared.scan(.voiceTyped)
                present(response, typed: true)
            } catch is CancellationError {} catch {
                self.error = error.localizedDescription
                UsageStats.shared.error(.voice, error)
                if let service = error as? AIServiceError, service.code == "subscription_required", subscriptions.offering != nil {
                    openPaywall(onOpen: false)
                }
            }
        }
    }

    /// Shows an estimate in Review Scan, or hands it to the New Meal editor.
    private func present(_ response: AIResult, typed: Bool) {
        let generatedDrafts = response.drafts(at: date, source: mode == .photo ? "aiPhoto" : "aiVoice")
        if generatedDrafts.isEmpty { UsageStats.shared.error(statsArea, code: "no_foods", message: "The scan found no foods to add.") }
        media = nil; image = nil
        if let onMealDrafts {
            onMealDrafts(generatedDrafts)
            return
        }
        result = response
        resultWasTyped = typed
        drafts = generatedDrafts
        addedDraftIDs.removeAll()
        undoDraftID = nil
    }

    /// Runs alongside the camera/microphone start so paying users see no delay. When scans are used up,
    /// the paywall appears before anything is captured, uploaded, or analyzed.
    private func gateAccessOnOpen() async {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        await subscriptions.refresh(regularLogCount: store.regularLogCount)
        guard !Task.isCancelled, let account = subscriptions.account, !account.canScan,
              subscriptions.offering != nil, result == nil, uploadId == nil else { return }
        recorder.cancel(); media = nil; image = nil
        gatedOnOpen = true
        openPaywall(onOpen: true)
    }

    /// Notes which screen and moment showed the paywall, for the stats.
    private func openPaywall(onOpen: Bool) {
        let newMeal = onMealDrafts != nil
        paywallTrigger = switch (mode, newMeal, onOpen) {
        case (.photo, false, true): .mealScanOpen
        case (.photo, false, false): .mealScanAnalyze
        case (.voice, false, true): .voiceOpen
        case (.voice, false, false): .voiceAnalyze
        case (.photo, true, true): .newMealPhotoOpen
        case (.photo, true, false): .newMealPhotoAnalyze
        case (.voice, true, true): .newMealVoiceOpen
        case (.voice, true, false): .newMealVoiceAnalyze
        }
        showPaywall = true
    }

    private func closePaywall() {
        showPaywall = false
        guard resumeAfterPurchase else {
            // Declining the up-front paywall leaves nothing usable here, so close the capture screen too.
            if gatedOnOpen { dismiss() }
            return
        }
        resumeAfterPurchase = false
        gatedOnOpen = false
        Task { @MainActor in
            await Task.yield()
            if typing { requestTextAnalysis() }
            else if media != nil { requestAnalysis() }
            else if mode == .voice { startRecording() }
        }
    }

    nonisolated static func preparePhoto(_ data: Data, maximumBytes: Int = 2 * 1024 * 1024) throws -> Data {
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
    static let maxDuration: TimeInterval = 60
    private(set) var startedAt: Date?
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
        guard r.record(forDuration:Self.maxDuration) else {cancel();throw AIServiceError(code:"recording",message:"Recording could not start.")}
        recording=true;startedAt=Date()
    }
    func stop() throws -> Data {
        recorder?.delegate=nil;recorder?.stop();recording=false;startedAt=nil
        defer {cancel()}
        guard let url else {throw AIServiceError(code:"recording",message:"No recording was captured.")}
        let data=try Data(contentsOf:url)
        guard data.count>1000 else {throw AIServiceError(code:"recording",message:"Record a little longer and try again.")}
        return data
    }
    func cancel() {
        recorder?.delegate=nil;recorder?.stop();recorder=nil;recording=false;finished=false;startedAt=nil
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
