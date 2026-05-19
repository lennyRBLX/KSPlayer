//
//  ThumbnailController.swift
//
//  RE source: Forward v1.3.15 — RE/64_thumbnail_generation_system.md
//  - RealtimeThumbnailGenerator (0x10091f6ec–0x100922d74, 10 functions)
//  - ThumbnailSession (0x1012f5560–0x1012f9820, 4 functions)
//  - ThumbnailController (0x10133339c–0x10133359c, 6 functions)
//  - ThumbnailQueue (0x101300164–0x101300674, 3 functions)
//

import AVFoundation
import Combine
import Foundation
import Libavcodec
import Libavformat
#if canImport(UIKit)
import UIKit
#endif

// MARK: - FFThumbnail

public struct FFThumbnail {
    public let image: UIImage
    public let time: TimeInterval
}

// MARK: - ThumbnailControllerDelegate

public protocol ThumbnailControllerDelegate: AnyObject {
    func didUpdate(thumbnails: [FFThumbnail], forFile file: URL, withProgress: Int)
}

// MARK: - ThumbnailCache (URL-level, 8 entries)

public class ThumbnailCache {
    public static let shared = ThumbnailCache()
    private var cache = [String: [FFThumbnail]]()
    private var accessOrder = [String]()
    private let maxEntries: Int
    private let lock = NSLock()

    public init(maxEntries: Int = 8) {
        self.maxEntries = maxEntries
    }

    public func get(for url: URL) -> [FFThumbnail]? {
        lock.lock()
        defer { lock.unlock() }
        let key = url.absoluteString
        guard let thumbnails = cache[key] else { return nil }
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
            accessOrder.append(key)
        }
        return thumbnails
    }

    public func set(_ thumbnails: [FFThumbnail], for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let key = url.absoluteString
        cache[key] = thumbnails
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
        while accessOrder.count > maxEntries {
            let evicted = accessOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        accessOrder.removeAll()
    }
}

// MARK: - ThumbnailSession (FFmpeg extraction engine)

public final class ThumbnailSession {
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var reScale: VideoSwresample?
    private var videoStreamIndex: Int32 = -1
    private var timeBase: Timebase = .defaultValue
    private let thumbWidth: Int32
    private var intervalPTS: Int64 = 0
    private var intervalSeconds: Double = 0
    private var startTime: Int64 = 0
    public private(set) var frameCount: Int = 0
    public private(set) var isHDR: Bool = false
    public private(set) var duration: Double = 0
    private var isCancelled = false
    private let maxPacketRetries = 99

