//
//  SubtitleRightView.swift
//  KSPlayer
//
//  RE addition: SwiftUI view for the secondary (right-side) subtitle
//  track display, used in dual subtitle mode. Renders an attributed-text
//  subtitle positioned via `TextPosition` with `screenWidth`-relative
//  layout. Originally surfaced in the "Forward" iOS app (v1.3.15);
//  renamed/situated here by role.
//
//  Binary: $s8KSPlayer17SubtitleRightViewV (value-witness entries only;
//  the SwiftUI `body` is inlined, so only the VWT accessor
//  `SubtitleRightView…Vwca @ 0x10149B3D8` is named — doc §1095-1096).
//

import SwiftUI

/// Secondary (right-side) subtitle surface in dual-subtitle mode.
///
/// Per the `types.json` roster (doc §1087), this struct carries exactly
/// three stored fields: the attributed subtitle text, its on-screen
/// `TextPosition`, and the reference `screenWidth` used for width-relative
/// layout. All color / font / background styling is carried *inside* the
/// `NSAttributedString` attributes — there are no separate styling fields.
public struct SubtitleRightView: View {
    /// The attributed subtitle text. Styling (color, font, stroke, etc.)
    /// lives in the attribute runs, matching the binary's
    /// `text :: __C.NSAttributedString` field (doc §1087).
    public var text: NSAttributedString
    /// On-screen placement (vertical/horizontal alignment + margins) that
    /// drives the rendered text's alignment and edge insets.
    public var textPosition: TextPosition
    /// Reference width (points) of the host video surface, used for
    /// width-relative layout of the right-side subtitle.
    public var screenWidth: Double

    public init(text: NSAttributedString = NSAttributedString(string: ""),
                textPosition: TextPosition = TextPosition(),
                screenWidth: Double = 0) {
        self.text = text
        self.textPosition = textPosition
        self.screenWidth = screenWidth
    }

    /// RE: 0x10149B3D8 (`SubtitleRightView…Vwca` — VWT accessor; the body
    /// itself is inlined in the binary). Reconstructed as an idiomatic
    /// SwiftUI body that displays the `NSAttributedString` and applies a
    /// position/frame derived from `textPosition` and `screenWidth`
    /// (doc §1093-1094). The sibling `SubtitlePartView` body in
    /// VideoSubtitleView.swift follows the same TextPosition-driven
    /// alignment convention.
    public var body: some View {
        if text.length > 0 {
            // Bridge the platform NSAttributedString into SwiftUI. The
            // AttributedString initializer preserves the attribute runs,
            // so the styling the binary carries on `text` survives into
            // the rendered Text.
            Text(AttributedString(text))
                .multilineTextAlignment(textAlignment)
                // Width-relative layout: constrain to the reference
                // screen width when one is provided; otherwise let the
                // text size naturally.
                .frame(maxWidth: layoutWidth, alignment: alignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: alignment)
                .padding(textPosition.edgeInsets)
        }
    }

    /// Maximum layout width derived from `screenWidth`. A non-positive
    /// `screenWidth` means "unconstrained", so fall back to `.infinity`.
    private var layoutWidth: CGFloat {
        screenWidth > 0 ? CGFloat(screenWidth) : .infinity
    }

    /// Map the horizontal component of `textPosition` to a SwiftUI
    /// `TextAlignment` for multi-line wrapping.
    private var textAlignment: TextAlignment {
        switch textPosition.horizontalAlign {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    /// Combine the vertical and horizontal components of `textPosition`
    /// into a SwiftUI `Alignment` for frame placement.
    private var alignment: Alignment {
        Alignment(horizontal: textPosition.horizontalAlign,
                  vertical: textPosition.verticalAlign)
    }
}
