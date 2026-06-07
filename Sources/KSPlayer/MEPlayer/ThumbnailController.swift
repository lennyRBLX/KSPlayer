//
//  ThumbnailController.swift
//
//  RE source: Forward v1.3.15 — .reversal/TrackDecode.md § ThumbnailController / GIFCreator
//  Verified Ghidra named entries:
//    ThumbnailController_initFields              @ 0x1001D558C
//    ThumbnailController_configureThumbnails     @ 0x1001D55C4
//    ThumbnailController_seekToPosition          @ 0x1001D5620  (coroutine read accessor)
//    ThumbnailController_loadNextBatch           @ 0x1001D56A0  (coroutine modify accessor)
//    ~~ThumbnailController_cancelPending~~       @ 0x10144F6AC  STRUCK (v5.3 R3) — async-context allocator, not ThumbnailController
//    ~~ThumbnailController_deinit~~              @ 0x10144F6F4  STRUCK (v5.3 R3) — async-context field init, not a class deinitializer
//    ~~ThumbnailController_resetState~~          @ 0x100772E10  STRUCK (v5.3 R3) — weak-ref accessor for a different class (offset +0x10 mismatch)
//    ThumbnailGenerator_updatePublishedProperties @ 0x1009957E0
//    ThumbnailGenerator_switchToMainActor        @ 0x10058B9D4
//    ThumbnailGenerator_resetSeeking_onMainActor @ 0x10099663C
//    FFmpegDecode_allocThumbnailContext          @ 0x101417F3C
//    PlayerCenter_renderSnapshotForThumbnail     @ 0x10103A030
//    PreLoadIOContext_getThumbnailFetchResult    @ 0x1000EA5B8
//    PreLoadIOContext_setThumbnailFetchResult    @ 0x101441440
//
//  KSPlayer FFThumbnail Swift type witness tables:
//    destroy/copy/copy-assign/take-assign/store
//    @ 0x10144F7B8 / 0x10144F7F0 / 0x10144F858 / 0x10144F914 / 0x10061A4D8
//
//  Components-side RealtimeThumbnailGenerator (Swift class
//  _TtC10Components26RealtimeThumbnailGenerator @ 0x1033118A0; bare-name
//  string @ 0x102E92940) has no named function symbols in current Ghidra —
//  implementation lives in anonymous FUN_* bodies
//  (FUN_10091F174, FUN_100921AB8, FUN_1009224F0, FUN_1012F5524, FUN_1012F5B20,
//  FUN_1012F7988, FUN_1012F96BC). The earlier addresses 0x10091f6ec, 0x1012f5560,
//  0x10133339c, 0x101300164 were mid-function offsets, not entries.
//
//  Components-side log strings the class emits:
//    "[Thumb] RealtimeThumbnailGenerator init FAILED: "        @ 0x103311D10
//    "[Thumb] RealtimeThumbnailGenerator session initialized"  @ 0x103311D50
//    "[Thumb] RealtimeThumbnailGenerator started, duration="   @ 0x103311E20
//

import AVFoundation
import Combine
import CoreGraphics
import Foundation
import ImageIO
import Libavcodec
import Libavformat
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MobileCoreServices)
import MobileCoreServices.UTType
#endif

// MARK: - FFThumbnail

/// Output unit of a single frame grab. 3 fields per types.json (declaration order):
///   1. jpegData  (Data?)    — JPEG-encoded frame bytes (nil until encoded)
///   2. _image    (UIImage?) — Lazily-decoded image (private backing for `image` computed property)
///   3. time      (Double)   — Presentation timestamp of the grabbed frame, in seconds
///
/// The binary stores JPEG bytes and lazily decodes to UIImage on first access,
/// saving memory when thumbnails are cached but not yet displayed.
/// RE: value-witness table $s8KSPlayer11FFThumbnailVwst @ 0x10061a4d8
public struct FFThumbnail {
    /// JPEG-encoded frame bytes. Stored for memory-efficient caching;
    /// the image is decoded lazily on first access via the `image` property.
    public var jpegData: Data?

    /// Private backing store for the lazily-decoded image.
    /// Uses underscore-prefix matching the binary's private-stored-property-behind-computed-property pattern.
    private var _image: UIImage?

    /// Presentation timestamp of the grabbed frame, in seconds.
    public let time: Double