    public init?(url: URL, thumbnailWidth: Int32 = 400, requestedFrameCount: Int = 100) {
        self.thumbWidth = thumbnailWidth
        let urlString = url.isFileURL ? url.path : url.absoluteString

        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&fmtCtx, urlString, nil, nil) >= 0, let fmtCtx else { return nil }
        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            avformat_close_input(&self.formatCtx)
            return nil
        }
        self.formatCtx = fmtCtx

        for i in 0 ..< Int32(fmtCtx.pointee.nb_streams) {
            if fmtCtx.pointee.streams[Int(i)]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                break
            }
        }
        guard videoStreamIndex >= 0,
              let videoStream = fmtCtx.pointee.streams[Int(videoStreamIndex)] else {
            avformat_close_input(&self.formatCtx)
            return nil
        }

        let avgFrameRate = videoStream.pointee.avg_frame_rate
        guard avgFrameRate.den != 0, av_q2d(avgFrameRate) > 0 else {
            avformat_close_input(&self.formatCtx)
            return nil
        }

        let codecpar = videoStream.pointee.codecpar!
        guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            avformat_close_input(&self.formatCtx)
            return nil
        }
        let ctx = avcodec_alloc_context3(codec)
        guard let ctx else {
            avformat_close_input(&self.formatCtx)
            return nil
        }
        avcodec_parameters_to_context(ctx, codecpar)
        guard avcodec_open2(ctx, codec, nil) >= 0 else {
            avcodec_free_context(&self.codecContext)
            avformat_close_input(&self.formatCtx)
            return nil
        }
        self.codecContext = ctx

        // HDR detection: scan side data for DV (type 29) or PQ transfer (18)
        let nbSideData = videoStream.pointee.codecpar.pointee.nb_coded_side_data
        for i in 0 ..< Int(nbSideData) {
            let sideData = videoStream.pointee.codecpar.pointee.coded_side_data[i]
            if sideData.type.rawValue == 29 { // AV_PKT_DATA_DOVI_CONF
                isHDR = true
                break
            }
        }
        if !isHDR, codecpar.pointee.color_trc == AVCOL_TRC_SMPTE2084 {
            isHDR = true
        }

        self.timeBase = Timebase(videoStream.pointee.time_base)
        self.startTime = videoStream.pointee.start_time != Int64(AV_NOPTS_VALUE) ? videoStream.pointee.start_time : 0

        let durationPTS = av_rescale_q(fmtCtx.pointee.duration, AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        self.duration = Double(durationPTS) * av_q2d(videoStream.pointee.time_base)
        self.frameCount = max(10, requestedFrameCount)
        self.intervalPTS = durationPTS / Int64(frameCount)
        self.intervalSeconds = duration / Double(frameCount)

        let thumbHeight = thumbWidth * ctx.pointee.height / ctx.pointee.width
        self.reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, isDovi: isHDR)

        KSLog("[Thumb] init done, duration=\(durationPTS), interval=\(intervalPTS), intervalSeconds=\(intervalSeconds), count=\(frameCount), isHDR=\(isHDR)")
    }

    /// Single-frame extraction at a specific index (RE: seekAndExtract 0x1012f6264, 6296 bytes)
    public func seekAndExtract(at index: Int) -> (image: UIImage, time: TimeInterval)? {
        guard let formatCtx, let codecContext, let reScale, !isCancelled else { return nil }

        let targetPTS = Int64(index) * intervalPTS + startTime
        let targetSeconds = intervalSeconds * Double(index)

        if let result = extractFrame(targetPTS: targetPTS, targetSeconds: targetSeconds, index: index, flags: AVSEEK_FLAG_BACKWARD) {
            return result
        }
        // Retry with AVSEEK_FLAG_ANY for content with sparse keyframes
        return extractFrame(targetPTS: targetPTS, targetSeconds: targetSeconds, index: index, flags: AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_ANY)
    }

    private func extractFrame(targetPTS: Int64, targetSeconds: Double, index: Int, flags: Int32) -> (image: UIImage, time: TimeInterval)? {
        guard let formatCtx, let codecContext, let reScale, !isCancelled else { return nil }

        let seekStart = CACurrentMediaTime()
        av_seek_frame(formatCtx, videoStreamIndex, targetPTS, flags)
        avcodec_flush_buffers(codecContext)

        var frame = av_frame_alloc()!
        defer { av_frame_free(&frame) }
        var packet = AVPacket()
        var packetsRead = 0
        var result: (UIImage, TimeInterval)?

        let readStart = CACurrentMediaTime()
        while av_read_frame(formatCtx, &packet) >= 0, packetsRead < maxPacketRetries {
            defer { av_packet_unref(&packet) }
            guard !isCancelled else { break }

            if packet.stream_index != videoStreamIndex { continue }
            packetsRead += 1

            if avcodec_send_packet(codecContext, &packet) < 0 { continue }
            let ret = avcodec_receive_frame(codecContext, frame)
            if ret == -EAGAIN { continue }
            if ret < 0 { break }

            let framePTS = frame.pointee.best_effort_timestamp
            let frameSeconds = Double(framePTS) * av_q2d(timeBase.rational)

            // Time validation: skip frames deviating > 2x interval
            if abs(frameSeconds - targetSeconds) > 2 * intervalSeconds, packetsRead < maxPacketRetries / 2 {
                av_frame_unref(frame)
                continue
            }

            let decodeTime = CACurrentMediaTime() - readStart
            if let pixelBuffer = reScale.transfer(frame: frame.pointee),
               let cgImage = pixelBuffer.cgImage() {
                let finalImage = isHDR ? Self.toSDR(cgImage) : cgImage
                let image = UIImage(cgImage: finalImage)
                let time = timeBase.cmtime(for: framePTS).seconds
                result = (image, time)
                let totalTime = CACurrentMediaTime() - seekStart
                KSLog("[Thumb] \(index) seek=\(Int((CACurrentMediaTime() - seekStart) * 1000))ms, decode=\(Int(decodeTime * 1000))ms, total=\(Int(totalTime * 1000))ms, packets=\(packetsRead)")
            }
            break
        }
        av_packet_unref(&packet)
        return result
    }

    /// Batch sequential extraction (RE: seekAndExtract2 0x1012f7b14, 7436 bytes)
    public func batchExtract(startIndex: Int, maxIndex: Int, progress: @escaping (UIImage, Int, Double) -> Bool) {
        guard let formatCtx, !isCancelled else { return }

        let seekPos = Int64(startIndex) * intervalPTS + startTime
        av_seek_frame(formatCtx, videoStreamIndex, seekPos, AVSEEK_FLAG_BACKWARD)
        avcodec_flush_buffers(codecContext!)

        var frame = av_frame_alloc()!
        defer { av_frame_free(&frame) }
        var packet = AVPacket()
        var savedCount = 0

        while av_read_frame(formatCtx, &packet) >= 0, !isCancelled {
            defer { av_packet_unref(&packet) }
            guard packet.stream_index == videoStreamIndex else { continue }
            guard avcodec_send_packet(codecContext, &packet) >= 0 else { continue }

            while avcodec_receive_frame(codecContext, frame) >= 0 {
                let framePTS = frame.pointee.best_effort_timestamp
                let index = Int((framePTS - startTime) / intervalPTS)
                guard index <= maxIndex else { return }

                if let pixelBuffer = reScale?.transfer(frame: frame.pointee),
                   let cgImage = pixelBuffer.cgImage() {
                    let finalImage = isHDR ? Self.toSDR(cgImage) : cgImage
                    let image = UIImage(cgImage: finalImage)
                    let time = timeBase.cmtime(for: framePTS).seconds
                    savedCount += 1
                    if !progress(image, index, time) { return }
                }
                av_frame_unref(frame)
            }
        }
        av_packet_unref(&packet)
    }

    /// Tone-map an HDR CGImage to sRGB for SDR thumbnail display.
    /// CoreGraphics handles PQ EOTF → linear → gamut mapping → sRGB OETF.
    private static func toSDR(_ cgImage: CGImage) -> CGImage {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                 bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return cgImage
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return ctx.makeImage() ?? cgImage
    }

    public func cancel() { isCancelled = true }

    public func shutdown() {
        reScale?.shutdown()
        if codecContext != nil {
            avcodec_free_context(&codecContext)
        }
        if formatCtx != nil {
            avformat_close_input(&formatCtx)
        }
    }

    deinit { shutdown() }
}

