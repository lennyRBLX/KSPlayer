//
//  FFmpegUtility+Thumbnail.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17). The FILE NAME is read, not chosen: every
//  KSLog site below carries `#fileID` "KSPlayer/FFmpegUtility+Thumbnail.swift" (0x103d35950).
//  Holds `FFmpegUtility.formatCtx(ioContext:options:)` (#line 226-253) and `ThumbnailSession`
//  (#line 739-1257). The other thumbnail statics named by the trie (generateThumbnail(for:...),
//  generateThumbnailFromCache, generateThumbnailAtTime x2, streamThumbnail) are separate units.
//
import AVFoundation
import CoreGraphics
import CoreMedia
import DOVIRPUShim
import FFmpegKit
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Metal
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

extension FFmpegUtility {
    /// FUN_101a308c4. Trie: `static FFmpegUtility.formatCtx(ioContext:options:) throws ->
    /// UnsafeMutablePointer<AVFormatContext>`. Six `.verbose` KSLogs, #line 226/232/239/243/249/253.
    /// The `getContext(writable: false)` AVIO install is inlined at the call site (av_malloc +
    /// avio_alloc_context + AVClass store), and `opaque` (+0x1a0) is the unretained ioContext.
    /// The error string is built into a 256-element `[CChar]` BEFORE the log gate (it is released on
    /// the gated-off path), so it is a `let`, not part of the autoclosure.
    public static func formatCtx(ioContext: AbstractAVIOContext, options: KSOptions?) throws -> UnsafeMutablePointer<AVFormatContext> {
        KSLog(level: .verbose, "[Thumb] formatCtx(ioContext:) starting...")
        var formatCtx = avformat_alloc_context()
        if let formatCtx {
            formatCtx.pointee.opaque = Unmanaged.passUnretained(ioContext).toOpaque()
            formatCtx.pointee.pb = ioContext.getContext(writable: false)
        }
        var avOptions = options?.formatContextOptions.avOptions
        KSLog(level: .verbose, "[Thumb] calling avformat_open_input...")
        var result = avformat_open_input(&formatCtx, nil, nil, &avOptions)
        av_dict_free(&avOptions)
        guard result == 0 else {
            var buffer = [CChar](repeating: 0, count: 256)
            av_strerror(result, &buffer, 256)
            let message = String(cString: buffer)
            KSLog(level: .verbose, "[Thumb] avformat_open_input FAILED: \(result), \(message)")
            FFmpegUtility.close(formatCtx: formatCtx)
            throw KSPlayerError(code: result, description: KSPlayerErrorCode.formatOpenInput.rawValue)
        }
        KSLog(level: .verbose, "[Thumb] avformat_open_input OK, calling avformat_find_stream_info...")
        result = avformat_find_stream_info(formatCtx, nil)
        guard result == 0, let formatCtx else {
            var buffer = [CChar](repeating: 0, count: 256)
            av_strerror(result, &buffer, 256)
            let message = String(cString: buffer)
            KSLog(level: .verbose, "[Thumb] avformat_find_stream_info FAILED: \(result), \(message)")
            FFmpegUtility.close(formatCtx: formatCtx)
            throw KSPlayerError(code: result, description: KSPlayerErrorCode.formatFindStreamInfo.rawValue)
        }
        KSLog(level: .verbose, "[Thumb] formatCtx OK, streams=\(formatCtx.pointee.nb_streams)")
        return formatCtx
    }
    /// Forward 0x101a241f4. #function "generateThumbnail(for:options:thumbWidth:queue:progressBlock:)",
    /// #line 310. `queue.next()` and `FFThumbnail(cgImage:...)` are inlined; the codecpar unwrap for
    /// `createContext` precedes the option copy (0x101a2456c); the copy is inline, not a merged closure.
    /// A `transfer` throw leaves through the frame/close defers only (0x101a24f4c).
    public static func generateThumbnail(for p0: URL, options: KSOptions?, thumbWidth: Int32, queue: ThumbnailQueue, progressBlock: (FFThumbnail, Int) -> Void) throws {
        let interrupt = IOInterruptContext(nil)
        let (formatCtx, _, _) = try openFormatContext(io: .left(p0), interrupt: interrupt, options: options, inFormat: nil)
        defer {
            FFmpegUtility.close(formatCtx: formatCtx)
        }
        var videoStream: UnsafeMutablePointer<AVStream>?
        var videoStreamIndex = 0
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            if let stream = formatCtx.pointee.streams[i], stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                videoStream = stream
                break
            }
        }
        guard let videoStream else {
            throw KSPlayerError(code: 0, description: "No video stream")
        }
        let videoAvgFrameRate = videoStream.pointee.avg_frame_rate
        if videoAvgFrameRate.den == 0 || av_q2d(videoAvgFrameRate) == 0 {
            throw KSPlayerError(code: 0, description: "Avg frame rate = 0, ignore")
        }
        var frame = av_frame_alloc()
        defer {
            av_frame_free(&frame)
        }
        guard let frame else {
            throw KSPlayerError(code: 0, description: "can not av_frame_alloc")
        }
        let codecpar = videoStream.pointee.codecpar.pointee
        let thumbHeight = codecpar.width > 0 ? codecpar.height * thumbWidth / codecpar.width : thumbWidth * 9 / 16
        let assetTrack = FFmpegAssetTrack(stream: videoStream)
        _ = assetTrack?.isDovi
        let codecParameters: UnsafeMutablePointer<AVCodecParameters> = videoStream.pointee.codecpar
        var codecOptions: KSOptions?
        if let options {
            let copied = KSOptions()
            copied.decoderOptions = options.decoderOptions
            copied.lowres = options.lowres
            copied.videoSoftDecodeThreadCount = options.videoSoftDecodeThreadCount
            copied.hardwareDecode = false
            codecOptions = copied
        }
        let codecContext = try codecParameters.pointee.createContext(options: codecOptions)
        let reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, dstFormat: thumbnailPixelFormat(AVPixelFormat(rawValue: codecpar.format)), fps: 60, dovi: assetTrack?.dovi)
        let duration = av_rescale_q(formatCtx.pointee.duration, AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        let interval = duration / Int64(queue.count)
        var packet = AVPacket()
        let timeBase = Timebase(videoStream.pointee.time_base)
        while let index = queue.next() {
            let seekPosition = interval * Int64(index) + videoStream.pointee.start_time
            let seekStart = CACurrentMediaTime()
            let result = av_seek_frame(formatCtx, Int32(videoStreamIndex), seekPosition, AVSEEK_FLAG_BACKWARD)
            KSLog("generateThumbnail seek to \(seekPosition) index=\(index) spendTime=\(CACurrentMediaTime() - seekStart)", line: 310)
            guard result == 0 else {
                continue
            }
            avcodec_flush_buffers(codecContext)
            while av_read_frame(formatCtx, &packet) >= 0 {
                guard packet.stream_index == Int32(videoStreamIndex), packet.flags & AV_PKT_FLAG_KEY != 0 else {
                    continue
                }
                if avcodec_send_packet(codecContext, &packet) < 0 {
                    break
                }
                let ret = avcodec_receive_frame(codecContext, frame)
                if ret < 0 {
                    if ret == KSPlayerError.tryAgain.code {
                        continue
                    }
                    break
                }
                let currentTimeStamp = frame.pointee.best_effort_timestamp
                let thumbnail: FFThumbnail? = try autoreleasepool {
                    let pixelBuffer = try reScale.transfer(frame: frame.pointee)
                    guard var cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: assetTrack?.dovi) else {
                        return nil
                    }
                    if cgImage.width > Int(thumbWidth) {
                        cgImage = cgImage.resized(width: thumbWidth) ?? cgImage
                    }
                    return FFThumbnail(cgImage: cgImage, time: timeBase.cmtime(for: currentTimeStamp).seconds, preferCompressedStorage: true, compressionQuality: 0.72)
                }
                if let thumbnail {
                    progressBlock(thumbnail, index)
                }
                av_frame_unref(frame)
                break
            }
        }
        av_packet_unref(&packet)
        reScale.shutdown()
        var codecContextOption: UnsafeMutablePointer<AVCodecContext>? = codecContext
        avcodec_free_context(&codecContextOption)
    }
    /// Forward 0x101a250fc. #function "generateThumbnailFromCache(ioContext:options:thumbWidth:queue:progressBlock:)",
    /// `.verbose` logs at #line 436/475/499/503/514. Queue methods and `FFThumbnail(cgImage:...)` are
    /// inlined. A `transfer` throw unrefs the packet twice (loop-body defer, then function defer) and
    /// runs the shutdown/codec/frame/close defers (0x101a26a94).
    public static func generateThumbnailFromCache(ioContext: AbstractAVIOContext, options: KSOptions?, thumbWidth: Int32, queue: ThumbnailQueue, progressBlock: (FFThumbnail, Int) -> Void) throws -> Set<Int> {
        let formatCtx = try FFmpegUtility.formatCtx(ioContext: ioContext, options: options)
        defer {
            FFmpegUtility.close(formatCtx: formatCtx)
        }
        var videoStream: UnsafeMutablePointer<AVStream>?
        var videoStreamIndex = 0
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            if let stream = formatCtx.pointee.streams[i], stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                videoStream = stream
                break
            }
        }
        guard let videoStream else {
            throw KSPlayerError(code: 0, description: "No video stream")
        }
        let videoAvgFrameRate = videoStream.pointee.avg_frame_rate
        if videoAvgFrameRate.den == 0 || av_q2d(videoAvgFrameRate) == 0 {
            throw KSPlayerError(code: 0, description: "Avg frame rate = 0, ignore")
        }
        var frame = av_frame_alloc()
        defer {
            av_frame_free(&frame)
        }
        guard let frame else {
            throw KSPlayerError(code: 0, description: "can not av_frame_alloc")
        }
        let codecParameters: UnsafeMutablePointer<AVCodecParameters> = videoStream.pointee.codecpar
        var codecOptions: KSOptions?
        if let options {
            let copied = KSOptions()
            copied.decoderOptions = options.decoderOptions
            copied.lowres = options.lowres
            copied.videoSoftDecodeThreadCount = options.videoSoftDecodeThreadCount
            copied.hardwareDecode = false
            codecOptions = copied
        }
        let codecContext = try codecParameters.pointee.createContext(options: codecOptions)
        defer {
            var codecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&codecContext)
        }
        let codecpar = videoStream.pointee.codecpar.pointee
        let thumbHeight = codecpar.width > 0 ? codecpar.height * thumbWidth / codecpar.width : thumbWidth * 9 / 16
        let assetTrack = FFmpegAssetTrack(stream: videoStream)
        _ = assetTrack?.isDovi
        let reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, dstFormat: thumbnailPixelFormat(AVPixelFormat(rawValue: codecpar.format)), fps: 60, dovi: assetTrack?.dovi)
        defer {
            reScale.shutdown()
        }
        let duration = av_rescale_q(formatCtx.pointee.duration, AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        let interval = duration / Int64(queue.count)
        var packet = AVPacket()
        defer {
            av_packet_unref(&packet)
        }
        var cached = Set<Int>()
        let timeBase = Timebase(videoStream.pointee.time_base)
        queueLoop: while let index = queue.next() {
            let seekPosition = interval * Int64(index) + videoStream.pointee.start_time
            let ret = av_seek_frame(formatCtx, Int32(videoStreamIndex), seekPosition, AVSEEK_FLAG_BACKWARD)
            guard ret >= 0 else {
                KSLog(level: .verbose, "[Thumb] seek failed: index=\(index), error=\(ret)", line: 436)
                queue.putBack(index)
                continue
            }
            avcodec_flush_buffers(codecContext)
            var packetCount = 0
            while av_read_frame(formatCtx, &packet) >= 0, packetCount < 100 {
                defer {
                    av_packet_unref(&packet)
                }
                guard packet.stream_index == Int32(videoStreamIndex), packet.flags & AV_PKT_FLAG_KEY != 0 else {
                    continue
                }
                packetCount += 1
                guard avcodec_send_packet(codecContext, &packet) >= 0 else {
                    continue
                }
                while avcodec_receive_frame(codecContext, frame) >= 0 {
                    let pts = frame.pointee.best_effort_timestamp
                    let time = timeBase.cmtime(for: pts).seconds
                    KSLog(level: .verbose, "[Thumb] decoded frame: index=\(index), pts=\(pts), time=\(String(format: "%.2f", time))s, format=\(frame.pointee.format), size=\(frame.pointee.width)x\(frame.pointee.height)", line: 475)
                    let thumbnail: FFThumbnail? = try autoreleasepool {
                        let pixelBuffer = try reScale.transfer(frame: frame.pointee)
                        guard var cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: assetTrack?.dovi) else {
                            return nil
                        }
                        if cgImage.width > Int(thumbWidth) {
                            cgImage = cgImage.resized(width: thumbWidth) ?? cgImage
                        }
                        return FFThumbnail(cgImage: cgImage, time: time, preferCompressedStorage: true, compressionQuality: 0.72)
                    }
                    av_frame_unref(frame)
                    if let thumbnail {
                        progressBlock(thumbnail, index)
                        queue.markGenerated(index)
                        cached.insert(index)
                        KSLog(level: .verbose, "[Thumb] generated: index=\(index), time=\(String(format: "%.2f", time))s, packets=\(packetCount)", line: 499)
                        continue queueLoop
                    }
                    KSLog(level: .verbose, "[Thumb] cgImage failed: index=\(index)", line: 503)
                }
            }
            KSLog(level: .verbose, "[Thumb] no frame: index=\(index), packets=\(packetCount)", line: 514)
            queue.putBack(index)
        }
        return cached
    }
    public static func generateThumbnailAtTime(ioContext: AbstractAVIOContext, time: Double, options: KSOptions?, thumbWidth: Int32) -> FFThumbnail? {
        do {
            let formatCtx = try FFmpegUtility.formatCtx(ioContext: ioContext, options: options)
            let thumbnail = generateThumbnailAtTime(formatCtx: formatCtx, time: time, thumbWidth: thumbWidth)
            FFmpegUtility.close(formatCtx: formatCtx)
            return thumbnail
        } catch {
            KSLog("generateThumbnailAtTime: failed to create formatCtx: \(error)", line: 541)
            return nil
        }
    }
    /// Forward 0x101a26d94 is a 1-insn thunk to 0x101a3132c (#function
    /// "generateThumbnailAtTime(formatCtx:time:thumbWidth:)", #line 594). First video stream only;
    /// VideoSwresample init is inlined. `isDovi` is evaluated and discarded (0x101a23760).
    public static func generateThumbnailAtTime(formatCtx: UnsafeMutablePointer<AVFormatContext>, time: Double, thumbWidth: Int32) -> FFThumbnail? {
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            guard let stream = formatCtx.pointee.streams[i], stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO else {
                continue
            }
            guard let codecContext = try? stream.pointee.codecpar.pointee.createContext(options: nil) else {
                return nil
            }
            defer {
                var codecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
                avcodec_free_context(&codecContext)
            }
            let codecpar = stream.pointee.codecpar.pointee
            var frame = av_frame_alloc()
            defer {
                av_frame_free(&frame)
            }
            guard let frame else {
                return nil
            }
            let thumbHeight = codecpar.width > 0 ? thumbWidth * codecpar.height / codecpar.width : thumbWidth * 9 / 16
            let assetTrack = FFmpegAssetTrack(stream: stream)
            _ = assetTrack?.isDovi
            let reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, dstFormat: thumbnailPixelFormat(AVPixelFormat(rawValue: codecpar.format)), fps: 60, dovi: assetTrack?.dovi)
            defer {
                reScale.shutdown()
            }
            let timestamp = av_rescale_q(Int64(time * 1_000_000), AVRational(num: 1, den: 1_000_000), stream.pointee.time_base)
            let timeBase = Timebase(stream.pointee.time_base)
            let ret = av_seek_frame(formatCtx, Int32(i), timestamp, AVSEEK_FLAG_BACKWARD)
            guard ret >= 0 else {
                KSLog("generateThumbnailAtTime: seek failed at time \(time), error: \(ret)", line: 594)
                return nil
            }
            avcodec_flush_buffers(codecContext)
            var packet = AVPacket()
            defer {
                av_packet_unref(&packet)
            }
            while av_read_frame(formatCtx, &packet) >= 0 {
                guard packet.stream_index == Int32(i) else {
                    av_packet_unref(&packet)
                    continue
                }
                guard avcodec_send_packet(codecContext, &packet) >= 0 else {
                    av_packet_unref(&packet)
                    break
                }
                let result = avcodec_receive_frame(codecContext, frame)
                if result < 0 {
                    if result == KSPlayerError.tryAgain.code {
                        av_packet_unref(&packet)
                        continue
                    }
                    av_packet_unref(&packet)
                    break
                }
                av_packet_unref(&packet)
                let frameTime = timeBase.cmtime(for: frame.pointee.best_effort_timestamp).seconds
                let thumbnail: FFThumbnail? = autoreleasepool {
                    guard let pixelBuffer = try? reScale.transfer(frame: frame.pointee),
                          let cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: assetTrack?.dovi)
                    else {
                        return nil
                    }
                    let image = cgImage.width > Int(thumbWidth) ? cgImage.resized(width: thumbWidth) ?? cgImage : cgImage
                    return FFThumbnail(image: UIImage(cgImage: image), time: frameTime)
                }
                guard let thumbnail else {
                    av_frame_unref(frame)
                    break
                }
                av_frame_unref(frame)
                return thumbnail
            }
            return nil
        }
        return nil
    }
}

