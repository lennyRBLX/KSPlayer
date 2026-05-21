//
//  GestureView.swift
//  KSPlayer
//
//  Forward addition (RE): SwiftUI struct wrapping the tvOS swipe and press
//  receiver. Two closure-typed properties form the entire API surface — one
//  per gesture flavour, both passing a UIKit swipe direction.
//
//  Binary: $s8KSPlayer11GestureViewV (struct value witnesses + body)
//  Fields per types.json:
//    swipeAction: (__C.Direction) -> ()
//    pressAction: (__C.Direction) -> ()
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import SwiftUI
import UIKit

public struct GestureView: View {
    public var swipeAction: (UISwipeGestureRecognizer.Direction) -> Void
    public var pressAction: (UISwipeGestureRecognizer.Direction) -> Void

    public init(
        swipeAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in },
        pressAction: @escaping (UISwipeGestureRecognizer.Direction) -> Void = { _ in }
    ) {
        self.swipeAction = swipeAction
        self.pressAction = pressAction
    }

    public var body: some View {
        TVGestureHelpViewRepresentable(
            swipeAction: swipeAction,
            pressAction: pressAction
        )
    }
}

#if os(tvOS)
private struct TVGestureHelpViewRepresentable: UIViewRepresentable {
    let swipeAction: (UISwipeGestureRecognizer.Direction) -> Void
    let pressAction: (UISwipeGestureRecognizer.Direction) -> Void

    func makeUIView(context: Context) -> TVGestureHelpView {
        TVGestureHelpView(swipeAction: swipeAction, pressAction: pressAction)
    }

    func updateUIView(_ uiView: TVGestureHelpView, context: Context) {
        uiView.swipeAction = swipeAction
        uiView.pressAction = pressAction
    }
}
#else
private struct TVGestureHelpViewRepresentable: View {
    let swipeAction: (UISwipeGestureRecognizer.Direction) -> Void
    let pressAction: (UISwipeGestureRecognizer.Direction) -> Void
    var body: some View { Color.clear }
}
#endif
#endif
