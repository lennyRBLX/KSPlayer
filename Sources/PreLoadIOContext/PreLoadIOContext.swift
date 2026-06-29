import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via CacheIOContext)
import FFmpegKit  // AVIOInterruptCB (inherited interrupt chain — FFmpeg C struct)

// PreLoadIOContext — base of the limit/preload family: a CacheIOContext (1C.7)
// extended with a preload buffer, a fake URL cursor, a locked time-index for
// position↔time interpolation, a locked playback snapshot, and thumbnail-fetch
// bookkeeping. Reconstructed A-structure-faithful from the Forward 1.3.17 binary:
//
//   fields  — the 11 stored properties are orchestrator-RESOLVED (decode_composite
//             + width/name inference); NAMES + ORDER + COUNT + TYPES transcribed
//             verbatim from the brief, NOT re-derived from the decompiles. The ⚑
//             ones are best-effort (composite tuple/pointer shapes deterministic via
//             decode_composite; inner stdlib types width-inferred) → l2_field_gate
//             UNCHECKs them (expected 0 FLAG). thumbnailFetchResult is an Int32
//             placeholder (4-byte; real type is likely an enum → P3/P6).
//   init    — NONE. PreLoadIOContext has NO own init: it inherits CacheIOContext's
//             designated/convenience inits, so EVERY field carries a default (all
//             from the binary's flattened init constants). Writing an init = divergence.
//   methods — only the 4 cached small methods are reconstructed (faithful spine +
//             `// UNRESOLVED` for the unnamed-FUN / devirt-jumptable parts). All
//             names are devirt→inferred (no mangled method symbol). Everything else
//             — the deep preload/download IO engine and the 9 null devirt slots — is
//             UNRESOLVED→later phase, marked NOT fabricated (see the tail markers).
//
// CacheIOContext / URLContextDownload / TimeIndexEntry are in-module (already
// committed; no import). AVIOInterruptCB resolves via `import FFmpegKit` (the
// inherited interrupt field). Builds via `swift build --target PreLoadIOContext`.
public class PreLoadIOContext: CacheIOContext {
    // --- stored fields (binary __swift5_fieldmd order; defaults are the binary's
    //     flattened init constants. Swift synthesizes accessors — do NOT hand-write
    //     get/set; do NOT write an init — all inherited from CacheIOContext) ---

