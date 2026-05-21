//
//  KSOptions.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
#if os(tvOS) || os(xrOS)
import DisplayCriteria
#endif
import Metal
import OSLog

#if canImport(UIKit)
import UIKit
#endif
open class KSOptions {
    // MARK: - Forward additions (RE/76: 29 fields added)

    /// App context identifier (e.g., source screen)
    // RE stub: not yet wired to consumers
    public var context: String = ""
    /// Live stream detection (nil = auto-detect)
    // RE stub: not yet wired to consumers
    public var isLive: Bool?
    /// Start position as percentage (0.0–1.0)
    // RE stub: not yet wired to consumers
    public var startPlayTimePercentage: Double = 0
    /// Resume from last saved position on re-enter
    // RE stub: not yet wired to consumers
    public var enterForgeResumePlay: Bool = false
    /// DLNA/UPnP casting active
    // RE stub: not yet wired to consumers
    public var isDLNARunning: Bool = false
    /// Interval for saving playback progress (seconds)
    // RE stub: not yet wired to consumers
    public var playbackTimeInterval: Double = 0
    /// Instance-level player type list (upstream uses static only)
    // RE stub: not yet wired to consumers
    public var playerTypes: [MediaPlayerProtocol.Type] = []
    /// Mix audio with other apps (vs. solo category)
    // RE stub: not yet wired to consumers
    public var mixAudio: Bool = false
    /// Video content mode (fit/fill)
    // RE stub: not yet wired to consumers
    public var contentMode: UIViewContentMode = .scaleAspectFit
    /// Output media type for recording
    // RE stub: not yet wired to consumers
    public var outputMediaType: AVMediaType?
    /// Output format context options
    // RE stub: not yet wired to consumers
    public var outputFormatContextOptions = [String: Any]()
    /// Instance-level HTTP proxy (upstream static only)
    // RE stub: not yet wired to consumers
    public var useSystemHTTPProxy: Bool = true
    /// Use packet cache during seeks (memory cache for fast short-range seek)
    // RE stub: not yet wired to consumers
    public var seekUsePacketCache: Bool = false
    /// Custom fonts directory for ASS/SSA subtitle rendering
    public var fontsDir: URL?
    /// Speech recognition engines for subtitle generation
    public var audioRecognizes: [Any] = []
    /// Current content dynamic range
    public var dynamicRange: DynamicRange = .sdr
    /// Specific video pipeline selection
    // RE stub: not yet wired to consumers
    public var videoPipeline: VideoPipeline?
    /// Rotate video via FFmpeg filter (vs. display transform)
    // RE stub: not yet wired to consumers
    public var isRotateByFilter: Bool = false
    /// Decode type selection (auto/hardware/software)
    // RE stub: not yet wired to consumers
    public var decodeType: DecodeType = .auto
    /// Software decode thread count (0 = auto)
    // RE stub: not yet wired to consumers
    public var videoSoftDecodeThreadCount: Int = 0
    /// Double display refresh rate (120Hz)
    // RE stub: not yet wired to consumers
    public var isDoubleRefreshRate: Bool = false
    /// Use dispatch timer vs CADisplayLink for render loop
    // RE stub: not yet wired to consumers
    public var renderUseDispatchSourceTimer: Bool = false
    /// Video brightness adjustment (Metal uniform)
    public var brightness: Float = 0.0
    /// Video contrast adjustment (Metal uniform)
    public var contrast: Float = 1.0
    /// Video saturation adjustment (Metal uniform)
    public var saturation: Float = 1.0
    /// Metal uniform buffer for brightness/contrast/saturation adjustments.
    /// Passed to the Metal render pipeline as a fragment buffer for real-time BCS adjustment.
    /// (Prior RE comment referenced `0x103B3CCA0`; that v1.3.14 IDA address has no xrefs in the
    /// v1.3.15 Ghidra DB -- see .reversal/DolbyVision.md "Dead addresses from v1.3.14".)
    public var adjustBuffer: MTLBuffer?
    /// First playable state timing metric
    public internal(set) var firstPlayableTime: Double = 0.0
    /// Spatial audio enabled for this session
    public var isSpatialAudioEnabled: Bool = false
    /// Audio engine type selection (0=AudioEngine, 1=AudioGraph, 2=AudioRenderer, 3=AudioUnit).
    /// Matches `AudioEngineType` enum below (defined at KSOptions.swift:607).
    public var audioEngineType: Int = 0
    /// Dolby Vision profile index (0 = none/auto)
    /// RE: Field descriptor at 0x103780768, index 48
    public var doviProfile: Int = 0
    /// Codec name of the active audio track (e.g. "aac", "eac3", "truehd")
    /// RE: Field descriptor at 0x103780768, index 49
    public var audioCodecName: String = ""
    /// Channel count of the active audio track
    /// RE: Field descriptor at 0x103780768, index 50
    public var audioChannelCount: Int = 0
    /// Allow background audio playback for this session (instance-level override of static)
    /// RE: KSOptions instance field — binary has per-session canBackgroundPlay
    public var canBackgroundPlay: Bool = false
    /// Preferred subtitle languages (BCP-47 codes, e.g. ["en", "ja"])
    /// RE: Used by PlayerPreferences.makeOptions() to set subtitle language preferences
    public var subtitleLanguages: [String] = []

    // MARK: - Upstream fields

