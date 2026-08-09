import Foundation
import KSPlayer    // AbstractAVIOContext (1C.4)
import FFmpegKit   // AVIOInterruptCB (FFmpeg C struct — the L3 cancel field)

// CacheIOContext — the 28-field core download/read/cache context of the SEPARATE
// PreLoadIOContext module: an AbstractAVIOContext that streams through an FFmpeg
// download (URLContextDownload) while persisting segments to an on-disk cache
// (a list of CacheFileEntry) under a temp staging URL.
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields  — the 28 stored properties are orchestrator-RESOLVED (reflection
//             double-run + field-record + l2_field_gate + the cached designated
//             init); NAMES + ORDER + COUNT + TYPES transcribed verbatim. The ⚑
//             ones are best-effort (unmapped stdlib int / Foundation / in-module
//             class / closure / FFmpeg-C) and flagged `// type inferred — ⚑`.
//   inits   — designated s61 → inner FUN_101b86d38 (cached): sets ALL 28 fields to  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
//             their defaults, then takes download/md5/bufferSize/saveFile/
//             isReadComplete as explicit param→field stores. The Foundation
//             cache-directory scan (enumerate videoCache dir → build entryList →
//             sum fetchedSize) is deep Foundation with unnamed helpers → its body
//             is UNRESOLVED→P8 (IO-completion) (the defaults + explicit param stores are faithful).
//           — convenience s60 @101b8668c (cached): builds `download` via the SHARED
//             URLContextDownload inner init FUN_101b90c58, delegates to designated,  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
//             then sets formatContextOptions + interrupt. The URLContext-open
//             inside FUN_101b90c58 is deep FFmpeg → left as the delegated call,  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
//             NOT reconstructed.
//   methods — read (slot 66) is the L3-critical override; its body is driven
//             through `download.read` + the AVIOInterruptCB callback and is NOT
//             cleanly separable from the FFmpeg-download branch → faithful spine +
//             UNRESOLVED→P8 (IO-completion) (see the method note). The small methods 22/23/64/67
//             are reconstructed faithfully; 63 is a devirtualized forwarder
//             (jumptable unrecovered) → spine + UNRESOLVED. The deep IO engine
//             (slots 80/82/83/84 — URL open/download/speed-sampling, 162–380 instr,
//             stripped-FFmpeg saturated) is UNRESOLVED→P8 (IO-completion), NOT reconstructed.
//
// AVIOInterruptCB is FFmpeg's C cancellation struct (callback + opaque) — declared
//   in FFmpegKit's headers, so it resolves via `import FFmpegKit`. CacheFileEntry +
//   URLContextDownload are in-module (already committed; no import). PreLoadIOContext
//   builds green via `swift build --target PreLoadIOContext`.
public class CacheIOContext: AbstractAVIOContext, PlayList {
    // --- stored fields (binary __swift5_fieldmd order; Swift synthesizes the 70
    //     accessors — do NOT hand-write get/set/_modify) ---

    // 0  bytesRead: running total of bytes returned to the reader. read() advances
    //    it (self+0x18 / unaff_x20[3]). gate-confirmed.
    public var bytesRead: UInt64 = 0
    // 1  download: the AVIO that streams the source, held as its Forward-added `any DownloadProtocol`
    //    existential (a 40-byte NON-class existential @+0x20, NOT a concrete URLContextDownload — the
    //    designated init value-witness-copies it into +0x20, and urlContext recovers the concrete AVIO
    //    via `as? AbstractAVIOContext`). Built by the convenience init via the shared URLContextDownload
    //    init (URLContextDownload conforms to DownloadProtocol through AbstractAVIOContext).
    // ⚑[tool=name_type_at_addr ref=DownloadProtocol:0x1039edd38 result=(any DownloadProtocol)? — 40B non-class existential; confirmed 4x: typeref-demangle 0x103571a68, 40B value-witness copy, fr_category=complex, downstream offset lastSpeedSampleTime@+0x58]
    var download: (any DownloadProtocol)?
    // 2  end: logical end offset of the cached stream. ⚑ gate-UNCHECKED; UInt64 by
    //    the position-field pattern (siblings gate-confirmed).
    var end: UInt64 = 0 // ⚑ (gate UNCHECKED; position-pattern)
    // 3  urlPos: current position within the backing download/url. gate-confirmed.
    //    Forward gives it a `didSet` — the vtable setter (slot 10 @0x101b85f50) is NOT the
    //    bare generated store its getter (slot 9) is: after `*(self+0x50) = newValue` it
    //    watermarks `end` (self+0x48) up to the new position and calls s23
    //    `updateDownloadSpeed` (@0x101b86044, the same body this file already reconstructs),
    //    both guarded by `newValue != .max`. The `.max` sentinel is the binary's
    //    `param_2 != 0xffffffffffffffff`; the `end` update is an unconditional store of
    //    `max(end, urlPos)` (the binary selects then stores on both arms), not a
    //    conditional assignment. Offsets are source-pinned, not decompiler-guessed:
    //    entryList is documented below at self+0x88 and logicalPos at self+0x80, which
    //    fixes end@+0x48 / urlPos@+0x50 / lastSpeedSampleTime@+0x58 exactly as the
    //    lastSpeedSample* comments already record.
    // ⚑[tool=vtable_walk ref=CacheIOContext.urlPos.setter:0x101b85f50 result=didSet recovered]
    var urlPos: UInt64 = 0 {
        didSet {
            if urlPos != .max {
                end = max(end, urlPos)
                updateDownloadSpeed(urlPos)
            }
        }
    }
    // 4  lastSpeedSampleTime: CFAbsoluteTime of the last speed sample (self+0x58).
    //    s23 reads it as a Double timestamp. field-record.
    private var lastSpeedSampleTime: Double = 0
    // 5  lastSpeedSamplePos: byte position at the last speed sample (self+0x60).
    //    ⚑ gate-UNCHECKED; UInt64 by the position-field pattern.
    private var lastSpeedSamplePos: UInt64 = 0 // ⚑ (gate UNCHECKED; position-pattern)
    // 6  _downloadSpeed: most-recent measured download speed (self+0x68). field-record.
    private var _downloadSpeed: Double = 0
    // 7  speedSampleInterval: min seconds between speed samples. Designated init sets
    //    self+0x70 to the const 0.5 — confirmed by s23's inlined 0.5 threshold.
    private let speedSampleInterval: Double = 0.5
    // 8  maxReasonableSpeed: speed ceiling above which a sample is discarded.
    //    Designated init sets self+0x78 to the const 209715200.0 (200 MiB/s) —
    //    confirmed by s23's inlined 209715200.0 threshold. field-record.
    private let maxReasonableSpeed: Double = 209_715_200.0
    // 9  logicalPos: current logical read cursor. gate-confirmed.
    public var logicalPos: UInt64 = 0
    // 10 entryList: the on-disk cache segments (self+0x88; designated init defaults
    //    it to [] then the dir-scan populates it). field-record.
    public var entryList: [CacheFileEntry] = []
    // 11 tmpURL: temp staging URL for the cache write. ⚑ (Foundation; unmapped).
    // ⚑[tool=binding_gate ref=CacheIOContext:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • tmpURL — assigned after super.init(); a `let` must be set before it
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    //   RESOLVED in session 62: `saveFile` is now `let` — the designated init assigns it from
    //   its `saveFile` PARAMETER (the convenience init delegates, so it obligates nothing),
    //   making the `= false` default unobservable. `tmpURL` still stands.
    // ⚑ s109: the type is now DERIVED, and it DIVERGES from what is written here. The field's
    //   own `vpWvd` demangles to `… CacheIOContext.tmpURL : Foundation.URL` with NO trailing `Sg`,
    //   so the binary field is NON-optional; `URL?` is the old inference this comment used to
    //   admit to. It is left as `URL?` only because correcting it does not stand alone:
    //   changing it to `URL` builds with exactly ONE error — "property 'self.tmpURL' not
    //   initialized at super.init call" at the designated init below — and the value that would
    //   satisfy it is written at 0x101b8745c by `blr x9` on a two-argument virtual call, inside
    //   the very Foundation cache-directory region that init records as UNRESOLVED. Making the
    //   field non-optional therefore requires reconstructing that construction first, which is
    //   the init's own unit. Do NOT spell it `URL!` — a field mangle without `Sg` is plain `T`,
    //   and IUO is not reflection-visible either way.
    //   ⚑[tool=export_trie_oracle ref=CacheIOContext.tmpURL:0x104c63908 result=vpWvd-URL-no-Sg]
    //
    // ⚑ s113 PARTIALLY READ THE CONSTRUCTION, which the note above called "the very Foundation
    //   cache-directory region that init records as UNRESOLVED". It is no longer unresolved, only
    //   unfinished, and three facts are banked so the next attempt starts from here:
    //     · `tmpURL` carries NO `vpfi` and NO setter — the trie holds exactly three symbols for it
    //       (getter, property descriptor, offset global), so it is `public let tmpURL: URL` with no
    //       declaration default, assigned in the designated init. There is no default-value escape
    //       from the "not initialized at super.init call" error; the init must be reconstructed.
    //     · the chain STARTS exactly as `cacheExists` and `copyPreloadCache` do:
    //       `bl _NSTemporaryDirectory` @0x101b86fa4, bridged to String, then
    //       `URL.init(fileURLWithPath:)` @0x101b86fd0 with the indirect return in x27.
    //     · the FIRST path component is the literal **"videoCaches"**, built in registers rather
    //       than loaded: x0/x1 at 0x101b86fdc-0x101b86ff4 carry the bytes
    //       `76 69 64 65 6f 43 61 63 | 68 65 73` under discriminator 0xEB, which is 0xE0|11 — an
    //       all-ASCII small string of count 11. `URL.appendingPathComponent` follows at
    //       0x101b87000, and a SECOND `appendingPathComponent` at 0x101b87038.
    //   ✅ THE x27 CONTRADICTION IS RESOLVED — an earlier draft of this note said x27 could not be
    //     both the URL and the integer that `ldr x27,[x20,#0x10]` @0x101b87158 makes it. It is
    //     both, at different times, and the spill is what reconciles them: x27 is saved to the
    //     frame slot `[x29-0x120]` by `stur x27` @0x101b8712c BEFORE being reused as an array
    //     count, and it is RELOADED by `ldur x27` @0x101b8778c and @0x101b878c4, each immediately
    //     before a `b 0x101b873ac`. So every path that reaches the store has the URL back in x27.
    //     It is a URL there and that is read, not assumed: 0x101b873c0 does `mov x20, x27` and
    //     calls `URL.path.getter` @0x1034523ec on it.
    //
    //   The assignment is GUARDED, and the guard is the whole tail:
    //     · `FileManager.default.fileExists(atPath: <candidate>.path)` @0x101b873e4;
    //     · `tbnz w20,#0` @0x101b873f4 — when it EXISTS, jump straight to the store;
    //     · otherwise fall through to `createDirectory(at:withIntermediateDirectories:)` with
    //       `w3 = 1` and `x4 = 0` @0x101b87434, then fall into the same store.
    //     i.e. `if !FileManager.default.fileExists(atPath: u.path) { try? …createDirectory(at: u,
    //     withIntermediateDirectories: true) }` followed unconditionally by `self.tmpURL = u`.
    //
    //   ✅ AND THE VALUE IS NOW READ IN FULL, so this field is neither optional nor divergent any
    //     more. There is NO loop in the selection — an earlier draft said the candidate came out of
    //     one, and that was wrong: the loop at 0x101b87158 is a LATER, separate
    //     `contentsOfDirectory` enumeration. The URL is built straight through, by two
    //     value-witness `assignWithTake` calls (VWT+0x28) into the same stack buffer x27:
    //       · `URL.init(fileURLWithPath:)` @0x101b86fd0 on `NSTemporaryDirectory()` -> x27
    //       · `appendingPathComponent("videoCaches")` @0x101b87000 -> x23, then
    //         assignWithTake(x27 <- x23) @0x101b8701c
    //       · `appendingPathComponent(<String>)` @0x101b87038 -> x23, then
    //         assignWithTake(x27 <- x23) @0x101b87058
    //     and that `<String>` is the `md5` PARAMETER, read from the prologue's own spill slots
    //     rather than guessed: the prologue stores x1 to [x29-0x130] @0x101b86d8c and x2 to
    //     [x29-0x120] @0x101b86d84, and 0x101b87028/0x101b87030 reload exactly those two slots as
    //     the String's two words. x1/x2 is `md5` in this init's register map.
    //   ⚠️ The literal is "videoCaches", ELEVEN characters — discriminator 0xEB = 0xE0|11, bytes
    //     `76 69 64 65 6f 43 61 63 | 68 65 73`. An older comment in this file said "videoCache"
    //     (ten); that was wrong and is corrected here.
    //
    // ⚑ `let`, not `var`, and that RESOLVES the session-61 binding refusal recorded above rather
    //   than working around it. The FieldRecord flags word is 0x00000000, which is `let`; s61 could
    //   not spell it only because the value was believed to arrive after `super.init()`. It does
    //   not — it is built from the parameters alone — so it is assigned BEFORE `super.init` and
    //   `let` compiles. The fileExists/createDirectory guard stays after it, where the binary has
    //   it; only the store moves, and it stores the same value either way.
    // ⚑[tool=decode_string_literal ref=CacheIOContext.init.tmpURL_component:0x101b86fdc result='videoCaches']
    public let tmpURL: URL
    // 12 isJudgeEOF: whether EOF is decided by the judge path. Designated init
    //    defaults it true. field-record.
    var isJudgeEOF: Bool = true
    // 13 saveFile: whether segments persist to disk. Designated init param-fed
    //    (explicit store from param_5). field-record.
    let saveFile: Bool
    // 14 isReadComplete: whether the download reached completion. Designated init
    //    param-fed (explicit store from param_6); s67 sets it true. field-record.
    var isReadComplete: Bool = false
    // 15 eof: whether the stream is at end. Designated init defaults it false.
    //    field-record.
    var eof: Bool = false
    // 16 _isClosed: whether close() has run. Designated init defaults it false; s64
    //    returns !_isClosed. field-record.
    //
    // ⚑ s113: OFFSET GLOBAL 0x104c63938 IS EITHER `eof` OR `_isClosed`, AND NOTHING ELSE. The
    //   handoffs carry this as a SEVEN-way tie — isJudgeEOF, saveFile, isReadComplete, eof,
    //   _isClosed, isInterleaved, isFirstFileSize — and it is two, by two deterministic axes:
    //     · MUTABILITY. `fileSize()` @0x101b8c178 STORES through the global and is a method, not an
    //       initialiser, so a `let` cannot be it. That drops `saveFile` (flags 0).
    //     · THE DEFAULT VALUE, which nothing had read. The designated init writes this global at
    //       0x101b86e7c and the instruction is **`strb wzr`** — the default is FALSE. That drops
    //       every candidate whose declaration default is true (`isJudgeEOF`, `isFirstFileSize`),
    //       and it drops `isInterleaved` too: that one is `Bool?`, whose `.none` is stored as the
    //       tag byte 2, so its default store would be `mov w9,#2` / `strb w9`, never `wzr`.
    //       `isReadComplete` is param-fed (no `vpfi` on this class at all), so a constant default
    //       store cannot be it either — which independently reproduces the `enableReadComplete()`
    //       elimination the handoff reached by a different route.
    // ⚑[tool=fieldrec ref=CacheIOContext.init.default:0x101b86e7c result=strb-wzr-default-false]
    //
    //   ✅ CLOSED, s114: **0x104c63938 is `eof`** — and by the very route recorded below as a
    //     negative. The negative was a SCAN DEFECT, not a fact about the binary.
    //
    //     The note said "all NINE accesses live in seven CacheIOContext methods, every one in THIS
    //     file". There are **22 sites in 19 functions**. A scan that only matches
    //     `ldr xN,[xM,#0x938]` misses the 13 sites that spell the same access as
    //     `adrp xM,0x104c63000` / `add xM,xM,#0x938` / `ldr xM,[xM]`, and every cross-file access
    //     happens to take that second form. The 19 functions span FOUR classes in FOUR files:
    //     CacheIOContext (this file), LimitPreLoadIOContext (`_54C5BFE7…`), PreLoadIOContext
    //     (`_9C48347E…`) and LimitSeparatePreLoadIOContext (`_D3E0B2D6…`).
    //
    //     THE DECIDING SITE IS A WRITE FROM ANOTHER FILE. At 0x101ba59b8-0x101ba59c8,
    //     `PreLoadIOContext.LimitSeparatePreLoadIOContext.more()` does
    //     `adrp/add #0x938` / `ldr x8,[x8]` / `mov w9,#0x1` / `strb w9,[x19,x8]`. `_isClosed` is
    //     private to file `_D69EFE1402863CA716A3171C7DB6DFB9` — its `vpfi` carries that
    //     discriminator, while `eof`'s is plain `…C3eofSbvpfi` with none — and `more()` is declared
    //     in file `_D3E0B2D62F772CE9EE6549031B37E873`. Swift cannot assign a file-private stored
    //     property from a different file, so this global CANNOT be `_isClosed`. Only `eof` remains.
    //     ⚑[tool=export_trie_oracle ref=CacheIOContext._isClosed:0x10002dab0 result=private-D69EFE14]
    //     ⚑[tool=function_extents ref=LimitSeparatePreLoadIOContext.more:0x101ba5398 result=cross-file-write]
    //
    //     ⚑ THE COMPLEMENT AGREES, which is what makes this more than an elimination: the sibling
    //       Bool global **0x1044f3848** has all 6 of its sites inside THIS file, is set `true` near
    //       the top of `close()` (0x101b8c8e8-0x101b8c8f0), and is the sole operand of the
    //       6-instruction leaf `shouldContinueRead()`, which returns `bic w0,w9,w8` = `!it`. That
    //       is the file-private closed flag, and it is a different global from this one.
    //
    //     This is a derivation from access-control scope, not a judgement about which name reads
    //     better against the `fileSize` write — that judgement is still forbidden here, and is the
    //     shape of the eight retractions session 112 had to make.
    private var _isClosed: Bool = false
    // 17 downloadLock: serializes the download/cache mutation. NON-optional — the designated init
    //    allocs NSRecursiveLock() unconditionally (allocWithZone + init, no nil-branch), and l2 reads
    //    the binary field as non-optional NSRecursiveLock (the prior `?` was an over-cautious flag,
    //    surfaced + corrected by the l2 gate on this touch).
    let downloadLock: NSRecursiveLock = NSRecursiveLock()
    // 18 urlRefreshHandler: callback to refresh an expired source URL. Designated
    //    init defaults it nil (2-word zero). ⚑ exact closure shape UNRESOLVED.
    public var urlRefreshHandler: (() -> Void)? // ⚑ closure — exact shape UNRESOLVED
    // 19 formatContextOptions: FFmpeg format-context options. Designated init defaults
    //    it nil; convenience init sets it. field-record.
    private var formatContextOptions: [String: Any]? // field-record
    // 20 interrupt: the AVIOInterruptCB the reader polls to cancel (the L3 cancel
    //    field). Designated init defaults it; convenience init sets it (2 words).
    //    field-record (FFmpeg C — import FFmpegKit).
    private var interrupt: AVIOInterruptCB? // field-record (FFmpeg C)
    // 21 onCacheUpdated: callback fired when the cache grows. Designated init defaults
    //    it nil (2-word zero). ⚑ exact closure shape UNRESOLVED.
    public var onCacheUpdated: (() -> Void)? // ⚑ closure — exact shape UNRESOLVED
    // 22 stopOnLimitReached: stop the download when a byte limit is hit. Designated
    //    init defaults it false; read() consults it before bumping fetchedSize.
    //    field-record.
    public var stopOnLimitReached: Bool = false
    // 23 fetchedSize: bytes fetched into the cache (SIGNED — gate-confirmed Int64,
    //    NOT UInt64). read() advances it (self+fetchedSize) with a SIGNED SCARRY8.
    // s112 — the `didSet` is READ, not added for effect. The setter @0x101b865c8 is 20 instructions:
    // `swift_beginAccess(&self.fetchedSize, …, flags=1)`, `str x19` of the new value, THEN
    // `bl 0x101b863f0`. Store first, observer second, so this is `didSet` and not `willSet`; a
    // `willSet` would also have used `newValue` rather than re-reading the stored property, which
    // 0x101b863f0 does under its own `beginAccess`.
    //
    // 0x101b863f0 has three call sites — this setter, the `modify` coroutine @0x101b8665c, and
    // `readComplete` @0x101b8a0f8, which assigns the property and gets the observer inlined. That
    // shared-ness is why it is a body of its own rather than an outlined single-caller chunk.
    //
    // The NAME is read from the LogHandler call at 0x101b86558, whose `#function` argument is a
    // SMALL string carried in registers rather than a pointer — x4 = `fetchedS` (0x5364656863746566)
    // and x5 = `ize` under discriminator 0xEB = 0xE0|11, i.e. **fetchedSize**, 11 characters — beside
    // its 37-character `#file` (`PreLoadIOContext/CacheIOContext.swift` @0x103d3eb40) and `w6` = 127.
    // `#function` inside an accessor is the PROPERTY's name, which is what identifies this body as
    // this property's observer. (`name_exhaustion_gate` reports "no #function candidate" here: its
    // recovery step looks for a pointer-form literal and does not read the register-built small
    // string. The route is open; the tool just cannot walk it.)
    // ⚑[tool=decode_string_literal ref=CacheIOContext.fetchedSize:0x103d3eb40 result=PreLoadIOContext-CacheIOContext-swift]
    //
    // The message is built from an empty String: append `"fetchedSize "` (12 chars, discriminator
    // 0xEC), then `Double.write(to:)` of the value, then append `"M"` (w0 = 0x4d, count 1). The
    // scale is TWO `fmul`s by the same constant 0x3f50000000000000 = 2^-10, not one by 2^-20, so the
    // source divides twice rather than by `1024 * 1024`. `scvtf` (signed) re-confirms Int64.
    // Level is case index 3 = `.warning`, KSLog's default, so it stays unspelled.
    // ⚑[tool=body_fingerprint ref=CacheIOContext.fetchedSize.didSet:0x101b863f0 result=warning-level-fetchedSize-MB]
    //
    // ⚠️ s112, for whoever takes `readComplete(buffer:size:isReadComplete:)` @0x101b8a0f8 (412
    // instructions, MEMBER_MISSING): declaring the observer above removed its ONLY unnamed callee,
    // so the CALL axis is now clear — every remaining callee is named or a low-range KSLog outline,
    // and its own `#function` literal @0x103d3eff0 confirms the full signature. It is still NOT
    // writable, and the reason is the FIELD axis that `rank_member_missing` cannot see:
    //   · of its three field-offset globals, two resolve because they are exported —
    //     0x104c63920 `stopOnLimitReached : Bool` and 0x104c63928 `fetchedSize : Int64` —
    //   · and 0x104c63938 does NOT. It is absent from the export trie, so the field is non-public,
    //     and it lives in `__DATA,__common`, which is ZERO-FILL: the offset value is not in the
    //     image at all, which is why `recover_field_offsets` answers NOT RECOVERED rather than
    //     guessing.
    //   · The vector route is closed too, and by the class's own shape rather than by a tool limit:
    //     `field_offset_vector --module PreLoadIOContext CacheIOContext` reports `metadata_init=1`,
    //     so the static image holds no field offsets for this class and reading it would return 0x0
    //     for every field while looking like a real map.
    //     (Pass `--module PreLoadIOContext`. Without it the tool looks up
    //     `$s8KSPlayer14CacheIOContextCN`, does not find it, and reports "no exported metadata
    //     symbol" — which reads as a finding about the class and is really a wrong-module lookup.)
    // Identifying 0x104c63938 needs anchor-site recovery across bodies and is its own unit. Two
    // more of this method's operands are also unread: the dispatch offsets 0x1e0 and 0x398.
    // ⚑[tool=recover_field_offsets ref=CacheIOContext:0x104c63938 result=NOT_RECOVERED]
    // ⚑[tool=field_offset_vector ref=CacheIOContext:0x104c63938 result=metadata_init-1-no-static-offsets]
    public var fetchedSize: Int64 = 0 { // gate-confirmed (SIGNED)
        didSet {
            KSLog("fetchedSize \(Double(fetchedSize) / 1024 / 1024)M")
        }
    }
    // 24 firstSeekTime: timestamp of the first seek. Designated init defaults it 0.
    //    field-record.
    private var firstSeekTime: Double = 0
    // 25 seekOffsets: recorded seek offsets. Designated init defaults it [] (empty
    //    array storage @ +0x80/0x88-region). ⚑ element type inferred.
    private var seekOffsets: [UInt64]? = [] // ⚑ array of offsets; element type inferred
    // 26 isInterleaved: whether the stream is interleaved. Designated init defaults
    //    it nil (optional-Bool tag byte 2 = .none). field-record (optional).
    private var isInterleaved: Bool? // field-record (optional)
    // 27 isFirstFileSize: whether this is the first file-size probe. Designated init
    //    defaults it true. field-record.
    private var isFirstFileSize: Bool = true

    // --- inits ---

    // Designated init s61 → inner FUN_101b86d38 (cached). Arity inferred (no mangled  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
    // init symbol): the EXPLICIT param→field stores in the inner init are
    //   param_1 → download (the `any DownloadProtocol` existential value-witness-copied into +0x20 —
    //     a 40-byte existential, not an 8-byte retained class ptr),
    //   param_2/param_3 → the Swift String `md5` (the appendingPathComponent base),
    //   param_4 → bufferSize (stored into base +0x14 → super.init(bufferSize:)),
    //   param_5 → saveFile (char store), param_6 → isReadComplete (char store).
    // The String param is `md5:` — RECOVERED, not inferred. It was previously "not
    // deterministically resolvable ... → named cacheKey, best-effort"; the orphaned export
    // trie carries the full mangled name with its argument labels. The class is word-
    // substituted (`05CacheC0C` re-uses words spelled by the module name), which is why no
    // literal search for it ever hit.
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext05CacheC0C8download3md510bufferSize8saveFile14isReadCompleteAC8KSPlayer16DownloadProtocol_p_SSs5Int32VS2btKcfc result=labels RECOVERED]
    // ⚑[tool=export_trie_oracle ref=CacheIOContext.init:throws result=the mangled name ends `tKcfc` — the K is `throws`, which this declaration does NOT carry; body+callers unchanged this batch, PINNED as its own unit]
    public init(download: (any DownloadProtocol)?, md5: String, bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool) {
        self.download = download
        self.saveFile = saveFile          // binary: explicit (char)param_5 store
        self.isReadComplete = isReadComplete // binary: explicit param_6 store
        // Read in full: NSTemporaryDirectory() -> URL(fileURLWithPath:) @0x101b86fd0, then two
        // appendingPathComponent calls, each landing back in the same buffer via a value-witness
        // assignWithTake. Assigned BEFORE super.init so the field can carry its binary `let`.
        tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("videoCaches")
            .appendingPathComponent(md5)
        super.init(bufferSize: bufferSize) // binary: *(self+0x14) = param_4
        // The guard the binary runs before it stores the field: fileExists @0x101b873e4, and on
        // the false edge createDirectory with withIntermediateDirectories = 1 @0x101b87434.
        if !FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.createDirectory(at: tmpURL, withIntermediateDirectories: true)
        }
        // UNRESOLVED → P8 (IO-completion): the Foundation cache-directory scan in FUN_101b86d38 —  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
        //   NSTemporaryDirectory()/appendingPathComponent("videoCache")/<md5>,
        //   fileExists + createDirectory, contentsOfDirectory enumeration building
        //   the entryList CacheFileEntry segments (via unnamed helpers FUN_101b87a48
        //   / FUN_101b88374 / FUN_101b91580) and summing fetchedSize. Deep Foundation
        //   with stripped helpers → not reconstructed; the field defaults + explicit
        //   param stores above are the faithful spine. — P2
    }

    // Convenience init s60 @101b8668c (cached). Faithful spine: build `download`
    // (the SHARED URLContextDownload inner init FUN_101b90c58, also reused by  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    // ReadCacheIOContext), delegate to the designated init (vtable+0x380), then set
    // formatContextOptions (= local_b0/param_3) and interrupt (2 words =
    // local_c0/local_b8). The URLContext-open inside FUN_101b90c58 is deep FFmpeg →  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    // left as the delegated `download`-build call, NOT reconstructed. Arity/param
    // roles beyond formatContextOptions + interrupt are inferred.
    //
    // UNRESOLVED → P8 (IO-completion): the real convenience init's full signature (the URL + options
    //   that FUN_101b90c58 opens an FFmpeg URLContext from) is deep FFmpeg whose  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    //   stripped calls only the P2 oracle names. The determinable post-delegation
    //   field stores (formatContextOptions, interrupt) are shown here as the faithful
    //   spine; the download-build is the delegated call, not fabricated.
    // ⚑[tool=export_trie_oracle ref=CacheIOContext.init(url:formatContextOptions:interrupt:saveFile:isReadComplete:) result=DIVERGENT — the trie carries this convenience at ARITY 5 with `url:` as the first label and NO `bufferSize:`; this declaration has 6 params led by `cacheKey:`. Signature + body are a unit of their own (dropping a parameter changes the delegation), so it is PINNED rather than half-applied here]
    public convenience init(cacheKey: String, formatContextOptions: [String: Any]?, interrupt: AVIOInterruptCB?, bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool) {
        // UNRESOLVED → P8 (IO-completion): download = URLContextDownload(<FFmpeg URLContext open via
        //   FUN_101b90c58>) — the shared inner init opens the libavformat URLContext;  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
        //   deep FFmpeg, not reconstructed. Delegated as nil here (compilable spine).
        self.init(download: nil, md5: cacheKey, bufferSize: bufferSize, saveFile: saveFile, isReadComplete: isReadComplete)
        self.formatContextOptions = formatContextOptions // binary: store at +formatContextOptions
        self.interrupt = interrupt                       // binary: 2-word store at +interrupt
    }

    // --- methods ---

    // read (L3-critical) — slot 66 @101b8a0f8 (the lone reconstructed
    // AbstractAVIOContext override). FAITHFUL SPINE + UNRESOLVED → P8 (IO-completion).
    //
    // The cached decompile drives the read entirely through `download.read`
    // (vtable+0x28 on the download value loaded from +0x20) and the AVIOInterruptCB
    // callback (vtable+0x1e0), across three branches:
    //   • a "not seekable" / availability guard (logs via DefaultStringInterpolation),
    //   • a single direct download.read that advances bytesRead and — when
    //     stopOnLimitReached — fetchedSize (SIGNED SCARRY8), then logs,
    //   • an interrupt-polled loop that repeatedly calls download.read, checks the
    //     interrupt callback and returns −1 on cancel, advancing bytesRead.
    // The cache-segment read (entryList CacheFileEntry.read) is NOT present in this
    // method, and the bytesRead/fetchedSize bookkeeping is interleaved with the
    // FFmpeg-download calls and the logging → the cache-read spine is NOT cleanly
    // separable from the FFmpeg branch. Per the brief's deferral rule the WHOLE
    // method is left as a faithful-spine marker rather than a guessed body.
    //
    // UNRESOLVED → P8 (IO-completion): read(buffer:size:) — the download-driven body (download.read +
    //   interrupt-poll + bytesRead/fetchedSize bookkeeping + speed-sample/log calls)
    //   calls stripped FFmpeg the P2 oracle names; not separable from the cache path
    //   → not reconstructed. Inherited AbstractAVIOContext.read is the compilable
    //   spine; the binary returns −1 on interrupt-cancel. — P2
    // ⚑ 0x10002c740 — `mov w0, #0x1` / `ret`. Unconditional true; the body reads no field and
    // takes no branch. The address is the image's canonical `return true` and is ICF-folded, so
    // what it establishes is exactly the constant — which is the whole of what this declares.
    // Signature from the trie: `PreLoadIOContext.CacheIOContext.canAccessNetwork() -> Swift.Bool`.
    // One of the seven members the PreLoadIOContext s30 pass recorded as undeclared here.
    public func canAccessNetwork() -> Bool {
        true
    }

    // ⚑ 0x10002d9d4 — `mov x0, #0` / `ret`. Unconditional nil: the body reads no field, takes no
    // branch, and never touches either parameter. That address is the image's canonical
    // `return nil` and is the most-folded in the whole binary (605 symbols share it), so it
    // carries nothing unique to this method beyond the constant — which is all this declares.
    // Trie: `PreLoadIOContext.CacheIOContext.reuseEntry(pos: Swift.UInt64, size: Swift.Int32)
    //        -> PreLoadIOContext.CacheFileEntry?`.
    // NOTE the subclass differs: LimitPreLoadIOContext.reuseEntry is a real 2255-instruction body
    // at 0x101b9f9a0, so this base implementation returning nil is the overridable default, not
    // the behaviour of the hierarchy.
    public func reuseEntry(pos _: UInt64, size _: Int32) -> CacheFileEntry? {
        nil
    }

    // ⚑ s109: `buffer` retyped to `UnsafeMutablePointer` with the base — see the correction on
    //   `AbstractAVIOContext.read`, where the trie's own entry for slot 4's impl settles it.
    public override func read(buffer: UnsafeMutablePointer<UInt8>?, size: Int32) -> Int32 {
        super.read(buffer: buffer, size: size)
    }

    // urlContext (base slot +0xa8) — io_open's terminal URLContext accessor. CacheIOContext holds its
    //   source as `any DownloadProtocol` (not a concrete AVIO), so it recovers the concrete
    //   AbstractAVIOContext by dynamic cast and recurses into ITS urlContext — the CHAIN-WALK down the
    //   AVIO cache stack; a non-AVIO or nil download yields nil. The binary's swift_dynamicCast (vs a
    //   free upcast) is exactly why download must be the existential, not URLContextDownload.
    // ⚑[tool=name_type_at_addr ref=FUN_101b8d8b8:0x101b8d8b8 result=(download as? AbstractAVIOContext)?.urlContext; cast src=any DownloadProtocol, target=AbstractAVIOContext (metadata 0x1044e69b0), recursion=vtable+0xa8]  ⚑[tool=resolve_fun_pins ref=FUN_101b8d8b8:0x101b8d8b8 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.nextAVOptions() -> Swift.UnsafeMutableRawPointer?
    public override func nextAVOptions() -> UnsafeMutableRawPointer? {
        (download as? AbstractAVIOContext)?.nextAVOptions() ?? nil
    }

    // s22 @101b86038 — ⚑ s105 RENAME: was `resetDownloadSpeed()`, self-declared "name
    //   inferred". The trie names 0x101b86038 `resetSpeedSample()` and carries exactly ONE
    //   symbol there, so it is not a fold. Body unchanged — only the name was invented.
    //   ⚑[tool=export_trie_oracle ref=CacheIOContext.resetSpeedSample:0x101b86038 result=name-recovered]
    //   Faithful
    //   (full): zeroes the speed-sampler triple lastSpeedSampleTime / lastSpeedSamplePos
    //   / _downloadSpeed (self+0x58/0x60/0x68).
    func resetSpeedSample() {
        lastSpeedSampleTime = 0
        lastSpeedSamplePos = 0
        _downloadSpeed = 0
    }

    // s23 @101b86044 — `func updateDownloadSpeed(_ pos: UInt64)` (name inferred,
    //   devirt). Faithful (full): on each call read CFAbsoluteTimeGetCurrent(); if a
    //   prior sample exists (lastSpeedSampleTime != 0) and at least speedSampleInterval
    //   (inlined 0.5 s) has elapsed and pos has not gone backwards, compute speed =
    //   Δpos / Δtime and accept it as _downloadSpeed only if ≤ maxReasonableSpeed
    //   (inlined 209715200.0). Always record the new sample (time, pos).
    //   NOTE: the binary inlines the 0.5 / 209715200.0 thresholds rather than reading
    //   speedSampleInterval / maxReasonableSpeed — preserved as literals for fidelity.
    func updateDownloadSpeed(_ pos: UInt64) { // name inferred (devirt)
        let now = CFAbsoluteTimeGetCurrent()
        if lastSpeedSampleTime != 0 {
            let elapsed = now - lastSpeedSampleTime
            if elapsed < 0.5 { // binary: inlined speedSampleInterval default
                return
            }
            if lastSpeedSamplePos <= pos {
                let speed = Double(pos - lastSpeedSamplePos) / elapsed
                if speed <= 209_715_200.0 { // binary: inlined maxReasonableSpeed default
                    _downloadSpeed = speed
                }
            }
        }
        lastSpeedSampleTime = now
        lastSpeedSamplePos = pos
    }

    // UNRESOLVED → P8 (IO-completion): s63 @101b885ac — a devirtualized forwarder: its only body is
    //   an indirect call through vtable+0x388 ("Could not recover jumptable … too many
    //   branches"). The target slot is devirt and the branch table is unrecovered →
    //   no readable body to reconstruct (name + body both unresolved). — P2
    // ⚠️ s97 — the NAME half is REFUTED. The address exports exactly one symbol, unfolded:
    //   $s16PreLoadIOContext05CacheC0C18canReadFromNetworkSbyF
    //   = PreLoadIOContext.CacheIOContext.canReadFromNetwork() -> Swift.Bool
    // The BODY half stands, but is now narrower than "unrecovered jumptable": the three
    // instructions are `ldr x8,[x20]` / `ldr x0,[x8,#0x388]` / `br x0`, i.e. a single indirect
    // dispatch through metadata word 0x388/8 = 113 = this class's own idx62 slot113 (@0x10002c740,
    // a 2-instruction `mov w0,#1; ret`). It is one devirtualised forward, not a branch table.
    // ⚑[tool=export_trie_oracle ref=PreLoadIOContext.CacheIOContext.canReadFromNetwork:0x101b885ac result=name-recovered]
    // ⚑ s106 DECLARED. The open question above was "what source spelling produces a forward to
    //   another overridable member" — the answer is just a call to it, once the target is named.
    //   Metadata word 0x388 against this class's VTableOffset of 51 words (0x198) gives
    //   slot (0x388-0x198)/8 = 62, which `vtable_walk` reports as kind **Method** with impl
    //   0x10002c740.
    //   That impl is a 270-symbol ICF fold — `mov w0,#1` / `ret` is maximally foldable — so
    //   address→name is a coin flip and `export_trie_oracle --addr` correctly refuses it. It
    //   resolves the other way: among CacheIOContext's OWN symbols at that address there is
    //   exactly one METHOD, `canAccessNetwork() -> Swift.Bool`; the others are `vpfi`s, which the
    //   vtable's Method kind excludes. That member is already declared above at line 245, and its
    //   body is the same `return true` those two instructions encode.
    //   ⚑[tool=vtable_walk ref=CacheIOContext:slot62@0x10002c740 result=Method-canAccessNetwork]
    func canReadFromNetwork() -> Bool {
        canAccessNetwork()
    }

    // s64 @101b8a0e0 — ⚑ s105 RENAME+KIND: was `var isOpen: Bool`, self-declared "name
    //   inferred". The trie names 0x101b8a0e0 `shouldContinueRead() -> Swift.Bool` — a FUNC,
    //   not a computed var. The address is ICF-folded across the hierarchy (CacheIOContext,
    //   LimitPreLoadIOContext and PreLoadIOContext all export it), which is consistent: all
    //   three compile to the same one-field negation. Body unchanged.
    //   ⚑[tool=export_trie_oracle ref=CacheIOContext.shouldContinueRead:0x101b8a0e0 result=name-recovered]
    //   Faithful (full):
    //   returns the logical negation of _isClosed (`(_isClosed ^ 0xff) & 1`).
    func shouldContinueRead() -> Bool {
        !_isClosed
    }

    // s67 @101b8a768 — `func markReadComplete()` (name inferred, devirt). Faithful
    //   (full): sets isReadComplete = true.
    // ⚑ s105 RENAME: was `markReadComplete()`, self-declared "name inferred". One symbol at
    // 0x101b8a768: `enableReadComplete() -> ()`. Body unchanged.
    // ⚑[tool=export_trie_oracle ref=CacheIOContext.enableReadComplete:0x101b8a768 result=name-recovered]
    func enableReadComplete() {
        isReadComplete = true
    }

    // MARK: - KSPlayer.PreLoadProtocol members inherited by both conformers
    //
    // PreLoadProtocol requirements 1, 2, 3 and 7 are satisfied for BOTH
    // LimitSeparatePreLoadIOContext and PreLoadIOContext by members declared HERE, on their shared
    // superclass — not by the conformers and not by protocol extensions. The evidence is that reqs
    // 1/2/3 resolve to ONE ICF-folded witness body in both conformance tables, and that body reads
    // only this class's stored fields.

    // Requirement 2. The witness body @0x101b914d0 is `ldr x8,[x20]` / `ldr d0,[x8,#0x68]` / `ret`,
    // and this class's own exported downloadSpeed getter @0x100d362bc is the same load at the same
    // offset — 0x68 is `_downloadSpeed`. A plain read of the private stored value.
    public var downloadSpeed: Double {
        _downloadSpeed
    }

    // Requirement 1. Declared here rather than on either conformer because its single ICF-folded
    // witness @0x101ba66bc (23 instr) touches ONLY superclass state: it takes a read access on
    // self+0x50 and returns it unless it is the UInt64.max sentinel, in which case it takes a
    // second read access on self+0x80 and returns that. Both offsets are anchored by this class's
    // own exported getters — urlPos @0x100a4e368 reads +0x50, logicalPos @0x101b86138 reads +0x80.
    public var position: UInt64 {
        urlPos == .max ? logicalPos : urlPos
    }

    // Requirement 7, the base implementation. LimitSeparatePreLoadIOContext does NOT override it —
    // its req7 witness @0x101b914dc dispatches virtually through metadata +0x438, which is this
    // class's vtable slot 84 — while PreLoadIOContext overrides it with a timeIndex-based version.
    //
    // Body @0x101b8eed0, 210 instr. Guard ladder, in order: `fcmp d0,#0.0` / `b.le` rejects a
    // non-positive duration; then `eof` (offset global 0x104c63938) must be true; then `end`
    // (self+0x48) must be non-zero. EVERY failure returns the empty-array storage loaded from
    // __got 0x104112d00 — a literal `[]`, with no tail call anywhere (unlike the override, whose
    // failure path tail-calls THIS method). On the live path it takes a read access and walks
    // `entryList` (self+0x88), reading each element's `CacheFileEntry.position` through offset
    // global 0x104c63948.
    //
    // UNRESOLVED → P8 (IO-completion): the per-entry accumulation between the guard and the return
    // is carried by two unnamed helpers, 0x101b91580 and 0x101b94c7c, both real trie negatives, so
    // how consecutive entries are turned into ranges is NOT read and is not written here. The guard
    // ladder and the empty-result contract above ARE read, and are what this body promises.
    // ⚑[tool=export_trie_oracle ref=cachedTimeRanges_accumulator:0x101b91580 result=NOT_IN_TRIE]
    public func cachedTimeRanges(duration: Double) -> [CachedTimeRange] {
        guard duration > 0, eof, end != 0 else {
            return []
        }
        // UNRESOLVED → P8: the entryList walk that builds the ranges.
        return []
    }

    // MARK: - KSPlayer.PlayList conformance
    //
    // Names, types and ORDER are the witness table's, not chosen: conformance descriptor
    // 0x103571aa0, witness table 0x1041e19c0 (validated), whose four slots forward to getters
    // the export trie names outright —
    //   0x101b8f528  audioLanguageCodeMap.getter    : [Swift.Int32 : Swift.String]
    //   0x101b8f60c  subtitleLanguageCodeMap.getter : [Swift.Int32 : Swift.String]
    //   0x101b8f6f0  playlists.getter               : [KSPlayer.MovieStream]
    //   0x101b8f7d0  currentStream.getter           : KSPlayer.MovieStream?
    // None of the four appears among this class's 28 field records, so all four are COMPUTED.
    //
    // All four bodies are the SAME shape, read at 0x101b8f528-0x101b8f8b4: copy the `download`
    // existential out of self+0x20, `_swift_dynamicCast` it to `any PlayList` with flags
    // w4 = 6 (TakeOnSuccess|DestroyOnFailure, Unconditional CLEAR — i.e. `as?`, not `as!`),
    // and on success project the result and `blr` the PlayList witness at wt+8*(i+1). There is
    // no loop, no filter, no map and no second cast: each getter is one forward plus a default.
    // The failure arms differ per requirement and are read off the epilogues:
    //   req0/req1 build an empty dictionary literal, req2 returns the empty-array storage,
    //   req3 writes 40 zero bytes into the sret buffer (`str xzr` + `stp q0,q0`) = nil.
    //
    // `download` is identified as the field at self+0x20 by TYPE, not by offset arithmetic: it
    // is this class's only stored field whose type is a bare protocol existential, and the
    // cast's SOURCE metadata resolves to `KSPlayer.DownloadProtocol` (descriptor 0x1039edd38),
    // which is that field's protocol. field_offset_vector refuses this class outright — its
    // metadata is runtime-initialized and it exports no `...CN` symbol — so the offset is NOT
    // taken from the field-record order.
    public var audioLanguageCodeMap: [Int32: String] {
        (download as? any PlayList)?.audioLanguageCodeMap ?? [:]
    }

    public var subtitleLanguageCodeMap: [Int32: String] {
        (download as? any PlayList)?.subtitleLanguageCodeMap ?? [:]
    }

    public var playlists: [any MovieStream] {
        (download as? any PlayList)?.playlists ?? []
    }

    public var currentStream: (any MovieStream)? {
        (download as? any PlayList)?.currentStream
    }

    // UNRESOLVED → P8 (IO-completion) (deep IO engine — NOT reconstructed; declare nothing beyond
    //   these markers; their symbols are devirt and their calls are stripped FFmpeg
    //   the P2 oracle names):
    //   • slot 80 @101b8ccac — URL/open
    //   • slot 82 @101b8d2c8 — URL/download
    //   • slot 83 @101b8d948 — deep IO
    //   • slot 84 @101b8eed0 — speed-sampling engine
    //   162–380 instr, FFmpeg/download saturated. — P2

    // UNRESOLVED → P8 (IO-completion): the remaining AbstractAVIOContext overrides (write/seek/close/
    //   fileSize) are not cleanly readable Foundation/Swift in the binary (devirt /
    //   FFmpeg-adjacent) → inherited from AbstractAVIOContext, NOT reconstructed. — P2

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.firstEntryEqual(logicalPos:):0x101b8cf34 result=112-instr]
    /// ⚠️ THE NAME MISLEADS, and the binary is unambiguous about it: this does NOT compare
    /// `entry.position` to `logicalPos`. Both fields are loaded — `position` (global 0x104c63948)
    /// into x22 and `size` (global 0x104c63950) as the 32-bit `ldr w28` — and the comparison is
    /// `adds x8, x22, x28` then `cmp x8, x19`, i.e. **`position + size == logicalPos`**. It finds
    /// the entry that ENDS exactly at `logicalPos`, which is the adjacency test a cache uses to
    /// append onto a segment, not an equality test on segment starts.
    ///
    /// Same inclusive binary search as its siblings (`hi = count - 1`, `mid = (lo + hi) / 2` with
    /// the round-toward-zero correction, `hi = mid - 1`), re-read rather than carried over. The
    /// three-way branch is read off consecutive condition codes on ONE compare:
    ///   · `b.eq`  → hit  @0x101b8d080: `mov w1, #0` then `mov x0, x21` — x21 is the MID INDEX.
    ///   · `b.hs`  → end > logicalPos (equality already consumed) → `sub x24, x21, #0x1`.
    ///   · fallthrough → end < logicalPos → `add x25, x21, #0x1`.
    ///   · miss @0x101b8d0ac: `mov x21, #0` / `mov w1, #1` — the `Int?` nil TAG, not a sentinel.
    ///
    /// ⚑ The `b.hs`/`b.lo` pair is UNSIGNED throughout, matching `UInt64`; a signed `b.gt` here
    ///   would mis-order any offset past 2^63.
    public func firstEntryEqual(logicalPos: UInt64) -> Int? {
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            let end = entry.position + UInt64(entry.size)
            if end == logicalPos {
                return mid
            } else if end > logicalPos {
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return nil
    }

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.firstEntryIndexContain(logicalPos:):0x101b8f36c result=111-instr]
    /// The index-returning twin of `firstEntryContain` below. The search is the SAME — inclusive
    /// `hi = count - 1`, `hi = mid - 1`, the identical half-open test against
    /// `CacheFileEntry.position` (global 0x104c63948) and `position + size` with `size` loaded as
    /// `ldr w27` (global 0x104c63950) — and it was re-read rather than assumed from the sibling.
    ///
    /// What differs is ONLY the returned value, and both arms are read from the `Int?` tagging:
    ///   · hit  @0x101b8f4b4 → `mov w1, #0`, falling into `mov x0, x21`. `x21` is the MID index,
    ///     not the entry pointer, which is what makes the return `Int?`.
    ///   · miss @0x101b8f4e0 → `mov x21, #0` / `mov w1, #1`; the `1` in the second register is
    ///     `Optional.none` for a payload that cannot spare a bit pattern.
    /// So the nil case is a TAG here, not a sentinel index — returning `-1` or `0` would be wrong.
    public func firstEntryIndexContain(logicalPos: UInt64) -> Int? {
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            if logicalPos < entry.position {
                hi = mid - 1
            } else if logicalPos < entry.position + UInt64(entry.size) {
                return mid
            } else {
                lo = mid + 1
            }
        }
        return nil
    }

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.firstEntryContain(logicalPos:):0x101b89d60 result=136-instr]
    /// The sibling of `firstEntryAfter` below, but NOT the same loop — the differences are read,
    /// not carried over:
    ///   · the bound is INCLUSIVE here. `subs x24, x0, #0x1` makes `hi = count - 1` and the
    ///     back-edge is `cmp x24, x27` / `b.ge`, i.e. `while lo <= hi`; the narrowing step is
    ///     `sub x24, x21, #0x1` (`hi = mid - 1`). `firstEntryAfter` instead keeps `hi = count`
    ///     with `hi = mid`.
    ///   · an empty list exits twice over: `cbz x0` on the count, then `tbnz x24, #0x3f` on the
    ///     negative `count - 1`.
    ///   · it RETURNS on a hit rather than narrowing further, so it is a plain containment search,
    ///     not a lower bound.
    ///
    /// The containment test uses BOTH entry fields, each named by its own `vpWvd`:
    ///   · global 0x104c63948 → `CacheFileEntry.position : UInt64`. `cmp x19, x23` / `b.lo` sends
    ///     `logicalPos < position` to the `hi = mid - 1` arm.
    ///   · global 0x104c63950 → `CacheFileEntry.size : UInt32`. It is loaded with `ldr w27` — a
    ///     32-BIT load, which is what fixes the `UInt64(...)` widening in the sum below — under
    ///     its own `swift_beginAccess`.
    ///   · `adds x8, x23, x27` forms `position + size` with a carry trap (`b.hs` → trap), and
    ///     `cmp x19, x8` / `b.lo` is the upper half of the half-open range.
    /// ⚑[tool=export_trie_oracle ref=CacheFileEntry.size:0x104c63950 result=vpWvd-named]
    ///
    /// ⚑ The range is HALF-OPEN: the lower test is `logicalPos < position` (so `>=` continues) and
    ///   the upper is `logicalPos < position + size`. An inclusive upper bound would need `b.ls`
    ///   here and the binary uses `b.lo`.
    public func firstEntryContain(logicalPos: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            if logicalPos < entry.position {
                hi = mid - 1
            } else if logicalPos < entry.position + UInt64(entry.size) {
                return entry
            } else {
                lo = mid + 1
            }
        }
        return nil
    }

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.firstEntryAfter(logicalPos:):0x101b89f80 result=88-instr]
    /// A LOWER-BOUND BINARY SEARCH, not a linear scan — read off the arithmetic, which is what
    /// distinguishes it: `adds x8, x27, x21` sums the bounds under an overflow trap (`b.vs` →
    /// `brk #0x1`), then `add x9, x8, x8, lsr #63` / `asr x23, x9, #1` is the round-toward-zero
    /// correction Swift emits for `Int` division — i.e. `(lo + hi) / 2`, not a shift.
    ///
    ///   · the searched array is `entryList`, accessed at the literal offset `+0x88` this file
    ///     already documents for it (line 95), under a `swift_beginAccess` read.
    ///   · `ldr x21, [x8, #0x10]` after masking the tag bits is the array COUNT, and `cmp x21, #1`
    ///     / `b.lt` is the empty-list exit that returns nil.
    ///   · the compared field is NAMED, not guessed: the element load is `ldr x8, [x26, #0x948]`
    ///     → global 0x104c63948, whose own `vpWvd` is
    ///     `PreLoadIOContext.CacheFileEntry.position : Swift.UInt64`.
    ///     ⚑[tool=export_trie_oracle ref=CacheFileEntry.position:0x104c63948 result=vpWvd-named]
    ///   · `cmp x19, x8` / `b.lo` is UNSIGNED, matching `logicalPos`'s `UInt64`. On the taken side
    ///     the candidate is retained into the result register and `hi = mid`; on the other
    ///     `lo = mid + 1`. That is lower-bound: it keeps narrowing after a hit rather than
    ///     returning immediately, so the answer is the FIRST entry past `logicalPos`.
    ///
    /// ⚑ The result register is seeded to 0 and returned unchanged when the loop never takes the
    ///   `b.lo` branch, which is the `nil` return — there is no separate not-found path.
    public func firstEntryAfter(logicalPos: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entryList.count
        var result: CacheFileEntry?
        while lo < hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            if logicalPos < entry.position {
                result = entry
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return result
    }

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.cacheExists(md5:in:):0x101b8e858 result=1-instr-thunk]
    /// ⚑ THE TRIE ADDRESS IS A THUNK, not an empty body — `0x101b8e858` is a single
    /// `b 0x101b95250`, and the real body is the 115 instructions there. Both this method and
    /// `preloadCacheExists` below resolve to that ONE address: they are ICF-folded, i.e. byte-identical,
    /// which is why they are written with identical bodies here. The difference between them is
    /// supplied entirely by the caller's `in:` argument.
    ///
    /// Every step of the 115-instruction body is read, and every callee named from the bind table
    /// or the selector table:
    ///   · `NSTemporaryDirectory()` → bridged with `String._unconditionallyBridgeFromObjectiveC`
    ///   · `URL(fileURLWithPath:)`  ⚑[tool=bind_oracle ref=0x103452308 result=Foundation.URL.init(fileURLWithPath:)]
    ///   · `.appendingPathComponent(_:)` TWICE, and the ORDER is read from the registers, not
    ///     assumed: at entry `md5` is (x0,x1) and `in` is (x2,x3); the first append is passed
    ///     x25/x20 (the `in` pair) and the second the pair reloaded from `[x29,#-0x70]` (`md5`).
    ///     So it is temp-dir → `in` → `md5`.
    ///   · `.path` then `_bridgeToObjectiveC`, and two ObjC sends decoded from their selrefs:
    ///     `defaultManager` and `fileExistsAtPath:isDirectory:`.
    ///     ⚑[tool=decode_objc_selector ref=0x10440b498 result='fileExistsAtPath:isDirectory:']
    ///
    /// ⚑ The return is `exists && isDirectory`, not `exists`. `sturb wzr,[x29,#-0x59]` zeroes the
    ///   out-parameter first, the send writes it, and `and w0, w20, w8` combines the call's result
    ///   with that byte. Dropping the conjunct would invert the answer for a plain file.
    public static func cacheExists(md5: String, in directory: String) -> Bool {
        var isDirectory: ObjCBool = false
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(directory)
            .appendingPathComponent(md5)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.preloadCacheExists(md5:in:):0x101b8e858 result=ICF-folded-with-cacheExists]
    /// Same address, same 115-instruction body as `cacheExists` above — ICF folds only
    /// byte-identical functions, so this is not an inference from similar names. See that comment
    /// for the full read; nothing here is derived from this symbol alone beyond its own signature.
    public static func preloadCacheExists(md5: String, in directory: String) -> Bool {
        var isDirectory: ObjCBool = false
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(directory)
            .appendingPathComponent(md5)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// @0x101b8e85c, 413 instructions. The trailing `Z` on the mangle makes it `static`, and the
    /// signature — labels and all three parameter types — is read, not inferred:
    /// ⚑[tool=export_trie_oracle ref=CacheIOContext.copyPreloadCache(md5:from:to:):0x101b8e85c result=static-3-String-returns-Bool]
    /// No parameter carries a trailing `Sg`, so all three are plain `String`, never optional.
    /// Like `cacheExists` above it has NO method-descriptor (`Tq`) symbol, so it occupies no
    /// vtable slot.
    ///
    /// ⚑ It touches NO instance state, which is what `static` predicts and what the binary
    ///   confirms independently: the body references no `0x1044f3xxx`/`0x104c63xxx` offset global
    ///   at all, and the `self` metatype in x20 is overwritten at 0x101b8e894 before any use.
    ///
    /// Statements, in body order:
    ///   · the three URLs are built exactly as `cacheExists` builds its one — `NSTemporaryDirectory()`
    ///     bridged to String and handed to `URL.init(fileURLWithPath:)`, then two
    ///     `appendingPathComponent` calls. `from` gives the source directory and `to` the
    ///     destination, both then joined with `md5`.
    ///   · the first guard is TWO conditions, and dropping either inverts the answer for a plain
    ///     file — the same trap `cacheExists` records: `cbz w20` on the send's result, then
    ///     `ldurb w8,[x29,#-0xe1]` / `cmp w8,#1` / `b.ne` on the `isDirectory` out-byte, which
    ///     `sturb wzr` zeroed beforehand. Both failures branch to the single `return false`.
    ///   · the early-success return is read from the branch target, not guessed: `cbnz w20`
    ///     at 0x101b8eaec jumps to 0x101b8ecb8, which destroys the three live URLs and does
    ///     `mov w0, #0x1`. It destroys THREE, not four, which is why the destination-directory URL
    ///     is built only after this point.
    ///   · `createDirectory` passes `w3 = 1` (withIntermediateDirectories) and `x4 = 0`
    ///     (attributes), with its `&NSError` slot pre-nulled.
    ///   · the copy is a real do/catch: `cbz w24` at 0x101b8eca0 splits `return true` from the
    ///     catch at 0x101b8ece8.
    /// ⚑[tool=decode_objc_selector ref=0x10440b498 result='fileExistsAtPath:isDirectory:']
    ///
    /// ⚑ `try?` vs `do { … } catch {}` is NOT decidable for the createDirectory call: both lower
    ///   to the identical convert / `swift_willThrow` / `swift_errorRelease` / fall-through shape
    ///   at 0x101b8ec20-0x101b8ec48, with no catch body. `try?` is the shorter of two spellings the
    ///   binary cannot separate. Same for `attributes:` — a defaulted argument and an explicit
    ///   `nil` both emit `x4 = 0`, so the argument is omitted here rather than invented.
    ///
    /// ⚑ The log line is fully read. The three literals are the `#file`, `#function` and message
    ///   prefix, and each length matches its count word exactly (0x25 = 37, 0x1e = 30, 0x2a = 42):
    ///   'PreLoadIOContext/CacheIOContext.swift', 'copyPreloadCache(md5:from:to:)' and
    ///   '[CacheIOContext] copyPreloadCache failed: '. The level argument is `mov w0, #0x3`, and 3
    ///   is the CASE INDEX — LogLevel's cases are panic/fatal/error/warning/…, so index 3 is
    ///   `.warning`, which is exactly `KSLog`'s default level, so no level is written at the call.
    ///   The gate `cmp w8,#3` / `b.hs` is that default folded against `KSOptions.logLevel`.
    ///   The `#file` literal names THIS file, which is what places the member here.
    /// ⚑[tool=decode_string_literal ref=CacheIOContext.copyPreloadCache:0x103d3eef0 result='[CacheIOContext] copyPreloadCache failed: ']
    /// ⚑ The line number the call passes is 752 — Forward's line, not this tree's, so it is
    ///   recorded and not reproduced.
    ///
    /// ⚑ ACCESS not independently proven — a method descriptor encodes kind, not access, and
    ///   `vtable_impl_oracle` proves access only on a `final` type or an actor. `public` matches
    ///   the two sibling statics directly above, which is the spelling this file already applies
    ///   to this exact situation.
    public static func copyPreloadCache(md5: String, from: String, to: String) -> Bool {
        var isDirectory: ObjCBool = false
        let tmpDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let sourceURL = tmpDirectory.appendingPathComponent(from).appendingPathComponent(md5)
        let destinationURL = tmpDirectory.appendingPathComponent(to).appendingPathComponent(md5)
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return true
        }
        let destinationDirectory = tmpDirectory.appendingPathComponent(to)
        if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return true
        } catch {
            KSLog("[CacheIOContext] copyPreloadCache failed: \(error)")
            return false
        }
    }

    // ⚑[tool=export_trie_oracle ref=CacheIOContext.clearOtherCache:0x101b8d948 result=LOCATED]
    // P43 existence check: this deferral is LOCATED, not a failed search. The member exists in the
    // trie at a known address, its body is read end to end below, and the single thing standing
    // between the read and a declaration is named exactly — `tmpURL`'s optionality, whose own
    // blocker is located at 0x101b8745c in the designated init. Nothing here is pending discovery.
    // ⚑ `clearOtherCache()` @0x101b8d948 — READ IN FULL, DECLARED NOWHERE, and blocked only on
    //   `tmpURL`'s type. Trie: `CacheIOContext.clearOtherCache() -> ()`, carrying its own `Tq`, and
    //   `override_table.py --impl 0x101b8d948` answers NO — so it is a NEW overridable member of
    //   this class, not an override. All 25 of its calls are Foundation/libc stubs; nothing is
    //   devirtualised. Written out here rather than declared, so the read is not lost:
    //
    //     let parent = tmpURL.deletingLastPathComponent()
    //     let keep = tmpURL.lastPathComponent
    //     guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path)
    //     else { return }
    //     for name in names where name != keep {
    //         try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
    //     }
    //
    //   Every step is resolved: __got 0x104109a88 `URL.deletingLastPathComponent`, 0x104109a38
    //   `URL.lastPathComponent.getter`, 0x104109ac8 `URL.path.getter`, 0x10410a238
    //   `String._bridgeToObjectiveC`, selref 0x10440ad40 `contentsOfDirectoryAtPath:error:`,
    //   $sSSN as the bridge element type (so `[String]`), 0x104109a70
    //   `URL.appendingPathComponent`, 0x104109a48 `URL._bridgeToObjectiveC` and selref
    //   0x10440ca38 `removeItemAtURL:error:`. The skip test is a pointer-equality fast path
    //   (`cmp x20,x25` / `ccmp x21,x23`) followed by `_stringCompareWithSmolCheck` with
    //   expecting=0 (.equal) and `tbnz w0,#0` continuing on a match — i.e. `name != keep`. Both
    //   error arms (0x101b8db88 for the listing, the loop tail for the removal) run
    //   convert/willThrow/errorRelease without rethrowing from a non-throwing signature, so both
    //   are `try?`; the listing one returns, the removal one continues the loop.
    //   The ONLY blocker is that the body reads `self.tmpURL` with no nil test, which the field's
    //   declared `URL?` cannot express — see the divergence note on that field. When `tmpURL`
    //   becomes non-optional this transcribes verbatim.
    // ⚑[tool=override_table ref=CacheIOContext.clearOtherCache:0x101b8d948 result=NO-not-an-override]
    // ⚑[tool=decode_objc_selector ref=0x10440ca38 result=removeItemAtURL:error:]
    // ⚑[tool=bind_oracle ref=__got:0x104109a88 result=Foundation.URL.deletingLastPathComponent]
    //
    // ⚑ s113: NOW DECLARED. The transcription above is unchanged — it was already read end to end
    //   and its ONLY blocker was `tmpURL`'s optionality, which is resolved at the field: the value
    //   is `NSTemporaryDirectory()/videoCaches/<md5>`, built from the parameters alone, so the
    //   field is the non-optional `let` the binary's FieldRecord always said it was and this body
    //   transcribes verbatim.
    // ⚑[tool=override_table ref=CacheIOContext.clearOtherCache:0x101b8d948 result=NO-not-an-override]
    // ⚑[tool=export_trie_oracle ref=CacheIOContext.clearOtherCache:0x101b8d948 result=LOCATED]
    func clearOtherCache() {
        let parent = tmpURL.deletingLastPathComponent()
        let keep = tmpURL.lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path)
        else { return }
        for name in names where name != keep {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
}
