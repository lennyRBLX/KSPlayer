//
//  TVGestureHelpView.swift
//  KSPlayer
//
//  Forward addition (RE): tvOS gesture help overlay that captures
//  swipe and press gestures, dispatching to configurable actions.
//
//  Binary: _TtC8KSPlayer17TVGestureHelpView (4 functions)
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

#if os(tvOS)
public class TVGestureHelpView: UIView {
    public var swipeAction: ((UISwipeGestureRecognizer.Direction) -> Void)?
    public var pressAction: (() -> Void)?

    // RE: TVGestureHelpView_init_withSwipeAndPressActions @ 0x1014a1038
    public init(swipeAction: ((UISwipeGestureRecognizer.Direction) -> Void)? = nil,
                pressAction: (() -> Void)? = nil) {
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

    @objc private func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        swipeAction?(gesture.direction)
    }

    // RE: TVGestureHelpView_pressesBegan_impl @ 0x1014a1414
    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        if press.type == .select {
            pressAction?()
        } else {
            super.pressesBegan(presses, with: event)
        }
    }
}
#endif
#endif
