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
    // ⚠️ STILL OPEN: 0x1044f6910 and 0x1044f6920 are `end` and `urlPos` in SOME order. Both are
    //   `var`, both `UInt64`, both defaulted, so neither width, mutability nor the default axis
    //   separates them. What IS established about 0x1044f6910, and is worth not re-deriving:
    //   it is a scalar and NOT a reference — `seek` traps on bit 63 at 0x101bad080 and then does
    //   `adds`/`b.vs` at 0x101bad084, which is arithmetic on a UInt64, and `fileSize` does an
    //   UNSIGNED max into it (`csel …, hi` @0x101bad4f8).
    //
    //   A HYPOTHESIS, recorded as one and NOT written into any body: the init's five default
    //   stores appear to run in FIELD-DECLARATION order, which would give 0x1044f6910 = `end` and
    //   0x1044f6920 = `urlPos`. Three of the five slots are independently bound above — eof (1st),
    //   logicalPos (3rd) and entryCache (5th) — and all three land exactly where declaration order
    //   predicts. That is suggestive, not decisive, and it is a claim about compiler behaviour
    //   rather than a read, so it needs a golden on a class whose bindings are ALL known before
    //   anything is written from it. Do not confuse it with MEMORY's "offset globals are not in
    //   field-record order", which is about the globals' ADDRESSES and still holds here: 0x910
    //   through 0x940 ascend while the fields they carry do not.
    private var eof: Bool = false
    // end: logical end offset of the cached stream.
    private var end: UInt64 = 0 // ⚑ gate-UNCHECKED; UInt64 by the position-field pattern (siblings gate-confirmed)
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

    // UNRESOLVED: slot 18 @101bad730 — the 576-instr cache-read engine (the lone
    //   AbstractAVIOContext override; deep IO calling stripped FFmpeg/Foundation) →
    //   NOT reconstructed; named only by the P2 oracle. — P2
}
