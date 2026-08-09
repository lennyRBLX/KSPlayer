import Foundation
import KSPlayer    // AbstractAVIOContext (superclass)
import FFmpegKit   // AVIOInterruptCB chain — subContexts holds CacheIOContext (1C.7), which exposes it

// HLSCacheIOContext — an AbstractAVIOContext that caches an HLS (m3u8 + segment)
// stream: it owns the m3u8 manifest buffer, the parsed segment list, a lock-guarded
// map of per-segment child CacheIOContexts, a pool of child HLSCacheIOContexts, and
// a concurrent prefetch queue. Reconstructed A-structure-faithful from the Forward
// 1.3.17 binary:
//
//   fields  — the 14 stored properties are orchestrator-RESOLVED (the brief's table:
//             NAMES + ORDER + COUNT + TYPES + defaults transcribed verbatim, NOT
//             re-derived from the decompile). ⚠️ THE "m3u8Buffer name is inferred" NOTE THAT
//             STOOD HERE WAS STALE: the ObjC ivar list names 0x1044f4308 `m3u8Buffer` outright.
//             baseURL / hlsCacheDir / m3u8Buffer are all NON-OPTIONAL (empty field-record tails)
//             and HLSSegment was a fabricated placeholder, now deleted — `segments` is
//             [Foundation.URL]. l2_field_gate still UNCHECKs several of these, but that means its
//             route (a mangled property symbol) is closed, NOT that the type is unknowable.
//   init    — the designated init s18 @101b96cb0 delegates to the inner field-store
//             init FUN_101b96cb0 (cached); reconstructed from that inner: it stores all  ⚑[tool=resolve_fun_pins ref=FUN_101b96cb0:0x101b96cb0 result=RESOLVES_UNIQUELY] = PreLoadIOContext.HLSCacheIOContext.init(download: PreLoadIOContext.URLContextDownload, mediaId: Swift.String, baseURL: Foundation.URL, formatContextOptions: [Swift.String : Any]) throws -> PreLoadIOContext.HLSCacheIOContext
//             14 fields (defaults below; download/mediaId/baseURL/formatContextOptions
//             from params), then derives hlsCacheDir =
//             NSTemporaryDirectory()/"videoCache"/<mediaId>/"hls" and createDirectory's
//             it (Foundation spine reconstructed; the create-or-throw detail is faithful).
//             Init signature inferred (no init symbol): the param→field stores are
//             explicit in the inner → arity/order transcribed.
//   methods — only the 4 cached small methods are reconstructed (faithful spine +
//             `// UNRESOLVED` for the unnamed-FUN / element-shape parts). Names are
//             devirt→inferred (no mangled method symbol). The deep m3u8 fetch/parse +
//             child-prefetch engine and the devirt slot are UNRESOLVED→later phase,
//             marked NOT fabricated (see the tail markers).
//
// CacheIOContext / URLContextDownload are in-module (already committed; no import).
// AVIOInterruptCB resolves via `import FFmpegKit` (subContexts' CacheIOContext value
// exposes it). Builds via `swift build --target PreLoadIOContext`.

// 🚨 `HLSSegment` WAS DELETED FROM HERE, AND IT NEVER EXISTED IN THE BINARY.
//   It was declared `public struct HLSSegment {}` as an "UNRESOLVED placeholder" for the
//   element type of `segments`, and the whole block above it deduced its ACCESS LEVEL from
//   `segments`' property descriptor — a careful deduction about a type that is not there.
//   The reflection field record for `segments` (index 7) is `Say<SYM:2@0x1052f1200>G`, and
//   that same symref target is ALSO fields 2 (`baseURL`) and 4 (`hlsCacheDir`); it resolves
//   through __got 0x104109b20 to `_$s10Foundation3URLVMn`. The element type is
//   `Foundation.URL`. See the declaration of `segments` below.

public class HLSCacheIOContext: AbstractAVIOContext {
    // --- stored fields (brief table order + defaults; defaults are the inner init's
    //     flattened constants. Swift synthesizes accessors — do NOT hand-write get/set) ---

