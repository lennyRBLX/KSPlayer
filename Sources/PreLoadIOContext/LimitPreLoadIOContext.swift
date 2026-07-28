import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via PreLoadIOContext → CacheIOContext)
import FFmpegKit  // AVIOInterruptCB (inherited interrupt chain — FFmpeg C struct)

// LimitPreLoadIOContext — a PreLoadIOContext (1C.7) extended with size-limited
// preloading: file-size / readed-size caps, a moov-protection window, an exact-or-
// approximate playback byte position, a periodic time-sync threshold, cache-delete
// bookkeeping, and a (~40-byte) cached byte distribution. Reconstructed A-structure-
// faithful from the Forward 1.3.17 binary:
//
//   fields  — the 14 stored properties are orchestrator-RESOLVED (decode_composite +
//             width + init constants); NAMES + ORDER + COUNT + TYPES + DEFAULTS are
//             transcribed verbatim from the brief, NOT re-derived from the decompiles.
//             The ⚑ ones are best-effort (composite/width-inferred) → l2_field_gate
//             UNCHECKs them (expected 0 FLAG). `cachedDistribution` is NO LONGER a
//             placeholder: its type is the labeled tuple recovered verbatim from the
//             field record (see the field comment).
//   init    — the designated init (s37 @101b9d748, READABLE) sets LimitPreLoad's 14
//             own fields (all but the two caps carry the field defaults below) and
//             delegates to CacheIOContext's designated init (inherited through
//             PreLoadIOContext, which has no own init). The decompile ALSO inlines
//             PreLoadIOContext's own field defaults (loadMoreBuffer/_timeIndex/etc.) —
//             that is the COMPILER flattening the init chain; those belong to
//             PreLoadIOContext's declared defaults and are NOT re-set here.
//   methods — s21 (@101b9d4dc) and s44 (@101b9f684) are reconstructed (faithful spine +
//             `// UNRESOLVED` for the unnamed-FUN parts). Their names are devirt→inferred
//             (no mangled method symbol). Everything else — the deep limit/cache IO
//             engine and the null devirt slots — is UNRESOLVED→later phase, marked NOT
//             fabricated (see the tail markers).
//
// PreLoadIOContext / CacheIOContext / TimeIndexEntry are in-module (already committed;
// no import). AVIOInterruptCB resolves via `import FFmpegKit` (the inherited interrupt
// field). Builds via `swift build --target PreLoadIOContext`.

public class LimitPreLoadIOContext: PreLoadIOContext {
    // --- stored fields (binary __swift5_fieldmd order; defaults are the binary's
    //     flattened init constants from s37. Swift synthesizes accessors — do NOT
    //     hand-write get/set) ---

