import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via CacheIOContext)
import FFmpegKit  // FFmpeg C types reachable through the CacheIOContext chain

// LimitSeparatePreLoadIOContext — CacheIOContext (1C.7) extended with a separate
// "load-more" download path and a size-limited / time-indexed preload engine.
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields  — the 8 own stored properties are orchestrator-RESOLVED (reflection
//             field-record + l2_field_gate + the cached designated init); NAMES +
//             ORDER + COUNT + TYPES transcribed verbatim from the brief's table.
//             The ⚑ ones are best-effort (unmapped stdlib int / pointer / in-module
//             class) and flagged `// ⚑`. All CacheIOContext fields are inherited.
//   inits   — designated s22 @101ba4650 (cached, READABLE): sets all 8 own fields
//             directly (loadMoreBuffer=nil, fakeUrlPos=0, moreUrlPos=0, _timeIndex=[],
//             _timeIndexLock=NSLock(), moreDownload=param-copied, maxFileSize=param_7,
//             maxReadedFileSize=param_8) then delegates to CacheIOContext's designated
//             init FUN_101b86d38. Arity/param-order inferred (no mangled init symbol);
//             the field stores + super-delegation are explicit in the decompile.
//           — s21 @101ba4308 is a THROWING CONVENIENCE init with a full 210-instruction
//             body (the earlier "devirtualized, no readable body" note was WRONG and is
//             corrected below); PINNED on its argument labels, not on its shape.
//   methods — s27 @101ba4bd0 (cached, 109 instr; name devirt→inferred): a locked,
//             sorted insert-or-update into _timeIndex keyed by position. Faithful
//             spine; the Swift-synthesized stdlib Array internals (COW / insert /
//             grow) are noted as UNRESOLVED rather than transcribed by FUN-address.
//           — s29 @101ba4e30 (346 instr) and s31 @101ba5a5c (250 instr) are reconstructed
//             below; NEITHER touches FFmpeg — both are pure Swift over the inherited
//             entryList/urlPos/logicalPos, so the older "stripped FFmpeg" note did not
//             apply to them. s30 (433 instr) is still NOT reconstructed. s28 (1-instr
//             stdlib stub) is skipped.
//
// CacheIOContext / URLContextDownload / TimeIndexEntry are in-module (already
//   committed; no import). PreLoadIOContext builds green via
//   `swift build --target PreLoadIOContext`.
public class LimitSeparatePreLoadIOContext: CacheIOContext {
    // --- stored fields (binary __swift5_fieldmd order; 8 own properties) ---

    // 0  maxFileSize: byte cap for this context. Designated init param-fed (param_7,
    //    8-byte store at +maxFileSize).
    var maxFileSize: UInt64 = 0
    // 1  maxReadedFileSize: cap on bytes read. Designated init param-fed (param_8,
    //    8-byte store at +maxReadedFileSize).
    var maxReadedFileSize: UInt64 = 0
    // 2  loadMoreBuffer: scratch buffer for the separate "load-more" download path.
    //    Designated init zeroes it (nil). ⚑ (element/optionality inferred; pointer width).
    var loadMoreBuffer: UnsafeMutablePointer<UInt8>? // ⚑
    // 3  fakeUrlPos: synthetic url position used by the separate-download bookkeeping.
    //    Designated init zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    var fakeUrlPos: UInt64 = 0 // ⚑
    // 4  moreDownload: the secondary URLContextDownload feeding the load-more path.
    //    Designated init copies a value into it (FUN_1001263e0 value-copy from param_2).
    //    ⚑ (name + shape inferred; copied, not retained-as-new).
    let moreDownload: URLContextDownload? // ⚑
    // 5  moreUrlPos: current position within the secondary download. Designated init
    //    zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    var moreUrlPos: UInt64 = 0 // ⚑
    // 6  _timeIndex: sorted-by-position index of (position,time) entries. Designated
    //    init defaults it to [] (PTR___swiftEmptyArrayStorage). field-record.
    var _timeIndex: [TimeIndexEntry] = []
    // 7  _timeIndexLock: serializes _timeIndex mutation. Designated init allocs
    //    NSLock() (objc_allocWithZone + init on __NSLock) — that store is the DECLARATION
    //    DEFAULT being materialized, not a user assignment, so it is spelled here.
    //    Session 62 resolved the session-61 `let` refusal (was: default AND init assignment).
    //    Two facts pick the declaration-default form over `let x: NSLock` + an init store —
    //    both emit the same alloc inside the init, so the store alone cannot decide it:
    //      • the sibling PreLoadIOContext.swift:47 carries the identical field as
    //        `let _timeIndexLock: NSLock = NSLock()` with NO init assignment, already
    //        committed and gate-clean ("two independent classes, same shape");
    //      • the designated init's stores run non-param defaults FIRST in declaration order
    //        (loadMoreBuffer, fakeUrlPos, moreUrlPos, _timeIndex, _timeIndexLock) and only
    //        then the param-derived ones — which is exactly the default-materialization
    //        prologue the compiler emits ahead of user statements.
    let _timeIndexLock: NSLock = NSLock()

    // --- computed accessors ahead of the inits (vtable slot 20; slots 6, 7, 23-25 and
    //     26 are covered by the PINs / the getter after the inits) ---

    // s20 @101ba4298 — `var timeIndex: [TimeIndexEntry]` (name inferred, devirt).
    //   FAITHFUL (full): vtable_walk puts the field triples at slots 8-19 and the two
    //   inits at 21/22, so this lone getter is declared exactly here, between the last
    //   stored field and the designated init. Straight-line, single exit: LOAD
    //   _timeIndexLock (a bare ivar load feeding the msgSend stub — there is NO retain of
    //   the lock; the body's only runtime calls are `swift_beginAccess` and
    //   `swift_bridgeObjectRetain`), `objc lock`, READ `swift_beginAccess` (flags 0,0) on the
    //   `_timeIndex` ivar-offset global, load the array word, `swift_bridgeObjectRetain`
    //   (the +1 handed to the caller), `objc unlock`, return. PreLoadIOContext#slot20
    //   @0x101ba78a4 carries the identical shape over its own `_timeIndex`/`_timeIndexLock`
    //   — two sibling classes duplicating one locked-read surface, and the same
    //   duplication that makes slots 6/23 literally shared function bodies below.
    // ⚑[tool=prefetch_decompiles ref=LimitSeparatePreLoadIOContext.timeIndex.getter:0x101ba4298 result=body full; NAME inferred]
    var timeIndex: [TimeIndexEntry] { // name inferred (devirt)
        _timeIndexLock.lock()
        let entries = _timeIndex
        _timeIndexLock.unlock()
        return entries
    }

    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot6.getter:0x101ba41f4 result=pinned]
    //   Slots 6 and 7 are lone get-only computed properties sitting BETWEEN the
    //   maxReadedFileSize triple (3-5) and the loadMoreBuffer triple (8-10). Slot 6's body
    //   is fully readable — `urlPos == .max ? logicalPos : urlPos`, a READ beginAccess on
    //   the inherited +0x50 and, only on the 0xffffffffffffffff sentinel, a second READ
    //   beginAccess on the inherited +0x80 — and it is THE SAME FOLDED FUNCTION as
    //   PreLoadIOContext#slot1, so the two vtable rows are one unit. NOT written: no name
    //   or argument label survives (recover_swift_function_name → None), and the
    //   declaration sits between two stored-field triples, so a guessed member would move
    //   this class's field slots. Deferred, not guessed.
    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot24.setter:0x101ba49f8 result=pinned]
    //   Slots 23-25 are a triple whose GETTER is the folded bare urlPos getter shared with
    //   CacheIOContext#slot9 and PreLoadIOContext#slot11 (all three vtable rows point at
    //   0x100a4e368) and whose SETTER inlines urlPos' own didSet — end = max(end, newValue)
    //   plus updateDownloadSpeed, both under `newValue != .max` — then mirrors the result
    //   into this class's `fakeUrlPos`. Same body as PreLoadIOContext#slot12 @0x101ba6e04
    //   against that class's fakeUrlPos. Name unrecoverable → deferred, not guessed.

    // --- inits ---

    // Designated init s22 @101ba4650 → inner FUN_101ba4650 (cached, READABLE). The
    // decompile sets all 8 own fields directly:
    //   loadMoreBuffer = nil (+loadMoreBuffer = 0), fakeUrlPos = 0, moreUrlPos = 0,
    //   _timeIndex = [] (PTR___swiftEmptyArrayStorage), _timeIndexLock = NSLock()
    //     (allocWithZone(__NSLock) + init), moreDownload = param_2 (value-copied via
    //     FUN_1001263e0), maxFileSize = param_7, maxReadedFileSize = param_8,
    // then delegates to CacheIOContext's designated init FUN_101b86d38 with the
    // download value (param_1, value-copied) + cacheKey/bufferSize/saveFile/
    // isReadComplete (param_3..param_6, param_9). Arity/param-order inferred (no
    // mangled init symbol); the field stores + the super-delegation are explicit in
    // the decompile and transcribed here. The `moreDownload` and `download` values are
    // copied (FUN_1001263e0) rather than freshly built — reflected as plain params.
    public init(download: URLContextDownload?, moreDownload: URLContextDownload?,
                cacheKey: String, bufferSize: Int32 = 32 * 1024, saveFile: Bool,
                isReadComplete: Bool, maxFileSize: UInt64, maxReadedFileSize: UInt64) {
        self.loadMoreBuffer = nil          // binary: *(self+loadMoreBuffer) = 0
        self.fakeUrlPos = 0                // binary: *(self+fakeUrlPos) = 0
        self.moreUrlPos = 0                // binary: *(self+moreUrlPos) = 0
        self._timeIndex = []               // binary: *(self+_timeIndex) = swiftEmptyArrayStorage
        self.moreDownload = moreDownload   // binary: FUN_1001263e0 value-copy of param_2
        self.maxFileSize = maxFileSize     // binary: *(self+maxFileSize) = param_7
        self.maxReadedFileSize = maxReadedFileSize // binary: *(self+maxReadedFileSize) = param_8
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete) // binary: FUN_101b86d38
    }

    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot21:0x101ba4308 result=pinned — throwing convenience init; 8 labels unrecoverable]
    //   CORRECTION: the previous note here ("devirtualized, the binary has no readable
    //   body") is FALSE. Slot 21 is a 210-instruction, fully readable function. It is
    //   PINNED because its argument LABELS are unrecoverable, NOT because it is empty.
    //
    //   What is proven about it:
    //   • It is an ALLOCATING init entry: `self` rides x20 as a METATYPE, and the body's
    //     one dispatched call is `ldur x20,[x29,#-0xe0]; ldr x8,[x20,#0x530]; blr x8`
    //     @0x101ba459c. vtable_walk reports VTableOffset=144 words (0x480) for this class,
    //     so metadata+0x530 = 0x480 + 22*8 = SLOT 22 — the designated init reconstructed
    //     above. An allocating entry that dispatches its own class's designated init
    //     through the metatype is a CONVENIENCE init (convenience inits have no separate
    //     initializing entry, which is also why the slot body is 210 instructions and not
    //     the ~13-instruction alloc+tail-call thunk an Init slot usually holds).
    //   • It THROWS and PROPAGATES (it does not catch): x21 (the arm64 swifterror
    //     register) is saved into x27 at entry, re-supplied before each call, tested with
    //     `cbz x21` after each, and restored into x21 in the epilogue alongside the
    //     returned object. Both error edges jump to the SAME epilogue with the error
    //     still live.
    //   • Ghidra's `/* WARNING: Removing unreachable block (ram,0x000101ba4514) */` is
    //     that SECOND error edge, and it hides NO source construct: disassembled, the
    //     block is `swift_release(obj1)` → URL value-witness `destroy` → the options
    //     bridgeObjectRelease → `b 0x101ba460c`, i.e. pure ARC unwind on the throw path.
    //     (Ghidra dropped it because it cannot model `bl` clobbering the swifterror
    //     register, so it proved x21==0 on that edge.)
    //   • It builds TWO URLContextDownloads before delegating — which is exactly this
    //     class's `download` + `moreDownload` pair. That identification is not a guess:
    //     `FUN_101b90c44(0)` is a metadata accessor
    //     (`adrp x1,cache; adrp x2,0x1039f5a64; b swift_getSingletonMetadata`) and
    //     descriptor 0x1039f5a64 is URLContextDownload's own entry in
    //     classmap_1.3.17.jsonl, which independently records 0x101b90c44 as its accessor;
    //     its result then feeds `swift_allocObject(md,[md+0x30],[md+0x34])`, and
    //     `FUN_101b90c58` is the initializing init URLContextDownload.swift already
    //     documents as the SHARED 7-arg inner init. Each gets a value-witness COPY of the
    //     SAME incoming Foundation.URL (`Foundation::URL` type-metadata accessor
    //     @0x103452464, then VWT+0x10 `initializeWithCopy` into two `__chkstk_darwin`
    //     allocas), so the convenience init's first parameter is a URL.
    // ⚑[tool=vtable_walk ref=type_metadata_accessor_for_URLContextDownload:0x101b90c44 result=desc 0x1039f5a64 = URLContextDownload (classmap)]
    // ⚑[tool=prefetch_decompiles ref=URLContextDownload.init.inner:0x101b90c58 result=shared 7-arg inner init, per URLContextDownload.swift]
    // ⚑[tool=disassemble_function ref=FUN_101a08224:0x101a08224 result=pinned — unnamed; called (optionsReceiver, GOT[0x104112ce0]+8), 1-word result passed by address to the URLContextDownload init then outlined-destroyed]
    // ⚑[tool=disassemble_function ref=FUN_100029440:0x100029440 result=pinned — unnamed; source operand is a 24-byte Any box (Int 100000 payload, Swift.Int metadata at +0x18)]
    // ⚑[tool=disassemble_function ref=FUN_101b9b5ac:0x101b9b5ac result=pinned — unnamed; receiver in x20, args = the "rw_timeout" small string + a swift_isUniquelyReferenced_nonNull_native flag + an INDIRECT value]
    // ⚑[tool=disassemble_function ref=FUN_1019f0d98:0x1019f0d98 result=pinned — unnamed; String→String, its result is the String passed in the designated init's cacheKey position]
    // ⚑[tool=disassemble_function ref=FUN_101b86a2c:0x101b86a2c result=pinned — unnamed; called with the incoming URL's address in the self register x20, returns the String fed to 0x1019f0d98]
    // ⚑[tool=disassemble_function ref=FUN_10323b034:0x10323b034 result=pinned — outlined destroy, called on the address of that 1-word value]
    //   • Between the two, it sets ONE FFmpeg AVOption on an options dictionary:
    //     key "rw_timeout" — recovered from the small-string immediates
    //     `mov x1,#0x7772; movk …#0x745f,#0x6d69,#0x6f65` = "rw_timeo" and
    //     `mov x2,#0x7475; movk x2,#0xea00,LSL#48` = "ut" with discriminator 0xea
    //     (0xe0 | count 10) — and value `Int(100000)` (`mov w9,#0x86a0; movk w9,#0x1,LSL
    //     #16`) boxed into a 24-byte `Any` existential whose metadata word sits at +0x18
    //     (`PTR___type_metadata_for_Swift_Int_104111920`). The receiver is mutated through
    //     x20 with a `swift_isUniquelyReferenced_nonNull_native` guard and released with
    //     `swift_bridgeObjectRelease` — the Dictionary COW signature — and the value is
    //     passed INDIRECTLY, so the dictionary's Value is address-only, i.e. `[String: Any]`.
    //   • The delegating call passes bufferSize = `mov w4,#0x40000` (262144 = 256 KiB),
    //     NOT the 32 KiB default.
    //
    //   Why it is NOT written: eight argument labels and three parameter TYPES
    //   (`FUN_101a08224`, `FUN_100029440`, `FUN_101b9b5ac`, `FUN_1019f0d98`,
    //   `FUN_101b86a2c` are all unnamed, and recover_swift_function_name @0x101ba4308
    //   returns None with no labels), so every label would be invented. Deferred, not
    //   guessed. — P2
    //
    //   OPEN QUESTION for the owner phase (evidence, not a change made here): the
    //   delegating call at 0x101ba45cc loads `ldp x6,x7,[x29,#-0xf0]` — TWO 64-bit values
    //   in x6/x7 — and pushes a Bool onto the stack (`strb w9,[sp,#-0x10]!`), with the
    //   other Bool in w5 and bufferSize in w4. That register assignment fits the order
    //   (…, bufferSize: Int32, <Bool>, <UInt64>, <UInt64>, <Bool>) and NOT the order
    //   declared above (…, bufferSize, saveFile, isReadComplete, maxFileSize,
    //   maxReadedFileSize), which would place the two Bools in w5/w6. Which Bool is
    //   `saveFile` and which is `isReadComplete` is NOT determinable from the binary
    //   (both are 1-bit), so the declaration above is left untouched rather than
    //   reordered on a guess.

    // s26 @101ba4b68 — `var bufferedBytes: Int` (name inferred, devirt). FAITHFUL (full):
    //   the lone getter between the slot 23-25 triple and the first method at slot 27, so
    //   it is declared here, after the inits. Reads only this class's own `fakeUrlPos`
    //   (exclusivity check elided — own field, no beginAccess emitted) and the inherited
    //   `logicalPos`. logicalPos@+0x80 is source-pinned rather than decompiler-guessed:
    //   CacheIOContext.swift documents entryList at self+0x88 with logicalPos immediately
    //   before it, and CacheIOContext#slot24 @0x101b86138 is logicalPos' own generated
    //   getter over that same +0x80. Shape: `fakeUrlPos == .max` (the binary's
    //   0xffffffffffffffff sentinel) → 0; `logicalPos > fakeUrlPos` → 0; else the
    //   difference clamped — the unsigned compare of the UInt64 difference against
    //   0x8000000000000000 selecting 0x7fffffffffffffff (Int.max) is `Int(clamping:)`.
    //   PreLoadIOContext#slot52 @0x101ba9e44 is the same property over that class's fields.
    // ⚑[tool=prefetch_decompiles ref=LimitSeparatePreLoadIOContext.bufferedBytes.getter:0x101ba4b68 result=body full; NAME inferred]
    var bufferedBytes: Int { // name inferred (devirt)
        guard fakeUrlPos != .max, logicalPos <= fakeUrlPos else {
            return 0
        }
        return Int(clamping: fakeUrlPos - logicalPos)
    }

    // --- methods ---

    // s27 @101ba4bd0 — `func addTimeIndex(position:time:)` (name inferred, devirt;
    //   109 instr). FAITHFUL SPINE.
    //
    // The cached decompile locks _timeIndexLock, then performs a SORTED insert-or-update
    // into _timeIndex keyed by `position` (the ulong param_2, compared against each
    // entry's +0x20 / TimeIndexEntry.position over a 0x10-stride buffer):
    //   • scan for the first entry whose position >= the new position;
    //   • position already present (==)  → replace that entry in place;
    //   • a greater position found (>)   → insert the new entry before it
    //                                      (FUN_101babf50 = Array insert-at-index);
    //   • none found (loop falls off)    → append (reserve/grow + count+1),
    //                                      writing +0x20 = position, +0x28 = time;
    // then unlock. The mutations go through Swift's COW machinery
    // (_swift_isUniquelyReferenced + FUN_101b94710 array-grow + FUN_101bac23c) which
    // the compiler synthesizes from the Array operations below — those unnamed-FUN
    // internals are NOT transcribed by address (see the UNRESOLVED note). `time` is the
    // 8-byte value stored into the entry's time slot (+0x28); `position` is the UInt64
    // search key (+0x20).
    //
    // UNRESOLVED → P8 (IO-completion): the exact COW/grow sequencing (FUN_101b94710 array-grow,
    //   FUN_101bac23c, FUN_101babf50 insert, _swift_isUniquelyReferenced uniqueness
    //   checks) is Swift-synthesized stdlib Array machinery — reproduced here via the
    //   equivalent Array operations rather than transcribed by FUN-address; the
    //   lock / sorted-search / insert-update-append spine is the faithful structure. — P2
    func addTimeIndex(position: UInt64, time: Double) { // name inferred (devirt)
        _timeIndexLock.lock()                  // binary: objc_stub::lock(_timeIndexLock)
        defer { _timeIndexLock.unlock() }      // binary: objc_stub::unlock(self) on every exit
        // binary: scan for the first entry with position >= the new position.
        if let idx = _timeIndex.firstIndex(where: { $0.position >= position }) {
            if _timeIndex[idx].position == position {
                _timeIndex[idx] = TimeIndexEntry(position: position, time: time) // == → replace in place
            } else {
                _timeIndex.insert(TimeIndexEntry(position: position, time: time), at: idx) // > → insert before (FUN_101babf50)
            }
        } else {
            _timeIndex.append(TimeIndexEntry(position: position, time: time)) // none → append (grow + count+1)
        }
    }

    // s28 — 1-instruction stdlib stub → skipped (no reconstructable body).

    // s29 @101ba4e30 — `func loadMorePosition() -> UInt64?` (name inferred, devirt;
    //   346 instr). FAITHFUL (full spine). NO FFmpeg: every call in the glossary is
    //   `_CocoaArrayWrapper.endIndex` (0x103459010), the bridged-element down-cast helper
    //   (0x101b95bfc) or ARC — this is pure Swift over the INHERITED entryList (+0x88),
    //   urlPos (+0x50) and logicalPos (+0x80).
    //
    //   Return type is `UInt64?`, not `(UInt64, Bool)`: the pair comes back in x0/x1 and
    //   EVERY failure edge forces x0 to 0 while setting x1 to 1
    //   (`uVar11 = end < logicalPos; uVar10 = 0; if !that { uVar10 = end }`), i.e. the
    //   payload is dead whenever the flag is set — the Optional payload/extra-tag ABI,
    //   not a meaningful tuple element.
    //
    //   Spine: pick the probe position (`urlPos == 0 ? logicalPos : min(urlPos,
    //   logicalPos)` — the binary really does special-case urlPos == 0 rather than fold it
    //   into the min), binary-search entryList for the entry that CONTAINS it, and if that
    //   misses retry once with `max(urlPos, logicalPos)`; then walk forward from the hit
    //   merging entries whose `position` equals the running end, and return that end
    //   unless it equals urlPos or lies below logicalPos.
    //
    //   The two searches are emitted as two identical loops — an explicit `(low + high)/2`
    //   walk with the Swift `+` overflow trap, a `_swift_release` of the probed element on
    //   the `key < position` edge, and an `isEmpty` pre-check — so they are transcribed
    //   twice here rather than factored into a helper the binary does not contain.
    // UNRESOLVED → P8: two byte-identical search loops are at least as likely to be ONE
    //   private source helper the optimizer inlined at both call sites (P115) as they are
    //   to be duplicated source. Nothing in the binary distinguishes the two spellings, so
    //   the literal form is kept and the alternative is recorded rather than chosen. — P2
    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot29:0x101ba4e30 result=Method; NAME inferred]
    func loadMorePosition() -> UInt64? { // name inferred (devirt)
        let position = urlPos == 0 ? logicalPos : min(urlPos, logicalPos)
        var index: Int?
        if !entryList.isEmpty {
            var low = 0
            var high = entryList.count - 1
            while low <= high {
                let mid = (low + high) / 2
                let entry = entryList[mid]
                if position < entry.position {
                    high = mid - 1
                } else if position < entry.position + UInt64(entry.size) {
                    index = mid
                    break
                } else {
                    low = mid + 1
                }
            }
        }
        // binary: max(urlPos, logicalPos) is computed on BOTH edges of the first search,
        //   before the hit/miss test.
        let retry = max(urlPos, logicalPos)
        if index == nil, retry != position, !entryList.isEmpty {
            var low = 0
            var high = entryList.count - 1
            while low <= high {
                let mid = (low + high) / 2
                let entry = entryList[mid]
                if retry < entry.position {
                    high = mid - 1
                } else if retry < entry.position + UInt64(entry.size) {
                    index = mid
                    break
                } else {
                    low = mid + 1
                }
            }
        }
        guard var cursor = index else {
            return nil
        }
        var end = entryList[cursor].position + UInt64(entryList[cursor].size)
        while cursor + 1 < entryList.count {
            let next = entryList[cursor + 1]
            if next.position != end {
                break
            }
            end += UInt64(next.size)   // binary: CARRY8-trapped UInt64 add
            cursor += 1
        }
        guard end != urlPos, end >= logicalPos else {
            return nil
        }
        return end
    }

    // UNRESOLVED → P8 (IO-completion): s30 @101ba5398 (433 instr) — the limit IO engine.
    //   NOT reconstructed; declare nothing beyond this marker. — P2

    // s31 @101ba5a5c — `func canPreload(_ position: UInt64) -> Bool` (name inferred,
    //   devirt; 250 instr). FAITHFUL (full). Also NO FFmpeg — same three inherited fields
    //   plus this class's own `maxFileSize` / `maxReadedFileSize`, both read through their
    //   ivar-offset globals (`…LimitSeparatePreLoadIOContext::maxFileSize` /
    //   `::maxReadedFileSize`), which is what pins those two reads to THIS class rather
    //   than a sibling's like-named field.
    //
    //   One argument (x0, a ulong) and a Bool return. Body: bail out `true` while the
    //   cache holds fewer than 9 entries; otherwise split the total cached bytes at the
    //   playhead into bytes already behind it and bytes ahead of it, and compare each
    //   against its cap. The `entryList.count - 3` index and the literal 9 are the
    //   binary's own constants (`SBORROW8(count,3)` guard; `if (count < 9) return true`).
    //
    //   The delete path really does MUTATE the inherited entryList: the binary takes a
    //   MODIFY exclusivity scope on +0x88 (`_swift_beginAccess(self+0x88, …, 0x21, 0)`,
    //   flags = Modify|Tracking, closed by `_swift_endAccess`) around a call whose
    //   disassembly is the textbook specialised `Array.remove(at:)` — COW make-unique,
    //   `cmp index,count; b.cs brk` bounds check, load the element at base+0x20+index*8,
    //   `memmove` the tail left by one word, store count-1 — and whose returned element is
    //   immediately `swift_release`d, i.e. discarded.
    // ⚑[tool=disassemble_function ref=Array.remove(at:)_specialized:0x101ba3fd0 result=COW make-unique + bounds check + memmove tail + count-1 + return removed element]
    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot31:0x101ba5a5c result=Method; NAME and argument label inferred]
    func canPreload(_ position: UInt64) -> Bool { // name inferred (devirt)
        if entryList.count < 9 {
            return true
        }
        var readedSize: UInt64 = 0
        var moreSize: UInt64 = 0
        for entry in entryList {
            if logicalPos < entry.position {
                moreSize += UInt64(entry.size)
            } else {
                readedSize += UInt64(entry.size)
            }
        }
        if moreSize > maxFileSize {
            return position < entryList[entryList.count - 3].position
        }
        if readedSize <= maxReadedFileSize {
            return true
        }
        let entry = entryList[1]
        if entry.position + UInt64(entry.size) < logicalPos {
            entryList.remove(at: 1)
            return true
        }
        return false
    }
}
