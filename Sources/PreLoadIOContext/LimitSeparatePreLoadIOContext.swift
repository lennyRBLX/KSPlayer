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
//             _timeIndexLock=NSLock(), moreDownload=param-copied, maxFileSize=x6,
//             maxReadedFileSize=x7) then delegates to CacheIOContext's designated
//             init FUN_101b86d38. PARAM ORDER is no longer inferred — session 62  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
//             recovered it from the super-delegation register map (see the init).
//           — s21 @101ba4308 is a THROWING CONVENIENCE init with a full 210-instruction
//             body (the earlier "devirtualized, no readable body" note was WRONG and is
//             corrected below). Session 62 reconstructed it as a faithful spine: two
//             URLContextDownloads off ONE URL, separated by one AVOption write, then
//             the s22 delegation. Only its argument LABELS remain pinned.
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
public class LimitSeparatePreLoadIOContext: CacheIOContext, PreLoadProtocol {
    // --- stored fields (binary __swift5_fieldmd order; 8 own properties) ---

    // 0  maxFileSize: byte cap for this context. Designated init param-fed (param_7,
    //    8-byte store at +maxFileSize).
    public var maxFileSize: UInt64 = 0
    // 1  maxReadedFileSize: cap on bytes read. Designated init param-fed (param_8,
    //    8-byte store at +maxReadedFileSize).
    public var maxReadedFileSize: UInt64 = 0
    // 2  loadMoreBuffer: scratch buffer for the separate "load-more" download path.
    //    Designated init zeroes it (nil). ⚑ (element/optionality inferred; pointer width).
    var loadMoreBuffer: UnsafeMutablePointer<UInt8>? // ⚑
    // 3  fakeUrlPos: synthetic url position used by the separate-download bookkeeping.
    //    Designated init zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    private var fakeUrlPos: UInt64 = 0 // ⚑

    /// urlPos override — slots 23-25, getter @0x100a4e368 / setter @0x101ba49f8 / modify
    /// @0x101ba4a6c. The note further down this file defers this as "Name unrecoverable"; that is
    /// STALE. `recover_swift_function_name` returning None is not the trie, and the trie names all
    /// three outright as `LimitSeparatePreLoadIOContext.urlPos.getter/.setter/.modify : UInt64`.
    /// A `didSet` override on an inherited stored property is exactly what emits that triple.
    ///
    /// The setter is read in full and splits cleanly into the INHERITED observer and the one line
    /// this class adds:
    ///   · `str x19,[x20,#0x50]` stores the new value FIRST (didSet, not willSet); +0x50 is the
    ///     inherited `urlPos` and +0x48 the inherited `end`, as CacheIOContext.swift already pins.
    ///   · `cmn x19,#1` then `csel …, hi` and a call to 0x101b86044 reproduce CacheIOContext's own
    ///     `urlPos` didSet verbatim — `if urlPos != .max { end = max(end, urlPos); … }` — because
    ///     Swift runs the superclass observer as well as this one, and the compiler inlined it.
    ///     (⚑ that callee is named `updateSpeedSample(newPos:)` by the trie, not
    ///     `updateDownloadSpeed(_:)` as CacheIOContext.swift:297 currently spells it — a separate
    ///     rename, not needed here since this body never names it.)
    ///   · what remains is the final unconditional `str x8, [x20, <fakeUrlPos>]`. On the `.max` arm
    ///     x8 is set to -1 and on the other it is the reloaded `urlPos`; since `.max` IS -1, both
    ///     arms store `urlPos`. So the added observer is a single mirror, with no branch.
    /// ⚑[tool=export_trie_oracle ref=LimitSeparatePreLoadIOContext.urlPos.setter:0x101ba49f8 result=name-recovered]
    override var urlPos: UInt64 {
        didSet {
            fakeUrlPos = urlPos
        }
    }
    // 4  moreDownload: the secondary download feeding the load-more path. The designated
    //    init copies its x1 parameter into this field with FUN_1001263e0, which
    //    disassembles as an EXISTENTIAL-container copy, not a class-ref retain:
    //    `x2=src[0x18]; dst[0x18]=x2; x8=src[0x20]; dst[0x20]=x8; call *(*(x2-8))(dst,src,x2)`
    //    — i.e. it copies the metadata word at +0x18, the witness-table word at +0x20,
    //    and then runs the payload metadata's VWT[0] (initializeBufferWithCopyOfBuffer)
    //    over the 3-word inline buffer. That is the 5-word `any P` layout, and it is the
    //    SAME helper CacheIOContext's designated init uses for its `download`, which is
    //    already declared `(any DownloadProtocol)?`. dump_binary_field_types also reports
    //    this field as fr_category=`complex` (not a concrete class ref).
    //    The convenience init below builds the container explicitly and proves the
    //    protocol: payload[0] = a URLContextDownload instance, +0x18 = URLContextDownload's
    //    metadata, +0x20 = witness table 0x1041d5330, which decode_witness_table resolves
    //    to `AbstractAVIOContext : DownloadProtocol` (the conformance is declared on the
    //    superclass, so the subclass instance rides the inherited witness table).
    //    Session 62 retyped this from `URLContextDownload?`, which was an 8-byte class ref
    //    and could not have been value-copied by FUN_1001263e0.
    // ⚑[tool=disassemble_function ref=outlined_existential_copy:0x1001263e0 result=CONFIRMED — copies metadata@+0x18 + witness@+0x20 + VWT[0] buffer copy]
    // ⚑[tool=decode_witness_table ref=AbstractAVIOContext:DownloadProtocol:0x1041d5330 result=CONFIRMED (conf_desc 0x103568820, 8 requirements)]
    let moreDownload: (any DownloadProtocol)? // ⚑ optionality inferred (a nil existential is a zero metadata word; unobservable here)
    // 5  moreUrlPos: current position within the secondary download. Designated init
    //    zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    private var moreUrlPos: UInt64 = 0 // ⚑
    // 6  _timeIndex: sorted-by-position index of (position,time) entries. Designated
    //    init defaults it to [] (PTR___swiftEmptyArrayStorage). field-record.
    private var _timeIndex: [TimeIndexEntry] = []