/// Forward-added type (descriptor + 6 vtable methods in the trie). Field order is the memory order
/// read from the init (FUN_101a26e58): +0x10 formatCtx, +0x18 codecContext, +0x20 frame, +0x28 reScale,
/// +0x30 videoStreamIndex, +0x38 timeBase, +0x40 thumbWidth, +0x48 interval, +0x50 startTime,
/// +0x58 count, +0x60 intervalSeconds, +0x68 isHDR, +0x69 hasDovi, +0x6a dovi, +0x78
/// indexedSeekPositions, +0x80 isCachedAtCurrentPosition, +0x90 isInterrupted, +0x91 isClosed.
/// `private` on the five vars is proven by the discriminated `vpfi` symbols
/// (`33_6396B00CDA13DAF3ED3725123AA55DD0LL`); `public` on the getters with property descriptors.
/// Access of videoStreamIndex/timeBase/thumbWidth/isHDR/dovi/indexedSeekPositions is inferred
/// (no export-trie symbol ⇒ not public).
public class ThumbnailSession {
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
    private var codecContext: UnsafeMutablePointer<AVCodecContext>? = nil
    private var frame: UnsafeMutablePointer<AVFrame>? = nil
    private var reScale: VideoSwresample? = nil
    let videoStreamIndex: Int
    let timeBase: Timebase
    let thumbWidth: Int32
    public let interval: Int64
    public let startTime: Int64
    public let count: Int
    public let intervalSeconds: Double
    let isHDR: Bool
    public let hasDovi: Bool
    let dovi: DOVIDecoderConfigurationRecord?
    let indexedSeekPositions: [Int64]?
    public var isCachedAtCurrentPosition: (() -> Bool)? = nil
    public var isInterrupted: Bool = false
    private var isClosed = false

