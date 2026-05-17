//
//  SystemCaptionAppearance.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 SubtitleModel_applySystemCaptionAppearance (0x101491738)
//

import CoreText
import Foundation
import MediaAccessibility
import SwiftUI

public extension SubtitleModel {
    /// Applies the user's system-wide caption appearance preferences (Settings → Accessibility → Subtitles & Captioning).
    /// Reads MACaptionAppearance values for: edge style, font, relative size, foreground/background color+opacity.
    @MainActor
    static func applySystemCaptionAppearance() {
        let domain = MACaptionAppearanceDomain.user

        // Edge style (maps to text shadow/stroke)
        let edgeStyle = MACaptionAppearanceGetTextEdgeStyle(domain, nil)
        captionEdgeStyle = CaptionEdgeStyle(rawValue: edgeStyle.rawValue) ?? .none

        // Font
        let fontDescriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, nil, .default)
        if let fd = fontDescriptor {
            let ctFont = CTFontCreateWithFontDescriptor(fd, 0, nil)
            let fontName = CTFontCopyPostScriptName(ctFont) as String
            if !fontName.isEmpty {
                captionFontName = fontName
            }
        }

        // Relative character size (0.0–2.0 range, 1.0 = default)
        let relativeSize = MACaptionAppearanceGetRelativeCharacterSize(domain, nil)
        if relativeSize > 0 {
            captionRelativeSize = CGFloat(relativeSize)
        }

        // Foreground color + opacity
        if let fgColor = MACaptionAppearanceCopyForegroundColor(domain, nil) {
            let fgOpacity = MACaptionAppearanceGetForegroundOpacity(domain, nil)
            captionForegroundColor = Color(cgColor: fgColor).opacity(Double(fgOpacity))
        }

        // Background color + opacity
        if let bgColor = MACaptionAppearanceCopyBackgroundColor(domain, nil) {
            let bgOpacity = MACaptionAppearanceGetBackgroundOpacity(domain, nil)
            captionBackgroundColor = Color(cgColor: bgColor).opacity(Double(bgOpacity))
        }

        // Window color + opacity (container behind subtitle region)
        if let winColor = MACaptionAppearanceCopyWindowColor(domain, nil) {
            let winOpacity = MACaptionAppearanceGetWindowOpacity(domain, nil)
            captionWindowColor = Color(cgColor: winColor).opacity(Double(winOpacity))
        }

        isSystemCaptionAppearanceApplied = true
    }

    /// Whether system caption appearance has been applied this session
    static var isSystemCaptionAppearanceApplied = false

    /// System caption edge style preference
    static var captionEdgeStyle: CaptionEdgeStyle = .none

    /// System caption font name (PostScript name)
    static var captionFontName: String?

    /// System caption relative size multiplier (1.0 = default)
    static var captionRelativeSize: CGFloat = 1.0

    /// System caption foreground color (with opacity applied)
    static var captionForegroundColor: Color?

    /// System caption background color (with opacity applied)
    static var captionBackgroundColor: Color?

    /// System caption window color (with opacity applied)
    static var captionWindowColor: Color?
}

/// Edge style types matching MACaptionAppearanceTextEdgeStyle values from the binary
public enum CaptionEdgeStyle: Int32 {
    case none = 0
    case raised = 1
    case depressed = 2
    case uniform = 3
    case dropShadow = 4

    public var shadow: Shadow? {
        switch self {
        case .none:
            return nil
        case .raised:
            return Shadow(color: .black.opacity(0.8), radius: 0, x: -1, y: -1)
        case .depressed:
            return Shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
        case .uniform:
            return Shadow(color: .black, radius: 1, x: 0, y: 0)
        case .dropShadow:
            return Shadow(color: .black.opacity(0.8), radius: 2, x: 2, y: 2)
        }
    }
}

public struct Shadow {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
}
