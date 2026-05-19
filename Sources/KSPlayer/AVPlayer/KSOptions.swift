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
    /// RE: KSOptions field #66, MTLBuffer? at 0x103B3CCA0 area. Passed to Metal render pipeline
    /// as fragment buffer for real-time BCS adjustment.
    public var adjustBuffer: MTLBuffer?
    /// First playable state timing metric
    public internal(set) var firstPlayableTime: Double = 0.0
    /// Spatial audio enabled for this session
    public var isSpatialAudioEnabled: Bool = false
    /// Audio engine type selection (0=AudioEngine, 1=AudioUnit, 2=AudioGraph, 3=AudioRenderer)
    public var audioEngineType: Int = 0

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
            // RE: classifyDynamicRange call on video track open (0x1012B0C44)
            // Classify dynamic range from the track's color transfer characteristic and Dolby Vision flag.
            if let ffmpegTrack = assetTrack as? FFmpegAssetTrack {
                let hasDovi = ffmpegTrack.dovi != nil
                let classified = KSOptions.classifyDynamicRange(colorTrc: ffmpegTrack.codecpar.color_trc, hasDovi: hasDovi)
                dynamicRange = classified
                if classified == .dolbyVision || classified == .hdr10 || classified == .hlg {
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
                var yadifMode = KSOptions.yadifMode
//                if let assetTrack = assetTrack as? FFmpegAssetTrack {
//                    if assetTrack.realFrameRate.num == 2 * assetTrack.avgFrameRate.num, assetTrack.realFrameRate.den == assetTrack.avgFrameRate.den {
//                        if yadifMode == 1 {
//                            yadifMode = 0
//                        } else if yadifMode == 3 {
//                            yadifMode = 2
//                        }
//                    }
//                }
                if KSOptions.deInterlaceAddIdet {
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
            if diff < -4 / fps {
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
        if let preferedDynamicRange = destinationDynamicRange {
            // value of 0 indicates that no HDR modes are supported.
            if availableHDRModes == AVPlayer.HDRMode(rawValue: 0) {
                return .sdr
            } else if availableHDRModes.contains(preferedDynamicRange.hdrMode) {
                return preferedDynamicRange
            } else if let contentRange,
                      availableHDRModes.contains(contentRange.hdrMode)
            {
                return contentRange
            } else if preferedDynamicRange != .sdr { // trying update to HDR mode
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

public extension KSOptions {
    /// Master flag for Dolby Vision enhanced decode path (ProAVPlayer routing).
    /// RE/76: DAT_104450978, AppStorage key "enhance_dolby".
    /// Set TRUE on player launch, FALSE on dismiss.
    static var enhanceDolby: Bool = false

    /// Classify dynamic range from FFmpeg transfer characteristics and Dolby Vision side data.
    /// RE binary address: 0x1012B0C44. Maps to Forward's compact DynamicRange scheme:
    ///   0=SDR, 1=HDR10(PQ), 2=HLG, 3=DolbyVision
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