    // 0  download: the URLContextDownload that streams the manifest/segments. init-set
    //    (param; the inner retains it via _swift_retain).
    let download: URLContextDownload
    // 1  mediaId: the media identifier (also the hlsCacheDir leaf). init-set (param;
    //    String two-word, bridge-retained).
    public let mediaId: String
    // 2  baseURL: the manifest base URL for resolving relative segment URLs. init-set
    //    (param_4; copied via Foundation::URL value-witness).
    //    NON-OPTIONAL, READ THREE WAYS: field record 2 is `symref->__got 0x104109b20` =
    //    `_$s10Foundation3URLVMn` with an EMPTY tail (flags=0, so `let`); the same symref target
    //    is field 4 and the element of field 7; and the trie's own init signature says
    //    `baseURL: Foundation.URL`. This file already QUOTED that signature in its comments while
    //    declaring `URL?` — the source contradicted its own recorded evidence.
    public let baseURL: URL
    // 3  formatContextOptions: FFmpeg format-context options for child contexts. init-set
    //    (param_5).
    let formatContextOptions: [String: Any]
    // 4  hlsCacheDir: on-disk cache dir (tmpDir/videoCache/<mediaId>/hls). init-derived
    //    + createDirectory. NON-OPTIONAL: field record 4 is the SAME `symref->__got 0x104109b20`
    //    (`_$s10Foundation3URLVMn`) with an EMPTY tail, flags=0 (`let`). The init already derives
    //    it from a non-optional `URL(fileURLWithPath:)` chain, so nothing else changes.
    public let hlsCacheDir: URL
    // 5  m3u8Buffer: the downloaded m3u8 manifest bytes.
    //    TYPE AND DEFAULT ARE BOTH READ. Field record 5 is `symref->__got 0x104109c60` =
    //    `_$s10Foundation4DataVMn` with an EMPTY tail, so the field is `Data`, NOT `Data?`
    //    (the same reader prints `Sg` where it is present — CacheIOContext's
    //    `formatContextOptions` is `SDySSypGSg`). The declaration default is the vpfi at
    //    0x1001871f8, which is `mov x0,#0 / mov x1,#-0x4000000000000000 / ret`. A swiftc probe
    //    compiling `Data()` at -O emits that byte-for-byte —
    //    `mov x0,#0 / mov x1,#-4611686018427387904 (=0xc000000000000000) / ret` — so the
    //    expression is `Data()`. ⚠️ It is NOT "two zeroed words": word 1 is 0xc000000000000000,
    //    which is also why the tag-3 arm of parseM3U8's isEmpty switch is the empty case.
    //    ⚑[tool=vpfi_initializer_oracle ref=HLSCacheIOContext.m3u8Buffer:0x1001871f8 result=Data()]
    private var m3u8Buffer: Data = Data()
    // 6  m3u8Parsed: whether the manifest has been parsed into `segments`. init false.
    private var m3u8Parsed: Bool = false
    // 7  segments: the parsed HLS segment list. init [].
    //    ELEMENT TYPE READ, not inferred: field record 7 is `Say<SYM:2@0x1052f1200>G`, whose
    //    symref target is shared with fields 2 (`baseURL`) and 4 (`hlsCacheDir`) and resolves
    //    through __got 0x104109b20 = `_$s10Foundation3URLVMn`. There is no `Sg` tail, so the
    //    element is `URL` and not `URL?` — the same reader prints `Sg` where it is present
    //    (CacheIOContext's `formatContextOptions` is `SDySSypGSg`, `isInterleaved` is `SbSg`).
    public var segments: [URL] = []
    // 8  subContexts: per-segment-URL child cache contexts, guarded by subContextsLock.
    //    init [:].
    private var subContexts: [String: CacheIOContext] = [:]
    // 9  subContextsLock: serializes subContexts access. init NSLock().
    private let subContextsLock: NSLock = NSLock()
    // 10 childHLSContexts: nested HLS cache contexts (variant playlists). init [].
    private var childHLSContexts: [HLSCacheIOContext] = []
    // 11 prefetchCount: how many segments ahead to prefetch. init 3 (binary const).
    private let prefetchCount: Int = 3
    // 12 prefetchQueue: concurrent queue driving segment prefetch. init
    //    DispatchQueue(label: "hls.prefetch", attributes: .concurrent) (binary string +
    //    get_concurrent + get_unspecified QoS).
    private let prefetchQueue: DispatchQueue = DispatchQueue(label: "hls.prefetch", attributes: .concurrent)
    // 13 isClosed: whether close() has run. init false.
    private var isClosed: Bool = false

    // --- designated init (s18 @101b96cb0 → inner FUN_101b96cb0) ---  ⚑[tool=resolve_fun_pins ref=FUN_101b96cb0:0x101b96cb0 result=RESOLVES_UNIQUELY] = PreLoadIOContext.HLSCacheIOContext.init(download: PreLoadIOContext.URLContextDownload, mediaId: Swift.String, baseURL: Foundation.URL, formatContextOptions: [Swift.String : Any]) throws -> PreLoadIOContext.HLSCacheIOContext