// MARK: - ThumbState (Combine-driven for SwiftUI)

public final class ThumbState: ObservableObject {
    @Published public var currentImage: CGImage?
    @Published public var currentDisplayedTime: Double?
    @Published public var isSeeking: Bool = false
}

// MARK: - RealtimeThumbnailGenerator (RE: 0x10091f6ec, 10 functions)

public final class RealtimeThumbnailGenerator: @unchecked Sendable {
    private let session: ThumbnailSession
    private let dispatchQueue = DispatchQueue(label: "thumbnail.realtime", qos: .userInteractive)
    private let lock = NSLock()

    private var cacheDict = [Int64: CGImage]()
    private var cacheOrder = [Int64]()
    private static let maxCacheSize = 16

    private var currentWorkItem: DispatchWorkItem?
    public let thumbState = ThumbState()
    private var memoryWarningObserver: NSObjectProtocol?

    public init?(url: URL, frameCount: Int = 100) {
        guard let session = ThumbnailSession(url: url, thumbnailWidth: 400, requestedFrameCount: frameCount) else {
            return nil
        }
        self.session = session

        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.clearCache()
        }
        #endif
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        session.cancel()
    }

    /// Cancel current work and restart extraction at new position (RE: cancelAndRestart 0x100922b00)
    public func seekToFrame(at index: Int) {
        lock.lock()
        currentWorkItem?.cancel()

        // Check LRU cache first
        let key = Int64(index)
        if let cached = cacheDict[key] {
            // LRU promotion
            if let idx = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: idx)
                cacheOrder.append(key)
            }
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.thumbState.currentImage = cached
                self?.thumbState.isSeeking = false
            }
            return
        }
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.thumbState.isSeeking = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let result = self.session.seekAndExtract(at: index) else {
                self.resetSeeking()
                return
            }

            let cgImage = result.image.cgImage
            if let cgImage {
                self.addToCache(key: key, image: cgImage)
            }

            DispatchQueue.main.async { [weak self] in
                self?.thumbState.currentImage = cgImage
                self?.thumbState.currentDisplayedTime = result.time
                self?.thumbState.isSeeking = false
            }
        }

        lock.lock()
        currentWorkItem = workItem
        lock.unlock()

        dispatchQueue.async(execute: workItem)
    }

    /// Convert a time position to frame index
    public func frameIndex(for time: TimeInterval) -> Int {
        guard session.duration > 0 else { return 0 }
        let fraction = time / session.duration
        let count = session.frameCount
        return max(0, min(count - 1, Int(fraction * Double(count))))
    }

    // RE: addOrReplaceThumbnail 0x1009223bc — LRU with FIFO eviction at 50
    private func addToCache(key: Int64, image: CGImage) {
        lock.lock()
        defer { lock.unlock() }
        if cacheDict[key] != nil {
            if let idx = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: idx)
                cacheOrder.append(key)
            }
        } else {
            cacheDict[key] = image
            cacheOrder.append(key)
            while cacheOrder.count > Self.maxCacheSize {
                let evicted = cacheOrder.removeFirst()
                cacheDict.removeValue(forKey: evicted)
            }
        }
        cacheDict[key] = image
    }

    // RE: clearCacheAndStorage 0x100922d74 — memory pressure handler
    private func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cacheDict.removeAll()
        cacheOrder.removeAll()
    }

    private func resetSeeking() {
        DispatchQueue.main.async { [weak self] in
            self?.thumbState.isSeeking = false
        }
    }

    public var isHDR: Bool { session.isHDR }
    public var videoDuration: Double { session.duration }
}

