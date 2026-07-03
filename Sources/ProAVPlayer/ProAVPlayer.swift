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
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary gives ProAVPlayer its OWN 16-slot vtable
/// (overrides + new methods on KSAVPlayer), which a `final` subclass would not emit (the SRC `final` gave
/// no own vtable). ⚑ EXACT-LAYOUT = tracked structural debt: matching the 16 own slots needs member-level
/// `final`/override reconstruction not yet done (same class as the LocalHLSServer residual).
class ProAVPlayer: KSAVPlayer, ConversionInfoDelegate {   // + ConversionInfoDelegate (binary conf@0x1035715a0); reqs → M2
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

    // ── ConversionInfoDelegate conformance (binary conf@0x1035715a0, wt 0x1041e1340). 3 instance-method
    //    witnesses, devirtualized/stripped → their bodies are ProAVPlayer's OWN M2 unit. Honest stubs so the
    //    protocol (declared from ConversionInfo's forwards, ConversionInfo.swift) compiles; ⚑ UNRESOLVED →
    //    ProAVPlayer M2. Names are the inferred ConversionInfoDelegate names (firm up with this conformance).
    func conversionDidUpdate() {
        // UNRESOLVED — ProAVPlayer ConversionInfoDelegate witness (wt 0x1041e1340, req0); ProAVPlayer M2.
    }
    func conversionDidReachEnd() {
        // UNRESOLVED — ProAVPlayer ConversionInfoDelegate witness (req1); ProAVPlayer M2.
    }
    func conversionDidFail(_ error: any Error) {
        // UNRESOLVED — ProAVPlayer ConversionInfoDelegate witness (req2); ProAVPlayer M2.
    }
}
