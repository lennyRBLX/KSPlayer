//
//  SubtitleRenderMode.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleRenderMode enum referenced by
//  EmptySubtitleInfo and the renderer-dispatch path. Centralises the
//  text / image / ass rendering-strategy selection that was previously
//  scattered across implicit `part.image != nil` / `part.text != nil`
//  checks.
//

import Foundation

/// Rendering strategy for a subtitle track, mirroring the
/// SubtitleRenderMode enum present in the Forward binary.
///
/// The binary uses this enum to decide which view path consumes a
/// SubtitlePart:
/// - `.text`  →  attributed-string overlay via VideoSubtitleView (SwiftUI)
/// - `.image` →  bitmap overlay for PGS / VOBSUB / DVB
/// - `.ass`   →  libass-driven AssIncrementImageRenderer / MetalSubtitleView
public enum SubtitleRenderMode: UInt8, Sendable, Hashable {
    /// Attributed-string text rendering. Default for SRT, VTT, and ASS
    /// tracks where libass image rendering is disabled.
    case text = 0

    /// Bitmap rendering. Used for PGS / SUP / VOBSUB / DVB tracks where
    /// `SubtitlePart.image` carries the rendered glyph.
    case image = 1

    /// libass image rendering for ASS / SSA tracks when complex effects
    /// (blur, animations, vector drawings, fade) require full libass
    /// fidelity.
    case ass = 2
}

public extension SubtitleRenderMode {
    /// Infer the appropriate render mode from a `SubtitlePart`'s payload.
    /// Used as the default for tracks that do not explicitly declare a
    /// `renderMode` (e.g. legacy `URLSubtitleInfo` instances).
    static func infer(from part: SubtitlePart) -> SubtitleRenderMode {
        if part.image != nil {
            return .image
        }
        return .text
    }
}