// MARK: - ThumbnailController (batch generation)

public class ThumbnailController {
    public weak var delegate: ThumbnailControllerDelegate?
    private let thumbnailCount: Int
    public var useCache = true
    /// Configured media URL, set via `configure(url:options:duration:)`
    public private(set) var mediaURL: URL?
    /// Configured media duration in seconds
    public private(set) var mediaDuration: TimeInterval = 0
    /// Options snapshot from configuration
    public private(set) var configuredOptions: KSOptions?
    /// ThumbnailSession created during configuration for batch/realtime use
    private var session: ThumbnailSession?
    /// RealtimeThumbnailGenerator created during configuration
    public private(set) var realtimeGenerator: RealtimeThumbnailGenerator?

    public init(thumbnailCount: Int = 100) {
        self.thumbnailCount = thumbnailCount
    }

    /// Bind the controller to a player instance by providing the media URL,
    /// player options, and total duration. Creates or reconfigures the
    /// underlying ThumbnailSession and RealtimeThumbnailGenerator.
    /// RE: ThumbnailController.configure at 0x10133339c
    public func configure(url: URL, options: KSOptions, duration: TimeInterval) {
        // Tear down previous session if URL changed
        if let existingURL = mediaURL, existingURL != url {
            session?.cancel()
            session?.shutdown()
            session = nil
            realtimeGenerator = nil
        }

        mediaURL = url
        mediaDuration = duration
        configuredOptions = options

        // Determine thumbnail width from options or use default
        let thumbWidth: Int32 = 240

        // Create or reconfigure the ThumbnailSession
        if session == nil {
            session = ThumbnailSession(
                url: url,
                thumbnailWidth: thumbWidth,
                requestedFrameCount: thumbnailCount
            )
        }

        // Create the RealtimeThumbnailGenerator for scrubbing if not yet created
        if realtimeGenerator == nil {
            realtimeGenerator = RealtimeThumbnailGenerator(url: url, frameCount: thumbnailCount)
        }

        KSLog("[ThumbnailController] configured for \(url.lastPathComponent), duration=\(duration)s, count=\(thumbnailCount)")
    }

