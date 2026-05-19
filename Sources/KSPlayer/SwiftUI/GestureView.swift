//
//  GestureView.swift
//  KSPlayer
//
//  Forward addition (RE): SwiftUI view wrapping gesture recognizers
//  for the video player overlay.
//
//  Binary: $s8KSPlayer11GestureViewV (VWT entries only)
//  RE source: Forward v1.3.15
//

import SwiftUI

public struct GestureView: View {
    public var onTap: (() -> Void)?
    public var onDoubleTap: (() -> Void)?
    public var onSwipe: ((SwipeDirection) -> Void)?
    public var onPan: ((CGSize) -> Void)?

    public enum SwipeDirection {
        case left, right, up, down
    }

    public init(onTap: (() -> Void)? = nil,
                onDoubleTap: (() -> Void)? = nil,
                onSwipe: ((SwipeDirection) -> Void)? = nil,
                onPan: ((CGSize) -> Void)? = nil) {
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
        self.onSwipe = onSwipe
        self.onPan = onPan
    }

    public var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleTap?()
            }
            .onTapGesture {
                onTap?()
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        if abs(horizontal) > abs(vertical) {
                            onSwipe?(horizontal > 0 ? .right : .left)
                        } else {
                            onSwipe?(vertical > 0 ? .down : .up)
                        }
                        onPan?(value.translation)
                    }
            )
    }
}
