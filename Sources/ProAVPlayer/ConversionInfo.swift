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
    // Session 62 RESOLVED the session-61 `let` refusal for assetTracks / duration /
    // maxBufferDuration / subtitles. Each carried a declaration default that the designated
    // init always overwrites, so the default was never observable and the faithful `let`
    // form is simply to drop it. Proof (default_drop_probe): the class's only non-delegating
    // init assigns all four, from a parameter or an init-local — neither of which a
    // declaration initializer can reference, so the default could not have been the source's.
    // Binding now matches the binary's FieldRecord (flags 0x00000000 = `let`).
    private let assetTracks: [FFmpegAssetTrack]
    private let duration: Double
    private let subtitles: [MediaPlayerTrack]  // existential array (mangle Say…_pG; non-optional)
    // weak optional existential (mangle _pSgXw) → ConversionInfoDelegate (AnyObject). 3 reqs → M2.
    private weak var delegate: ConversionInfoDelegate? = nil
    var demuxerTime: Double = 0   // internal (was private, P34): ProAVPlayer.replaceCurrentItem's item-swap closure reads m3u8Info.demuxerTime cross-file
    private var currentPlaybackTime: Double = 0
    let maxBufferDuration: Double  // internal (was private, P34): ProAVPlayer.conversionDidReachEnd reads m3u8Info.maxBufferDuration cross-file
    // ⚑ binary NON-optional refs (single symref, no Sg); RETIRED from IUO — the designated init assigns all 4.
    let remuxerIOAction: RemuxerIOAction   // internal (was private, P34): ProAVPlayer.replaceCurrentItem reads m3u8Info.remuxerIOAction.startPlayTime cross-file
    let demuxerIO: DemuxerIO
    let server: LocalHLSServer
    private let directoryWatcher: DirectoryWatcher  // KSPlayer (public type fe13053; init→public this pass, P34)

    // MARK: Designated init — `FUN_101b6b2a4` (M2)

    /// `init(server:remuxerIOAction:maxBufferDuration:)` — the coordinator's real designated init
    /// (#function verbatim @0x103d3e0b0; recover_swift_function_name crashes on this addr — a tool bug,
    /// the name is the string literal). Field→offset map disasm/FOV-verified: `delegate` is a 2-word weak
    /// @0x28 (weakInit + `str xzr,[+0x30]`) ⇒ demuxerTime@0x38 … directoryWatcher@0x68, total 0x70 = the
    /// alloc size. Retires the 4 IUO M1 stand-ins with real construction. `formatContext`/`assetTracks`/
    /// `duration` derive from the injected `remuxerIOAction.formatContext` — the binary reads those cross-file
    /// (P34: `formatContext`/`subtitles`/`delegate` broadened `private`→`internal` on RemuxerIOAction, precedent
    /// `startPlayTime`; `DirectoryWatcher.init` `internal`→`public`, cross-module). Field VALUES chased not
    /// flagged (P36/P43 — the "deep" defers were recoverable): assetTracks/duration/subtitles are real reads.
    init(server: LocalHLSServer, remuxerIOAction: RemuxerIOAction, maxBufferDuration: Double) {
        let formatContext = remuxerIOAction.formatContext                          // [ldr x20,[x22,#0x28]]
        self.assetTracks = formatContext.assetTracks                              // *(fc+0x40)   @0x10
        self.duration = formatContext.duration                                    // *(fc+0x28)   @0x18
        self.subtitles = remuxerIOAction.subtitles.map { $0 as MediaPlayerTrack }  // FUN_101b762a0 (per-elem _swift_dynamicCast) @0x20
        self.delegate = nil                                                       // weakInit     @0x28 (2-word weak)
        self.demuxerTime = 0                                                      // @0x38
        self.currentPlaybackTime = 0                                              // @0x40
        self.maxBufferDuration = maxBufferDuration                                // d8           @0x48
        self.remuxerIOAction = remuxerIOAction                                    // @0x50
        self.demuxerIO = DemuxerIO(formatContext: formatContext,                  // FUN_101b6b184 (actor) @0x58
                                   ioAction: remuxerIOAction, delegate: nil)      //   delegate=nil: binary passes x2/x3=0
        self.server = server                                                      // @0x60
        self.directoryWatcher = DirectoryWatcher()                               // FUN_101a04e20 (KSPlayer actor) @0x68  ⚑[tool=resolve_fun_pins ref=FUN_101a04e20:0x101a04e20 result=RESOLVES_UNIQUELY] = KSPlayer.DirectoryWatcher.__allocating_init() -> KSPlayer.DirectoryWatcher
        remuxerIOAction.delegate = self                                          // weak; RemuxerIOActionDelegate wt 0x1041e0b80
        // ⚑ server route install — DEFERRED (owner-phase, binary-read not assumed): the binary registers a
        //   handler on `server` under exclusive access (swift_beginAccess on server+0x20), passing the route
        //   thunk FUN_101b6ba5c and its context box → the request processor FUN_101b68b38.
        // ⚑ CORRECTION (this comment previously said "captures self+server"): the thunk captures self and a
        //   Double, NOT `server`. The whole 3-instruction body is
        //       ldr x1, [x20, #0x10] ; ldr d0, [x20, #0x18] ; b 0x101b68b38
        //   and ctx+0x18 is loaded into an FP register, so it cannot be an object reference. Confirmed twice
        //   more: the box destructor releases ONLY +0x10 (so +0x18 is trivial, not refcounted), and the
        //   capture descriptor reads [ProAVPlayer.ConversionInfo, Swift.Double]. The Double is the init's
        //   maxBufferDuration parameter (the same register stored to self.maxBufferDuration).
        //   `server` is the RECEIVER of the install, not a capture — it is never stored into the box.
        //   ⇒ the deferred handler is shaped `{ [self, maxBufferDuration] (req) in … }`.
        //   ⚑[tool=llvm-objdump ref=FUN_101b6ba5c:0x101b6ba5c result=CAPTURES_SELF_PLUS_DOUBLE]
        //   ⚑[tool=prefetch_decompiles ref=FUN_101b68b38:0x101b68b38 result=LOCATED]
    }

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
                // ⚑ UNRESOLVED — deep-async body. ENTRY is FUN_101b6b7f8 (async-fn-ptr record DAT_1035711c8,
                //   ctxSize 0x20 — the RECORD address is what the task-create helper takes in x3), a 27-instr
                //   trampoline that unpacks the closure box and tail-calls FUN_101b6a530, which sets URL-typed
                //   task-locals and `_swift_task_switch`es to the continuation FUN_101b6a59c — continuation-split
                //   (verified deep-async, not assumed). This comment previously named FUN_101b6a530 as the entry,
                //   which is one hop DOWNSTREAM: nothing in the image ever materialises 0x101b6a530 as a value.
                //   Capture list READ from the box capture descriptor: [Optional<any Actor> (the @isolated(any)
                //   operand of Task.init, the two zero words at box+0x10), ProAVPlayer.ConversionInfo at box+0x20]
                //   ⇒ `Task { [self] in }` is exact and nothing is missing from the spelling below.
                //   Internals = the "ConversionInfo deep-async closures" sub-unit (P36, sibling of DemuxerIO
                //   slot28/30).
                //   ⚑[tool=llvm-objdump ref=FUN_101b6b7f8:0x101b6b7f8 result=TRAMPOLINE_TO_101b6a530]
                _ = self
            }
        }
    }

    /// `FUN_101b69fc4`. The PLAYER-side counterpart to `didUpdateCurrentTime(_:)` — ProAVPlayer's item-swap
    /// closure (`FUN_101b7c460`) + progress method (`FUN_101b7b7e8`) call this with the current playback  ⚑[tool=resolve_fun_pins ref=FUN_101b7b7e8:0x101b7b7e8 result=RESOLVES_UNIQUELY] = ProAVPlayer.ProAVPlayer.changePlaybackTime(time: Swift.Double) -> ()
    /// position. Symmetric to the demuxer side but stores `currentPlaybackTime` (@0x40) and spawns the progress
    /// `Task` only when the un-drained lead `(demuxerTime - remuxerIOAction.startPlayTime) - time` drops BELOW
    /// `maxBufferDuration` (the consumer catching up — the INVERSE of `didUpdateCurrentTime`'s producer test).
    /// Disasm-verified: no `> 0` pre-guard (unlike the demuxer side); the `currentPlaybackTime` store is
    /// guard-scoped (`str d8,[x20,#0x40]` @0x101b6a02c). ⚑ method NAME inferred (P28: `recover_swift_function_name`
    /// = "rcl" KSLog-category red-herring, unrecovered; #file None). The Task's async body is deep → deferred.
    func updateCurrentPlaybackTime(_ time: Double) {
        guard abs(currentPlaybackTime - time) >= 1.0 else { return }   // [ldr d0,[x20,#0x40]; fabd; fcmp #1.0; b.mi @0x101b6a028]
        currentPlaybackTime = time                                     // [str d8,[x20,#0x40] @0x101b6a02c — guard-scoped]
        var start = 0.0
        if let sp = remuxerIOAction.startPlayTime { start = sp }       // [remuxerIOAction@0x50; startPlayTime payload@+0x10/tag@+0x18]
        if (demuxerTime - start) - time < maxBufferDuration {          // [fsub;fsub;fcmp d0,d1(maxBuf);b.pl @0x101b6a05c — Task iff lead < buffer]
            Task { [self] in                                           // [swift_retain self @0x101b6a0a8; swift_task_create via FUN_101b76920 @0x101b6a0c4]
                // ⚑ UNRESOLVED — deep-async body: FUN_101b6b968 (async-fn-ptr @DAT_103571210) trampolines
                //   (`swift_task_alloc` + async-frame) to the continuation FUN_101b6a0e4 — a continuation-split
                //   coroutine (genuinely deep-async). The spawn + strong self-capture are faithful; internals =
                //   the ConversionInfo deep-async closures sub-unit (P36, sibling of didUpdateCurrentTime's FUN_101b6a530).
                //   ⚑[tool=disassemble_function ref=FUN_101b6b968:0x101b6b968 result=LOCATED]
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
                // ⚑ UNRESOLVED — deep-async body. ENTRY is FUN_101b6b8d8 (async-fn-ptr record DAT_1035711e8,
                //   ctxSize 0x20; record taken in x3 of the task-create helper), a 27-instr trampoline that
                //   unpacks the closure box and tail-calls FUN_101b6adc8, which `_swift_task_switch`es to the
                //   continuation FUN_101b6ade0 — continuation-split (verified deep-async, not assumed). This
                //   comment previously named FUN_101b6adc8 as the entry, one hop DOWNSTREAM. Captures READ from
                //   the box capture descriptor: [Optional<any Actor>, ProAVPlayer.ConversionInfo] ⇒ `Task { [self]
                //   in }` is exact. Internals = "ConversionInfo deep-async closures" sub-unit (P36).
                //   NOTE the third, structurally identical Task site in this file already named its trampoline
                //   correctly; these two sites were the inconsistent ones.
                //   ⚑[tool=llvm-objdump ref=FUN_101b6b8d8:0x101b6b8d8 result=TRAMPOLINE_TO_101b6adc8]
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
