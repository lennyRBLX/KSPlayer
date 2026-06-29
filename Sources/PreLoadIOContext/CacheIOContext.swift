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
//   inits   — designated s61 → inner FUN_101b86d38 (cached): sets ALL 28 fields to
//             their defaults, then takes download/cacheKey/bufferSize/saveFile/
//             isReadComplete as explicit param→field stores. The Foundation
//             cache-directory scan (enumerate videoCache dir → build entryList →
//             sum fetchedSize) is deep Foundation with unnamed helpers → its body
//             is UNRESOLVED→P8 (IO-completion) (the defaults + explicit param stores are faithful).
//           — convenience s60 @101b8668c (cached): builds `download` via the SHARED
//             URLContextDownload inner init FUN_101b90c58, delegates to designated,
//             then sets formatContextOptions + interrupt. The URLContext-open
//             inside FUN_101b90c58 is deep FFmpeg → left as the delegated call,
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
public class CacheIOContext: AbstractAVIOContext {
    // --- stored fields (binary __swift5_fieldmd order; Swift synthesizes the 70
    //     accessors — do NOT hand-write get/set/_modify) ---

    // 0  bytesRead: running total of bytes returned to the reader. read() advances
    //    it (self+0x18 / unaff_x20[3]). gate-confirmed.
    var bytesRead: UInt64 = 0
    // 1  download: the URLContextDownload that streams the source (designated init
    //    stores it at +0x20; read() drives download.read via vtable+0x28). Built by
    //    the convenience init via the shared URLContextDownload init FUN_101b90c58.
    var download: URLContextDownload? // type inferred — ⚑ (built via the shared URLContextDownload init)
    // 2  end: logical end offset of the cached stream. ⚑ gate-UNCHECKED; UInt64 by
    //    the position-field pattern (siblings gate-confirmed).
    var end: UInt64 = 0 // ⚑ (gate UNCHECKED; position-pattern)
    // 3  urlPos: current position within the backing download/url. gate-confirmed.
    var urlPos: UInt64 = 0
    // 4  lastSpeedSampleTime: CFAbsoluteTime of the last speed sample (self+0x58).
    //    s23 reads it as a Double timestamp. field-record.
    var lastSpeedSampleTime: Double = 0
    // 5  lastSpeedSamplePos: byte position at the last speed sample (self+0x60).
    //    ⚑ gate-UNCHECKED; UInt64 by the position-field pattern.
    var lastSpeedSamplePos: UInt64 = 0 // ⚑ (gate UNCHECKED; position-pattern)
    // 6  _downloadSpeed: most-recent measured download speed (self+0x68). field-record.
    var _downloadSpeed: Double = 0
    // 7  speedSampleInterval: min seconds between speed samples. Designated init sets
    //    self+0x70 to the const 0.5 — confirmed by s23's inlined 0.5 threshold.
    var speedSampleInterval: Double = 0.5
    // 8  maxReasonableSpeed: speed ceiling above which a sample is discarded.
    //    Designated init sets self+0x78 to the const 209715200.0 (200 MiB/s) —
    //    confirmed by s23's inlined 209715200.0 threshold. field-record.
    var maxReasonableSpeed: Double = 209_715_200.0
    // 9  logicalPos: current logical read cursor. gate-confirmed.
    var logicalPos: UInt64 = 0
    // 10 entryList: the on-disk cache segments (self+0x88; designated init defaults
    //    it to [] then the dir-scan populates it). field-record.
    var entryList: [CacheFileEntry] = []
    // 11 tmpURL: temp staging URL for the cache write. ⚑ (Foundation; unmapped).
    var tmpURL: URL? // type inferred — ⚑ (Foundation; unmapped)
    // 12 isJudgeEOF: whether EOF is decided by the judge path. Designated init
    //    defaults it true. field-record.
    var isJudgeEOF: Bool = true
    // 13 saveFile: whether segments persist to disk. Designated init param-fed
    //    (explicit store from param_5). field-record.
    var saveFile: Bool = false
    // 14 isReadComplete: whether the download reached completion. Designated init
    //    param-fed (explicit store from param_6); s67 sets it true. field-record.
    var isReadComplete: Bool = false
    // 15 eof: whether the stream is at end. Designated init defaults it false.
    //    field-record.
    var eof: Bool = false
    // 16 _isClosed: whether close() has run. Designated init defaults it false; s64
    //    returns !_isClosed. field-record.
    var _isClosed: Bool = false
    // 17 downloadLock: serializes the download/cache mutation. Designated init allocs
    //    NSRecursiveLock(). ⚑ decompile-strong (designated init allocs NSRecursiveLock).
    var downloadLock: NSRecursiveLock? = NSRecursiveLock() // ⚑ decompile-strong
    // 18 urlRefreshHandler: callback to refresh an expired source URL. Designated
    //    init defaults it nil (2-word zero). ⚑ exact closure shape UNRESOLVED.
    var urlRefreshHandler: (() -> Void)? // ⚑ closure — exact shape UNRESOLVED
    // 19 formatContextOptions: FFmpeg format-context options. Designated init defaults
    //    it nil; convenience init sets it. field-record.
    var formatContextOptions: [String: Any]? // field-record
    // 20 interrupt: the AVIOInterruptCB the reader polls to cancel (the L3 cancel
    //    field). Designated init defaults it; convenience init sets it (2 words).
    //    field-record (FFmpeg C — import FFmpegKit).
    var interrupt: AVIOInterruptCB? // field-record (FFmpeg C)
    // 21 onCacheUpdated: callback fired when the cache grows. Designated init defaults
    //    it nil (2-word zero). ⚑ exact closure shape UNRESOLVED.
    var onCacheUpdated: (() -> Void)? // ⚑ closure — exact shape UNRESOLVED
    // 22 stopOnLimitReached: stop the download when a byte limit is hit. Designated
    //    init defaults it false; read() consults it before bumping fetchedSize.
    //    field-record.
    var stopOnLimitReached: Bool = false
    // 23 fetchedSize: bytes fetched into the cache (SIGNED — gate-confirmed Int64,
    //    NOT UInt64). read() advances it (self+fetchedSize) with a SIGNED SCARRY8.
    var fetchedSize: Int64 = 0 // gate-confirmed (SIGNED)
    // 24 firstSeekTime: timestamp of the first seek. Designated init defaults it 0.
    //    field-record.
    var firstSeekTime: Double = 0
    // 25 seekOffsets: recorded seek offsets. Designated init defaults it [] (empty
    //    array storage @ +0x80/0x88-region). ⚑ element type inferred.
    var seekOffsets: [UInt64]? = [] // ⚑ array of offsets; element type inferred
    // 26 isInterleaved: whether the stream is interleaved. Designated init defaults
    //    it nil (optional-Bool tag byte 2 = .none). field-record (optional).
    var isInterleaved: Bool? // field-record (optional)
    // 27 isFirstFileSize: whether this is the first file-size probe. Designated init
    //    defaults it true. field-record.
    var isFirstFileSize: Bool = true

