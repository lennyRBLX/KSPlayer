//
//  OutputStreamInfo.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — NEW Forward-only class (0 source hits).
//  STRUCTURE-ONLY scope (user-gated): the type's 12 stored fields + an inferred minimal init are
//  reconstructed faithfully from the binary __swift5_fieldmd field-records. The 3 substantive methods
//  (vtable slots 13/14/15) are DEVIRTUALIZED ~170-line per-stream remux ops with unrecoverable
//  names/signatures → documented UNRESOLVED below, reconstructed in PHASE 2 (Remuxer).
//
//  The per-output-stream config the Phase-2 Remuxer writes packets through.
//
import Libavformat

public final class OutputStreamInfo {       // `final` not binary-pinned (no library evolution) — M2 vtable_anchor_diff verifies; matches 1C.5 choice
    // Types from the class's own __swift5_fieldmd field-records (authoritative). Reflection order.
    public var assetTrackMap: [Int: FFmpegAssetTrack] = [:]      // +0x10  ⚑ key unmapped (non-Si→Int inferred); var (accessor triple, confirmed)
    public var transcodeMap:  [Int: any TranscodeProtocol] = [:] // +0x18  ⚑ key inferred Int; value = P2 skeleton; var (accessor triple, confirmed)
    public var timeBaseMap:   [Int: AVRational] = [:]            // ⚑ key inferred Int; AVRational = FFmpeg C
    public var frameRate:     Int = 0                            // v4 concrete `Si`
    public var url:           String = ""                        // v4 concrete `SS`
    public var streamMapping: [Int: Int] = [:]                   // ⚑ key+value inferred Int (binary AA back-ref)
    public var lastDTSMap:    [Int: Int64] = [:]                 // ⚑ key inferred Int; value Int64 (DTS)
    public var hasWriteTrailer: Bool = false                     // v4 concrete `Sb`
    public let formatCtx:     UnsafeMutablePointer<AVFormatContext>  // v4 concrete (non-optional → init param)
    public var outPacket:     UnsafeMutablePointer<AVPacket>? = nil  // v4 concrete (optional)
    public var formatName:    String = ""                        // v4 concrete `SS`
    public var removeADTS:    Bool = false                       // v4 concrete `Sb`

    // init: binary slot 12 is DEVIRTUALIZED (no body) → signature UNRESOLVED. Minimal inferred init:
    // formatCtx is non-optional (must be supplied); all other fields default. Real init signature
    // (params/order) is unrecoverable from the binary → P2 refines.
    public init(formatCtx: UnsafeMutablePointer<AVFormatContext>) {  // inferred — devirt slot 12, no body
        self.formatCtx = formatCtx
    }

    // ── UNRESOLVED — Phase-2 Remuxer (do NOT reconstruct here; structure-only scope) ──────────────
    // The binary has 3 substantive methods (vtable slots 13/14/15), all DEVIRTUALIZED (names + exact
    // signatures unrecoverable). Each is a ~170-line per-stream remux op (Dictionary lookups over the
    // maps + codec-id/`aac_adts` checks + closure dispatch) = Phase-2 Remuxer logic:
    //   • slot 13 @0x101a1ab5c  — per-stream packet op (ADTS handling; reads removeADTS/maps)
    //   • slot 14 @0x101a1b8d4  — Dictionary/field op over the stream maps
    //   • slot 15 @0x101a1bb5c  — Dictionary/field op over the stream maps
    // Also devirt: accessor triples for 2 further `var` fields (slots 6-11) + the init (slot 12).
    // P2 reconstructs these against the FFmpeg oracle + the real Remuxer call-sites. (Tracked in the
    // ledger "1C.6 → P2 follow-ups".)
}