    /// FUN_101a26e58 (allocating entry FUN_101a26dec). Every throw closes the format context first
    /// (FFmpegUtility.close(formatCtx:) at 0x101a26f34/f80/271d4/27278).
    public init(ioContext: AbstractAVIOContext, options: KSOptions?, thumbWidth: Int32, count: Int) throws {
        self.thumbWidth = thumbWidth
        self.count = count
        let formatCtx = try FFmpegUtility.formatCtx(ioContext: ioContext, options: options)
        self.formatCtx = formatCtx
        var videoStream: UnsafeMutablePointer<AVStream>?
        var streamIndex = 0
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            if let stream = formatCtx.pointee.streams[i], stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                streamIndex = i
                videoStream = stream
                break
            }
        }
        guard let videoStream else {
            FFmpegUtility.close(formatCtx: formatCtx)
            throw KSPlayerError(code: 0, description: "No video stream")
        }
        videoStreamIndex = streamIndex
        let avgFrameRate = videoStream.pointee.avg_frame_rate
        if avgFrameRate.den == 0 || av_q2d(avgFrameRate) == 0 {
            FFmpegUtility.close(formatCtx: formatCtx)
            throw KSPlayerError(code: 0, description: "Avg frame rate = 0, ignore")
        }
        // A fresh KSOptions carrying only the decoder knobs, with hardware decode forced off. Forward
        // unwraps codecpar (0x101a27038) before the option copy, so the copy is the argument expression.
        let codecContext: UnsafeMutablePointer<AVCodecContext>
        do {
            codecContext = try videoStream.pointee.codecpar.pointee.createContext(options: options.map { options in
                let copied = KSOptions()
                copied.decoderOptions = options.decoderOptions
                copied.lowres = options.lowres
                copied.videoSoftDecodeThreadCount = options.videoSoftDecodeThreadCount
                copied.hardwareDecode = false
                return copied
            })
        } catch {
            FFmpegUtility.close(formatCtx: formatCtx)
            throw error
        }
        self.codecContext = codecContext
        guard let frame = av_frame_alloc() else {
            var codecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&codecContext)
            FFmpegUtility.close(formatCtx: formatCtx)
            throw KSPlayerError(code: 0, description: "can not av_frame_alloc")
        }
        self.frame = frame
        let codecpar = videoStream.pointee.codecpar.pointee
        let format = codecpar.format
        let width = codecpar.width
        let colorTrc = codecpar.color_trc
        let thumbHeight = width > 0 ? codecpar.height * thumbWidth / width : thumbWidth * 9 / 16
        // FUN_101a211ec = FFmpegAssetTrack(stream:); FUN_101a23760 = its `isDovi` specialisation.
        let assetTrack = FFmpegAssetTrack(stream: videoStream)
        let hasDovi = assetTrack?.isDovi ?? false
        self.hasDovi = hasDovi
        dovi = assetTrack?.dovi
        isHDR = hasDovi || colorTrc == AVCOL_TRC_SMPTE2084 || colorTrc == AVCOL_TRC_ARIB_STD_B67
        KSLog("[Thumb] HDR检测: isHDR=\(isHDR), color_trc=\(colorTrc.rawValue), hasDovi=\(hasDovi)", line: 739)
        reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, dstFormat: thumbnailPixelFormat(AVPixelFormat(rawValue: format)), fps: 60, dovi: assetTrack?.dovi)
        let duration = av_rescale_q(formatCtx.pointee.duration, AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        interval = duration / Int64(count)
        startTime = videoStream.pointee.start_time
        timeBase = Timebase(videoStream.pointee.time_base)
        intervalSeconds = Double(formatCtx.pointee.duration) / 1_000_000 / Double(count)
        indexedSeekPositions = ThumbnailSession.buildIndexedSeekPositions(videoStream: videoStream, count: count)
        KSLog(level: .verbose, "[Thumb] init done, duration=\(duration), interval=\(interval), intervalSeconds=\(intervalSeconds), count=\(count), isHDR=\(isHDR), indexedSeek=\(indexedSeekPositions != nil)", line: 760)
    }

    /// FUN_101a31bd0. #function "buildIndexedSeekPositions(videoStream:count:)", #line 783/795.
    /// Static-vs-free placement inferred (no self, no trie symbol).
    private static func buildIndexedSeekPositions(videoStream: UnsafeMutablePointer<AVStream>, count: Int) -> [Int64]? {
        let entriesCount = avformat_index_get_entries_count(videoStream)
        guard entriesCount > 0 else {
            return nil
        }
        var keyframeTimestamps = [Int64]()
        keyframeTimestamps.reserveCapacity(Int(entriesCount))
        for i in 0 ..< entriesCount {
            if let entry = avformat_index_get_entry(videoStream, i), entry.pointee.flags & AVINDEX_KEYFRAME != 0 {
                keyframeTimestamps.append(entry.pointee.timestamp)
            }
        }
        guard keyframeTimestamps.count >= count else {
            KSLog("[Thumb] 关键帧数(\(keyframeTimestamps.count))少于所需缩略图数(\(count))，使用均匀插值")
            return nil
        }
        var positions = [Int64]()
        positions.reserveCapacity(count)
        for i in 0 ..< count {
            let index = min(Int(Double(keyframeTimestamps.count) * Double(i) / Double(count)), keyframeTimestamps.count - 1)
            positions.append(keyframeTimestamps[index])
        }
        KSLog("[Thumb] 关键帧索引就绪: 共\(keyframeTimestamps.count)个关键帧，均匀采样\(count)个，精确 seek 已启用")
        return positions
    }

    /// deinit @0x101a27aac: `close()` then the stored-property releases.
    deinit {
        close()
    }

    /// FUN_101a27b14, vtable. `reScale?.shutdown()` is inlined (sws_freeContext + nil).
    public func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        reScale?.shutdown()
        reScale = nil
        av_frame_free(&frame)
        avcodec_free_context(&codecContext)
        if formatCtx != nil {
            FFmpegUtility.close(formatCtx: formatCtx)
            formatCtx = nil
        }
        KSLog(level: .verbose, "[Thumb] closed", line: 821)
    }

    /// FUN_101a27d00, vtable. #function "generateThumbnail(at:)", #line 847-947.
    public func generateThumbnail(at index: Int) -> FFThumbnail? {
        guard let frame, let codecContext, let formatCtx, let reScale else {
            return nil
        }
        let seekPosition: Int64
        let targetTime: Double
        if let indexedSeekPositions, index < indexedSeekPositions.count {
            seekPosition = indexedSeekPositions[index]
            targetTime = timeBase.cmtime(for: seekPosition).seconds
        } else {
            seekPosition = interval * Int64(index) + startTime
            targetTime = intervalSeconds * Double(index)
        }
        let seekStart = CACurrentMediaTime()
        let seekResult = av_seek_frame(formatCtx, Int32(videoStreamIndex), seekPosition, AVSEEK_FLAG_BACKWARD)
        let seekEnd = CACurrentMediaTime()
        guard seekResult >= 0 else {
            KSLog(level: .verbose, "[Thumb] seek failed: index=\(index), error=\(seekResult)", line: 847)
            return nil
        }
        if let isCachedAtCurrentPosition, !isCachedAtCurrentPosition() {
            KSLog(level: .verbose, "[Thumb] no cache at current position: index=\(index), skipping", line: 853)
            return nil
        }
        avcodec_flush_buffers(codecContext)
        var packet = AVPacket()
        defer {
            av_packet_unref(&packet)
        }
        let tolerance = indexedSeekPositions == nil ? 2.0 : 0.6
        let maxDiff = intervalSeconds * tolerance
        var packetCount = 0
        let seekTime = (seekEnd - seekStart) * 1000
        var readTime = 0.0
        var readStart = CACurrentMediaTime()
        var ret = av_read_frame(formatCtx, &packet)
        while ret >= 0, packetCount < 100 {
            readTime += (CACurrentMediaTime() - readStart) * 1000
            if packet.stream_index == Int32(videoStreamIndex), packet.flags & AV_PKT_FLAG_KEY != 0 {
                packetCount += 1
                let decodeStart = CACurrentMediaTime()
                if avcodec_send_packet(codecContext, &packet) >= 0 {
                    while avcodec_receive_frame(codecContext, frame) >= 0 {
                        let decodeEnd = CACurrentMediaTime()
                        let frameTime = timeBase.cmtime(for: frame.pointee.best_effort_timestamp).seconds
                        let diff = abs(frameTime - targetTime)
                        guard diff <= maxDiff else {
                            KSLog(level: .verbose, "[Thumb] frame time too far from target: index=\(index), target=\(String(format: "%.2f", targetTime))s, actual=\(String(format: "%.2f", frameTime))s, diff=\(String(format: "%.2f", abs(frameTime - targetTime)))s, skipping", line: 906)
                            av_frame_unref(frame)
                            continue
                        }
                        let convertStart = CACurrentMediaTime()
                        let thumbnail: FFThumbnail? = autoreleasepool {
                            do {
                                let pixelBuffer = try reScale.transfer(frame: frame.pointee)
                                guard var cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: dovi) else {
                                    return nil
                                }
                                if cgImage.width > Int(thumbWidth) {
                                    KSLog("[Thumb] resize needed: cgImage.width=\(cgImage.width), thumbWidth=\(thumbWidth)", line: 921)
                                    cgImage = cgImage.resized(width: thumbWidth) ?? cgImage
                                }
                                return ThumbnailSession.makeThumbnail(cgImage: cgImage, time: frameTime)
                            } catch {
                                KSLog(level: .verbose, "[Thumb] reScale.transfer failed: \(error)", line: 929)
                                return nil
                            }
                        }
                        guard let thumbnail else {
                            av_frame_unref(frame)
                            continue
                        }
                        let convertEnd = CACurrentMediaTime()
                        av_frame_unref(frame)
                        let decodeTime = (decodeEnd - decodeStart) * 1000
                        let convertTime = (convertEnd - convertStart) * 1000
                        KSLog("[Thumb] #\(index) seek=\(String(format: "%.1f", seekTime))ms, read=\(String(format: "%.1f", readTime))ms, 解码=\(String(format: "%.1f", decodeTime))ms, 转换=\(String(format: "%.1f", convertTime))ms, 总计=\(String(format: "%.1f", seekTime + readTime + decodeTime + convertTime))ms, packets=\(packetCount)", line: 939)
                        av_packet_unref(&packet)
                        return thumbnail
                    }
                    readStart = CACurrentMediaTime()
                }
            }
            av_packet_unref(&packet)
            ret = av_read_frame(formatCtx, &packet)
        }
        KSLog(level: .verbose, "[Thumb] no frame: index=\(index), packets=\(packetCount)", line: 947)
        return nil
    }

    /// FUN_101a29690, vtable. #function "generateThumbnail(at:)", #line 969-1065.
    /// Keeps the frame closest to `time`; stops once a frame reaches `time` or a second keyframe
    /// has been decoded (`fcmp time,frameTime; ccmp count,#1,#0,hi; b.ge`).
    public func generateThumbnail(at time: Double) -> FFThumbnail? {
        guard let frame, let codecContext, let formatCtx, let reScale, let stream = formatCtx.pointee.streams[videoStreamIndex] else {
            return nil
        }
        let time = max(0, time)
        let seekTarget = av_rescale_q(Int64(time * 1_000_000), AVRational(num: 1, den: 1_000_000), stream.pointee.time_base)
        let seekStart = CACurrentMediaTime()
        let seekResult = av_seek_frame(formatCtx, Int32(videoStreamIndex), seekTarget, AVSEEK_FLAG_BACKWARD)
        let seekEnd = CACurrentMediaTime()
        guard seekResult >= 0 else {
            KSLog(level: .verbose, "[Thumb] preview seek failed: time=\(String(format: "%.2f", time))s, error=\(seekResult)", line: 969)
            return nil
        }
        if let isCachedAtCurrentPosition, !isCachedAtCurrentPosition() {
            KSLog(level: .verbose, "[Thumb] preview no cache at current position: time=\(String(format: "%.2f", time))s", line: 974)
            return nil
        }
        avcodec_flush_buffers(codecContext)
        var packet = AVPacket()
        defer {
            av_packet_unref(&packet)
        }
        var packetCount = 0
        let seekTime = (seekEnd - seekStart) * 1000
        var readTime = 0.0
        var bestDiff = Double.greatestFiniteMagnitude
        var best: FFThumbnail?
        var bestTime = time
        var readStart = CACurrentMediaTime()
        var ret = av_read_frame(formatCtx, &packet)
        while ret >= 0, packetCount < 160 {
            readTime += (CACurrentMediaTime() - readStart) * 1000
            if packet.stream_index == Int32(videoStreamIndex), packet.flags & AV_PKT_FLAG_KEY != 0 {
                packetCount += 1
                let decodeStart = CACurrentMediaTime()
                if avcodec_send_packet(codecContext, &packet) >= 0 {
                    while avcodec_receive_frame(codecContext, frame) >= 0 {
                        let decodeEnd = CACurrentMediaTime()
                        let frameTime = timeBase.cmtime(for: frame.pointee.best_effort_timestamp).seconds
                        let convertStart = CACurrentMediaTime()
                        let thumbnail: FFThumbnail? = autoreleasepool {
                            do {
                                let pixelBuffer = try reScale.transfer(frame: frame.pointee)
                                guard var cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: dovi) else {
                                    return nil
                                }
                                if cgImage.width > Int(thumbWidth) {
                                    cgImage = cgImage.resized(width: thumbWidth) ?? cgImage
                                }
                                if let data = cgImage.data(type: .jpg, quality: 0.72) {
                                    return FFThumbnail(jpegData: data, time: frameTime)
                                }
                                if let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                                    if let image = context.makeImage(), let data = image.data(type: .jpg, quality: 0.72) {
                                        return FFThumbnail(jpegData: data, time: frameTime)
                                    }
                                }
                                return FFThumbnail(image: UIImage(cgImage: cgImage), time: frameTime)
                            } catch {
                                KSLog(level: .verbose, "[Thumb] preview reScale.transfer failed: \(error)", line: 1037)
                                return nil
                            }
                        }
                        let convertEnd = CACurrentMediaTime()
                        av_frame_unref(frame)
                        if let thumbnail, abs(frameTime - time) < bestDiff {
                            best = thumbnail
                            bestDiff = abs(frameTime - time)
                            bestTime = frameTime
                        }
                        guard frameTime < time, packetCount < 2 else {
                            if best != nil {
                                let decodeTime = (decodeEnd - decodeStart) * 1000
                                let convertTime = (convertEnd - convertStart) * 1000
                                KSLog("[Thumb] preview target=\(String(format: "%.2f", time))s, actual=\(String(format: "%.2f", bestTime))s, seek=\(String(format: "%.1f", seekTime))ms, read=\(String(format: "%.1f", readTime))ms, 解码=\(String(format: "%.1f", decodeTime))ms, 转换=\(String(format: "%.1f", convertTime))ms, 总计=\(String(format: "%.1f", seekTime + readTime + decodeTime + convertTime))ms, keyframes=\(packetCount)", line: 1053)
                            }
                            av_packet_unref(&packet)
                            return best
                        }
                    }
                    readStart = CACurrentMediaTime()
                }
            }
            av_packet_unref(&packet)
            ret = av_read_frame(formatCtx, &packet)
        }
        if let best {
            KSLog(level: .verbose, "[Thumb] preview fallback target=\(String(format: "%.2f", time))s, actual=\(String(format: "%.2f", bestTime))s, keyframes=\(packetCount)", line: 1063)
            return best
        }
        KSLog(level: .verbose, "[Thumb] preview no frame: target=\(String(format: "%.2f", time))s, packets=\(packetCount)", line: 1065)
        return nil
    }

    /// Identical-code-folded with `generateThumbnail(at: Int)`: `minInterval` is unused.
    public func generateThumbnail(at index: Int, minInterval _: Double) -> FFThumbnail? {
        generateThumbnail(at: index)
    }

    /// FUN_101a2b040, vtable. #function "generateSequentially(from:to:needSeek:onThumbnail:)",
    /// #line 1096-1257. Decodes keyframes forward from `from`, handing each new index to
    /// `onThumbnail`; returns the last index reached. `iFrames` is kept in lock-step with `decoded`
    /// (the binary folds them into one register).
    public func generateSequentially(from startIndex: Int, to maxIndex: Int, needSeek: Bool, onThumbnail: (FFThumbnail, Int) -> Bool) -> Int {
        guard let frame, let codecContext, let formatCtx, let reScale else {
            return startIndex
        }
        KSLog(level: .verbose, "[Thumb] generateSequentially: start=\(startIndex), max=\(maxIndex), needSeek=\(needSeek)", line: 1096)
        if needSeek {
            let seekPosition = interval * Int64(startIndex) + startTime
            let ret = av_seek_frame(formatCtx, Int32(videoStreamIndex), seekPosition, AVSEEK_FLAG_BACKWARD)
            if ret < 0 {
                KSLog(level: .verbose, "[Thumb] initial seek failed: index=\(startIndex), error=\(ret)", line: 1105)
                return startIndex
            }
            avcodec_flush_buffers(codecContext)
        }
        var packet = AVPacket()
        defer {
            av_packet_unref(&packet)
        }
        var index = startIndex
        var lastSavedIndex = -1
        var packets = 0
        var videoPackets = 0
        var keyframes = 0
        var decoded = 0
        var iFrames = 0
        var saved = 0
        var endReason = ""
        while !isInterrupted, index <= maxIndex {
            var readFailed = false
            let stopIndex: Int? = autoreleasepool {
                let ret = av_read_frame(formatCtx, &packet)
                if ret < 0 {
                    if ret == AVError.eof.code {
                        endReason = "EOF"
                    } else if ret == -EIO {
                        endReason = "EIO(缓存未命中)"
                    } else {
                        var buffer = [CChar](repeating: 0, count: 256)
                        av_strerror(ret, &buffer, 256)
                        endReason = "error(\(ret)): \(String(cString: buffer))"
                    }
                    KSLog(level: .verbose, "[Thumb] av_read_frame failed: \(endReason), idx=\(index), packets=\(packets)", line: 1143)
                    readFailed = true
                    return nil
                }
                packets += 1
                guard packet.stream_index == Int32(videoStreamIndex) else {
                    av_packet_unref(&packet)
                    return nil
                }
                videoPackets += 1
                guard packet.flags & AV_PKT_FLAG_KEY != 0 else {
                    av_packet_unref(&packet)
                    return nil
                }
                keyframes += 1
                let pts = packet.pts < 0 ? packet.dts : packet.pts
                if pts >= 0, Int(timeBase.cmtime(for: pts).seconds / intervalSeconds) <= lastSavedIndex {
                    av_packet_unref(&packet)
                    return nil
                }
                let decodeStart = CACurrentMediaTime()
                guard avcodec_send_packet(codecContext, &packet) >= 0, avcodec_receive_frame(codecContext, frame) >= 0 else {
                    av_packet_unref(&packet)
                    return nil
                }
                let decodeEnd = CACurrentMediaTime()
                decoded += 1
                iFrames += 1
                let frameTime = timeBase.cmtime(for: frame.pointee.best_effort_timestamp).seconds
                let frameIndex = Int(frameTime / intervalSeconds)
                if frameIndex > maxIndex {
                    KSLog(level: .verbose, "[Thumb] reached maxIndex: frameIndex=\(frameIndex), maxIndex=\(maxIndex)", line: 1200)
                    av_packet_unref(&packet)
                    return frameIndex
                }
                let convertStart = CACurrentMediaTime()
                let thumbnail: FFThumbnail? = autoreleasepool {
                    do {
                        let pixelBuffer = try reScale.transfer(frame: frame.pointee)
                        guard var cgImage = thumbnailImage(frame: frame.pointee, pixelBuffer: pixelBuffer, dovi: dovi) else {
                            KSLog(level: .verbose, "[Thumb] cgImage() failed at index=\(frameIndex)", line: 1216)
                            return nil
                        }
                        if cgImage.width > Int(thumbWidth) {
                            cgImage = cgImage.resized(width: thumbWidth) ?? cgImage
                        }
                        return ThumbnailSession.makeThumbnail(cgImage: cgImage, time: frameTime)
                    } catch {
                        KSLog(level: .verbose, "[Thumb] reScale.transfer failed: \(error)", line: 1219)
                        return nil
                    }
                }
                guard let thumbnail else {
                    av_frame_unref(frame)
                    av_packet_unref(&packet)
                    return nil
                }
                let convertEnd = CACurrentMediaTime()
                av_frame_unref(frame)
                let decodeTime = (decodeEnd - decodeStart) * 1000
                let convertTime = (convertEnd - convertStart) * 1000
                KSLog("[Thumb] #\(frameIndex) 解码=\(String(format: "%.1f", decodeTime))ms, 转换=\(String(format: "%.1f", convertTime))ms, 总计=\(String(format: "%.1f", decodeTime + convertTime))ms", line: 1233)
                saved += 1
                guard onThumbnail(thumbnail, frameIndex) else {
                    KSLog(level: .verbose, "[Thumb] stopped by callback at index=\(frameIndex)", line: 1242)
                    av_packet_unref(&packet)
                    return frameIndex
                }
                av_packet_unref(&packet)
                lastSavedIndex = frameIndex
                index = frameIndex
                return nil
            }
            if let stopIndex {
                return stopIndex
            }
            if readFailed {
                break
            }
        }
        KSLog(level: .debug, "[Thumb] generateSequentially done: lastIndex=\(index), saved=\(saved), packets=\(packets), videoPackets=\(videoPackets), keyframes=\(keyframes), decoded=\(decoded), iFrames=\(iFrames), endReason=\(endReason)", line: 1257)
        return index
    }

    /// The JPEG-or-fallback tail shared by all three generators (inlined at every site; name
    /// inferred). JPEG at quality 0.72 (0x3fe70a3d70a3d70a); if encoding fails, redraw into an
    /// 8-bit RGBX context and retry; last resort is an in-memory UIImage.
    private static func makeThumbnail(cgImage: CGImage, time: TimeInterval) -> FFThumbnail {
        if let data = cgImage.data(type: .jpg, quality: 0.72) {
            return FFThumbnail(jpegData: data, time: time)
        }
        if let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            if let image = context.makeImage(), let data = image.data(type: .jpg, quality: 0.72) {
                return FFThumbnail(jpegData: data, time: time)
            }
        }
        return FFThumbnail(image: UIImage(cgImage: cgImage), time: time)
    }
}

