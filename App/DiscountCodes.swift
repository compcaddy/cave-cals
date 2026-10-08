import SwiftUI

/// Where someone found Cave Cals, asked once after setup (`DiscoverySourceView`). Raw values go to usage stats.
enum DiscoverySource: String, CaseIterable, Identifiable {
    case trainer, social, friend, appStore, google, ai, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trainer: "Trainer or coach"
        case .social: "Social media"
        case .friend: "Friend or family"
        case .appStore: "App Store"
        case .google: "Google search"
        case .ai: "AI"
        case .other: "Other"
        }
    }
    /// Shown in light gray beside the title.
    var detail: String? {
        switch self {
        case .social: "(TikTok, IG, YT, etc.)"
        case .ai: "(ChatGPT, Claude)"
        default: nil
        }
    }
    /// VoiceOver reads the names in full.
    var spokenDetail: String? {
        switch self {
        case .social: "TikTok, Instagram, YouTube, and others"
        case .ai: "ChatGPT, Claude"
        default: nil
        }
    }
    /// Trainers and creators hand out codes, so picking them opens the code box.
    var expectsCode: Bool { self == .trainer || self == .social }
}

/// A trainer's or creator's code the backend accepted. It stays on this iPhone for good (in the Keychain, so a
/// reinstall keeps it), and every paywall shows its RevenueCat offering. Apple sets the prices; a code only picks them.
struct AppliedDiscount: Codable, Equatable {
    let code: String
    /// Who shared it ("Sarah").
    let name: String
    /// The RevenueCat offering with the code's prices.
    let offering: String
    /// "Half price on Cave Cals+", from the backend.
    let deal: String
}

/// Checking and keeping discount codes. Codes are managed on the backend's /admin/codes page; each one has a
/// page at CaveCals.com/<code> whose button copies it, so it can be pasted here.
enum DiscountCodes {
    static let minimumLength = 2
    static let notFound = AIServiceError(code: "code_not_found", message: "That code doesn’t work. Check the spelling and try again.")

    /// The backend's rule: capitals, spaces, and punctuation don't matter, so "sarah-30 " is SARAH30.
    static func normalize(_ text: String) -> String {
        var scalars = text.precomposedStringWithCompatibilityMapping.uppercased().unicodeScalars
        scalars.removeAll { !(("A"..."Z").contains($0) || ("0"..."9").contains($0)) }
        return String(String(scalars).prefix(30))
    }

    private static let key = "discount.code.v1"
    /// UI tests, screenshots, and unit tests keep codes in memory, so they never touch the real Keychain.
    @MainActor private static var memory: AppliedDiscount?
    private static var usesMemory: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") || arguments.contains("--screenshots")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    /// The code applied on this iPhone, if any. Read it through `AISubscriptions.discount` in views.
    @MainActor static var applied: AppliedDiscount? {
        get {
            if usesMemory { return memory }
            return KeychainValue.read(key).flatMap { try? JSONDecoder().decode(AppliedDiscount.self, from: Data($0.utf8)) }
        }
        set {
            if usesMemory { memory = newValue; return }
            let json = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
            try? KeychainValue.save(json, key: key)
        }
    }

    /// Asks the backend whether a code works. Unsigned, like food search: codes are public and setup runs before
    /// device verification. `count` is false for the developer preview, so its checks aren't counted.
    static func check(_ text: String, count: Bool = true) async throws -> AppliedDiscount {
        let code = normalize(text)
        #if DEBUG
        // UI tests never reach the backend: CAVETEST works and anything else doesn't.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            try await Task.sleep(for: .milliseconds(250))
            guard code == "CAVETEST" else { throw notFound }
            return AppliedDiscount(code: code, name: "Test Creator", offering: "discount", deal: "Half price on Cave Cals+")
        }
        #endif
        guard let base = AIConfiguration.baseURL else {
            throw AIServiceError(code: "not_configured", message: "Codes aren’t available right now. Please try again later.")
        }
        var request = URLRequest(url: base.appendingPathComponent("api/v1/discount/check"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "count": count])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { struct Detail: Decodable { let code: String; let message: String }; let error: Detail }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            if failure?.error.code == notFound.code { throw notFound }
            throw AIServiceError(code: failure?.error.code ?? "server", message: failure?.error.message ?? "The service is unavailable. Please try again.")
        }
        return try JSONDecoder().decode(AppliedDiscount.self, from: data)
    }
}

