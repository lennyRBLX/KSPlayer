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
#if canImport(CryptoKit)
import CryptoKit
#endif

public final class MEPlayerItem: Sendable {
    private let url: URL
    private let options: KSOptions
    private let operationQueue = OperationQueue()
    private let condition = NSCondition()
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>?
    private var outputFormatCtx: UnsafeMutablePointer<AVFormatContext>?
    private var outputPacket: UnsafeMutablePointer<AVPacket>?
    private var streamMapping = [Int: Int]()

    // MARK: -- RE-derived custom I/O machinery (Forward v1.3.15)
    //
    // The binary replaces the FFmpeg-default `formatCtx->io_open` and
    // `io_close2` callbacks at AVFormatContext element 0x38 (= byte +0x1C0)
    // and element 0x39 (= byte +0x1C8) with its own dispatch, saving the
    // original 16-byte (function pointer + retained context) closure pairs into
    // `defaultIOOpen` / `defaultIOClose`. Verified at openAndFindStream
    // disassembly 0x10142fc0c..0x10142fd2c.

    /// RE: Saved original FFmpeg `io_open` closure. Field anchored by Swift
    /// field-offset symbol `_TtC8KSPlayer12MEPlayerItem::defaultIOOpen`.
    /// Reset to `nil` whenever `formatCtx` is (re)allocated.
    private var defaultIOOpen: IOOpenCallback?

    /// RE: Saved original FFmpeg `io_close2` closure. Field anchored by
    /// `_TtC8KSPlayer12MEPlayerItem::defaultIOClose`.
    private var defaultIOClose: IOCloseCallback?

    /// RE: Tracks protocol buffer objects opened through the custom-IO path so
    /// they can be released on teardown. Field anchored by Swift field-offset
    /// symbol `_TtC8KSPlayer12MEPlayerItem::pbArray`; reset to
    /// `_swiftEmptyArrayStorage` at the start of every openAndFindStream call
    /// (binary @ 0x10142fbd4-0x10142fbec).
    ///
    /// The binary types this as a Swift `Array` of `PBClass` instances. Here
    /// we record each opened slot as a `PBSlot` struct so we can keep the
    /// `AbstractAVIOContext` Swift object alive (the AVIOContext's `opaque`
    /// holds an `Unmanaged.passRetained(...)` to it) AND the matching
    /// `AVIOContext *` for matching during close.
    private var pbArray: [PBSlot] = []

    /// Each entry in `pbArray`: one `AbstractAVIOContext`-backed open.
    fileprivate struct PBSlot {
        let context: AbstractAVIOContext
        let pb: UnsafeMutablePointer<AVIOContext>
    }

    /// RE: Suspension continuation for the read loop when the source pauses
    /// without tearing down the I/O connection. The binary's read loop, on
    /// `state == .paused (5)`, calls `avio_flush(formatCtx->pb)` and stores a
    /// `CheckedContinuation` in the `ioWaiter` slot via
    /// `swift_continuation_await`. Resume is triggered by the external
    /// `resume()` path, which signals the waiter to let the task continue.
    /// This avoids tearing down the TCP / HTTP socket on pause.
    private var ioWaiter: CheckedContinuation<Void, Never>?

    /// Type for the saved FFmpeg `io_open` C-function. FFmpeg signature:
    /// `int (*io_open)(AVFormatContext *s, AVIOContext **pb, const char *url,
    ///                 int flags, AVDictionary **options)`.
    typealias IOOpenCallback = @convention(c) (
        UnsafeMutablePointer<AVFormatContext>?,
        UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?,
        UnsafePointer<CChar>?,
        Int32,
        UnsafeMutablePointer<OpaquePointer?>?
    ) -> Int32

    /// Type for the saved FFmpeg `io_close2` C-function. FFmpeg signature:
    /// `int (*io_close2)(AVFormatContext *s, AVIOContext *pb)`.
    typealias IOCloseCallback = @convention(c) (
        UnsafeMutablePointer<AVFormatContext>?,
        UnsafeMutablePointer<AVIOContext>?
    ) -> Int32
    /// Remuxer for TranscodeContext-based recording/transcoding pipeline.
    /// Activated when options.outputURL is set and options.outputMediaType specifies
    /// which stream types to include. Uses TranscodeContext hierarchy for per-stream
    /// processing (copy, BSF, or full transcode).
    private var remuxer: Remuxer?
    private var openOperation: BlockOperation?
    private var readOperation: BlockOperation?
    private var closeOperation: BlockOperation?
    private var seekingCompletionHandler: ((Bool) -> Void)?
    // 没有音频数据可以渲染
    private var isAudioStalled = true
    private var audioClock = KSClock()
    private var videoClock = KSClock()
    private var isFirst = true
    private var isSeek = false
    private var allPlayerItemTracks = [PlayerItemTrackProtocol]()
    private var maxFrameDuration = 10.0
    private var videoAudioTracks = [CapacityProtocol]()
    private var videoTrack: SyncPlayerItemTrack<VideoVTBFrame>?
    private var audioTrack: SyncPlayerItemTrack<AudioFrame>?
    private(set) var assetTracks = [FFmpegAssetTrack]()
    private var videoAdaptation: VideoAdaptationState?
    private var videoDisplayCount = UInt8(0)
    private var seekByBytes = false
    private var lastVideoDisplayTime = CACurrentMediaTime()
    public private(set) var chapters: [Chapter] = []
    public var currentPlaybackTime: TimeInterval {
        state == .seeking ? seekTime : (mainClock().time - startTime).seconds
    }

    private var seekTime = TimeInterval(0)
    private var startTime = CMTime.zero
    public private(set) var duration: TimeInterval = 0
    public private(set) var fileSize: Double = 0
    public private(set) var naturalSize = CGSize.zero
    private var error: NSError? {
        didSet {
            if error != nil {
                state = .failed
            }
        }
    }

    private var state = MESourceState.idle {
        didSet {
            switch state {
            case .opened:
                delegate?.sourceDidOpened()
            case .reading:
                timer.fireDate = Date.distantPast
            case .closed:
                timer.invalidate()
            case .failed:
                delegate?.sourceDidFailed(error: error)
                timer.fireDate = Date.distantFuture
            case .idle, .opening, .seeking, .paused, .finished:
                break
            }
        }
    }