    // Reconstructed from the inner field-store init: the param-fed fields (download,
    // mediaId, baseURL, formatContextOptions) are stored, every other field takes its
    // default above, then hlsCacheDir is derived as
    // NSTemporaryDirectory()/"videoCache"/<mediaId>/"hls" and created on disk (the inner
    // checks fileExistsAtPath: on the dir's path and, when absent, calls
    // createDirectoryAtURL:withIntermediateDirectories:attributes:error: — a throwing
    // create). Signature (param→field) transcribed from the inner's explicit stores; the
    // init symbol itself is absent so arity/labels are inferred. super.init(bufferSize:)
    // is the inherited AbstractAVIOContext spine.
    public init(download: URLContextDownload, mediaId: String, baseURL: URL, formatContextOptions: [String: Any]) throws {
        self.download = download
        self.mediaId = mediaId
        self.baseURL = baseURL
        self.formatContextOptions = formatContextOptions
        // hlsCacheDir = NSTemporaryDirectory()/"videoCache"/<mediaId>/"hls"
        //   (inner: _NSTemporaryDirectory → String → URL, then three appendPathComponent
        //    of "videoCache", mediaId, "hls").
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("videoCache")
            .appendingPathComponent(mediaId)
            .appendingPathComponent("hls")
        self.hlsCacheDir = dir
        super.init(bufferSize: 32 * 1024)
        // inner: if !FileManager.default.fileExists(atPath: dir.path) → create (throwing).
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // urlContext (base slot +0xa8) — io_open's terminal URLContext accessor. HLS forwards
    //   to its manifest/segment `download` (a CONCRETE URLContextDownload — a direct field
    //   load, no cast) and returns download.context. The decompile loads self.download
    //   (self+0x18), then does a checked-exclusivity read of download.context (its +0x18).
    // ⚑[tool=prefetch_decompiles ref=FUN_101b99cac:0x101b99cac result=lVar1=*(self+0x18)[download];beginAccess(lVar1+0x18);return*(lVar1+0x18) == download.context]  ⚑[tool=resolve_fun_pins ref=FUN_101b99cac:0x101b99cac result=RESOLVES_UNIQUELY] = PreLoadIOContext.HLSCacheIOContext.nextAVOptions() -> Swift.UnsafeMutableRawPointer?
    public override func nextAVOptions() -> UnsafeMutableRawPointer? { download.context.map { UnsafeMutableRawPointer($0) } }

    // addSub (base slot +0xb0) — the io_open sub-URL router; the SOLE concrete +0xb0 override (every
    //   other AbstractAVIOContext subclass inherits the base `nil`). io_open (the reconstructed ioOpen,
    //   MEPlayerItem.swift:538) dispatches each HLS sub-URL open through here: on a handled URL it returns
    //   the built/found child sub-context's AVIOContext* (ioOpen stores it into *pb and tracks it in a
    //   PBClass); on a decline it returns nil (ioOpen falls back to the saved default opener).
    //   Reconstructed FAITHFUL-PARTIAL: the ROUTING SPINE is faithful — the m3u8 / m3u / ".m3u8"-contains
    //   path-extension classification, the subContextsLock discipline, and the isEmpty + segment-index
    //   lookup guard. The child-context CONSTRUCTION is PINNED (`// UNRESOLVED → P8/streaming`): it builds a
    //   child URLContextDownload whose designated init is deferred to P8 (IO-completion) and materializes
    //   the returned AVIOContext through a shared avio_alloc_context-style helper (bufferSize@self+0x14 +
    //   read/write/seek trampolines) — neither is reconstructed, so the spine returns nil at the success
    //   points and the markers below characterize the real non-nil return. NOT fabricated. (The decompiler
    //   showed `return 0` on every path — an x0 value-residue across the materialization helper; the
    //   disassembly + the ioOpen caller arbitrate the true non-nil-AVIOContext contract, P28.)
    // ⚑[tool=disassemble ref=FUN_101b97b2c:0x101b97b2c result=ext=url.pathExtension.lowercased(); route (ext=="m3u8"||ext=="m3u"||url.absoluteString.contains(".m3u8"))→child-HLS else→segment-cache; success returns the sub-context AVIOContext* else nil (epilogue mov x0,#0)]  ⚑[tool=resolve_fun_pins ref=FUN_101b97b2c:0x101b97b2c result=RESOLVES_UNIQUELY] = PreLoadIOContext.HLSCacheIOContext.addSub(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB) -> Swift.UnsafeMutablePointer<__C.AVIOContext>?
    // ⚑[tool=get_function_by_address ref=FUN_101b90c58:0x101b90c58 result=URLContextDownload designated-init inner (s3) — deferred to P8/IO-completion per URLContextDownload.swift; the child download build in both branches]  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    // ⚑[tool=decompile ref=FUN_1019e258c:0x1019e258c result=AVIOContext materialization — avio_alloc_context-style (bufferSize@self+0x14, write-flag, read/write/seek callbacks, class 0x104c63590); shared KSPlayer outlined helper; the success-path return residue]  ⚑[tool=resolve_fun_pins ref=FUN_1019e258c:0x1019e258c result=RESOLVES_UNIQUELY] = KSPlayer.AbstractAVIOContext.getContext(writable: Swift.Bool) -> Swift.UnsafeMutablePointer<__C.AVIOContext>?
    public override func addSub(url: URL, flags: Int32, options: UnsafeMutablePointer<OpaquePointer?>?, interrupt: AVIOInterruptCB) -> UnsafeMutablePointer<AVIOContext>? {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" || url.absoluteString.contains(".m3u8") {
            // variant playlist (a child .m3u8): build a child URLContextDownload for `url`, wrap it in a
            //   child HLSCacheIOContext(download:, mediaId: mediaId, baseURL: url,
            //   formatContextOptions: formatContextOptions) [this file's designated init], append it to
            //   childHLSContexts, and return that child's AVIOContext*.
            // UNRESOLVED → owner phase (streaming/P8): the child URLContextDownload build and the
            //   AVIOContext materialization are the deferred residuals (see the class-level markers), so the
            //   child is not built here and the childHLSContexts.append + non-nil return are characterized
            //   only. The routing/classification spine above is faithful.
            // ⚑[tool=disassemble ref=FUN_101b96cb0:0x101b96cb0 result=HLSCacheIOContext designated init (this file) — the child (download:, mediaId:, baseURL:url, formatContextOptions:) construction, called after the P8 URLContextDownload build]  ⚑[tool=resolve_fun_pins ref=FUN_101b96cb0:0x101b96cb0 result=RESOLVES_UNIQUELY] = PreLoadIOContext.HLSCacheIOContext.init(download: PreLoadIOContext.URLContextDownload, mediaId: Swift.String, baseURL: Foundation.URL, formatContextOptions: [Swift.String : Any]) throws -> PreLoadIOContext.HLSCacheIOContext
            return nil
        }
        // media segment: consult the per-segment child cache under subContextsLock, creating it on a miss.
        subContextsLock.lock()
        if !subContexts.isEmpty, segmentIndex(for: url) != nil {
            // hit: the child CacheIOContext already cached at the resolved segment key is returned (its
            //   AVIOContext*). The isEmpty guard + lock discipline + segment-index lookup spine are
            //   faithful; the key→value read (subContexts storage) + AVIOContext materialization are pinned.
            // UNRESOLVED → owner phase (streaming): return subContexts[<resolved key>]'s AVIOContext*.
            // ⚑[tool=get_function_by_address ref=FUN_100020444:0x100020444 result=segment-index lookup helper (the segmentIndex(for:) spine, == subContext's s22 lookup)]
            subContextsLock.unlock()
            return nil
        }
        subContextsLock.unlock()
        // miss: derive the segment cache key from `url`, build a URLContextDownload, construct a child
        //   CacheIOContext(download:, cacheKey:, bufferSize: 0x40000, saveFile: true, isReadComplete:
        //   false) [CacheIOContext's designated init, in-module/done], insert it into subContexts under
        //   subContextsLock, register the segment, and return its AVIOContext*.
        // UNRESOLVED → owner phase (streaming/P8): the cache-key String derivation, the URLContextDownload
        //   build (P8), the keyed subContexts insert (the same insert helper setSubContext pins), and the
        //   trailing segment-match loop over `segments` (its element URL read is a plain [URL]
        //   element read now that the HLSSegment fabrication is gone, as in segmentIndex) are NOT reconstructed; the AVIOContext materialization +
        //   non-nil return are characterized only. The lock discipline + miss-path spine above are faithful.
        // ⚑[tool=get_function_by_address ref=FUN_101b86a2c:0x101b86a2c result=segment cache-key String builder (URLComponents queryItems/url, 651B)]  ⚑[tool=resolve_fun_pins ref=FUN_101b86a2c:0x101b86a2c result=RESOLVES_UNIQUELY] = (extension in PreLoadIOContext):Foundation.URL.sortQueryString.getter : Swift.String
        // ⚑[tool=get_function_by_address ref=FUN_1019f0d98:0x1019f0d98 result=String(UTF8View,count) re-encode in the cache-key derivation]  ⚑[tool=resolve_fun_pins ref=FUN_1019f0d98:0x1019f0d98 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Swift.String.md5() -> Swift.String
        // ⚑[tool=get_function_by_address ref=FUN_101b9b45c:0x101b9b45c result=subContexts keyed insert (same helper setSubContext pins, 335B)]
        // ⚑[tool=disassemble ref=FUN_101b86d38:0x101b86d38 result=CacheIOContext designated init (in-module/done, CacheIOContext.swift:147); addSub calls it with bufferSize=0x40000 saveFile=true isReadComplete=false]  ⚑[tool=resolve_fun_pins ref=FUN_101b86d38:0x101b86d38 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheIOContext.init(download: KSPlayer.DownloadProtocol, md5: Swift.String, bufferSize: Swift.Int32, saveFile: Swift.Bool, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.CacheIOContext
        return nil
    }