extension CGImage {
    /// FUN_101a24fb0 (out of line; 3 callers, inlined in the two generateThumbnail(at:) bodies).
    /// Name inferred. Scales down to `width` keeping aspect; returns self when already narrow enough.
    func resized(width: Int32) -> CGImage? {
        let originalWidth = self.width
        let originalHeight = height
        guard Int(width) < originalWidth else {
            return self
        }
        let newHeight = Int(Double(width) * Double(originalHeight) / Double(originalWidth))
        guard let context = CGContext(data: nil, width: Int(width), height: newHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: Double(width), height: Double(newHeight)))
        return context.makeImage()
    }
}

/// FUN_101a2fe34. `bestPixelFormat` with a different alpha arm: RGB+alpha → BGRA (28), other alpha →
/// AYUV64LE (155). Name inferred.
private func thumbnailPixelFormat(_ format: AVPixelFormat) -> AVPixelFormat {
    guard let desc = av_pix_fmt_desc_get(format) else {
        return AV_PIX_FMT_NV12
    }
    if desc.pointee.flags & UInt64(AV_PIX_FMT_FLAG_ALPHA) != 0 {
        return desc.pointee.flags & UInt64(AV_PIX_FMT_FLAG_RGB) != 0 ? AV_PIX_FMT_BGRA : AV_PIX_FMT_AYUV64LE
    }
    let depth = desc.pointee.comp.0.depth
    if depth > 10 {
        return desc.pointee.log2_chroma_w == 0 ? AV_PIX_FMT_P416LE : AV_PIX_FMT_P216LE
    }
    if desc.pointee.log2_chroma_w == 0 {
        return depth <= 8 ? AV_PIX_FMT_NV24 : AV_PIX_FMT_P410LE
    }
    if desc.pointee.log2_chroma_h == 0 {
        return depth <= 8 ? AV_PIX_FMT_NV16 : AV_PIX_FMT_P210LE
    }
    return depth <= 8 ? AV_PIX_FMT_NV12 : AV_PIX_FMT_P010LE
}