    private lazy var timer: Timer = .scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        self?.codecDidChangeCapacity()
    }

    lazy var dynamicInfo = DynamicInfo { [weak self] in
        // metadata可能会实时变化。所以把它放在DynamicInfo里面
        toDictionary(self?.formatCtx?.pointee.metadata)
    } bytesRead: { [weak self] in
        self?.formatCtx?.pointee.pb?.pointee.bytes_read ?? 0
    } audioBitrate: { [weak self] in
        Int(8 * (self?.audioTrack?.bitrate ?? 0))
    } videoBitrate: { [weak self] in
        Int(8 * (self?.videoTrack?.bitrate ?? 0))
    }

    private static var onceInitial: Void = {
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

    weak var delegate: MEPlayerDelegate?
    public init(url: URL, options: KSOptions) {
        self.url = url
        self.options = options
        timer.fireDate = Date.distantFuture
        operationQueue.name = "KSPlayer_" + String(describing: self).components(separatedBy: ".").last!
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive
        _ = MEPlayerItem.onceInitial
    }

    func select(track: some MediaPlayerTrack) -> Bool {
        if track.isEnabled {
            return false
        }
        assetTracks.filter { $0.mediaType == track.mediaType }.forEach {
            $0.isEnabled = track === $0
        }
        guard let assetTrack = track as? FFmpegAssetTrack else {
            return false
        }
        if assetTrack.mediaType == .video {
            findBestAudio(videoTrack: assetTrack)
        } else if assetTrack.mediaType == .subtitle {
            if assetTrack.isImageSubtitle {
                if !options.isSeekImageSubtitle {
                    return false
                }
            } else {
                return false
            }
        }
        seek(time: currentPlaybackTime) { _ in
        }
        return true
    }
}

// MARK: private functions

extension MEPlayerItem {
    private func openThread() {
        // RE: Forward v1.3.15 -- openAndFindStream resets `pbArray` to the
        // empty array at the top of the call so subsequent custom-IO opens can
        // collect new PBClass entries for cleanup. Verified at disassembly
        // 0x10142fbd4-0x10142fbec.
        pbArray.removeAll(keepingCapacity: true)
        avformat_close_input(&self.formatCtx)
        formatCtx = avformat_alloc_context()
        guard let formatCtx else {
            error = NSError(errorCode: .formatCreate)
            return
        }
        // RE: Forward v1.3.15 -- save the original FFmpeg `io_open` /
        // `io_close2` closures into `defaultIOOpen` / `defaultIOClose`, then
        // install our custom dispatch in their place. Verified at
        // openAndFindStream disassembly 0x10142fc0c-0x10142fd2c. Both slots are
        // 16-byte closure pairs (function ptr + retained context object) on the
        // AVFormatContext at element 0x38 / element 0x39 (= byte +0x1C0 /
        // +0x1C8 in the FFmpeg version compiled into the binary).
        defaultIOOpen = formatCtx.pointee.io_open
        defaultIOClose = formatCtx.pointee.io_close2
        formatCtx.pointee.io_open = MEPlayerItem._customIOOpenC
        formatCtx.pointee.io_close2 = MEPlayerItem._customIOCloseC
        // Bind the AVFormatContext's `opaque` to `self` so the C-convention
        // trampolines can resolve back to this MEPlayerItem instance.
        formatCtx.pointee.opaque = Unmanaged.passUnretained(self).toOpaque()
        var interruptCB = AVIOInterruptCB()
        interruptCB.opaque = Unmanaged.passUnretained(self).toOpaque()
        // RE: Forward v1.3.15 -- `MEPlayerItem_interruptCallback` @ 0x1014367a0.
        // Verified decompile: returns 1 if the `interrupt` flag is set OR if
        // `state - 7 < 2` (i.e. state ∈ {7, 8} = .closed, .failed). The binary
        // does NOT trigger on .finished -- only the terminal teardown states.
        interruptCB.callback = { ctx -> Int32 in
            guard let ctx else {
                return 0
            }
            let formatContext = Unmanaged<MEPlayerItem>.fromOpaque(ctx).takeUnretainedValue()
            switch formatContext.state {
            case .closed, .failed:
                return 1
            default:
                return 0
            }
        }
        formatCtx.pointee.interrupt_callback = interruptCB
        // avformat_close_input这个函数会调用io_close2。但是自定义协议是不会调用io_close2这个函数
//        formatCtx.pointee.io_close2 = { _, _ -> Int32 in
//            0
//        }
        setHttpProxy()
        var avOptions = options.formatContextOptions.avOptions
        if let pb = options.process(url: url) {
            // 如果要自定义协议的话，那就用avio_alloc_context，对formatCtx.pointee.pb赋值
            formatCtx.pointee.pb = pb.getContext()
        }
        let urlString: String
        if url.isFileURL {
            urlString = url.path
        } else {
            urlString = url.absoluteString
        }
        var result = avformat_open_input(&self.formatCtx, urlString, nil, &avOptions)
        av_dict_free(&avOptions)
        if result == AVError.eof.code {
            state = .finished
            delegate?.sourceDidFinished()
            return
        }
        guard result == 0 else {
            error = .init(errorCode: .formatOpenInput, avErrorCode: result)
            avformat_close_input(&self.formatCtx)
            return
        }
        options.openTime = CACurrentMediaTime()
        // RE: Log output format name on open URL (FormatContext_getOutputFormatName)
        let openFormatName = FormatContext.getOutputFormatName(for: url)
        KSLog("[MEPlayerItem] openURL format: \(openFormatName)")
        formatCtx.pointee.flags |= AVFMT_FLAG_GENPTS
        if options.nobuffer {
            formatCtx.pointee.flags |= AVFMT_FLAG_NOBUFFER
        }
        if let probesize = options.probesize {
            formatCtx.pointee.probesize = probesize
        }
        if let maxAnalyzeDuration = options.maxAnalyzeDuration {
            formatCtx.pointee.max_analyze_duration = maxAnalyzeDuration
        }
        // RE: Forward v1.3.15 large-file optimization @ 0x101430310 (inside
        // `FUN_10142f680` = `MEPlayerItem_openAndFindStream`).
        //
        // The raw constant emitted by the compiler is `0xBA43B7401` =
        // 50,000,000,001 (one above the round number). The compare is
        // `CMP x20, x8 / B.LT skip`, so the effective trigger is
        // `fileSize > 50,000,000,000` for any integer-valued size -- which is
        // what we test below.
        //
        // The store target in the binary is `formatCtx[+0x1D0]`; the FFmpeg
        // header field at that offset is `max_ts_probe` in this build. The
        // "max_ts_probe" strings in the binary (@ 0x1034dd8bc, @ 0x103742275)
        // are data-only with no code xrefs, so the field name is inferred
        // from the FFmpeg AVFormatContext layout, not from a string anchor.
        //
        // Divisor is 235 (`0xEB`), emitted as a magic-multiply by
        // `0x16E068942737_8EB5` + `UMULH` + `LSR #7`; 235 is close to the
        // 188-byte MPEG-TS packet size.
        let pbSize = avio_size(formatCtx.pointee.pb)
        if pbSize > 50_000_000_000 {
            formatCtx.pointee.max_ts_probe = Int32(clamping: pbSize / 235)
        }
        result = avformat_find_stream_info(formatCtx, nil)
        guard result == 0 else {
            error = .init(errorCode: .formatFindStreamInfo, avErrorCode: result)
            avformat_close_input(&self.formatCtx)
            return
        }
        // FIXME: hack, ffplay maybe should not use avio_feof() to test for the end
        formatCtx.pointee.pb?.pointee.eof_reached = 0
        // RE: Forward v1.3.15 -- step 12 of openAndFindStream computes a per-
        // stream fonts directory at `NSTemporaryDirectory()/fontsDir/<MD5>`
        // (MD5 of the stream URL via CryptoKit `Insecure.MD5`) and writes it
        // into `KSOptions.fontsDir`. Only set this when the caller has not
        // supplied a directory explicitly.
        if options.fontsDir == nil {
            options.fontsDir = Self.deriveFontsDir(for: url)
        }
        let flags = formatCtx.pointee.iformat.pointee.flags
        maxFrameDuration = flags & AVFMT_TS_DISCONT == AVFMT_TS_DISCONT ? 10.0 : 3600.0
        options.findTime = CACurrentMediaTime()
        options.formatName = String(cString: formatCtx.pointee.iformat.pointee.name)
        seekByBytes = (flags & AVFMT_NO_BYTE_SEEK == 0) && (flags & AVFMT_TS_DISCONT != 0) && options.formatName != "ogg"
        if formatCtx.pointee.start_time != Int64.min {
            startTime = CMTime(value: formatCtx.pointee.start_time, timescale: AV_TIME_BASE)
            videoClock.time = startTime
            audioClock.time = startTime
        }
        duration = TimeInterval(max(formatCtx.pointee.duration, 0) / Int64(AV_TIME_BASE))
        fileSize = Double(formatCtx.pointee.bit_rate) * duration / 8
        createCodec(formatCtx: formatCtx)
        if formatCtx.pointee.nb_chapters > 0 {
            chapters.removeAll()
            for i in 0 ..< formatCtx.pointee.nb_chapters {
                if let chapter = formatCtx.pointee.chapters[Int(i)]?.pointee {
                    let timeBase = Timebase(chapter.time_base)
                    let start = timeBase.cmtime(for: chapter.start).seconds
                    let end = timeBase.cmtime(for: chapter.end).seconds
                    let metadata = toDictionary(chapter.metadata)
                    let title = metadata["title"] ?? ""
                    chapters.append(Chapter(start: start, end: end, title: title))
                }
            }
        }

        if let outputURL = options.outputURL {
            startRecord(url: outputURL)
            // When outputURL is set, also create a Remuxer with the TranscodeContext
            // pipeline for proper stream processing (BSF, transcode, etc.)
            createRemuxer(outputURL: outputURL)
        }
        if videoTrack == nil, audioTrack == nil {
            state = .failed
        } else {
            state = .opened
            read()
        }
    }

