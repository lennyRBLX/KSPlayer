//
//  ProAVPlayer.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new KSAVPlayer subclass that plays the locally-converted HLS via
//  AVFoundation. Field types resolved deterministically (field-record mangle + a known-answer control
//  for the Task Failure). Method bodies → M2.
//  Binary: desc=0x1039f52c4, superclass=KSAVPlayer (needs `open`), vtable=16, 1 impl body @slot15
//  (the AVPlayer-wrapper method per the module enumeration); rest devirt/inherited → M2.
//

import AVFoundation
import KSPlayer

/// The ProAVPlayer module's player: a KSAVPlayer subclass that plays the locally-served HLS conversion.
/// Forward-new (ProAVPlayer module).
final class ProAVPlayer: KSAVPlayer, ConversionInfoDelegate {   // + ConversionInfoDelegate (binary conf@0x1035715a0); reqs → M2
    // 4 reflection fields (order = layout). Optionality from the mangle Sg.
    // task's Failure = Error PROVEN (known-answer control: KSAVPlayer.error `Error?` symref → the
    // same protocol descriptor 0x10536d100); Success = AVPlayerItem (So-mangle). Access level is not
    // binary-determined — `private` under-includes (P17); widen at M2 if a usage requires it.
    private var m3u8Info: ConversionInfo? = nil
    private var task: Task<AVPlayerItem, Error>? = nil
    private var hasEndOfStream: Bool = false
    private var seekToTime: CMTime? = nil

    // Adds no designated init + all 4 stored props defaulted ⇒ inherits KSAVPlayer's
    // `required init(url:options:)`. vtable=16, slot15 impl (+ inherited/devirt) → M2.
}
