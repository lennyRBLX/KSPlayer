import Foundation
import KSPlayer

// ReadCacheIOContext — an AbstractAVIOContext that reads through a cache, backed by
// a single CacheFileEntry + an optional URLContextDownload, with a tmp staging URL.
//
// STRUCTURE-ONLY this wave (forced by the binary, not a scope choice):
//   fields  — __swift5_fieldmd reflection (NAMES + ORDER + COUNT authoritative;
//             double-run deterministic). Concrete types from field-records; the ⚑
//             ones are unmapped (stdlib ints / Foundation / in-module class) →
//             best-effort + flagged.
//   inits   — the DESIGNATED field-store init is DEVIRTUALIZED (descriptor slot 16 =
//             new-unresolved, addr=null, NO readable body). The two readable inits
//             (s15 @101bacb8c, s17 @101bacd64) are CONVENIENCE thunks that build the
//             `download` (via the shared URLContextDownload init FUN_101b90c58) then  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
//             DELEGATE to the devirt slot-16 — so the 8-field store has no readable
//             body to reconstruct. → all real inits UNRESOLVED→P8 (IO-completion) (cardinal: no body,
//             never fabricate). `init(bufferSize:)` is the inherited compilable spine.
//   method  — slot 18 @101bad730 is a single 576-instr method (the cache-read engine;
//             the lone AbstractAVIOContext override) → deep IO → UNRESOLVED→P8 (IO-completion).
//
// NOT exercised by the 1C.9 L3 capability test (that uses CacheIOContext) → structure
// -only is sufficient for Phase 1 (OutputStreamInfo 1C.6 precedent). Full inits +
// read body deferred to P2 (devirt recovery + the FFmpeg oracle).
public class ReadCacheIOContext: AbstractAVIOContext {
    // --- stored fields (binary __swift5_fieldmd order) ---
    // download: the URLContextDownload the convenience inits build (FUN_101b90c58).  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    // ⚑[tool=binding_gate ref=ReadCacheIOContext:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • download, tmpURL — assigned after super.init(); a `let` must be set before it
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    var download: URLContextDownload? // type inferred — ⚑ (built via the shared URLContextDownload init)
    // tmpURL: staging URL for the cache write.
    var tmpURL: URL? // type inferred — ⚑ (Foundation; unmapped in field-records)
    // onlyCache: serve strictly from cache (no network). v4 concrete.
    let onlyCache: Bool = false
    // eof: whether the cached stream is at end. v4 concrete.
    //
    // ⚑ OFFSET GLOBAL 0x1044f6918 IS `eof`. Sessions 112 and 113 both recorded this as an
    //   unbreakable 2-way tie against `onlyCache` — the s113 handoff says in terms that the two
    //   SEMANTIC readings point in opposite directions (`read()` consulting a cache-only policy
    //   flag argues onlyCache; `fileSize()` setting a flag when a probe hits the end argues eof)
    //   and that it must therefore STAY OPEN. Semantics never had to enter it, and the axis that
    //   decides it is MUTABILITY:
    //     · `fileSize()` @0x101bad320 STORES through this global — `mov w9,#1` /
    //       `strb w9,[x21,x8]` at 0x101bad50c, x21 = swiftself — and the trie names that address
    //       `ReadCacheIOContext.fileSize() -> Swift.Int64`, so it is a METHOD, not an initialiser.
    //     · the field records give `onlyCache` flags=0 and `eof` flags=2; flags 0x2 is IsVar.
    //   Swift does not permit assigning a `let` stored property outside an initialiser, so the
    //   mutated global cannot be `onlyCache`. This is a derivation, not a reading of which name
    //   fits better, and it survives the objection the handoff raised.
    //
    //   ⚠️ The sibling byte global 0x1044f6940 is NOT settled by this and must not be assumed to
    //   be `onlyCache` by elimination from one body: its only store is `strb w9,#1` at 0x101baf760
    //   INSIDE the initialiser 0x101baf0cc, where a `let` is perfectly assignable, so the axis
    //   does not fire there and it stays a 2-way candidate.
    // ⚑[tool=recover_field_by_access ref=ReadCacheIOContext.eof:0x1044f6918 result=UNIQUE-byte-mutability]
    // ⚑[tool=fieldrec ref=ReadCacheIOContext.onlyCache:flags result=0-let]
    //
    // ── s113: THE WHOLE OFFSET-GLOBAL MAP FOR THIS CLASS, and what is still open ──────────────
    // The eliminating frame is the DECLARATION-DEFAULT axis, which is a closed set on both sides:
    // the trie lists exactly FIVE `vpfi` fields (end, entryCache, eof, logicalPos, urlPos), and
    // the designated init 0x101baf0cc opens with exactly FIVE default stores, at 0x101baf604,
    // 0x101baf614, 0x101baf620, 0x101baf62c and 0x101baf638. So the five defaulted fields map onto
    // {0x1044f6910, 0x1044f6918, 0x1044f6920, 0x1044f6930, 0x104c639e0}, and the three fields with
    // NO default (download, tmpURL, onlyCache) map onto everything else.
    //
    //   0x104c639e0 = logicalPos   trie-named outright (its own vpWvd), Swift.UInt64.
    //   0x1044f6918 = eof          the mutability axis, above.
    //   0x1044f6930 = entryCache   PROVEN, and not by elimination: `firstEntryContain` loads it at
    //                              0x101bad8a4, `cbz`-checks it (so it is Optional), and then
    //                              indexes the loaded value with `CacheFileEntry.position`'s OWN
    //                              offset global 0x104c63948 — a value indexed by another class's
    //                              field offset is an instance of that class.
    //   0x1044f6938 = tmpURL       by elimination on the no-default axis: only tmpURL and
    //   0x1044f6940 = onlyCache    onlyCache lack a `vpfi` (download is at CONSTANT offset +0x18,
    //                              not through a global at all), and 0x1044f6940 is byte-class
    //                              (`strb` @0x101baf760) while tmpURL is a `Foundation.URL`.
    // ⚑[tool=export_trie_oracle ref=ReadCacheIOContext:vpfi result=5-end-entryCache-eof-logicalPos-urlPos]
    // ⚑[tool=body_fingerprint ref=ReadCacheIOContext.firstEntryContain:0x101bad8a4 result=indexed-by-CacheFileEntry.position]
    //
    // ✅ CLOSED, s114: **0x1044f6910 is `end`** — and NOT by the declaration-order hypothesis below,
    //   which stays refuted. The route that closed it is a READ, not a guess about the compiler:
    //   `seek` LOGS the field it is about to interpolate, so the label names the value.
    //
    //   At 0x101bad13c-0x101bad168 the 28-byte literal `'[ReadCacheIOContext] urlPos '` is appended
    //   and the very next load is `ldr x8,[x8,#0x920]` through **0x1044f6920**, whose value goes
    //   straight into the interpolation buffer. That pins `urlPos` = 0x1044f6920.
    //
    //   ⚑ THE PAIRING IS VALIDATED AGAINST A KNOWN ANSWER before being used, which is the whole
    //     reason it is trustworthy. The next label in the SAME statement is built in registers at
    //     0x101bad1a0-0x101bad1b8 — x0 = 0x6c616369676f6c20, x1 = 0xec000000_3a736f50, i.e.
    //     `" logicalPos:"`, count 12 — and the load that follows it at 0x101bad1c8 goes through
    //     **0x104c639e0**, which the export trie independently names
    //     `direct field offset for …ReadCacheIOContext.logicalPos`. The label-to-value convention
    //     therefore holds on a field bound by an entirely different route.
    //     ⚑[tool=export_trie_oracle ref=ReadCacheIOContext.logicalPos:0x104c639e0 result=vpWvd-logicalPos]
    //
    //   With every other `var` pinned by an independent route — `eof` 0x1044f6918 (mutability axis),
    //   `logicalPos` 0x104c639e0 (vpWvd), `urlPos` 0x1044f6920 (the label above), `entryCache`
    //   0x1044f6930 (loaded, nil'd with `str xzr`, then `swift_release`d at 0x101bad6a4-0x101bad6ac,
    //   which only a class-typed optional can be) — `end` is the only `var` the field records leave
    //   for 0x1044f6910. The arithmetic axis corroborates it independently: `seek` traps on bit 63
    //   at 0x101bad080 and does signed `adds`/`b.vs` at 0x101bad084, and `fileSize` does an unsigned
    //   max into it (`csel …, hi` @0x101bad4f8) — arithmetic, so not the reference-typed candidate.
    //   ⚑[tool=fieldrec ref=ReadCacheIOContext:0x103cc0ccc result=8-fields-5-var]
    //   ⚑[tool=bind_oracle ref=ReadCacheIOContext.entryCache:0x104113030 result=swift_release]
    //
    //   THE SUPERSEDED HYPOTHESIS, kept because its refutation is still load-bearing: the init's
    //   five default stores appear to run in FIELD-DECLARATION order, which would give the same
    //   answer for the wrong reason. It is a claim about compiler behaviour rather than a read.
    //
    //   ❌ THAT GOLDEN WAS RUN, ON KSPlayerLayer, AND THE HYPOTHESIS FAILED IT. DO NOT USE IT.
    //   KSPlayerLayer is the ideal control — 11 `vpfi` fields, with `delegate` and
    //   `isAutoReplaceAndConstrainPlayerView` both trie-bound at known declaration positions — and
    //   its designated init 0x1019ca41c does NOT lay the defaults down as one contiguous run in
    //   declaration order. `delegate`'s global 0x1044e6138 is touched at 0x1019ca578, far ahead of
    //   the run at 0x1019ca650-0x1019ca688, and that run then CONTINUES past the defaulted fields
    //   into ordinary init-body assignments — 0x104c634f8 is `url`, which carries no `vpfi` at all,
    //   and 0x104c63508 takes `strb w9` with w9 = 1. So a store's POSITION in an init does not
    //   identify its field: defaults and body assignments interleave, and the run has no readable
    //   boundary. ReadCacheIOContext's init merely happens to look tidy.
    //   ⚑[tool=function_extents ref=KSPlayerLayer.init:0x1019ca41c result=416-instr-no-contiguous-default-run]
    //
    //   ⚠️ A SEPARATE FINDING fell out of that control and is NOT this class's business, but should
    //   not be lost: KSPlayerLayer's init stores **1** into 0x104c63508 at 0x1019ca698, and
    //   `recover_field_offsets` binds that global to `isAutoReplaceAndConstrainPlayerView`, which
    //   KSPlayerLayer.swift declares `= false`. That is either an init-body assignment or a
    //   divergent declaration default, and it needs its own row.
    //
    //   Do not confuse any of this with MEMORY's "offset globals are not in
    //   field-record order", which is about the globals' ADDRESSES and still holds here: 0x910
    //   through 0x940 ascend while the fields they carry do not.
    private var eof: Bool = false
    // end: logical end offset of the cached stream.
    private var end: UInt64 = 0 // UInt64 read from the field record (symref -> __got 0x104112b58 = _$ss6UInt64VMn); offset global 0x1044f6910, closed s114 — see above
    // logicalPos: current logical read cursor.
    public var logicalPos: UInt64 = 0 // UInt64 — l2_field_gate binary signal (unscoped; matches CacheOnlyIOContext.logicalPos)
    // urlPos: current position within the backing download.
    private var urlPos: UInt64 = 0 // UInt64 — l2_field_gate binary signal (unscoped)
    // entryCache: the single backing cache entry. v4 concrete (references CacheFileEntry).
    private var entryCache: CacheFileEntry? // field-record concrete