    /// 最低缓存视频时间
    @Published
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration
    /// 最大缓存视频时间
    public var maxBufferDuration = KSOptions.maxBufferDuration
    /// 是否开启秒开
    public var isSecondOpen = KSOptions.isSecondOpen
    /// 开启精确seek
    public var isAccurateSeek = KSOptions.isAccurateSeek
    /// Applies to short videos only
    public var isLoopPlay = KSOptions.isLoopPlay
    /// seek完是否自动播放
    public var isSeekedAutoPlay = KSOptions.isSeekedAutoPlay
    /*
     AVSEEK_FLAG_BACKWARD: 1
     AVSEEK_FLAG_BYTE: 2
     AVSEEK_FLAG_ANY: 4
     AVSEEK_FLAG_FRAME: 8
     */
    public var seekFlags = Int32(1)
    // ffmpeg only cache http
    // 这个开关不能用，因为ff_tempfile: Cannot open temporary file
    public var cache = false
    //  record stream
    public var outputURL: URL?
    public var avOptions = [String: Any]()
    public var formatContextOptions = [String: Any]()
    public var decoderOptions = [String: Any]()
    public var probesize: Int64?
    public var maxAnalyzeDuration: Int64?
    public var lowres = UInt8(0)
    public var nobuffer = false
    public var codecLowDelay = false
    public var startPlayTime: TimeInterval = 0
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true // 默认支持来自系统控制中心的控制
    public var referer: String? {
        didSet {
            if let referer {
                formatContextOptions["referer"] = "Referer: \(referer)"
            } else {
                formatContextOptions["referer"] = nil
            }
        }
    }

    public var userAgent: String? = "KSPlayer" {
        didSet {
            formatContextOptions["user_agent"] = userAgent
        }
    }

    // audio
    public var audioFilters = [String]()
    public var syncDecodeAudio = false
    // sutile
    public var autoSelectEmbedSubtitle = true
    public var isSeekImageSubtitle = false
    // video
    public var display = DisplayEnum.plane
    public var videoDelay = 0.0 // s
    public var autoDeInterlace = false
    /// Instance-level deinterlace mode (per-session override of KSOptions.yadifMode).
    /// RE: Field #43 in binary field map. 0=send_frame, 1=send_field (doubles frame rate).
    public var yadifMode: Int = KSOptions.yadifMode
    /// Instance-level idet filter flag (per-session override of KSOptions.deInterlaceAddIdet).
    /// RE: Field #44 in binary field map.
    public var deInterlaceAddIdet: Bool = KSOptions.deInterlaceAddIdet
    public var autoRotate = true
    public var destinationDynamicRange: DynamicRange?
    public var videoAdaptable = true
    public var videoFilters = [String]()
    public var syncDecodeVideo = false
    public var hardwareDecode = KSOptions.hardwareDecode
    public var asynchronousDecompression = KSOptions.asynchronousDecompression
    public var videoDisable = false
    public var canStartPictureInPictureAutomaticallyFromInline = KSOptions.canStartPictureInPictureAutomaticallyFromInline
    public var automaticWindowResize = true
    @Published
    public var videoInterlacingType: VideoInterlacingType?
    private var videoClockDelayCount = 0

    public internal(set) var formatName = ""
    public internal(set) var prepareTime = 0.0
    public internal(set) var dnsStartTime = 0.0
    public internal(set) var tcpStartTime = 0.0
    public internal(set) var tcpConnectedTime = 0.0
    public internal(set) var openTime = 0.0
    public internal(set) var findTime = 0.0
    public internal(set) var readyTime = 0.0
    public internal(set) var readAudioTime = 0.0
    public internal(set) var readVideoTime = 0.0
    public internal(set) var decodeAudioTime = 0.0
    public internal(set) var decodeVideoTime = 0.0
    public init() {
        formatContextOptions["user_agent"] = userAgent
        // 参数的配置可以参考protocols.texi 和 http.c
        // 这个一定要，不然有的流就会判断不准FieldOrder
        formatContextOptions["scan_all_pmts"] = 1
        // ts直播流需要加这个才能一直直播下去，不然播放一小段就会结束了。
        formatContextOptions["reconnect"] = 1
        formatContextOptions["reconnect_streamed"] = 1
        // RE: Forward v1.3.15 -- `rw_timeout` default = 15_000_000 us (15 s).
        // Required for the open-and-find-stream path to abort cleanly on a
        // hung remote, before the retry / reconnect logic kicks in.
        formatContextOptions["rw_timeout"] = 15_000_000
        // 这个是用来开启http的链接复用（keep-alive）。vlc默认是打开的，所以这边也默认打开。
        // 开启这个，百度网盘的视频链接无法播放
        // formatContextOptions["multiple_requests"] = 1
        // 下面是用来处理秒开的参数，有需要的自己打开。默认不开，不然在播放某些特殊的ts直播流会频繁卡顿。
//        formatContextOptions["auto_convert"] = 0
//        formatContextOptions["fps_probe_size"] = 3
//        formatContextOptions["rw_timeout"] = 10_000_000
//        formatContextOptions["max_analyze_duration"] = 300 * 1000
        // 默认情况下允许所有协议，只有嵌套协议才需要指定这个协议子集，例如m3u8里面有http。
//        formatContextOptions["protocol_whitelist"] = "file,http,https,tcp,tls,crypto,async,cache,data,httpproxy"
        // 开启这个，纯ipv6地址会无法播放。并且有些视频结束了，但还会一直尝试重连。所以这个值默认不设置
//        formatContextOptions["reconnect_at_eof"] = 1
        // 开启这个，会导致tcp Failed to resolve hostname 还会一直重试
//        formatContextOptions["reconnect_on_network_error"] = 1
        // There is total different meaning for 'listen_timeout' option in rtmp
        // set 'listen_timeout' = -1 for rtmp、rtsp
//        formatContextOptions["listen_timeout"] = 3
        decoderOptions["threads"] = "auto"
        decoderOptions["refcounted_frames"] = "1"
    }

