//
//  ConversionToM3U8.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new entry that converts a source into local HLS (M3U8) under a
//  temp save dir and hands it to LocalHLSServer. Field types resolved deterministically
//  (field-record + decode_composite + the field-store decompile); method bodies + the real init → M2.
//  Binary: desc=0x1039f5150, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import Foundation

/// Produces the local HLS (master M3U8 + segments) under `videoSaveURL` for `LocalHLSServer` to serve.
/// Forward-new (ProAVPlayer module).
final class ConversionToM3U8 {
    // 2 reflection fields (order = layout). Types: decode_composite + the field-store decompile.
    // ⚑ binary NON-optional (field-record mangle has no `Sg`; FUN_101b6bf88 value-witness-copies a URL
    //   value directly into the field — value type, not Optional). `!` (IUO) is the M1 placeholder-init
    //   stand-in; the real construction (NSTemporaryDirectory temp dir, "m3u8") → M2.
    private var videoSaveURL: URL! = nil
    private var localHLSServer: LocalHLSServer? = nil   // optional (mangle `Sg`; init-stored nil)

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real
    // init (FUN_101b6bf88 stores videoSaveURL, nils localHLSServer). Structure-only here (P15).
}
