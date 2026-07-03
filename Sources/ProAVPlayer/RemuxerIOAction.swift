//
//  RemuxerIOAction.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new remux action (writes HLS segments + the master M3U8).
//  Field types: field-record + decode_composite (deterministic); bodies + the real init → M2.
//  Binary: desc=0x1039f561c, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import CoreMedia   // CMTime `-` operator (CoreMedia overlay; not re-exported through KSPlayer) — performRead PTS→seconds
import Foundation
import KSPlayer
import FFmpegKit

/// Demuxes the source and writes HLS segments + the master M3U8 that LocalHLSServer serves.
/// Forward-new (ProAVPlayer module).
final class RemuxerIOAction: DemuxerIOAction {   // binary conformance (conf@0x103571970, witness-validated); DemuxerIOAction reqs → M2
    // 10 reflection fields (order = layout). Types: field-record-concrete / decode_composite-resolved.
    var startPlayTime: Double? = nil   // internal (was `private`): ConversionInfo.didUpdateCurrentTime reads it directly (FUN_101b6a40c @remuxerIOAction+0x10/+0x18) — cross-file same-module access is binary-arbitrated; modifier under-included (§1/P34-style)
    private var outputStreamInfo: OutputStreamInfo! = nil        // ⚑ binary non-optional; IUO M1 stand-in → M2
    private var formatContext: FormatContext! = nil             // ⚑ binary non-optional; IUO M1 stand-in → M2
    private var dir: URL! = nil                                 // ⚑ binary non-optional (symref); decompile: URL; IUO M1 stand-in → M2
    private var subtitles: [FFmpegAssetTrack] = []
    private weak var delegate: RemuxerIOActionDelegate? = nil   // weak optional (mangle _pSgXw)
    private var formatContextOptions: [String: Any] = [:]
    private var masterM3U8Context: String = ""
    private var packet: UnsafeMutablePointer<AVPacket>? = nil
    private var directoryWatcher: DirectoryWatcher! = nil       // ⚑ binary non-optional; KSPlayer (now public); IUO M1 stand-in → M2

    // ── Designated init VERIFIED (FUN_101b81b18, 351i, cached + disasm-read) — reachable via the alloc site
    //    FUN_101b6e31c (swift_allocObject(RemuxerIOAction metadata) → self=x21 → bl 0x101b81b18). `throws`
    //    (the outputStreamInfo build can throw → the error path `_swift_deallocPartialClassInstance`).
    //    ABI: self=x20; x0..x5 = param_1..param_6. Verified field construction:
    //      formatContext (@0x28) ← param_1 (retained)                         [clean, grounded]
    //      dir           ← URL(param_2)  (URL value-witness init-copy)         [clean, grounded]
    //      formatContextOptions ← param_4  ([String:Any], bridged)            [clean, grounded]
    //      masterM3U8Context    ← String(param_5, param_6)                    [clean, grounded]
    //      packet        ← av_packet_alloc()  (FUN_102d61878)                 [clean, grounded]
    //      startPlayTime = nil (str xzr@+0x10 + tag=1@+0x18) ; delegate = nil (weak init)   [clean, grounded]
    //      directoryWatcher ← FUN_101a04e20(…)  (KSPlayer DirectoryWatcher construction)    [args UNRESOLVED]
    //      outputStreamInfo ← FUN_101b8559c(formatContext, dir, options, master)  ⚑ OutputStreamInfo
    //          factory — OWNER-PHASE devirt API (blocked; not fabricated, P32/P23)
    //      subtitles ← flatMap over param_3's tracks (FUN_101a36488 + keyPath + Sequence.flatMap +
    //          outputStreamInfo.<+0xb8>)  ⚑ complex — deferred
    //    COMPILING reconstruction BLOCKED on 3 verified residuals → deferred:
    //      1. param_3 TYPE — a deep up-chain field `*(coordinator+0x420)` (FUN_101b6e31c ← FUN_101b6e2d0);
    //         the subtitles/track source. Un-named without further up-chain tracing.
    //      2. outputStreamInfo factory (FUN_101b8559c) = OutputStreamInfo devirt API — unblocks when
    //         OutputStreamInfo (1C.6) is reconstructed.
    //      3. subtitles flatMap (complex).
    //    ⇒ the 4 IUO stand-ins (outputStreamInfo/formatContext/dir/directoryWatcher) stay IUO until the
    //    compiling init lands (needs param_3's type + OutputStreamInfo's API). NAME/param-LABELS inferred
    //    (recover_swift_function_name = jel/None, labels=0).