    // 0  loadMoreBuffer: scratch buffer the preload path reads ahead into. ⚑
    //    composite (UnsafeMutablePointer<UInt8>?) via decode_composite; init nil.
    var loadMoreBuffer: UnsafeMutablePointer<UInt8>? = nil // ⚑ (composite; gate UNCHECKED)
    // 1  fakeUrlPos: the synthetic URL cursor the preload presents to the reader. ⚑
    //    width-inferred UInt64; init 0.
    var fakeUrlPos: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)
    // 2  isPreloadPaused: whether the preload is paused (s55 short-circuits on it).
    //    init false.
    var isPreloadPaused: Bool = false
    // 3  _timeIndex: the position↔time index entries, guarded by _timeIndexLock.
    //    init []. (TimeIndexEntry is in-module.)
    var _timeIndex: [TimeIndexEntry] = []
    // 4  _timeIndexLock: serializes _timeIndex access (s33 locks it). init NSLock().
    var _timeIndexLock: NSLock = NSLock()
    // 5  _playbackSnapshot: last (time, position) reported by the player, guarded by
    //    _playbackSnapshotLock (s31 stores/nils it). ⚑ composite tuple-optional via
    //    decode_composite; init nil.
    var _playbackSnapshot: (time: Double, position: UInt64)? = nil // ⚑ (composite; gate UNCHECKED)
    // 6  _playbackSnapshotLock: serializes _playbackSnapshot access (s31 locks it).
    //    init NSLock().
    var _playbackSnapshotLock: NSLock = NSLock()
    // 7  minBufferSecondsForThumbnail: min buffered seconds before a thumbnail fetch
    //    is allowed. init 5.0 (binary const).
    var minBufferSecondsForThumbnail: Double = 5.0
    // 8  videoDuration: known media duration in seconds. init 0.
    var videoDuration: Double = 0
    // 9  thumbnailFetchRequest: pending thumbnail fetch (byte offset + size). ⚑
    //    composite tuple-optional via decode_composite; init nil.
    var thumbnailFetchRequest: (offset: UInt64, size: UInt32)? = nil // ⚑ (composite; gate UNCHECKED)
    // 10 thumbnailFetchResult: outcome of the last thumbnail fetch. ⚑ Int32
    //    PLACEHOLDER (4-byte; real type likely an enum → P3/P6). init 0.
    var thumbnailFetchResult: Int32 = 0 // ⚑ placeholder (4-byte; real type likely an enum — P3/P6)

    // --- methods (only the 4 cached small methods; names devirt→inferred) ---

    // s31 @101ba6980 — `func updatePlaybackSnapshot(time:position:invalid:)` (name
    //   inferred, devirt). FAITHFUL (full): under _playbackSnapshotLock, validate
    //   `time` — the binary masks the sign bit (`time-bits & 0x7fffffffffffffff`) and
    //   compares against the NaN/±inf bit ranges (== `time.isNaN || time.isInfinite`).
    //   If invalid OR the explicit `invalid` flag is set → store nil (writes 0,0 and
    //   the optional tag byte = 1). Else → store the (time, position) pair (tag = 0).
    //   `position` is the UInt64 second word (param_2), `invalid` the char param_3.
    func updatePlaybackSnapshot(time: Double, position: UInt64, invalid: Bool) { // name inferred (devirt)
        _playbackSnapshotLock.lock()
        // Binary gate (FUN_101ba6980): isNaN || isInfinite || time < 0 || invalid.
        // The `time < 0` (negative-finite) clause was RECOVERED by the M1C audit's
        // independent recheck — decompile clauses C/D are sign-bit-guarded
        // (`(long)param_1 < 0`) finite-exponent tests that reject every negative
        // finite time (counterexample -1.0 = 0xBFF0… → nil). The original
        // reconstruction omitted it. -0.0 is NOT rejected (matches strict `< 0`).
        if time.isNaN || time.isInfinite || time < 0 || invalid {
            _playbackSnapshot = nil      // binary: *puVar1=0; puVar1[1]=0; tag byte=1
        } else {
            _playbackSnapshot = (time: time, position: position) // binary: tag byte=0
        }
        _playbackSnapshotLock.unlock()
    }

    // s33 @101ba80e8 — `func interpolateTime(_:position:total:) -> Double` (name
    //   inferred, devirt). FAITHFUL SPINE + UNRESOLVED on the two unnamed helpers.
    //   The decompile returns 0 unless `total != 0` and the first double passes the
    //   same NaN/inf validity gate as s31; then, under _timeIndexLock, it calls the
    //   unnamed FUN_101bac458 over _timeIndex (a lookup returning a found-marker) and,
    //   on miss (== 0), falls back to the linear interpolation `time * position /
    //   total` clamped to ≤ time; on hit it delegates to the unnamed FUN_101bac70c
    //   (then bridge-releases the returned object). param_1=time, param_2=position
    //   (UInt64), param_3=total (UInt64) — both reinterpreted from the double regs in
    //   the binary. Helper bodies are unnamed FUN_ with no readable signature → spine
    //   only, NOT fabricated.
    func interpolateTime(_ time: Double, position: UInt64, total: UInt64) -> Double { // name inferred (devirt)
        var result = 0.0
        // Binary gate (FUN_101ba80e8): total != 0 && finite && time > 0. The decompile
        // enters the lock body only when `-1 < (long)param_1` (sign bit clear = non-negative)
        // AND finite-exponent, or the positive-subnormal clause — net strictly-positive-finite.
        // The `time > 0` requirement was OMITTED in the original reconstruction; RECOVERED by
        // the orchestrator re-walk of the M1C audit. NB the audit itself FALSE-PASSED this unit
        // (rationalized the sign term as isFinite inlining — the same trap s31's compare agent
        // hit). Counterexample time=-1.0,total=10,pos=5: binary -> 0.0 (gate fails); pre-fix -> -1.0.
        guard total != 0, !(time.isNaN || time.isInfinite), time > 0 else { return result }
        _timeIndexLock.lock()
        // UNRESOLVED → P8 (IO-completion): lVar1 = FUN_101bac458(time, _timeIndex, total) — an unnamed
        //   time-index lookup over _timeIndex returning a found-entry marker (0 == miss).
        //   On a HIT the binary then computes result = FUN_101bac70c(time, position,
        //   total, <entry>) and _swift_bridgeObjectRelease(<entry>) — a second unnamed
        //   interpolation helper over the found index entry. Both helpers are unnamed
        //   FUN_ with no readable signature/body → NOT reconstructed; only the MISS path
        //   below (which the decompile spells out) is reconstructed. The lock/unlock and
        //   the miss-branch math are the faithful spine.
        _timeIndexLock.unlock()
        // binary (miss): dVar2 = time; if position < total and
        //   (time * Double(position)) / Double(total) <= time → take the interpolation.
        result = time
        if position < total {
            let interp = (time * Double(position)) / Double(total)
            if interp <= time { result = interp }
        }
        return result
    }

    // s36 @101bab2d8 — `func reportThumbnailProgress(_:_:)` (name inferred, devirt).
    //   FAITHFUL SPINE + UNRESOLVED → P8 (IO-completion) (the tail is a devirtualized indirect call
    //   through an UNRECOVERED JUMPTABLE — "Could not recover jumptable … too many
    //   branches"). The decompile gates two doubles through the NaN/inf validity check,
    //   reads CacheIOContext.eof (== true) and a duration-like double field, and on the
    //   pass path computes via the unnamed FUN_101ba7dc8 before the indirect tail-call
    //   through `*(vtable + 0x590)`; otherwise it passes 0/flag through the same slot.
    //   The branch target (vtable+0x590) is devirt with an unrecovered branch table →
    //   no readable callee. Body left as a faithful-spine marker, NOT fabricated.
    func reportThumbnailProgress(_ a: Double, _ b: Double) { // name inferred (devirt)
        _ = a
        _ = b
        // UNRESOLVED → P8 (IO-completion) (s36 @101bab2d8): validity-gate(a,b) && eof==true &&
        //   <duration-double> != 0 → dVar = FUN_101ba7dc8(a, b, <duration>), then the
        //   indirect tail-call (*(self.vtable + 0x590))(a, dVar, flag) through an
        //   UNRECOVERED JUMPTABLE; the else-branch passes (a, 0.0, 1) through the same
        //   slot. The devirt branch target + the unnamed FUN_101ba7dc8 have no readable
        //   body → not reconstructed. — P2
        //   NB (M1C audit): the validity-gate here is the SAME family as s31/s33. When
        //   P2 reconstructs it, the gate MUST include the sign / `> 0` term (binary
        //   rejects non-positive time), not just isNaN/isInfinite — s31 AND s33 both
        //   omitted it. Do not repeat the omission.
    }

    // s55 @101ba6bb8 — `func bufferedBytesAvailable() -> UInt32` (name inferred,
    //   devirt). FAITHFUL (full, modulo the inherited-field offsets it reads). The
    //   decompile: if isPreloadPaused → 0. Else, when CacheIOContext.eof and the two
    //   inherited position fields at +0x50/+0x48 are equal (the fully-buffered case),
    //   it returns the inherited 4-byte field at +0x14 (the AbstractAVIOContext buffer
    //   size) only if `(<field+0x80> &+ uVar4) < <pos+0x50>`, else 0 — the &+ is an
    //   overflow-checked add (the SoftwareBreakpoint(…) paths are Swift's UInt overflow
    //   traps, NOT calls). When not at that EOF-equal case it returns that same +0x14
    //   field. The +0x14/+0x48/+0x50/+0x80 reads are INHERITED CacheIOContext /
    //   AbstractAVIOContext fields (out of this class's reconstruction scope — their
    //   exact property names live in 1C.4/1C.7, not re-derived here) → the field-offset
    //   arithmetic is preserved as an UNRESOLVED note and the isPreloadPaused spine is faithful.
    func bufferedBytesAvailable() -> UInt32 { // name inferred (devirt)
        if isPreloadPaused {
            return 0
        }
        // UNRESOLVED → P8 (IO-completion): the eof / fully-buffered branch reads INHERITED CacheIOContext
        //   + AbstractAVIOContext fields by offset (+0x14 buffer-size, +0x48/+0x50
        //   position pair, +0x80) with an overflow-checked &+; those property names are
        //   owned by 1C.4/1C.7 and not re-derived here → the available-bytes arithmetic
        //   is not reconstructed. The isPreloadPaused short-circuit above is faithful;
        //   the non-paused fall-through returns 0 as a compilable spine (binary returns
        //   the +0x14 buffer-size field). — P2
        return 0
    }

    // UNRESOLVED → later phase (do NOT reconstruct — declared nowhere beyond these
    //   markers; their symbols are devirt and/or their calls are stripped FFmpeg the
    //   P2 oracle names — fabrication risk):
    //   DEEP ENGINE (preload / download IO → P2):
    //     • slot 21  (301 instr) @ —    — preload/download IO
    //     • slot 32  (200 instr) @ —    — preload/download IO
    //     • slot 35  (165 instr) @ —    — preload/download IO
    //     • slot 49  (208 instr) @ —    — preload/download IO
    //     • slot 50  (141 instr) @ —    — preload/download IO
    //     • slot 53  (346 instr) @ —    — preload/download IO
    //     • slot 51  (1193 instr) @ —   — preload/download IO (deepest)
    //     • slot 54  (1183 instr) @ —   — preload/download IO (deepest)
    //   DEVIRT (null, no body): slots 22, 23, 24, 25, 26, 27, 28, 29, 30, 34.
    //   thumbnail-result typing is P3; preload/download IO is P2. — NOT fabricated.
}