    // 0  canPreload: whether preloading is permitted. init true (binary: byte = 1).
    var canPreload: Bool = true
    // 1  maxFileSize: cap on total file size to preload. init = init param.
    var maxFileSize: UInt64
    // 2  maxReadedFileSize: cap on bytes read while preloading. init = init param.
    var maxReadedFileSize: UInt64
    // 3  moovProtectionSize: protected head window (moov atom). init 10_485_760
    //    (binary const 0xa00000).
    var moovProtectionSize: UInt64 = 10_485_760
    // 4  playbackBytePosition: current playback byte position (exact-or-approx). ⚑
    //    UInt64? (9-byte: payload + tag) — l2_field_gate binary type (brief table had
    //    Int64?; per the brief's FLAG rule the integer is set to the gate's binary
    //    type). init nil per brief (binary s37/s21 store payload 0 + tag byte 1).
    var playbackBytePosition: UInt64? = nil // ⚑ (composite Optional; gate-typed UInt64?)
    // 5  playbackBytePositionIsExact: whether playbackBytePosition is exact. init false
    //    (binary: byte = 0).
    var playbackBytePositionIsExact: Bool = false
    // 6  _lastSyncedTime: last time a sync occurred. init -1.0 (binary const
    //    0xbff0000000000000).
    var _lastSyncedTime: Double = -1.0
    // 7  syncThreshold: min interval between syncs. init 1.0 (binary const
    //    0x3ff0000000000000).
    let syncThreshold: Double = 1.0
    // 8  lastCheckCacheSize: cache size at last delete-check. ⚑ width-inferred UInt64;
    //    init 0.
    var lastCheckCacheSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)
    // 9  deleteCheckThreshold: cache growth before a delete-check. ⚑ width-inferred
    //    UInt64; init 4_194_304 (binary const 0x400000).
    let deleteCheckThreshold: UInt64 = 4_194_304 // ⚑ (width-inferred; gate UNCHECKED)
    // 10 cachedDistribution: the cached byte-distribution snapshot produced by s44.
    //    NOT a placeholder and NOT inferred — the element NAMES, ORDER and TYPES are
    //    transcribed verbatim from this field's own MangledTypeName record
    //    @0x103c38424 (71 bytes), which decodes as an OPTIONAL LABELED TUPLE:
    //      02 33a74d00                 symbolic ref → Swift.UInt64 (the same symref
    //                                  carried by maxFileSize/maxReadedFileSize/
    //                                  moovProtectionSize, i.e. proven = UInt64)
    //      "6readed_"                  element 0: label `readed`
    //      "AA" "17contiguousPreload"  element 1: subst→UInt64, label `contiguousPreload`
    //      "AA" "12disconnected"       element 2: subst→UInt64, label `disconnected`
    //      "SiSg" "0D10StartIndex"     element 3: Int?, label = word-subst 'D'(=word 3,
    //                                  "disconnected") + "StartIndex" → `disconnectedStartIndex`
    //      "t"                         → tuple
    //      "Sg"                        → Optional<tuple>
    //    Layout corroborates the decode twice over: the tuple payload is 33 bytes
    //    (4 words + the Int? tag byte at +32) and the OUTER Optional adds a second tag
    //    byte at +33 — which is exactly why the designated init writes the payload words
    //    as four zero stores and then a single 16-bit `0x0100` at +32 (inner tag 0,
    //    outer tag 1 = nil), and why s44's consumer stores 33 bytes and then
    //    `strb wzr,[x28,#0x21]` (outer tag 0 = .some) at 0x101b9fc7c.
    //    The decode is not hand-waved: feeding the record verbatim to the official
    //    demangler — substituting `Su` for the symbolic reference (a standard
    //    substitution contributes no identifier, so the word-substitution table is
    //    unchanged) —
    //      swift-demangle '$sSu6readed_Su17contiguousPreloadSu12disconnectedSiSg0D10StartIndextSg'
    //      → (readed: Swift.UInt, contiguousPreload: Swift.UInt,
    //         disconnected: Swift.UInt, disconnectedStartIndex: Swift.Int?)?
    //    i.e. the demangler itself resolves the `0D10StartIndex` word substitution to
    //    `disconnectedStartIndex`.
    // ⚑[tool=dump_field_type_mangles ref=LimitPreLoadIOContext.cachedDistribution:0x103c38424 result=0233a74d00367265616465645f41413137636f6e746967756f75735072656c6f616441413132646973636f6e6e656374656453695367304431305374617274496e646578745367]
    var cachedDistribution: (readed: UInt64, contiguousPreload: UInt64,
                             disconnected: UInt64, disconnectedStartIndex: Int?)?
        // binary init: 4 zero words + `strh #0x100` at +32 ⇒ nil (implicit here).
    // 11 cachedDistributionLogicalPos: logical position the distribution covers. ⚑
    //    Int64; init -1 (binary const 0xffffffffffffffff).
    var cachedDistributionLogicalPos: Int64 = -1 // ⚑ (composite/width-inferred; gate UNCHECKED)
    // 12 cachedDistributionEntryCount: entries in the distribution. field-record Int;
    //    init -1 (binary const 0xffffffffffffffff).
    var cachedDistributionEntryCount: Int = -1
    // 13 lastKnownCachedSize: last observed cached size. ⚑ width-inferred UInt64;
    //    init 0.
    var lastKnownCachedSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)

    // --- init (designated; s37 @101b9d748, READABLE) ---
    //
    // s37 sets all 14 own fields then delegates to CacheIOContext's designated init.
    // The constant fields carry the declared defaults above, so the init body sets only
    // the two caps from params and delegates to super; the super call is
    // CacheIOContext's designated init (PreLoadIOContext has no own init → inherited).
    // Arity/order of the leading params is inferred (no init mangled symbol); the field
    // stores (maxFileSize/maxReadedFileSize) and the super-delegation are explicit and
    // grounded in the decompile (param_6 → maxFileSize, param_7 → maxReadedFileSize;
    // FUN_101b86d38 = CacheIOContext's designated init).
    init(download: URLContextDownload?, cacheKey: String, bufferSize: Int32 = 32 * 1024,
         saveFile: Bool, isReadComplete: Bool, maxFileSize: UInt64, maxReadedFileSize: UInt64) {
        self.maxFileSize = maxFileSize            // binary s37: self.maxFileSize = param_6
        self.maxReadedFileSize = maxReadedFileSize // binary s37: self.maxReadedFileSize = param_7
        // binary s37: the remaining 12 own fields are set to the constants carried as the
        //   declared defaults above; PreLoadIOContext's inlined field inits in the
        //   decompile (loadMoreBuffer/_timeIndex/_playbackSnapshot/etc.) are the compiler
        //   flattening the chain and belong to PreLoadIOContext — NOT re-set here.
        // binary s37: delegates to CacheIOContext's designated init (FUN_101b86d38),
        //   inherited through PreLoadIOContext.
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete)
    }

    // --- computed accessor between the init and the methods (vtable slot 38) ---

    // s38 @101b9dbf0 — `var cachedSize: UInt64` (name inferred, devirt). FAITHFUL (full):
    //   vtable_walk puts the init at slot 37 and the first deep-IO method at slot 39, so
    //   this lone getter is declared exactly here. It sums `size` over the inherited
    //   `entryList`: a READ `swift_beginAccess` on +0x88 — source-pinned as entryList by
    //   CacheIOContext.swift's own "entryList (self+0x88)" note, and corroborated by
    //   CacheIOContext#slot27 @0x100a1335c being entryList's generated getter over that
    //   same +0x88 with a `swift_bridgeObjectRetain` — then a straight `for` over its
    //   elements, reading each entry's `size` through the
    //   `CacheFileEntry::size` ivar-offset global (a `uint`, matching this file's sibling
    //   declaration `var size: UInt32`) and accumulating.
    //   Two details fix the types rather than guess them: the accumulator's add is
    //   overflow-trapped at 64 bits (`CARRY8` → a SoftwareBreakpoint, i.e. Swift's UInt64
    //   `+` trap), so the running total is UInt64 and each UInt32 `size` is widened; and
    //   the loop is an explicit index walk with a bridged-array fallback
    //   (`_CocoaArrayWrapper.endIndex` plus the element down-cast helper 0x101b95bfc,
    //   which classify_compiler_helpers reports HELPER via value-witness membership), i.e.
    //   plain `for` codegen over an Array of a class element — NOT a `reduce`, which would
    //   have emitted a closure.
    // ⚑[tool=prefetch_decompiles ref=LimitPreLoadIOContext.cachedSize.getter:0x101b9dbf0 result=body full; NAME inferred]
    var cachedSize: UInt64 { // name inferred (devirt)
        var total: UInt64 = 0
        for entry in entryList {
            total += UInt64(entry.size)
        }
        return total
    }

    // --- methods (only the one cached small method; name devirt→inferred) ---

    // s21 @101b9d4dc — `func resetPlaybackPosition()` (name inferred, devirt; 40 instr).
    //   FAITHFUL SPINE. The decompile resets the playback-position state: under a write
    //   access to playbackBytePosition it stores payload 0 + tag byte 1, sets
    //   playbackBytePositionIsExact = false, and _lastSyncedTime = -1.0; then, under
    //   PreLoadIOContext's inherited _playbackSnapshotLock, it nils _playbackSnapshot
    //   (stores 0,0 + tag byte 1). The _playbackSnapshot/_playbackSnapshotLock writes
    //   touch INHERITED PreLoadIOContext fields (out of this class's field scope — owned
    //   by 1C.7) → that tail is preserved as an UNRESOLVED note, not re-derived here.
    func resetPlaybackPosition() { // name inferred (devirt)
        // binary s21: _swift_beginAccess(&playbackBytePosition); store payload 0 + tag 1.
        //   Brief default is nil; the binary writes .some(0). Match the binary store here:
        playbackBytePosition = 0
        playbackBytePositionIsExact = false      // binary: byte = 0
        _lastSyncedTime = -1.0                    // binary const 0xbff0000000000000
        // UNRESOLVED → P8 (IO-completion) (s21 tail @101b9d4dc): the binary then locks PreLoadIOContext's
        //   inherited _playbackSnapshotLock (objc_stub::lock(self._playbackSnapshotLock)),
        //   nils _playbackSnapshot (*p=0; p[1]=0; tag byte=1), and unlocks. Those are
        //   INHERITED PreLoadIOContext fields owned by 1C.7 (not in this class's
        //   reconstruction scope) → preserved as a faithful note, NOT re-set here.
    }

    // UNRESOLVED → later phase (do NOT reconstruct — their calls are stripped FFmpeg the
    //   P2 oracle names — fabrication risk):
    //   DEEP ENGINE (limit / cache IO → P2):
    //     • s39 (177 instr)  @0x101b9dee0 — limit/cache IO engine
    //     • s43 (1009 instr) @0x101b9e510 — limit/cache IO engine (deepest); one of the
    //       three direct callers of s44 below.
    //   DEVIRT (null, no body): slots 40, 41, 42.
    //   — NOT fabricated.

    // s44 @101b9f684 — `func calculateCachedDistribution() -> (readed: UInt64,
    //   contiguousPreload: UInt64, disconnected: UInt64, disconnectedStartIndex: Int?)`.
    //   LAST vtable slot (VTableSize=45), so it is declared last. FAITHFUL (full body).
    //
    //   The NAME is inferred (recover_swift_function_name → None, no labels). The RETURN
    //   TYPE is NOT inferred: it is the `cachedDistribution` field's own tuple, minus the
    //   outer Optional — see that field's mangle transcription above. Three independent
    //   signals fix it:
    //     1. the prologue saves x8 (`str x8,[sp,#0x20]`) and the epilogue writes the
    //        result through it as 4 words + one byte at +32 ⇒ a 33-byte INDIRECT return,
    //        exactly the tuple payload (the outer Optional's tag byte at +33 is NOT
    //        written here);
    //     2. caller FUN_101b9f9a0 sets the sret dest, calls, reads the 33 bytes back and
    //        re-stores them followed by `strb wzr,[…,#0x21]` — i.e. it wraps the result in
    //        `.some` before assigning it to the Optional field;
    //     3. the four accumulators' arithmetic matches the four labels one-for-one
    //        (below), which is what makes the slot→member mapping evidence and not a guess.
    //   x0-x7 are never read (all four `swift_beginAccess` calls pass 0 in x2/x3), so the
    //   method takes NO arguments; `self` rides x20 as usual.
    //
    //   Body, straight from the decompile:
    //     • READ `swift_beginAccess` on the inherited logicalPos (+0x80) and on this
    //       class's `moovProtectionSize` ivar-offset global, then
    //       `csel x19,x8,x23,hi` = max(moovProtectionSize, logicalPos) — computed ONCE
    //       before the loop (`preloadStart` here), while `logicalPos` is re-read from
    //       +0x80 inside the loop under the same access.
    //     • READ beginAccess on the inherited entryList (+0x88) then an index walk with
    //       the bridged-array fallback (`_CocoaArrayWrapper.endIndex` + the element
    //       down-cast helper 0x101b95bfc) — plain `for` codegen over an Array of a class
    //       element. TWO lock-step counters advance together (both `+1` with an SCARRY8
    //       trap) and only one of them is ever consumed — as the value stored into
    //       `disconnectedStartIndex` — which is `enumerated()` codegen (offset counter +
    //       base position), so the loop is written as such here.
    //     • each entry contributes `end = position + size` (CARRY8-trapped, i.e. the
    //       UInt64 `+` trap) with `size` read through the `CacheFileEntry::size`
    //       ivar-offset global as a `uint` and widened to 64 bits.
    //   Every `-` below is a checked UInt64 subtraction in the binary too (the
    //   `if (end < lower) SoftwareBreakpoint` guards are that trap, not source branches).
    // ⚑[tool=vtable_walk ref=LimitPreLoadIOContext.slot44:0x101b9f684 result=Method, last slot; NAME inferred]
    func calculateCachedDistribution() -> (readed: UInt64, contiguousPreload: UInt64,
                                           disconnected: UInt64, disconnectedStartIndex: Int?) {
        var readed: UInt64 = 0
        var contiguousPreload: UInt64 = 0
        var disconnected: UInt64 = 0
        var disconnectedStartIndex: Int?
        var cursor = logicalPos                                  // binary: uVar18, seeded from +0x80
        let preloadStart = max(moovProtectionSize, logicalPos)   // binary: csel …,hi (uVar2)
        for (index, entry) in entryList.enumerated() {
            let position = entry.position
            let size = UInt64(entry.size)
            let end = position + size
            if logicalPos < end {
                if cursor < position {
                    // binary: the tag byte is stored unconditionally (0 on both paths) and
                    //   only the payload is conditional — that is `x == nil` codegen.
                    if disconnectedStartIndex == nil {
                        disconnectedStartIndex = index
                    }
                    disconnected += size
                } else {
                    if position < logicalPos, moovProtectionSize < logicalPos {
                        readed += logicalPos - max(moovProtectionSize, position)
                    }
                    if preloadStart < end {
                        contiguousPreload += end - max(preloadStart, position)
                    }
                    cursor = max(cursor, end)
                }
            } else if moovProtectionSize < end {
                // entry ends at or before the playhead: it is already-read bytes, clipped
                //   to the moov-protection window.
                readed += position < moovProtectionSize ? end - moovProtectionSize : size
            }
        }
        return (readed, contiguousPreload, disconnected, disconnectedStartIndex)
    }
}