    func startRecord(url: URL) {
        stopRecord()
        // RE: Log output format name on record/open URL (FormatContext_getOutputFormatName)
        let outputFormatName = FormatContext.getOutputFormatName(for: url)
        KSLog("[MEPlayerItem] startRecord format: \(outputFormatName)")
        let filename = url.isFileURL ? url.path : url.absoluteString
        var ret = avformat_alloc_output_context2(&outputFormatCtx, nil, nil, filename)
        guard let outputFormatCtx, let formatCtx else {
            KSLog(NSError(errorCode: .formatOutputCreate, avErrorCode: ret))
            return
        }
        var index = 0
        var audioIndex: Int?
        var videoIndex: Int?
        let formatName = outputFormatCtx.pointee.oformat.pointee.name.flatMap { String(cString: $0) }
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            if let inputStream = formatCtx.pointee.streams[i] {
                let codecType = inputStream.pointee.codecpar.pointee.codec_type
                if [AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO, AVMEDIA_TYPE_SUBTITLE].contains(codecType) {
                    if codecType == AVMEDIA_TYPE_AUDIO {
                        if let audioIndex {
                            streamMapping[i] = audioIndex
                            continue
                        } else {
                            audioIndex = index
                        }
                    } else if codecType == AVMEDIA_TYPE_VIDEO {
                        if let videoIndex {
                            streamMapping[i] = videoIndex
                            continue
                        } else {
                            videoIndex = index
                        }
                    }
                    if let outStream = avformat_new_stream(outputFormatCtx, nil) {
                        streamMapping[i] = index
                        index += 1
                        avcodec_parameters_copy(outStream.pointee.codecpar, inputStream.pointee.codecpar)
                        if codecType == AVMEDIA_TYPE_SUBTITLE, formatName == "mp4" || formatName == "mov" {
                            outStream.pointee.codecpar.pointee.codec_id = AV_CODEC_ID_MOV_TEXT
                        }
                        // DV-aware codec_tag resolution (binary ref: FUN_1013fd1dc)
                        // Determines correct tag from DOVIDecoderConfigurationRecord
                        // instead of blindly overwriting with generic HEVC.
                        if codecType == AVMEDIA_TYPE_VIDEO {
                            let doviRecord = assetTracks.first(where: {
                                $0.mediaType == .video && $0.dovi != nil
                            })?.dovi
                            applyResolvedCodecTag(
                                to: outStream.pointee.codecpar,
                                codecID: inputStream.pointee.codecpar.pointee.codec_id,
                                dovi: doviRecord
                            )
                        } else {
                            outStream.pointee.codecpar.pointee.codec_tag = 0
                        }
                    }
                }
            }
        }
        avio_open(&(outputFormatCtx.pointee.pb), filename, AVIO_FLAG_WRITE)
        ret = avformat_write_header(outputFormatCtx, nil)
        guard ret >= 0 else {
            KSLog(NSError(errorCode: .formatWriteHeader, avErrorCode: ret))
            avformat_close_input(&self.outputFormatCtx)
            return
        }
        outputPacket = av_packet_alloc()
    }

    private func createCodec(formatCtx: UnsafeMutablePointer<AVFormatContext>) {
        allPlayerItemTracks.removeAll()
        assetTracks.removeAll()
        videoAdaptation = nil
        videoTrack = nil
        audioTrack = nil
        videoAudioTracks.removeAll()
        assetTracks = (0 ..< Int(formatCtx.pointee.nb_streams)).compactMap { i in
            if let coreStream = formatCtx.pointee.streams[i] {
                coreStream.pointee.discard = AVDISCARD_ALL
                if let assetTrack = FFmpegAssetTrack(stream: coreStream) {
                    if assetTrack.mediaType == .subtitle {
                        let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 255, options: options)
                        assetTrack.subtitle = subtitle
                        allPlayerItemTracks.append(subtitle)
                    }
                    assetTrack.seekByBytes = seekByBytes
                    return assetTrack
                }
            }
            return nil
        }
        var videoIndex: Int32 = -1
        if !options.videoDisable {
            let videos = assetTracks.filter { $0.mediaType == .video }
            let wantedStreamNb: Int32
            if !videos.isEmpty, let index = options.wantedVideo(tracks: videos) {
                wantedStreamNb = videos[index].trackID
            } else {
                wantedStreamNb = -1
            }
            videoIndex = av_find_best_stream(formatCtx, AVMEDIA_TYPE_VIDEO, wantedStreamNb, -1, nil, 0)
            if let first = videos.first(where: { $0.trackID == videoIndex }) {
                first.isEnabled = true
                let rotation = first.rotation
                if rotation > 0, options.autoRotate {
                    options.hardwareDecode = false
                    if abs(rotation - 90) <= 1 {
                        options.videoFilters.append("transpose=clock")
                    } else if abs(rotation - 180) <= 1 {
                        options.videoFilters.append("hflip")
                        options.videoFilters.append("vflip")
                    } else if abs(rotation - 270) <= 1 {
                        options.videoFilters.append("transpose=cclock")
                    } else if abs(rotation) > 1 {
                        options.videoFilters.append("rotate=\(rotation)*PI/180")
                    }
                }
                naturalSize = abs(rotation - 90) <= 1 || abs(rotation - 270) <= 1 ? first.naturalSize.reverse : first.naturalSize
                // RE: Forward v1.3.15 DV codec detection — DV video (old camcorder format)
                // cannot be hardware decoded by VideoToolbox, force software decode path.
                if first.codecpar.codec_id == AV_CODEC_ID_DVVIDEO {
                    options.hardwareDecode = false
                }
                options.process(assetTrack: first)
                let frameCapacity = options.videoFrameMaxCount(fps: first.nominalFrameRate, naturalSize: naturalSize, isLive: duration == 0)
                let track = options.syncDecodeVideo ? SyncPlayerItemTrack<VideoVTBFrame>(mediaType: .video, frameCapacity: frameCapacity, options: options) : AsyncPlayerItemTrack<VideoVTBFrame>(mediaType: .video, frameCapacity: frameCapacity, options: options)
                track.delegate = self
                allPlayerItemTracks.append(track)
                videoTrack = track
                if first.codecpar.codec_id != AV_CODEC_ID_MJPEG {
                    videoAudioTracks.append(track)
                }
                let bitRates = videos.map(\.bitRate).filter {
                    $0 > 0
                }
                if bitRates.count > 1, options.videoAdaptable {
                    let bitRateState = VideoAdaptationState.BitRateState(bitRate: first.bitRate, time: CACurrentMediaTime())
                    videoAdaptation = VideoAdaptationState(bitRates: bitRates.sorted(by: <), duration: duration, fps: first.nominalFrameRate, bitRateStates: [bitRateState])
                }
            }
        }

        let audios = assetTracks.filter { $0.mediaType == .audio }
        let wantedStreamNb: Int32
        if !audios.isEmpty, let index = options.wantedAudio(tracks: audios) {
            wantedStreamNb = audios[index].trackID
        } else {
            wantedStreamNb = -1
        }
        let index = av_find_best_stream(formatCtx, AVMEDIA_TYPE_AUDIO, wantedStreamNb, videoIndex, nil, 0)
        if let first = audios.first(where: {
            index > 0 ? $0.trackID == index : true
        }), first.codecpar.codec_id != AV_CODEC_ID_NONE {
            first.isEnabled = true
            options.process(assetTrack: first)
            // 音频要比较所有的音轨，因为truehd的fps是1200，跟其他的音轨差距太大了
            let fps = audios.map(\.nominalFrameRate).max() ?? 44
            let frameCapacity = options.audioFrameMaxCount(fps: fps, channelCount: Int(first.audioDescriptor?.audioFormat.channelCount ?? 2))
            let track = options.syncDecodeAudio ? SyncPlayerItemTrack<AudioFrame>(mediaType: .audio, frameCapacity: frameCapacity, options: options) : AsyncPlayerItemTrack<AudioFrame>(mediaType: .audio, frameCapacity: frameCapacity, options: options)
            track.delegate = self
            allPlayerItemTracks.append(track)
            audioTrack = track
            videoAudioTracks.append(track)
            isAudioStalled = false
        }
    }

    private func read() {
        readOperation = BlockOperation { [weak self] in
            guard let self else { return }
            Thread.current.name = (self.operationQueue.name ?? "") + "_read"
            Thread.current.stackSize = KSOptions.stackSize
            self.readThread()
        }
        readOperation?.queuePriority = .veryHigh
        readOperation?.qualityOfService = .userInteractive
        if let readOperation {
            operationQueue.addOperation(readOperation)
        }
    }

    private func readThread() {
        if state == .opened {
            if options.startPlayTime > 0 {
                let timestamp = startTime + CMTime(seconds: options.startPlayTime)
                let flags = seekByBytes ? AVSEEK_FLAG_BYTE : 0
                let seekStartTime = CACurrentMediaTime()
                let result = avformat_seek_file(formatCtx, -1, Int64.min, timestamp.value, Int64.max, flags)
                audioClock.time = timestamp
                videoClock.time = timestamp
                KSLog("start PlayTime: \(timestamp.seconds) spend Time: \(CACurrentMediaTime() - seekStartTime)")
            }
            state = .reading
        }
        allPlayerItemTracks.forEach { $0.decode() }
        while [MESourceState.paused, .seeking, .reading].contains(state) {
            if state == .paused {
                condition.wait()
            }
            if state == .seeking {
                let seekToTime = seekTime
                let time = mainClock().time
                var increase = Int64(seekTime + startTime.seconds - time.seconds)
                var seekFlags = options.seekFlags
                let timeStamp: Int64
                if seekByBytes {
                    seekFlags |= AVSEEK_FLAG_BYTE
                    if let bitRate = formatCtx?.pointee.bit_rate {
                        increase = increase * bitRate / 8
                    } else {
                        increase *= 180_000
                    }
                    var position = Int64(-1)
                    if position < 0 {
                        position = videoClock.position
                    }
                    if position < 0 {
                        position = audioClock.position
                    }
                    if position < 0 {
                        position = avio_tell(formatCtx?.pointee.pb)
                    }
                    timeStamp = position + increase
                } else {
                    increase *= Int64(AV_TIME_BASE)
                    timeStamp = Int64(time.seconds) * Int64(AV_TIME_BASE) + increase
                }
                let seekMin = increase > 0 ? timeStamp - increase + 2 : Int64.min
                let seekMax = increase < 0 ? timeStamp - increase - 2 : Int64.max
                // can not seek to key frame
                let seekStartTime = CACurrentMediaTime()
                var result = avformat_seek_file(formatCtx, -1, seekMin, timeStamp, seekMax, seekFlags)
//                var result = av_seek_frame(formatCtx, -1, timeStamp, seekFlags)
                // When seeking before the beginning of the file, and seeking fails,
                // try again without the backwards flag to make it seek to the
                // beginning.
                if result < 0, seekFlags & AVSEEK_FLAG_BACKWARD == AVSEEK_FLAG_BACKWARD {
                    KSLog("seek to \(seekToTime) failed. seekFlags remove BACKWARD")
                    options.seekFlags &= ~AVSEEK_FLAG_BACKWARD
                    seekFlags &= ~AVSEEK_FLAG_BACKWARD
                    result = avformat_seek_file(formatCtx, -1, seekMin, timeStamp, seekMax, seekFlags)
                }
                KSLog("seek to \(seekToTime) spend Time: \(CACurrentMediaTime() - seekStartTime)")
                if state == .closed {
                    break
                }
                if seekToTime != seekTime {
                    continue
                }
                isSeek = true
                allPlayerItemTracks.forEach { $0.seek(time: seekToTime) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.seekingCompletionHandler?(result >= 0)
                    self.seekingCompletionHandler = nil
                }
                audioClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale) + startTime
                videoClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale) + startTime
                state = .reading
            } else if state == .reading {
                autoreleasepool {
                    _ = reading()
                }
            }
        }
    }

    private func reading() -> Int32 {
        let packet = Packet()
        guard let corePacket = packet.corePacket else {
            return 0
        }
        let readResult = av_read_frame(formatCtx, corePacket)
        if state == .closed {
            return 0
        }
        if readResult == 0 {
            if let outputFormatCtx, let formatCtx {
                let index = Int(corePacket.pointee.stream_index)
                if let outputIndex = streamMapping[index],
                   let inputTb = formatCtx.pointee.streams[index]?.pointee.time_base,
                   let outputTb = outputFormatCtx.pointee.streams[outputIndex]?.pointee.time_base,
                   let outputPacket
                {
                    av_packet_ref(outputPacket, corePacket)
                    outputPacket.pointee.stream_index = Int32(outputIndex)
                    av_packet_rescale_ts(outputPacket, inputTb, outputTb)
                    outputPacket.pointee.pos = -1
                    let ret = av_interleaved_write_frame(outputFormatCtx, outputPacket)
                    if ret < 0 {
                        KSLog("can not av_interleaved_write_frame")
                    }
                }
            }
            if corePacket.pointee.size <= 0 {
                return 0
            }
            let first = assetTracks.first { $0.trackID == corePacket.pointee.stream_index }
            if let first, first.isEnabled {
                packet.assetTrack = first
                if first.mediaType == .video {
                    if options.readVideoTime == 0 {
                        options.readVideoTime = CACurrentMediaTime()
                    }
                    videoTrack?.putPacket(packet: packet)
                } else if first.mediaType == .audio {
                    if options.readAudioTime == 0 {
                        options.readAudioTime = CACurrentMediaTime()
                    }
                    audioTrack?.putPacket(packet: packet)
                } else {
                    first.subtitle?.putPacket(packet: packet)
                }
            }
        } else {
            if readResult == AVError.eof.code || avio_feof(formatCtx?.pointee.pb) > 0 {
                if options.isLoopPlay, allPlayerItemTracks.allSatisfy({ !$0.isLoopModel }) {
                    allPlayerItemTracks.forEach { $0.isLoopModel = true }
                    _ = av_seek_frame(formatCtx, -1, startTime.value, AVSEEK_FLAG_BACKWARD)
                } else {
                    allPlayerItemTracks.forEach { $0.isEndOfFile = true }
                    state = .finished
                }
            } else {
                //                        if IS_AVERROR_INVALIDDATA(readResult)
                error = .init(errorCode: .readFrame, avErrorCode: readResult)
            }
        }
        return readResult
    }

    private func pause() {
        if state == .reading {
            state = .paused
        }
    }

    private func resume() {
        if state == .paused {
            state = .reading
            // RE: signal both the legacy NSCondition-based pause path AND
            // the async `ioWaiter` continuation. The binary uses only the
            // continuation path; `condition.signal()` is the existing
            // OperationQueue-driven equivalent and stays for compatibility.
            signalResume()
        }
    }

    /// Reconnects a network stream by closing the current format context and
    /// fully reopening it. Configures a reconnect count in format context options,
    /// recreates codecs from the new context, and resumes reading.
    func reconnect() {
        guard state != .closed else { return }
        KSLog("[reconnect] initiating stream reconnection")
        // Pause reading while we reconnect
        let wasReading = state == .reading
        if wasReading {
            state = .paused
        }
        // Configure reconnect attempts
        options.formatContextOptions["reconnect"] = 10

        // Close current format context
        allPlayerItemTracks.forEach { $0.shutdown() }
        avformat_close_input(&self.formatCtx)

        // Reopen from scratch — openThread handles alloc, open, find_stream_info, createCodec, and read()
        openThread()
    }

    /// Checks whether all active video/audio track packet buffers contain data spanning
    /// the target seek time. If all tracks can serve the seek from their in-memory packet
    /// cache, returns true — allowing a fast seek without an expensive `av_seek_frame` call.
    ///
    /// - Parameter time: The target seek time in seconds
    /// - Returns: `true` if all tracks can serve the seek from their packet cache
    func usePacketCacheSeek(time: TimeInterval) -> Bool {
        guard !videoAudioTracks.isEmpty else { return false }
        for track in videoAudioTracks {
            // Only AsyncPlayerItemTrack has a packetQueue we can scan
            if let asyncTrack = track as? AsyncPlayerItemTrack<VideoVTBFrame> {
                let found = asyncTrack.packetQueue.scan { packet in
                    // Compare using seconds (packet timestamps are in per-track timebase)
                    let packetStartSec = packet.seconds
                    let packetEndSec = packetStartSec + packet.timebase.cmtime(for: packet.duration).seconds
                    return packetStartSec <= time && packetEndSec > time
                }
                if found.isEmpty { return false }
            } else if let asyncTrack = track as? AsyncPlayerItemTrack<AudioFrame> {
                let found = asyncTrack.packetQueue.scan { packet in
                    let packetStartSec = packet.seconds
                    let packetEndSec = packetStartSec + packet.timebase.cmtime(for: packet.duration).seconds
                    return packetStartSec <= time && packetEndSec > time
                }
                if found.isEmpty { return false }
            } else {
                // SyncPlayerItemTrack doesn't buffer packets — can't do cache seek
                return false
            }
        }
        return true
    }
}