    /**
     you can add http-header or other options which mentions in https://developer.apple.com/reference/avfoundation/avurlasset/initialization_options

     to add http-header init options like this
     ```
     options.appendHeader(["Referer":"https:www.xxx.com"])
     ```
     */
    public func appendHeader(_ header: [String: String]) {
        var oldValue = avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [
            String: String
        ]()
        oldValue.merge(header) { _, new in new }
        avOptions["AVURLAssetHTTPHeaderFieldsKey"] = oldValue
        var str = formatContextOptions["headers"] as? String ?? ""
        for (key, value) in header {
            str.append("\(key):\(value)\r\n")
        }
        formatContextOptions["headers"] = str
    }

    public func setCookie(_ cookies: [HTTPCookie]) {
        avOptions[AVURLAssetHTTPCookiesKey] = cookies
        let cookieStr = cookies.map { cookie in "\(cookie.name)=\(cookie.value)" }.joined(separator: "; ")
        appendHeader(["Cookie": cookieStr])
    }

    // 缓冲算法函数
    open func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
        let packetCount = capacitys.map(\.packetCount).min() ?? 0
        let frameCount = capacitys.map(\.frameCount).min() ?? 0
        let isEndOfFile = capacitys.allSatisfy(\.isEndOfFile)
        let loadedTime = capacitys.map(\.loadedTime).min() ?? 0
        let progress = preferredForwardBufferDuration == 0 ? 100 : loadedTime * 100.0 / preferredForwardBufferDuration
        let isPlayable = capacitys.allSatisfy { capacity in
            if capacity.isEndOfFile && capacity.packetCount == 0 {
                return true
            }
            guard capacity.frameCount >= 2 else {
                return false
            }
            if capacity.isEndOfFile {
                return true
            }
            if (syncDecodeVideo && capacity.mediaType == .video) || (syncDecodeAudio && capacity.mediaType == .audio) {
                return true
            }
            if isFirst || isSeek {
                // 让纯音频能更快的打开
                if capacity.mediaType == .audio || isSecondOpen {
                    if isFirst {
                        return true
                    } else {
                        return capacity.loadedTime >= self.preferredForwardBufferDuration / 2
                    }
                }
            }
            return capacity.loadedTime >= self.preferredForwardBufferDuration
        }
        return LoadingState(loadedTime: loadedTime, progress: progress, packetCount: packetCount,
                            frameCount: frameCount, isEndOfFile: isEndOfFile, isPlayable: isPlayable,
                            isFirst: isFirst, isSeek: isSeek)
    }

    open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)? {
        guard let state, let last = state.bitRateStates.last, CACurrentMediaTime() - last.time > maxBufferDuration / 2, let index = state.bitRates.firstIndex(of: last.bitRate) else {
            return nil
        }
        let isUp = state.loadedCount > Int(Double(state.fps) * maxBufferDuration / 2)
        if isUp != state.isPlayable {
            return nil
        }
        if isUp {
            if index < state.bitRates.endIndex - 1 {
                return (last.bitRate, state.bitRates[index + 1])
            }
        } else {
            if index > state.bitRates.startIndex {
                return (last.bitRate, state.bitRates[index - 1])
            }
        }
        return nil
    }

    ///  wanted video stream index, or nil for automatic selection
    /// - Parameter : video track
    /// - Returns: The index of the track
    open func wantedVideo(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }

    /// wanted audio stream index, or nil for automatic selection
    /// - Parameter :  audio track
    /// - Returns: The index of the track
    open func wantedAudio(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }

    open func videoFrameMaxCount(fps _: Float, naturalSize _: CGSize, isLive: Bool) -> UInt8 {
        isLive ? 4 : 16
    }

    open func audioFrameMaxCount(fps: Float, channelCount: Int) -> UInt8 {
        let count = (Int(fps) * channelCount) >> 2
        if count >= UInt8.max {
            return UInt8.max
        } else {
            return UInt8(count)
        }
    }

    /// customize dar
    /// - Parameters:
    ///   - sar: SAR(Sample Aspect Ratio)
    ///   - dar: PAR(Pixel Aspect Ratio)
    /// - Returns: DAR(Display Aspect Ratio)
    open func customizeDar(sar _: CGSize, par _: CGSize) -> CGSize? {
        nil
    }

    // 虽然只有iOS才支持PIP。但是因为AVSampleBufferDisplayLayer能够支持HDR10+。所以默认还是推荐用AVSampleBufferDisplayLayer
    open func isUseDisplayLayer() -> Bool {
        if display != .plane { return false }
        if dynamicRange == .dolbyVision && KSOptions.enhanceDolby {
            return false
        }
        return true
    }

    open func urlIO(log: String) {
        if log.starts(with: "Original list of addresses"), dnsStartTime == 0 {
            dnsStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Starting connection attempt to"), tcpStartTime == 0 {
            tcpStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Successfully connected to"), tcpConnectedTime == 0 {
            tcpConnectedTime = CACurrentMediaTime()
        }
    }

    private var idetTypeMap = [VideoInterlacingType: UInt]()
    open func filter(log: String) {
        if log.starts(with: "Repeated Field:"), autoDeInterlace {
            for str in log.split(separator: ",") {
                let map = str.split(separator: ":")
                if map.count >= 2 {
                    if String(map[0].trimmingCharacters(in: .whitespaces)) == "Multi frame" {
                        if let type = VideoInterlacingType(rawValue: map[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                            idetTypeMap[type] = (idetTypeMap[type] ?? 0) + 1
                            let tff = idetTypeMap[.tff] ?? 0
                            let bff = idetTypeMap[.bff] ?? 0
                            let progressive = idetTypeMap[.progressive] ?? 0
                            let undetermined = idetTypeMap[.undetermined] ?? 0
                            if progressive - tff - bff > 100 {
                                videoInterlacingType = .progressive
                                autoDeInterlace = false
                            } else if bff - progressive > 100 {
                                videoInterlacingType = .bff
                                autoDeInterlace = false
                            } else if tff - progressive > 100 {
                                videoInterlacingType = .tff
                                autoDeInterlace = false
                            } else if undetermined - progressive - tff - bff > 100 {
                                videoInterlacingType = .undetermined
                                autoDeInterlace = false
                            }
                        }
                    }
                }
            }
        }
    }

    open func sei(string: String) {
        KSLog("sei \(string)")
    }

    /**
            在创建解码器之前可以对KSOptions和assetTrack做一些处理。例如判断fieldOrder为tt或bb的话，那就自动加videofilters
     */
    open func process(assetTrack: some MediaPlayerTrack) {
        if assetTrack.mediaType == .video {
            // RE: KSOptions_classifyDynamicRange @ 0x1013c38fc (v1.3.15 Ghidra).
            // Prefer the two-path classifier when we have a codec_tag + CMFormatDescription
            // (matches the binary's vtable+0x90 / vtable+0x98 dispatch shape); fall back to
            // the simple transfer-function classifier otherwise.
            if let ffmpegTrack = assetTrack as? FFmpegAssetTrack {
                let classified: DynamicRange
                let codecTag = ffmpegTrack.codecpar.codec_tag
                if codecTag != 0 {
                    classified = KSOptions.classifyDynamicRange(
                        codecTag: codecTag,
                        formatDescription: ffmpegTrack.formatDescription
                    )
                } else {
                    classified = KSOptions.classifyDynamicRange(
                        colorTrc: ffmpegTrack.codecpar.color_trc,
                        hasDovi: ffmpegTrack.dovi != nil
                    )
                }
                dynamicRange = classified
                if classified == .dolbyVision || classified == .hdr10
                    || classified == .hdr10Fallback || classified == .hlg {
                    // HDR content: disable async decompression and force hardware decode
                    // for correct HDR metadata passthrough (RE: onVideoTrackOpened behavior)
                    asynchronousDecompression = false
                    hardwareDecode = true
                }
            }
            if [FFmpegFieldOrder.bb, .bt, .tt, .tb].contains(assetTrack.fieldOrder) {
                // todo 先不要用yadif_videotoolbox，不然会crash。这个后续在看下要怎么解决
                hardwareDecode = false
                asynchronousDecompression = false
                let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
                var yadifMode = self.yadifMode
//                if let assetTrack = assetTrack as? FFmpegAssetTrack {
//                    if assetTrack.realFrameRate.num == 2 * assetTrack.avgFrameRate.num, assetTrack.realFrameRate.den == assetTrack.avgFrameRate.den {
//                        if yadifMode == 1 {
//                            yadifMode = 0
//                        } else if yadifMode == 3 {
//                            yadifMode = 2
//                        }
//                    }
//                }
                if self.deInterlaceAddIdet {
                    videoFilters.append("idet")
                }
                videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")
                if yadifMode == 1 || yadifMode == 3 {
                    assetTrack.nominalFrameRate = assetTrack.nominalFrameRate * 2
                }
            }
            // HDR→SDR tone mapping via libplacebo FFmpeg filter (RE/19: pl_shader_detect_peak_hdr)
            if KSOptions.enableHDRToSDRToneMapping, dynamicRange != .sdr {
                let algo = KSOptions.tonemapAlgorithm
                videoFilters.append("libplacebo=tonemapping=\(algo):apply_dolbyvision=1:colorspace=bt709:color_primaries=bt709:color_trc=bt709")
                destinationDynamicRange = .sdr
            }
        }
    }

    @MainActor
    open func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        #if os(tvOS) || os(xrOS)
        /**
         快速更改preferredDisplayCriteria，会导致isDisplayModeSwitchInProgress变成true。
         例如退出一个视频，然后在3s内重新进入的话。所以不判断isDisplayModeSwitchInProgress了
         */
        guard let displayManager = UIApplication.shared.windows.first?.avDisplayManager,
              displayManager.isDisplayCriteriaMatchingEnabled
        else {
            return
        }
        if let dynamicRange = isDovi ? .dolbyVision : formatDescription?.dynamicRange {
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, videoDynamicRange: dynamicRange.rawValue)
        }
        #endif
    }

    open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: Int) -> (Double, ClockProcessType) {
        let desire = main.getTime() - videoDelay
        let diff = nextVideoTime - desire
//        print("[video] video diff \(diff) nextVideoTime \(nextVideoTime) main \(main.time.seconds)")
        if diff >= 1 / fps / 2 {
            videoClockDelayCount = 0
            return (diff, .remain)
        } else {
            // RE: Forward v1.3.15 videoClockSync uses -2/fps (not -4/fps) as the falling-behind threshold.
            // See .reversal/DisplayMetal.md §KSOptions_videoClockSync sync-thresholds table.
            if diff < -2 / fps {
                videoClockDelayCount += 1
                let log = "[video] video delay=\(diff), clock=\(desire), delay count=\(videoClockDelayCount), frameCount=\(frameCount)"
                if frameCount == 1 {
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) drop gop Packet")
                        return (diff, .dropGOPPacket)
                    } else if videoClockDelayCount % 5 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                } else {
                    if diff < -8, videoClockDelayCount % 100 == 0 {
                        KSLog("\(log) seek video track")
                        return (diff, .seek)
                    }
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) flush video track")
                        return (diff, .flush)
                    }
                    if videoClockDelayCount % 2 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                }
            } else {
                videoClockDelayCount = 0
                return (diff, .next)
            }
        }
    }

    open func availableDynamicRange(_ contentRange: DynamicRange?) -> DynamicRange? {
        #if canImport(UIKit)
        let availableHDRModes = AVPlayer.availableHDRModes
        if let preferredDynamicRange = destinationDynamicRange {
            // value of 0 indicates that no HDR modes are supported.
            if availableHDRModes == AVPlayer.HDRMode(rawValue: 0) {
                return .sdr
            } else if availableHDRModes.contains(preferredDynamicRange.hdrMode) {
                return preferredDynamicRange
            } else if let contentRange,
                      availableHDRModes.contains(contentRange.hdrMode)
            {
                return contentRange
            } else if preferredDynamicRange != .sdr { // trying update to HDR mode
                return availableHDRModes.dynamicRange
            }
        }
        return contentRange
        #else
        return destinationDynamicRange ?? contentRange
        #endif
    }

    open func playerLayerDeinit() {
        #if os(tvOS) || os(xrOS)
        runOnMainThread {
            UIApplication.shared.windows.first?.avDisplayManager.preferredDisplayCriteria = nil
        }
        #endif
    }

    open func liveAdaptivePlaybackRate(loadingState _: LoadingState) -> Float? {
        nil
//        if loadingState.isFirst {
//            return nil
//        }
//        if loadingState.loadedTime > preferredForwardBufferDuration + 5 {
//            return 1.2
//        } else if loadingState.loadedTime < preferredForwardBufferDuration / 2 {
//            return 0.8
//        } else {
//            return 1
//        }
    }

    open func process(url: URL) -> AbstractAVIOContext? {
        if seekUsePacketCache, !url.isFileURL {
            return PreLoadIOContext(url: url)
        }
        return nil
    }
}