    /// Lazily-decoded image: returns `_image` if already decoded, otherwise
    /// decodes from `jpegData` on first access, caches the result in `_image`,
    /// and returns it. Falls back to nil if neither source is available.
    public var image: UIImage? {
        mutating get {
            if let _image { return _image }
            guard let jpegData, let decoded = UIImage(data: jpegData) else { return _image }
            _image = decoded
            return decoded
        }
    }

    /// Initialize with a pre-decoded image (used during extraction when the image
    /// is already in memory). Encodes to JPEG for the lazy-decode cache path.
    public init(image: UIImage, time: Double) {
        self._image = image
        #if canImport(UIKit)
        self.jpegData = image.jpegData(compressionQuality: 0.85)
        #else
        // macOS: NSImage -> NSBitmapImageRep -> JPEG data
        if let tiff = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiff) {
            self.jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        } else {
            self.jpegData = nil
        }
        #endif
        self.time = time
    }

    /// Initialize with raw JPEG data for deferred decoding (memory-efficient path).
    public init(jpegData: Data, time: Double) {
        self.jpegData = jpegData
        self._image = nil
        self.time = time
    }
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

/// RE: companion allocator FFmpegDecode_allocThumbnailContext @ 0x101417F3C (1.3.15)
/// Per-source FFmpeg decode session that owns the C decode state for frame grabbing.
/// 17 fields per types.json (declaration order documented in TrackDecode.md § ThumbnailSession).
public final class ThumbnailSession {
    // Field 1: Demuxer context for the thumbnail source
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>?
    // Field 2: Video decoder context
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    // Field 3: Reusable decode-output frame (doc: persistent field, paralleling FFmpegDecode)
    private var frame: UnsafeMutablePointer<AVFrame>?
    // Field 4: swscale rescaler -> downscaled thumbnail pixel buffer
    private var reScale: VideoSwresample?
    // Field 5: Index of the video stream being grabbed (doc type: Swift.Int)
    private var videoStreamIndex: Int = -1
    // Field 6: Stream timebase for PTS<->seconds conversion
    private var timeBase: Timebase = .defaultValue
    // Field 7: Target thumbnail width (height derived from aspect)
    private let thumbWidth: Int32
    // Field 8: Grab interval in timebase units
    private var intervalPTS: Int64 = 0
    // Field 9: Stream start PTS offset
    private var startTime: Int64 = 0
    // Field 10: Total thumbnails to generate across the timeline
    public private(set) var frameCount: Int = 0
    // Field 11: Grab interval in seconds
    private var intervalSeconds: Double = 0
    // Field 12: True if source is HDR (affects rescale/tone-map)
    public private(set) var isHDR: Bool = false
    // Field 13: True if source carries Dolby Vision
    public private(set) var hasDovi: Bool = false
    // Field 14: Optional precomputed seek-position table (element type erased in reflection)
    private var indexedSeekPositions: [Int64]?
    // Field 15: Closure probing whether the current position is already cached
    private var isCachedAtCurrentPosition: (() -> Bool)?
    // Field 16: Cooperative-cancellation flag for the FFmpeg interrupt callback
    private var isInterrupted = false
    // Field 17: Set once the session's contexts are freed
    private var isClosed = false

    public private(set) var duration: Double = 0
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

