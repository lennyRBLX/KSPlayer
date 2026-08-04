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
    public var tmpURL: URL? // type inferred — ⚑ (Foundation; unmapped)
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
    public var fetchedSize: Int64 = 0 // gate-confirmed (SIGNED)
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
        super.init(bufferSize: bufferSize) // binary: *(self+0x14) = param_4
        _ = md5
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

    public override func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
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
    // Still NOT declared here: what source spelling produces a forward to another overridable
    // member has not been established, and inventing one is worse than the pin.
    // ⚑[tool=export_trie_oracle ref=PreLoadIOContext.CacheIOContext.canReadFromNetwork:0x101b885ac result=name-recovered]

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
}