/// The code box's state, shared by the question after setup and the paywall's "Have a code?" sheet.
@MainActor @Observable final class DiscountCodeEntry {
    var code = ""
    private(set) var checking = false
    var message: String?
    var canApply: Bool { !checking && DiscountCodes.normalize(code).count >= DiscountCodes.minimumLength }

    /// Checks the typed code and, unless this is the developer preview, keeps it for every paywall.
    /// `place` (setup or paywall) is for usage stats.
    func apply(from place: String, preview: Bool, subscriptions: AISubscriptions?) async -> AppliedDiscount? {
        guard canApply else { return nil }
        let typed = DiscountCodes.normalize(code)
        checking = true; message = nil
        defer { checking = false }
        // The spinner shows for at least a moment, even when the answer comes back right away.
        let shown = Task { try? await Task.sleep(for: .milliseconds(600)) }
        do {
            let discount: AppliedDiscount
            do { discount = try await DiscountCodes.check(typed, count: !preview) } catch { await shown.value; throw error }
            await shown.value
            if !preview {
                if let subscriptions { subscriptions.apply(discount) } else { DiscountCodes.applied = discount }
                UsageStats.shared.event("discount.code", ["result": "applied", "code": discount.code, "from": place])
            }
            Haptics.play(.success)
            code = ""
            return discount
        } catch {
            let notFound = (error as? AIServiceError)?.code == DiscountCodes.notFound.code
            message = notFound ? DiscountCodes.notFound.message : "Couldn’t check the code. Check your connection and try again."
            if !preview {
                // Codes that don't work aren't sent: they're typed text.
                UsageStats.shared.event("discount.code", ["result": notFound ? "notFound" : "error", "from": place])
                if !notFound { UsageStats.shared.error(.discountCode, error) }
            }
            return nil
        }
    }
}

/// Type a code (or paste it with the field's own menu), then Apply. There's no Paste button (removed October 7,
/// 2026), so the app never touches the clipboard.
struct DiscountCodeBox: View {
    @Bindable var entry: DiscountCodeEntry
    var focus: FocusState<Bool>.Binding
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discount code").font(.cave(.subheadline))
            HStack(spacing: 8) {
                // Keep the edit intact while typing; checking the code normalizes it.
                // Rewriting the field from onChange can overwrite later keystrokes.
                TextField("Code", text: $entry.code)
                    .font(.cave(.title2))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.go)
                    .onSubmit { if entry.canApply { apply() } }
                    .focused(focus)
                    .accessibilityLabel("Discount code")
                    .accessibilityIdentifier("discountCode")
                if !entry.code.isEmpty {
                    Button { entry.code = ""; entry.message = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red)
                            .frame(width: 36, height: 44).contentShape(Rectangle())
                    }
                    .hapticButtonStyle(.plain)
                    .keyboardInputArea()
                    .accessibilityLabel("Clear code")
                    .accessibilityIdentifier("clearDiscountCode")
                }
                Button(action: apply) {
                    ZStack {
                        Text("Apply").opacity(entry.checking ? 0 : 1)
                        if entry.checking { ProgressView().tint(.white) }
                    }
                }
                .hapticButtonStyle(.borderedProminent)
                // Stays orange while checking so the white spinner shows; a second tap does nothing (`canApply`).
                .disabled(!entry.canApply && !entry.checking)
                .accessibilityLabel(entry.checking ? "Checking code" : "Apply")
                .accessibilityIdentifier("applyDiscountCode")
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            // Taps in the box (the ×, Apply, its padding) keep the keyboard; the padding opens the field.
            .keyboardInputArea { focus.wrappedValue = true }
            if let message = entry.message {
                Text(message).font(.cave(.footnote)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("discountCodeMessage")
            }
        }
        .onChange(of: entry.code) { _, new in
            entry.message = nil
        }
    }
}

