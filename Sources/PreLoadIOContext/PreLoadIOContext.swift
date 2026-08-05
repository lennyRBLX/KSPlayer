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
public class PreLoadIOContext: CacheIOContext, PreLoadProtocol, PreLoadPlaybackPositionSyncProtocol {
    // --- stored fields (binary __swift5_fieldmd order; defaults are the binary's
    //     flattened init constants. Swift synthesizes accessors — do NOT hand-write
    //     get/set; do NOT write an init — all inherited from CacheIOContext) ---

    // 0  loadMoreBuffer: scratch buffer the preload path reads ahead into. ⚑
    //    composite (UnsafeMutablePointer<UInt8>?) via decode_composite; init nil.
    var loadMoreBuffer: UnsafeMutablePointer<UInt8>? = nil // ⚑ (composite; gate UNCHECKED)
    // 1  fakeUrlPos: the synthetic URL cursor the preload presents to the reader. ⚑
    //    width-inferred UInt64; init 0.
    private var fakeUrlPos: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)
    // 2  isPreloadPaused: whether the preload is paused (s55 short-circuits on it).
    //    init false.
    public var isPreloadPaused: Bool = false
    // 3  _timeIndex: the position↔time index entries, guarded by _timeIndexLock.
    //    init []. (TimeIndexEntry is in-module.)
    private var _timeIndex: [TimeIndexEntry] = []
    // 4  _timeIndexLock: serializes _timeIndex access (s33 locks it). init NSLock().
    private let _timeIndexLock: NSLock = NSLock()
    // 5  _playbackSnapshot: last (time, position) reported by the player, guarded by
    //    _playbackSnapshotLock (s31 stores/nils it). ⚑ composite tuple-optional via
    //    decode_composite; init nil.
    private var _playbackSnapshot: (time: Double, position: UInt64)? = nil // ⚑ (composite; gate UNCHECKED)
    // 6  _playbackSnapshotLock: serializes _playbackSnapshot access (s31 locks it).
    //    init NSLock().
    private let _playbackSnapshotLock: NSLock = NSLock()
    // 7  minBufferSecondsForThumbnail: min buffered seconds before a thumbnail fetch
    //    is allowed. init 5.0 (binary const).
    public var minBufferSecondsForThumbnail: Double = 5.0
    // 8  videoDuration: known media duration in seconds. init 0.
    public var videoDuration: Double = 0
    // 9  thumbnailFetchRequest: pending thumbnail fetch (byte offset + size). ⚑
    //    composite tuple-optional via decode_composite; init nil.
    private var thumbnailFetchRequest: (offset: UInt64, size: UInt32)? = nil // ⚑ (composite; gate UNCHECKED)
    // 10 thumbnailFetchResult: outcome of the last thumbnail fetch. ⚑ Int32
    //    PLACEHOLDER (4-byte; real type likely an enum → P3/P6). init 0.
    private var thumbnailFetchResult: Int32 = 0 // ⚑ placeholder (4-byte; real type likely an enum — P3/P6)

    // --- computed accessors (vtable slots 0, 1, 11-13 and 20; only slot 20 is written —
    //     see the PINs below for the other three) ---

    // s20 @101ba78a4 — `var timeIndex: [TimeIndexEntry]` (name inferred, devirt).
    //   FAITHFUL (full): the lone getter that closes the stored-field triples (vtable_walk
    //   puts the field triples at slots 2-19 and the first deep-IO method at slot 21, so
    //   this is declared exactly here). Straight-line, single exit: LOAD _timeIndexLock
    //   (a bare ivar load feeding the msgSend stub — there is NO retain of the lock; the
    //   body's only runtime calls are `swift_beginAccess` and `swift_bridgeObjectRetain`),
    //   `objc lock`, READ `swift_beginAccess` (flags 0,0) on the `_timeIndex` ivar-offset
    //   global, load the array word, `swift_bridgeObjectRetain` it (the +1 the return
    //   hands out), `objc unlock`, return. The `_x`-prefixed storage + a locked public
    //   face is the same pairing LimitSeparatePreLoadIOContext#slot20 @0x101ba4298 carries
    //   with its own `_timeIndex`/`_timeIndexLock` — two independent classes, same shape.
    // ⚑[tool=prefetch_decompiles ref=PreLoadIOContext.timeIndex.getter:0x101ba78a4 result=body full; NAME inferred]
    public var timeIndex: [TimeIndexEntry] { // name inferred (devirt)
        _timeIndexLock.lock()
        let entries = _timeIndex
        _timeIndexLock.unlock()
        return entries
    }

    // --- methods (only the 4 cached small methods; names devirt→inferred) ---

    // s31 @101ba6980 — `func updatePlaybackSnapshot(time:position:invalid:)` (name
    //   inferred, devirt). FAITHFUL (full): under _playbackSnapshotLock, validate
    //   `time` — the binary masks the sign bit (`time-bits & 0x7fffffffffffffff`) and
    //   compares against the NaN/±inf bit ranges (== `time.isNaN || time.isInfinite`).
    //   If invalid OR the explicit `invalid` flag is set → store nil (writes 0,0 and
    //   the optional tag byte = 1). Else → store the (time, position) pair (tag = 0).
    //   `position` is the UInt64 second word (param_2), `invalid` the char param_3.
    // s98 RENAMED. The name was inferred as `updatePlaybackSnapshot(time:position:invalid:)`;
    // the marker below already carried the real one. It is
    // `syncPlaybackPosition(time: Double, position: UInt64?)` — PreLoadProtocol's SIBLING
    // protocol requirement (PreLoadPlaybackPositionSyncProtocol req0), body @0x101ba6980,
    // 54 instr, vtable slot 31 / metadata +0x590. The `invalid:` third parameter
    // corresponds to NOTHING in the binary: the nil-vs-value distinction is carried by the
    // Optional tag of `position` itself, which the body tests with `and w9,w21,#0xff` /
    // `cmp w9,#0x1` before choosing between the value store and the nil store.
    public func syncPlaybackPosition(time: Double, position: UInt64?) {
        _playbackSnapshotLock.lock()
        // Binary gate (FUN_101ba6980): isNaN || isInfinite || time < 0 || invalid.  ⚑[tool=resolve_fun_pins ref=FUN_101ba6980:0x101ba6980 result=RESOLVES_UNIQUELY] = PreLoadIOContext.PreLoadIOContext.syncPlaybackPosition(time: Swift.Double, position: Swift.UInt64?) -> ()
        // The `time < 0` (negative-finite) clause was RECOVERED by the M1C audit's
        // independent recheck — decompile clauses C/D are sign-bit-guarded
        // (`(long)param_1 < 0`) finite-exponent tests that reject every negative
        // finite time (counterexample -1.0 = 0xBFF0… → nil). The original
        // reconstruction omitted it. -0.0 is NOT rejected (matches strict `< 0`).
        if let position, !time.isNaN, !time.isInfinite, time >= 0 {
            _playbackSnapshot = (time: time, position: position) // binary: tag byte=0
        } else {
            _playbackSnapshot = nil      // binary: *puVar1=0; puVar1[1]=0; tag byte=1
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
        // Binary gate (FUN_101ba80e8): total != 0 && finite && time > 0. The decompile  ⚑[tool=resolve_fun_pins ref=FUN_101ba80e8:0x101ba80e8 result=RESOLVES_UNIQUELY] = PreLoadIOContext.PreLoadIOContext.positionToTime(position: Swift.UInt64, fileSize: Swift.UInt64, duration: Swift.Double) -> Swift.Double
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
    //   pass path computes via the unnamed FUN_101ba7dc8 before the indirect tail-call  ⚑[tool=resolve_fun_pins ref=FUN_101ba7dc8:0x101ba7dc8 result=RESOLVES_UNIQUELY] = PreLoadIOContext.PreLoadIOContext.timeToPosition(time: Swift.Double, fileSize: Swift.UInt64, duration: Swift.Double) -> Swift.UInt64
    //   through `*(vtable + 0x590)`; otherwise it passes 0/flag through the same slot.
    //   The branch target (vtable+0x590) is devirt with an unrecovered branch table →
    //   no readable callee. Body left as a faithful-spine marker, NOT fabricated.
    func reportThumbnailProgress(_ a: Double, _ b: Double) { // name inferred (devirt)
        _ = a
        _ = b
        // UNRESOLVED → P8 (IO-completion) (s36 @101bab2d8): validity-gate(a,b) && eof==true &&
        //   <duration-double> != 0 → dVar = FUN_101ba7dc8(a, b, <duration>), then the  ⚑[tool=resolve_fun_pins ref=FUN_101ba7dc8:0x101ba7dc8 result=RESOLVES_UNIQUELY] = PreLoadIOContext.PreLoadIOContext.timeToPosition(time: Swift.Double, fileSize: Swift.UInt64, duration: Swift.Double) -> Swift.UInt64
        //   indirect tail-call (*(self.vtable + 0x590))(a, dVar, flag) through an
        //   UNRECOVERED JUMPTABLE; the else-branch passes (a, 0.0, 1) through the same
        //   slot. The devirt branch target + the unnamed FUN_101ba7dc8 have no readable  ⚑[tool=resolve_fun_pins ref=FUN_101ba7dc8:0x101ba7dc8 result=RESOLVES_UNIQUELY] = PreLoadIOContext.PreLoadIOContext.timeToPosition(time: Swift.Double, fileSize: Swift.UInt64, duration: Swift.Double) -> Swift.UInt64
        //   body → not reconstructed. — P2
        //   NB (M1C audit): the validity-gate here is the SAME family as s31/s33. When
        //   P2 reconstructs it, the gate MUST include the sign / `> 0` term (binary
        //   rejects non-positive time), not just isNaN/isInfinite — s31 AND s33 both
        //   omitted it. Do not repeat the omission.
    }

    // ── s49 / s50: the two cached-segment lookups. Both walk the inherited
    //    `entryList` ([CacheFileEntry], self+0x88) with the SAME inlined binary search;
    //    see the shared-helper PIN at the bottom of this pair.

    // s49 @101ba862c — `func bufferedSeconds() -> Double` (name inferred, devirt).
    //   FAITHFUL (full): all 208 instructions are accounted for. The only calls are
    //   `interpolateTime` (this class's own s33 — vtable_walk puts slot 33 at exactly the
    //   address the decompile calls, so this is a resolved same-class direct call, not an
    //   unnamed helper), the stdlib Array bridged-subscript / `_CocoaArrayWrapper.endIndex`
    //   thunks, and swift_beginAccess/retain/release. NO FFmpeg symbol, no unresolved
    //   callee, and NO dropped do/catch: every callee in the prefetch glossary has a
    //   construct in the body, the cache contains no "Removing unreachable block" (its only
    //   warnings are "Does not return", ×8, one per trap), and all eight `brk #1` sites are
    //   Swift overflow/bounds traps, not calls.
    // ⚑[tool=vtable_walk ref=interpolateTime:0x101ba80e8 result=slot33 — same-class direct call]
    //
    //   SIGNATURE is disassembly-grounded, not conventional. vtable_walk reports slot 49 as
    //   kind=Method (a computed property prints `Getter`) → a `func`; and NO argument register
    //   is ever READ: x0-x3 are each WRITTEN first (`add x0,x20,x21` … `mov x3,#0`), x4-x7 and
    //   v0-v7 never appear except as destinations, and the only live-in is x20 (swiftself) →
    //   it takes NO arguments. The result leaves in d0 → Double.
    //
    //   Field identity is symbol-grounded, not offset-guessed: the decompile resolves the
    //   ivar-offset globals by NAME (`CacheIOContext::eof`, `PreLoadIOContext::videoDuration`,
    //   `CacheFileEntry::position`, `CacheFileEntry::size`) and each of those names checks out
    //   against the committed field lists. The direct-offset reads are the ones CacheIOContext
    //   already pins: end@+0x48, logicalPos@+0x80, entryList@+0x88.
    //   Corroboration that `entry.position` and `entry.size` are read (and not some other
    //   pair): `size` is fetched THROUGH a swift_beginAccess and `position` is NOT, which is
    //   exactly what dump_field_bindings reports for CacheFileEntry — `position` is a `let`
    //   (no exclusivity check possible) and `size` is a `var`.
    //
    //   Shape, instruction-anchored:
    //     0x101ba867c  guard eof                       (ldrb; cmp w8,#1; b.ne → return 0)
    //     0x101ba868c  guard end != 0                  (INTEGER `cbz x19`, not a float compare —
    //                                                   Ghidra types +0x48 as `double` only
    //                                                   because it shares a reg with the call)
    //     0x101ba8698  guard videoDuration > 0         (fcmp d8,#0.0; b.le — NaN exits too)
    //     0x101ba86c0  startTime = interpolateTime(videoDuration, position: logicalPos, total: end)
    //     0x101ba86f4  guard !entryList.isEmpty        (count is loaded TWICE — once for this
    //                                                   `cbz`, once for `count - 1`)
    //     0x101ba8744  binary search for logicalPos    (mid = (low+high)/2 via adds/asr with the
    //                                                   overflow trap = a checked Int `+`)
    //     0x101ba87fc  forward contiguity scan         (count re-loaded EVERY iteration ⇒ the
    //                                                   source is a `while i < entryList.count`,
    //                                                   not a `for i in ..<count`)
    //     0x101ba8888  cursor = max(cursor, …)         (cmp + csel …,hi)
    //     0x101ba88e8  endTime = interpolateTime(videoDuration, position: cursor, total: end)
    //     0x101ba88ec  return endTime - startTime      (fsub d0,d9)
    //   `logicalPos` is RE-LOADED from the ivar at each of its three uses (0x101ba86b4 /
    //   0x101ba86c8 / 0x101ba87f8) rather than held in a register across the call, so the
    //   source really does spell the property three times — a `let` local would have pinned it.
    // ⚑[tool=prefetch_decompiles ref=PreLoadIOContext.slot49:0x101ba862c result=body full; NAME inferred]
    func bufferedSeconds() -> Double { // name inferred (devirt)
        guard eof, end != 0, videoDuration > 0 else { return 0 }
        let startTime = interpolateTime(videoDuration, position: logicalPos, total: end)
        guard !entryList.isEmpty else { return 0 }
        var low = 0
        var high = entryList.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = entryList[mid]
            if logicalPos < entry.position {
                high = mid - 1
            } else if logicalPos < entry.position + UInt64(entry.size) {
                // hit: extend forward while the following segments stay contiguous
                var cursor = logicalPos
                var index = mid
                while index < entryList.count {
                    let next = entryList[index]
                    if cursor < next.position {
                        break
                    }
                    cursor = max(cursor, next.position + UInt64(next.size))
                    index += 1
                }
                let endTime = interpolateTime(videoDuration, position: cursor, total: end)
                return endTime - startTime
            } else {
                low = mid + 1
            }
        }
        return 0
    }

    // s50 @101ba896c — `func requestThumbnailData(offset:size:) -> UInt32` (name inferred,
    //   devirt). FAITHFUL (full): all 141 instructions are accounted for; the only calls are
    //   the stdlib Array bridged-subscript / endIndex thunks and swift_beginAccess/retain/
    //   release. NO FFmpeg symbol, no unresolved callee, and NO dropped do/catch (same three
    //   checks as s49: glossary fully consumed, no unreachable-block warning, and the seven
    //   `brk #1` sites are overflow/bounds traps).
    //
    //   SIGNATURE, from the prologue: x0 is a 64-bit live-in and w1 a 32-bit live-in
    //   (`str w1,[sp,#0xc]` / `mov x21,x0` before any other use), x2+ untouched → two
    //   parameters, (UInt64, UInt32). The widths are then CONFIRMED by the only side effect:
    //   the miss path stores x0 as the 8-byte word and w1 as the 4-byte word of
    //   `thumbnailFetchRequest`, whose declared shape is `(offset: UInt64, size: UInt32)?`.
    //   The return leaves in w0 → 32-bit, and the hit path returns parameter 2 verbatim
    //   (`ldr w0,[sp,#0xc]`), so the return type is that parameter's type, UInt32.
    //
    //   Shape, instruction-anchored:
    //     0x101ba89bc  guard !entryList.isEmpty        (miss when empty — same double count
    //                                                   load as s49)
    //     0x101ba8a0c  the SAME binary search as s49, keyed on `offset`
    //     0x101ba8ac8  HIT → subscript entryList[mid] once more and DISCARD it, then
    //                  `return size`. The discard is in the binary, not an editorial choice:
    //                  the bridged arm calls the subscript thunk and immediately
    //                  swift_unknownObjectReleases the +1 it returns, and the native arm keeps
    //                  only the two bounds traps (`cmn x19,#1` re-derives mid ≥ 0 for a SECOND
    //                  subscript at the same index) with the element load itself ARC-elided.
    //                  The loop's own `entry` is already released at 0x101ba8a80, before this.
    //     0x101ba8b18  MISS (search exhausted or list empty) → thumbnailFetchRequest =
    //                  (offset, size); the tag byte at +0xc is stored 0 = `.some`; return 0.
    //   Note the miss store clobbers x20, so it can only ever be reached on the miss path —
    //   which is itself the proof that the hit path never falls through into it.
    // ⚑[tool=prefetch_decompiles ref=PreLoadIOContext.slot50:0x101ba896c result=body full; NAME inferred]
    func requestThumbnailData(offset: UInt64, size: UInt32) -> UInt32 { // name inferred (devirt)
        if !entryList.isEmpty {
            var low = 0
            var high = entryList.count - 1
            while low <= high {
                let mid = (low + high) / 2
                let entry = entryList[mid]
                if offset < entry.position {
                    high = mid - 1
                } else if offset < entry.position + UInt64(entry.size) {
                    _ = entryList[mid] // binary: the hit is re-fetched and dropped (see above)
                    return size
                } else {
                    low = mid + 1
                }
            }
        }
        thumbnailFetchRequest = (offset: offset, size: size)
        return 0
    }

    // ⚑[tool=disassemble_function ref=PreLoadIOContext.slot49:0x101ba8744 result=pinned]
    //   s49 and s50 contain the SAME inlined binary search over `entryList`, down to the
    //   redundant `guard !entryList.isEmpty` ahead of a `count - 1` that the loop test would
    //   have covered anyway. That is what a shared helper looks like after -O WMO inlining,
    //   and the two call sites even consume DIFFERENT results from it — s49 uses the found
    //   INDEX (it resumes the forward scan at `mid`), while s50 re-subscripts and drops the
    //   found ELEMENT, which is the signature of an `if let … = <helper returning
    //   CacheFileEntry?>` binding that never reads its binding. So a shared private helper is
    //   likely, but its NAME, its RETURN TYPE and even whether it is one helper or two are all
    //   unrecoverable — it has no vtable slot (private methods get none) and no surviving
    //   symbol. Writing the loop out at both sites invents nothing and is code-equivalent
    //   (the compiler would have inlined the helper here regardless); inventing a helper name
    //   would not be. Deferred, not guessed.

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

    // s52 @101ba9e44 — `var bufferedBytes: Int` (name inferred, devirt). FAITHFUL (full).
    //   Distinct from bufferedBytesAvailable() above: that one reads +0x14/+0x48/+0x50,
    //   this one reads ONLY `fakeUrlPos` (this class's own field, its exclusivity check
    //   elided) and the inherited `logicalPos`. logicalPos@+0x80 is source-pinned, not
    //   guessed: CacheIOContext.swift documents entryList at self+0x88 and logicalPos as
    //   the field immediately before it, and CacheIOContext#slot24 @0x101b86138 is
    //   logicalPos' own generated getter reading that same +0x80.
    //   Shape: `fakeUrlPos == .max` (the binary's 0xffffffffffffffff sentinel) → 0;
    //   `logicalPos > fakeUrlPos` → 0; otherwise the difference, clamped. The clamp is
    //   the tell for `Int(clamping:)` — an unsigned compare of the UInt64 difference
    //   against 0x8000000000000000 selecting 0x7fffffffffffffff (== Int.max) on the high
    //   side. (`Int(exactly:) ?? .max` emits the same select; `Int(clamping:)` is the
    //   idiomatic spelling and is what is written.)
    // ⚑[tool=prefetch_decompiles ref=PreLoadIOContext.bufferedBytes.getter:0x101ba9e44 result=body full; NAME inferred]
    var bufferedBytes: Int { // name inferred (devirt)
        guard fakeUrlPos != .max, logicalPos <= fakeUrlPos else {
            return 0
        }
        return Int(clamping: fakeUrlPos - logicalPos)
    }

    // ⚑[tool=vtable_walk ref=PreLoadIOContext.slot1.getter:0x101ba41f4 result=pinned]
    //   A get-only computed property declared BEFORE the stored fields (slots 0 and 1 are
    //   lone getters ahead of the slot-2 field triples). Body fully readable:
    //   `urlPos == .max ? logicalPos : urlPos` — READ beginAccess on +0x50 (urlPos), and
    //   only on the `.max` sentinel a second READ beginAccess on +0x80 (logicalPos).
    //   THE SAME FUNCTION BODY is LimitSeparatePreLoadIOContext#slot6 (identical bodies
    //   folded by the linker), so the pair is one unit, not two. NOT written: the name is
    //   unrecoverable (recover_swift_function_name → no name, no labels) AND its
    //   declaration position is ahead of the stored fields, so inventing it would move
    //   every field triple in this class. Deferred, not guessed.
    // ⚑[tool=vtable_walk ref=PreLoadIOContext.slot12.setter:0x101ba6e04 result=pinned]
    //   Slots 11-13 are a full triple whose GETTER is literally the same folded body as
    //   CacheIOContext#slot9 / LimitSeparatePreLoadIOContext#slot23 (all three vtables
    //   point at 0x100a4e368, the bare `beginAccess(+0x50) + load` urlPos getter), and
    //   whose SETTER inlines urlPos' own didSet (end = max(end, newValue) +
    //   updateDownloadSpeed, guarded by `newValue != .max`) and then mirrors the result
    //   into `fakeUrlPos`. So the source is a get/set pair over `urlPos` that also keeps
    //   `fakeUrlPos` in step — but the property NAME is unrecoverable and, like slot 1, it
    //   sits among the stored-field triples. LimitSeparatePreLoadIOContext#slot24
    //   @0x101ba49f8 is the same body against its own fakeUrlPos. Deferred, not guessed.

    // UNRESOLVED → later phase (do NOT reconstruct — declared nowhere beyond these
    //   markers; their symbols are devirt and/or their calls are stripped FFmpeg the
    //   P2 oracle names — fabrication risk):
    //   DEEP ENGINE (preload / download IO → P2):
    //     • slot 21  (301 instr) @ —    — preload/download IO
    //     • slot 32  (200 instr) @ —    — preload/download IO
    //     • slot 35  (165 instr) @ —    — preload/download IO
    //     • slot 53  (346 instr) @ —    — preload/download IO
    //     • slot 51  (1193 instr) @ —   — preload/download IO (deepest)
    //     • slot 54  (1183 instr) @ —   — preload/download IO (deepest)
    //   DEVIRT (null, no body): slots 22, 23, 24, 25, 26, 27, 28, 29, 30, 34.
    //   thumbnail-result typing is P3; preload/download IO is P2. — NOT fabricated.

    // MARK: - KSPlayer.PreLoadProtocol members
    //
    // Requirements 1, 2 and 3 are inherited from CacheIOContext; 5 is declared above; the sibling
    // protocol's sole requirement is the renamed syncPlaybackPosition(time:position:) above.

    // Requirement 0. Body @0x101ba9e44, 26 instr, vtable slot 52 — structurally identical to
    // LimitSeparatePreLoadIOContext's, differing only in its field-offset global (0x1044f6238,
    // which the reflection offset/name table names `fakeUrlPos`). Same shape: sentinel test, then
    // a borrowing subtraction against the inherited logicalPos, then saturation at Int64.max.
    /// @0x101ba4244, 21 instructions. Get-only (no `vs` in the trie) and public (its own `vpMV`).
    ///
    /// The getter takes a READ `swift_beginAccess` (flags 0, 0) on `self+0x88`, retains what it
    /// loads, hands it to the outlined helper @0x101bab128 and releases the original. +0x88 is
    /// `CacheIOContext.entryList`, the offset that class's own notes already pin, and this class
    /// inherits it. The helper is the 108-instruction array conversion — tagged-pointer check,
    /// count load, fresh buffer, per-element box — that Swift emits for the covariant
    /// `[CacheFileEntry]` -> `[any CacheEntryProtocol]` conversion, which is available because
    /// `CacheFileEntry` conforms to `CacheEntryProtocol`. So the body is the bare `entryList`.
    ///
    /// ⚑ The getter ADDRESS is shared with the sibling class's `cacheList` — an ICF fold, not one
    ///   property. Both carry their OWN `vpMV` (0x103572120 and 0x103572198), and this file's
    ///   PreLoadProtocol note already establishes why the two fold: they are siblings under
    ///   CacheIOContext with an identical inherited layout, so bit-identical bodies come out of
    ///   the same source and the linker merges them. Each is declared on its own class.
    /// ⚑[tool=export_trie_oracle ref=cacheList.getter:0x101ba4244 result=two-vpMV-one-ICF-folded-body]
    public var cacheList: [any CacheEntryProtocol] {
        entryList
    }

    public var loadedSize: Int64 {
        guard fakeUrlPos != .max, fakeUrlPos >= logicalPos else {
            return 0
        }
        let delta = fakeUrlPos - logicalPos
        return delta > UInt64(Int64.max) ? .max : Int64(delta)
    }

    // Requirement 8. Body @0x101bab2d8, 49 instr, slot 36. It is a pure FORWARDER: every path
    // tail-calls the (time:position:) overload above through metadata +0x590. Guard ladder, in
    // order: a float ladder on `time` rejecting negative / ±Inf / NaN; the same on `duration`; the
    // inherited `eof` must be true; the inherited `end` must be non-zero. All pass -> forward with
    // `.some(timeToPosition(time:fileSize:duration:))`, where the converter is 0x101ba7dc8 and
    // `fileSize` is `end` (the body loads self+0x48 straight into x0). Any fail -> forward with
    // `nil`, and note the body does NOT reset d0, so the original time is still passed.
    //
    // UNRESOLVED → P8: `timeToPosition(time:fileSize:duration:)` @0x101ba7dc8 is 200 instructions
    // and is NOT reconstructed, so the success arm cannot be written without inventing it. Only
    // the guard ladder and the nil arm are expressed.
    // ⚑[tool=export_trie_oracle ref=PreLoadIOContext.timeToPosition:0x101ba7dc8 result=name-recovered]
    public func syncPlaybackPosition(time: Double, duration: Double) {
        guard !time.isNaN, !time.isInfinite, time >= 0,
              !duration.isNaN, !duration.isInfinite, duration > 0,
              eof, end != 0
        else {
            syncPlaybackPosition(time: time, position: nil)
            return
        }
        // UNRESOLVED → P8: forward with .some(timeToPosition(time:fileSize:duration:)).
        syncPlaybackPosition(time: time, position: nil)
    }

    // Requirement 6. Body @0x101ba7914, 301 instr — a DIFFERENT method from the 109-instruction
    // sibling on LimitSeparatePreLoadIOContext, not a copy of it. Four things it does that the
    // sibling does not: (a) a leading NaN/±Inf/negative guard on `time` taken BEFORE the lock, so
    // it returns without locking at all; (b) a BINARY SEARCH (lower-bound partition on position)
    // where the sibling does a linear firstIndex scan; (c) strict `time` monotonicity enforcement
    // around the insertion point — it REJECTS the write, unlocking and returning, if the new time
    // is <= the previous entry's or >= the next entry's; (d) on an exact position match it compares
    // the stored time and NO-OPS when equal, where the sibling replaces unconditionally. It always
    // inserts through the shared helper 0x101babf50 with no append fast-path, and ends with a KSLog
    // at #line 84 whose #fileID is "PreLoadIOContext/PreLoadIOContext.swift" and #function
    // "addTimeIndex(position:time:)".
    //
    // UNRESOLVED → P8: the search/insert interior. Its Array machinery runs through unnamed
    // helpers (0x101babf50 insert, 0x101bac23c COW) that are real trie negatives, and transcribing
    // by FUN-address is forbidden. The leading guard IS read and is expressed.
    // ⚑[tool=export_trie_oracle ref=addTimeIndex_insert_helper:0x101babf50 result=NOT_IN_TRIE]
    public func addTimeIndex(position: UInt64, time: Double) {
        guard !time.isNaN, !time.isInfinite, time >= 0 else {
            return
        }
        _timeIndexLock.lock()
        defer { _timeIndexLock.unlock() }
        // UNRESOLVED → P8: binary-search insertion with monotonicity rejection.
    }

    // Requirement 7, overriding CacheIOContext's entryList-based implementation with a
    // timeIndex-based one. Body @0x101ba6fa0, 526 instr, and its FAILURE PATH IS A TAIL CALL TO
    // SUPER (`b 0x101b8eed0`) rather than an empty array — which is why the guard is expressed as
    // a fall-through to `super`. Three conjuncts: duration finite and strictly positive; the
    // inherited `eof` true; the inherited `end` non-zero.
    //
    // On the live path it takes TWO sequential non-overlapping locks — _timeIndexLock around a
    // read of _timeIndex, then _playbackSnapshotLock around a read of the 17-byte
    // _playbackSnapshot — then loops over the private `cachedByteRanges(clampedTo: end)`,
    // converting each byte endpoint to seconds, stretching whichever range CONTAINS the playback
    // snapshot so that it covers the snapshot time, and appending only when start < end. A second
    // coalescing pass merges touching ranges, and ITS output is what is returned. It ends with a
    // KSLog at #line 412.
    //
    // UNRESOLVED → P8: both loops. The byte→seconds conversion and the coalescing pass run through
    // unnamed helpers (0x101bac70c, 0x101ba6880, 0x101bac458), all real trie negatives.
    // ⚑[tool=export_trie_oracle ref=cachedTimeRanges_convert:0x101bac70c result=NOT_IN_TRIE]
    override public func cachedTimeRanges(duration: Double) -> [CachedTimeRange] {
        guard !duration.isNaN, !duration.isInfinite, duration > 0, eof, end != 0 else {
            return super.cachedTimeRanges(duration: duration)
        }
        // UNRESOLVED → P8: the timeIndex-based range build and its coalescing pass.
        return []
    }

    // Requirement 4. Body @0x101ba9eac, 1183 instr, vtable slot 201 — ONE `ret` at 0x101baa6bc
    // with every path funnelling through a shared epilogue, plus ten traps.
    //
    // The guard ladder, in order, is fully read: (1) `isPreloadPaused` -> KSLog #line 636 ->
    // return -1 WITHOUT unlocking (the lock has not been taken yet); (2) an objc `tryLock` on the
    // inherited downloadLock -> on failure KSLog 642 -> return 1, again without unlocking;
    // (3) `isPreloadPaused` re-read AFTER the lock -> KSLog 649 -> unlock -> -1;
    // (4) `processThumbnailFetchRequest()` true -> unlock -> 1; (5) a lazy
    // `swift_slowAlloc(Int(bufferSize), -1)` into the load-more buffer when it is nil;
    // (6) `CacheIOContext.canAccessNetwork()` false -> KSLog 670 -> unlock -> -1;
    // (7) `preloadCount()` == 0 -> KSLog 678 -> unlock -> -1.
    //
    // Beyond it: `findDiscontinuousPos()` .some takes a seek path (KSLog 686); .none gates a second
    // findDiscontinuousPos behind a four-part conjunction (eof AND urlPos != end AND
    // logicalPos + bufferSize < urlPos), whose .none zeroes the three speed-sample fields and
    // returns 0. The read path binary-searches entryList, clamps the size to the gap, calls
    // `readComplete(buffer:size:isReadComplete:)`, substitutes AVERROR(EAGAIN) = -35 when at EOF
    // but not finished, and on success calls `addEntry(...)` virtually while DISCARDING a thrown
    // error, then advances urlPos and calls `updateSpeedSample(newPos:)`. Nine KSLog sites in all,
    // at #lines 636, 642, 649, 670, 678, 686, 698, 712, 735.
    //
    // UNRESOLVED → P8 (IO-completion): this is written to its RESULT CONTRACT and its first guard
    // only. The remainder depends on members our source does not yet declare
    // (processThumbnailFetchRequest, canAccessNetwork, preloadCount, findDiscontinuousPos,
    // readComplete, addEntry, updateSpeedSample), and inventing any of them is worse than the pin.
    public func more() -> Int32 {
        guard !isPreloadPaused else {
            return -1
        }
        // UNRESOLVED → P8: the lock, the six remaining guards, and the seek / cache-read split.
        return 0
    }
}