    /// Result of `performRead(formatCtx:)`. Layout compile-oracle-CONFIRMED (16 bytes): `value` @0 (8B),
    /// `isEnd` @8, `isError` @9. The binary assembles the status half-word as `isEnd | (isError << 8)`
    /// (FUN_101b823b8 L385: `auVar24._8_4_ = uVar18 & 0xff | iVar12 << 8`), so byte 8 = isEnd (`uVar18`),
    /// byte 9 = isError (`iVar12`) — traced from the branch stores, NOT hand-partitioned:
    ///   • packet==nil  → isEnd=0, isError=1, value=0xffffffff (the -1 sentinel)  [L108-110]
    ///   • av_read_frame != 0 → isEnd=0, isError=1, value=status                   [L380-382]
    ///   • read ok      → isError=0 (L377); isEnd=0 with value=seconds, OR isEnd=1 with value=0 (skip/EOF).
    /// Semantics (from the caller): isError → `value` holds an Int32 error code; isEnd → end-of-stream/skip;
    /// both false → ok, `value` = Double seconds.
    /// ⚑ struct-vs-tuple: layout-identical; picked `struct` (P-choice). ⚑ Field NAMES (value/isEnd/isError)
    ///   INFERRED (not binary-recoverable). ⚑ Type NAME `ReadResult` INFERRED (not binary-recoverable).
    ///   ⚑ Nested in RemuxerIOAction (vs top-level in DemuxerIO.swift) is a placement choice — the protocol
    ///   req references it as `RemuxerIOAction.ReadResult`.
    /// The `enum { ok(Double); endOfStream; failed(Int32) }` candidate was DISPROVEN (Swift packs that tag in
    /// ONE byte; the binary uses two).
    struct ReadResult {
        var value: Double   // @0  — seconds (ok) OR Int32 error-code bits reinterpreted (error)
        var isEnd: Bool     // @8  — end-of-stream / skip
        var isError: Bool   // @9  — read failed; `value` carries the code
    }

