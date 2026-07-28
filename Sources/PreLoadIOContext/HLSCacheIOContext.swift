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
//             re-derived from the decompile). The ⚑ ones are best-effort (Optional/
//             composite shapes, plus the m3u8Buffer name is inferred) → l2_field_gate
//             UNCHECKs them (expected 0 FLAG). HLSSegment is an UNRESOLVED placeholder
//             — its real fields belong to the streaming owner phase, NOT fabricated here.
//   init    — the designated init s18 @101b96cb0 delegates to the inner field-store
//             init FUN_101b96cb0 (cached); reconstructed from that inner: it stores all
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

struct HLSSegment {}  // UNRESOLVED placeholder — real fields → owner phase (streaming)

public class HLSCacheIOContext: AbstractAVIOContext {
    // --- stored fields (brief table order + defaults; defaults are the inner init's
    //     flattened constants. Swift synthesizes accessors — do NOT hand-write get/set) ---

    // 0  download: the URLContextDownload that streams the manifest/segments. init-set
    //    (param; the inner retains it via _swift_retain).
    let download: URLContextDownload
    // 1  mediaId: the media identifier (also the hlsCacheDir leaf). init-set (param;
    //    String two-word, bridge-retained).
    let mediaId: String
    // 2  baseURL: the manifest base URL for resolving relative segment URLs. init-set
    //    (param_4; copied via Foundation::URL value-witness). ⚑ optionality inferred.
    let baseURL: URL? // ⚑ (optionality inferred; gate UNCHECKED)
    // 3  formatContextOptions: FFmpeg format-context options for child contexts. init-set
    //    (param_5).
    let formatContextOptions: [String: Any]
    // 4  hlsCacheDir: on-disk cache dir (tmpDir/videoCache/<mediaId>/hls). init-derived
    //    + createDirectory. ⚑ optionality inferred.
    let hlsCacheDir: URL? // ⚑ (optionality inferred; gate UNCHECKED)
    // 5  m3u8Buffer: the downloaded m3u8 manifest bytes. init nil. ⚑ name + type inferred
    //    (two-word optional zeroed in the inner).
    var m3u8Buffer: Data? = nil // ⚑ (name + type inferred; gate UNCHECKED)
    // 6  m3u8Parsed: whether the manifest has been parsed into `segments`. init false.
    var m3u8Parsed: Bool = false
    // 7  segments: the parsed HLS segment list. init []. ⚑ element type is the
    //    HLSSegment placeholder (UNRESOLVED).
    var segments: [HLSSegment] = [] // ⚑ (element type placeholder; gate UNCHECKED)
    // 8  subContexts: per-segment-URL child cache contexts, guarded by subContextsLock.
    //    init [:].
    var subContexts: [String: CacheIOContext] = [:]
    // 9  subContextsLock: serializes subContexts access. init NSLock().
    let subContextsLock: NSLock = NSLock()
    // 10 childHLSContexts: nested HLS cache contexts (variant playlists). init [].
    var childHLSContexts: [HLSCacheIOContext] = []
    // 11 prefetchCount: how many segments ahead to prefetch. init 3 (binary const).
    let prefetchCount: Int = 3
    // 12 prefetchQueue: concurrent queue driving segment prefetch. init
    //    DispatchQueue(label: "hls.prefetch", attributes: .concurrent) (binary string +
    //    get_concurrent + get_unspecified QoS).
    let prefetchQueue: DispatchQueue = DispatchQueue(label: "hls.prefetch", attributes: .concurrent)
    // 13 isClosed: whether close() has run. init false.
    var isClosed: Bool = false

    // --- designated init (s18 @101b96cb0 → inner FUN_101b96cb0) ---

