//
//  NALUnitParser.swift
//  KSPlayer
//
//  P3a Phase B prereq — typed NAL-unit parser (stub; body → DV-decode NAL subsystem).
//

import Libavcodec

/// One parsed NAL unit. Binary entry layout (Forward 1.3.17, 24 B per entry):
///   `type: Int16 @+0x00` · `kind: UInt8 @+0x02` · `offset: Int64 @+0x08` · `length: UInt64 @+0x10`
/// `kind` is the per-codec classification the parser assigns (1 = HEVC, 0 = H264, 3/4/5 = SEI/other).
struct NALEntry {
    let type: Int16
    let kind: UInt8
    let offset: Int64
    let length: UInt64
}

/// Splits a length-prefixed (AVCC) / start-code bitstream into typed NAL units, extracting the
/// per-codec NAL type (HEVC: `(byte >> 1) & 0x3f`; H264: `byte & 0x1f`) plus SEI payload sizes.
///
/// Binary: `FUN_101a0ce98` (length-prefix) / `FUN_101a0c470` (Annex-B start-code), shared by 3
/// decode callers (VTBox.decodeFrame + two software-decode paths). The typed-parse body is
/// DEFERRED → its own "DV-decode NAL subsystem" unit. This stub returns no units so the callers
/// build and are body-auditable.
func parseNALUnits(data: UnsafePointer<UInt8>, size: Int, codecID: AVCodecID) -> [NALEntry] {
    // UNRESOLVED → DV-decode NAL subsystem: the typed length-prefix/start-code parse + SEI handling.
    return []
}