public enum VideoInterlacingType: String {
    case tff
    case bff
    case progressive
    case undetermined
}

// MARK: - Forward enums (RE/76)

public enum DecodeType: Int, Sendable {
    case auto = 0
    case hardware = 1
    case software = 2
}

public enum VideoPipeline: Int, Sendable {
    case auto = 0
    case videoToolbox = 1
    case metal = 2
    case libplacebo = 3
}

/// Audio engine backend selection.
/// RE: Forward v1.3.15 AudioEngineType enum with 4 cases.
/// Binary values: audioEngine=0, audioGraph=1, audioRenderer=2, audioUnit=3
public enum AudioEngineType: Int, CaseIterable, Codable, Sendable {
    case audioEngine = 0
    case audioGraph = 1
    case audioRenderer = 2
    case audioUnit = 3
}

public extension KSOptions {
    /// Master flag for Dolby Vision enhanced decode path. Default `true`.
    ///
    /// **Backing static in the binary (v1.3.15):** `DAT_104450978` (1-byte Bool, exclusivity
    /// enforced via `_swift_beginAccess` for the public getter/setter/modify trio at
    /// `0x1000bd4bc / 0x1000bd4fc / 0x1000bd540`). Public AppStorage key: `"enhance_dolby"`.
    ///
    /// **Lifecycle writes (binary).** Per `.reversal/DolbyVision.md §"Lifecycle write sites
    /// for DAT_104450978"`: `PlayerCenter_presentPlayerViewController` (entry `0x101027cd0`,
    /// write at `0x101027fec`) force-sets `DAT_104450978 = 1` AND mirrors the value into
    /// `NSUserDefaults` via `setBool:forKey:`; `PlayerCenter_dismissPlayer` (entry
    /// `0x100fcc540`, write at `0x100fcc6e4`) does the same with `0`. Both writes are
    /// unconditional constants and skip `_swift_beginAccess`. Net effect: player lifecycle
    /// **overrides** the user's stored preference. The Swift port reproduces the observable
    /// behaviour idiomatically through `@AppStorage("enhance_dolby")` in `PlayerPreferences`
    /// plus `PlayerCenter.present/dismiss`.
    ///
    /// **Selection chain (binary).** `enhanceDolby == true` is what enables the Metal
    /// `DoviDisplayModel` reshape path for DV content; see `isUseDisplayLayer()` below and
    /// `MetalPlayView`'s DV-metadata gate. There is no inversion: `enhanceDolby == true`
    /// selects Metal DV, `enhanceDolby == false` selects HDR10 fallback / AVSBDL.
    ///
    /// **Related static.** `DAT_103d097d8` is a *separate* KSOptions-related Bool with its
    /// own accessor triple at `0x1013a3658 / 0x1013a3698 / 0x1013a36dc` (witness at
    /// `0x104820ecf/d0`) and 14+ readers across decode/render. It is **not** a copy of
    /// `enhanceDolby` -- semantic identity unresolved. `classifyDynamicRange` reads it
    /// inlined to gate Profile-7 DV-vs-HDR10. See `.reversal/DolbyVision.md §"Statics that
    /// look related to enhanceDolby"`.
    static var enhanceDolby: Bool = true

