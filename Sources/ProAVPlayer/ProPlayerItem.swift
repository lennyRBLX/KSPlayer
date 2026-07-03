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
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary gives ProPlayerItem its OWN 3-slot vtable
/// (overrides/new members on AVPlayerItem), which a `final` subclass would not emit (the SRC `final` gave
/// no own vtable). ⚑ EXACT-LAYOUT = tracked structural debt: matching the 3 own slots needs member-level
/// reconstruction not yet done (same class as the LocalHLSServer residual).
class ProPlayerItem: AVPlayerItem {
    // 1 reflection field. Optional (mangle Sg) — defaults nil ⇒ AVPlayerItem designated inits inherited
    // (no new designated init + the one new stored prop is defaulted). The real init → M2.
    var m3u8Info: ConversionInfo? = nil

    // vtable-empty (3 devirtualized slots — AVPlayerItem overrides/additions) → M2 via witness-table-
    // anchoring (the e651ff8 technique). Structure-only here (P15).
}
