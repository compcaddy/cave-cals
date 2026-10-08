import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Where a recipe import comes from: New Meal → Import a recipe offers all three.
enum RecipeImportSource: String {
    case link, photo, clipboard
}

/// The whole recipe an import produced and how many servings it makes; the meal editor divides when saving.
struct ImportedRecipe {
    var name: String
    var items: [EntryDraft]
    var servings: Int
}

enum RecipeImportInput {
    static let maxPages = 5
    /// Matches the backend's `MAX_RECIPE_TEXT`.
    static let maxTextLength = 20_000
    static let minTextLength = 20

    /// Accepts "example.com/recipe" or http links and upgrades them to https.
    static func link(_ value: String) -> URL? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("http://") { value = "https://" + value.dropFirst(7) }
        if !value.lowercased().hasPrefix("https://") { value = "https://" + value }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Copied text that is only a link imports that page instead.
    static func pastedLink(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.lowercased().hasPrefix("http") || value.lowercased().hasPrefix("www.") || value.contains("/") else { return nil }
        return link(value)
    }

    /// Drops control characters the backend refuses (keeping line breaks and tabs), trims the ends, and keeps
    /// within the backend's limit, which counts UTF-16 units (an emoji counts twice there).
    static func cleanText(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar == "\r" || (scalar.value >= 0x20 && scalar.value != 0x7f)
        }
        let clean = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf16.count > maxTextLength else { return clean }
        var units = 0
        var end = clean.startIndex
        for index in clean.indices {
            units += clean[index].utf16.count
            guard units <= maxTextLength else { break }
            end = clean.index(after: index)
        }
        return String(clean[..<end])
    }
}

/// One recipe page ready to upload: a prepared JPEG plus a small thumbnail for the page strip.
struct RecipePage: Identifiable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage

    init(_ original: Data) throws {
        data = try AIInputSheet.preparePhoto(original)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360
              ] as CFDictionary) else {
            throw AIServiceError(code: "photo", message: "This photo could not be read.")
        }
        thumbnail = UIImage(cgImage: small)
    }
}

