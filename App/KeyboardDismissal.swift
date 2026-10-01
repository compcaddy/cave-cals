import SwiftUI
import UIKit

// Cave Cals has no Done bar over the keyboard. On a screen marked with `tapOutsideClosesKeyboard()`, a tap
// anywhere that isn't a text field closes the keyboard, and whatever was tapped (a button, switch, or
// picker) still acts on that same tap. A field's box, row, or pop-up list marked with `keyboardInputArea`
// counts as part of the field: tapping it keeps the keyboard up, and can move focus into the field.
//
// This is a UIKit tap recognizer on the screen's (or sheet's) root view rather than a SwiftUI gesture:
// it never takes a tap away from another control, and Forms and sheets need no coordinate bookkeeping.

extension View {
    /// Put on a screen or sheet with text fields.
    func tapOutsideClosesKeyboard() -> some View { background(KeyboardDismissAnchor()) }
    /// Marks a field's box, row, or pop-up list. A tap inside keeps the keyboard up; `focus`, if given,
    /// moves focus into the field (use it for boxes whose padding or label should open the field).
    func keyboardInputArea(focus: (() -> Void)? = nil) -> some View { background(KeyboardInputArea(focus: focus)) }
}

private struct KeyboardDismissAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ view: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        private weak var scope: UIView?
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scope { KeyboardDismissTap.release(from: scope); self.scope = nil }
            guard window != nil, let root = presentationRoot else { return }
            KeyboardDismissTap.retain(on: root)
            scope = root
        }
        /// The root view of the screen or sheet this is in, navigation bar included.
        private var presentationRoot: UIView? {
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard var controller = responder as? UIViewController else { return window }
            while let parent = controller.parent { controller = parent }
            return controller.view
        }
    }
}

/// One per screen or sheet, shared by every anchor on it.
private final class KeyboardDismissTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    private var users = 0

    static func retain(on view: UIView) {
        let tap = existing(on: view) ?? {
            let tap = KeyboardDismissTap()
            view.addGestureRecognizer(tap)
            return tap
        }()
        tap.users += 1
    }

    static func release(from view: UIView) {
        guard let tap = existing(on: view) else { return }
        tap.users -= 1
        if tap.users <= 0 { view.removeGestureRecognizer(tap) }
    }

    private static func existing(on view: UIView) -> KeyboardDismissTap? {
        view.gestureRecognizers?.lazy.compactMap { $0 as? KeyboardDismissTap }.first
    }

    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(tapped))
        // Never take the tap from what's under it, or hold it back.
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func tapped() {
        guard let scope = view else { return }
        if let area = KeyboardInputArea.AreaView.area(at: location(in: nil), in: scope) {
            area.focus?()
            return
        }
        // Close the field that was being typed in, once the tapped control has finished with the tap:
        // closing mid-tap resets some controls (a segmented picker wouldn't switch). A field the tapped
        // control focuses in the meantime stays open.
        guard let editing = UIResponder.current, editing is UITextField || editing is UITextView,
              (editing as? UIView)?.isDescendant(of: scope) == true else { return }
        DispatchQueue.main.async { if editing.isFirstResponder { editing.resignFirstResponder() } }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// A tap on a text field is the field's own (placing the cursor, moving focus there).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?
    /// Whatever has keyboard focus (actions sent to no target go to the first responder).
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(reportAsCurrent), to: nil, from: nil, for: nil)
        return found
    }
    @objc private func reportAsCurrent() { UIResponder.found = self }
}

private struct KeyboardInputArea: UIViewRepresentable {
    let focus: (() -> Void)?
    func makeUIView(context: Context) -> AreaView { AreaView() }
    func updateUIView(_ view: AreaView, context: Context) { view.focus = focus }

    final class AreaView: UIView {
        var focus: (() -> Void)?
        private static let all = NSHashTable<AreaView>.weakObjects()

        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { Self.all.remove(self) } else { Self.all.add(self) }
        }

        /// The area under a tap (in window coordinates) on this screen or sheet.
        static func area(at point: CGPoint, in scope: UIView) -> AreaView? {
            all.allObjects.first { $0.window != nil && $0.isDescendant(of: scope) && $0.visibleFrame.contains(point) }
        }

        /// Only the part that's showing counts: not the part scrolled under a navigation bar, a pinned
        /// footer, or the keyboard, where a tap belongs to what's on top.
        private var visibleFrame: CGRect {
            let frame = convert(bounds, to: nil)
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { return frame }
            return frame.intersection(scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil))
        }
    }
}
