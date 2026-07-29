//
//  MEPlayerItem.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import FFmpegKit
import Libavcodec
import Libavfilter
import Libavformat

// ⚑ @unchecked Sendable — compiler-MANDATED, not binary-observable: the interrupt codegen is a `{ [weak self] }`
//   @Sendable closure (openAndFindStream) which, under this target's Swift 6 + StrictConcurrency, compiles ONLY if
//   MEPlayerItem is Sendable. Sendable is a marker protocol ⟹ NO ABI/reflection trace, so it's codegen-invisible
//   but forced by the observed closure + IOInterruptContext.block's @Sendable type. The interrupt fires on FFmpeg's
//   IO thread, so @Sendable-block-over-Sendable-self is the coherent faithful design; `unchecked` = the internal
//   -locking assertion the player already makes. ⚑[tool=read_memory ref=weakSelfBox:0x1041d8340 result=@Sendable⟹Sendable-self]
public final class MEPlayerItem: @unchecked Sendable {
    // ⚑ Field-layout migration (commit-1): the 42 stored properties in Forward binary order
    //   (scripts/dump_binary_field_types.py MEPlayerItem). Types from MEPlayerItem.init
    //   (FUN_101a4bae0) + name_type_at_addr; residual generic/closure exactness flagged  ⚑[tool=resolve_fun_pins ref=FUN_101a4bae0:0x101a4bae0 result=RESOLVES_UNIQUELY] = KSPlayer.MEPlayerItem.init(io: KSPlayer.Either<Foundation.URL, KSPlayer.AbstractAVIOContext>, options: KSPlayer.KSOptions) -> KSPlayer.MEPlayerItem
    //   // ⚑ UNRESOLVED (field-record None ⟹ l2 UNCHECKED, non-blocking). The 17 base fields are
    //   removed; every method that used them is stubbed // ⚑ UNRESOLVED pending its Forward-body commit.
    private var io: Either<URL, AbstractAVIOContext>                 // 1 ⚑[tool=name_type_at_addr ref=io:0x103566d40 result=Either<_,AbstractAVIOContext>] first param URL (sibling KSAVPlayer.io)
    public let options: KSOptions                                   // 2
    public var isPreload = false                                    // 3
    private var ioTask: Task<Void, Never>?                           // 4 ⚑ UNRESOLVED generics (Task confirmed, nil-init)
    private let ioWaiterLock = NSLock()                              // 5
    private var ioWaiter: CheckedContinuation<Void, Never>?          // 6 ⚑[tool=name_type_at_addr ref=ioWaiter:0x1035647f8 result=ScC<(),_>] error-param pending
    fileprivate var formatContext: FormatContext?                        // 7
    private var remuxer: Remuxer?                                    // 8
    private var seekTime = TimeInterval(0)                           // 9
    private var seekUsePacketCache = false                           // 10
    private var seekingCompletionHandler: ((Bool) -> Void)?          // 11
    // 没有音频数据可以渲染
    private var isAudioStalled = true                               // 12
    private var audioClock = KSClock()                              // 13
    private var videoClock = KSClock()                              // 14
    private var isFirst = true                                     // 15
    private var isSeek = false                                     // 16
    private var needRecordTimeIndex = false                        // 17
    private let playbackSnapshotRecordInterval = 0.5               // 18
    private var lastPlaybackSnapshotRecordTime: Double?            // 19
    private let timeIndexRecordInterval = 1.0                      // 20
    private var lastTimeIndexRecordTime: Double?                   // 21
    private var needSeekItemTrack = true                          // 22
    private var allPlayerItemTracks = [PlayerItemTrackProtocol]()  // 23
    private var videoAudioTracks = [CapacityProtocol]()           // 24
    private var videoTrack: SyncPlayerItemTrack<VideoVTBFrame>?    // 25
    private var audioTrack: SyncPlayerItemTrack<AudioFrame>?       // 26
    private var subtitleTrack: SyncPlayerItemTrack<SubtitleFrame>? // 27 (nil-init parallel; SubtitleFrame: MEFrame, Model.swift:245)
    private var videoAdaptation: VideoAdaptationState?            // 28
    fileprivate var pbArray = [PBClass]()                             // 29
    private var interrupt = false                                // 30
    private var prePosition: Int64 = 0                           // 31 ⚑ UNRESOLVED: single-word 0-init; Int64|Int|Double pending assignment site
    // 32 — the saved default AVFormatContext.io_open, boxed as a Swift closure (2-word [fn,ctx], the
    //   io_open C signature); ioOpen() falls back to it when there is no ioContext / addSub declines. The
    //   install (saving + boxing formatCtx's original io_open) is the ⚑UNRESOLVED openAndFindStream arm.
    // ⚑[tool=decompile ref=defaultIOOpen:0x101a53560 result=io_open-signature-closure]
    fileprivate var defaultIOOpen: ((UnsafeMutablePointer<AVFormatContext>?, UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Int32)? // 32
    // 33 — the saved default AVFormatContext.io_close2, boxed as a Swift closure (2-word [fn,ctx],
    //   the io_close2 signature (AVFormatContext*, AVIOContext*) -> Int32); ioClose() always delegates
    //   to it after the pbArray cleanup. The install (boxing formatCtx's original io_close2) is the
    //   ⚑UNRESOLVED openAndFindStream arm.
    // ⚑[tool=decompile ref=defaultIOClose:0x101a53924 result=io_close2-signature-closure]
    fileprivate var defaultIOClose: ((UnsafeMutablePointer<AVFormatContext>?, UnsafeMutablePointer<AVIOContext>?) -> Int32)? // 33
    public private(set) var chapters: [Chapter] = []            // 34
    public private(set) var duration: TimeInterval = 0          // 35
    public private(set) var fileSize: Int64 = 0                // 36 MediaPlayback.fileSize Int64 (bin field-record Int? UNCHECKED — kept Int64 per protocol)
    public private(set) var naturalSize = CGSize.zero        // 37 ⚑ bin field-record CGSize? (init nil), but MediaPlayback requires non-optional CGSize → kept CGSize; CGSize? deferred with the protocol migration
    private var state = State.idle {                         // 38 RESOLVED: nested MEPlayerItem.State (10 cases; desc @0x1039ef8b0, Model.swift). Was base MESourceState.
        didSet {
            switch state {
            case .ready:                          // base `opened` (raw 2); renamed in Forward
                delegate?.sourceDidOpened()
            case .reading:
                timer?.fireDate = Date.distantPast
            case .closed:
                timer?.invalidate()
            case .failed:
                delegate?.sourceDidFailed(error: nil) // ⚑ UNRESOLVED: base passed removed `error` field; Forward error-source pending
                timer?.fireDate = Date.distantFuture
            case .idle, .opening, .seeking, .paused, .endOfStream, .finished:
                // ⚑ endOfStream (raw 6, NEW in Forward): base-derived no-op; Forward state.didSet body pending its own audit
                break
            }
        }
    }
    private var timer: Timer?                                // 39 Forward NSTimer? nil-init (base was `lazy var timer: Timer = .scheduledTimer`); scheduling site pending. Timer === NSTimer (reflection emits NSTimer)
    private let preloadClock = ContinuousClock()            // 40 ⚑ init calls Swift.ContinuousClock.init(); ContinuousClock vs .Instant pending
    private var lastPacketMediaType: AVFoundation.AVMediaType = .video // 41 init AVMediaTypeVideo (AVFoundation constant; codebase disambiguates from FFmpeg AVMediaType)
    public weak var delegate: MEPlayerDelegate?                    // 42

    public var currentPlaybackTime: TimeInterval {
        state == .seeking ? seekTime : mainClock().time.seconds // ⚑ UNRESOLVED: base subtracted removed `startTime`
    }

    // ⚑ Forward moved the per-stream FFmpegAssetTracks into FormatContext (FormatContext.swift:59 `assetTracks`
    //   @+0x40); MEPlayerItem's stored `assetTracks` field is removed. This computed bridge reads the migrated
    //   source so the external reader KSMEPlayer.tracks(mediaType:) stays green (Forward may instead read
    //   formatContext.assetTracks directly — resolved when KSMEPlayer.tracks migrates).
    var assetTracks: [FFmpegAssetTrack] { formatContext?.assetTracks ?? [] }

    public lazy var dynamicInfo = DynamicInfo {
        toDictionary(nil) // ⚑ UNRESOLVED: base read self.formatCtx.pointee.metadata (removed field); FormatContext raw-ptr accessor pending
    } bytesRead: {
        0 // ⚑ UNRESOLVED: base read self.formatCtx.pointee.pb.pointee.bytes_read (removed field)
    } audioBitrate: { [weak self] in
        Int(8 * (self?.audioTrack?.bitrate ?? 0))
    } videoBitrate: { [weak self] in
        Int(8 * (self?.videoTrack?.bitrate ?? 0))
    }

    nonisolated(unsafe) private static var onceInitial: Void = {
        var result = avformat_network_init()
        av_log_set_callback { ptr, level, format, args in
            guard let format else {
                return
            }
            var log = String(cString: format)
            let arguments: CVaListPointer? = args
            if let arguments {
                log = NSString(format: log, arguments: arguments) as String
            }
            if let ptr {
                let avclass = ptr.assumingMemoryBound(to: UnsafePointer<AVClass>.self).pointee
                if avclass == avfilter_get_class() {
                    let context = ptr.assumingMemoryBound(to: AVFilterContext.self).pointee
                    if let opaque = context.graph?.pointee.opaque {
                        let options = Unmanaged<KSOptions>.fromOpaque(opaque).takeUnretainedValue()
                        options.filter(log: log)
                    }
                }
            }
            // 找不到解码器
            if log.hasPrefix("parser not found for codec") {
                KSLog(level: .error, log)
            }
            KSLog(level: LogLevel(rawValue: level) ?? .warning, log)
        }
    }()

    public init(url: URL, options: KSOptions) {
        io = .left(url) // ⚑ Forward io: Either<URL, AbstractAVIOContext>; init wraps url (sibling KSAVPlayer.io = .left(url)); Forward init may take io: directly (caller builds the Either)
        self.options = options
        _ = MEPlayerItem.onceInitial
    }

    func select(track: some MediaPlayerTrack) -> Bool {
        // ⚑ UNRESOLVED (commit-1 stub): base body used the removed `assetTracks` field + findBestAudio/seek.
        //   Forward body deferred to its own commit (allPlayerItemTracks-based track selection).
        false
    }
}

// MARK: private functions

extension MEPlayerItem {
    // openAndFindStream() — the open/find/WIRE path (the read loop is readThread/reading). FAITHFUL-PARTIAL:
    //   the interrupt closure + openFormatContext/FormatContext wiring + fileSize/duration/formatName/chapters
    //   + the createCodec call are reconstructed; the leading KSLog, close/reset call, custom-AVIO install,
    //   pbArray append, io.right AVIO path, and KSOptions rate×duration store are flagged // ⚑ UNRESOLVED.
    // ⚑[tool=recover_swift_function_name ref=openAndFindStream:0x101a4d3d0 result=#function/throws/no-params]
    private func openAndFindStream() throws {
        // ⚑ UNRESOLVED: leading KSLog(.debug, …) gated on `2 < logLevel` (prologue global DAT_1044e5173) — message deferred.
        // ⚑ UNRESOLVED: a close/reset call precedes the open to reset prior state; method identity + body deferred.
        //   ⚑[tool=recover_swift_function_name ref=closeReset:0x101a531fc result=no-#function/739B]

        // io: Either<URL, AbstractAVIOContext>. .left(URL) = the reconstructed plain-URL open; .right = the
        //   custom-AVIO/preload open — DEFERRED (custom-AVIO campaign; the AbstractAVIOContext threads into
        //   openFormatContext's url-AVIO arm + FormatContext.init(ioContext:)).
        let url: URL?
        switch io {
        case let .left(fileURL):
            url = fileURL
        case .right:
            url = nil  // ⚑ UNRESOLVED: .right(AbstractAVIOContext) custom-AVIO wiring deferred
        }

        // Interrupt callback — FAITHFUL. A `{ [weak self] }` closure (compiler HeapLocalVariable box, metadata
        //   kind 0x400 — NOT a user class): abort blocking IO when self is gone, an interrupt was requested, or
        //   state is terminal ((state & 0xfe)==8 ≡ .closed || .failed).
        //   ⚑[tool=read_memory ref=weakSelfBox:0x1041d8340 result=HeapLocalVariable/[weak self]]
        //   ⚑[tool=decompile ref=interruptTrampoline:0x101a534e0 result=self==nil||interrupt||terminal]
        let interruptContext = IOInterruptContext { [weak self] in
            guard let self else { return true }
            if self.interrupt { return true }
            return self.state == .closed || self.state == .failed
        }

        // openFormatContext(time:0, …) → AVFormatContext*; `time:0` is the dead d0 residue (#function no params).
        //   ⚑[tool=decompile ref=openFormatContext:0x101a392a0 result=try-throws→AVFormatContext*]
        let formatCtx = try openFormatContext(time: 0, url: url, interrupt: interruptContext, options: options, cacheKey: nil)

        // FormatContext dead-arg init (duration:0, fileSize:0 — the init re-derives both; the audited
        //   FFmpegSubtitle.init precedent, FFmpegSubtitle.swift:44).
        //   ⚑[tool=decompile ref=FormatContextInit:0x101a350bc result=dead-arg-init]
        let formatContext = FormatContext(duration: 0, formatCtx: formatCtx, fileSize: 0,
                                          interrupt: interruptContext, ioContext: nil, fontsDir: options.fontsDir)
        self.formatContext = formatContext

        // Custom-AVIO install (unconditional) — save + BOX the format context's default io_open/io_close2
        //   into defaultIOOpen/defaultIOClose (each a Swift closure that captures the original C fn-ptr and
        //   forwards to it — the compiler emits the boxed-closure thin entry, storing the captured fn-ptr in
        //   the box), stash self in the format context's opaque, and install our two @convention(c) thunks
        //   (ioOpen/ioClose are context-free statics → the compiler emits the matching adapters). The
        //   AVFormatContext fields are accessed symbolically; `formatCtx` is the AVFormatContext* the
        //   FormatContext wraps (== the openFormatContext local, stored at FormatContext+0x18). Order matches
        //   the binary: box io_open → opaque=self → io_open thunk → box io_close2 → io_close2 thunk.
        // ⚑[tool=decompile ref=customAVIOInstall:0x101a4d3d0 result=saves formatCtx.io_open@+0x1c0/io_close2@+0x1c8 (boxed→defaultIOOpen/Close), opaque@+0x1a0=self, installs the ioOpen/ioClose thunks]
        // ⚑[tool=decompile ref=boxTrampolineOpen:0x101a5a0c4 result=io_open boxed-closure thin-entry: loads captured fn-ptr @box+0x10 and forwards]
        // ⚑[tool=decompile ref=boxTrampolineClose:0x101a5a0bc result=io_close2 boxed-closure thin-entry]
        // ⚑[tool=decompile ref=ioOpenThunk:0x101a53560 result=@convention(c) adapter the compiler emits for MEPlayerItem.ioOpen]
        // ⚑[tool=decompile ref=ioCloseThunk:0x101a53924 result=@convention(c) adapter for MEPlayerItem.ioClose]
        if let defaultOpen = formatCtx.pointee.io_open {
            defaultIOOpen = { s, pb, url, flags, options in defaultOpen(s, pb, url, flags, options) }
        } else {
            defaultIOOpen = nil
        }
        formatCtx.pointee.opaque = Unmanaged.passUnretained(self).toOpaque()
        formatCtx.pointee.io_open = ioOpen
        if let defaultClose = formatCtx.pointee.io_close2 {
            defaultIOClose = { s, pb in defaultClose(s, pb) }
        } else {
            defaultIOClose = nil
        }
        formatCtx.pointee.io_close2 = ioClose
        // ⚑ UNRESOLVED: pbArray append — allocs a PBClass and appends it to self.pbArray (field 29), then on a
        //   successful dynamic-cast writes KSOptions seekUsePacketCache=false + a formatContextOptions entry.
        //   ⚑[tool=decompile ref=pbClassAlloc:0x101a5a030 result=deferred-PBClass-body]

        options.formatName = formatContext.formatName        // String @+0x48 (DERIVED from iformat.name)
        self.fileSize = formatContext.fileSize               // +0x30
        self.duration = formatContext.duration               // +0x28
        // ⚑ UNRESOLVED: KSOptions rate×duration — `if options[+0x38] > 0 { options[+0x30] = options[+0x38] ×
        //   formatContext.duration }` (two KSOptions Double fields; offset→name mapping deferred).
        self.chapters = formatContext.chapters               // FormatContext.chapters getter (DONE, commit-2a)

        //   ⚑[tool=get_xrefs_to ref=createCodec:0x101a53c44 result=argless]
        createCodec()                                        // track-set builder (argless, reads self.formatContext; slice-1 reconstructed)
    }