/// FUN_101a2fedc. The frame's AV_FRAME_DATA_DOVI_METADATA side data, converted. Name inferred.
private func doviMetadata(frame: AVFrame) -> KSDOVIMetadata? {
    for i in 0 ..< Int(frame.nb_side_data) {
        if let sideData = frame.side_data[i], sideData.pointee.type == AV_FRAME_DATA_DOVI_METADATA {
            return sideData.pointee.data.withMemoryRebound(to: AVDOVIMetadata.self, capacity: 1) {
                convertAVDOVIToKSDOVIMetadata($0)
            }
        }
    }
    return nil
}

/// FUN_101a306bc. With Dolby Vision RPU metadata on a bi-planar buffer, render through the DV
/// pipeline; otherwise the buffer's own `cgImage()`. Name inferred.
private func thumbnailImage(frame: AVFrame, pixelBuffer: PixelBufferProtocol, dovi: DOVIDecoderConfigurationRecord?) -> CGImage? {
    if let doviData = doviMetadata(frame: frame), pixelBuffer.planeCount > 1 {
        let vtbFrame = VideoVTBFrame(pixelBuffer: pixelBuffer, fps: 60, isKeyFrame: frame.flags & AV_FRAME_FLAG_KEY != 0, dovi: dovi, edrMetaData: nil, doviData: doviData, rpuBuffer: nil)
        pixelBuffer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
        return renderThumbnail(frame: vtbFrame)
    }
    return pixelBuffer.cgImage()
}

