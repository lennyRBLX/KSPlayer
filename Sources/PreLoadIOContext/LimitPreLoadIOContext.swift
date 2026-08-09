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
    public var canPreload: Bool = true
    // 1  maxFileSize: cap on total file size to preload. init = init param.
    public var maxFileSize: UInt64
    // 2  maxReadedFileSize: cap on bytes read while preloading. init = init param.
    public var maxReadedFileSize: UInt64
    // 3  moovProtectionSize: protected head window (moov atom). init 10_485_760
    //    (binary const 0xa00000).
    public var moovProtectionSize: UInt64 = 10_485_760
    // 4  playbackBytePosition: current playback byte position (exact-or-approx). ⚑
    //    UInt64? (9-byte: payload + tag) — l2_field_gate binary type (brief table had
    //    Int64?; per the brief's FLAG rule the integer is set to the gate's binary
    //    type). init nil per brief (binary s37/s21 store payload 0 + tag byte 1).
    public var playbackBytePosition: UInt64? = nil // ⚑ (composite Optional; gate-typed UInt64?)
    // 5  playbackBytePositionIsExact: whether playbackBytePosition is exact. init false
    //    (binary: byte = 0).
    private var playbackBytePositionIsExact: Bool = false
    // 6  _lastSyncedTime: last time a sync occurred. init -1.0 (binary const
    //    0xbff0000000000000).
    private var _lastSyncedTime: Double = -1.0
    // 7  syncThreshold: min interval between syncs. init 1.0 (binary const
    //    0x3ff0000000000000).
    private let syncThreshold: Double = 1.0
    // 8  lastCheckCacheSize: cache size at last delete-check. ⚑ width-inferred UInt64;
    //    init 0.
    private var lastCheckCacheSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)
    // 9  deleteCheckThreshold: cache growth before a delete-check. ⚑ width-inferred
    //    UInt64; init 4_194_304 (binary const 0x400000).
    private let deleteCheckThreshold: UInt64 = 4_194_304 // ⚑ (width-inferred; gate UNCHECKED)
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
    private var cachedDistribution: (readed: UInt64, contiguousPreload: UInt64,
                             disconnected: UInt64, disconnectedStartIndex: Int?)?
        // binary init: 4 zero words + `strh #0x100` at +32 ⇒ nil (implicit here).
    // 11 cachedDistributionLogicalPos: logical position the distribution covers. ⚑
    //    Int64; init -1 (binary const 0xffffffffffffffff).
    //    TYPE AND DEFAULT ARE READ. Field record 11 is `symref->__got 0x104112b58` =
    //    `_$ss6UInt64VMn` with an EMPTY tail — `UInt64`, not `Int64`, and with `Int64` the
    //    `cachedDistributionLogicalPos == logicalPos` compare in preloadCount() would not even
    //    compile. The default comes from the vpfi at 0x10047dae8, `mov x0,#-0x1 / ret`, which the
    //    compiler SHARES with `cachedDistributionEntryCount` below — one body, all bits set,
    //    read as -1 for Int and UInt64.max for UInt64.
    //    ⟨spelling: the VALUE 0xFFFFFFFFFFFFFFFF is read; `UInt64.max` vs `~0` is not decidable.⟩
    private var cachedDistributionLogicalPos: UInt64 = UInt64.max
    // 12 cachedDistributionEntryCount: entries in the distribution. field-record Int;
    //    init -1 (binary const 0xffffffffffffffff).
    private var cachedDistributionEntryCount: Int = -1
    // 13 lastKnownCachedSize: last observed cached size. ⚑ width-inferred UInt64;
    //    init 0.
    private var lastKnownCachedSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)

    // --- init (designated; s37 @101b9d748, READABLE) ---
    //
    // s37 sets all 14 own fields then delegates to CacheIOContext's designated init.
    // The constant fields carry the declared defaults above, so the init body sets only
    // the two caps from params and delegates to super; the super call is
    // CacheIOContext's designated init (PreLoadIOContext has no own init → inherited).
    // Labels AND order are RECOVERED — the comment here used to say "Arity/order of the
    // leading params is inferred (no init mangled symbol)". The symbol exists; the class name
    // is word-substituted (`05LimitabC0C`), which is why no literal search found it. The field
    // stores (maxFileSize/maxReadedFileSize) and the super-delegation remain as decompiled
    // (param_6 → maxFileSize, param_7 → maxReadedFileSize; the super-delegation target is
    // CacheIOContext's designated init). `isReadComplete` is LAST, not fifth.
    // ⚑[tool=export_trie_oracle ref=FUN_101b86d38:0x101b86d38 result=IDENTIFIED as $s16PreLoadIOContext05CacheC0C8download3md510bufferSize8saveFile14isReadCompleteAC8KSPlayer16DownloadProtocol_p_SSs5Int32VS2btKcfc — CacheIOContext's designated init, INITIALIZING entry (`cfc`). It was a raw FUN_ only because the class name is word-substituted]  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext05LimitabC0C8download3md510bufferSize8saveFile03maxjH00k6ReadedjH014isReadCompleteAC8KSPlayer16DownloadProtocol_p_SSs5Int32VSbs6UInt64VAPSbtKcfc result=labels+order RECOVERED]
    // `download` is the EXISTENTIAL `any DownloadProtocol`: the mangle above spells it
    // `8KSPlayer16DownloadProtocol_p`, where `_p` marks the existential, while the same module's
    // HLSCacheIOContext init mangles a concrete one as `AcA18URLContextDownloadC_`. Corroborated
    // by the ABI in the subclass that delegates through here — LimitCountPreLoadIOContext's init
    // @0x101ba26c4 passes download by ADDRESS and copies it with the outlined existential helper
    // 0x1001263e0 (metadata at +0x18, witness table at +0x20, then a value witness = a 40-byte
    // box). See CacheIOContext.swift:166, which read the same 40-byte copy independently.
    // The optionality is STILL DIVERGENT: no `Sg` in the mangle, so the binary's parameter is
    // non-optional. Blocked on the `download: nil` P8 spines at CacheIOContext.swift:211 and
    // LimitSeparatePreLoadIOContext.swift:346 — see LimitCountPreLoadIOContext.swift. The
    // existence-check for the value those spines stand in for LOCATED it:
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext18URLContextDownloadC3url5flags7options9interrupt14isReadCompleteAC10Foundation3URLV_s5Int32VSpys13OpaquePointerVSgGSgSo15AVIOInterruptCBVSbtKcfc:0x101b90c58 result=LOCATED]
    init(download: any DownloadProtocol, md5: String, bufferSize: Int32 = 32 * 1024,
         saveFile: Bool, maxFileSize: UInt64, maxReadedFileSize: UInt64,
         isReadComplete: Bool) throws {
        self.maxFileSize = maxFileSize            // binary s37: self.maxFileSize = param_6
        self.maxReadedFileSize = maxReadedFileSize // binary s37: self.maxReadedFileSize = param_7
        // binary s37: the remaining 12 own fields are set to the constants carried as the
        //   declared defaults above; PreLoadIOContext's inlined field inits in the
        //   decompile (loadMoreBuffer/_timeIndex/_playbackSnapshot/etc.) are the compiler
        //   flattening the chain and belong to PreLoadIOContext — NOT re-set here.
        // binary s37: delegates to CacheIOContext's designated init (FUN_101b86d38),  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
        //   inherited through PreLoadIOContext.
        try super.init(download: download, md5: md5, bufferSize: bufferSize,
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
    public var cachedSize: UInt64 { // name inferred (devirt)
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
    // ⚑ 0x10002c740 — `mov w0, #0x1` / `ret`. Unconditional true; the body reads no field and
    // takes no branch. That address is the image's canonical `return true` and is ICF-folded, so
    // the constant is precisely what it establishes, and precisely what this declares.
    // Signature from the trie:
    // `PreLoadIOContext.LimitPreLoadIOContext.canReadFromNetwork() -> Swift.Bool`.
    // Unlike the sibling name on CacheIOContext, this one is NOT the same body — CacheIOContext's
    // canReadFromNetwork is 3 instructions at 0x101b885ac (a forward to canAccessNetwork), while
    // this one is the constant.
    // ⚑ s106: `override` added. The base declared no `canReadFromNetwork` until this session, so
    //   this declaration was previously a new member rather than an override; once the base's was
    //   declared the compiler required the keyword, which is the inheritance the vtable showed all
    //   along — this class's slot overrides CacheIOContext's.
    /// @0x101b8a0e0 — the SAME address as `CacheIOContext.shouldContinueRead`, ICF-folded across
    /// all three classes in this hierarchy (each exports its own mangled name). `override_table.py
    /// --impl` confirms this class overrides it.
    ///
    /// The returned value is read, and it is the base's: `ldrb` the inherited Bool field, then
    /// `bic w0, #1, w8` — the negation of `_isClosed`.
    /// ⚑ The SPELLING is constrained rather than chosen. `_isClosed` is PROVABLY private — the
    ///   trie carries its initializer as `…_isClosed33_D69EFE1402863CA716A3171C7DB6DFB9LLSbvpfi`,
    ///   and a per-file discriminator is what `private` emits — so this subclass cannot read it,
    ///   in this file or any other (Swift denies a subclass access to a `private` superclass
    ///   member even in the same file). A body spelled `!_isClosed` here is therefore impossible,
    ///   and the earlier attempt to make it possible by widening that field to `internal` was
    ///   reverted as a false ACCESS claim. `super.shouldContinueRead()` is the one spelling that
    ///   compiles AND yields this code: the base is internal and non-open, so it devirtualises and
    ///   inlines, leaving a body byte-identical to the base's — which is exactly what lets ICF
    ///   fold the three.
    /// ⚑[tool=export_trie_oracle ref=CacheIOContext._isClosed:vpfi result=private-33_D69EFE…LL]
    override func shouldContinueRead() -> Bool {
        super.shouldContinueRead()
    }

    override public func canReadFromNetwork() -> Bool {
        true
    }

    /// @0x101b9dd1c, 113 instructions. `override` is proven, not inferred from the base having a
    /// `canAccessNetwork()`: ⚑[tool=override_table ref=LimitPreLoadIOContext.canAccessNetwork:0x101b9dd1c result=YES-index-2]
    ///
    ///   · the first statement reads `stopOnLimitReached` (global 0x104c63920, inherited from
    ///     CacheIOContext) under a (0, 0) beginAccess; `cmp w8,#1 / b.ne` goes straight to the
    ///     `mov w0,#1` return. So a false flag short-circuits to `true` — the limit is only
    ///     enforced when the caller asked for it.
    ///   · `fetchedSize` (global 0x104c63928, `Int64`) is loaded and immediately
    ///     `tbnz x21,#0x3f` → `brk`. A trap on the sign bit is the `UInt64(_:)` conversion, which
    ///     is why the comparison below is unsigned throughout.
    ///   · the array is `self + 0x88` as a CONSTANT immediate, not an offset global — this class
    ///     is `metadata_init=1` so there is no static field-offset vector, and the offset resolver
    ///     REFUSES 0x88. It is identified two ways that agree: CacheIOContext.swift:95 already
    ///     pins `entryList` at self+0x88, and each element here is dereferenced through the
    ///     offset global for `CacheFileEntry.size : Swift.UInt32` (0x104c63950), so the ELEMENT
    ///     type is CacheFileEntry. Identified by what it holds, never by position.
    ///   · the loop is a native-array walk with the `_CocoaArrayWrapper.endIndex` bridged fallback
    ///     the compiler always emits; `ldr w24` is the 32-bit `size` and `adds x27,x27,x24` with
    ///     `b.lo` to continue is a checked UInt64 accumulate (the carry path is a `brk`).
    ///   · `csel x19, x27, x8, hi` after `cmp x27, x8` is `max(total, UInt64(fetchedSize))`.
    ///   · `maxFileSize` (global 0x104c63988, `UInt64`) is then compared `b.hs` → `mov w0,#0`,
    ///     so the result is `< maxFileSize` and the boundary is EXCLUSIVE: reaching the cap
    ///     exactly returns false.
    /// ⚑[tool=recover_field_offsets ref=CacheFileEntry.size:0x104c63950 result=UInt32]
    override public func canAccessNetwork() -> Bool {
        guard stopOnLimitReached else {
            return true
        }
        return max(entryList.reduce(0) { $0 + UInt64($1.size) }, UInt64(fetchedSize)) < maxFileSize
    }

    /// @0x101b9dee0, 177 instructions. Signature from the trie — BOTH parameters are `UInt64?`,
    /// and the prologue confirms it: each arrives as a (payload, isNil-flag) pair and each is
    /// gated by `cmp w,#1 / b.eq` past its own store.
    ///
    ///   · `strb wzr` through 0x104c63920 is the FIRST statement and is unconditional —
    ///     `stopOnLimitReached = false`, before either optional is examined.
    ///   · `moovProtectionSize` comes from the `vpWvd` symbol at offset global 0x104c63998, not
    ///     from position: `recover_field_offsets` refuses that global outright. The stored value
    ///     is `mov w8, #0xa00000` = 10_485_760, which independently matches the declaration
    ///     default already on that property above.
    ///   · the log gate is `ldrb` of `KSOptions.logLevel` then `cmp w8,#3 / b.lo` past the call.
    ///     3 is the CASE INDEX (LogLevel's rawValues are 0/8/16/24…, so 3 is `.warning`), and
    ///     `KSLog`'s own `level.rawValue <= KSOptions.logLevel.rawValue` folds to exactly that tag
    ///     compare. `.warning` is KSLog's DEFAULT level, so the source passes no level argument.
    ///   · the message is two literals with two interpolations between them, read off the image:
    ///     56 bytes at 0x103d3f5d0 and 19 at 0x103d3f610, both in the large-string form (count in
    ///     the first word, pointer 32 bytes above the `sub` result). `_StringGuts.grow(79)`
    ///     reserves 56+19+slack, corroborating the pair.
    /// ⚑ The interpolations read the STORED PROPERTIES, not the parameters — each is a fresh
    ///   `beginAccess` + load through the field's own offset global (0x104c63988 at 0x101b9e068,
    ///   0x104c63990 at 0x101b9e0dc) AFTER the two conditional stores. So a nil argument logs the
    ///   value that was already there, which `self.` makes explicit here.
    /// ⚑[tool=export_trie_oracle ref=LimitPreLoadIOContext.moovProtectionSize:0x104c63998 result=vpWvd-named-UInt64]
    /// ⚑[tool=decode_string_literal ref=0x103d3f5d0:56 result='[CacheIOContext] switched to playback mode, maxFileSize=']
    /// ⚑ ACCESS not independently proven: no private discriminator on the symbol, and a method
    ///   carries no `vpMV`. `public` matches every sibling in this class.
    public func switchToPlaybackMode(maxFileSize: UInt64?, maxReadedFileSize: UInt64?) {
        stopOnLimitReached = false
        if let maxFileSize {
            self.maxFileSize = maxFileSize
        }
        if let maxReadedFileSize {
            self.maxReadedFileSize = maxReadedFileSize
        }
        moovProtectionSize = 10_485_760
        KSLog("[CacheIOContext] switched to playback mode, maxFileSize=\(self.maxFileSize) maxReadedFileSize=\(self.maxReadedFileSize)")
    }

    // ⚑ s106 RENAME `resetPlaybackPosition()` → `clearPlaybackPosition()`. The old name carried
    //   its own disclaimer, "name inferred (devirt)", and the inference was never needed: the
    //   export trie names 0x101b9d4dc directly. Arity 0, Void return and the body all match, so
    //   this is a rename, not a signature change. No call sites — the tree-wide grep returns only
    //   this declaration and its own comment.
    //   ⚑[tool=export_trie_oracle ref=LimitPreLoadIOContext.clearPlaybackPosition:0x101b9d4dc result=clearPlaybackPosition-not-resetPlaybackPosition]
    func clearPlaybackPosition() {
        // ⚠️ s109 CORRECTION: this line was `playbackBytePosition = 0`, on the comment's claim that
        //   "the binary writes .some(0)". It writes NIL. For `UInt64?` the payload has no spare
        //   bits, so the Optional carries a separate tag byte, and tag 1 is `.none` — this file's
        //   own field note already says so: "init nil per brief (binary s37/s21 store payload 0 +
        //   tag byte 1)". The same payload-0-plus-tag-1 pair therefore cannot mean `.some(0)` here
        //   and `nil` at the initializer. `syncPlaybackPosition` below writes the identical pair on
        //   its guard path, which is what surfaced the contradiction.
        playbackBytePosition = nil
        playbackBytePositionIsExact = false      // binary: byte = 0
        _lastSyncedTime = -1.0                    // binary const 0xbff0000000000000
        // UNRESOLVED → P8 (IO-completion) (s21 tail @101b9d4dc): the binary then locks PreLoadIOContext's
        //   inherited _playbackSnapshotLock (objc_stub::lock(self._playbackSnapshotLock)),
        //   nils _playbackSnapshot (*p=0; p[1]=0; tag byte=1), and unlocks. Those are
        //   INHERITED PreLoadIOContext fields owned by 1C.7 (not in this class's
        //   reconstruction scope) → preserved as a faithful note, NOT re-set here.
    }

    /// @0x101b9cf78, 96 instructions. Trie:
    /// `syncPlaybackPosition(time: Swift.Double, position: Swift.UInt64?) -> ()`. `override` is
    /// proven, not inferred from the base declaring the same name — `override_table.py --impl
    /// 0x101b9cf78` answers YES at index 0.
    ///
    /// THE GUARD. The first fourteen instructions are a bit-pattern predicate on `time`, not an
    /// `fcmp`, and each test was decoded rather than pattern-matched:
    ///   · `and x9, x8, #0x7fff…` is |bits|; `sub x10, x9, #1` / `cmp` against 0xfffffffffffff
    ///     with `cset lo` is "nonzero and subnormal".
    ///   · `add x11, x9, #0xfff0000000000000` (i.e. −0x0010000000000000) / `lsr #53` /
    ///     `cmp #0x3ff` / `cset lo` is "normal": it reduces to biased-exponent < 0x7ff, and the
    ///     subtraction underflows for zero and subnormals, so those fail it too.
    ///   · `cmp x8, #0` gates BOTH of those results through `csel …, ge`, so they only contribute
    ///     when the sign bit is set.
    ///   · `cmp x9, #0x7ff0000000000000` then two `csinc`s force 1 for infinity (`ne`) and for NaN
    ///     (`le`, since the masked value exceeds the infinity pattern only for NaN).
    /// The disjunction is `!isFinite || (negative && nonzero-finite)`, and `-0.0` falls through
    /// every arm — which is exactly `!(time.isFinite && time >= 0)`. Cross-checked by compiling
    /// `t.isFinite && t >= 0` with `swiftc -O` for arm64-ios: same primitives (the 0xfffffffffffff
    /// subnormal test, the −0x0010000000000000 / lsr 53 / cmp 0x3ff exponent test, the
    /// 0x7ff0000000000000 test, the sign gate), selected as `ccmn`/`ccmp` chains because the probe
    /// returns a Bool where this body branches.
    /// Then `and w8, w1, #0xff` / `cmp #1` takes the same arm when the Optional's tag byte is 1,
    /// i.e. `position` is nil — hence the third guard clause.
    ///
    /// THE TWO ARMS. Both open a MODIFY `swift_beginAccess` (flags 1, 0) on `playbackBytePosition`
    /// (offset global 0x104c639a0, trie-pinned) and write payload + tag byte; the guard arm writes
    /// payload 0 / tag 1 = nil, the success arm the unwrapped value / tag 0.
    /// The two private fields are identified by the VALUE stored, never by global order — the trap
    /// this reconstruction hit twice:
    ///   · 0x1044f4a78 takes a one-byte `strb` (1 on success, 0 on the guard arm) and
    ///     `playbackBytePositionIsExact` is this class's only `Bool` past `canPreload`.
    ///   · 0x1044f4a80 takes the immediate 0xbff0000000000000 = **−1.0** on the guard arm, which is
    ///     precisely `_lastSyncedTime`'s declared init value, and `time` on the success arm.
    /// ⚑ UNRESOLVED tail, preserved rather than written — the same boundary `clearPlaybackPosition`
    ///   above keeps: the binary then loads offset global 0x1044f6228, sends `lock`, writes offset
    ///   global 0x1044f6230 as {Double, UInt64, tag} — `(time, position)` on success, 0/0/tag 1 on
    ///   the guard arm — and sends `unlock`. Those are PreLoadIOContext's inherited
    ///   `_playbackSnapshotLock` and `_playbackSnapshot`, whose tuple-optional layout matches that
    ///   store exactly. Both are declared `private` in another file, so writing this tail would
    ///   mean widening their access with no binary evidence for the wider level — the exact move
    ///   that had to be reverted for `CacheIOContext._isClosed` earlier this session. It stays a
    ///   note until those fields' access is derived.
    /// ⚑[tool=override_table ref=LimitPreLoadIOContext.syncPlaybackPosition:0x101b9cf78 result=YES-index-0]
    /// ⚑[tool=export_trie_oracle ref=LimitPreLoadIOContext.playbackBytePosition:0x104c639a0 result=vpWvd-UInt64-optional]
    override public func syncPlaybackPosition(time: Double, position: UInt64?) {
        guard time.isFinite, time >= 0, let position else {
            playbackBytePosition = nil
            playbackBytePositionIsExact = false
            _lastSyncedTime = -1.0
            // UNRESOLVED → 1C.7: lock 0x1044f6228 (_playbackSnapshotLock), nil 0x1044f6230
            //   (_playbackSnapshot: stores 0, 0, tag byte 1), unlock. Inherited + private.
            return
        }
        playbackBytePosition = position
        playbackBytePositionIsExact = true
        _lastSyncedTime = time
        // UNRESOLVED → 1C.7: lock 0x1044f6228 (_playbackSnapshotLock), store 0x1044f6230
        //   (_playbackSnapshot = (time: time, position: position), tag byte 0), unlock.
        //   Inherited + private.
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
    //     2. caller FUN_101b9f9a0 sets the sret dest, calls, reads the 33 bytes back and  ⚑[tool=resolve_fun_pins ref=FUN_101b9f9a0:0x101b9f9a0 result=RESOLVES_UNIQUELY] = PreLoadIOContext.LimitPreLoadIOContext.reuseEntry(pos: Swift.UInt64, size: Swift.Int32) -> PreLoadIOContext.CacheFileEntry?
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
    // 🚨 THE NAME WAS FABRICATED AND IS NOW READ — note the missing "d". The trie carries
    //   `$s16PreLoadIOContext05LimitabC0C26calculateCacheDistribution33_54C5BFE79C74C4F124A8D6AC1061ABF8LL…`
    //   = `LimitPreLoadIOContext.(calculateCacheDistribution in _54C5BFE79C74C4F124A8D6AC1061ABF8)()`.
    //   `calculateCachedDistribution` was never in the binary. The `LL` discriminator makes it
    //   file-private, hence `private`. It had no caller in the tree, so the rename was free.
    //   ⚠️ THAT LAST CLAUSE IS NOW STALE: `preloadCount()` below calls it (`bl 0x101b9f684` at
    //   0x101ba1f68), which is also the binary's only caller. The rename remains correct.
    // ⚑[tool=vtable_walk ref=LimitPreLoadIOContext.slot44:0x101b9f684 result=Method-last-slot]
    private func calculateCacheDistribution() -> (readed: UInt64, contiguousPreload: UInt64,
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

    /// ⚑[tool=export_trie_oracle ref=LimitPreLoadIOContext.preloadProgress():0x101ba2618 result=43-instr]
    /// Both fields are named by their own `vpWvd`, and their SIGNEDNESS is confirmed by the
    /// conversion opcode rather than assumed:
    ///   · `maxFileSize` (global 0x104c63988) → `ucvtf` — UNSIGNED, matching its `UInt64`.
    ///   · `fetchedSize` (global 0x104c63928, inherited from CacheIOContext) → `scvtf` —
    ///     SIGNED, matching its `Int64`.
    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.fetchedSize:0x104c63928 result=vpWvd-named-Int64]
    ///
    /// `cbz x19` on the loaded `maxFileSize` returns **1.0** for a zero cap — a guard, not a
    /// division-by-zero fallthrough.
    ///
    /// ⚑ The 2^-20 scaling in the binary is NOT part of the semantics and is deliberately not
    ///   reproduced. Numerator and denominator are each multiplied by 2^-10 twice
    ///   (`0x3f50000000000000`), and the `ucvtf …, #0xa` fixed-point form folds one of those in —
    ///   the factors cancel in the quotient. It is overflow avoidance for the Int64/UInt64 range,
    ///   which Swift's `Double(_:)` conversions already handle.
    ///
    /// ⚑ Clamp ORDER is read off the opcodes: `fminnm` against 1.0 first, then `fmaxnm` against
    ///   the constant at 0x103487958, whose value is **0.01** (read from the pool, not assumed).
    ///   So it is `max(min(x, 1), 0.01)` — the floor wins on a tie, and a zero `fetchedSize`
    ///   reports 0.01 rather than 0.
    public func preloadProgress() -> Double {
        guard maxFileSize != 0 else {
            return 1
        }
        return max(min(Double(fetchedSize) / Double(maxFileSize), 1), 0.01)
    }

    /// Forward 1.3.17 @0x101ba1cdc, extent 0x101ba1cdc-0x101ba2618 (2364 B / 591 instr), one symbol.
    ///
    /// It is an OVERRIDE, which is why it carries no method descriptor of its own: override-table
    /// entry 8 pairs impl 0x101ba1cdc with base-method-descriptor 0x1039f6578 =
    /// `method descriptor for PreLoadIOContext.PreLoadIOContext.preloadCount() -> Swift.UInt32`,
    /// under base-class descriptor 0x1039f6380. It is absent from the 45-slot vtable, as an
    /// override should be. Access is written bare to match the base's bare `func` at
    /// PreLoadIOContext.swift:357; the mangling carries no discriminator (so not private) and an
    /// override emits nothing that separates internal from public.
    /// ⚑[tool=override_table ref=LimitPreLoadIOContext.preloadCount:0x101ba1cdc result=entry8-base-0x1039f6578]
    ///
    /// EVERY field this body touches is NAMED, not eliminated — the ObjC ivar list names the
    /// offset globals outright and its 14 entries match `fieldrec`'s 14 records in order:
    /// `canPreload` 0x104c63980, `maxFileSize` 0x104c63988, `maxReadedFileSize` 0x104c63990,
    /// `cachedDistribution` 0x1044f4aa0, `cachedDistributionLogicalPos` 0x1044f4aa8,
    /// `cachedDistributionEntryCount` 0x1044f4ab0, `lastKnownCachedSize` 0x1044f4ab8. The constant
    /// offsets come from those globals' static values: `bufferSize` +0x14, `end` +0x48,
    /// `urlPos` +0x50, `logicalPos` +0x80, `entryList` +0x88.
    /// ⚑[tool=ivar_name_oracle ref=LimitPreLoadIOContext:0x104406c00 result=14-named-in-record-order]
    ///
    /// CONTROL FLOW, re-verified against the binary by the orchestrator rather than taken from the
    /// derivation: `cmp w8,#0x1 / b.ne` on `canPreload` (0x101ba1d18); `cbz w19` on the base result
    /// (0x101ba1de4); `cmp x0,#0x2 / b.lt` on `entryList.count` (0x101ba1e10); `cmp x21,x8 / b.hs`
    /// picking the log arm when `contiguousPreload >= maxFileSize` (0x101ba1ff4); and
    /// `cmp x8,x22 / b.hs` returning `count` when `maxReadedFileSize >= readed` (0x101ba201c).
    ///
    /// `super.preloadCount()` is INLINED at 0x101ba1d24-0x101ba1de4 — it reproduces the base body
    /// @0x101ba6bb8 field for field (isPreloadPaused → eof → `urlPos == end` →
    /// `logicalPos + UInt64(bufferSize) < urlPos`), differing only in that the base's
    /// `csel w0,w8,wzr,lo` is split into a branch because the two arms have different fates here.
    ///
    /// THE LOG MESSAGE IS READ, not paraphrased. `_StringGuts.grow` is called with `w0 = 0xa5`
    /// (0x101ba2118), and `literalCapacity + 2 * interpolationCount` = 149 + 2*8 = 165 = 0xa5 for
    /// exactly the eight segments below — which is why the inconsistent `=` / `:` punctuation is
    /// preserved rather than tidied. Level is `mov w0,#0x3` = `.warning`, gated on
    /// `KSOptions.logLevel` (`cmp w8,#0x3 / b.lo`); `#fileID` decodes to
    /// 'PreLoadIOContext/LimitPreLoadIOContext.swift' and `#line` to `mov w6,#0x207` = 519.
    /// ⚑ 519 exceeds this file's length, so the reconstruction's line numbering does not match the
    ///   original and `#line` cannot serve as a placement gate here.
    /// ⚑ `KSLog(…)` vs `KSLog(level: .warning, …)` is NOT DECIDABLE: `w0 = 3` equals `KSLog`'s
    ///   declared default, so the call site cannot distinguish an omitted argument from an explicit
    ///   one. Written bare, matching every other KSLog site in this file.
    /// ⚑ `first!`/`last!` vs `[0]`/`[count-1]`: both lower to the same trap sequence. The binary
    ///   emits `cbz count → brk` for the first element and a separate `count-1` overflow check plus
    ///   a bounds check for the last, which is consistent with either spelling.
    /// ⚑ The `for` loop vs `reduce`, and `guard` vs `if`, are likewise indistinguishable — the
    ///   ORDER of the four cache conditions is read, the syntax carrying them is not.
    override func preloadCount() -> UInt32 {
        guard canPreload else {
            return 0
        }
        let count = super.preloadCount()
        if count == 0 {
            return 0
        }
        if entryList.count < 2 {
            return count
        }
        var totalSize: UInt64 = 0
        for entry in entryList {
            totalSize += UInt64(entry.size)
        }
        let distribution: (readed: UInt64, contiguousPreload: UInt64,
                           disconnected: UInt64, disconnectedStartIndex: Int?)
        if let cached = cachedDistribution,
           cachedDistributionLogicalPos == logicalPos,
           cachedDistributionEntryCount == entryList.count,
           lastKnownCachedSize == totalSize
        {
            distribution = cached
        } else {
            distribution = calculateCacheDistribution()
            cachedDistribution = distribution
            cachedDistributionLogicalPos = logicalPos
            cachedDistributionEntryCount = entryList.count
            lastKnownCachedSize = totalSize
        }
        if distribution.contiguousPreload >= maxFileSize {
            KSLog("[CacheIOContext] reach maxFileSize=\(maxFileSize) contiguousPreload=\(distribution.contiguousPreload) disconnected=\(distribution.disconnected) first entryLogicalPos=\(entryList.first!.position) last entryLogicalPos:\(entryList.last!.position) logicalPos:\(logicalPos) urlPos:\(urlPos) entryListCount:\(entryList.count)")
            return 0
        }
        if distribution.readed > maxReadedFileSize {
            let entry = entryList[1]
            return entry.maxSize ?? entry.size
        }
        return count
    }
}
