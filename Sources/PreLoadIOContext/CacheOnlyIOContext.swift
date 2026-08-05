import Foundation
import KSPlayer

// CacheOnlyIOContext — an AbstractAVIOContext that serves reads from a set of
// on-disk CacheFileEntry segments (with optional network fallback), rather than
// from a live stream.
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields — __swift5_fieldmd reflection (NAMES + ORDER + COUNT authoritative).
//            The closure / source-context / int field TYPES are ⚑ best-effort
//            (the brief's inferred shapes); confirmed against the binary where a
//            property descriptor exists (see l2_field_gate). `// type inferred`.
//   init   — real designated init s15 @101b95c6c → inner FUN_101b96a28 (cached): a
//            1-arg source init that stores source WEAK into sourceContext + builds 3
//            closures (entryListProvider/endProvider/eofProvider) weakly capturing it.
//            Source param type + closure bodies not deterministically resolvable →
//            UNRESOLVED→P8 (IO-completion); inherited init(bufferSize:) is the compilable spine.
//
// UNRESOLVED: AbstractAVIOContext overrides (read/write/seek) are devirtualized in
//   the binary (no readable body) → NOT reconstructed here; inherited from the
//   superclass. Deferred to P2 (follow-callees). — P2
public class CacheOnlyIOContext: AbstractAVIOContext {
    // --- stored fields (binary __swift5_fieldmd order) ---
    // entryListProvider: supplies the cached segments backing this context.
    // ⚑[tool=binding_gate ref=CacheOnlyIOContext:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • endProvider, entryListProvider, eofProvider — assigned after super.init(); a `let` must be set before it
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    var entryListProvider: (() -> [CacheFileEntry])? // type inferred — ⚑ (closure shape not visible in s15 thunk)
    // endProvider: supplies the logical end offset of the cached stream.
    /// ⚑ RETURN TYPE CORRECTED Int64 → UInt64, from two independent bodies rather than inference:
    /// `fileSize()` @0x101b968c0 and `seek(offset:whence:)` @0x101b96820 each call this closure and
    /// then guard its result with `tbnz …,#0x3f` whose branch target is **`brk #0x1`** — a TRAP.
    /// A set bit-63 trapping is the `UInt64 → Int64` conversion check Swift emits for
    /// `Int64(endProvider())`; an `Int64` closure would need no such guard to be used as an Int64.
    /// ⚑ Do not confuse that with `tbnz …,#0x3f` whose target SETS −1 — that one is a genuine
    ///   negative-value early return. Both shapes appear inside `seek`.
    /// ⚑[tool=disassemble ref=CacheOnlyIOContext.seek:0x101b96820 result=UInt64→Int64-conversion-trap]
    var endProvider: (() -> UInt64)? // ⚑ closure shape still inferred; RETURN type now read
    // eofProvider: reports whether the cached stream is at EOF.
    /// ⚑ Both this and `endProvider` are invoked with `ldp` + `blr` and NO null test, in BOTH
    /// `fileSize()` and `seek(offset:whence:)` — so neither is Optional in the binary. They are
    /// left Optional here only because the real designated init (s15 @0x101b95c6c, which builds all
    /// three closures) is still UNRESOLVED above; without it nothing assigns them and a
    /// non-Optional spelling cannot compile. Fix the init first, then drop the `?` on all three.
    var eofProvider: (() -> Bool)? // ⚑ non-Optional in the binary — see note
    // logicalPos: current logical read cursor across the segment set.
    //   l2_field_gate binary property descriptor resolves UInt64 (brief's `Int64`
    //   ⚑ guess corrected — matches the known CacheEntry.logicalPos UInt64 shape).
    private var logicalPos: UInt64 = 0 // type inferred — ⚑ (brief said Int64; l2 gate → UInt64)
    // sourceContext: optional wrapped upstream context for network fallback.
    //   WEAK reference (binary uses _swift_weakInit/_swift_weakAssign on this field).
    weak private var sourceContext: AbstractAVIOContext? // type inferred — ⚑ (referent class not pinned; AbstractAVIOContext? retained best-effort)
    // allowNetworkFallback: whether misses may fall through to sourceContext. v4 concrete.
    public var allowNetworkFallback: Bool = false
    // requestedBytes: running count of bytes requested (for the byte budget).
    private var requestedBytes: Int64 = 0 // type inferred — ⚑ (unmapped int)
    // maxNetworkBytes: ceiling on bytes served via the network fallback path.
    public var maxNetworkBytes: Int64 = 0 // type inferred — ⚑ (unmapped int)

    // UNRESOLVED: real designated init s15 @101b95c6c → inner FUN_101b96a28 (1 arg = source, stored WEAK
    //   into sourceContext). Builds 3 closures (entryListProvider/endProvider/eofProvider @+0x18/+0x28/+0x38)
    //   that weakly capture source. source param type + closure bodies not deterministically resolvable
    //   → deferred (not reconstructed; inherited init(bufferSize:) is the compilable spine). — P2
    public override init(bufferSize: Int32 = 32 * 1024) {
        super.init(bufferSize: bufferSize)
    }

    // UNRESOLVED: read(buffer:size:) / write(buffer:size:) / seek(offset:whence:)
    //   overrides are devirtualized in the binary (no readable body) — inherited
    //   from AbstractAVIOContext, NOT reconstructed. — P2
}
