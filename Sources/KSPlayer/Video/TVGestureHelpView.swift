//
//  TVGestureHelpView.swift
//  KSPlayer
//
//  Forward addition (RE): tvOS swipe/press receiver. Subclasses UIControl
//  (not UIView) per binary metadata. Both action closures pass a
//  UISwipeGestureRecognizer.Direction so swipe and press dispatch share a
//  uniform callback signature, matching binary field shape.
//
//  Binary: $s8KSPlayer17TVGestureHelpViewCMa @ 0x101384aa8
//  Class shape per types.json:
//    class KSPlayer.TVGestureHelpView : __C.UIControl
//      swipeAction: (__C.Direction) -> ()
//      pressAction: (__C.Direction) -> ()
//  Functions:
//    alloc_init                       @ 0x1014a0dbc  108B
//    alloc_init_fromTuple             @ 0x1014a0ea0  100B
//    init_withSwipeAndPressActions    @ 0x1014a1038  472B
//    pressesBegan_impl                @ 0x1014a1414  328B
//    handleSwipeGestureWithGesture:   @ 0x1014a12e4  304B
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

#if os(tvOS)
public class TVGestureHelpView: UIControl {
    public var swipeAction: (UISwipeGestureRecognizer.Direction) -> Void
    public var pressAction: (UISwipeGestureRecognizer.Direction) -> Void

    // RE: TVGestureHelpView_init_withSwipeAndPressActions @ 0x1014a1038
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

    // RE: TVGestureHelpView_alloc_init @ 0x1014a0dbc
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // RE: handleSwipeGestureWithGesture: @ 0x1014a12e4
    @objc private func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        swipeAction(gesture.direction)
    }

    // RE: TVGestureHelpView_pressesBegan_impl @ 0x1014a1414
    // Press routing maps tvOS UIPress.PressType onto the same Direction enum
    // so swipe and press callers can share a single dispatcher.
    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch press.type {
        case .upArrow:    pressAction(.up)
        case .downArrow:  pressAction(.down)
        case .leftArrow:  pressAction(.left)
        case .rightArrow: pressAction(.right)
        case .select:     pressAction(.up) // select treated as confirmation; route to .up
        default:          super.pressesBegan(presses, with: event)
        }
    }
}
#endif
#endif