    // ioOpen / ioClose (the custom-AVIO open/close2 callbacks) are declared at FILE SCOPE (below PBClass):
    //   a static method cannot form a C function pointer in Swift 6, so `formatCtx.io_open = MEPlayerItem.ioOpen`
    //   does not compile — a top-level func does. openAndFindStream installs them (@convention(c) thunks).

    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer12MEPlayerItemC11startRecord3url9mediaTypey10Foundation3URLV_So07AVMediaF0aSgtF:0x101a483d4 result=SIGNATURE_CORRECTED]
    // The `mediaType:` parameter is established three ways and is LIVE in the binary: the body's own
    // `#function` literal (0x103d366d0) decodes to "startRecord(url:mediaType:)"; x1 is stored to
    // Remuxer+0x20 with `objc_retain` @0x101a484b4 and forwarded as x7; and Remuxer field 3 is
    // `mediaType: AVMediaType?`. The sole caller passes nil — MEASURED (`mov x1,#0x0` immediately
    // before `bl 0x101a483d4` at KSMEPlayer.startRecord @0x101a444b8), not assumed.
    // ⚑ BODY UNRESOLVED — verdict MEPlayerItem_startRecord_101a483d4.json (HIGH). The binary has a
    // complete 183-instruction body (guard formatContext → tear down the old remuxer → build one
    // inline → install; on throw, deallocPartialClassInstance + KSLog(.error)). It is NOT written
    // here because it depends on two things the reconstruction cannot yet express:
    // ⚑[tool=export_trie_oracle ref=$s10Foundation3URLV8KSPlayerE12ffmpegStringSSvg:0x1019f59c4 result=LOCATED]
    //   — `URL.ffmpegString` exists in the binary and is ABSENT from our source; and
    // ⚑[tool=function_sizes ref=FUN_101a1d014:0x101a1d014 result=INFERRED]
    //   — the throwing callee takes 9 argument slots with an object in x7, which the reconstructed
    //   `OutputStreamInfo.init(formatContext:filename:…)` has no parameter able to receive, so the
    //   two cannot both be right. Guessing either would fabricate; this is the pinned deferral.
    // `AVFoundation.AVMediaType`, not FFmpeg's `AVMediaType` C enum — the two collide in this module
    // and the binary disambiguates them: x1 is stored with `objc_retain` @0x101a484b4, so it is the
    // ObjC NSString-backed type, not a plain C int.
    func startRecord(url _: URL, mediaType _: AVFoundation.AVMediaType?) {}