    // Reconstructed from the inner field-store init: the param-fed fields (download,
    // mediaId, baseURL, formatContextOptions) are stored, every other field takes its
    // default above, then hlsCacheDir is derived as
    // NSTemporaryDirectory()/"videoCache"/<mediaId>/"hls" and created on disk (the inner
    // checks fileExistsAtPath: on the dir's path and, when absent, calls
    // createDirectoryAtURL:withIntermediateDirectories:attributes:error: — a throwing
    // create). Signature (param→field) transcribed from the inner's explicit stores; the
    // init symbol itself is absent so arity/labels are inferred. super.init(bufferSize:)
    // is the inherited AbstractAVIOContext spine.
    public init(download: URLContextDownload, mediaId: String, baseURL: URL?, formatContextOptions: [String: Any]) throws {
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
    // ⚑[tool=prefetch_decompiles ref=FUN_101b99cac:0x101b99cac result=lVar1=*(self+0x18)[download];beginAccess(lVar1+0x18);return*(lVar1+0x18) == download.context]
    public override var urlContext: UnsafeMutablePointer<URLContext>? { download.context }

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
    // ⚑[tool=disassemble ref=FUN_101b97b2c:0x101b97b2c result=ext=url.pathExtension.lowercased(); route (ext=="m3u8"||ext=="m3u"||url.absoluteString.contains(".m3u8"))→child-HLS else→segment-cache; success returns the sub-context AVIOContext* else nil (epilogue mov x0,#0)]
    // ⚑[tool=get_function_by_address ref=FUN_101b90c58:0x101b90c58 result=URLContextDownload designated-init inner (s3) — deferred to P8/IO-completion per URLContextDownload.swift; the child download build in both branches]
    // ⚑[tool=decompile ref=FUN_1019e258c:0x1019e258c result=AVIOContext materialization — avio_alloc_context-style (bufferSize@self+0x14, write-flag, read/write/seek callbacks, class 0x104c63590); shared KSPlayer outlined helper; the success-path return residue]
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
            // ⚑[tool=disassemble ref=FUN_101b96cb0:0x101b96cb0 result=HLSCacheIOContext designated init (this file) — the child (download:, mediaId:, baseURL:url, formatContextOptions:) construction, called after the P8 URLContextDownload build]
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
        //   trailing segment-match loop over `segments` (its element URL read goes through the HLSSegment
        //   placeholder layout, like segmentIndex) are NOT reconstructed; the AVIOContext materialization +
        //   non-nil return are characterized only. The lock discipline + miss-path spine above are faithful.
        // ⚑[tool=get_function_by_address ref=FUN_101b86a2c:0x101b86a2c result=segment cache-key String builder (URLComponents queryItems/url, 651B)]
        // ⚑[tool=get_function_by_address ref=FUN_1019f0d98:0x1019f0d98 result=String(UTF8View,count) re-encode in the cache-key derivation]
        // ⚑[tool=get_function_by_address ref=FUN_101b9b45c:0x101b9b45c result=subContexts keyed insert (same helper setSubContext pins, 335B)]
        // ⚑[tool=disassemble ref=FUN_101b86d38:0x101b86d38 result=CacheIOContext designated init (in-module/done, CacheIOContext.swift:147); addSub calls it with bufferSize=0x40000 saveFile=true isReadComplete=false]
        return nil
    }

    // --- methods (only the 4 cached small methods; names devirt→inferred) ---

    // s22 @101b9a960 — `func segmentIndex(for url: URL) -> Int?` (name inferred, devirt).
    //   FAITHFUL SPINE + UNRESOLVED on the segment element shape. The decompile takes a
    //   URL, computes its absoluteString, then under exclusive access on `segments`
    //   iterates the array comparing each segment's `URL.absoluteString` (via
    //   get_absoluteString + Swift._stringCompareWithSmolCheck) and returns the matching
    //   index (the found-marker pair {index, found}); miss → none. The per-element URL
    //   read goes through HLSSegment's value-witness layout, whose fields are the
    //   UNRESOLVED placeholder → the comparison body is a faithful spine, the element
    //   access is NOT reconstructed.
    func segmentIndex(for url: URL) -> Int? { // name inferred (devirt)
        let target = url.absoluteString
        for index in segments.indices {
            _ = index
            _ = target
            // UNRESOLVED → owner phase (streaming): the binary reads segments[index]'s URL
            //   via HLSSegment's value-witness layout, computes its .absoluteString and
            //   compares to `target` (get_absoluteString + _stringCompareWithSmolCheck);
            //   on equality returns `index`. HLSSegment's fields are the UNRESOLVED
            //   placeholder → the element URL access is NOT reconstructed; the loop/compare
            //   spine above is faithful.
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
        //   layout (HLSSegment placeholder) → NOT reconstructed; the lock + empty-guard +
        //   lookup spine are faithful.
        return nil
    }

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
    var subContextCount: Int { // name inferred (devirt)
        subContextsLock.lock()
        let count = subContexts.count
        subContextsLock.unlock()
        return count
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
    //   HLSSegment's fields are owned by the streaming phase. — NOT fabricated.
}