    /// ⚑[tool=export_trie_oracle ref=LimitSeparatePreLoadIOContext.close():0x101ba4ad0 result=38-instr]
    /// Both fields are named by ELIMINATION ON TYPE — neither global carries a `vpWvd`, but this
    /// class has exactly EIGHT fields and among them exactly one `NSLock` and exactly one Array:
    ///   · global 0x1044f5c30 receives the ObjC `lock` / `unlock` sends (0x103464ae0 / 0x10346e620,
    ///     the same pair decoded for Anime4KFrameDump.reset) ⇒ `_timeIndexLock`.
    ///   · global 0x1044f5c38 is overwritten with `_swiftEmptyArrayStorage` (__got 0x104112d00)
    ///     under a MODIFY access (`w2 = 1`), with the old value released ⇒ `_timeIndex = []`.
    ///     Storing the empty-array singleton is what makes it `= []` rather than
    ///     `removeAll(keepingCapacity:)`, which would leave the buffer in place.
    ///
    /// ⚑ `super.close()` is a DIRECT `bl 0x101b8c83c` = `CacheIOContext.close()`, which is this
    ///   class's immediate superclass — so the call is `super`, not a re-dispatch. It resolves
    ///   against `AbstractAVIOContext.close()` (PlayerDefines.swift:610) until CacheIOContext's own
    ///   override is reconstructed; that row is still open and 284 instructions.
    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.close():0x101b8c83c result=super-target]
    override public func close() {
        _timeIndexLock.lock()
        _timeIndex = []
        _timeIndexLock.unlock()
        super.close()
    }
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
    private let _timeIndexLock: NSLock = NSLock()

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
    public var timeIndex: [TimeIndexEntry] { // name inferred (devirt)
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

    // Designated init s22 @101ba4650 → inner FUN_101ba4650 (cached, READABLE). The  ⚑[tool=resolve_fun_pins ref=FUN_101ba4650:0x101ba4650 result=RESOLVES_UNIQUELY] = PreLoadIOContext.LimitSeparatePreLoadIOContext.__allocating_init(download: KSPlayer.DownloadProtocol, moreDownload: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, maxFileSize: Swift.UInt64, maxReadedFileSize: Swift.UInt64, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.LimitSeparatePreLoadIOContext
    // decompile sets all 8 own fields directly:
    //   loadMoreBuffer = nil (+loadMoreBuffer = 0), fakeUrlPos = 0, moreUrlPos = 0,
    //   _timeIndex = [] (PTR___swiftEmptyArrayStorage), _timeIndexLock = NSLock()
    //     (allocWithZone(__NSLock) + init), moreDownload = x1 (existential value-copied
    //     via FUN_1001263e0), maxFileSize = x6, maxReadedFileSize = x7,
    // then delegates to CacheIOContext's designated init FUN_101b86d38.  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
    //
    // PARAM ORDER — RESOLVED in session 62; the previous declaration was WRONG here and
    // carried an explicit OPEN QUESTION saying so. It is now read straight off the
    // super-delegation register map at 0x101ba4724-0x101ba4748, which is dispositive
    // because CacheIOContext's own designated init order is already established:
    //     ours x0        -> super x0        = download        (existential, indirect)
    //     ours x1        -> (field)         = moreDownload    (existential, indirect)
    //     ours x2,x3     -> super x1,x2     = md5             (String)
    //     ours w4        -> super w3        = bufferSize      (Int32)
    //     ours w5        -> super w4        = saveFile        (Bool)
    //     ours x6        -> (field)         = maxFileSize     (UInt64)
    //     ours x7        -> (field)         = maxReadedFileSize (UInt64)
    //     ours [x29+0x10] (STACK, ldrb w26) -> super x5 = isReadComplete (Bool)
    // The two Bools were previously guessed to be adjacent (saveFile, isReadComplete in
    // positions 5 and 6); the binary separates them by the two UInt64s, and the one that
    // reaches super's saveFile slot (w4) is ours w5 while the one that reaches super's
    // isReadComplete slot (x5) is the STACK argument. So the Bool ambiguity the old note
    // called "NOT determinable from the binary" IS determinable — through the delegation.
    //
    // maxFileSize vs maxReadedFileSize is likewise no longer positional guesswork. The
    // x6 store goes through ivar-offset GOT slot 0x104c639a8 and the x7 store through
    // 0x104c639b0; get_xrefs_to shows 0x104c639a8 is the slot read by vtable slots 0/1/2
    // and 0x104c639b0 the one read by slots 3/4/5 — i.e. the accessor triples of stored
    // fields 1 and 2 — and canPreload (s31) reads the same two globals under Ghidra's
    // own symbol names `…LimitSeparatePreLoadIOContext::maxFileSize` /
    // `::maxReadedFileSize`. So x6 = maxFileSize and x7 = maxReadedFileSize, named.
    // ⚑[tool=get_xrefs_to ref=LimitSeparatePreLoadIOContext.maxFileSize.ivarOffset:0x104c639a8 result=CONFIRMED — read by slots 0/1/2 + the x6 store @0x101ba4710]
    // ⚑[tool=get_xrefs_to ref=LimitSeparatePreLoadIOContext.maxReadedFileSize.ivarOffset:0x104c639b0 result=CONFIRMED — read by slots 3/4/5 + the x7 store @0x101ba471c]
    //
    // Argument LABELS remain inferred (no mangled init symbol survives); the ORDER and
    // the TYPES above are transcribed, not guessed. `download`/`moreDownload` are
    // existentials because both arrive indirectly and are destroyed on exit with the
    // outlined existential destroy 0x100012a78 (@in/owned indirect params, the same
    // convention the convenience init below uses for its URL).
    public init(download: (any DownloadProtocol)?, moreDownload: (any DownloadProtocol)?,
                md5: String, bufferSize: Int32 = 32 * 1024, saveFile: Bool,
                maxFileSize: UInt64, maxReadedFileSize: UInt64, isReadComplete: Bool) {
        self.loadMoreBuffer = nil          // binary: *(self+loadMoreBuffer) = 0
        self.fakeUrlPos = 0                // binary: *(self+fakeUrlPos) = 0
        self.moreUrlPos = 0                // binary: *(self+moreUrlPos) = 0
        self._timeIndex = []               // binary: *(self+_timeIndex) = swiftEmptyArrayStorage
        self.moreDownload = moreDownload   // binary: FUN_1001263e0 existential copy of x1 @0x101ba4708
        self.maxFileSize = maxFileSize     // binary: *(self+0x104c639a8) = x6 @0x101ba4714
        self.maxReadedFileSize = maxReadedFileSize // binary: *(self+0x104c639b0) = x7 @0x101ba4720
        super.init(download: download, md5: md5, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete) // binary: FUN_101b86d38  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
    }

    // Convenience init s21 @101ba4308 (210 instr — init_thunk_probe: NOT_A_PLAIN_THUNK).
    //   FAITHFUL SPINE + UNRESOLVED → P8 on the two download builds and the cacheKey.
    // ⚑[tool=vtable_walk ref=LimitSeparatePreLoadIOContext.slot21:0x101ba4308 result=Init slot, 210 instr; body written below, 7 argument LABELS still unrecoverable]
    //   CORRECTION: an older note here ("devirtualized, the binary has no readable body")
    //   is FALSE. Slot 21 is a 210-instruction, fully readable function. Session 61 then
    //   PINNED it whole on the grounds that "eight argument labels and three parameter
    //   TYPES" were unknown; session 62 resolved the types (below), so what remains
    //   unrecoverable is the labels alone, and the body is written.
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
    //     `FUN_101b90c44(0)` is a metadata accessor  ⚑[tool=resolve_fun_pins ref=FUN_101b90c44:0x101b90c44 result=RESOLVES_UNIQUELY] = type metadata accessor for PreLoadIOContext.URLContextDownload
    //     (`adrp x1,cache; adrp x2,0x1039f5a64; b swift_getSingletonMetadata`) and
    //     descriptor 0x1039f5a64 is URLContextDownload's own entry in
    //     classmap_1.3.17.jsonl, which independently records 0x101b90c44 as its accessor;
    //     its result then feeds `swift_allocObject(md,[md+0x30],[md+0x34])`, and
    //     `FUN_101b90c58` is the initializing init URLContextDownload.swift already  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    //     documents as the SHARED 7-arg inner init. Each gets a value-witness COPY of the
    //     SAME incoming Foundation.URL (`Foundation::URL` type-metadata accessor
    //     @0x103452464, then VWT+0x10 `initializeWithCopy` into two `__chkstk_darwin`
    //     allocas), so the convenience init's first parameter is a URL.
    // ⚑[tool=vtable_walk ref=type_metadata_accessor_for_URLContextDownload:0x101b90c44 result=desc 0x1039f5a64 = URLContextDownload (classmap)]
    // ⚑[tool=prefetch_decompiles ref=URLContextDownload.init.inner:0x101b90c58 result=shared 7-arg inner init, per URLContextDownload.swift]
    // ⚑[tool=disassemble_function ref=Dictionary.avOptions_builder:0x101a08224 result=LOCATED — zeroes a 1-word slot, captures its ADDRESS into a forEach closure context, runs Sequence.forEach over the dictionary in x20, returns the slot. That is AVFFmpegExtension.swift:447 `[String:Any].avOptions`, which inserts each entry into an OpaquePointer? dictionary — the C entry point it calls is that file's claim to name, not this one's (no address for it is observable here). Its extra x1 = GOT[0x104112ce0]+8, an unresolved metadata operand — the generic Value witness — ⚑ pinned]
    // ⚑[tool=disassemble_function ref=outlined_Any_copy:0x100029440 result=LOCATED — 4-instruction outlined copy of a 32-byte Any; here it moves the Int-100000 box into the value operand, and 0x101b9b5ac tail-calls it to store into the bucket]
    // ⚑[tool=disassemble_function ref=Dictionary.subscript.setter_specialized:0x101b9b5ac result=CONFIRMED — `ldr x20,[x20]` inout receiver, find(key) @0x100020444, count+!found vs capacity, resize @0x101b9bc80, makeUnique @0x101b9b840, hit → values base `[x4,#0x38] + bucket<<5` (STRIDE 0x20 = a 32-byte Any) destroy-then-assign, miss → insert @0x100035948]
    // ⚑[tool=disassemble_function ref=FUN_1019f0d98:0x1019f0d98 result=pinned — unnamed; String→String, its result is the String passed in the designated init's cacheKey position. HLSCacheIOContext.swift:172 independently records it as the `String(UTF8View,count)` re-encode in ITS cache-key derivation]  ⚑[tool=resolve_fun_pins ref=FUN_1019f0d98:0x1019f0d98 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Swift.String.md5() -> Swift.String
    // ⚑[tool=disassemble_function ref=FUN_101b86a2c:0x101b86a2c result=pinned — unnamed; called with the incoming URL's address in the self register x20, returns the String fed to 0x1019f0d98. HLSCacheIOContext.swift:171 independently records it as the segment cache-key String builder (URLComponents queryItems/url, 651B)]  ⚑[tool=resolve_fun_pins ref=FUN_101b86a2c:0x101b86a2c result=RESOLVES_UNIQUELY] = (extension in PreLoadIOContext):Foundation.URL.sortQueryString.getter : Swift.String
    // ⚑[tool=ffmpeg_name_oracle ref=av_dict_free:0x10323b034 result=CONFIRMED]
    // ⚑[tool=ffmpeg_name_oracle ref=av_freep:0x103253ed0 result=CONFIRMED]  (already CONFIRMED at
    //   FormatContext.swift:31/212 for this same address — carried here, not re-derived)
    //   CORRECTION (session 62): the previous note called 0x10323b034 an "outlined
    //   destroy". It is av_dict_free, and the repo had ALREADY confirmed that at
    //   FormatContext.swift:263 and OutputStreamInfo.swift:72/136 — this file was
    //   contradicting a settled fact. The disassembly is textbook av_dict_free:
    //   `m = *pm; if (m) { while (m->count--) { av_freep(&elems[count].key);
    //   av_freep(&elems[count].value); } av_freep(&m->elems); } av_freep(pm)` — the
    //   16-byte AVDictionaryEntry stride (`add x0,x9,w8,SXTW #4`), count at +0, elems at
    //   +8, and av_freep @0x103253ed0 on every edge including the tail. It is in the
    //   oracle's 28-name candidate set for this address, so the structural match names it.
    //   This RETYPES the 1-word slot at [x29-0x88]: it is an `AVDictionary *`, built by
    //   0x101a08224 from the options dictionary, passed BY ADDRESS (`AVDictionary **`) to
    //   the URLContextDownload init, and freed after each of the two builds.
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
    //   PARAMETERS — recovered in session 62 from the entry register saves at
    //   0x101ba432c-0x101ba4344 and the two places each value is consumed:
    //     x0    URL, indirect. Copied TWICE with Foundation.URL's VWT+0x10
    //           `initializeWithCopy` into two `__chkstk_darwin` allocas (one per download),
    //           and DESTROYED by this function on every exit path via VWT+8 on the
    //           caller's own pointer @0x101ba443c / 0x101ba45fc ⇒ @in/owned, the same
    //           convention the designated init uses for its two existentials.
    //     x1    [String: Any], @owned. It is `swift_isUniquelyReferenced_nonNull_native`d,
    //           subscript-set through an inout address in x20, and released with
    //           `swift_bridgeObjectRelease` — and exactly ONE dictionary value is owned at
    //           a time (error edge 1 releases the pre-mutation value in x24, error edge 2
    //           and the success epilogue release the post-mutation value), which is a
    //           single mutable binding, not two locals. It is NOT Optional: the uniqueness
    //           check and the subscript set are unconditional, with no nil test anywhere
    //           between 0x101ba4444 and 0x101ba44a8.
    //     x2,x3 two TRIVIAL words — never retained, never released, forwarded verbatim to
    //           BOTH URLContextDownload inits in the x3/x4 argument positions. ⚑ TYPE
    //           INFERRED as `AVIOInterruptCB` (FFmpeg's {callback, opaque}, 2 pointers,
    //           trivial) from that argument position: HLSCacheIOContext.swift:136 already
    //           types the same URLContextDownload-building surface as
    //           `(url:flags:options:interrupt:)` with `interrupt: AVIOInterruptCB`, and
    //           the init's w1=1 / x2=&AVDictionary* line up with `flags` / `options`.
    //           A 2-word trivial pair is all the binary itself proves.
    //     w4    Bool  -> delegated into slot 22's saveFile position (w5).
    //     x5    UInt64 -> delegated into slot 22's maxFileSize position (x6).
    //     x6    UInt64 -> delegated into slot 22's maxReadedFileSize position (x7).
    //     w7    Bool  -> delegated onto the STACK = slot 22's isReadComplete position.
    //   The last four are named by the delegation, not guessed — see the register map on
    //   the designated init above. bufferSize is NOT forwarded: it is the literal
    //   `mov w4,#0x40000`.
    //
    //   ORDER OF OPERATIONS (this is the load-bearing part, and it is explicit):
    //   download #1 is built from `FUN_101a08224(x24 = the ORIGINAL dictionary)`  ⚑[tool=resolve_fun_pins ref=FUN_101a08224:0x101a08224 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Swift.Dictionary< where A == Swift.String>.avOptions.getter : Swift.OpaquePointer?
    //   @0x101ba43bc, i.e. BEFORE the AVOption write; the "rw_timeout" subscript set runs
    //   @0x101ba44a4; download #2 is built from `FUN_101a08224(x23)` @0x101ba44b8 where  ⚑[tool=resolve_fun_pins ref=FUN_101a08224:0x101a08224 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Swift.Dictionary< where A == Swift.String>.avOptions.getter : Swift.OpaquePointer?
    //   `ldur x23,[x29,#-0xb0]` @0x101ba44a8 reloads the dictionary the setter just
    //   rewrote. So the SECOND download is the one that carries rw_timeout, and the
    //   secondary/"load-more" download is therefore the timeout-bounded one.
    //
    //   STILL PINNED — the argument LABELS. recover_swift_function_name @0x101ba4308
    //   returns None with no labels and no mangled init symbol survives, so the seven
    //   labels written below are INFERRED from the roles above and from the names this
    //   repo already uses for the same surfaces. The order and the types are transcribed.
    // ⚑[tool=export_trie_oracle ref=LimitSeparatePreLoadIOContext.slot21.convenienceInit:0x101ba4308 result=CONFIRMED — labels RECOVERED, no longer inferred]
    //   The session-62 pin here said "no name, no argument labels; the 7 labels below are inferred".
    //   That was wrong: `recover_swift_function_name` and `nm` cannot see this symbol, but the
    //   ORPHANED region of LC_DYLD_EXPORTS_TRIE holds the full mangled name —
    //     …C3url20formatContextOptions9interrupt8saveFile03maxL4Size0m6ReadedlN014isReadComplete
    //       AC10Foundation3URLV_SDySSypGSo15AVIOInterruptCBVSbs6UInt64VARSbtKcfC
    //   which CORRECTS one label (`options:` → `formatContextOptions:`) and independently
    //   CONFIRMS the `interrupt` type as `AVIOInterruptCB` (`So15AVIOInterruptCBV`), which was
    //   itself pinned as a name inference. The designated init above is corrected the same way
    //   (`cacheKey:` → `md5:`, from `…C8download12moreDownload3md510bufferSize…`).
    //
    // UNRESOLVED → P8 (IO-completion): the two `URLContextDownload(url:flags:options:
    //   interrupt:…)` builds are the SHARED inner init FUN_101b90c58, which  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    //   URLContextDownload.swift leaves deferred (it opens an FFmpeg URLContext). They are
    //   NOT reconstructed here; `nil` is delegated in their place, exactly as
    //   CacheIOContext.swift:203-210 does for the same call. — P2
    // UNRESOLVED → P8 (IO-completion): the cacheKey is derived from `url` by
    //   FUN_101b86a2c → FUN_1019f0d98 (both unnamed; HLSCacheIOContext.swift:171-172  ⚑[tool=resolve_fun_pins ref=FUN_101b86a2c:0x101b86a2c result=RESOLVES_UNIQUELY] = (extension in PreLoadIOContext):Foundation.URL.sortQueryString.getter : Swift.String  ⚑[tool=resolve_fun_pins ref=FUN_1019f0d98:0x1019f0d98 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Swift.String.md5() -> Swift.String
    //   pins the same pair in its own cache-key derivation). NOT reconstructed — the
    //   placeholder below is marked and is NOT the binary's value. — P2
    public convenience init(url: URL, formatContextOptions: [String: Any], interrupt: AVIOInterruptCB,
                            saveFile: Bool, maxFileSize: UInt64,
                            maxReadedFileSize: UInt64, isReadComplete: Bool) throws {
        // binary: one owned dictionary, mutated in place between the two download builds.
        var options = formatContextOptions
        // UNRESOLVED → P8: download = try URLContextDownload(url: url, flags: 1,
        //   options: &options.avOptions, interrupt: interrupt) — binary @0x101ba43bc-
        //   0x101ba4420: avOptions built from the PRE-mutation dictionary, the
        //   AVDictionary** passed as x2, then av_dict_free(&avOptions) @0x101ba444c.
        options["rw_timeout"] = 100_000 // binary: Dictionary<String,Any> subscript set @0x101ba44a4
        // UNRESOLVED → P8: moreDownload = try URLContextDownload(url: url, flags: 1,
        //   options: &options.avOptions, interrupt: interrupt) — binary @0x101ba44b8-
        //   0x101ba4508 over the POST-mutation dictionary, av_dict_free @0x101ba4540.
        _ = options // the mutated dictionary feeds the deferred second build above
        let cacheKey = "" // ⚑ PLACEHOLDER — NOT the binary's value; see the UNRESOLVED cacheKey marker
        self.init(download: nil, moreDownload: nil, md5: cacheKey,
                  bufferSize: 256 * 1024, // binary: mov w4,#0x40000 — NOT the 32 KiB default
                  saveFile: saveFile, maxFileSize: maxFileSize,
                  maxReadedFileSize: maxReadedFileSize, isReadComplete: isReadComplete)
    }

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
    // PUBLIC because it witnesses PreLoadProtocol requirement 6. The name is no longer
    // "inferred": the export trie names this body
    // LimitSeparatePreLoadIOContext.addTimeIndex(position: Swift.UInt64, time: Swift.Double).
    public func addTimeIndex(position: UInt64, time: Double) {
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

    // MARK: - KSPlayer.PreLoadProtocol members
    //
    // Requirements 1, 2, 3 and 7 are inherited from CacheIOContext (see the members declared
    // there); 5 and 6 are already declared above. These are the three this class owes.

    // Requirement 0. Body @0x101ba4b68, 26 instructions, and structurally identical to
    // PreLoadIOContext's instruction for instruction — the two differ ONLY in which field-offset
    // global they load, and are NOT ICF-folded with each other. That global is 0x1044f5c40, which
    // the reflection offset/name table names `fakeUrlPos` (an agent could narrow it no further than
    // {fakeUrlPos, moreUrlPos}; the table settles it).
    //
    // Shape, read from the body: load fakeUrlPos; `cmn x19,#0x1` -> if it is the UInt64.max
    // sentinel return 0; else `subs x8, x19, [self+0x80]` against the inherited logicalPos and
    // `b.hs` -> if that subtraction BORROWED (i.e. fakeUrlPos < logicalPos) return 0; otherwise
    // `cmn x8,#0x1` / `csel x0, x8, Int64.max, gt` -> return the difference, saturating to
    // Int64.max when its sign bit is set. Its only call is a read `swift_beginAccess` on logicalPos.
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

    /// ⚑[tool=disassemble ref=LimitSeparatePreLoadIOContext.position.getter:0x101ba41f4 result=20-instr]
    /// An override whose body is IDENTICAL to the base's, which is why it is easy to miss: this is
    /// a separate symbol at a separate address, not the inherited getter.
    /// Read: a read access on self+0x50 and `ldr x0,[x20,#0x50]`, then `cmn x0,#0x1` / `b.ne` —
    /// return that value unless it is the -1 sentinel; otherwise a second read access on self+0x80
    /// and return `ldr x0,[x20,#0x80]`.
    /// The two offsets are named from the SIBLING, not guessed: LimitSeparatePreLoadIOContext's own
    /// accessors reach them by constant immediate so `recover_field_offsets` finds nothing for this
    /// class, but `PreLoadIOContext` — which extends the same CacheIOContext and therefore shares
    /// the inherited layout — maps +0x50 to `urlPos` and +0x80 to the field its `loadedSize` reads,
    /// i.e. `logicalPos`. CacheIOContext.swift:383 anchors the same pair from the other direction.
    /// ⚑[tool=recover_field_offsets ref=PreLoadIOContext:+0x50 result=urlPos]
    /// This is byte-for-byte the base's `position` at CacheIOContext.swift:384, so the override
    /// carries no new behaviour — it is declared because the binary declares it, not because it
    /// differs.
    override public var position: UInt64 {
        urlPos == .max ? logicalPos : urlPos
    }

    // Requirement 8. The witness for this requirement is 0x10000e52c — a BARE `ret`. That is an
    // EMPTY body, not a missing one: this class deliberately does nothing on a playback-position
    // sync, where PreLoadIOContext forwards to its own (time:position:) overload. The address is
    // ICF-folded 420 ways, which is exactly what an empty function attracts.
    public func syncPlaybackPosition(time _: Double, duration _: Double) {}

    // Requirement 4. Body @0x101ba5398, 433 instructions, ONE `ret` with the Int32 result carried
    // in x24, plus nine traps. It returns an FFmpeg-convention Int32: a byte count when positive,
    // otherwise an AVERROR.
    //
    // The five distinct result values, each read at its own site: 0 seeded at 0x101ba5478;
    // 1 at 0x101ba56b0 (the seek branch, taken whether or not the seek succeeded — the sign test
    // only skips the bookkeeping); -1 at 0x101ba5708, emitted on exactly one condition, that the
    // private `canContinuePreload(at:)` @0x101ba5a5c returned false; 0xDFB9B0BB at 0x101ba59cc,
    // which is AVERROR_EOF grounded in the FFmpeg headers (FFERRTAG('E','O','F',' ') = -0x20464F45),
    // emitted only when the read itself returned AVERROR_EOF AND the requested size was >= 1; and
    // the read result itself at 0x101ba593c.
    //
    // Spine, read from the body: branch on the private `findDiscontinuousPos()` @0x101ba4e30
    // returning an Optional<UInt64> — `.some` takes the cache-read path, `.none` the seek path.
    // The read path binary-searches `entryList` for the first entry whose position is strictly
    // greater than the target and clamps the read size to that gap. Both paths dispatch through
    // the `moreDownload` existential's witness table — slot +0x30 with (pos, 0) on the seek path
    // and slot +0x28 with (buffer, size) on the read path; slot +0x30 resolves through
    // DownloadProtocol requirement 5 to `AbstractAVIOContext.seek(offset:whence:)`. On success it
    // calls `CacheIOContext.addEntry(logicalPos:buffer:size:)` and DISCARDS a thrown error
    // (swift_errorRelease with no rethrow — a `try?`-shaped pattern), then advances the position
    // field and calls the private `updateSpeedSample(newPos:)`.
    //
    // Two KSLog sites, both at level 3, both gated on KSOptions.logLevel >= 3, at #line 166 and
    // 186, with #fileID "PreLoadIOContext/LimitSeparatePreLoadIOContext.swift" and the 34-char
    // message prefix "[CacheIOContext] more ffurl_seek2 ". Their #function argument is a
    // register-form small string that decode_string_literal has no path for and was NOT decoded.
    //
    // UNRESOLVED → P8 (IO-completion): the body is written to its RESULT CONTRACT only. The
    // interleaving of the buffer bookkeeping, the two witness dispatches and the entryList search
    // is read but not transcribed, because several of its callees are real trie negatives
    // (0x101babf50, 0x101bac23c, 0x101b94710) and transcribing by FUN-address is forbidden.
    // ⚑[tool=export_trie_oracle ref=more_insert_helper:0x101babf50 result=NOT_IN_TRIE]
    //
    // NOTE on the -1 guard: the binary calls a PRIVATE `canContinuePreload(at:)` @0x101ba5a5c.
    // Our source has no member of that name — it declares `canPreload(_:)` at :524, which is a
    // DIFFERENT symbol — so the call is NOT written here rather than being bent onto the wrong
    // member. Reconciling those two names is its own unit.
    public func more() -> Int32 {
        // UNRESOLVED → P8: the canContinuePreload guard, the seek / cache-read split and its
        // bookkeeping. Only the result contract above is read.
        0
    }
}