    /// Classify dynamic range from FFmpeg transfer characteristics and Dolby Vision side data.
    /// RE binary address: `KSOptions_classifyDynamicRange @ 0x1013c38fc`
    /// (delegates to `_fromFormatDescription @ 0x1013ee0cc` for the CMFormatDescription path).
    ///
    /// **Binary control flow (informs the two-path overload below).** Per
    /// `.reversal/DolbyVision.md §"classifyDynamicRange"`:
    ///   - **Path 1** (no usable CMFormatDescription): if `(codecTag & 0xff0000) == 0x70000`
    ///     (DV Profile 7) → `DAT_103d097d8 ? 3 (DV) : 1 (HDR10)`; otherwise return `3` (DV).
    ///   - **Path 2** (CMFormatDescription present): `vtable+0x98` probe → if `0` return
    ///     `4` (`hdr10Fallback`); else delegate to `_fromFormatDescription` which checks
    ///     `dvhe`/`dvh1` (return 3), then PQ transfer (return 1), HLG (return 2), else SDR.
    ///
    /// This thin convenience overload pushes Profile-7 detection upstream into the
    /// `hasDovi` boolean (set by the caller from `AVCodecParameters` /
    /// `DOVIDecoderConfigurationRecord`). For call sites that have a codec tag and an
    /// optional `CMFormatDescription` the richer two-path variant below should be preferred.
    ///
    /// - Parameters:
    ///   - colorTrc: The track's color transfer characteristic (color_trc from AVCodecParameters).
    ///   - hasDovi: Whether Dolby Vision side data / configuration record is present.
    /// - Returns: The classified `DynamicRange` value.
    static func classifyDynamicRange(colorTrc: AVColorTransferCharacteristic, hasDovi: Bool) -> DynamicRange {
        if hasDovi {
            return .dolbyVision
        }
        switch colorTrc {
        case AVCOL_TRC_SMPTE2084:
            return .hdr10
        case AVCOL_TRC_ARIB_STD_B67:
            return .hlg
        default:
            return .sdr
        }
    }