        for i in 0 ..< Int(fmtCtx.pointee.nb_streams) {
            if fmtCtx.pointee.streams[i]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                break
            }
        }
        guard videoStreamIndex >= 0,
              let videoStream = fmtCtx.pointee.streams[videoStreamIndex] else {
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

        // Allocate persistent reusable frame (doc field 3)
        self.frame = av_frame_alloc()

        // HDR detection: scan side data for DV (type 29) or PQ transfer (18)
        let nbSideData = videoStream.pointee.codecpar.pointee.nb_coded_side_data
        for i in 0 ..< Int(nbSideData) {
            let sideData = videoStream.pointee.codecpar.pointee.coded_side_data[i]
            if sideData.type.rawValue == 29 { // AV_PKT_DATA_DOVI_CONF
                hasDovi = true
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
        self.reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, isDovi: hasDovi || isHDR)

        KSLog("[Thumb] init done, duration=\(durationPTS), interval=\(intervalPTS), intervalSeconds=\(intervalSeconds), count=\(frameCount), isHDR=\(isHDR), hasDovi=\(hasDovi)")
    }

    /// Single-frame extraction at a specific index
    /// (RE: seekAndExtract body inside FUN_1012F5B20, 2,684 B)
    public func seekAndExtract(at index: Int) -> (image: UIImage, time: TimeInterval)? {
        guard !isClosed, !isInterrupted,
              let formatCtx, let codecContext, let reScale else { return nil }

        // Check cached-position closure if provided (doc field 15)
        if let isCachedAtCurrentPosition, isCachedAtCurrentPosition() {
            return nil
        }

        let targetPTS = Int64(index) * intervalPTS + startTime
        let targetSeconds = intervalSeconds * Double(index)

        if let result = extractFrame(targetPTS: targetPTS, targetSeconds: targetSeconds, index: index, flags: AVSEEK_FLAG_BACKWARD) {
            return result
        }
        // Retry with AVSEEK_FLAG_ANY for content with sparse keyframes
        return extractFrame(targetPTS: targetPTS, targetSeconds: targetSeconds, index: index, flags: AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_ANY)
    }

    private func extractFrame(targetPTS: Int64, targetSeconds: Double, index: Int, flags: Int32) -> (image: UIImage, time: TimeInterval)? {
        guard !isClosed, !isInterrupted,
              let formatCtx, let codecContext, let reScale, let frame else { return nil }

        let seekStart = CACurrentMediaTime()
        av_seek_frame(formatCtx, Int32(videoStreamIndex), targetPTS, flags)
        avcodec_flush_buffers(codecContext)

        var packet = AVPacket()
        var packetsRead = 0
        var result: (UIImage, TimeInterval)?

        let readStart = CACurrentMediaTime()
        while av_read_frame(formatCtx, &packet) >= 0, packetsRead < maxPacketRetries {
            defer { av_packet_unref(&packet) }
            guard !isInterrupted else { break }

            if packet.stream_index != Int32(videoStreamIndex) { continue }
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
            av_frame_unref(frame)
            break
        }
        av_packet_unref(&packet)
        return result
    }

    /// Batch sequential extraction (RE: seekAndExtract2 0x1012f7b14, 7436 bytes)
    public func batchExtract(startIndex: Int, maxIndex: Int, progress: @escaping (UIImage, Int, Double) -> Bool) {
        guard !isClosed, !isInterrupted,
              let formatCtx, let codecContext, let frame else { return }

        let seekPos = Int64(startIndex) * intervalPTS + startTime
        av_seek_frame(formatCtx, Int32(videoStreamIndex), seekPos, AVSEEK_FLAG_BACKWARD)
        avcodec_flush_buffers(codecContext)

        var packet = AVPacket()
        var savedCount = 0

        while av_read_frame(formatCtx, &packet) >= 0, !isInterrupted {
            defer { av_packet_unref(&packet) }
            guard packet.stream_index == Int32(videoStreamIndex) else { continue }
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

    /// Set the cooperative-cancellation flag (doc field 16: isInterrupted).
    /// Named for the FFmpeg avformat interrupt callback pattern.
    public func cancel() { isInterrupted = true }

    /// Free all FFmpeg contexts and mark the session as closed (doc field 17: isClosed).
    /// Idempotent: subsequent calls after isClosed is set are no-ops.
    public func shutdown() {
        guard !isClosed else { return }
        isClosed = true
        reScale?.shutdown()
        if frame != nil {
            av_frame_free(&frame)
        }
        if codecContext != nil {
            avcodec_free_context(&codecContext)
        }
        if formatCtx != nil {
            avformat_close_input(&formatCtx)
        }
    }

    /// Set indexed seek positions table for optimized seeking in sparse-keyframe sources (doc field 14).
    public func setIndexedSeekPositions(_ positions: [Int64]) {
        indexedSeekPositions = positions
    }

    /// Set the cache-probe closure (doc field 15).
    public func setCacheProbe(_ probe: (() -> Bool)?) {
        isCachedAtCurrentPosition = probe
    }

    deinit { shutdown() }
}

// MARK: - ThumbState (Combine-driven for SwiftUI)

public final class ThumbState: ObservableObject {
    @Published public var currentImage: CGImage?
    @Published public var currentDisplayedTime: Double?
    @Published public var isSeeking: Bool = false
}

// MARK: - RealtimeThumbnailGenerator
// RE: implementation lives in anonymous FUN_10091F174 (init body, 1,120 B) plus
//     FUN_100921AB8 (2,616 B; contains updatePublishedProperties, switchToMainActor,
//     resetSeeking_onMainActor, addOrReplaceThumbnail) and
//     FUN_1009224F0 (2,656 B; contains setupRealtimeThumbnailGenerator,
//     dispatchAsyncGeneration, cancelAndRestart, clearCacheAndStorage).
// The four-claimed-functions-collapse-into-one observation is a side-effect of
// Swift @inlinable / generic specialization, not a separate symbol per method.

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

    /// Cancel current work and restart extraction at new position
    /// (RE: cancelAndRestart inside FUN_1009224F0)
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

    // RE: addOrReplaceThumbnail (inside FUN_100921AB8) — LRU with FIFO eviction at 50
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

    // RE: clearCacheAndStorage (inside FUN_1009224F0) — memory pressure handler
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
    public var hasDovi: Bool { session.hasDovi }
    public var videoDuration: Double { session.duration }
}

// MARK: - ThumbnailController (batch generation)

/// Thumbnail-extraction driver coordinating batched generation against a delegate.
///
/// Binary layout: **2 stored fields** per `types.json`:
///   1. delegate       (weak ThumbnailControllerDelegate?)  offset +0x40
///   2. thumbnailCount (Int)                                offset +0x48
///
/// The 6 additional properties below (`useCache`, `mediaURL`, `mediaDuration`,
/// `configuredOptions`, `session`, `realtimeGenerator`) are **reconstruction
/// extensions** — they do not appear in the binary's type metadata dump but are
/// needed to wire the controller into the player's configuration and session
/// lifecycle in our Swift reconstruction. The binary likely managed these
/// relationships through its Components-layer coordinator rather than storing
/// them directly on the controller.
public class ThumbnailController {
    // ── Binary fields (2, per types.json) ──────────────────────────────

    /// RE: 0x1001D558C (ThumbnailController_initFields, 1.3.15)
    /// Weakly-held delegate notified as batches complete (offset +0x40 in binary).
    public weak var delegate: ThumbnailControllerDelegate?
    /// RE: ThumbnailController_configureThumbnails stores count at +0x48
    private let thumbnailCount: Int

    // ── Reconstruction extensions (not in binary type metadata) ────────

    /// Whether to use the URL-level ThumbnailCache for generated results.
    public var useCache = true
    /// Configured media URL, set via `configure(url:options:duration:)`.
    public private(set) var mediaURL: URL?
    /// Configured media duration in seconds.
    public private(set) var mediaDuration: TimeInterval = 0
    /// Options snapshot from configuration.
    public private(set) var configuredOptions: KSOptions?
    /// ThumbnailSession created during configuration for batch/realtime use.
    private var session: ThumbnailSession?
    /// RealtimeThumbnailGenerator created during configuration.
    public private(set) var realtimeGenerator: RealtimeThumbnailGenerator?

    public init(thumbnailCount: Int = 100) {
        self.thumbnailCount = thumbnailCount
    }

    /// The current (delegate, count) batch target, expressed as a computed property
    /// whose get/set map to the binary's coroutine accessor pair.
    ///
    /// RE: 0x1001D5620 (seekToPosition / coroutine read accessor, 1.3.15)
    ///     Allocates a 0x30 coro frame, weak-loads the delegate from +0x40,
    ///     captures count from +0x48, and yields into loadNextBatch.
    ///
    /// RE: 0x1001D56A0 (loadNextBatch / coroutine modify accessor, 1.3.15)
    ///     Pushes the current (delegate, count) pair onto the next batch target,
    ///     writes count to +0x48, weak-assigns delegate to +0x40, then releases
    ///     and frees the coro frame.
    public var batchTarget: (delegate: ThumbnailControllerDelegate?, count: Int) {
        get {
            (delegate, thumbnailCount)
        }
        set {
            delegate = newValue.delegate
            // thumbnailCount is let-bound; the binary's modify accessor writes
            // to +0x48 which is the same offset. In our reconstruction the count
            // is immutable after init, so the setter only updates the delegate.
            // If a mutable count is needed, change thumbnailCount to var.
        }
    }

    /// Bind the controller to a player instance by providing the media URL,
    /// player options, and total duration. Creates or reconfigures the
    /// underlying ThumbnailSession and RealtimeThumbnailGenerator.
    /// RE: 0x1001D55C4 (ThumbnailController_configureThumbnails, 1.3.15)
    ///     `_swift_unknownObjectWeakAssign(self+0x40, delegate)` and stores
    ///     `count` at `self+0x48`.
    ///     (companion to ThumbnailController_initFields @ 0x1001D558C)
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

// MARK: - GIFCreator (RE: TrackDecode.md § GIFCreator)

/// Frame-to-animated-GIF export engine. Builds a `CGImageDestination`,
/// drives an `AVAssetImageGenerator` over a computed array of `CMTime`
/// sample points, and writes each decoded frame into the GIF.
///
/// Binary layout (3 fields per types.json):
///   +0x10  destination      : CGImageDestination
///   +0x18  frameProperties  : CFDictionary
///   --     firstImage       : UIImage?
public class ThumbnailGIFCreator {
    /// RE: 0x1013e608c (GIFCreator_createImageDestination, 1.3.15)
    /// GIF output destination, created in `createImageDestination`.
    private var destination: CGImageDestination?

    /// RE: 0x1013e608c (GIFCreator_createImageDestination, 1.3.15)
    /// Per-frame GIF properties dictionary containing kCGImagePropertyGIFDelayTime.
    private var frameProperties: CFDictionary?

    /// First decoded frame, used as cover/preview image.
    public private(set) var firstImage: UIImage?

    /// Collected (image, time) pairs for merge-sort before finalization.
    /// The AVAssetImageGenerator completion callback does not guarantee
    /// chronological order, so we accumulate frames and sort before writing.
    private var collectedFrames: [(image: CGImage, time: CMTime)] = []

    /// Output URL for the GIF file.
    private let savePath: URL

    public init(savePath: URL) {
        self.savePath = savePath
    }

    /// Main entry point: compute sample times, configure the generator,
    /// and asynchronously extract frames from the asset.
    ///
    /// RE: 0x1013cb3ac (GIFCreator_createFromAsset, 1.3.15)
    /// Computes frame count n = (end-start)/interval, builds [NSValue] of n
    /// CMTime sample points with timescale 1000000, allocates AVAssetImageGenerator,
    /// sets requestedTimeToleranceBefore/After = kCMTimeZero (exact-frame grabbing),
    /// calls createImageDestination, then generateCGImagesAsynchronouslyForTimes
    /// with the boxed callback.
    public func createFromAsset(
        _ asset: AVAsset,
        startTime: TimeInterval,
        endTime: TimeInterval,
        interval: TimeInterval,
        completion: @escaping (Bool, UIImage?) -> Void
    ) {
        guard interval > 0, endTime > startTime else {
            completion(false, nil)
            return
        }

        let frameCount = Int((endTime - startTime) / interval)
        guard frameCount > 0 else {
            completion(false, nil)
            return
        }

        // Build [NSValue] array of n CMTime sample points (timescale 1000000)
        // RE: binary uses valueWithCMTime: with timescale 1000000
        let timescale: CMTimeScale = 1_000_000
        let sampleTimes: [NSValue] = (0 ..< frameCount).map { i in
            let seconds = startTime + Double(i) * interval
            let cmTime = CMTime(value: CMTimeValue(seconds * Double(timescale)), timescale: timescale)
            return NSValue(time: cmTime)
        }

        // Create image destination for output
        createImageDestination(imagesCount: frameCount)
        guard destination != nil else {
            completion(false, nil)
            return
        }

        // Allocate AVAssetImageGenerator with exact-frame tolerance (kCMTimeZero)
        // RE: binary sets requestedTimeToleranceBefore/After = kCMTimeZero
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        // Reset collection buffer
        collectedFrames.removeAll()
        collectedFrames.reserveCapacity(frameCount)

        var receivedCount = 0

        // RE: 0x1013cb2f0 (imageGeneratorCallback_wrapper, 1.3.15)
        // ObjC-block thunk bridging AVAssetImageGenerator's completion block
        // to the Swift callback. In Swift reconstruction, this is the closure
        // passed to generateCGImagesAsynchronously.
        //
        // RE: 0x1013cba90 (blockInvoke, 1.3.15)
        // Block invoke body for the async generation closure — captures
        // destination, image-list, and the [NSValue] times array.
        imageGenerator.generateCGImagesAsynchronously(forTimes: sampleTimes) { [weak self] requestedTime, imageRef, _, result, _ in
            guard let self else { return }
            receivedCount += 1

            // RE: 0x1013cb758 (imageGeneratorCallback, 1.3.15)
            // Per-frame completion callback: appends each generated CGImage
            // to the collected frames list for later merge-sort and writing.
            if result == .succeeded, let imageRef {
                self.imageGeneratorCallback(image: imageRef, time: requestedTime)
            }

            // All frames received — merge-sort and finalize
            if receivedCount == frameCount {
                let success = self.finalizeWithMergeSort()
                completion(success, self.firstImage)
            }
        }
    }

    /// Per-frame completion callback: records each generated CGImage with its
    /// time for later merge-sort ordering.
    ///
    /// RE: 0x1013cb758 (GIFCreator_imageGeneratorCallback, 1.3.15)
    /// Appends each generated CGImage to the destination with frameProperties.
    private func imageGeneratorCallback(image: CGImage, time: CMTime) {
        if firstImage == nil {
            firstImage = UIImage(cgImage: image)
        }
        collectedFrames.append((image: image, time: time))
    }

    /// Create the GIF image destination and configure loop properties.
    ///
    /// RE: 0x1013e608c (GIFCreator_createImageDestination, 1.3.15)
    /// Deletes any existing output file (NSFileManager removeItemAtURL:),
    /// builds the GIF dictionaries — kCGImagePropertyGIFDictionary containing
    /// kCGImagePropertyGIFDelayTime = 0.25 (0x3FD0000000000000) and
    /// kCGImagePropertyGIFLoopCount = 0 (infinite) — then
    /// CGImageDestinationCreateWithURL + CGImageDestinationSetProperties;
    /// stores the destination at self+0x10 and the per-frame property dict
    /// at self+0x18.
    private func createImageDestination(imagesCount: Int) {
        // Delete existing file if present
        try? FileManager.default.removeItem(at: savePath)

        // Per-frame properties: delay time 0.25s
        // RE: binary encodes 0x3FD0000000000000 = 0.25 IEEE 754 double
        frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]
        ] as CFDictionary

        // Create destination
        guard let dest = CGImageDestinationCreateWithURL(
            savePath as CFURL,
            kUTTypeGIF,
            imagesCount,
            nil
        ) else {
            destination = nil
            return
        }

        // File-level properties: infinite loop (loopCount = 0)
        let fileProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary
        CGImageDestinationSetProperties(dest, fileProperties)

        destination = dest
    }

    /// Merge-sort the collected frames by time, write them to the GIF
    /// destination in chronological order, and finalize.
    ///
    /// RE: 0x1013cbbc0 (GIFCreator_mergeSort, 1.3.15)
    /// Merge-sort over the captured frame list — orders frames by time
    /// before writing to the GIF destination. Without this sort, GIF frames
    /// may be out of order because AVAssetImageGenerator does not guarantee
    /// chronological callback order.
    private func finalizeWithMergeSort() -> Bool {
        guard let destination, let frameProperties else { return false }

        // Sort frames chronologically via merge sort
        let sorted = mergeSort(collectedFrames)

        // Write sorted frames to destination
        for frame in sorted {
            CGImageDestinationAddImage(destination, frame.image, frameProperties)
        }

        return CGImageDestinationFinalize(destination)
    }

    /// Stable merge-sort implementation for frame ordering.
    ///
    /// RE: 0x1013cbbc0 (GIFCreator_mergeSort, 1.3.15)
    /// Merge-sort over the captured frame list (orders frames by time
    /// before writing). Uses CMTime comparison for correct ordering.
    private func mergeSort(_ array: [(image: CGImage, time: CMTime)]) -> [(image: CGImage, time: CMTime)] {
        guard array.count > 1 else { return array }

        let mid = array.count / 2
        let left = mergeSort(Array(array[0 ..< mid]))
        let right = mergeSort(Array(array[mid...]))

        return merge(left, right)
    }

    /// Merge two sorted arrays by time.
    private func merge(
        _ left: [(image: CGImage, time: CMTime)],
        _ right: [(image: CGImage, time: CMTime)]
    ) -> [(image: CGImage, time: CMTime)] {
        var result = [(image: CGImage, time: CMTime)]()
        result.reserveCapacity(left.count + right.count)

        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < left.count, rightIndex < right.count {
            if CMTimeCompare(left[leftIndex].time, right[rightIndex].time) <= 0 {
                result.append(left[leftIndex])
                leftIndex += 1
            } else {
                result.append(right[rightIndex])
                rightIndex += 1
            }
        }

        result.append(contentsOf: left[leftIndex...])
        result.append(contentsOf: right[rightIndex...])
        return result
    }
}
