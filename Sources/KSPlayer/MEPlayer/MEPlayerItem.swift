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
    private var formatContext: FormatContext?                        // 7
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
    private var pbArray = [PBClass]()                             // 29
    private var interrupt = false                                // 30
    private var prePosition: Int64 = 0                           // 31 ⚑ UNRESOLVED: single-word 0-init; Int64|Int|Double pending assignment site
    private var defaultIOOpen: (() -> Void)?                     // 32 ⚑ UNRESOLVED placeholder: AVIO io_open closure (openAndFindStream thunk FUN_101a5a0c4)
    private var defaultIOClose: (() -> Void)?                    // 33 ⚑ UNRESOLVED placeholder: AVIO io_close closure (thunk FUN_101a5a0bc)
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

        // ⚑ UNRESOLVED: custom-AVIO install — Forward saves formatCtx.pb's default io_open/io_close into
        //   defaultIOOpen/defaultIOClose (boxed) and swaps in its own thunks (formatCtx.pb.opaque = self).
        //   ⚑[tool=decompile ref=ioOpenThunk:0x101a53560 result=deferred-custom-AVIO]
        // ⚑ UNRESOLVED: pbArray append — allocs a PBClass and appends it to self.pbArray (field 29), then on a
        //   successful dynamic-cast writes KSOptions seekUsePacketCache=false + a formatContextOptions entry.
        //   ⚑[tool=decompile ref=pbClassAlloc:0x101a5a030 result=deferred-PBClass-body]

        options.formatName = formatContext.formatName        // String @+0x48 (DERIVED from iformat.name)
        self.fileSize = formatContext.fileSize               // +0x30
        self.duration = formatContext.duration               // +0x28
        // ⚑ UNRESOLVED: KSOptions rate×duration — `if options[+0x38] > 0 { options[+0x30] = options[+0x38] ×
        //   formatContext.duration }` (two KSOptions Double fields; offset→name mapping deferred).
        self.chapters = formatContext.chapters               // FormatContext.chapters getter (DONE, commit-2a)

        //   ⚑[tool=decompile ref=createCodec:0x101a53c44 result=stub-call]
        createCodec(formatCtx: formatCtx)                    // track-set builder; body deferred (commit-1 stub)
    }

    func startRecord(url: URL) {
        // ⚑ UNRESOLVED (commit-1 stub): base body used the removed outputFormatCtx/streamMapping/outputPacket
        //   + formatCtx fields. Forward routes recording through `remuxer: Remuxer?` (field 8). Deferred to
        //   the remuxer migration commit.
    }

    private func createCodec(formatCtx: UnsafeMutablePointer<AVFormatContext>) {
        // ⚑ UNRESOLVED (commit-1 stub): base body populated the removed `assetTracks` field and used the
        //   removed `seekByBytes`. Forward builds allPlayerItemTracks/videoAudioTracks/videoTrack/audioTrack/
        //   subtitleTrack from the streams. Deferred to the createCodec migration commit.
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