    /// Two-path classifier that mirrors the binary's dispatch shape.
    /// RE binary: `KSOptions_classifyDynamicRange @ 0x1013c38fc` +
    /// `_fromFormatDescription @ 0x1013ee0cc`. See `.reversal/DolbyVision.md §classifyDynamicRange`.
    ///
    /// - Parameters:
    ///   - codecTag: 32-bit FourCC code from `AVCodecParameters.codec_tag`.
    ///   - formatDescription: Optional `CMFormatDescription`. When `nil` the binary's
    ///     `vtable+0x90` probe returns `0`, which selects Path 1 (codec-tag dispatch).
    ///   - profileSevenPrefersDV: Mirror of binary's `DAT_103d097d8` read; when `true`,
    ///     Profile-7 content returns `.dolbyVision`, when `false` it returns `.hdr10`.
    ///     Default: `KSOptions.enhanceDolby` (the closest Swift-side analogue; the actual
    ///     binary static has an unresolved identity -- see `enhanceDolby` doc comment).
    /// - Returns: A `DynamicRange` value matching the binary's compact 0/1/2/3/4 scheme
    ///   (mapped through `DynamicRange.init(forwardValue:)`).
    static func classifyDynamicRange(
        codecTag: UInt32,
        formatDescription: CMFormatDescription?,
        profileSevenPrefersDV: Bool = KSOptions.enhanceDolby
    ) -> DynamicRange {
        // Binary probe: vtable+0x90 returns a bool in the low bit. Swift analogue:
        // "is a CMFormatDescription actually available?"
        guard let fd = formatDescription else {
            // Path 1: codec-tag dispatch.
            if (codecTag & 0xFF_0000) == 0x07_0000 {
                // DV Profile 7: gate DV-vs-HDR10 on the second static.
                return profileSevenPrefersDV ? .dolbyVision : .hdr10
            }
            // No CMFormatDescription, no Profile-7 hint -> assume DV.
            return .dolbyVision
        }
        // Path 2 vtable+0x98 probe: in the binary the inner virtual call returns 0 when
        // the format descriptor cannot resolve a media sub-type. CoreMedia's
        // `formatDescription.mediaSubType` is the Swift equivalent; an unrecognised
        // sub-type maps to the `.hdr10Fallback` rail (Forward compact value 4).
        let subType = CMFormatDescriptionGetMediaSubType(fd)
        if subType == 0 {
            return .hdr10Fallback
        }
        // dvhe / dvh1 fourcc -> DV (matches the post-bswap compares at 0x1013ee0cc).
        // CMVideoCodecType is a big-endian FourCC: 'd','v','h','1' -> 0x64766831.
        if subType == CMVideoCodecType(0x6476_6831)        // 'dvh1'
            || subType == CMVideoCodecType(0x6476_6865) {  // 'dvhe'
            return .dolbyVision
        }
        // Transfer-function fallback when sub-type is recognised but not DV.
        if let ext = CMFormatDescriptionGetExtension(
            fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String {
            if ext == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String {
                return .hdr10
            }
            if ext == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String {
                return .hlg
            }
        }
        return .sdr
    }

    /// Lazy-initialized global `DoviDisplayModel` singleton.
    ///
    /// RE source: Forward v1.3.15 `KSOptions_createDoviDisplayModel` @ `0x1013a30cc` (376B).
    /// The binary stores the instance at `QWORD_104458878` (read by `MEPlayerItem_processFrameSideData
    /// @ 0x101407cc4`, `MetalPlayView_renderFrameImpl @ 0x1014457f4`, and `FUN_1014508b4 @ 0x101450f00`).
    /// Allocation size is `0x88` (136B) per `_swift_allocObject(..., 0x88, 7)`. The accessor uses
    /// `swift_once(&DAT_103d06280, ...)` so the instance is created exactly once per process.
    ///
    /// See .reversal/DisplayMetal.md §DoviDisplayModel.
    @MainActor
    static func createDoviDisplayModel() -> DoviDisplayModel? {
        if let existing = doviDisplayModelStorage {
            return existing
        }
        let model = DoviDisplayModel(device: MetalRender.device)
        doviDisplayModelStorage = model
        return model
    }
}

/// Backing storage for the `DoviDisplayModel` singleton (binary: `QWORD_104458878`).
///
/// Kept module-private and `@MainActor`-isolated so writes happen on a single actor — mirrors the
/// `swift_once` gate around the binary's `KSOptions_createDoviDisplayModel`. Read via the
/// `KSOptions.createDoviDisplayModel()` accessor; never assign directly.
@MainActor
private var doviDisplayModelStorage: DoviDisplayModel?

public extension KSOptions {