/// FUN_101a2ffa4. Name inferred.
private func renderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = texture
    descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store
    return descriptor
}

/// FUN_101a300f8. Offscreen BGRA render of a DV frame, read back into a PQ CGImage. Name inferred.
/// ⚑ GAP: between the texture binds and `endEncoding` Forward draws with
///   `ThumbnailDoviDisplayModel.shared.set(frame:encoder:)` (swift_once 0x101a2381c → global
///   0x1044e9a90; override 0x101a23858). That class is still a skeleton and its `set` override is a
///   separate, unreconstructed unit (it needs the DV shader-source builder 0x101a82044 shared with
///   DoviDisplayModel.set 0x101a825b4, and PlaneDisplayModel is @MainActor), so the draw is omitted
///   and the readback yields the cleared target.
private func renderThumbnail(frame: VideoVTBFrame) -> CGImage? {
    let pixelBuffer = frame.pixelBuffer
    let width = pixelBuffer.width
    let height = pixelBuffer.height
    guard width > 0, height > 0 else {
        return nil
    }
    let device = MetalRender.device
    guard let commandQueue = device.makeCommandQueue(), let commandBuffer = commandQueue.makeCommandBuffer() else {
        return nil
    }
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    textureDescriptor.usage = .renderTarget
    guard let texture = device.makeTexture(descriptor: textureDescriptor),
          let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor(texture: texture))
    else {
        return nil
    }
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    encoder.setFragmentSamplerState(device.makeSamplerState(descriptor: samplerDescriptor), index: 0)
    for (index, texture) in pixelBuffer.textures().enumerated() {
        encoder.setFragmentTexture(texture, index: index)
    }
    encoder.endEncoding()
    let bytesPerRow = width * 4
    let length = bytesPerRow * height
    guard let buffer = device.makeBuffer(length: length, options: []), let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
        return nil
    }
    blitEncoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
    blitEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let textureCache = MetalRender.mtlTextureCache {
        CVMetalTextureCacheFlush(textureCache, 0)
    }
    let data = Data(bytes: buffer.contents(), count: length)
    let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
    guard let provider = CGDataProvider(data: data as CFData) else {
        return nil
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

// ThumbnailDoviDisplayModel — Forward 1.3.17 reconstruction skeleton. Bodies: Phase 3 (DV).
// No-anchor class (novtable-new): no walkable vtable, no __text witness →
// methods recovered by instantiation-site dataflow.
// Binary provenance (Forward-1.3.17):
//   descriptor 0x1039ef224 · metadata accessor 0x101a3227c · novtable · stored fields 6
//   init  @ 0x101a2400c   (alloc size 0x70 / 112 bytes)
//   dataflow_recover.py: 1 corroborated (init) · 0 flagged
//   → reconstruction/dataflow_ThumbnailDoviDisplayModel.json
// ⚑[tool=field_surface ref=ThumbnailDoviDisplayModel:fieldmd result=6 fields @0x40..0x68 size 0x70]
// Superclass PlaneDisplayModel (descriptor superclass; its InstanceSize 0x39 rounds to the first
// field at 0x40). Every value below is read from the init at 0x101a2400c:
//   +0x40/+0x48 — 0x101a83020 (MTLLibrary.makePipelineState) with x0/x1 = "mapTexture",
//     x2/x3 = 19 bytes at 0x103d35fc0 "displayICtCpTexture" / 27 bytes at 0x103d35fa0
//     "displayICtCpBiPlanarTexture", w4 = 8 (the default bitDepth).
//   +0x50 — NSLock class ref 0x104410560 alloc+init; +0x58 — `mov w8, #4`.
//   +0x60/+0x68 — __got 0x104112d08 / 0x104112d00, the empty Dictionary / Array singletons.
//   Then q0 = 0 over +0x10..+0x39: the superclass's lazy slots and isSphere, inlined.
private class ThumbnailDoviDisplayModel: PlaneDisplayModel {
    let iCtCp = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpTexture")
    let iCtCpBiPlanar = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpBiPlanarTexture")
    let pipelineLock = NSLock()
    let maxCachedPipelines = 4
    var pipelineMap: [String: MTLRenderPipelineState] = [:]
    var pipelineOrder: [String] = []
}

/// Forward's field record and initializer put these fields at +0x10 through +0x48.
/// The other queue methods remain separate reconstruction units.
public class ThumbnailQueue {
    private var pendingIndices: [Int]
    private var generatedSet: Set<Int> = []
    private var skippedSet: Set<Int> = []
    private let lock = NSLock()
    public let id: String
    public let count: Int
    public let duration: Double

    public init(id: String, count: Int, duration: Double) {
        self.id = id
        self.count = max(count, 1)
        self.duration = duration
        pendingIndices = Array(0 ..< self.count)
    }

    public func restoreCached(_ cached: Set<Int>) {
        lock.lock()
        generatedSet.formUnion(cached)
        pendingIndices.removeAll { cached.contains($0) }
        lock.unlock()
    }

    public func restoreCached(where predicate: (Int) -> Bool) {
        lock.lock()
        for index in 0 ..< count {
            if predicate(index) {
                generatedSet.insert(index)
            }
        }
        pendingIndices.removeAll { generatedSet.contains($0) }
        lock.unlock()
    }

    public func seek(toIndex index: Int) {
        lock.lock()
        guard index >= 0, index < count else {
            lock.unlock()
            return
        }

        var after: [Int] = []
        var before: [Int] = []
        var target: Int?
        for pending in pendingIndices {
            if pending == index {
                target = pending
            } else if index < pending {
                after.append(pending)
            } else {
                before.append(pending)
            }
        }
        after.sort()
        before.sort(by: >)
        var reordered: [Int] = []
        if let target {
            reordered.append(target)
        }
        reordered.append(contentsOf: after)
        reordered.append(contentsOf: before)
        pendingIndices = reordered
        lock.unlock()
    }

    public func seek(toTime time: Double) {
        guard duration > 0 else { return }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        let index = min(count - 1, scaledIndex)
        seek(toIndex: index)
    }

    public func next() -> Int? {
        lock.lock()
        let result: Int?
        if pendingIndices.isEmpty {
            result = nil
        } else {
            result = pendingIndices.removeFirst()
        }
        lock.unlock()
        return result
    }

    public func markGenerated(_ index: Int) {
        lock.lock()
        generatedSet.insert(index)
        lock.unlock()
    }

    public func putBack(_ index: Int) {
        lock.lock()
        if !generatedSet.contains(index) {
            skippedSet.insert(index)
        }
        lock.unlock()
    }

    public func retrySkipped() {
        lock.lock()
        for index in skippedSet {
            if !generatedSet.contains(index) && !pendingIndices.contains(index) {
                pendingIndices.append(index)
            }
        }
        skippedSet = []
        lock.unlock()
    }
    public var skippedCount: Int {
        lock.lock()
        let result = skippedSet.count
        lock.unlock()
        return result
    }

    public func isGenerated(_ index: Int) -> Bool {
        lock.lock()
        let result = generatedSet.contains(index)
        lock.unlock()
        return result
    }

    public func isSkipped(_ index: Int) -> Bool {
        lock.lock()
        let result = skippedSet.contains(index)
        lock.unlock()
        return result
    }

    public func skipAllPending() {
        lock.lock()
        for index in pendingIndices {
            skippedSet.insert(index)
        }
        pendingIndices = []
        lock.unlock()
    }
    public var pendingCount: Int {
        lock.lock()
        let result = pendingIndices.count
        lock.unlock()
        return result
    }

    public func isGenerated(atTime time: Double) -> Bool {
        guard duration > 0 else { return false }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        let index = min(count - 1, scaledIndex)
        lock.lock()
        let result = generatedSet.contains(index)
        lock.unlock()
        return result
    }

    public func index(forTime time: Double) -> Int {
        guard duration > 0 else { return 0 }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        return min(count - 1, scaledIndex)
    }

    public func reset() {
        lock.lock()
        pendingIndices = Array(0 ..< count)
        generatedSet = []
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        pendingIndices = []
        lock.unlock()
    }
    public var isEmpty: Bool {
        lock.lock()
        let result = pendingIndices.isEmpty
        lock.unlock()
        return result
    }
    public var remaining: Int {
        lock.lock()
        let result = pendingIndices.count
        lock.unlock()
        return result
    }

    public var generatedCount: Int {
        lock.lock()
        let result = generatedSet.count
        lock.unlock()
        return result
    }
}
