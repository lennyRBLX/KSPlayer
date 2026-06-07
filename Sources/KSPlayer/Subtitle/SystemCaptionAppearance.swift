//
//  SystemCaptionAppearance.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 SubtitleModel_applySystemCaptionAppearance (0x101491738).
//  Note: 0x101491738 is the entry/thunk; the function body lives in the
//  0x1014963xx–0x1014969xx span. The doc's second row 0x101496194
//  "applySystemCaptionAppearance (variant)" decompiles to the IDENTICAL body —
//  it is ONE function, not a primary + variant. Do not reconstruct a phantom variant.
//

import CoreText
import Foundation
import MediaAccessibility
import SwiftUI

public extension SubtitleModel {
    /// Applies the user's system-wide caption appearance preferences (Settings → Accessibility → Subtitles & Captioning).
    /// Reads MACaptionAppearance values for: edge style, font, relative size, foreground/background color+opacity.
    ///
    /// RE: 0x101491738 (SubtitleModel.applySystemCaptionAppearance, 1.3.15).
    /// Binary order: GetTextEdgeStyle → edge-style shadow globals → font descriptor
    /// (name attribute, "SF Pro" default) → font-size = CTFontGetSize * relativeCharacterSize
    /// → foreground color+opacity → background color+opacity. It never reads window color.
    @MainActor
    static func applySystemCaptionAppearance() {
        let domain = MACaptionAppearanceDomain.user

        // Edge style. The binary switches on the raw MACaptionAppearanceTextEdgeStyle
        // return (1..5) and writes the global subtitle shadow state accordingly; the
        // CaptionEdgeStyle.shadow helper mirrors that per-case shadow geometry.
        let edgeStyle = MACaptionAppearanceGetTextEdgeStyle(domain, nil)
        captionEdgeStyle = CaptionEdgeStyle(rawValue: edgeStyle.rawValue) ?? .none

        // Font. Binary seeds the caption font-name global with the literal "SF Pro"
        // (s_SF_Pro @ 0x103d09790) as the default, then overwrites it from the font
        // descriptor's name attribute (kCTFontNameAttribute) via
        // CTFontDescriptorCopyAttribute + swift_dynamicCast<String>.
        captionFontName = "SF Pro"
        let fontDescriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, nil, .default)
        if let fd = fontDescriptor {
            if let nameAttr = CTFontDescriptorCopyAttribute(fd, kCTFontNameAttribute) as? String,
               !nameAttr.isEmpty
            {
                captionFontName = nameAttr
            }
            // Effective point size = CTFontGetSize(descriptor font) * relativeCharacterSize.
            // The binary stores the PRODUCT into the shared font-size global
            // (DAT_103d097a0, the textFontSize mirror), not the bare multiplier.
            let ctFont = CTFontCreateWithFontDescriptor(fd, 0, nil)
            let pointSize = CTFontGetSize(ctFont)
            let relativeSize = MACaptionAppearanceGetRelativeCharacterSize(domain, nil)
            let effectiveSize = CGFloat(pointSize) * CGFloat(relativeSize)
            captionRelativeSize = effectiveSize
            textFontSize = effectiveSize
        }

        // Foreground color + opacity (MACaptionAppearanceCopyForegroundColor +
        // GetForegroundOpacity → UIColor.colorWithAlphaComponent).
        if let fgColor = MACaptionAppearanceCopyForegroundColor(domain, nil) {
            let fgOpacity = MACaptionAppearanceGetForegroundOpacity(domain, nil)
            captionForegroundColor = Color(cgColor: fgColor).opacity(Double(fgOpacity))
        }

        // Background color + opacity (MACaptionAppearanceCopyBackgroundColor +
        // GetBackgroundOpacity → UIColor.colorWithAlphaComponent).
        if let bgColor = MACaptionAppearanceCopyBackgroundColor(domain, nil) {
            let bgOpacity = MACaptionAppearanceGetBackgroundOpacity(domain, nil)
            captionBackgroundColor = Color(cgColor: bgColor).opacity(Double(bgOpacity))
        }

        isSystemCaptionAppearanceApplied = true
    }

    /// Whether system caption appearance has been applied this session
    static var isSystemCaptionAppearanceApplied = false

    /// System caption edge style preference
    static var captionEdgeStyle: CaptionEdgeStyle = .none

    /// System caption font name. Binary default is the literal "SF Pro".
    static var captionFontName: String? = "SF Pro"

    /// System caption effective font size (points). Binary stores
    /// CTFontGetSize * relativeCharacterSize here (DAT_103d097a0); kept as a named
    /// alias of the resolved size so existing consumers continue to compile.
    static var captionRelativeSize: CGFloat = SubtitleModel.Size.standard.rawValue

    /// System caption foreground color (with opacity applied)
    static var captionForegroundColor: Color?

    /// System caption background color (with opacity applied)
    static var captionBackgroundColor: Color?
}

/// Edge style types matching the MediaAccessibility `MACaptionAppearanceTextEdgeStyle`
/// system enum (so `CaptionEdgeStyle(rawValue: edgeStyle.rawValue)` round-trips 1:1).
///
/// RE: 0x101491738. The binary's edge-style switch keys on these exact raw values:
///   1 none      → clearColor, shadow opacity 0, no offset
///   2 raised     → clearColor, offset (-3.5, 3.5), blur 5.0, opacity 0
///   3 depressed  → clearColor, offset ( 3.5, -3.5), blur 5.0, opacity 0
///   4 uniform    → blackColor, no offset, opacity 2.0
///   5 dropShadow → blackColor, offset ( 0.0, 3.5), blur 6.0, opacity 1.0
public enum CaptionEdgeStyle: Int32 {
    case undefined = 0
    case none = 1
    case raised = 2
    case depressed = 3
    case uniform = 4
    case dropShadow = 5

    /// Per-case shadow geometry as written to the global subtitle shadow state by
    /// `applySystemCaptionAppearance`. Offsets/blur/opacity are the binary constants
    /// (DAT_104458790/798 offset, DAT_1044587a8 blur, DAT_104458788 opacity).
    public var shadow: Shadow? {
        switch self {
        case .undefined, .none:
            return nil
        case .raised:
            // clearColor + offset (-3.5, 3.5), blur 5.0, opacity 0 (transparent stroke)
            return Shadow(color: .clear, radius: 5, x: -3.5, y: 3.5)
        case .depressed:
            // clearColor + offset (3.5, -3.5), blur 5.0, opacity 0 (transparent stroke)
            return Shadow(color: .clear, radius: 5, x: 3.5, y: -3.5)
        case .uniform:
            // blackColor, opacity 2.0 (clamped to 1.0 by Color), no offset/blur
            return Shadow(color: .black, radius: 0, x: 0, y: 0)
        case .dropShadow:
            // blackColor + offset (0.0, 3.5), blur 6.0, opacity 1.0
            return Shadow(color: .black, radius: 6, x: 0, y: 3.5)
        }
    }
}

public struct Shadow {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
}