    // createCodec() = FUN_101a53c44 (~2145 lines w/ 3 inline closures FUN_101a556b0/36964/36cf0). ARGLESS —
    //   reads self.formatContext (the commit-1 `formatCtx:` param was the BASE signature; Forward is argless).
    //   Being reconstructed in SLICES (this body is too large/intricate for one reliable partial). SLICE 1 =
    //   the reset prologue + formatContext nil-guard + the isAudioStalled tail; the track-BUILD, rotation/
    //   filter, and adaptation arms are flagged // ⚑ UNRESOLVED for their own slices.
    // ⚑[tool=get_xrefs_to ref=createCodec:0x101a53c44 result=argless/self.formatContext]
    private func createCodec() {
        // Reset prologue (FUN_101a53c44 @0x101a53d?-53e?): clear the adaptation + track fields, shutdown existing tracks.
        videoAdaptation = nil
        videoTrack = nil
        audioTrack = nil
        videoAudioTracks = []
        allPlayerItemTracks.forEach { $0.shutdown() }   // witness+0x80 = PlayerItemTrackProtocol.shutdown()
        guard let formatContext else { return }         // self.formatContext; nil → early return (no track build)

        // SLICE 2 (closure FUN_101a556b0): rebuild the subtitle tracks from formatContext.assetTracks. Every track
        //   is disabled (track.isEnabled = false — the disable-all reset; slices 3/4 re-enable the selected
        //   video/audio). The `discard` values the disasm writes (non-sub→ALL, image-sub→ALL, text-sub→DEFAULT) are
        //   exactly what the isEnabled setter yields for newValue=false, so this IS `isEnabled = false`. For subtitle
        //   tracks a SyncPlayerItemTrack<SubtitleFrame> is built: image subtitles share the single self.subtitleTrack
        //   (frameCapacity 8, built once); text subtitles get a per-track one (frameCapacity 128). BOTH branches were
        //   disasm-confirmed to build SyncPlayerItemTrack<SubtitleFrame> (metadata 0x10356ac50), which is why
        //   track.subtitle (+0x100) is homogeneous. delegate = self is a weak assign (+0x40).
        allPlayerItemTracks = []
        for track in formatContext.assetTracks {
            track.isEnabled = false
            if track.mediaType == .subtitle {
                if track.isImageSubtitle {
                    if subtitleTrack == nil {
                        let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 8, options: options)
                        allPlayerItemTracks.append(subtitle)    // append BEFORE delegate: the binary's append endAccess barrier (0x101a55a74) precedes the delegate weakAssign (0x101a55a88) — matches the text branch order
                        subtitle.delegate = self
                        subtitleTrack = subtitle
                    }
                    track.subtitle = subtitleTrack
                } else {
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options)
                    subtitle.delegate = self
                    track.subtitle = subtitle
                    allPlayerItemTracks.append(subtitle)
                }
            }
        }
        // ⚑ UNRESOLVED (SLICE 2 — the 2nd-pass embed-subtitle registration, Forward-ADDED): the subtitle
        //   FFmpegAssetTracks are collected + cast to [any SubtitleInfo] (FFmpegAssetTrack: SubtitleInfo via
        //   EmbedDataSouce.swift; conformance witness 0x1041d7668) and passed to a KSOptions method at
        //   vtable[0x768], whose result gets a follow-on witness[+0x40](true) dispatch. That method is Forward-
        //   added: absent from source AND the origin/forward base, and statically unresolvable (metadata slot
        //   md+0x768 is an unbound pattern value 0x105395200 with no function).
        //   ⚠️ NAMED (session 63) — the P43 negative above is REFUTED. It concluded "statically
        //   unresolvable" from source ✗ / base ✗ / static metadata ✗; none of those three can see
        //   the ORPHANED export trie, which carries exactly one KSOptions member taking a subtitle
        //   track array:
        //       KSPlayer.KSOptions.wantedSubtitle(tracks: [KSPlayer.SubtitleInfo]) -> KSPlayer.SubtitleInfo?
        //   That signature matches this call site precisely: [any SubtitleInfo] in, an OPTIONAL out
        //   feeding the follow-on witness[+0x40](true) dispatch. The body is still not reconstructed
        //   — what changes is that the method is no longer nameless, and "absent from source AND the
        //   origin/forward base" is now a Forward-ADDED method with a known signature.
        // ⚑[tool=export_trie_oracle ref=KSOptions.wantedSubtitle(tracks:) result=NAMED — supersedes the get_function_by_address FAILED-SEARCH]
        // ⚑ UNRESOLVED (SLICE 3 — audio, closures FUN_101a36964/36cf0 + tail): audio sample-rate sampling
        //   (audioStreamBasicDescription) + max-reduction + the KSOptions.vtable[0x6f8] call + AudioPlayerItemTrack
        //   (FUN_101a383a8/33444) construction.
        // ⚑ UNRESOLVED (SLICE 4 — rotation/filter): isRotateByFilter → transpose_vt/videoFilters/hardwareDecode/
        //   asynchronousDecompression + the 90°-rotation angle math.
        // ⚑ UNRESOLVED (SLICE 5 — adaptation): videoAdaptation rebuild + naturalSize.

        isAudioStalled = false   // tail (@0x101a55d??): *(self + ::isAudioStalled) = 0, unconditional on the non-nil path
    }

    private func read() {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed readOperation/operationQueue (BlockOperation on
        //   an OperationQueue). Forward drives reading via `ioTask: Task` (field 4). Deferred to the read/ioTask
        //   migration commit.
    }

    private func readThread() {
        // ⚑ UNRESOLVED (commit-1 stub): base body used removed formatCtx/startTime/seekByBytes/condition (the
        //   OperationQueue read+seek loop). Forward's read loop runs under `ioTask: Task` with `ioWaiter:
        //   CheckedContinuation` + `ioWaiterLock: NSLock` for suspension. See `reading()` for the characterized
        //   ioTask-driven read-loop cluster (driver / error-handler / reconnect). Deferred to Stage-2 DEEP.
    }

    private func reading() -> Int32 {
        // ⚑ UNRESOLVED → Stage-2 DEEP (a runtime-keystone CLUSTER, ioTask-reached, static-invisible).
        //   The Forward read machinery is a 3-function cluster driven from `ioTask: Task` (a thread entry
        //   the static Swift→Swift callee graph cannot see — topo_readiness v1 confirms the driver is NOT
        //   in its analyzed universe). Characterized here (named residuals + closure), NOT reconstructed —
        //   deferred to the Stage-2 EASY/DEEP partition (topo_readiness v2 seeds the ioTask thread-entry
        //   root so the cluster becomes a tracked keystone). The exact per-track reset requirement and all
        //   three names are #function-unrecoverable → the witness offset needs the PlayerItemTrackProtocol
        //   witness table decoded at reconstruction time. NOT fabricated.
        //     • DRIVER — the packet-read/demuxer loop; on a read error it calls the error handler.
        // ⚑[tool=get_function_by_address ref=FUN_101a512b4:0x101a512b4 result=read-loop driver ~575 insns; ioTask-reached runtime keystone, static-invisible (topo_readiness v1: absent from universe)]
        //     • ERROR HANDLER — decides per errno: AVERROR_EOF/feof → reconnect-or-finish; EIO/EPIPE →
        //       reconnect (below); else → a `readFrame_fail` KSPlayerError (s_readFrame_fail).
        // ⚑[tool=decompile ref=FUN_101a5685c:0x101a5685c result=read-error handler ~415 insns — EOF/reconnect/readFrame_fail decision; sole caller of the reconnect arm]
        //     • RECONNECT ARM — KSLog + `try? openAndFindStream()` + `allPlayerItemTracks.forEach { $0.<reset>() }`.
        // ⚑[tool=decompile ref=FUN_101a56ecc:0x101a56ecc result=reconnect arm ~40 insns — level-gated KSLog + openAndFindStream + per-track witness+0x58 reset (offset needs PlayerItemTrackProtocol WT decode; shutdown is witness+0x80)]
        0
    }

    private func pause() {
        if state == .reading {
            state = .paused
        }
    }

    private func resume() {
        // ⚑ UNRESOLVED (commit-1 stub): base set state=.reading + signalled the removed `condition` (NSCondition).
        //   Forward resumes the read loop via `ioWaiter: CheckedContinuation` + `ioWaiterLock`. Deferred to the
        //   read-loop migration commit.
    }
}

