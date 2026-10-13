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
}

/// Asked once after setup, before the Cave Cals+ offer: where someone found Cave Cals. The answer goes to anonymous
/// usage stats. The discount code box was removed October 13, 2026: App Review rejected in-app codes (guideline 3.1.1).
struct DiscoverySourceView: View {
    /// Developer → Preview onboarding: nothing is recorded.
    var isPreview = false
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
    @State private var finished = false
    @FocusState private var otherFocused: Bool

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }

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
                            if source == option && option == .other { otherField }
                        }
                    }
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: source) { _, new in if new == .other { scroll(proxy, to: "other") } }
            // The keyboard and the Continue panel cover the lower half, so the box moves up into view once the
            // keyboard is out.
            .onChange(of: otherFocused) { _, focused in if focused { scroll(proxy, to: "other", after: 400) } }
        }
        .caveScreenBackground()
        // Rows scroll up under the clock; a strip of the page color keeps them clear of it.
        .overlay(alignment: .top) { Color.caveBackground.ignoresSafeArea(edges: .top).frame(height: 0) }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        // No Done bar over the keyboard: a tap outside the box closes it.
        .tapOutsideClosesKeyboard()
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

    private var otherField: some View {
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

    private var footer: some View {
        VStack(spacing: 4) {
            Button { complete() } label: {
                Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .hapticButtonStyle(.borderedProminent)
            // Required (October 7, 2026): no Skip. Other works without typing anything.
            .disabled(source == nil)
            .accessibilityIdentifier("discoveryContinue")
        }
        .font(.cave(.body))
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        // The panel runs down behind the keyboard, so no page content shows between them.
        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .bottom) }
    }

    private func complete() {
        guard let source, !finished else { return }
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
