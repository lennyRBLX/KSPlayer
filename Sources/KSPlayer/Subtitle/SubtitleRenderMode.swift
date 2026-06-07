//
//  SubtitleRenderMode.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleRenderMode enum referenced by
//  EmptySubtitleInfo and the renderer-dispatch path. Centralises the
//  image / assView / srtView rendering-strategy selection that was
//  previously scattered across implicit `part.image != nil` /
//  `part.text != nil` checks.
//
//  Case order/names verified 1.3.15 from reflection metadata
//  (__swift5_fieldmd, via DumpSwiftEnums.java): the cases are
//  image (0), assView (1), srtView (2) — declaration index = raw tag.
//

import Foundation

/// Rendering strategy for a subtitle track, mirroring the
/// SubtitleRenderMode enum present in the Forward binary.
///
/// The binary uses this enum to decide which view path consumes a
/// SubtitlePart:
/// - `.image`   →  bitmap overlay for PGS / VOBSUB / DVB
/// - `.assView` →  libass-driven AssIncrementImageRenderer / MetalSubtitleView
/// - `.srtView` →  text/SRT attributed-string overlay via VideoSubtitleView (SwiftUI)
public enum SubtitleRenderMode: UInt8, Sendable, Hashable {
    /// Bitmap rendering. Used for PGS / SUP / VOBSUB / DVB tracks where
    /// `SubtitlePart.image` carries the rendered glyph.
    case image = 0

    /// libass image rendering for ASS / SSA tracks when complex effects
    /// (blur, animations, vector drawings, fade) require full libass
    /// fidelity, via `AssIncrementImageRenderer` / `MetalSubtitleView`.
    case assView = 1

    /// Attributed-string text rendering via `VideoSubtitleView`. Default
    /// for SRT, VTT, and ASS tracks where libass image rendering is
    /// disabled.
    case srtView = 2
}

public extension SubtitleRenderMode {
    /// Infer the appropriate render mode from a `SubtitlePart`'s payload.
    /// Used as the default for tracks that do not explicitly declare a
    /// `renderMode` (e.g. legacy `URLSubtitleInfo` instances).
    static func infer(from part: SubtitlePart) -> SubtitleRenderMode {
        if part.image != nil {
            return .image
        }
        return .srtView
    }
}