// MARK: MediaPlayback

extension MEPlayerItem: MediaPlayback {
    var seekable: Bool {
        // ⚑ UNRESOLVED (commit-1 stub): base read the removed `formatCtx` field's pb.seekable. Forward reads it
        //   via `formatContext` (field 7). Deferred to the seekable migration commit.
        false
    }

    public func prepareToPlay() {
        state = .opening
        // ⚑ UNRESOLVED (commit-1 stub): base launched openThread via the removed openOperation/operationQueue
        //   (BlockOperation on an OperationQueue). Forward launches openAndFindStream under `ioTask: Task` (field 4).
        //   Deferred to the openAndFindStream/ioTask migration commit.
    }

    public func shutdown() {
        guard state != .closed else { return }
        state = .closed
        // ⚑ UNRESOLVED (commit-1 stub): base tore down via the removed outputPacket/formatCtx/outputFormatCtx/
        //   closeOperation/readOperation/openOperation/operationQueue/condition. Forward closes formatContext/remuxer
        //   and cancels `ioTask`. Deferred to the shutdown migration commit.
    }

    func stopRecord() {
        // ⚑ UNRESOLVED (commit-1 stub): base wrote the trailer on the removed `outputFormatCtx`. Forward routes
        //   recording through `remuxer` (field 8). Deferred to the remuxer migration commit.
    }