    /// Binary: FUN_101b823b8. Name `performRead(formatCtx:)` recovered high-confidence; the impl of the
    /// `DemuxerIOAction.performRead` requirement. NON-throwing (0 throw machinery here; the actor-side
    /// `DemuxerIO.slot29` `throws(Int32)` wrapper is the thrower — out of scope).
    ///
    /// ⚑ `formatCtx` (x0 = `param_1`) vs `self.formatContext` (@0x28): the two are DISTINCT. `formatCtx` is
    ///   handed straight to `av_read_frame` (FUN_1030e6e78), which treats it as a raw C `AVFormatContext*`
    ///   (fields +0x10/+0x3d/+0x08…) → param type INFERRED `UnsafeMutablePointer<AVFormatContext>`. The
    ///   PTS→seconds stream lookup instead walks `self.formatContext`'s streams (`*(self+0x28)+0x40`), i.e.
    ///   the Swift `FormatContext` wrapper's assetTracks/streams. Faithful to the cache; the exact source-level
    ///   spelling of what the caller forwards (likely `self.formatContext.formatCtx`) is walled → M2.
    ///
    /// Reconstructs the control flow, the av_read_frame call, PTS→seconds, the outputStreamInfo write, the
    /// startPlayTime record, and the return struct. KSLog debug/error forms kept UNRESOLVED (class-wide).
    func performRead(formatCtx: UnsafeMutablePointer<AVFormatContext>) -> ReadResult {
        // [L106-110] No packet allocated → error result with the -1 (0xffffffff) sentinel.
        guard let packet = self.packet else {
            // isEnd=false, isError=true, value = the 0xffffffff sentinel (Int32(-1) bits).
            return ReadResult(value: Double(bitPattern: 0xffff_ffff), isEnd: false, isError: true)
        }

        // [L113] av_read_frame(formatCtx, packet) — FUN_1030e6e78 wraps FFmpeg's av_read_frame (returns Int32).
        let status = av_read_frame(formatCtx, packet)   // ⚑ FUN_1030e6e78; call name/arg-order decompile-grounded
        // [L379-382] Non-zero → error result carrying the status code. isEnd=false, isError=true.
        guard status == 0 else {
            return ReadResult(value: Double(bitPattern: UInt64(UInt32(bitPattern: status))), isEnd: false, isError: true)
        }

        // ── read ok ──────────────────────────────────────────────────────────────────────────────────
        // [L115] streamIndex = packet.pointee.stream_index (AVPacket +0x24).
        let streamIndex = packet.pointee.stream_index

        // [L116-122] pts = the packet's presentation stamp, defaulting to the "no value" sentinel
        //   (AV_NOPTS_VALUE = -0x8000000000000000): prefer dts (+0x10 = plVar17[2]) then override with
        //   pts (+0x08 = plVar17[1]) when each is not the sentinel — so pts wins when present, else dts,
        //   else 0. (Binary computes an Int64 `lVar1`.)
        var pts: Int64 = 0
        if packet.pointee.dts != .min { pts = packet.pointee.dts }   // plVar17[2] (+0x10)
        if packet.pointee.pts != .min { pts = packet.pointee.pts }   // plVar17[1] (+0x08); pts overrides dts

        // [L123-194] PTS→seconds over self.formatContext's streams (FUN_101a32e28), gated by an
        //   index-match + a String compare on the matched stream.
        // ⚑ STREAM-MATCH PARTITION — hand-derived (P31). The caller pre-walks self.formatContext's stream
        //   array (`*(self+0x28)+0x40`) [L123-181]; for the stream whose `stream.index (+0x10) == streamIndex`
        //   it performs TWO `String.__unconditionallyBridgeFromObjectiveC()` bridges + a
        //   `_stringCompareWithSmolCheck` [L162-177]. The two bridged String operands are passed in registers
        //   the decompile does not surface, so WHICH strings are compared is NOT traceable → NOT reconstructed
        //   (cardinal-failure avoidance). Observable partition of the outcome:
        //     • strings EQUAL  (L166 `SVar25 == SVar26`, or compare-true L177) → `LAB_101b825b4`: skip/EOF
        //       result (value=0, isEnd=1).
        //     • strings differ (compare-false, L176)                          → `LAB_101b824ec`: compute
        //       seconds via FUN_101a32e28.
        //   No index match anywhere also falls through to `LAB_101b824ec` [L183-186].
        // FUN_101a32e28 (PTS→seconds): re-walk streams, find `stream.index == streamIndex`, then
        //   `CMTime(value: pts * stream.timebase.num (+0xc0), timescale: stream.timebase.den (+0xc4))
        //    - stream.startTime (+0xa0..+0xb0)`, take `.seconds`, clamp to >= 0. Its second return lane is a
        //   flag (1 = "no match / sentinel pts" → treated as skip/EOF). [FUN_101a32e28 L72-96 / L103-104]
        var value: Double
        var isEnd: Bool
        // ⚑ The seconds computation + the skip/EOF flag are produced together (FUN_101a32e28 returns
        //   (Double, flag); flag==1 ⇒ isEnd). Modeled here as the PTS→seconds helper below.
        (value, isEnd) = ptsToSeconds(streamIndex: streamIndex, pts: pts)

        // [L197-278] Debug log on the ok path: "packet index=…, size=…, flags=…, timestamp=…, duration=…"
        //   (fields: streamIndex, size=(Int32)plVar17[4], flags=(Int32)plVar17[5], timestamp=pts, duration=plVar17[8]).
        //   Gated by a log-level check (FUN_1019b4074 → `*pbVar7 > 2`).
        // ⚑ KSLog(...) — form UNRESOLVED (class-wide). Debug packet-trace omitted.

        // [L279-283] Write the packet through outputStreamInfo (vtable method @+0x118), returning an Int32.
        // ⚑ outputStreamInfo write UNRESOLVED: the binary calls `(*(*(self+0x20)+0x118))(packet, 0, 0)` — a
        //   vtable slot (+0x118) on `self.outputStreamInfo` (@0x20) whose Swift method NAME/SIGNATURE is
        //   devirtualized (OutputStreamInfo's substantive methods are documented UNRESOLVED). NOT emitting a
        //   live `outputStreamInfo.<write>(packet)` here — that would fabricate an OutputStreamInfo API AND
        //   fail to compile. The call returns an Int32 error code; modeled as a neutral `0` (success) so the
        //   traced error-gate below is preserved without inventing the callee.
        let writeStatus: Int32 = 0   // ⚑ UNRESOLVED — outputStreamInfo vtable +0x118 write; return code stubbed 0

        // [L285-286] Error-log gate on the write's return: code == -0x7265636f (a FourCC-form AVERROR),
        //   or code == -0x16 (EINVAL) when pts is absent (lVar1==0 ⇒ pts==0 here).
        if writeStatus == -0x7265_636f || (writeStatus == -0x16 && pts == 0) {
            // [L287-364] ⚑ KSLog(...) — form UNRESOLVED (class-wide). Error packet-trace log omitted
            //   ("…index=…, size=…, flags=…, timestamp=…, duration=…" with the write's error code).
            // [L365] Helper call (FUN_101b7e2f4) — RemuxerIOAction internal (rebuild/reset side effect).
            // ⚑ FUN_101b7e2f4 effect UNRESOLVED (own reconstruction unit); NOT invented.
            reconstruct(completion: nil)   // FUN_101b7e2f4(0,0) = nil completion; name RECOVERED (was fabricated `performReadErrorRecovery`)
            // [L366-370] Re-issue the outputStreamInfo write once after recovery.
            // ⚑ UNRESOLVED — second outputStreamInfo vtable +0x118 write (same slot); NOT emitted (see above).
        }

        // [L372-374] Record startPlayTime on the first non-skip packet: if not isEnd AND startPlayTime is
        //   still nil (tag byte @0x18 == 1), set startPlayTime = value (payload @0x10; tag ← isEnd == 0 ⇒ .some).
        if !isEnd, startPlayTime == nil {
            startPlayTime = value
        }

        // [L376] av_packet_unref(packet) — FUN_102d61970.
        av_packet_unref(packet)   // ⚑ FUN_102d61970

        // [L377,385-388] Return: isError=false on the ok path; isEnd + value as computed above.
        return ReadResult(value: value, isEnd: isEnd, isError: false)
    }

