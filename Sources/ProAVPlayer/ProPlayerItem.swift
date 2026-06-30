//
//  ProPlayerItem.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new AVPlayerItem subclass carrying the conversion info for the
//  locally-served HLS. Field type resolved deterministically (field-record mangle); superclass from
//  the descriptor mangle (So…AVPlayerItemC). Method bodies → M2.
//  Binary: desc=0x1039f5278, superclass=AVPlayerItem, vtable=3 (vtable-empty; slots devirtualized → M2).
//

import AVFoundation

/// The AVPlayerItem ProAVPlayer plays — carries the `ConversionInfo` describing the local HLS conversion.
/// Forward-new (ProAVPlayer module).
final class ProPlayerItem: AVPlayerItem {
    // 1 reflection field. Optional (mangle Sg) — defaults nil ⇒ AVPlayerItem designated inits inherited
    // (no new designated init + the one new stored prop is defaulted). The real init → M2.
    var m3u8Info: ConversionInfo? = nil

    // vtable-empty (3 devirtualized slots — AVPlayerItem overrides/additions) → M2 via witness-table-
    // anchoring (the e651ff8 technique). Structure-only here (P15).
}