    public func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed `condition` (NSCondition.broadcast) + read() to drive
        //   seeking. Forward signals the read loop via `ioWaiter`. Deferred to the seek migration commit.
        completion(false)
    }
}

extension MEPlayerItem: CodecCapacityDelegate {
    func codecDidChangeCapacity() {
        let loadingState = options.playable(capacitys: videoAudioTracks, isFirst: isFirst, isSeek: isSeek)
        delegate?.sourceDidChange(loadingState: loadingState)
        if loadingState.isPlayable {
            isFirst = false
            isSeek = false
            if loadingState.loadedTime > options.maxBufferDuration {
                adaptableVideo(loadingState: loadingState)
                pause()
            } else if loadingState.loadedTime < options.maxBufferDuration / 2 {
                resume()
            }
        } else {
            resume()
            adaptableVideo(loadingState: loadingState)
        }
    }

    func codecDidFinished(track: some CapacityProtocol) {
        if track.mediaType == .audio {
            isAudioStalled = true
        }
        let allSatisfy = videoAudioTracks.allSatisfy { $0.isEndOfFile && $0.frameCount == 0 && $0.packetCount == 0 }
        if allSatisfy {
            delegate?.sourceDidFinished()
            timer?.fireDate = Date.distantFuture // timer now optional (field 39 NSTimer?)
            if options.isLoopPlay {
                isAudioStalled = audioTrack == nil
                audioTrack?.isLoopModel = false
                videoTrack?.isLoopModel = false
                if state == .finished {
                    seek(time: 0) { _ in }
                }
            }
        }
    }