/// Imports a recipe from a link, photos of its pages, or whatever was copied, then hands the whole recipe and its
/// serving count to the meal editor for review. Cave Cals+ only: the paywall shows as soon as it opens.
struct RecipeImportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: RecipeImportSource
    let imported: (ImportedRecipe) -> Void
    @State private var subscriptions = AISubscriptions()
    @State private var link = ""
    @State private var pages: [RecipePage] = []
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var preparingPages = false
    @State private var showCamera = false
    @State private var pastedText = ""
    @State private var textTrimmed = false
    @State private var working = false
    @State private var progress: String?
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var showPaywall = false
    @State private var retryAfterPurchase = false
    @State private var gatedOnOpen = false
    @State private var paywallTrigger = PaywallTrigger.recipeImportOpen

    private enum Request {
        case link(URL), text(String), pages([RecipePage])
    }

    var body: some View {
        NavigationStack {
            HapticForm {
                switch source {
                case .link: linkSection
                case .photo: pagesSection
                case .clipboard: clipboardSections
                }
                Section {
                    Button(action: runImport) {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(.white) }
                            else { CaveIcon(.arrowRight, size: 18) }
                            Text(working ? progress ?? "Importing…" : "Import Recipe")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .hapticButtonStyle(.borderedProminent)
                    .disabled(request == nil || working || preparingPages)
                    .accessibilityIdentifier("importMeal")
                } footer: {
                    if working { Text("Big recipe take a minute. Every food shown for review before saving.") }
                }
                .listRowBackground(Color.clear)
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }.caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .task {
                // Importing is a Cave Cals+ feature: show the paywall before anything is chosen or pasted.
                guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
                await subscriptions.refresh(regularLogCount: store.regularLogCount)
                if let account = subscriptions.account, !account.active, subscriptions.offering != nil {
                    gatedOnOpen = true
                    paywallTrigger = .recipeImportOpen
                    showPaywall = true
                }
            }
            .onDisappear { operation?.cancel() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { operation?.cancel(); dismiss() }.hapticButtonStyle(.automatic)
                }
            }
            .navigationDestination(isPresented: $showPaywall) {
                AIUpgradePaywall(
                    subscriptions: subscriptions,
                    trigger: paywallTrigger,
                    onAccessGranted: { retryAfterPurchase = true },
                    onDismissRequested: closePaywall
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                RecipeCamera { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                    addPages([data])
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                Task { @MainActor in
                    var originals: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { originals.append(data) }
                    }
                    if originals.count < items.count { error = "Some photos could not be loaded. Try choosing them again." }
                    addPages(originals)
                }
            }
        }
        .presentationDetents(source == .link ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch source {
        case .link: "Recipe Link"
        case .photo: "Recipe Photos"
        case .clipboard: "Paste Recipe"
        }
    }

    // MARK: Link

    @ViewBuilder private var linkSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("example.com/recipe", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(runImport)
                    .accessibilityIdentifier("mealImportLink")
                // PasteButton reads the clipboard only when tapped, so no paste-permission prompt.
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { link = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(.caveOrange)
            }
            // Paste belongs to the link field, so it keeps the keyboard up.
            .keyboardInputArea()
        } header: {
            Text("Recipe or meal link")
        } footer: {
            Text("Works with public recipe sites and restaurant menu pages. Every item is shown for review before the meal is saved.")
        }
    }

    // MARK: Photos

    @ViewBuilder private var pagesSection: some View {
        Section {
            if !pages.isEmpty { pageStrip }
            if pages.count < RecipeImportInput.maxPages {
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: RecipeImportInput.maxPages - pages.count,
                             selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                    Label { Text(pages.isEmpty ? "Pick from Photos" : "Add from Photos") } icon: { CaveIcon(.phone, size: 22) }
                        .foregroundStyle(Color.caveOrange)
                        .frame(minHeight: 44)
                }
                .disabled(working || preparingPages)
                .accessibilityIdentifier("recipePickPhotos")
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        Label { Text(pages.isEmpty ? "Take Photo" : "Take Another Photo") } icon: { CaveIcon(.camera, size: 22) }
                            .foregroundStyle(Color.caveOrange)
                            .frame(minHeight: 44)
                    }
                    .disabled(working || preparingPages)
                    .accessibilityIdentifier("recipeTakePhoto")
                }
            }
            if preparingPages { ProgressView("Preparing photos…") }
        } header: {
            Text(pages.isEmpty ? "Recipe pages" : "Recipe pages (\(pages.count) of \(RecipeImportInput.maxPages))")
        } footer: {
            Text("Cookbook page, recipe card, or screenshot. Up to \(RecipeImportInput.maxPages) pages, in order.")
        }
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    pageThumbnail(page, number: index + 1, of: pages.count)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func pageThumbnail(_ page: RecipePage, number: Int, of count: Int) -> some View {
        Image(uiImage: page.thumbnail)
            .resizable().scaledToFill()
            .frame(width: 84, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if count > 1 {
                    Text("\(number)").font(.cave(.caption).bold()).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color.caveOrange, in: Circle())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation { pages.removeAll { $0.id == page.id } } } label: {
                    CaveIcon(.plus, size: 12).rotationEffect(.degrees(45))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .hapticButtonStyle(.borderless)
                .disabled(working)
                .accessibilityLabel("Remove page \(number)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recipe page \(number)")
    }

    private func addPages(_ originals: [Data]) {
        guard !originals.isEmpty else { return }
        preparingPages = true
        Task { @MainActor in
            defer { preparingPages = false }
            let room = RecipeImportInput.maxPages - pages.count
            let prepared = await Task.detached(priority: .userInitiated) {
                originals.prefix(max(0, room)).map { try? RecipePage($0) }
            }.value
            let readable = prepared.compactMap { $0 }
            if readable.count < prepared.count {
                error = "Some photos could not be read. Try a JPEG, PNG, or HEIC photo."
            } else if source == .photo {
                error = nil
            }
            if source == .clipboard {
                // A pasted picture replaces whatever was pasted before.
                pages = Array(readable.prefix(1))
                if !readable.isEmpty { pastedText = ""; textTrimmed = false }
            } else {
                pages += readable
            }
        }
    }

    // MARK: Clipboard

    @ViewBuilder private var clipboardSections: some View {
        Section {
            // Reads the clipboard only when tapped, so no paste-permission prompt; greyed out when nothing usable is copied.
            PasteButton(supportedContentTypes: [.plainText, .url, .image]) { providers in
                Haptics.play(.tap)
                paste(providers)
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(.caveOrange)
            .disabled(working)
            .frame(maxWidth: .infinity, minHeight: 44)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Copy recipe words or a picture of a recipe, then tap Paste. Links work too.")
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        Section {
            if let page = pages.first {
                HStack {
                    Spacer()
                    pageThumbnail(page, number: 1, of: 1)
                    Spacer()
                }
            } else {
                TextEditor(text: $pastedText)
                    .font(.cave(.body))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("Or paste or type recipe here")
                                .font(.cave(.body)).foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .keyboardInputArea()
                    .accessibilityIdentifier("recipeText")
                    .accessibilityLabel("Recipe text")
                    .onChange(of: pastedText) { _, text in
                        if text.count > RecipeImportInput.maxTextLength {
                            pastedText = String(text.prefix(RecipeImportInput.maxTextLength))
                            textTrimmed = true
                        }
                    }
            }
        } header: {
            Text(pages.isEmpty ? (RecipeImportInput.pastedLink(pastedText) == nil ? "Recipe" : "Recipe link") : "Recipe picture")
        } footer: {
            if RecipeImportInput.pastedLink(pastedText) != nil {
                Text("Link found. Cave read that page.")
            } else if textTrimmed {
                Text("Long recipe. Cave read first \(RecipeImportInput.maxTextLength.formatted()) letters.")
            }
        }
    }

    /// Text wins over a picture (it reads more accurately); text that is only a link imports that page.
    private func paste(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            error = nil
            if let text = await Self.loadText(providers), !RecipeImportInput.cleanText(text).isEmpty {
                pages = []
                textTrimmed = text.count > RecipeImportInput.maxTextLength
                pastedText = String(text.prefix(RecipeImportInput.maxTextLength))
            } else if let image = await Self.loadImage(providers) {
                addPages([image])
            } else if let url = await Self.loadURL(providers) {
                pages = []; textTrimmed = false
                pastedText = url.absoluteString
            } else {
                error = "Nothing to paste. Copy recipe words or a picture first."
            }
        }
    }

    private static func loadText(_ providers: [NSItemProvider]) async -> String? {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in continuation.resume(returning: value as? String) }
            }
            if let text { return text }
        }
        return nil
    }

    private static func loadImage(_ providers: [NSItemProvider]) async -> Data? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in continuation.resume(returning: data) }
            }
            if let data { return data }
        }
        return nil
    }

    private static func loadURL(_ providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { value, _ in continuation.resume(returning: (value as? NSURL) as URL?) }
            }
            if let url, url.scheme?.lowercased().hasPrefix("http") == true { return url }
        }
        return nil
    }

    // MARK: Import

    private var request: Request? {
        switch source {
        case .link:
            return RecipeImportInput.link(link).map(Request.link)
        case .photo:
            return pages.isEmpty ? nil : .pages(pages)
        case .clipboard:
            if !pages.isEmpty { return .pages(pages) }
            if let url = RecipeImportInput.pastedLink(pastedText) { return .link(url) }
            let text = RecipeImportInput.cleanText(pastedText)
            return text.count >= RecipeImportInput.minTextLength ? .text(text) : nil
        }
    }

    private func runImport() {
        guard let request, !working else { return }
        working = true; error = nil; progress = nil
        operation = Task { @MainActor in
            defer { working = false; progress = nil }
            await subscriptions.refresh(regularLogCount: store.regularLogCount)
            guard let account = subscriptions.account else {
                error = subscriptions.message ?? "Could not check access. Please try again."
                return
            }
            guard account.active else {
                if subscriptions.offering != nil { paywallTrigger = .recipeImport; showPaywall = true }
                else {
                    error = subscriptions.message ?? "Subscriptions could not load. Please try again."
                    UsageStats.shared.error(.recipe, code: "paywall_unavailable", message: error ?? "")
                }
                return
            }
            do {
                let result: AIMealImportResult
                let kind: ScanKind
                let draftSource: String
                switch request {
                case .link(let url):
                    progress = "Reading recipe…"
                    result = try await AIBackend.shared.importMeal(from: url)
                    kind = .recipe; draftSource = "aiLink"
                case .text(let text):
                    progress = "Reading recipe…"
                    result = try await AIBackend.shared.importMeal(text: text)
                    kind = .recipeText; draftSource = "aiRecipeText"
                case .pages(let pages):
                    let count = pages.count
                    progress = count > 1 ? "Uploading page 1 of \(count)…" : "Uploading photo…"
                    result = try await AIBackend.shared.importMeal(pages: pages.map(\.data), regularLogCount: store.regularLogCount) { uploaded in
                        await MainActor.run { progress = uploaded < count ? "Uploading page \(uploaded + 1) of \(count)…" : "Reading recipe…" }
                    }
                    kind = .recipePhoto; draftSource = "aiRecipePhoto"
                }
                try Task.checkCancellation()
                UsageStats.shared.scan(kind)
                let drafts = result.drafts(at: Date(), source: draftSource)
                guard !drafts.isEmpty else {
                    error = result.notes.isEmpty ? "No recipe found. Try another." : result.notes
                    UsageStats.shared.error(.recipe, code: "no_foods", message: "No recipe items were found.")
                    return
                }
                imported(ImportedRecipe(name: result.mealName, items: drafts, servings: result.servingCount))
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                UsageStats.shared.error(.recipe, error)
                if let service = error as? AIServiceError,
                   service.code == "subscription_required", subscriptions.offering != nil {
                    paywallTrigger = .recipeImport
                    showPaywall = true
                }
            }
        }
    }

    private func closePaywall() {
        showPaywall = false
        guard retryAfterPurchase else {
            // Declining the up-front paywall leaves nothing usable here, so close the import too.
            if gatedOnOpen { dismiss() }
            return
        }
        retryAfterPurchase = false
        gatedOnOpen = false
        guard request != nil else { return }
        Task { @MainActor in
            await Task.yield()
            runImport()
        }
    }
}

/// The system camera for snapping a recipe page; each shot adds one page.
private struct RecipeCamera: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: RecipeCamera
        init(_ parent: RecipeCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.captured(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