    // --- methods (only the 4 cached small methods; names devirt→inferred) ---

    // @0x101b99ce8 — 798 instr (0x101b99ce8-0x101b9a960), vtable slot 20, a NEW `Method` slot and
    //   NOT an override (none of the 7 override-table impls is this address). Trie-named
    //   `$s16PreLoadIOContext08HLSCacheC0C9parseM3U8yyF`, one symbol (no ICF fold).
    //
    // ⚠️ PLACEMENT IS A KNOWN DIVERGENCE AND IS NOT FAKED. The four KSLog sites carry
    //   `#line` 285, 318, 320 and 323 (`mov w6,#0x11d / #0x13e / #0x140 / #0x143`) in
    //   `PreLoadIOContext/HLSCacheIOContext.swift` (the 40-byte `#fileID` at 0x103d3f0f0), so in
    //   Forward this body sits far earlier in the file than it does here. Hitting those lines
    //   exactly would mean restructuring the whole file; the line evidence is recorded instead of
    //   silently discarded, and the body itself is unaffected.
    //
    // Verified against the binary rather than accepted from the derivation: the guard order
    //   (`tbnz w8,#0` on m3u8Parsed @0x101b99ea0 → epilogue, then the 4-way `Data._Representation`
    //   tag switch on m3u8Buffer, whose tag-3 arm — the one `Data()` produces — also returns), and
    //   `m3u8Parsed = true` landing AFTER both guards at 0x101b99f18. The two CharacterSet globals
    //   were bound individually: 0x1041094f0 is `.newlines` and 0x104109460 is **`.whitespaces`**,
    //   NOT `.whitespacesAndNewlines`.
    //
    // ⚠️ THE TAG INVENTORY IS EXACTLY FOUR LITERALS — `"#EXTINF:"`, `"#"`, `"http://"`,
    //   `"https://"`. There is no `#EXTM3U` and no `#EXT-X-…` anywhere in the body; a reader
    //   expecting them will look for code that does not exist. Each was re-derived by hand from
    //   its `mov`/`movk` immediates plus the 0xE0|n discriminator byte (`#EXTINF:` is
    //   `23 45 58 54 49 4e 46 3a` with disc 0xE8 = 8; `#` is disc 0xE1 = 1; `http://` 0xE7 = 7;
    //   `https://` 0xE8 = 8).
    //
    // Argument order at the `hasPrefix` sites is settled by a swiftc probe, not by reading:
    //   `b.hasPrefix(a)` compiles to a tail-branch with ZERO register moves, so x0/x1 is the
    //   prefix and x2/x3 is `self` — i.e. at every site here the LITERAL is the prefix and the
    //   trimmed line is the receiver.
    //
    // KSLog is the bare 3-argument form deliberately: `KSLog(level: LogLevel = .warning, …)`
    //   defaults to `.warning`, whose case index is 3, and the binary's inlined gate compares
    //   `KSOptions.logLevel` against 3 and passes `mov w0,#0x3` to the handler.
    //
    // ⟨No local identifier in this body is recoverable — the trie carries only `parseM3U8yyF` and
    //  the sole in-body identifier literal is the `#function` default "parseM3U8()". The local
    //  names below are CHOSEN, not derived.⟩
    // ⟨The `#EXTINF:` flag assignment is written as one unconditional tail assignment; an
    //  if/else-if chain assigning in both arms lowers identically, so the source form is not
    //  decidable from the machine code.⟩
    func parseM3U8() {
        guard !m3u8Parsed, !m3u8Buffer.isEmpty else {
            return
        }
        m3u8Parsed = true
        guard let content = String(data: m3u8Buffer, encoding: .utf8) else {
            KSLog("[HLSCache] parseM3U8 failed: cannot decode m3u8 content as UTF-8") // #line 285
            return
        }
        let lines = content.components(separatedBy: .newlines)
        var urls: [URL] = []
        var isSegmentLine = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isEXTINF = trimmed.hasPrefix("#EXTINF:")
            if !isEXTINF, isSegmentLine, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                let segmentURL: URL?
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    segmentURL = URL(string: trimmed)
                } else {
                    segmentURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
                }
                if let segmentURL {
                    urls.append(segmentURL)
                }
            }
            isSegmentLine = isEXTINF
        }
        segments = urls
        KSLog("[HLSCache] parseM3U8 completed: \(segments.count) segments found") // #line 318
        if let first = segments.first {
            KSLog("[HLSCache] first segment: \(first.absoluteString)") // #line 320
        }
        if let last = segments.last {
            KSLog("[HLSCache] last segment: \(last.absoluteString)") // #line 323
        }
    }

    // s22 @0x101b9a960 — 101 instr (0x101b9a960-0x101b9aaf4). THE NAME IS READ, NOT INFERRED:
    //   the trie carries `$s16PreLoadIOContext08HLSCacheC0C12segmentIndex3forSiSg10Foundation3URLV_tF`
    //   = `HLSCacheIOContext.segmentIndex(for: Foundation.URL) -> Swift.Int?`, so the old
    //   "name inferred (devirt)" tag was wrong — this identifier was never a guess.
    //
    // 🚨 THE RECORDED BLOCKER WAS THE FABRICATION ITSELF. The body used to be a loop with
    //   `_ = index` / `_ = target` no-ops, deferred to the "owner phase (streaming)" because
    //   "the per-element URL read goes through HLSSegment's value-witness layout, whose
    //   fields are the UNRESOLVED placeholder". HLSSegment never existed; the element is a
    //   `URL`, so there is nothing to defer and the loop is written out in full.
    //
    // The body independently CONFIRMS the element type, which is why it is corrected in the
    //   same unit as the field: at 0x101b9aa24 the element is copied into an alloca through
    //   the value witness `initializeWithCopy` ([x27,#0x10]) and at 0x101b9aa34 the copy is
    //   handed straight to `bl 0x1034522d8` = `URL.absoluteString.getter` with the copy as
    //   swiftself. A struct wrapping a URL could not be called that way.
    //
    // Read in full: `target` is computed once before the loop (same getter, on the parameter);
    //   `segments` is read under a read-mode `swift_beginAccess`; an empty array takes
    //   `cbz x28 -> 0x101b9aa90`, which sets tag 1 = nil. Each iteration bounds-checks
    //   (`cmp x23,x8` / `b.hs` -> `brk #0x1`), addresses the element by VWT stride
    //   (`madd x1, x9, x23, x8`), then compares the two Strings by raw words first
    //   (`cmp x0,x25` + `cmp x20,x19`, the equal-equal fast path at 0x101b9aa9c) and falls
    //   back to `bl 0x103459604` = `_stringCompareWithSmolCheck(…, w4=0)`. A hit returns
    //   `(x23, tag 0)`; running off the end returns `(0, tag 1)`.
    func segmentIndex(for url: URL) -> Int? {
        let target = url.absoluteString
        for index in segments.indices {
            if segments[index].absoluteString == target {
                return index
            }
        }
        return nil
    }

    // s23 @101b9aaf4 — `func subContext(for url: URL) -> CacheIOContext?` (name inferred,
    //   devirt). FAITHFUL (full, modulo the s22 lookup it calls). Under subContextsLock,
    //   if `subContexts` is empty → nil; else it runs the s22 segment lookup
    //   (FUN_100020444 == s22) and, on a hit, returns the child context at the resolved
    //   key (subContexts value at the found index, retained); on a miss → nil.
    func subContext(for url: URL) -> CacheIOContext? { // name inferred (devirt)
        subContextsLock.lock()
        defer { subContextsLock.unlock() }
        if subContexts.isEmpty {
            return nil
        }
        // binary: auVar3 = s22(url, segments); if found → return the subContexts value at
        //   the resolved key (retained), else nil. The found→value mapping below preserves
        //   that lookup spine.
        guard let index = segmentIndex(for: url), index < segments.count else {
            return nil
        }
        _ = index
        // UNRESOLVED → owner phase (streaming): the binary indexes subContexts' value
        //   buffer (*(subContexts + 0x38) + index*8) by the s22-resolved slot to return the
        //   child CacheIOContext. That index→key→value mapping depends on the segment/key
        //   layout → NOT reconstructed (the HLSSegment fabrication is gone; what remains
        //   unread here is the subContexts key mapping, not the element type); the lock + empty-guard +
        //   lookup spine are faithful.
        return nil
    }

    /// ⚑[tool=export_trie_oracle ref=HLSCacheIOContext.getSubContext(for:):0x101b9aaf4 result=50-instr]
    /// Trie signature: `getSubContext(for: Swift.String) -> PreLoadIOContext.CacheIOContext?` —
    /// the key is a **String**, matching `subContexts: [String: CacheIOContext]`.
    ///
    /// Read straight through:
    ///   · global 0x1044f4320 is the `subContextsLock` field; `bl 0x103464ae0` is selector
    ///     `lock` and the tail `bl 0x10346e620` is `unlock` (the same pair decoded for
    ///     Anime4KFrameDump.reset), so the whole body runs under that lock.
    ///   · global 0x1044f4318 is `subContexts`. `ldr x8,[x20,#0x10]` is the dictionary COUNT and
    ///     `cbz` returns nil for an empty dictionary before hashing at all.
    ///   · `bl 0x100020444` is the keyed lookup returning (index in x0, found-flag in w1);
    ///     `tbz w1,#0` takes the not-found arm to nil, otherwise `ldr x8,[x20,#0x38]` is the
    ///     values buffer and `ldr x21,[x8, x0, lsl #3]` loads the element, which is then retained.
    /// That is a plain `subContexts[key]` under the lock — no insert, no default.
    func getSubContext(for key: String) -> CacheIOContext? {
        subContextsLock.lock()
        defer { subContextsLock.unlock() }
        return subContexts[key]
    }

    // ⚠️ TWO CORRECTIONS to the note below, both from the export trie, which was not consulted
    //   when it was written:
    //   1. The name is NOT inferred — the trie carries
    //      `PreLoadIOContext.HLSCacheIOContext.setSubContext(_: PreLoadIOContext.CacheIOContext, for: Swift.String)`.
    //   2. Its second parameter is **`Swift.String`, not `URL`** — the signature below is a type
    //      divergence. It is left unchanged here because retyping it touches every call site and
    //      is its own unit; `getSubContext` above uses the correct `String` key, and the two must
    //      end up agreeing.
    //   ⚑[tool=export_trie_oracle ref=HLSCacheIOContext.setSubContext result=for:String-not-URL]
    // s24 @101b9abbc — `func setSubContext(_ context: CacheIOContext, for url: URL)`
    //   (name inferred, devirt). FAITHFUL SPINE + UNRESOLVED on the mutating helper. Under
    //   subContextsLock, with exclusive (mutating) access on `subContexts`, the binary
    //   performs the standard Swift dictionary mutate-in-place dance
    //   (_swift_isUniquelyReferenced_nonNull_native, swap the storage to empty, mutate,
    //   swap back) and calls the unnamed FUN_101b9b45c to do the actual insert keyed by the
    //   URL. The insert helper is an unnamed FUN_ with no readable body → only the
    //   lock/exclusive-access spine is reconstructed.
    func setSubContext(_ context: CacheIOContext, for url: URL) { // name inferred (devirt)
        subContextsLock.lock()
        defer { subContextsLock.unlock() }
        _ = context
        _ = url
        // UNRESOLVED → owner phase (streaming): under exclusive access on `subContexts`
        //   the binary calls FUN_101b9b45c(self, url, context, <uniqueness>) — the keyed
        //   dictionary insert (COW mutate-in-place). FUN_101b9b45c is an unnamed FUN with
        //   no readable signature/body → the mutation is NOT reconstructed; the lock +
        //   subContextsLock spine above is faithful.
    }

    // s25 @101b9ac94 — `func removeSubContext(for url: URL) -> CacheIOContext?` (name
    //   inferred, devirt). FAITHFUL SPINE + UNRESOLVED on the mutating helper. Under
    //   subContextsLock, with exclusive (mutating) access on `subContexts`, the binary
    //   delegates to the unnamed FUN_101b9b3a0 and returns its result — a keyed remove/
    //   take over subContexts. FUN_101b9b3a0 is an unnamed FUN_ with no readable body →
    //   only the lock/exclusive-access spine is reconstructed.
    func removeSubContext(for url: URL) -> CacheIOContext? { // name inferred (devirt)
        subContextsLock.lock()
        defer { subContextsLock.unlock() }
        _ = url
        // UNRESOLVED → owner phase (streaming): under exclusive access on `subContexts`
        //   the binary returns FUN_101b9b3a0(self, url) — the keyed remove/take. FUN_101b9b3a0
        //   is an unnamed FUN with no readable signature/body → NOT reconstructed; the lock +
        //   subContextsLock spine above is faithful.
        return nil
    }

    // s26 @101b9ad24 — `var subContextCount: Int` (name inferred, devirt). FAITHFUL
    //   (full): the LAST vtable slot (vtable_walk: VTableSize=27, so slot 26 is declared
    //   after the four sub-context methods above — hence its position here). Straight-line
    //   body, no branches: LOAD subContextsLock into a register (a bare ivar load feeding
    //   the msgSend stub — there is NO retain anywhere in this body; its only runtime call
    //   is `swift_beginAccess`), `objc lock`, then a
    //   READ `swift_beginAccess` (flags 0,0) on the `subContexts` ivar-offset global,
    //   load `*(storage + 0x10)` — `count` in `__RawDictionaryStorage`, which sits right
    //   after the 16-byte object header — then `objc unlock` and return that word. No
    //   `defer`-shaped cleanup is discernible (there is exactly one exit), so the
    //   lock/read/unlock is written straight-line to match; the siblings above use
    //   `defer` only because they have early exits.
    // ⚑[tool=prefetch_decompiles ref=HLSCacheIOContext.subContextCount.getter:0x101b9ad24 result=body full; NAME inferred]
    public var subContextCount: Int { // name inferred (devirt)
        subContextsLock.lock()
        let count = subContexts.count
        subContextsLock.unlock()
        return count
    }

    /// @0x101b9ad90 (extent 0x101b9ad90–0x101b9b1bc, 267 instr) — trie signature
    /// `static PreLoadIOContext.HLSCacheIOContext.clearCache(for: Swift.String) -> ()`.
    /// No `Tq` method descriptor, so it is a `static` (non-overridable) member, not `class`.
    ///
    /// Tractable because all 28 calls are Foundation/libc stubs — no KSPlayer helper, nothing
    /// devirtualized. Read straight through:
    ///   · 0x101b9ae70–0x101b9ae94 builds the directory: `NSTemporaryDirectory` →
    ///     `URL.init(fileURLWithPath:)` → `appendingPathComponent` with the immediate-formed
    ///     small string `mov x0,#0x6976 / movk 0x6564 / movk 0x436f / movk 0x6361`,
    ///     `x1 = 0x…6568/0x73` tagged `0xeb00` (count 11) = "videoCaches".
    ///   · 0x101b9aec8–0x101b9af28 lists it: `defaultManager`, `URL.path.getter`, then the
    ///     selector `contentsOfDirectoryAtPath:error:` with its error slot at [x29,#-0x70];
    ///     `cbz x20 → 0x101b9b078` is the failure arm, which runs
    ///     `_convertNSErrorToError` → `swift_willThrow` → `swift_errorRelease` and falls into
    ///     the epilogue without rethrowing — the signature is non-throwing, so that is `try?`
    ///     plus an early return. The success arm bridges via
    ///     `Array._unconditionallyBridgeFromObjectiveC` to `[String]`.
    ///   · 0x101b9af34–0x101b9af5c builds the prefix: `w8 = 0x6c68 / movk 0x5f73` = "hls_"
    ///     with `x9 = 0xE4…` (count 4) stored as a String at [x29,#-0x70], whose address goes
    ///     into x20 (swiftself for the `inout` receiver); the first `String.append` takes the
    ///     `for:` parameter in (x0,x1) — reloaded from [x29,#-0x88]/x28 — and the second takes
    ///     `w0 = 0x5f`, `x1 = 0xE1…` (count 1) = "_". So the prefix is "hls_" + md5 + "_".
    ///   · 0x101b9af98–0x101b9b030 is the loop: per element `hasPrefix` with self=(x20,x21)
    ///     the name and arg=(x25,x24) the prefix; `tbz w0,#0` skips a non-match; a match runs
    ///     `defaultManager`, `appendingPathComponent(name)`, `URL._bridgeToObjectiveC` and the
    ///     selector `removeItemAtURL:error:`, whose failure arm at 0x101b9b034 converts and
    ///     releases the error then branches back to 0x101b9af8c — the next iteration. Errors
    ///     are swallowed per-item, so that too is `try?`.
    /// ⚑[tool=export_trie_oracle ref=HLSCacheIOContext.clearCache:0x101b9ad90 result=static-no-Tq]
    /// ⚑[tool=decode_string_literal ref=HLSCacheIOContext.clearCache:0x101b9ae70 result=videoCaches/hls_/underscore]
    /// ⚑[tool=decode_objc_selector ref=HLSCacheIOContext.clearCache:0x101b9aec8 result=contentsOfDirectoryAtPath-error/removeItemAtURL-error]
    public static func clearCache(for md5: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("videoCaches")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return
        }
        var prefix = "hls_"
        prefix.append(md5)
        prefix.append("_")
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// @0x101b975e0 (21 instr) and @0x101b9757c (25 instr). `override_table.py --impl` answers
    /// YES at index 2 and index 1 respectively, so both override `AbstractAVIOContext`.
    ///
    /// Both delegate through `download` rather than owning a URLContext: `ldr x19,[x20,#0x18]`
    /// loads this class's field at +0x18 and then reads THAT object at ITS +0x18, which is the
    /// offset `URLContextDownload.nextAVOptions` already pins as `context`. So the object at
    /// +0x18 is a URLContextDownload — identified by what is dereferenced out of it, not by
    /// position — and `download` is this class's only field of that type.
    /// From there the shape is the same as the URLContextDownload pair: a READ `swift_beginAccess`
    /// (flags 0, 0) on that context slot, `cbz` → the base class's −1 default, otherwise one
    /// `ffurl_seek2` call — with `x1 = 0` / `w2 = 0x10000` (`AVSEEK_SIZE`, avio.h:468) for
    /// `fileSize`, and with the two parameters for `seek`.
    /// The callee's naming and the FFmpegKit shim prototype it needs are documented on
    /// `URLContextDownload.fileSize`.
    /// ⚑[tool=override_table ref=HLSCacheIOContext.fileSize:0x101b975e0 result=YES-index-2]
    /// ⚑[tool=override_table ref=HLSCacheIOContext.seek(offset:whence:):0x101b9757c result=YES-index-1]
    override public func fileSize() -> Int64 {
        guard let context = download.context else {
            return -1
        }
        return ffurl_seek2(context, 0, AVSEEK_SIZE)
    }

    override public func seek(offset: Int64, whence: Int32) -> Int64 {
        guard let context = download.context else {
            return -1
        }
        return ffurl_seek2(context, offset, whence)
    }

    // UNRESOLVED → later phase (do NOT reconstruct — declared nowhere beyond these
    //   markers; their bodies are deep/devirt and/or call stripped FFmpeg + DirectoryWatcher
    //   (1C.3) the P2 oracle names — fabrication risk):
    //   DEEP ENGINE (m3u8 fetch/parse + child prefetch → streaming/P2):
    //     • s19 (593 instr) @ — — m3u8 fetch/parse + child prefetch
    //     • s20 (798 instr) @ — — m3u8 fetch/parse + child prefetch engine (DirectoryWatcher
    //       1C.3 + stripped FFmpeg)
    //   DEVIRT (no readable body):
    //     • s21 @ — — devirtualized → P2
    //   the streaming engine is owned by a later phase. — NOT fabricated.
    //   (HLSSegment is deleted; it was never in the binary.)
}