// MARK: MediaPlayback

extension MEPlayerItem: MediaPlayback {
    var seekable: Bool {
        guard let formatCtx else {
            return false
        }
        var seekable = true
        if let ioContext = formatCtx.pointee.pb {
            seekable = ioContext.pointee.seekable > 0
        }
        return seekable
    }

    public func prepareToPlay() {
        state = .opening
        openOperation = BlockOperation { [weak self] in
            guard let self else { return }
            Thread.current.name = (self.operationQueue.name ?? "") + "_open"
            Thread.current.stackSize = KSOptions.stackSize
            self.openThread()
        }
        openOperation?.queuePriority = .veryHigh
        openOperation?.qualityOfService = .userInteractive
        if let openOperation {
            operationQueue.addOperation(openOperation)
        }
    }

    public func shutdown() {
        guard state != .closed else { return }
        state = .closed
        av_packet_free(&outputPacket)
        stopRecord()
        // 故意循环引用。等结束了。才释放
        let closeOperation = BlockOperation {
            Thread.current.name = (self.operationQueue.name ?? "") + "_close"
            self.allPlayerItemTracks.forEach { $0.shutdown() }
            KSLog("清空formatCtx")
            // 自定义的协议才会av_class为空
            if let formatCtx = self.formatCtx, (formatCtx.pointee.flags & AVFMT_FLAG_CUSTOM_IO) != 0, let opaque = formatCtx.pointee.pb.pointee.opaque {
                let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque).takeRetainedValue()
                value.close()
            }
            // 不要自己来释放pb。不然第二次播放同一个url会出问题
//            self.formatCtx?.pointee.pb = nil
            self.formatCtx?.pointee.interrupt_callback.opaque = nil
            self.formatCtx?.pointee.interrupt_callback.callback = nil
            avformat_close_input(&self.formatCtx)
            avformat_close_input(&self.outputFormatCtx)
            self.duration = 0
            self.closeOperation = nil
            self.operationQueue.cancelAllOperations()
        }
        closeOperation.queuePriority = .veryHigh
        closeOperation.qualityOfService = .userInteractive
        if let readOperation {
            readOperation.cancel()
            closeOperation.addDependency(readOperation)
        } else if let openOperation {
            openOperation.cancel()
            closeOperation.addDependency(openOperation)
        }
        operationQueue.addOperation(closeOperation)
        condition.signal()
        if options.syncDecodeVideo || options.syncDecodeAudio {
            DispatchQueue.global().async { [weak self] in
                self?.allPlayerItemTracks.forEach { $0.shutdown() }
            }
        }
        self.closeOperation = closeOperation
    }

    func stopRecord() {
        if let outputFormatCtx {
            av_write_trailer(outputFormatCtx)
        }
        remuxer?.cancel()
        remuxer = nil
    }

    public func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        if state == .reading || state == .paused {
            seekTime = time
            state = .seeking
            seekingCompletionHandler = completion
            condition.broadcast()
            allPlayerItemTracks.forEach { $0.seek(time: time) }
        } else if state == .finished {
            seekTime = time
            state = .seeking
            seekingCompletionHandler = completion
            read()
        } else if state == .seeking {
            seekTime = time
            seekingCompletionHandler = completion
        }
        isAudioStalled = audioTrack == nil
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
            timer.fireDate = Date.distantFuture
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
        if options.videoDisable || videoAdaptation == nil || loadingState.isEndOfFile || loadingState.isSeek || state == .seeking {
            return
        }
        guard let track = videoTrack else {
            return
        }
        videoAdaptation?.loadedCount = track.packetCount + track.frameCount
        videoAdaptation?.currentPlaybackTime = currentPlaybackTime
        videoAdaptation?.isPlayable = loadingState.isPlayable
        guard let (oldBitRate, newBitrate) = options.adaptable(state: videoAdaptation), oldBitRate != newBitrate,
              let newFFmpegAssetTrack = assetTracks.first(where: { $0.mediaType == .video && $0.bitRate == newBitrate })
        else {
            return
        }
        assetTracks.first { $0.mediaType == .video && $0.bitRate == oldBitRate }?.isEnabled = false
        newFFmpegAssetTrack.isEnabled = true
        findBestAudio(videoTrack: newFFmpegAssetTrack)
        let bitRateState = VideoAdaptationState.BitRateState(bitRate: newBitrate, time: CACurrentMediaTime())
        videoAdaptation?.bitRateStates.append(bitRateState)
        delegate?.sourceDidChange(oldBitRate: oldBitRate, newBitrate: newBitrate)
    }

    private func findBestAudio(videoTrack: FFmpegAssetTrack) {
        guard videoAdaptation != nil, let first = assetTracks.first(where: { $0.mediaType == .audio && $0.isEnabled }) else {
            return
        }
        let index = av_find_best_stream(formatCtx, AVMEDIA_TYPE_AUDIO, -1, videoTrack.trackID, nil, 0)
        if index != first.trackID {
            first.isEnabled = false
            assetTracks.first { $0.mediaType == .audio && $0.trackID == index }?.isEnabled = true
        }
    }
}

