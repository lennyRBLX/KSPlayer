//
//  PlayerSlider.swift
//  KSPlayer
//
//  Forward addition (RE): Custom SwiftUI slider for video player
//  seek bar with configurable track colors.
//
//  Binary: $s8KSPlayer12PlayerSliderV (VWT + 7 functions)
//  RE source: Forward v1.3.15
//

import SwiftUI

public struct PlayerSlider: View {
    @Binding public var value: Double
    public var range: ClosedRange<Double> = 0...1
    public var onEditingChanged: ((Bool) -> Void)?

    public var trackColor: Color
    public var progressColor: Color
    public var thumbColor: Color

    // RE: PlayerSlider_initDefaultTrackColor @ 0x1008eac60
    public init(value: Binding<Double>,
                range: ClosedRange<Double> = 0...1,
                trackColor: Color = .gray.opacity(0.3),
                progressColor: Color = .white,
                thumbColor: Color = .white,
                onEditingChanged: ((Bool) -> Void)? = nil) {
        self._value = value
        self.range = range
        self.trackColor = trackColor
        self.progressColor = progressColor
        self.thumbColor = thumbColor
        self.onEditingChanged = onEditingChanged
    }

    // RE: PlayerSlider_bodyBuilder @ 0x1014b2bfc
    public var body: some View {
        GeometryReader { geometry in
            buildTrackBody(in: geometry)
        }
    }

    // RE: PlayerSlider_buildTrackBody @ 0x1014b44d0
    @ViewBuilder
    private func buildTrackBody(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let progressWidth = width * CGFloat(normalizedValue)

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(trackColor)
                .frame(height: 4)
                .cornerRadius(2)

            Rectangle()
                .fill(progressColor)
                .frame(width: max(0, progressWidth), height: 4)
                .cornerRadius(2)

            Circle()
                .fill(thumbColor)
                .frame(width: 14, height: 14)
                .offset(x: max(0, progressWidth - 7))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(gesture.location.x / width)
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                    onEditingChanged?(true)
                }
                .onEnded { _ in
                    onEditingChanged?(false)
                }
        )
    }
}