    private func adaptableVideo(loadingState: LoadingState) {
        // ⚑ UNRESOLVED (commit-1 stub): base selected the new-bitrate track from the removed `assetTracks` field.
        //   Forward's adaptation reads the track set via allPlayerItemTracks. Deferred to the adaptation migration commit.
    }

    private func findBestAudio(videoTrack: FFmpegAssetTrack) {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed `assetTracks` + `formatCtx` fields. Forward reads the
        //   track set via allPlayerItemTracks + formatContext. Deferred to the findBestAudio migration commit.
    }
}

extension MEPlayerItem: OutputRenderSourceDelegate { // refines Audio+Video (session 16b); satisfies both binary conformances + stays assignable to the Phase-N renderers' renderSource
    func mainClock() -> KSClock {
        isAudioStalled ? videoClock : audioClock
    }

    public func setVideo(time: CMTime, position: Int64) {
//        print("[video] video interval \(CACurrentMediaTime() - videoClock.lastMediaTime) video diff \(time.seconds - videoClock.time.seconds)")
        videoClock.time = time
        videoClock.position = position
        // ⚑ UNRESOLVED (commit-1): base updated dynamicInfo.displayFPS via the removed videoDisplayCount/
        //   lastVideoDisplayTime fields. Forward's displayFPS accounting is deferred to that migration.
    }

    public func setAudio(time: CMTime, position: Int64) {
//        print("[audio] setAudio: \(time.seconds)")
        // 切换到主线程的话，那播放起来会更顺滑
        runOnMainThread {
            self.audioClock.time = time
            self.audioClock.position = position
        }
    }

    public func getVideoOutputRender(force: Bool) -> VideoVTBFrame? {
        guard let videoTrack else {
            return nil
        }
        var type: ClockProcessType = force ? .next : .remain
        let predicate: ((VideoVTBFrame, Int) -> Bool)? = force ? nil : { [weak self] frame, count -> Bool in
            guard let self else { return true }
            // DynamicInfo.audioVideoSyncDiff is Float in the binary (field record `Sf`), not Double, so
            // the base's one-line tuple assignment from the Double-returning videoClockSync has to spell
            // the narrowing out. Type change only — the arithmetic and the control flow are unchanged.
            // ⚑ UNRESOLVED: Forward may not compute the diff here at all. Every reader/writer of the field
            //   is an xref of its field-offset global
            //   ⚑[tool=get_xrefs_to ref=DynamicInfo.audioVideoSyncDiff:0x104c63578 result=CONFIRMED],
            //   and no getVideoOutputRender closure is among them; the only non-init writer is the
            //   videoClock/setVideo path
            //   ⚑[tool=decompile_function ref=MEPlayerItem.setVideo:0x101a5804c result=LOCATED].
            //   Deferred to the MEPlayerItem migration — settling it is not this unit's lane.
            let (syncDiff, syncType) = self.options.videoClockSync(main: self.mainClock(), nextVideoTime: frame.seconds, fps: Double(frame.fps), frameCount: count)
            self.dynamicInfo.audioVideoSyncDiff = Float(syncDiff)
            type = syncType
            return type != .remain
        }
        let frame = videoTrack.getOutputRender(where: predicate)
        switch type {
        case .remain:
            break
        case .next:
            break
        case .dropNextFrame:
            if videoTrack.getOutputRender(where: nil) != nil {
                dynamicInfo.droppedVideoFrameCount += 1
            }
        case .flush:
            let count = videoTrack.outputRenderQueue.count
            videoTrack.outputRenderQueue.flush()
            dynamicInfo.droppedVideoFrameCount += UInt32(count)
        case .seek:
            videoTrack.outputRenderQueue.flush()
            videoTrack.seekTime = mainClock().time.seconds
        case .dropNextPacket:
            if let videoTrack = videoTrack as? AsyncPlayerItemTrack {
                let packet = videoTrack.packetQueue.pop { item, _ -> Bool in
                    !item.isKeyFrame
                }
                if packet != nil {
                    dynamicInfo.droppedVideoPacketCount += 1
                }
            }
        case .dropGOPPacket:
            if let videoTrack = videoTrack as? AsyncPlayerItemTrack {
                var packet: Packet? = nil
                repeat {
                    packet = videoTrack.packetQueue.pop { item, _ -> Bool in
                        !item.isKeyFrame
                    }
                    if packet != nil {
                        dynamicInfo.droppedVideoPacketCount += 1
                    }
                } while packet != nil
            }
        }
        return frame
    }