extension MEPlayerItem: OutputRenderSourceDelegate {
    func mainClock() -> KSClock {
        isAudioStalled ? videoClock : audioClock
    }

    public func setVideo(time: CMTime, position: Int64) {
//        print("[video] video interval \(CACurrentMediaTime() - videoClock.lastMediaTime) video diff \(time.seconds - videoClock.time.seconds)")
        videoClock.time = time
        videoClock.position = position
        videoDisplayCount += 1
        let diff = videoClock.lastMediaTime - lastVideoDisplayTime
        if diff > 1 {
            dynamicInfo.displayFPS = Double(videoDisplayCount) / diff
            videoDisplayCount = 0
            lastVideoDisplayTime = videoClock.lastMediaTime
        }
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

// MARK: - TranscodeContext Factory & Remuxer Wiring

extension MEPlayerItem {
    /// Factory method that creates the appropriate TranscodeContext based on stream type.
    /// RE: Forward v1.3.15 `TranscodeContext_createForStreamIndex` (interior to mega-function FUN_10129d8e0).
    ///
    /// Decision criteria from binary analysis:
    /// - Audio: If AAC with ADTS headers (0xFF, >= 0xF0) and streamCount >= 3,
    ///   use BSFTranscodeContext("aac_adtstoasc"); otherwise CopyTranscodeContext
    /// - Video: CopyTranscodeContext (passthrough) -- muxer handles annexb filters
    /// - Subtitle: SubtitleTranscodeContext targeting ASS or WEBVTT
    /// - Default: CopyTranscodeContext.shared (singleton passthrough)
    static func createTranscodeContext(
        for stream: UnsafeMutablePointer<AVStream>,
        streamCount: Int,
        outputFormatName: String?
    ) -> TranscodeProtocol {
        let codecpar = stream.pointee.codecpar!
        let mediaType = codecpar.pointee.codec_type
        let timeBase = stream.pointee.time_base

        switch mediaType {
        case AVMEDIA_TYPE_AUDIO:
            // RE: BSF decision criteria -- AAC codec with ADTS sync word and >= 3 streams
            if codecpar.pointee.codec_id == AV_CODEC_ID_AAC, streamCount >= 3 {
                // Check for ADTS sync word in extradata
                let hasADTS: Bool
                if let extradata = codecpar.pointee.extradata,
                   codecpar.pointee.extradata_size >= 2 {
                    hasADTS = extradata[0] == 0xFF && extradata[1] >= 0xF0
                } else {
                    hasADTS = false
                }
                if hasADTS {
                    if let bsf = BSFTranscodeContext(filterName: "aac_adtstoasc",
                                                     codecpar: codecpar,
                                                     timeBase: timeBase) {
                        return bsf
                    }
                }
            }
            return CopyTranscodeContext.shared

        case AVMEDIA_TYPE_VIDEO:
            // RE: Binary does NOT manually apply hevc_mp4toannexb or h264_mp4toannexb.
            // FFmpeg's HLS/MOV muxer auto-inserts these BSFs internally.
            return CopyTranscodeContext.shared

        case AVMEDIA_TYPE_SUBTITLE:
            // RE: Target codecs AV_CODEC_ID_ASS (94213) or AV_CODEC_ID_WEBVTT (94226)
            if let sub = SubtitleTranscodeContext(inputCodecpar: codecpar,
                                                  outputCodecID: AV_CODEC_ID_WEBVTT) {
                return sub
            }
            return CopyTranscodeContext.shared

        default:
            return CopyTranscodeContext.shared
        }
    }

    /// Create and attach a Remuxer for TranscodeContext-based output.
    ///
    /// Flow:
    /// 1. If existing remuxer, cancel and clean up
    /// 2. Create new Remuxer with input formatCtx and output URL
    /// 3. OutputStreamInfo handles stream mapping and TranscodeContext creation
    /// 4. Start the remux operation asynchronously
    ///
    /// Trigger: Called from openThread when options.outputURL is present.
    private func createRemuxer(outputURL: URL) {
        // Cancel any existing remuxer
        remuxer?.cancel()
        remuxer = nil

        let outputFormat = outputURL.pathExtension.isEmpty ? nil : outputURL.pathExtension
        let newRemuxer = Remuxer(inputURL: url, outputURL: outputURL, outputFormat: outputFormat)

        // Wire progress handler
        newRemuxer.progressHandler = { [weak self] progress in
            KSLog("[remuxer] progress: \(Int(progress * 100))%")
            _ = self // prevent unused capture warning
        }

        self.remuxer = newRemuxer

        // Start remux asynchronously -- the Remuxer opens its own input context
        // and runs the av_read_frame loop in a cancellable Task.
        Task.detached { [weak self] in
            let success = await newRemuxer.remux()
            if !success {
                KSLog("[remuxer] remux failed for \(outputURL)")
            }
            // Clean up on main
            await MainActor.run {
                if self?.remuxer === newRemuxer {
                    self?.remuxer = nil
                }
            }
        }
    }
}

// MARK: - Cache I/O Pipeline

extension MEPlayerItem {
    /// Select the appropriate cache context based on KSOptions configuration.
    /// RE: Forward v1.3.15 I/O Context Selection table:
    ///   HTTP/HTTPS -> PreLoadIOContext (cache hierarchy)
    ///   SMB/CIFS   -> SMB I/O context
    ///   File       -> Default FFmpeg I/O
    ///   Custom     -> AbstractAVIOContext subclass
    ///
    /// This method creates a cache-aware I/O context for network URLs
    /// when seekUsePacketCache is enabled. The cache hierarchy is:
    ///   URLContextDownload -> CacheIOContext -> LimitCacheIOContext
    ///   -> LimitPreLoadIOContext (moov protection) -> LimitCountPreLoadIOContext
    ///   -> PreLoadIOContext (top of chain, preload scheduling).
    /// `ReadCacheIOContext` is a separate standalone class, not part of this chain.
    ///
    /// - Parameter url: The media URL to create a cache context for
    /// - Returns: An AbstractAVIOContext subclass, or nil to use default FFmpeg I/O
    private func createCacheContext(for url: URL) -> AbstractAVIOContext? {
        guard options.seekUsePacketCache, !url.isFileURL else {
            return nil
        }

        // Estimate bitrate for preload target size.
        // Use file size / duration as a rough estimate, or a reasonable default.
        let estimatedBitrate: Double
        if duration > 0, fileSize > 0 {
            estimatedBitrate = fileSize / duration // bytes per second
        } else {
            estimatedBitrate = 500_000 // ~4 Mbps default
        }

        let cacheSize = options.preferredForwardBufferDuration * estimatedBitrate
        return LimitPreLoadIOContext(url: url, cacheSize: cacheSize)
    }
}

extension AbstractAVIOContext {
    func getContext() -> UnsafeMutablePointer<AVIOContext> {
        // 需要持有ioContext，不然会被释放掉,等到shutdown在清空
        avio_alloc_context(av_malloc(Int(bufferSize)), bufferSize, writable ? 1 : 0, Unmanaged.passRetained(self).toOpaque()) { opaque, buffer, size -> Int32 in
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

// MARK: - Custom I/O Open trampolines (RE: MEPlayerItem_customIOOpen)

extension MEPlayerItem {
    /// C trampoline for `formatCtx->io_open`. Matches the binary's
    /// `MEPlayerItem_customIOOpen` (@ 0x101436800, body 0x101436800-0x101436b47)
    /// and its `b 0x101436800` thunk @ 0x101436b48. The binary attempts the
    /// `ioContext` protocol dispatch for custom URL schemes (HLS segments),
    /// falling back to `defaultIOOpen` (saved original FFmpeg `io_open`) when
    /// the custom path does not apply. Opened protocol buffer objects are
    /// tracked in `pbArray` for cleanup.
    static let _customIOOpenC: IOOpenCallback = { ctx, pbOut, urlPtr, flags, optionsPtr in
        guard let ctx,
              let opaque = ctx.pointee.opaque
        else {
            return AVERROR(EINVAL)
        }
        let item = Unmanaged<MEPlayerItem>.fromOpaque(opaque).takeUnretainedValue()
        return item._customIOOpen(ctx: ctx,
                                  pb: pbOut,
                                  url: urlPtr,
                                  flags: flags,
                                  options: optionsPtr)
    }

    /// C trampoline for `formatCtx->io_close2`.
    static let _customIOCloseC: IOCloseCallback = { ctx, pb in
        guard let ctx,
              let opaque = ctx.pointee.opaque
        else {
            return 0
        }
        let item = Unmanaged<MEPlayerItem>.fromOpaque(opaque).takeUnretainedValue()
        return item._customIOClose(ctx: ctx, pb: pb)
    }

    /// Swift-side body of the custom `io_open` dispatch.
    fileprivate func _customIOOpen(ctx: UnsafeMutablePointer<AVFormatContext>,
                                   pb pbOut: UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?,
                                   url urlPtr: UnsafePointer<CChar>?,
                                   flags: Int32,
                                   options optionsPtr: UnsafeMutablePointer<OpaquePointer?>?) -> Int32 {
        // 1. Try the ioContext protocol dispatch path for HLS-segment and
        //    other custom URL schemes. The binary parses the URL via
        //    `URL(string:)` and dispatches through the ioContext vtable at
        //    +176 (the `open(url:)` method).
        if let urlPtr,
           let parsed = URL(string: String(cString: urlPtr)),
           parsed.scheme != nil,
           let nested = options.process(url: parsed)
        {
            let inner = nested.getContext()
            pbOut?.pointee = inner
            // RE: pbArray tracks the AbstractAVIOContext + its AVIOContext so
            // both stay alive until `io_close2` matches the slot. The Swift
            // struct here is the OUR side of the binary's per-element record.
            pbArray.append(PBSlot(context: nested, pb: inner))
            return 0
        }
        // 2. Fall through to the saved FFmpeg default `io_open`.
        guard let defaultIOOpen else { return AVERROR(ENOSYS) }
        return defaultIOOpen(ctx, pbOut, urlPtr, flags, optionsPtr)
    }

    /// Swift-side body of the custom `io_close2` dispatch.
    fileprivate func _customIOClose(ctx: UnsafeMutablePointer<AVFormatContext>,
                                    pb: UnsafeMutablePointer<AVIOContext>?) -> Int32 {
        // If this AVIOContext was opened via our custom path, drop the
        // tracked slot so the AbstractAVIOContext can be released.
        if let pb,
           let idx = pbArray.firstIndex(where: { $0.pb == pb }) {
            let slot = pbArray.remove(at: idx)
            slot.context.close()
            // Release the retained Swift reference the `getContext()`
            // helper put into `pb.pointee.opaque`.
            if let opaque = slot.pb.pointee.opaque {
                Unmanaged<AbstractAVIOContext>.fromOpaque(opaque).release()
            }
            var local: UnsafeMutablePointer<AVIOContext>? = slot.pb
            avio_context_free(&local)
            return 0
        }
        // Otherwise delegate to the saved FFmpeg `io_close2`.
        guard let defaultIOClose else { return 0 }
        return defaultIOClose(ctx, pb)
    }
}

// MARK: - fontsDir derivation (RE: step 12 of openAndFindStream)

extension MEPlayerItem {
    /// RE: Forward v1.3.15 step 12 of `MEPlayerItem_openAndFindStream`. The
    /// binary computes `NSTemporaryDirectory()/fontsDir/<MD5>` where `<MD5>`
    /// is the CryptoKit `Insecure.MD5` digest of the stream URL's UTF-8
    /// bytes, then writes the resulting `URL` into `KSOptions.fontsDir`.
    static func deriveFontsDir(for url: URL) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fontsDir", isDirectory: true)
        let key = url.isFileURL ? url.path : url.absoluteString
        let hex: String
        #if canImport(CryptoKit)
        if let data = key.data(using: .utf8) {
            let digest = Insecure.MD5.hash(data: data)
            hex = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            hex = UUID().uuidString
        }
        #else
        hex = UUID().uuidString
        #endif
        return base.appendingPathComponent(hex, isDirectory: true)
    }
}

// MARK: - I/O suspension (RE: read-loop pause via CheckedContinuation)

extension MEPlayerItem {
    /// RE: Forward v1.3.15 read-loop pause path. When `state == .paused (5)`,
    /// the binary calls `avio_flush(formatCtx->pb)`, stores a
    /// `CheckedContinuation` into the `ioWaiter` slot, and suspends via
    /// `swift_continuation_await`. This keeps the TCP / HTTP connection alive
    /// across pauses instead of tearing it down.
    ///
    /// The existing read loop in this file uses `NSCondition.wait()` for the
    /// equivalent block, which is fine for the OperationQueue model. This
    /// helper provides the async-await variant the binary uses, for callers
    /// that drive the read loop from a Swift `Task`.
    func awaitResume() async {
        if let pb = formatCtx?.pointee.pb {
            avio_flush(pb)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            condition.lock()
            // If we already transitioned out of .paused while acquiring the
            // lock, resume immediately.
            if state != .paused {
                condition.unlock()
                cont.resume()
                return
            }
            ioWaiter = cont
            condition.unlock()
        }
    }

    /// Signal the read-loop to resume from `awaitResume()`.
    func signalResume() {
        condition.lock()
        let waiter = ioWaiter
        ioWaiter = nil
        condition.unlock()
        waiter?.resume()
        // Also signal the legacy `NSCondition`-based pause path.
        condition.signal()
    }
}
