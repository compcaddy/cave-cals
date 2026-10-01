import SwiftUI
import UIKit
#if DEBUG
import os
#endif

/// What a control means, so each kind of tap feels different.
enum HapticFeel: String {
    /// Ordinary buttons: open, close, edit, navigate.
    case tap
    /// Choosing among options: pills, segments, day and week arrows, chart columns.
    case selection
    /// Food logged or something saved.
    case success
    /// Destructive actions: delete, reset, discard.
    case warning
    /// The control's system UI already gives feedback, or it shouldn't buzz.
    case none
}

/// Cave Cals' haptics. Buttons play their feel through `HapticButtonStyle` (installed at the app root and wrapped
/// around every explicit button style); mark a control's meaning with `.hapticFeel(_:)`. Nothing plays when
/// Settings → Haptic feedback is off, and UIKit's generators also honor the iPhone's System Haptics switch.
@MainActor enum Haptics {
    /// Settings → "Haptic feedback" (on by default, this iPhone only).
    static let enabledKey = "hapticFeedback.v1"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static var rumble: Task<Void, Never>?
    #if DEBUG
    private static let logger = Logger(subsystem: "com.philstarkovich.cavecals", category: "haptics")
    #endif

    static func play(_ feel: HapticFeel) {
        guard feel != .none, isEnabled else { return }
        record(feel.rawValue)
        switch feel {
        case .tap: light.impactOccurred(intensity: 0.7)
        case .selection: selectionGenerator.selectionChanged()
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .none: break
        }
    }

    /// Feel the calories go in: ticks spaced by calories along the count-up's own curve, so they buzz while the
    /// digits race and slow as they settle, then one firm bump when the final number lands. A zero duration
    /// (Reduce Motion) plays only the bump; a falling total plays nothing.
    static func countUp(by calories: Double, curve: UnitCurve, duration: TimeInterval) {
        rumble?.cancel()
        guard calories >= 1, isEnabled else { return }
        record("countUp \(Int(calories))")
        let (ticks, landing) = countUpTimes(by: calories, curve: curve, duration: duration)
        rumble = Task { @MainActor in
            let start = ContinuousClock.now
            for (index, time) in ticks.enumerated() {
                try? await Task.sleep(until: start + .seconds(time), clock: .continuous)
                guard !Task.isCancelled else { return }
                light.impactOccurred(intensity: 0.8 - 0.45 * Double(index) / Double(max(ticks.count, 1)))
            }
            try? await Task.sleep(until: start + .seconds(landing), clock: .continuous)
            guard !Task.isCancelled else { return }
            rigid.impactOccurred(intensity: 0.9)
        }
    }

    /// Tick times (seconds) at even calorie steps, at least 35 ms apart so the Taptic Engine keeps up, and the
    /// landing time: when the rounded total first shows the final number.
    nonisolated static func countUpTimes(by calories: Double, curve: UnitCurve, duration: TimeInterval) -> (ticks: [Double], landing: Double) {
        let landing = curve.inverse.value(at: max(0, 1 - 0.5 / calories)) * duration
        let steps = min(max(Int(calories / 15), 6), 40)
        var ticks: [Double] = []
        for step in 1..<steps {
            let time = curve.inverse.value(at: Double(step) / Double(steps)) * duration
            guard time < landing - 0.035 else { break }
            if time - (ticks.last ?? -1) >= 0.035 { ticks.append(time) }
        }
        return (ticks, landing)
    }

    private static func record(_ event: String) {
        #if DEBUG
        logger.info("haptic \(event, privacy: .public)")
        #endif
    }
}

private struct HapticFeelKey: EnvironmentKey {
    static let defaultValue = HapticFeel.tap
}

extension EnvironmentValues {
    var hapticFeel: HapticFeel {
        get { self[HapticFeelKey.self] }
        set { self[HapticFeelKey.self] = newValue }
    }
}

/// Plays the button's feel when it's activated (tap, VoiceOver, or keyboard), then draws the style it would have
/// had. Destructive-role buttons always feel like a warning.
struct HapticButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    var base: Base
    @Environment(\.hapticFeel) private var feel

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            Haptics.play(configuration.role == .destructive ? .warning : feel)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(base)
    }
}

/// Forms and Lists reset the button style for their rows (toolbars do too), so the app-root haptic style never
/// reaches row buttons. These restore it inside; use them in place of `Form` and `List`.
struct HapticForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { Form { content.hapticButtonStyle(.automatic) } }
}

struct HapticList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { List { content.hapticButtonStyle(.automatic) } }
}

extension View {
    /// Use instead of `.buttonStyle(_:)` so the button keeps its haptic.
    func hapticButtonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        buttonStyle(HapticButtonStyle(base: style))
    }
    /// What the buttons inside feel like when tapped.
    func hapticFeel(_ feel: HapticFeel) -> some View {
        environment(\.hapticFeel, feel)
    }
    /// `NavigationLink` rows don't use button styles, and a tap gesture on them blocks navigation, so the
    /// pushed screen taps as it appears. Put this on the link's destination.
    func hapticOnPush() -> some View {
        onAppear { Haptics.play(.tap) }
    }
    /// A selection tick when a picker, segment, or chart selection changes.
    func hapticSelection<V: Equatable>(on value: V) -> some View {
        onChange(of: value) { Haptics.play(.selection) }
    }
}