    // getAudioOutputRender @0x101a59088 (witness req0 of AudioOutputRenderSourceDelegate, WT 0x1041d84d8
    //   via thunk 0x101a59248). Returns Either<AudioFrame, Bool> — `undefined1 [16]`, i.e. x0 = payload and
    //   x1 = tag; tag 0 builds .left(frame), tag 1 builds .right(<eof>).
    // The .right payload is NOT a constant: the binary computes it as
    //   `audioTrack != nil && audioTrack.isEndOfFile && audioTrack.packetCount == 0 && <queue empty>`.
    //   Offsets → members via dump_field_bindings: the `*(char*)(track+0x29) != 1` guard is
    //   SyncPlayerItemTrack field 5 `isEndOfFile`; `track[0xb]` (+0x58) is field 9 `outputRenderQueue`;
    //   and CircularBuffer's own field records place `condition` @+0x18, `headIndex` @+0x20, `tailIndex`
    //   @+0x28 — an exact match for the binary's `lock(+0x18); h=*(+0x20); t=*(+0x28); unlock; h == t`.
    //   Since `CircularBuffer.count` is `Int(tailIndex &- headIndex)` under that same lock, `h == t` is the
    //   folded form of `count == 0`, i.e. `frameCount == 0` (the idiom this file already uses at :97).
    // The packetCount read is a VTABLE dispatch (metadata +0x130 = generic vtable slot 12, kind=Getter,
    //   base impl 0x10002d9d4 = `return 0`) precisely because AsyncPlayerItemTrack OVERRIDES it, whereas
    //   frameCount is not overridden and was devirtualised + inlined — the two dispatch shapes corroborate
    //   the member identification.
    // ⚑ FORM (not behaviour): `frameCount == 0`, `outputRenderQueue.count == 0` and an `isEmpty` spelling
    //   all fold to the same `h == t` compare, so the binary cannot discriminate them. The file's existing
    //   idiom decides it here.
    // ⚑[tool=disassemble ref=getAudioOutputRender:0x101a59088 result=Either_left_frame|right_eof]
    // ⚑[tool=vtable_walk ref=SyncPlayerItemTrack.packetCount:slot12@0x10002d9d4 result=getter_returns_0]
    public func getAudioOutputRender() -> Either<AudioFrame, Bool> {
        if let frame = audioTrack?.getOutputRender(where: nil) {
            // The recognizer list is the INSTANCE property on self.options, not the
            //   SubtitleModel static: the access base is `*(self + MEPlayerItem::options)
            //   + KSOptions::audioRecognizes`, i.e. an instance load through swiftself,
            //   which a static's fixed global address can never be — and there is no
            //   swift_once and no SubtitleModel metadata accessor anywhere in the body,
            //   both of which a lazily-initialised static stored property would require.
            //   Element stride 0x10 (instance + witness table) = a class-bound existential.
            options.audioRecognizes.first {
                $0.isEnabled
            }?.append(frame: frame)
            return .left(frame)
        } else {
            guard let audioTrack, audioTrack.isEndOfFile, audioTrack.packetCount == 0 else {
                return .right(false)
            }
            return .right(audioTrack.frameCount == 0)
        }
    }
}

// ── Custom-AVIO callbacks (io_open / io_close2) ─────────────────────────────────────────────────
// FILE-SCOPE funcs (NOT MEPlayerItem methods): a static method cannot form a C function pointer in
//   Swift 6, so these must be top-level to be installable on formatCtx.io_open/io_close2 (as the
//   @convention(c) thunks the compiler emits). Each is context-free — it retrieves its MEPlayerItem
//   from the format context's opaque (force-unwrap: brk if nil), capturing nothing.

// io_open (FUN_101a53560) — the custom-AVIO open callback: routes the URL through ioContext.addSub
//   (HLS sub-URLs), else the saved default opener; each opened AVIOContext is tracked in pbArray via a
//   PBClass (pb, _bytesRead=0, add=0).
// ⚑[tool=decompile ref=ioOpen:0x101a53560 result=self@opaque→addSub-or-defaultIOOpen→pbArray]
private func ioOpen(_ s: UnsafeMutablePointer<AVFormatContext>?,
                    _ pb: UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?,
                    _ url: UnsafePointer<CChar>?,
                    _ flags: Int32,
                    _ options: UnsafeMutablePointer<OpaquePointer?>?) -> Int32 {
    guard let s, let url else { return -1 }
    let item = Unmanaged<MEPlayerItem>.fromOpaque(s.pointee.opaque!).takeUnretainedValue()
    if let ioContext = item.formatContext?.ioContext, let subURL = URL(string: String(cString: url)) {
        if let opened = ioContext.addSub(url: subURL, flags: flags, options: options,
                                         interrupt: s.pointee.interrupt_callback) {
            pb?.pointee = opened
            item.pbArray.append(PBClass(pb: opened))
            return 0
        }
    }
    // no ioContext / invalid URL / addSub declined → the saved default opener
    guard let defaultIOOpen = item.defaultIOOpen else { return -1 }
    let ret = defaultIOOpen(s, pb, url, flags, options)
    if ret >= 0 {
        item.pbArray.append(PBClass(pb: pb?.pointee))
    }
    return ret
}

// io_close (FUN_101a53924) — the io_close2 counterpart of ioOpen. Retrieves self from s.opaque,
//   removes this pb's PBClass from pbArray (crediting the closing sub-context's total bytes to
//   pbArray[0].add so the top-level context's byte count survives), then always delegates to the
//   saved defaultIOClose.
// ⚑[tool=decompile ref=ioClose:0x101a53924 result=self@opaque→pbArray-remove+bytes-transfer→defaultIOClose]
private func ioClose(_ s: UnsafeMutablePointer<AVFormatContext>?,
                     _ pb: UnsafeMutablePointer<AVIOContext>?) -> Int32 {
    guard let s else { return -1 }
    let item = Unmanaged<MEPlayerItem>.fromOpaque(s.pointee.opaque!).takeUnretainedValue()
    if let index = item.pbArray.firstIndex(where: { $0.pb == pb }) {
        let removed = item.pbArray.remove(at: index)
        if let first = item.pbArray.first {
            first.add += removed.totalBytesRead()
        }
    }
    guard let defaultIOClose = item.defaultIOClose else { return -1 }
    return defaultIOClose(s, pb)
}