    /// Build a dictionary of playback timing metrics from the instance's recorded timestamps.
    /// Useful for analytics / debugging first-frame latency breakdown.
    func buildPlaybackTimingMetrics() -> [String: TimeInterval] {
        var metrics = [String: TimeInterval]()
        metrics["prepareTime"] = prepareTime
        metrics["dnsStartTime"] = dnsStartTime
        metrics["tcpStartTime"] = tcpStartTime
        metrics["tcpConnectedTime"] = tcpConnectedTime
        metrics["openTime"] = openTime
        metrics["findTime"] = findTime
        metrics["readyTime"] = readyTime
        metrics["readAudioTime"] = readAudioTime
        metrics["readVideoTime"] = readVideoTime
        metrics["decodeAudioTime"] = decodeAudioTime
        metrics["decodeVideoTime"] = decodeVideoTime
        metrics["firstPlayableTime"] = firstPlayableTime
        return metrics
    }

    /// Whether the simple (non-BCS, non-HDR) render pipeline can be used.
    /// RE/62: true only when no EDR metadata, BCS are identity, display is .plane,
    /// no custom pipeline configured.
    func canUseSimpleRenderPipeline() -> Bool {
        brightness == 0.0 && contrast == 1.0 && saturation == 1.0
            && display == .plane
            && videoPipeline == nil
    }

    static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self
    /// 最低缓存视频时间
    static var preferredForwardBufferDuration = 3.0
    /// 最大缓存视频时间
    static var maxBufferDuration = 30.0
    /// 是否开启秒开
    static var isSecondOpen = false
    /// 开启精确seek
    static var isAccurateSeek = false
    /// Applies to short videos only
    static var isLoopPlay = false
    /// 是否自动播放，默认true
    static var isAutoPlay = true
    /// seek完是否自动播放
    static var isSeekedAutoPlay = true
    static var hardwareDecode = true
    // 默认不用自研的硬解，因为有些视频的AVPacket的pts顺序是不对的，只有解码后的AVFrame里面的pts是对的。
    static var asynchronousDecompression = false
    static var isPipPopViewController = false
    static var canStartPictureInPictureAutomaticallyFromInline = true
    /// Use libass C library for ASS/SSA subtitle rendering (enables embedded font extraction)
    public static var useLibassForASS = true
    /// Enable HDR→SDR tone mapping via libplacebo FFmpeg filter.
    /// RE source: Forward v1.3.15 libplacebo pipeline with pl_shader_detect_peak_hdr,
    /// apply_dolbyvision=1 default. See RE/19.
    public static var enableHDRToSDRToneMapping = false
    /// Enable HDR-aware subtitle compositing via MetalSubtitleView.
    /// RE: KSOptions instance field, gates CAMetalLayer EDR + CIColorControls pipeline
    /// for subtitle rendering in HDR/DV content.
    public static var enableHDRSubtitle: Bool = false
    /// Tone mapping algorithm for HDR→SDR conversion.
    /// Supported: "hable", "mobius", "reinhard", "bt2390", "gamma", "linear"
    public static var tonemapAlgorithm = "hable"
    /// Enable Anime4K real-time upscaling (GLSL→Metal transpiled shaders)
    public static var enableAnime4K = false
    /// Anime4K preset name (e.g., "Mode A", "Mode B", "Mode C", "Mode A+A")
    public static var anime4KPreset = "Mode A"
    #if canImport(Speech)
    @available(iOS 10.0, macOS 10.15, *)
    static func registerSpeechRecognition() {
        SubtitleModel.audioRecognizes.append(SpeechRecognizeSubtitle())
    }
    #endif

    /// Use a single shared CADisplayLink across all MetalPlayView instances
    /// instead of one CADisplayLink per view. Preferred for multi-view layouts.
    static var useSharedDisplayLink = false
    static var preferredFrame = true
    static var useSystemHTTPProxy = true
    /// 日志级别
    static var logLevel = LogLevel.warning
    static var logger: LogHandler = OSLog(lable: "KSPlayer")
    internal static func deviceCpuCount() -> Int {
        var ncpu = UInt(0)
        var len: size_t = MemoryLayout.size(ofValue: ncpu)
        sysctlbyname("hw.ncpu", &ncpu, &len, nil, 0)
        return Int(ncpu)
    }

