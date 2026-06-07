//
//  TVGestureHelpView.swift
//  KSPlayer
//
//  tvOS swipe/press receiver (RE addition). Subclasses UIControl (not UIView)
//  per binary metadata. Both action closures pass a
//  UISwipeGestureRecognizer.Direction so swipe and press dispatch share a
//  uniform callback signature, matching binary field shape.
//
//  Binary metadata accessor: $s8KSPlayer17TVGestureHelpViewCMa @ 0x1014a0e80
//  (re-verified 1.3.15; prior 0x101384aa8 was stale).
//  Class shape per types.json:
//    class KSPlayer.TVGestureHelpView : __C.UIControl
//      swipeAction: (__C.Direction) -> ()
//      pressAction: (__C.Direction) -> ()
//  Functions:
//    alloc_init                       @ 0x1014a0dbc  108B
//    alloc_init_fromTuple             @ 0x1014a0ea0  100B
//    init_withSwipeAndPressActions    @ 0x1014a1038  472B
//    handleSwipeGestureWithGesture:   @ 0x1014a12e4  304B
//    pressesBegan_impl                @ 0x1014a1414  328B
//    pressesBegan:withEvent: (ObjC)   @ 0x1014a15a0  288B
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

// tvOS-only: TVGestureHelpView consumes Siri-Remote presses (UIPress.PressType)
// in addition to swipes, which only exist on tvOS. The whole type is gated to
// tvOS so the press-handling path compiles only where UIPress arrow/select
// types are meaningful.
#if os(tvOS)
public class TVGestureHelpView: UIControl {
    public var swipeAction: (UISwipeGestureRecognizer.Direction) -> Void
    public var pressAction: (UISwipeGestureRecognizer.Direction) -> Void

    /// RE: 0x1014a1038 (TVGestureHelpView.init_withSwipeAndPressActions, 1.3.15)
    /// Designated init: stores both closures, then installs four
    /// UISwipeGestureRecognizers (one per direction) targeting handleSwipeGesture(_:).
    public init(
        swipeAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in },
        pressAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in }
    ) {
        self.swipeAction = swipeAction
        self.pressAction = pressAction
        super.init(frame: .zero)

        let directions: [UISwipeGestureRecognizer.Direction] = [.up, .down, .left, .right]
        for direction in directions {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
    }

    // init?(coder:) is the Swift NSCoding requirement — TVGestureHelpView is
    // never archived/unarchived, so it is unavailable. (This is NOT the binary's
    // alloc_init @ 0x1014a0dbc, which is the +alloc/init convenience thunk for
    // init_withSwipeAndPressActions; see the static convenience helpers below.)
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// RE: 0x1014a0dbc (TVGestureHelpView.alloc_init, 1.3.15)
    /// +alloc/init convenience thunk: allocates the instance (objc_allocWithZone),
    /// retains both closures, and forwards to the designated init. Reconstructed
    /// as an explicit factory so the binary's two-step alloc-then-init pattern is
    /// preserved as a separate call site (API Surface Preservation).
    public static func make(
        swipeAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in },
        pressAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in }
    ) -> TVGestureHelpView {
        TVGestureHelpView(swipeAction: swipeAction, pressAction: pressAction)
    }

    /// RE: 0x1014a0ea0 (TVGestureHelpView.alloc_init_fromTuple, 1.3.15)
    /// Tuple-argument allocation bridge: the binary loads the (swipeAction,
    /// pressAction) closure pair from a 4-word tuple in x20 (each closure is a
    /// {fnPtr, context} pair), retains both, allocates, and forwards to the
    /// designated init. This is the compiler-emitted entry used when the call
    /// site passes the two closures as a single tuple value (e.g. from the
    /// GestureView wrapper); it is otherwise identical to alloc_init. Exposed as
    /// a tuple-taking convenience so the distinct binary entry point has a Swift
    /// counterpart rather than being silently folded into `make`.
    public static func make(
        actions: (
            swipeAction: (UISwipeGestureRecognizer.Direction) -> Void,
            pressAction: (UISwipeGestureRecognizer.Direction) -> Void
        )
    ) -> TVGestureHelpView {
        TVGestureHelpView(swipeAction: actions.swipeAction, pressAction: actions.pressAction)
    }

    /// RE: 0x1014a12e4 (TVGestureHelpView.handleSwipeGestureWithGesture:, 1.3.15)
    /// ObjC swipe-recognizer target → forwards the recognizer's direction to swipeAction.
    @objc private func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        swipeAction(gesture.direction)
    }

    /// RE: 0x1014a15a0 (TVGestureHelpView.pressesBegan:withEvent:, 1.3.15)
    /// ObjC-selector bridge entry point. Asserts MainActor execution
    /// (binary: _swift_task_reportUnexpectedExecutor("KSPlayer/GestureView.swift",
    /// line 26)), bridges the NSSet<UIPress> from ObjC, and forwards to
    /// pressesBegan_impl. Kept distinct from the impl per the binary's two-step
    /// bridge/impl split (API Surface Preservation).
    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        assert(Thread.isMainThread, "TVGestureHelpView.pressesBegan must run on the main actor")
        pressesBeganImpl(presses, with: event)
    }

    /// RE: 0x1014a1414 (TVGestureHelpView.pressesBegan_impl, 1.3.15)
    /// Reads UIPress.type (raw value) from the first press and dispatches:
    /// type ∈ {0,1,2,3} — upArrow/downArrow/leftArrow/rightArrow — invoke the
    /// stored pressAction closure with the matching Direction. For ALL OTHER
    /// types (including .select = 4) the press is NOT handled locally; the impl
    /// bridges the set back and forwards to super via objc_msgSendSuper2
    /// (Swift: super.pressesBegan). Select therefore falls through to UIControl,
    /// it does NOT trigger pressAction.
    private func pressesBeganImpl(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch press.type {
        case .upArrow:    pressAction(.up)      // type 0
        case .downArrow:  pressAction(.down)    // type 1
        case .leftArrow:  pressAction(.left)    // type 2
        case .rightArrow: pressAction(.right)   // type 3
        default:          super.pressesBegan(presses, with: event) // incl. .select (4)
        }
    }
}
#endif
#endif