    /// PTS→seconds for the asset track matching `streamIndex`, plus the not-found/skip flag.
    /// Binary FUN_101a32e28 (a shared leaf, 2 callers; `self` = RemuxerIOAction via the inherited swiftself x20 —
    /// no `mov x20` at the call site — linker-placed in the base __text range). Reconstructed on the EXISTING
    /// KSPlayer API (P19 — source is ground truth): iterate `self.subtitles` (`self+0x40` = the sole
    /// `[FFmpegAssetTrack]` field), match `track.trackID (@+0x10) == streamIndex`, compute
    /// `(track.timebase.cmtime(for: pts) - track.startTime).seconds` (== the binary's
    /// `CMTime(value: pts*num@0xc0, timescale: den@0xc4) - startTime@0xa0`), clamp ≥ 0. `pts == AV_NOPTS_VALUE`
    /// or no match ⇒ `(0, isEnd=true)`. The `timebase`/`startTime`/`cmtime(for:)` reads cross the
    /// ProAVPlayer→KSPlayer module boundary (binary-arbitrated) → made `package` in KSPlayer (§1 modifier flagged).
    /// ⚑ iterated array `subtitles` is offset-derived (self+0x40, the only `[FFmpegAssetTrack]`); ⚑ helper NAME
    ///   inferred (no #function on FUN_101a32e28).
    private func ptsToSeconds(streamIndex: Int32, pts: Int64) -> (value: Double, isEnd: Bool) {
        guard pts != .min else { return (0, true) }                  // AV_NOPTS_VALUE (Int64.min) [FUN_101a32e28 L36,103]
        for track in subtitles where track.trackID == streamIndex {  // index match @+0x10 [L48-72]
            let seconds = (track.timebase.cmtime(for: pts) - track.startTime).seconds  // [L74-96]
            return (max(seconds, 0), false)                          // clamp >= 0 [L92-95]
        }
        return (0, true)                                             // no match ⇒ skip/EOF [L103-104]
    }

