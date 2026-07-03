//
//  ConversionInfo.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new coordinator for the convert-to-HLS pipeline: owns the
//  demuxer/remuxer/server/watcher and tracks playback timing. Field types resolved deterministically
//  (field-record mangle token-walk + l2_field_gate); method bodies + the real init → M2.
//  Binary: desc=0x1039f4fdc, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import Foundation
import KSPlayer

/// Coordinates the convert-to-HLS pipeline (demuxer ↔ remuxer ↔ local server ↔ directory watcher) and
/// surfaces playback timing/duration. Forward-new (ProAVPlayer module).
final class ConversionInfo: DemuxerIODelegate, RemuxerIOActionDelegate {   // binary conformances (conf@0x1035711a8/0x103571198); reqs → M2
    // 11 reflection fields (order = layout). Types: field-record mangle token-walk (Sg/Xw/_p suffix
    // authoritative for optionality); refs are non-optional (single symref, no Sg) → IUO M1 stand-ins.
    private var assetTracks: [FFmpegAssetTrack] = []
    private var duration: Double = 0
    private var subtitles: [MediaPlayerTrack] = []        // existential array (mangle Say…_pG; non-optional)
    // weak optional existential (mangle _pSgXw) → ConversionInfoDelegate (AnyObject). 3 reqs → M2.
    private weak var delegate: ConversionInfoDelegate? = nil
    private var demuxerTime: Double = 0
    private var currentPlaybackTime: Double = 0
    private var maxBufferDuration: Double = 0
    // ⚑ binary NON-optional refs (single symref, no Sg); IUO M1 stand-ins — real construction → M2.
    private var remuxerIOAction: RemuxerIOAction! = nil
    private var demuxerIO: DemuxerIO! = nil
    private var server: LocalHLSServer! = nil
    private var directoryWatcher: DirectoryWatcher! = nil  // KSPlayer (now public, fe13053)

    // ── DemuxerIODelegate conformance (wt 0x1041e0b90). 4 instance-method reqs (conformance_walker):
    //    ConversionInfo observes the demuxer and forwards lifecycle to its own `delegate`
    //    (ConversionInfoDelegate). Witness bodies binary-read (prefetch verbatim, P27).

    /// `FUN_101b6a40c`. Throttled progress: act only on a forward move of ≥ 1.0s
    /// (`abs(demuxerTime - value) >= 1.0`), record the new demuxer time, then spawn the progress `Task`
    /// only when the un-drained lead `(value - remuxerIOAction.startPlayTime) - currentPlaybackTime`
    /// exceeds `maxBufferDuration`. Disasm-verified: the `demuxerTime` store is guard-scoped
    /// (`str d8,[x20,#0x38]` @0x101b6a47c, inside the ≥1.0s guard) — NOT hoisted (P42). The Task's async
    /// body is deep → deferred (see the marker below).
    func didUpdateCurrentTime(_ value: Double) {
        guard value > 0, abs(demuxerTime - value) >= 1.0 else { return }   // [fcmp/b.ls @0x460; fcmp/b.mi @0x478]
        demuxerTime = value                                                // [str d8,[x20,#0x38] @0x47c — guard-scoped]
        var start = 0.0
        if let sp = remuxerIOAction.startPlayTime { start = sp }           // [remuxerIOAction@0x50; startPlayTime payload@+0x10/tag@+0x18]
        if maxBufferDuration < (value - start) - currentPlaybackTime {     // [fsub;fsub;fcmp d2,d0;b.pl @0x498-4a8]
            Task { [self] in                                               // [swift_retain self @0x4f4; swift_task_create via FUN_101b76920 @0x510]
                // ⚑ UNRESOLVED — deep-async body: FUN_101b6a530 (READ, P43) sets URL-typed task-locals then
                //   `_swift_task_switch`es to the continuation FUN_101b6a59c — a continuation-split coroutine
                //   chain (genuinely deep-async, verified not assumed). The spawn + strong self-capture are
                //   faithful; the closure internals = the "ConversionInfo deep-async closures" sub-unit
                //   (P36, sibling of DemuxerIO's slot28/30).
                _ = self
            }
        }
    }

    /// `FUN_101b6abf8` — forward to the coordinator's own delegate (witness +0x10 = ConversionInfoDelegate req1).
    func demuxerDidReachEnd() {
        delegate?.conversionDidReachEnd()
    }

    /// `FUN_101b6ac44` — forward the error (witness +0x18 = ConversionInfoDelegate req2).
    func demuxerDidFail(_ error: any Error) {
        delegate?.conversionDidFail(error)
    }

    /// `FUN_10000e52c` — empty in the binary (an outlined no-op in the low `__text` segment; segment
    /// pre-flighted — it is a bona-fide witness-table entry, not a mis-attribution).
    func demuxerDidClose() {
    }

    // ── RemuxerIOActionDelegate conformance (wt 0x1041e0b80). 1 instance-method req; witness FUN_101b6aca8.

    /// `FUN_101b6aca8` — dispatch on the remux signal: `== 2` spawns the async handler Task; an odd value
    /// (`(state & 1) != 0`, i.e. 1/3) forwards to the coordinator delegate (witness +0x8 =
    /// ConversionInfoDelegate req0); any other value is ignored. ⚑ req NAME + arg TYPE inferred (protocol decl).
    func remuxerDidChangeState(_ state: Int) {
        if state == 2 {                                                    // [cmp/b.eq case 2 @FUN_101b6aca8]
            Task { [self] in                                              // [swift_retain self; swift_task_create via FUN_101b76920]
                // ⚑ UNRESOLVED — deep-async body: FUN_101b6adc8 (READ, P43) `_swift_task_switch`es to the
                //   continuation FUN_101b6ade0 — continuation-split (verified deep-async, not assumed). Spawn +
                //   self-capture faithful; internals = "ConversionInfo deep-async closures" sub-unit (P36).
                _ = self
            }
        } else if (state & 1) != 0 {                                       // [tbz #0 bit-test — P38 partial, hand-read + audit]
            delegate?.conversionDidUpdate()
        }
    }

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real
    // init. Structure-only here (P15).
}

/// Coordinator delegate — weak-referenced ⇒ `AnyObject`. 3 instance-method requirements (protocol desc
/// 0x1039f4fa0), witness-anchored via ConversionInfo's forwards (wt 0x1041e0b90 / 0x1041e0b80 call these at
/// witness +0x8 / +0x10 / +0x18 = requirement index 0 / 1 / 2; kinds = Method per conformance_walker).
/// ⚑ req NAMES INFERRED — no in-binary `#function`; the sole conformer is ProAVPlayer (wt 0x1041e1340,
/// stripped) → the names firm up when ProAVPlayer's ConversionInfoDelegate conformance is reconstructed.
protocol ConversionInfoDelegate: AnyObject {
    func conversionDidUpdate()                    // req0 (+0x8)  ⚑ name inferred — from remuxerDidChangeState (odd) forward
    func conversionDidReachEnd()                  // req1 (+0x10) ⚑ name inferred — from demuxerDidReachEnd forward
    func conversionDidFail(_ error: any Error)    // req2 (+0x18) ⚑ name inferred — from demuxerDidFail forward (error arg)
}