    // UNRESOLVED: real inits → P2. Designated field-store init = descriptor slot 16
    //   DEVIRTUALIZED (addr=null, no body). Convenience inits s15 @101bacb8c + s17
    //   @101bacd64 build `download` then delegate to the devirt slot-16 (vtable+0x180)
    //   → the 8-field store has no readable body. Not reconstructed; init(bufferSize:)
    //   is the inherited compilable spine. — P2
    public override init(bufferSize: Int32 = 32 * 1024) {
        super.init(bufferSize: bufferSize)
    }

    /// @0x101bad688, 42 instructions. `override_table.py --impl` answers YES at index 3.
    ///
    ///   · the first statement loads a field, stores `xzr` over it and calls `swift_release`
    ///     (__got 0x104113030) on the old value. ONE word stored and a NATIVE release — not
    ///     `swift_unknownObjectRelease` — so the field is a plain class Optional, which among this
    ///     class's eight fields is `entryCache`; `download` is an existential several words wide
    ///     and would not be cleared by a single `str xzr`.
    ///   · the rest is a `download?.close()`. The helper at 0x10002e588 is a generic outlined
    ///     COPY — it instantiates a type from a mangled name and calls that type's
    ///     `initializeWithCopy` (VWT+0x10) — so the existential is copied to the stack; the copy's
    ///     +0x18 and +0x20 words are its metadata and witness table, `cbz` on the first is the
    ///     Optional's nil test (the `?.`), and `[witness + 0x40]` is req7 of DownloadProtocol.
    ///     0x100012a78 / 0x10003751c are the matching outlined destroys on the two exits.
    ///   · req7 is `close()`, and that is resolved rather than assumed: its witness thunk
    ///     @0x1019e2564 dereferences the box and dispatches `[metadata + 0xa0]`, which
    ///     `vtable_walk AbstractAVIOContext --metadata-offset 0xa0` maps to slot 8 with impl
    ///     0x10000e52c — this image's canonical ICF-folded empty body, matching the empty
    ///     `AbstractAVIOContext.close()`. Declaring that requirement on DownloadProtocol (see
    ///     PlayerDefines.swift) is what makes this call expressible.
    /// ⚑ The binary dispatches `download` as an EXISTENTIAL; this file declares it
    ///   `URLContextDownload?`, which its own comment already marks "type inferred". The field
    ///   record carries a symbolic ref with a `_pSg` tail, i.e. `(any …)?` — a divergence that is
    ///   its own unit and does not change what this body does.
    /// ⚑[tool=override_table ref=ReadCacheIOContext.close():0x101bad688 result=YES-index-3]
    /// ⚑[tool=vtable_walk ref=AbstractAVIOContext:metadata+0xa0 result=slot8-impl-0x10000e52c-empty]
    override public func close() {
        entryCache = nil
        download?.close()
    }