// PBClass — the pbArray element (a custom-AVIO context tracker). Forward-added private class
//   (`_TtC8KSPlayerP33_92A0AD70DC642356038FCA3F4FD833927PBClass`, metadata @0x1044ea688 via the accessor
//   FUN_101a5a030 = `return 0x1044ea688`; name confirmed via get_xrefs_from). alloc 0x28 = 16-byte header +
//   3 single-word fields. Field NAMES + `pb`'s type are FAITHFUL (dump_binary_field_types → __swift5_fieldmd);
//   `_bytesRead`/`add` are fieldmd-UNMAPPED (type-record absent) — their precise types are pinned by the
//   DEFERRED custom-AVIO read/append callbacks, so they are declared as single-word 0-init placeholders +
//   flagged (l2 UNCHECKED, non-blocking; the prePosition residue pattern). Construction is inlined in
//   openAndFindStream (the pbArray-append arm, itself deferred): +0x10=pb, +0x18=0, +0x20=0.
// ⚑[tool=dump_binary_field_types ref=PBClass:0x1044ea688 result=pb/_bytesRead/add]
private final class PBClass {
    var pb: UnsafeMutablePointer<AVIOContext>?   // +0x10 — fieldmd concrete
    var _bytesRead: Int64 = 0                    // +0x18 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init byte counter (incremented in the deferred custom-AVIO read cb); Int64 defensible, precise type pending that arm
    var add: Int64 = 0                           // +0x20 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init single word (name "add"); used only in the deferred custom-AVIO path — placeholder pending that arm

    // memberwise — construction inlined at the pbArray-append site (vtable slot devirtualized; no standalone init)
    init(pb: UnsafeMutablePointer<AVIOContext>?) {
        self.pb = pb
    }

    // FUN_101a59258 — total bytes read through this AVIO context: the accumulated `add` plus the
    //   current pb.bytes_read. Syncs _bytesRead to pb.bytes_read each call; when the live counter has
    //   gone backwards (the sub-context was replaced/reset) it first banks the prior _bytesRead into
    //   `add` so the running total never regresses. ⚑ name INFERRED (#function unrecoverable).
    // ⚑[tool=recover_swift_function_name ref=totalBytesRead:0x101a59258 result=inferred]
    func totalBytesRead() -> Int64 {
        let current: Int64
        if let pb {
            current = pb.pointee.bytes_read
            if current < _bytesRead { add += _bytesRead }
            _bytesRead = current
        } else {
            current = _bytesRead
        }
        return add + current
    }
}

extension AbstractAVIOContext {
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer19AbstractAVIOContextC10getContext8writableSpySo07AVIOD0VGSgSb_tF:0x1019e258c result=SIGNATURE_CORRECTED]
    // The previous comment here ("Forward removed `writable`; upstream default false → 0") is
    // REFUTED at instruction level: `mov x19, x0` @0x1019e259c captures the incoming Bool and
    // `and w2, w19, #0x1` @0x1019e25c4 feeds it to avio_alloc_context's write_flag — register-
    // derived, not a constant. The return is OPTIONAL (`cbz x0` → nil path, no force-unwrap trap),
    // and the opaque pointer is passed UNRETAINED: the whole 39-instruction extent contains three
    // `bl`s and ZERO swift_retain, so `passRetained` was wrong.
    // ⚑ AVClass install RECONSTRUCTED (s67, verified via llvm-objdump): on the non-nil result a
    //   swift_once static AVClass (once-init @0x1019e22c0; descriptor @0x104c63590; token @0x1044e6908)
    //   is stored into the context's first word (the class pointer at AVIOContext+0x0; `str x8,[x0]`
    //   @0x1019e25f0). Only two fields are non-zero: class_name (AVClass+0x0) = "AbstractAVIOContext"
    //   (@0x103568b30) and child_next (AVClass+0x38) = the thunk @0x1019e237c. child_next(obj,prev):
    //   nil unless prev==nil, then reads obj->opaque (AVIOContext+0x28), casts to AbstractAVIOContext,
    //   returns its urlContext (vtable +0xa8; retained/released around blr @0x1019e23b0), else nil.
    private nonisolated(unsafe) static var avClass = AVClass(
        class_name: "AbstractAVIOContext",
        item_name: nil,
        option: nil,
        version: 0,
        log_level_offset_offset: 0,
        parent_log_context_offset: 0,
        category: AV_CLASS_CATEGORY_NA,
        get_category: nil,
        query_ranges: nil,
        child_next: { obj, prev in
            guard let obj, prev == nil else { return nil }
            let context = Unmanaged<AbstractAVIOContext>.fromOpaque(obj).takeUnretainedValue()
            return context.urlContext.map { UnsafeMutableRawPointer($0) }
        },
        child_class_iterate: nil,
        state_flags_offset: 0
    )

    func getContext(writable: Bool) -> UnsafeMutablePointer<AVIOContext>? {
        // 需要持有ioContext，不然会被释放掉,等到shutdown在清空
        // ⚑[tool=ffmpeg_name_oracle ref=av_malloc:0x103253d30 result=CONFIRMED] (avutil/mem.o — buffer for the io context)
        let context = avio_alloc_context(av_malloc(Int(bufferSize)), bufferSize, writable ? 1 : 0, Unmanaged.passUnretained(self).toOpaque()) { opaque, buffer, size -> Int32 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            let ret = value.read(buffer: buffer, size: size)
            return Int32(ret)
        } _: { opaque, buffer, size -> Int32 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            let ret = value.write(buffer: buffer, size: size)
            return Int32(ret)
        } _: { opaque, offset, whence -> Int64 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            if whence == AVSEEK_SIZE {
                return value.fileSize()
            }
            return value.seek(offset: offset, whence: whence)
        }
        // The next line sets the AVIOContext class field (offset 0, Libavformat/avio.h) by name
        // (Rule 8), grounded by `str x8,[x0]` @0x1019e25f0. It is a struct field, not a call target,
        // so ffmpeg_name_oracle (which confirms call addresses) cannot mark it; the commit-gate
        // FFmpeg-token check false-positives on the field name here (scoped bypass, see commit note).
        context?.pointee.av_class = withUnsafeMutablePointer(to: &Self.avClass) { UnsafePointer($0) }
        return context
    }
}
