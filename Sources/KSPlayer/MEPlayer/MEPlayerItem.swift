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
    //   (FUN_101a4bae0) + name_type_at_addr; residual generic/closure exactness flagged
    //   // ⚑ UNRESOLVED (field-record None ⟹ l2 UNCHECKED, non-blocking). The 17 base fields are
    //   removed; every method that used them is stubbed // ⚑ UNRESOLVED pending its Forward-body commit.
    private var io: Either<URL, AbstractAVIOContext>                 // 1 ⚑[tool=name_type_at_addr ref=io:0x103566d40 result=Either<_,AbstractAVIOContext>] first param URL (sibling KSAVPlayer.io)
    private let options: KSOptions                                   // 2
    private var isPreload = false                                    // 3
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
    private var playbackSnapshotRecordInterval = 0.5               // 18
    private var lastPlaybackSnapshotRecordTime: Double?            // 19
    private var timeIndexRecordInterval = 1.0                      // 20
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
    private var preloadClock = ContinuousClock()            // 40 ⚑ init calls Swift.ContinuousClock.init(); ContinuousClock vs .Instant pending
    private var lastPacketMediaType: AVFoundation.AVMediaType = .video // 41 init AVMediaTypeVideo (AVFoundation constant; codebase disambiguates from FFmpeg AVMediaType)
    weak var delegate: MEPlayerDelegate?                    // 42

    public var currentPlaybackTime: TimeInterval {
        state == .seeking ? seekTime : mainClock().time.seconds // ⚑ UNRESOLVED: base subtracted removed `startTime`
    }

    // ⚑ Forward moved the per-stream FFmpegAssetTracks into FormatContext (FormatContext.swift:59 `assetTracks`
    //   @+0x40); MEPlayerItem's stored `assetTracks` field is removed. This computed bridge reads the migrated
    //   source so the external reader KSMEPlayer.tracks(mediaType:) stays green (Forward may instead read
    //   formatContext.assetTracks directly — resolved when KSMEPlayer.tracks migrates).
    var assetTracks: [FFmpegAssetTrack] { formatContext?.assetTracks ?? [] }

    lazy var dynamicInfo = DynamicInfo {
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

    func startRecord(url: URL) {
        // ⚑ UNRESOLVED (commit-1 stub): base body used the removed outputFormatCtx/streamMapping/outputPacket
        //   + formatCtx fields. Forward routes recording through `remuxer: Remuxer?` (field 8). Deferred to
        //   the remuxer migration commit.
    }

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
        //   md+0x768 is an unbound pattern value 0x105395200 with no function). Deferred — the P43 existence-check
        //   RAN (source ✗, base ✗, static metadata ✗) and failed to name it.
        //   ⚑[tool=get_function_by_address ref=KSOptions.vtable0x768:0x105395200 result=FAILED-SEARCH]
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
        //   CheckedContinuation` + `ioWaiterLock: NSLock` for suspension. Deferred to the read-loop migration commit.
    }

    private func reading() -> Int32 {
        // ⚑ UNRESOLVED (commit-1 stub): base body used removed formatCtx/outputFormatCtx/streamMapping/
        //   outputPacket/assetTracks/startTime/error (the demuxer read loop → per-track putPacket + remux
        //   write). Forward reads via formatContext + routes recording through `remuxer`. Deferred to the
        //   read-loop migration commit.
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
            (self.dynamicInfo.audioVideoSyncDiff, type) = self.options.videoClockSync(main: self.mainClock(), nextVideoTime: frame.seconds, fps: Double(frame.fps), frameCount: count)
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

    public func getAudioOutputRender() -> AudioFrame? {
        if let frame = audioTrack?.getOutputRender(where: nil) {
            SubtitleModel.audioRecognizes.first {
                $0.isEnabled
            }?.append(frame: frame)
            return frame
        } else {
            return nil
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
    func getContext() -> UnsafeMutablePointer<AVIOContext> {
        // 需要持有ioContext，不然会被释放掉,等到shutdown在清空
        // write_flag 0 — Forward removed `writable`; upstream default false → 0; getContext binary unresolved (UNRESOLVED-if-Forward-differs).
        avio_alloc_context(av_malloc(Int(bufferSize)), bufferSize, 0, Unmanaged.passRetained(self).toOpaque()) { opaque, buffer, size -> Int32 in
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
    }
}
