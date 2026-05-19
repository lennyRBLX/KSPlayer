//
//  SubtitleRightView.swift
//  KSPlayer
//
//  Forward addition (RE): SwiftUI view for the secondary (right-side)
//  subtitle track display, used in dual subtitle mode.
//
//  Binary: $s8KSPlayer17SubtitleRightViewV (VWT entries only)
//  RE source: Forward v1.3.15
//

import SwiftUI

public struct SubtitleRightView: View {
    public var text: String
    public var textColor: Color
    public var fontSize: CGFloat
    public var backgroundColor: Color

    public init(text: String = "",
                textColor: Color = .white,
                fontSize: CGFloat = 16,
                backgroundColor: Color = .black.opacity(0.5)) {
        self.text = text
        self.textColor = textColor
        self.fontSize = fontSize
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundColor(textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor)
                .cornerRadius(4)
        }
    }
}
