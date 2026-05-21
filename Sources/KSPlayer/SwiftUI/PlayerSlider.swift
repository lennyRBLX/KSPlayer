//
//  PlayerSlider.swift
//  KSPlayer
//
//  Forward addition (RE): SwiftUI seek-bar slider. Field shape is taken
//  verbatim from the binary's reflection metadata: a Float-valued binding
//  with an explicit `bufferValue` rail, a `bounds` ClosedRange named after
//  the binary field (not `range`), a non-optional `onEditingChanged`
//  closure, and three SwiftUI property-wrapper-backed state fields for
//  in-flight drag, focus, and hover.
//
//  Binary: $s8KSPlayer12PlayerSliderV
//  Struct shape per types.json:
//    value:             SwiftUI.Binding<Swift.Float>
//    bufferValue:       Swift.Float
//    bounds:            Swift.ClosedRange<Swift.Float>
//    onEditingChanged:  (Swift.Bool) -> ()
//    _beginDrag:        SwiftUI.State<Swift.Bool>
//    _isFocused:        SwiftUI.FocusState<Swift.Bool>
//    _hoverValue:       SwiftUI.State<Swift.Float?>
//  RE source: Forward v1.3.15
//

import SwiftUI

public struct PlayerSlider: View {
    @Binding public var value: Float
    public var bufferValue: Float
    public var bounds: ClosedRange<Float>
    public var onEditingChanged: (Bool) -> Void

    @State private var beginDrag: Bool = false
    @FocusState private var isFocused: Bool
    @State private var hoverValue: Float? = nil

    public init(
        value: Binding<Float>,
        bufferValue: Float = 0,
        bounds: ClosedRange<Float> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.bufferValue = bufferValue
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            buildTrackBody(in: geometry)
        }
        .frame(height: 14)
        .focusable(true)
        .focused($isFocused)
    }

    @ViewBuilder
    private func buildTrackBody(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let span = bounds.upperBound - bounds.lowerBound
        let normalized = span > 0 ? (value - bounds.lowerBound) / span : 0
        let bufferNormalized = span > 0 ? max(0, min(1, (bufferValue - bounds.lowerBound) / span)) : 0
        let progressWidth = width * CGFloat(normalized)
        let bufferWidth = width * CGFloat(bufferNormalized)
        let hoverNormalized: CGFloat? = hoverValue.flatMap { hv in
            span > 0 ? CGFloat((hv - bounds.lowerBound) / span) : nil
        }

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 4)
                .cornerRadius(2)

            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: max(0, bufferWidth), height: 4)
                .cornerRadius(2)

            Rectangle()
                .fill(isFocused ? Color.accentColor : Color.white)
                .frame(width: max(0, progressWidth), height: 4)
                .cornerRadius(2)

            if let hv = hoverNormalized {
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 2, height: 8)
                    .offset(x: max(0, hv * width - 1))
            }

            Circle()
                .fill(Color.white)
                .frame(width: beginDrag ? 18 : 14, height: beginDrag ? 18 : 14)
                .offset(x: max(0, progressWidth - (beginDrag ? 9 : 7)))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !beginDrag {
                        beginDrag = true
                        onEditingChanged(true)
                    }
                    let fraction = Float(max(0, min(1, g.location.x / width)))
                    value = bounds.lowerBound + fraction * span
                }
                .onEnded { _ in
                    beginDrag = false
                    onEditingChanged(false)
                }
        )
        #if os(macOS) || targetEnvironment(macCatalyst)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let fraction = Float(max(0, min(1, point.x / width)))
                hoverValue = bounds.lowerBound + fraction * span
            case .ended:
                hoverValue = nil
            }
        }
        #endif
    }
}
