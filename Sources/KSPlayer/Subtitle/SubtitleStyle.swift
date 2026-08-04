//
//  SubtitleStyle.swift
//  KSPlayer
//
//  Forward 1.3.17 subtitle text-styling + render model (P4 M1 structure).
//  Field types/order/kinds are binary-decoded (spec 2026-07-04-subtitle-datasource-migration-phase.md §8.4/§8.6);
//  bodies are P4 M2. Visibility under-included (not binary-pinned, §1).
//
import CoreGraphics
import Foundation
import SwiftUI

// Either (SubtitlePart.render payload) — ALREADY declared in Core/Utility.swift as the KSPlayer enum
// `Either<Left, Right>` (§8.6 @0x1039ee5d4); NOT re-declared here.

// SubtitleRenderMode @0x1039f18c0 — cases descriptor-confirmed
public enum SubtitleRenderMode {
    case image
    case assView
    case srtView
}

// SubtitleTextRole @0x1039f2204 — dual-subtitle role; cases descriptor-confirmed
public enum SubtitleTextRole {
    case primary
    case secondary
}

// SubtitleImageInfo @0x1039f215c
public struct SubtitleImageInfo {
    public var rect: CGRect
    public var source: BitmapSource
    public var displaySize: CGSize
    public var styleRole: SubtitleTextRole
}

// SubtitleTextInfo @0x1039f21cc
public struct SubtitleTextInfo {
    public var text: NSAttributedString
    public var position: TextPosition?
    public var displaySize: CGSize?
    public var styleRole: SubtitleTextRole
    public var usesForcedPosition: Bool

    /// ⚑ getter 0x10047dc78, eight instructions and only two of them are the body:
    ///   ldr x20, [x20]        ; self's FIRST field, i.e. `text` — offset 0, no addend
    ///   bl  0x10345868c       ; a stub through __got 0x104113628
    /// and that GOT slot binds `_$sSo8NSObjectC10ObjectiveCE9hashValueSivg`, the ObjectiveC
    /// overlay's `NSObject.hashValue` getter. NSAttributedString is an NSObject, so the whole
    /// body is `text.hashValue` — no other field is loaded and nothing else is called.
    /// ⚑[tool=bind_oracle ref=NSObject.hashValue:0x104113628 result=libswiftObjectiveC]
    /// Trie: `KSPlayer.SubtitleTextInfo.id.getter : Swift.Int`.
    public var id: Int {
        text.hashValue
    }
}

// SubtitleTextStyle @0x1039f2220 — all-optional override
public struct SubtitleTextStyle {
    public var textColor: UIColor?
    public var textFontName: String?
    public var subtitleFontSize: Double?
    public var subtitleFontSizeScale: Double?
    public var textBold: Bool?
    public var textItalic: Bool?
    public var textStrokeColor: UIColor?
    public var textStrokeWidth: CGFloat?     // ⚑ CGFloat inferred (GOT-indirect symref) → recon/mangle-evidenced
    public var textShadowOffset: CGSize?
    public var textShadowBlurRadius: Double?
    public var textShadowColor: UIColor?
}

// ResolvedSubtitleTextStyle @0x1039f2258 — resolved, non-optional (+textBackgroundColor @ field-index 9)
public struct ResolvedSubtitleTextStyle {
    public var textColor: UIColor
    public var textFontName: String
    public var subtitleFontSize: Double
    public var subtitleFontSizeScale: Double
    public var textBold: Bool
    public var textItalic: Bool
    public var textStrokeColor: UIColor
    public var textStrokeWidth: CGFloat      // ⚑ CGFloat inferred
    public var textShadowOffset: CGSize
    public var textBackgroundColor: UIColor
    public var textShadowBlurRadius: Double
    public var textShadowColor: UIColor
}

// KSSubtitleQuery @0x1039f1884 — the SubtitleActor lookup key
public struct KSSubtitleQuery {
    public var time: Double
    public var size: CGSize
    public var verticalAlign: VerticalAlignment?   // ⚑ SwiftUI VerticalAlignment (recon TextPosition survives it)
    public var textPosition: TextPosition?
    public var textRole: SubtitleTextRole
}