/// Shown once a code works: what it gets and, once Cave Cals+ has loaded, its prices against the regular ones.
struct AppliedDiscountCard: View {
    let discount: AppliedDiscount
    var prices: [String] = []
    var remove: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CaveIcon(.check, size: 24).foregroundStyle(Color.caveOrange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Code \(discount.code) worked!").font(.cave(.headline))
                Text("Special discount on Cave Cals+").font(.cave(.subheadline))
                ForEach(prices, id: \.self) { Text($0).font(.cave(.subheadline)).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((["Code \(discount.code) worked", "Special discount on Cave Cals+"] + prices).joined(separator: ". "))
            Spacer(minLength: 0)
            if let remove {
                Button("Remove", action: remove)
                    .font(.cave(.footnote))
                    .foregroundStyle(Color.caveOrange)
                    .frame(minHeight: 44)
                    .hapticButtonStyle(.plain)
                    .accessibilityLabel("Remove code")
                    .accessibilityIdentifier("removeDiscountCode")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.caveOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("discountApplied")
    }
}

/// Asked once after setup, before the Cave Cals+ offer: where someone found Cave Cals, with a box for a trainer's
/// or creator's discount code. The answer goes to anonymous usage stats; an applied code is kept for every paywall.
struct DiscoverySourceView: View {
    /// Developer → Preview onboarding: codes are checked without counting, and nothing is saved or recorded.
    var isPreview = false
    /// Cave Cals+ loads while this shows; it keeps the code and supplies its prices once ready.
    var subscriptions: AISubscriptions?
    let onFinish: () -> Void

    /// Skipped in UI tests, so setup tests go straight to the offer, unless a test adds `--discovery-question`.
    static var shouldAsk: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshots") { return false }
        return !arguments.contains("--uitesting") || arguments.contains("--discovery-question")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source: DiscoverySource?
    @State private var other = ""
    @State private var wantsCode = false
    @State private var entry = DiscountCodeEntry()
    @State private var discount: AppliedDiscount?
    /// Each code that works drops confetti.
    @State private var confetti = 0
    @State private var finished = false
    @FocusState private var codeFocused: Bool
    @FocusState private var otherFocused: Bool

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    /// The box opens under Trainer or coach and Social media, or below the list after "Have a code?".
    private var codeInline: Bool { discount == nil && source?.expectsCode == true }
    private var codeBelow: Bool { discount == nil && wantsCode && !codeInline }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    (Text(Image(systemName: "magnifyingglass")).foregroundStyle(Color.caveOrange) + Text(" Where did you hear about Cave Cals?"))
                        .font(.cave(.largeTitle))
                        // Never a third line: large text shrinks instead.
                        .lineLimit(2).minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Where did you hear about Cave Cals?")
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 10) {
                        ForEach(DiscoverySource.allCases) { option in
                            row(option)
                            if source == option { extras(for: option) }
                        }
                    }
                    if codeBelow {
                        codeBox
                    } else if discount == nil && !codeInline {
                        Button("Have a code?") { withAnimation(animation) { wantsCode = true } }
                            .font(.cave(.subheadline))
                            .foregroundStyle(Color.caveOrange)
                            .frame(minHeight: 44)
                            .hapticButtonStyle(.plain)
                            .accessibilityIdentifier("discoveryHaveCode")
                    }
                    if let discount {
                        AppliedDiscountCard(discount: discount, prices: subscriptions?.priceComparison(for: discount.offering) ?? [],
                                            remove: { remove() })
                            .id("applied")
                    }
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: wantsCode) { _, wants in
                guard wants else { return }
                scroll(proxy, to: "code")
                codeFocused = true
            }
            .onChange(of: source) { _, new in if new == .other { scroll(proxy, to: "other") } }
            .onChange(of: discount) { _, new in if new != nil { scroll(proxy, to: "applied") } }
            // The keyboard and the Continue panel cover the lower half, so a box being typed in (and its message)
            // moves up into view once the keyboard is out.
            .onChange(of: codeFocused) { _, focused in if focused { scroll(proxy, to: "code", after: 400) } }
            .onChange(of: otherFocused) { _, focused in if focused { scroll(proxy, to: "other", after: 400) } }
            .onChange(of: entry.message) { _, message in if message != nil { scroll(proxy, to: "code") } }
        }
        .caveScreenBackground()
        // Rows scroll up under the clock; a strip of the page color keeps them clear of it.
        .overlay(alignment: .top) { Color.caveBackground.ignoresSafeArea(edges: .top).frame(height: 0) }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay { ConfettiBurst(trigger: confetti) }
        // No Done bar over the keyboard: a tap outside the boxes closes it.
        .tapOutsideClosesKeyboard()
        .onAppear {
            // A code kept from before (a reinstall keeps it) shows as applied.
            if !isPreview && discount == nil { discount = subscriptions?.discount ?? DiscountCodes.applied }
        }
    }

    private func row(_ option: DiscoverySource) -> some View {
        let selected = source == option
        return Button { withAnimation(animation) { source = option } } label: {
            HStack(spacing: 14) {
                // The examples sit beside the title, in light gray.
                (Text(option.title).foregroundStyle(Color.primary)
                    + Text(option.detail.map { " " + $0 } ?? "").font(.cave(.subheadline)).foregroundStyle(Color.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.caveOrange : .secondary)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? Color.caveOrange.opacity(0.1) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .hapticButtonStyle(.plain).hapticFeel(.selection)
        .accessibilityLabel(option.spokenDetail.map { "\(option.title), \($0)" } ?? option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("discovery-\(option.rawValue)")
    }

    @ViewBuilder private func extras(for option: DiscoverySource) -> some View {
        if option.expectsCode && discount == nil { codeBox }
        if option == .other {
            TextField("Where? (optional)", text: $other)
                .font(.cave(.body))
                .focused($otherFocused)
                .submitLabel(.done)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .keyboardInputArea { otherFocused = true }
                .accessibilityLabel("Where did you hear about Cave Cals?")
                .accessibilityIdentifier("discoveryOther")
                .id("other")
                .onChange(of: other) { _, new in if new.count > 60 { other = String(new.prefix(60)) } }
        }
    }

    private var codeBox: some View {
        DiscountCodeBox(entry: entry, focus: $codeFocused) { Task { await apply() } }.id("code")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button { Task { await continueTapped() } } label: {
                Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .hapticButtonStyle(.borderedProminent)
            // Required (October 7, 2026): no Skip. Other works without typing anything.
            .disabled(source == nil || entry.checking)
            .accessibilityIdentifier("discoveryContinue")
        }
        .font(.cave(.body))
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        // The panel runs down behind the keyboard, so no page content shows between them.
        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .bottom) }
    }

    private func apply() async {
        guard let applied = await entry.apply(from: "setup", preview: isPreview, subscriptions: subscriptions) else { return }
        codeFocused = false
        withAnimation(animation) { discount = applied }
        confetti += 1
    }

    private func remove() {
        if !isPreview {
            if let subscriptions { subscriptions.apply(nil) } else { DiscountCodes.applied = nil }
        }
        withAnimation(animation) { discount = nil }
    }

    /// A typed code that hasn't been applied is applied first. If it doesn't work, the question stays so the
    /// code can be fixed or cleared with the red ×.
    private func continueTapped() async {
        guard let source else { return }
        if discount == nil && (codeInline || codeBelow) && entry.canApply {
            await apply()
            guard discount != nil else { return }
        }
        complete(source)
    }

    private func complete(_ source: DiscoverySource) {
        guard !finished else { return }
        finished = true
        if !isPreview {
            var props = ["source": source.rawValue]
            let text = other.trimmingCharacters(in: .whitespacesAndNewlines)
            if source == .other && !text.isEmpty { props["other"] = String(text.prefix(60)) }
            UsageStats.shared.event("onboarding.source", props)
        }
        onFinish()
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String, after delay: Int = 250) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            withAnimation(animation) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

/// "Have a code?" under a Cave Cals+ paywall, for people who didn't have a code after setup or got one later.
struct DiscountCodeSheet: View {
    let subscriptions: AISubscriptions
    /// Called just before the sheet closes on a code that works (the paywall drops confetti).
    var onApplied: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var entry = DiscountCodeEntry()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Got a code from a trainer or creator? Type or paste it here.")
                    .font(.cave(.subheadline)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DiscountCodeBox(entry: entry, focus: $focused) { Task { await apply() } }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .caveScreenBackground()
            .tapOutsideClosesKeyboard()
            .navigationTitle("Have a code?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.hapticButtonStyle(.automatic).accessibilityIdentifier("cancelDiscountCode")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            focused = true
        }
    }

    private func apply() async {
        guard await entry.apply(from: "paywall", preview: false, subscriptions: subscriptions) != nil else { return }
        onApplied()
        dismiss()
    }
}

/// Confetti falling down the whole screen for a few seconds, when a discount code works. Decorative and
/// untappable; Reduce Motion skips it.
struct ConfettiBurst: View {
    /// Each change drops a new burst.
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    private struct Piece {
        var x = CGFloat.random(in: 0...1)
        var delay = Double.random(in: 0...0.7)
        /// Screen heights per second.
        var speed = CGFloat.random(in: 0.38...0.62)
        var drift = CGFloat.random(in: 8...28)
        var wobble = Double.random(in: 2...5)
        var phase = Double.random(in: 0...(2 * .pi))
        var spin = Double.random(in: -6...6)
        var flip = Double.random(in: 4...10)
        var size = CGFloat.random(in: 7...12)
        var round = Bool.random() && Bool.random()
        var color = ConfettiBurst.colors.randomElement() ?? .orange
    }
    fileprivate static let colors: [Color] = [
        .caveOrange, Color(red: 0.98, green: 0.76, blue: 0.22), Color(red: 0.93, green: 0.36, blue: 0.29),
        Color(red: 0.55, green: 0.32, blue: 0.16), Color(red: 0.95, green: 0.86, blue: 0.68), Color(red: 0.42, green: 0.66, blue: 0.45),
    ]

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let time = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let elapsed = time - piece.delay
                    guard elapsed > 0 else { continue }
                    let y = -20 + CGFloat(elapsed) * piece.speed * size.height
                    guard y < size.height + 20 else { continue }
                    var layer = context
                    layer.translateBy(x: piece.x * size.width + sin(elapsed * piece.wobble + piece.phase) * piece.drift, y: y)
                    layer.rotate(by: .radians(elapsed * piece.spin))
                    // Squashing one side as it turns reads as a flutter.
                    layer.scaleBy(x: max(0.15, abs(cos(elapsed * piece.flip))), y: 1)
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size * 0.3, width: piece.size, height: piece.size * 0.6)
                    layer.fill(piece.round ? Path(ellipseIn: rect.insetBy(dx: piece.size * 0.2, dy: -piece.size * 0.1)) : Path(rect),
                               with: .color(piece.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let began = Date.now
            pieces = (0..<140).map { _ in Piece() }
            start = began
            Task { @MainActor in
                // Everything has fallen past the bottom by then.
                try? await Task.sleep(for: .seconds(4))
                if start == began { start = nil; pieces = [] }
            }
        }
    }
}