    static func setAudioSession() {
        #if os(macOS)
//        try? AVAudioSession.sharedInstance().setRouteSharingPolicy(.longFormAudio)
        #else
        var category = AVAudioSession.sharedInstance().category
        if category != .playAndRecord {
            category = .playback
        }
        #if os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormAudio)
        #else
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormVideo)
        #endif
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    #if !os(macOS)
    static func isSpatialAudioEnabled(channelCount _: AVAudioChannelCount) -> Bool {
        if #available(tvOS 15.0, iOS 15.0, *) {
            let isSpatialAudioEnabled = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
            try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(isSpatialAudioEnabled)
            return isSpatialAudioEnabled
        } else {
            return false
        }
    }

    static func outputNumberOfChannels(channelCount: AVAudioChannelCount) -> AVAudioChannelCount {
        let maximumOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        let preferredOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().preferredOutputNumberOfChannels)
        let isSpatialAudioEnabled = isSpatialAudioEnabled(channelCount: channelCount)
        let isUseAudioRenderer = KSOptions.audioPlayerType == AudioRendererPlayer.self
        KSLog("[audio] maximumOutputNumberOfChannels: \(maximumOutputNumberOfChannels), preferredOutputNumberOfChannels: \(preferredOutputNumberOfChannels), isSpatialAudioEnabled: \(isSpatialAudioEnabled), isUseAudioRenderer: \(isUseAudioRenderer) ")
        let maxRouteChannelsCount = AVAudioSession.sharedInstance().currentRoute.outputs.compactMap {
            $0.channels?.count
        }.max() ?? 2
        KSLog("[audio] currentRoute max channels: \(maxRouteChannelsCount)")
        var channelCount = channelCount
        if channelCount > 2 {
            let minChannels = min(maximumOutputNumberOfChannels, channelCount)
            #if os(tvOS) || targetEnvironment(simulator)
            if !(isUseAudioRenderer && isSpatialAudioEnabled) {
                // 不要用maxRouteChannelsCount来判断，有可能会不准。导致多音道设备也返回2（一开始播放一个2声道，就容易出现），也不能用outputNumberOfChannels来判断，有可能会返回2
//                channelCount = AVAudioChannelCount(min(AVAudioSession.sharedInstance().outputNumberOfChannels, maxRouteChannelsCount))
                channelCount = minChannels
            }
            #else
            // iOS 外放是会自动有空间音频功能，但是蓝牙耳机有可能没有空间音频功能或者把空间音频给关了，。所以还是需要处理。
            if !isSpatialAudioEnabled {
                channelCount = minChannels
            }
            #endif
        } else {
            channelCount = 2
        }
        // 不在这里设置setPreferredOutputNumberOfChannels,因为这个方法会在获取音轨信息的时候，进行调用。
        KSLog("[audio] outputNumberOfChannels: \(AVAudioSession.sharedInstance().outputNumberOfChannels) output channelCount: \(channelCount)")
        return channelCount
    }
    #endif
}

public enum LogLevel: Int32, CustomStringConvertible {
    case panic = 0
    case fatal = 8
    case error = 16
    case warning = 24
    case info = 32
    case verbose = 40
    case debug = 48
    case trace = 56

    public var description: String {
        switch self {
        case .panic:
            return "panic"
        case .fatal:
            return "fault"
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info:
            return "info"
        case .verbose:
            return "verbose"
        case .debug:
            return "debug"
        case .trace:
            return "trace"
        }
    }
}

public extension LogLevel {
    var logType: OSLogType {
        switch self {
        case .panic, .fatal:
            return .fault
        case .error:
            return .error
        case .warning:
            return .debug
        case .info, .verbose, .debug:
            return .info
        case .trace:
            return .default
        }
    }
}

public protocol LogHandler {
    @inlinable
    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt)
}

public class OSLog: LogHandler {
    public let label: String
    public init(lable: String) {
        label = lable
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        os_log(level.logType, "%@ %@: %@:%d %@ | %@", level.description, label, file, line, function, message.description)
    }
}

public class FileLog: LogHandler {
    public let fileHandle: FileHandle
    public let formatter = DateFormatter()
    public init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        formatter.dateFormat = "MM-dd HH:mm:ss.SSSSSS"
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        let string = String(format: "%@ %@ %@:%d %@ | %@\n", formatter.string(from: Date()), level.description, file, line, function, message.description)
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

@inlinable
public func KSLog(_ error: @autoclosure () -> Error, file: String = #file, function: String = #function, line: UInt = #line) {
    KSLog(level: .error, error().localizedDescription, file: file, function: function, line: line)
}

@inlinable
public func KSLog(level: LogLevel = .warning, _ message: @autoclosure () -> CustomStringConvertible, file: String = #file, function: String = #function, line: UInt = #line) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        let fileName = (file as NSString).lastPathComponent
        KSOptions.logger.log(level: level, message: message(), file: fileName, function: function, line: line)
    }
}

@inlinable
public func KSLog(level: LogLevel = .warning, dso: UnsafeRawPointer = #dsohandle, _ message: StaticString, _ args: CVarArg...) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        os_log(level.logType, dso: dso, message, args)
    }
}

public extension Array {
    func toDictionary<Key: Hashable>(with selectKey: (Element) -> Key) -> [Key: Element] {
        var dict = [Key: Element]()
        forEach { element in
            dict[selectKey(element)] = element
        }
        return dict
    }
}

public struct KSClock {
    public private(set) var lastMediaTime = CACurrentMediaTime()
    public internal(set) var position = Int64(0)
    public internal(set) var time = CMTime.zero {
        didSet {
            lastMediaTime = CACurrentMediaTime()
        }
    }

    func getTime() -> TimeInterval {
        time.seconds + CACurrentMediaTime() - lastMediaTime
    }
}