    /// Error-recovery on the write-error path — FUN_101b7e2f4. Name `reconstruct(completion:)` RECOVERED
    /// (recover_swift_function_name, high conf, #file ProAVPlayer/RemuxerIO.swift); the agent's earlier
    /// `performReadErrorRecovery` was a FABRICATED name (P28/P30) — corrected here. Body UNRESOLVED (own unit):
    ///   rebuilds/resets state (subtitles/dir/formatContextOptions/masterM3U8Context, resets startPlayTime,
    ///   drives outputStreamInfo vtable slots +0xb0/+0xb8/+0x128, re-creates @0x20 via FUN_101b8559c, notifies
    ///   the delegate). ⚑ completion type + access level UNRESOLVED (own unit); performRead passes a nil closure.
    private func reconstruct(completion: (() -> Void)?) {
        // ── Body DEFERRED to owner-phase (blocked on OutputStreamInfo's devirt API + RemuxerIOActionDelegate).
        //    Grounded control flow from FUN_101b7e2f4 (239i; prefetch-cached + disasm-verified — NOT live code, to
        //    avoid fabricating the OutputStreamInfo interface / mis-placing the swifterror-guarded resets, P32/P36):
        //    1. [KSLog debug gate: `if logLevel > 2` (FUN_1019b4074) — form UNRESOLVED, class-wide]
        //    2. Tear down the current output — THROWING devirt calls on self.outputStreamInfo (@0x20):
        //       `<+0xb0>()` ; `<+0xb8>([])` ; `<+0x128>()`  (OutputStreamInfo vtable; owner-phase API — not fabricated).
        //    3. Rebuild: `let new = <OutputStreamInfo build>(formatContext@0x28, dir, formatContextOptions,
        //       masterM3U8Context)` via FUN_101b8559c — throwing.
        //    4. guard(no swifterror from 2–3 — `cbz x21` @0x101b7e4ec) else early-out (bridgeObjectRelease). No-error path:
        //         `self.outputStreamInfo = new` (release old) ; `new.<+0xb8>(old)`
        //         `for track in subtitles { <per-element FUN_101a20fb0> }`   // iteration recoverable; per-element UNRESOLVED
        //         `startPlayTime = nil`                                       // str xzr@+0x10 + tag=1@+0x18 (disasm-confirmed; no-error path ONLY)
        //         `if completion == nil { delegate?.<notify>(2) }`           // weak RemuxerIOActionDelegate req (undeclared) — UNRESOLVED
        //         `Task { completion?() }`                                   // async completion spawn (FUN_101b76920, &DAT_103571988) — UNRESOLVED
    }

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real init.
}

/// Remux action delegate — weak-referenced ⇒ `AnyObject`. 1 instance-method requirement (protocol desc
/// 0x1039f55f0), witness-anchored via ConversionInfo's conformance (wt 0x1041e0b80 → FUN_101b6aca8; kind
/// Method per conformance_walker). ⚑ req NAME + arg TYPE INFERRED — no `#function`, and no ProAVPlayer enum
/// for the arg (build_module_classmap: only State/Event, both DemuxerIO-parented) → primitive `Int` (the
/// binary reads a byte; `reconstruct(completion:)` signals `2`, the witness special-cases `2` vs an odd value).
protocol RemuxerIOActionDelegate: AnyObject {
    func remuxerDidChangeState(_ state: Int)
}
