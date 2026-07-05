//
//  AssImageParse.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW ASS-image parser + the incremental image-renderer actor (P4 M1 structure). Bodies → P4 M2.
//
import CoreGraphics
import Foundation

// AssImageParse @0x1039f14f8 — stateless parser (:KSParseProtocol, §8.5).
public class AssImageParse: KSParseProtocol {
    public init() {}
    // ⚑ UNRESOLVED → P4 M2: canParse / parsePart bodies
    public func canParse(scanner: Scanner) -> Bool { false }
    public func parsePart(scanner: Scanner) -> SubtitlePart? { nil }
}

// AssIncrementImageRenderer @0x1039f1534 — NEW `actor` ($defaultActor; type_kind_gate). Fields reflection-ordered
// (uuid/header/subtitles/fontsDir/renderer/basicFontSize), types §8.3/§8.6. Bodies → P4 M2.
actor AssIncrementImageRenderer: KSSubtitleProtocol { // §8.5-gap: KSSubtitleProtocol conformer (reverse-walk-confirmed)
    private let uuid: UUID = UUID()                                                  // ⚑ UUID inferred (GOT-indirect) → recon/mangle-evidenced
    private var header: String?
    private var subtitles: [(subtitle: String, start: Double, duration: Double)] = [] // §8.6
    private var fontsDir: String?
    private let renderer: AssImageRenderer
    private var basicFontSize: Int = 0
    // ⚑ init shape inferred → M2 witness-verify
    init(renderer: AssImageRenderer) {
        self.renderer = renderer
    }
    // ⚑ UNRESOLVED → P4 M2: the incremental libass-render async methods

    // ⚑ UNRESOLVED → P4 M2: search(for:) — serves rendered subtitle parts by time (KSSubtitleProtocol req)
    nonisolated func search(for _: TimeInterval) -> [SubtitlePart] { [] }
}