    public func generateThumbnail(for url: URL, thumbWidth: Int32 = 240) async throws -> [FFThumbnail] {
        if useCache, let cached = ThumbnailCache.shared.get(for: url) {
            return cached
        }
        let result = try await Task {
            try getPeeks(for: url, thumbWidth: thumbWidth)
        }.value
        if useCache {
            ThumbnailCache.shared.set(result, for: url)
        }
        return result
    }

    private func getPeeks(for url: URL, thumbWidth: Int32 = 240) throws -> [FFThumbnail] {
        let urlString: String
        if url.isFileURL {
            urlString = url.path
        } else {
            urlString = url.absoluteString
        }
        var thumbnails = [FFThumbnail]()
        var formatCtx = avformat_alloc_context()
        defer {
            avformat_close_input(&formatCtx)
        }
        var result = avformat_open_input(&formatCtx, urlString, nil, nil)
        guard result == 0, let formatCtx else {
            throw NSError(errorCode: .formatOpenInput, avErrorCode: result)
        }
        result = avformat_find_stream_info(formatCtx, nil)
        guard result == 0 else {
            throw NSError(errorCode: .formatFindStreamInfo, avErrorCode: result)
        }
        var videoStreamIndex = -1
        for i in 0 ..< Int32(formatCtx.pointee.nb_streams) {
            if formatCtx.pointee.streams[Int(i)]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int(i)
                break
            }
        }
        guard videoStreamIndex >= 0, let videoStream = formatCtx.pointee.streams[videoStreamIndex] else {
            throw NSError(description: "No video stream")
        }

        let videoAvgFrameRate = videoStream.pointee.avg_frame_rate
        if videoAvgFrameRate.den == 0 || av_q2d(videoAvgFrameRate) == 0 {
            throw NSError(description: "Avg frame rate = 0, ignore")
        }
        var codecContext = try videoStream.pointee.codecpar.pointee.createContext(options: nil)
        defer {
            avcodec_close(codecContext)
            var codecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&codecContext)
        }
        let thumbHeight = thumbWidth * codecContext.pointee.height / codecContext.pointee.width
        let reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, isDovi: false)
        let duration = av_rescale_q(formatCtx.pointee.duration,
                                    AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        let interval = duration / Int64(thumbnailCount)
        var packet = AVPacket()
        let timeBase = Timebase(videoStream.pointee.time_base)
        var frame = av_frame_alloc()
        defer {
            av_frame_free(&frame)
        }
        guard let frame else {
            throw NSError(description: "can not av_frame_alloc")
        }
        for i in 0 ..< thumbnailCount {
            let seek_pos = interval * Int64(i) + videoStream.pointee.start_time
            avcodec_flush_buffers(codecContext)
            result = av_seek_frame(formatCtx, Int32(videoStreamIndex), seek_pos, AVSEEK_FLAG_BACKWARD)
            guard result == 0 else {
                return thumbnails
            }
            avcodec_flush_buffers(codecContext)
            while av_read_frame(formatCtx, &packet) >= 0 {
                if packet.stream_index == Int32(videoStreamIndex) {
                    if avcodec_send_packet(codecContext, &packet) < 0 {
                        break
                    }
                    let ret = avcodec_receive_frame(codecContext, frame)
                    if ret < 0 {
                        if ret == -EAGAIN {
                            continue
                        } else {
                            break
                        }
                    }
                    let image = reScale.transfer(frame: frame.pointee)?.cgImage().map {
                        UIImage(cgImage: $0)
                    }
                    let currentTimeStamp = frame.pointee.best_effort_timestamp
                    if let image {
                        let thumbnail = FFThumbnail(image: image, time: timeBase.cmtime(for: currentTimeStamp).seconds)
                        thumbnails.append(thumbnail)
                        delegate?.didUpdate(thumbnails: thumbnails, forFile: url, withProgress: i)
                    }
                    break
                }
            }
        }
        av_packet_unref(&packet)
        reScale.shutdown()
        return thumbnails
    }
}