    // --- inits ---

    // Designated init s61 → inner FUN_101b86d38 (cached). Arity inferred (no mangled
    // init symbol): the EXPLICIT param→field stores in the inner init are
    //   param_1 → download (retained into +0x20),
    //   param_2/param_3 → a Swift String cacheKey (the appendingPathComponent base),
    //   param_4 → bufferSize (stored into base +0x14 → super.init(bufferSize:)),
    //   param_5 → saveFile (char store), param_6 → isReadComplete (char store).
    // The String param's role/name is not deterministically resolvable beyond "Swift
    // String used to derive the per-source cache subdirectory" → named cacheKey,
    // best-effort. All 28 field defaults are transcribed above as property
    // initializers (so a stored-property-only init body is faithful to the defaults).
    public init(download: URLContextDownload?, cacheKey: String, bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool) {
        self.download = download
        self.saveFile = saveFile          // binary: explicit (char)param_5 store
        self.isReadComplete = isReadComplete // binary: explicit param_6 store
        super.init(bufferSize: bufferSize) // binary: *(self+0x14) = param_4
        _ = cacheKey
        // UNRESOLVED → P8 (IO-completion): the Foundation cache-directory scan in FUN_101b86d38 —
        //   NSTemporaryDirectory()/appendingPathComponent("videoCache")/<cacheKey>,
        //   fileExists + createDirectory, contentsOfDirectory enumeration building
        //   the entryList CacheFileEntry segments (via unnamed helpers FUN_101b87a48
        //   / FUN_101b88374 / FUN_101b91580) and summing fetchedSize. Deep Foundation
        //   with stripped helpers → not reconstructed; the field defaults + explicit
        //   param stores above are the faithful spine. — P2
    }

    // Convenience init s60 @101b8668c (cached). Faithful spine: build `download`
    // (the SHARED URLContextDownload inner init FUN_101b90c58, also reused by
    // ReadCacheIOContext), delegate to the designated init (vtable+0x380), then set
    // formatContextOptions (= local_b0/param_3) and interrupt (2 words =
    // local_c0/local_b8). The URLContext-open inside FUN_101b90c58 is deep FFmpeg →
    // left as the delegated `download`-build call, NOT reconstructed. Arity/param
    // roles beyond formatContextOptions + interrupt are inferred.
    //
    // UNRESOLVED → P8 (IO-completion): the real convenience init's full signature (the URL + options
    //   that FUN_101b90c58 opens an FFmpeg URLContext from) is deep FFmpeg whose
    //   stripped calls only the P2 oracle names. The determinable post-delegation
    //   field stores (formatContextOptions, interrupt) are shown here as the faithful
    //   spine; the download-build is the delegated call, not fabricated.
    public convenience init(cacheKey: String, formatContextOptions: [String: Any]?, interrupt: AVIOInterruptCB?, bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool) {
        // UNRESOLVED → P8 (IO-completion): download = URLContextDownload(<FFmpeg URLContext open via
        //   FUN_101b90c58>) — the shared inner init opens the libavformat URLContext;
        //   deep FFmpeg, not reconstructed. Delegated as nil here (compilable spine).
        self.init(download: nil, cacheKey: cacheKey, bufferSize: bufferSize, saveFile: saveFile, isReadComplete: isReadComplete)
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
    public override func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        super.read(buffer: buffer, size: size)
    }

    // s22 @101b86038 — `func resetDownloadSpeed()` (name inferred, devirt). Faithful
    //   (full): zeroes the speed-sampler triple lastSpeedSampleTime / lastSpeedSamplePos
    //   / _downloadSpeed (self+0x58/0x60/0x68).
    func resetDownloadSpeed() { // name inferred (devirt)
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

    // s64 @101b8a0e0 — `var isOpen: Bool` (name inferred, devirt). Faithful (full):
    //   returns the logical negation of _isClosed (`(_isClosed ^ 0xff) & 1`).
    var isOpen: Bool { // name inferred (devirt)
        !_isClosed
    }

    // s67 @101b8a768 — `func markReadComplete()` (name inferred, devirt). Faithful
    //   (full): sets isReadComplete = true.
    func markReadComplete() { // name inferred (devirt)
        isReadComplete = true
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
