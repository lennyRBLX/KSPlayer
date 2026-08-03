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
    private var outputStreamInfo: OutputStreamInfo             // binary non-optional — RETIRED from IUO (init assigns via Self.write; reconstruct() reassigns)
    let formatContext: FormatContext                          // internal (was private, P34): ConversionInfo.init reads it cross-file for assetTracks/duration/DemuxerIO; binary non-optional — RETIRED from IUO (init assigns = param_1)
    private let dir: URL                                      // binary non-optional (symref; decompile: URL) — RETIRED from IUO (init assigns = param_2)
    let subtitles: [FFmpegAssetTrack] = []                    // internal (was private, P34): ConversionInfo.init maps it → its own subtitles
    weak var delegate: RemuxerIOActionDelegate? = nil          // internal (was private, P34): ConversionInfo.init sets it = self; weak optional (mangle _pSgXw)
    // Session 62 RESOLVED the session-61 `let` refusal for all three. formatContextOptions and
    // masterM3U8Context are assigned from PARAMETERS, so their defaults were never observable
    // and the faithful `let` form drops them. `packet` went the other way — see its declaration
    // below: the binary's store sits in the default-materialization prologue, so the
    // initializer belongs ON the declaration and the init assignment was the artifact.
    private let formatContextOptions: [String: Any]
    private let masterM3U8Context: String
    // `packet`: session 62 resolved the session-61 `let` refusal. The binary's init allocates
    // the packet (L70-72) INSIDE the default-materialization prologue — the stores at L64-76
    // are exactly the non-param fields, emitted in DECLARATION order (startPlayTime@19,
    // delegate@24, packet@33, directoryWatcher@34) ahead of every param-derived store
    // (formatContext L77 … masterM3U8Context L84-86). A declaration default is what the
    // compiler emits there, so the initializer belongs on the declaration and the old
    // `= nil` was the artifact. `let x: T?` + an init store emits the same alloc, so this is
    // an ORDER argument, not a store-presence one.
    // ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED]
    private let packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    private let directoryWatcher: DirectoryWatcher! = nil       // ⚑ binary non-optional; KSPlayer (now public); IUO M1 stand-in → M2

    /// Designated init — binary `FUN_101b81b18` (351i, cached + disasm-read; reachable via the alloc site
    /// FUN_101b6e31c → swift_allocObject → bl 0x101b81b18). Constructs the fields then builds
    /// `outputStreamInfo` via `write()` (NOW LIVE — the OSI init landed 21c9d6a). `throws` — write() can
    /// throw → the binary's error path is `_swift_deallocPartialClassInstance` (L205-219).
    /// ⚑ signature devirt-inferred (recover = jel/None, labels=0): param_1=formatContext, param_2=dir,
    ///   param_4=formatContextOptions, {param_5,param_6}=masterM3U8Context — GROUNDED. `source` = param_3 is
    ///   the subtitles/track source — an up-chain-UN-TYPED class (`*(coordinator+0x420)`; it has a `+0x768`
    ///   vtable method + a tracks keyPath) → typed `AnyObject` (under-included, §1) + its uses DEFERRED.
    /// ⚑ DEFERRED (L97-203, own follow-up unit): `subtitles` = flatMap over `source`'s tracks (keyPath +
    ///   Sequence.flatMap); the post-write `outputStreamInfo.<slot1 +0xb8>(FUN_101a36488(source))` +  ⚑[tool=resolve_fun_pins ref=FUN_101a36488:0x101a36488 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.subtitleAssetTrackMap(options: KSPlayer.KSOptions) -> [Swift.Int32 : KSPlayer.FFmpegAssetTrack]
    ///   `source.<+0x768>()` + the subtitles iteration. `directoryWatcher` construction (FUN_101a06ce0 /  ⚑[tool=resolve_fun_pins ref=FUN_101a06ce0:0x101a06ce0 result=RESOLVES_UNIQUELY] = type metadata accessor for KSPlayer.DirectoryWatcher
    ///   FUN_101a04e20 args UNRESOLVED) → stays IUO default. `subtitles` stays [].  ⚑[tool=resolve_fun_pins ref=FUN_101a04e20:0x101a04e20 result=RESOLVES_UNIQUELY] = KSPlayer.DirectoryWatcher.__allocating_init() -> KSPlayer.DirectoryWatcher
    init(formatContext: FormatContext, dir: URL, source: AnyObject,
         formatContextOptions: [String: Any], masterM3U8Context: String) throws {
        self.startPlayTime = nil                              // L64-65 (payload 0, tag 1 = nil)
        // delegate stays nil (weak init, L66-69); directoryWatcher stays nil IUO (L73-76 ctor args UNRESOLVED)
        // packet: allocated by its DECLARATION default (binary L70-72); see the declaration
        // for the marker and for why that store is the prologue's, not this init's.
        self.formatContext = formatContext                    // L77 (@0x28 = param_1, retained)
        self.dir = dir                                        // L78-81 (URL value-witness init-copy of param_2)
        self.formatContextOptions = formatContextOptions      // L82-83 (param_4)
        self.masterM3U8Context = masterM3U8Context            // L84-86 ({param_5, param_6})
        self.outputStreamInfo = try Self.write(formatContext: formatContext, dir: dir,   // L92 (throws → dealloc on throw)
                                               formatContextOptions: formatContextOptions,
                                               masterM3U8Context: masterM3U8Context)
        // ⚑ DEFERRED — subtitles flatMap + the post-write source/OSI interactions (L97-203); source uses deferred.
        _ = source
    }

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

        // [L123-194] PTS→seconds over self.formatContext's streams (FUN_101a32e28), gated by an  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
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
        //       seconds via FUN_101a32e28.  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
        //   No index match anywhere also falls through to `LAB_101b824ec` [L183-186].
        // FUN_101a32e28 (PTS→seconds): re-walk streams, find `stream.index == streamIndex`, then  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
        //   `CMTime(value: pts * stream.timebase.num (+0xc0), timescale: stream.timebase.den (+0xc4))
        //    - stream.startTime (+0xa0..+0xb0)`, take `.seconds`, clamp to >= 0. Its second return lane is a
        //   flag (1 = "no match / sentinel pts" → treated as skip/EOF). [FUN_101a32e28 L72-96 / L103-104]  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
        var value: Double
        var isEnd: Bool
        // ⚑ The seconds computation + the skip/EOF flag are produced together (FUN_101a32e28 returns  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
        //   (Double, flag); flag==1 ⇒ isEnd). Modeled here as the PTS→seconds helper below.
        (value, isEnd) = ptsToSeconds(streamIndex: streamIndex, pts: pts)

        // [L197-278] Debug log on the ok path: "packet index=…, size=…, flags=…, timestamp=…, duration=…"
        //   (fields: streamIndex, size=(Int32)plVar17[4], flags=(Int32)plVar17[5], timestamp=pts, duration=plVar17[8]).
        //   Gated by a log-level check (FUN_1019b4074 → `*pbVar7 > 2`).  ⚑[tool=resolve_fun_pins ref=FUN_1019b4074:0x1019b4074 result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.logLevel.unsafeMutableAddressor : KSPlayer.LogLevel
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
            // `mov x0,#0 ; mov x1,#0` = closure fn ptr AND context both zero = the Optional<() -> Void> nil
            // form ⇒ `completion: nil`. `mov x21,#0` initialises the swifterror slot — emitted only for a
            // throwing callee. On return `cbz x21` then a call to swift_errorRelease (GOT 0x104112E48), and
            // control falls through either way: the error is CAUGHT AND DISCARDED, so this is `try?`.
            try? reconstruct(completion: nil)
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
    /// Binary FUN_101a32e28 (a shared leaf, 2 callers; `self` = RemuxerIOAction via the inherited swiftself x20 —  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
    /// no `mov x20` at the call site — linker-placed in the base __text range). Reconstructed on the EXISTING
    /// KSPlayer API (P19 — source is ground truth): iterate `self.subtitles` (`self+0x40` = the sole
    /// `[FFmpegAssetTrack]` field), match `track.trackID (@+0x10) == streamIndex`, compute
    /// `(track.timebase.cmtime(for: pts) - track.startTime).seconds` (== the binary's
    /// `CMTime(value: pts*num@0xc0, timescale: den@0xc4) - startTime@0xa0`), clamp ≥ 0. `pts == AV_NOPTS_VALUE`
    /// or no match ⇒ `(0, isEnd=true)`. The `timebase`/`startTime`/`cmtime(for:)` reads cross the
    /// ProAVPlayer→KSPlayer module boundary (binary-arbitrated) → made `package` in KSPlayer (§1 modifier flagged).
    /// ⚑ iterated array `subtitles` is offset-derived (self+0x40, the only `[FFmpegAssetTrack]`); ⚑ helper NAME
    ///   inferred (no #function on FUN_101a32e28).  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
    private func ptsToSeconds(streamIndex: Int32, pts: Int64) -> (value: Double, isEnd: Bool) {
        guard pts != .min else { return (0, true) }                  // AV_NOPTS_VALUE (Int64.min) [FUN_101a32e28 L36,103]  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
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
    ///   drives outputStreamInfo vtable slots +0xb0/+0xb8/+0x128, re-creates @0x20 via self.write() [FUN_101b8559c], notifies
    ///   the delegate). ⚑ completion type + access level UNRESOLVED (own unit); performRead passes a nil closure.
    /// `throws` — PROVEN three independent ways, do not "simplify" it away:
    ///   (a) ABI: the prologue saves x28,x27,x26,x25,x24,x23,x22,x20,x19,x29,x30 and NOT x21, yet the body
    ///       clobbers x21. Only the swifterror register may be clobbered unsaved in the x19-x28 range.
    ///   (b) rethrow: `mov x21,x25` re-supplies swifterror to write(); `mov x25,x21` captures it back —
    ///       overwriting the "saved" copy, which a callee-save shuffle would never do — and the epilogue
    ///       `mov x21,x25` returns WITH it. There is no `mov x21,#0` anywhere in the body, so the error is
    ///       never swallowed.
    ///   (c) both call sites emit `mov x21,#0` before the `bl` and test x21 after: performRead (-> the error
    ///       is released, i.e. `try?`) and the async funclet at 0x101b6a138 (-> propagates).
    /// NOT `async` (plain stp x29,x30 frame + `ret`; no async-frame marker) and returns Void.
    /// The NAME is ground truth, not inferred: the KSLog call passes #function = "reconstruct(completion:)"
    /// and #file = "ProAVPlayer/RemuxerIO.swift" (so this type's Swift file is misnamed), #line = 347.
    /// ⚑ CORRECTIONS to the doc below, which had two errors: the OutputStreamInfo +0xb0/+0xb8/+0x128 calls
    ///   are NON-throwing (x21 carries the callee ADDRESS across each `blr` and no error test follows —
    ///   `write()` is the only throwing callee), and the `cbz x21` is a RETHROW, not an early-out.
    private func reconstruct(completion: (() -> Void)?) throws {
        // ── Body DEFERRED to owner-phase (blocked on OutputStreamInfo's devirt API + RemuxerIOActionDelegate).
        //    Grounded control flow from FUN_101b7e2f4 (239i; prefetch-cached + disasm-verified — NOT live code, to
        //    avoid fabricating the OutputStreamInfo interface / mis-placing the swifterror-guarded resets, P32/P36):
        //    1. [KSLog debug gate: `if logLevel > 2` (FUN_1019b4074) — form UNRESOLVED, class-wide]  ⚑[tool=resolve_fun_pins ref=FUN_1019b4074:0x1019b4074 result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.logLevel.unsafeMutableAddressor : KSPlayer.LogLevel
        //    2. Tear down the current output — THROWING devirt calls on self.outputStreamInfo (@0x20):
        //       `<+0xb0>()` ; `<+0xb8>([])` ; `<+0x128>()`  (OutputStreamInfo vtable; owner-phase API — not fabricated).
        //    3. Rebuild: `let new = try self.write(formatContext:dir:formatContextOptions:masterM3U8Context:)`
        //       [FUN_101b8559c] — throwing; write() sets up the HLS output + builds the OSI via the real
        //       factory FUN_101a1d014 (see the write() grounded-doc at the end of the class). NOT a raw
        //       "OutputStreamInfo build" — same mislabel, CORRECTED.
        //    4. guard(no swifterror from 2–3 — `cbz x21` @0x101b7e4ec) else early-out (bridgeObjectRelease). No-error path:
        //         `self.outputStreamInfo = new` (release old) ; `new.<+0xb8>(old)`
        //         `for track in subtitles { <per-element FUN_101a20fb0> }`   // iteration recoverable; per-element UNRESOLVED  ⚑[tool=resolve_fun_pins ref=FUN_101a20fb0:0x101a20fb0 result=RESOLVES_UNIQUELY] = KSPlayer.FFmpegAssetTrack.flush() -> ()
        //         `startPlayTime = nil`                                       // str xzr@+0x10 + tag=1@+0x18 (disasm-confirmed; no-error path ONLY)
        //         `if completion == nil { delegate?.<notify>(2) }`           // weak RemuxerIOActionDelegate req (undeclared) — UNRESOLVED
        //         `Task { completion?() }`                                   // async completion spawn (FUN_101b76920, &DAT_103571988) — UNRESOLVED
    }

    /// `DemuxerIOAction.cancel()` requirement impl — binary `FUN_101b82c04` (self=RemuxerIOAction,
    /// field-access-confirmed: `outputStreamInfo`@0x20 + the `RemuxerIOAction.packet` offset). Driven by
    /// `DemuxerIO.cancelReading` on `ioAction` (witness deleted → devirt). No-arg, `Void`, non-throwing (P44:
    /// plain-`ret` epilogue; the FileManager error is caught + logged internally). ⚑ NAME `cancel()` inferred
    /// (recover_swift_function_name = None). RECONSTRUCTED (later·62): OutputStreamInfo's slot14/15
    /// (finishWriting/close) are now reconstructed + OSI is non-final, so they dispatch through the OSI vtable
    /// (+0x120/+0x128) exactly as the binary does.
    func cancel() {
        outputStreamInfo.finishWriting()             // OSI vtable +0x120 = slot14 (drain + av_write_trailer) [retain/call/release]
        outputStreamInfo.close()                     // OSI vtable +0x128 = slot15 (close-all)
        var p = packet                               // binary loads self.packet into a local (local_50)…
        av_packet_free(&p)                           // …and frees the LOCAL — FUN_102d618b8, ffmpeg_name_oracle CONFIRMED av_packet_free (46/184 exact). ⚑ self.packet is NOT nulled (no writeback) — faithful to the binary's local-copy free.
        do {
            try FileManager.default.removeItem(at: dir)   // NSFileManager.removeItemAtURL(dir._bridgeToObjectiveC()) — removes the output
        } catch {
            // ⚑ on failure: KSLog(error) gated `logLevel > 1` (FUN_1019b4074 → `*level < 2` skips the log, just  ⚑[tool=resolve_fun_pins ref=FUN_1019b4074:0x1019b4074 result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.logLevel.unsafeMutableAddressor : KSPlayer.LogLevel
            //   releases the error) — KSLog form UNRESOLVED (class-wide); the error is caught + swallowed (cancel does NOT throw).
        }
    }

    /// `write(formatContext:dir:formatContextOptions:masterM3U8Context:)` — binary `FUN_101b8559c`
    /// (recover_swift_function_name HIGH, 4 labels, #file ProAVPlayer/RemuxerIO.swift). The OSI-PRODUCING
    /// method both the designated init and reconstruct() call: sets up the HLS output dir, writes the master
    /// playlist, configures the HLS segment-filename muxer option, then builds + returns the OutputStreamInfo
    /// via its real designated init (thunk FUN_101a19724 → factory FUN_101a1d014). `throws -> OutputStreamInfo`  ⚑[tool=resolve_fun_pins ref=FUN_101a19724:0x101a19724 result=RESOLVES_UNIQUELY] = static KSPlayer.FFmpegUtility.write(formatContext: KSPlayer.FormatContext, to: Swift.String, isMergeStream: Swift.Bool, formatContextOptions: [Swift.String : Any]?, outFormat: Swift.String?, mediaType: __C.AVMediaType?, allowAudioCodecs: [__C.AVCodecID]?) throws -> KSPlayer.OutputStreamInfo
    /// — P44 disasm-confirmed (reconstruct() does `str x0,[x23,#0x20]` = store the return into
    /// outputStreamInfo@0x20). No FFmpeg calls (verified: 0 `bl` in the FFmpeg range). NOW LIVE (the OSI init
    /// landed 21c9d6a). ⚑ flagged-compiling residuals: the OSI filename is `FUN_1019f59c4`-computed  ⚑[tool=resolve_fun_pins ref=FUN_1019f59c4:0x1019f59c4 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Foundation.URL.ffmpegString.getter : Swift.String
    /// (approximated as dir/playlist_%v.m3u8); the factory's p9 = a static `[AVCodecID]` allowlist
    /// (&DAT_1044f3788) passed `[]` here; the exact options-dict threading is decompiler-plumbing-approximate;
    /// KSLog debug (L194-214) omitted (class-wide UNRESOLVED).
    /// `static` — FUN_101b8559c reads NO self (0 `unaff_x20` / swiftself field-loads; all 5 inputs are params),
    /// so it is a type method the init + reconstruct() call as `Self.write(…)`.
    static func write(formatContext: FormatContext, dir: URL, formatContextOptions: [String: Any],
                      masterM3U8Context: String) throws -> OutputStreamInfo {
        // 1. remove any existing output dir — error SWALLOWED (willThrow→errorRelease→swifterror cleared ⇒ try?) [L126-133]
        try? FileManager.default.removeItem(at: dir)
        // 2. create the output dir — error PROPAGATES (convertNSError→willThrow, NO errorRelease ⇒ throws) [L139-145]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 3. base = dir path, trailing-slash-normalized [L150-163]
        var base = dir.path
        if !base.hasSuffix("/") { base += "/" }
        // 4. HLS segment-filename muxer option (key "hls_segment_filename" @0x103d3e9f0, value = base + the .ts
        //    segment pattern @0x103d3ea10) [L168-179]. ⚑ the exact dict threaded into the OSI (the mutated copy
        //    vs the original param_3) is decompiler-plumbing-ambiguous; reconstructed as the augmented options
        //    (HLS muxing needs the segment pattern). The formatContextOptions["hls_segment_type"]=="fmp4" check
        //    [L217-239] feeds the OSI's removeADTS, not write() itself.
        var options = formatContextOptions
        options["hls_segment_filename"] = base + "segment_%v_%05d.ts"
        // 5. write the master playlist ("master.m3u8" @0x103d3ea?, atomically, .utf8) [L183-190]
        try masterM3U8Context.write(to: dir.appendingPathComponent("master.m3u8"), atomically: true, encoding: .utf8)
        // 6. KSLog debug gate (logLevel > 2, FUN_1019b4074) — form UNRESOLVED (class-wide) [L194-214]  ⚑[tool=resolve_fun_pins ref=FUN_1019b4074:0x1019b4074 result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.logLevel.unsafeMutableAddressor : KSPlayer.LogLevel
        // 7. build + return the OSI via its real designated init [L244-247]
        let filename = dir.appendingPathComponent("playlist_%v.m3u8").ffmpegString   // ⚑ was `.path` (approximated); the call at 0x101b85b60 is ffmpegString, now reconstructed  ⚑[tool=resolve_fun_pins ref=FUN_1019f59c4:0x1019f59c4 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Foundation.URL.ffmpegString.getter : Swift.String
        return try OutputStreamInfo(formatContext: formatContext,
                                    filename: filename,
                                    forceTranscode: false,                  // p4 = 0
                                    formatContextOptions: options,
                                    formatName: "hls",                      // p6+p7 = "hls" (0x736c68)
                                    mediaType: nil,                         // p8 = 0 (null AVMediaType?)
                                    transcodeCodecIDs: [])                  // ⚑ p9 = static [AVCodecID] &DAT_1044f3788 — passed [] (flagged)
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