    /// @0x101bad320, 218 instructions. `override_table.py --impl` answers YES at index 2, over the
    /// same base class descriptor as `close()` at index 3 — so this overrides
    /// `AbstractAVIOContext.fileSize()`. The trie gives the return type outright:
    /// `PreLoadIOContext.ReadCacheIOContext.fileSize() -> Swift.Int64`, one symbol, no ICF fold.
    /// ⚑[tool=override_table ref=ReadCacheIOContext.fileSize():0x101bad320 result=YES-index-2]
    ///
    ///   · the `guard let download` is a read, not an inference: 0x10002e588 is a generic outlined
    ///     COPY that instantiates the field's type from the mangled-name record at 0x103572200 —
    ///     whose 9 bytes decode to `DownloadProtocol` + a `_pSg` tail, i.e. `(any DownloadProtocol)?`
    ///     — and copies self+0x18 into a 40-byte existential container. `cbz [sp+0xa8]`
    ///     @0x101bad364 is the nil test on that container's metadata word. (Same divergence the
    ///     `close()` note above records: this file still declares the field `URLContextDownload?`.)
    ///     ⚑[tool=name_type_at_addr ref=ReadCacheIOContext.download:0x103c384f2 result=DownloadProtocol_pSg]
    ///   · `[witness + 0x38]` is req6, called with no formal argument and returning Int64;
    ///     `[witness + 0x30]` is req5, called with `x0 = -1` / `w1 = 2` and returning Int64. Two is
    ///     `SEEK_END`, which PlayerDefines.swift quotes from the C header. `close()` above already
    ///     pins `[witness + 0x40]` as req7, so the neighbouring indices agree.
    ///   · both logs are `KSLog` INLINED at its DEFAULT level: the guard reads the LogLevel tag byte
    ///     through `KSOptions.logLevel.unsafeMutableAddressor` @0x1019b4074 and skips on `b.lo #3`,
    ///     and 3 is also the level handed to the handler reached through
    ///     `KSOptions.logger.unsafeMutableAddressor` @0x1019c0094. Case index 3 is `.warning`.
    ///     ⚑[tool=export_trie_oracle ref=KSOptions.logLevel:0x1019b4074 result=unsafeMutableAddressor]
    ///   · the two field writes use the bindings closed this session: `end` (offset global
    ///     0x1044f6910) takes an UNSIGNED max (`cmp` / `csel …, hi` @0x101bad4f4), and `eof`
    ///     (0x1044f6918) is set with `strb #1` @0x101bad50c. Both happen only on the `size > 0` join.
    ///
    /// ⚑ The `#fileID` literal is 41 chars, `'PreLoadIOContext/ReadCacheIOContext.swift'` — the
    ///   MODULE-qualified form. This tree's `KSLog` declares `file: String = #file`, which would
    ///   materialise an absolute path instead, so that default is itself divergent; it is a separate
    ///   unit and does not change what this body does. `#function` reads `fileSize()` and the two
    ///   `#line` values are 169 and 174.
    ///   ⚑[tool=decode_string_literal ref=ReadCacheIOContext.fileSize():0x103d3fe40 result='PreLoadIOContext/ReadCacheIOContext.swift']
    ///
    /// ⚑ NO AVERROR constant appears in this body — the complete immediate inventory is
    ///   -1, 2, 3, 35, 41, 58, 169, 174 plus the String discriminators. `ffurl_seek2` occurs only as
    ///   LABEL TEXT inside the log message, not as a call; FFmpeg's own `ffurl_seek2` is never
    ///   invoked here.
    ///
    /// ⚑ Two spellings are NOT decided by the binary and are written as the plainer of the pair:
    ///   `csel` cannot separate `max(end, UInt64(size))` from an if-converted
    ///   `if UInt64(size) > end { … }`, and `#line` 169 -> 174 leaves a five-line gap where only
    ///   four statement lines are grounded.
    ///   ⚑[tool=decode_string_literal ref=ReadCacheIOContext.fileSize():0x101bad320 result=line-169-and-174]
    override public func fileSize() -> Int64 {
        guard let download else {
            return Int64(end)
        }
        var size = download.fileSize()
        KSLog("[ReadCacheIOContext] ffurl_seek2 \(size)")
        if size <= 0 {
            size = download.seek(offset: -1, whence: SEEK_END)
            if size < 0 {
                KSLog("[ReadCacheIOContext] Inner protocol failed to seekback end")
                return size
            }
        }
        if size > 0 {
            end = max(end, UInt64(size))
            eof = true
        }
        return size
    }

    // UNRESOLVED: slot 18 @101bad730 — the 576-instr cache-read engine (the lone
    //   AbstractAVIOContext override; deep IO calling stripped FFmpeg/Foundation) →
    //   NOT reconstructed; named only by the P2 oracle. — P2
}
