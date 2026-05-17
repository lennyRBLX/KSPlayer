//
//  TranscodeContext.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15
//  - OutputStreamInfo_createForRemuxing (0x1012ED66C)
//  - TranscodeContext_createForStreamIndex (0x1012E8BEC)
//  - BSFContext_findAndInitFilter (0x1012E9060)
//  - AudioTranscodeContext_init (0x1012E9EE4)
//  - Remuxer_readLoop_body (0x1012E815C)
//  - Remuxer_setupSubtitleTranscodeContexts (0x1012E83E0)
//
//  Pipeline: Remuxer → OutputStreamInfo → per-stream TranscodeContext → packet delivery
//

import Foundation
import Libavcodec
import Libavformat
import Libavutil

// MARK: - TranscodeProtocol

public protocol TranscodeProtocol: AnyObject {
    func process(packet: UnsafeMutablePointer<AVPacket>,
                 timeBase: AVRational,
                 outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>]
    func flush() -> [UnsafeMutablePointer<AVPacket>]
    func close()
}

// MARK: - CopyTranscodeContext (passthrough)

public final class CopyTranscodeContext: TranscodeProtocol {
    public static let shared = CopyTranscodeContext()
    private init() {}

    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        av_packet_rescale_ts(packet, timeBase, outputTimeBase)
        return [packet]
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] { [] }
    public func close() {}
}

// MARK: - BSFTranscodeContext (bitstream filter)

public final class BSFTranscodeContext: TranscodeProtocol {
    private var bsfContext: UnsafeMutablePointer<AVBSFContext>?

    public init?(filterName: String, codecpar: UnsafeMutablePointer<AVCodecParameters>, timeBase: AVRational) {
        guard let filter = av_bsf_get_by_name(filterName) else {
            KSLog("[transcode] BSF filter '\(filterName)' not found")
            return nil
        }
        var ctx: UnsafeMutablePointer<AVBSFContext>?
        guard av_bsf_alloc(filter, &ctx) >= 0, let ctx else {
            return nil
        }
        avcodec_parameters_copy(ctx.pointee.par_in, codecpar)
        ctx.pointee.time_base_in = timeBase
        guard av_bsf_init(ctx) >= 0 else {
            av_bsf_free(&self.bsfContext)
            return nil
        }
        self.bsfContext = ctx
    }

    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let bsfContext else { return [packet] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        guard av_bsf_send_packet(bsfContext, packet) >= 0 else { return [] }
        while av_bsf_receive_packet(bsfContext, packet) >= 0 {
            av_packet_rescale_ts(packet, bsfContext.pointee.time_base_out, outputTimeBase)
            if let outPkt = av_packet_clone(packet) {
                results.append(outPkt)
            }
        }
        return results
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] {
        guard let bsfContext else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        av_bsf_send_packet(bsfContext, nil)
        let pkt = av_packet_alloc()!
        while av_bsf_receive_packet(bsfContext, pkt) >= 0 {
            if let outPkt = av_packet_clone(pkt) {
                results.append(outPkt)
            }
        }
        av_packet_free(&UnsafeMutablePointer(mutating: Optional(pkt)))
        return results
    }

    public func close() {
        if bsfContext != nil {
            av_bsf_free(&bsfContext)
        }
    }

    deinit { close() }
}

// MARK: - AudioTranscodeContext (decode → resample → encode)

public final class AudioTranscodeContext: TranscodeProtocol {
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var decodedFrame: UnsafeMutablePointer<AVFrame>?
    private var swrContext: OpaquePointer?
    private var pts: Int64 = 0

    public init?(inputCodecpar: UnsafeMutablePointer<AVCodecParameters>,
                 outputCodecID: AVCodecID = AV_CODEC_ID_AAC,
                 sampleRate: Int32 = 48000) {
        guard let decoder = avcodec_find_decoder(inputCodecpar.pointee.codec_id) else { return nil }
        decodeContext = avcodec_alloc_context3(decoder)
        guard let decodeContext else { return nil }
        avcodec_parameters_to_context(decodeContext, inputCodecpar)
        guard avcodec_open2(decodeContext, decoder, nil) >= 0 else { return nil }

        guard let encoder = avcodec_find_encoder(outputCodecID) else { return nil }
        encodeContext = avcodec_alloc_context3(encoder)
        guard let encodeContext else { return nil }
        encodeContext.pointee.sample_rate = sampleRate
        encodeContext.pointee.sample_fmt = encoder.pointee.sample_fmts.pointee
        encodeContext.pointee.ch_layout = decodeContext.pointee.ch_layout
        encodeContext.pointee.bit_rate = 128_000
        guard avcodec_open2(encodeContext, encoder, nil) >= 0 else { return nil }

        decodedFrame = av_frame_alloc()
    }

    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let decodeContext, let encodeContext, let decodedFrame else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        guard avcodec_send_packet(decodeContext, packet) >= 0 else { return [] }
        while avcodec_receive_frame(decodeContext, decodedFrame) >= 0 {
            decodedFrame.pointee.pts = pts
            guard avcodec_send_frame(encodeContext, decodedFrame) >= 0 else { continue }
            let outPkt = av_packet_alloc()!
            while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
                av_packet_rescale_ts(outPkt, encodeContext.pointee.time_base, outputTimeBase)
                if let clone = av_packet_clone(outPkt) {
                    results.append(clone)
                }
            }
            av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
            pts += Int64(decodedFrame.pointee.nb_samples)
            av_frame_unref(decodedFrame)
        }
        return results
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] {
        guard let encodeContext else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        avcodec_send_frame(encodeContext, nil)
        let outPkt = av_packet_alloc()!
        while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
            if let clone = av_packet_clone(outPkt) {
                results.append(clone)
            }
        }
        av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
        return results
    }

    public func close() {
        if let decodedFrame {
            av_frame_free(&self.decodedFrame)
        }
        if decodeContext != nil {
            avcodec_free_context(&decodeContext)
        }
        if encodeContext != nil {
            avcodec_free_context(&encodeContext)
        }
    }

    deinit { close() }
}

// MARK: - VideoTranscodeContext (decode → encode, no rescale)

public final class VideoTranscodeContext: TranscodeProtocol {
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var decodedFrame: UnsafeMutablePointer<AVFrame>?

    public init?(inputCodecpar: UnsafeMutablePointer<AVCodecParameters>,
                 outputCodecID: AVCodecID) {
        guard let decoder = avcodec_find_decoder(inputCodecpar.pointee.codec_id) else { return nil }
        decodeContext = avcodec_alloc_context3(decoder)
        guard let decodeContext else { return nil }
        avcodec_parameters_to_context(decodeContext, inputCodecpar)
        guard avcodec_open2(decodeContext, decoder, nil) >= 0 else { return nil }

        guard let encoder = avcodec_find_encoder(outputCodecID) else { return nil }
        encodeContext = avcodec_alloc_context3(encoder)
        guard let encodeContext else { return nil }
        encodeContext.pointee.width = decodeContext.pointee.width
        encodeContext.pointee.height = decodeContext.pointee.height
        encodeContext.pointee.pix_fmt = decodeContext.pointee.pix_fmt
        encodeContext.pointee.time_base = decodeContext.pointee.time_base
        guard avcodec_open2(encodeContext, encoder, nil) >= 0 else { return nil }

        decodedFrame = av_frame_alloc()
    }

    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let decodeContext, let encodeContext, let decodedFrame else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        guard avcodec_send_packet(decodeContext, packet) >= 0 else { return [] }
        while avcodec_receive_frame(decodeContext, decodedFrame) >= 0 {
            guard avcodec_send_frame(encodeContext, decodedFrame) >= 0 else { continue }
            let outPkt = av_packet_alloc()!
            while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
                av_packet_rescale_ts(outPkt, encodeContext.pointee.time_base, outputTimeBase)
                if let clone = av_packet_clone(outPkt) {
                    results.append(clone)
                }
            }
            av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
            av_frame_unref(decodedFrame)
        }
        return results
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] {
        guard let encodeContext else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        avcodec_send_frame(encodeContext, nil)
        let outPkt = av_packet_alloc()!
        while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
            if let clone = av_packet_clone(outPkt) {
                results.append(clone)
            }
        }
        av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
        return results
    }

    public func close() {
        if decodedFrame != nil {
            av_frame_free(&decodedFrame)
        }
        if decodeContext != nil {
            avcodec_free_context(&decodeContext)
        }
        if encodeContext != nil {
            avcodec_free_context(&encodeContext)
        }
    }

    deinit { close() }
}

// MARK: - SubtitleTranscodeContext (text format conversion)

public final class SubtitleTranscodeContext: TranscodeProtocol {
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?

    public init?(inputCodecpar: UnsafeMutablePointer<AVCodecParameters>,
                 outputCodecID: AVCodecID = AV_CODEC_ID_WEBVTT) {
        guard let decoder = avcodec_find_decoder(inputCodecpar.pointee.codec_id) else { return nil }
        decodeContext = avcodec_alloc_context3(decoder)
        guard let decodeContext else { return nil }
        avcodec_parameters_to_context(decodeContext, inputCodecpar)
        guard avcodec_open2(decodeContext, decoder, nil) >= 0 else { return nil }

        guard let encoder = avcodec_find_encoder(outputCodecID) else { return nil }
        encodeContext = avcodec_alloc_context3(encoder)
        guard let encodeContext else { return nil }
        guard avcodec_open2(encodeContext, encoder, nil) >= 0 else { return nil }
    }

    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let decodeContext, let encodeContext else { return [] }
        var subtitle = AVSubtitle()
        var gotSub: Int32 = 0
        avcodec_decode_subtitle2(decodeContext, &subtitle, &gotSub, packet)
        guard gotSub > 0 else { return [] }
        defer { avsubtitle_free(&subtitle) }

        var results = [UnsafeMutablePointer<AVPacket>]()
        let outPkt = av_packet_alloc()!
        let bufSize: Int32 = 1024 * 1024
        let buf = av_malloc(Int(bufSize))!
        let ret = avcodec_encode_subtitle(encodeContext, buf.assumingMemoryBound(to: UInt8.self), bufSize, &subtitle)
        if ret > 0 {
            outPkt.pointee.data = buf.assumingMemoryBound(to: UInt8.self)
            outPkt.pointee.size = ret
            av_packet_rescale_ts(outPkt, timeBase, outputTimeBase)
            outPkt.pointee.pts = packet.pointee.pts
            outPkt.pointee.duration = packet.pointee.duration
            if let clone = av_packet_clone(outPkt) {
                results.append(clone)
            }
        }
        av_free(buf)
        av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
        return results
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] { [] }

    public func close() {
        if decodeContext != nil {
            avcodec_free_context(&decodeContext)
        }
        if encodeContext != nil {
            avcodec_free_context(&encodeContext)
        }
    }

    deinit { close() }
}

// MARK: - OutputStreamInfo

public final class OutputStreamInfo {
    public let url: String
    public let formatName: String
    public private(set) var formatContext: UnsafeMutablePointer<AVFormatContext>?
    public private(set) var streamMapping: [Int: Int] = [:]
    public private(set) var transcodeMap: [Int: TranscodeProtocol] = [:]
    public private(set) var timeBases: [AVRational?] = []
    private var hasWrittenTrailer = false

    public init?(url: String, formatName: String?, inputFormatContext: UnsafeMutablePointer<AVFormatContext>) {
        self.url = url
        self.formatName = formatName ?? "mp4"
        var outputCtx: UnsafeMutablePointer<AVFormatContext>?
        let ret = avformat_alloc_output_context2(&outputCtx, nil, formatName, url)
        guard ret >= 0, let outputCtx else {
            KSLog("[transcode] failed to alloc output context: \(ret)")
            return nil
        }
        self.formatContext = outputCtx

        let streamCount = Int(inputFormatContext.pointee.nb_streams)
        var outputStreamIndex = 0

        for i in 0 ..< streamCount {
            guard let inputStream = inputFormatContext.pointee.streams[i] else { continue }
            let codecpar = inputStream.pointee.codecpar!
            let mediaType = codecpar.pointee.codec_type

            guard mediaType == AVMEDIA_TYPE_VIDEO || mediaType == AVMEDIA_TYPE_AUDIO || mediaType == AVMEDIA_TYPE_SUBTITLE else {
                continue
            }

            guard let outputStream = avformat_new_stream(outputCtx, nil) else { continue }
            avcodec_parameters_copy(outputStream.pointee.codecpar, codecpar)
            outputStream.pointee.codecpar.pointee.codec_tag = 0

            streamMapping[i] = outputStreamIndex
            timeBases.append(outputStream.pointee.time_base)
            outputStreamIndex += 1

            let context = createTranscodeContext(
                codecpar: codecpar,
                mediaType: mediaType,
                inputTimeBase: inputStream.pointee.time_base,
                outputFormatName: self.formatName,
                streamCount: streamCount
            )
            transcodeMap[i] = context
        }
    }

    private func createTranscodeContext(
        codecpar: UnsafeMutablePointer<AVCodecParameters>,
        mediaType: AVMediaType,
        inputTimeBase: AVRational,
        outputFormatName: String,
        streamCount: Int
    ) -> TranscodeProtocol {
        if mediaType == AVMEDIA_TYPE_AUDIO {
            let codecID = codecpar.pointee.codec_id
            if codecID == AV_CODEC_ID_AAC, streamCount >= 3 {
                let isMPEGTS = outputFormatName == "mpegts" || outputFormatName == "hls"
                if !isMPEGTS {
                    if let bsf = BSFTranscodeContext(filterName: "aac_adtstoasc",
                                                     codecpar: codecpar,
                                                     timeBase: inputTimeBase) {
                        return bsf
                    }
                }
            }
        } else if mediaType == AVMEDIA_TYPE_VIDEO {
            let codecID = codecpar.pointee.codec_id
            let outputIsMPEGTS = outputFormatName == "mpegts" || outputFormatName == "hls"
            if outputIsMPEGTS {
                if codecID == AV_CODEC_ID_H264 {
                    if let bsf = BSFTranscodeContext(filterName: "h264_mp4toannexb",
                                                     codecpar: codecpar,
                                                     timeBase: inputTimeBase) {
                        return bsf
                    }
                } else if codecID == AV_CODEC_ID_HEVC {
                    if let bsf = BSFTranscodeContext(filterName: "hevc_mp4toannexb",
                                                     codecpar: codecpar,
                                                     timeBase: inputTimeBase) {
                        return bsf
                    }
                }
            }
        }

        return CopyTranscodeContext.shared
    }

    public func writeHeader() -> Bool {
        guard let formatContext else { return false }
        if formatContext.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            guard avio_open(&formatContext.pointee.pb, url, AVIO_FLAG_WRITE) >= 0 else {
                KSLog("[transcode] failed to open output: \(url)")
                return false
            }
        }
        return avformat_write_header(formatContext, nil) >= 0
    }

    public func writePacket(_ packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        guard let formatContext else { return false }
        return av_interleaved_write_frame(formatContext, packet) >= 0
    }

    public func writeTrailer() {
        guard !hasWrittenTrailer, let formatContext else { return }
        av_write_trailer(formatContext)
        if formatContext.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            avio_closep(&formatContext.pointee.pb)
        }
        hasWrittenTrailer = true
    }

    public func close() {
        writeTrailer()
        if formatContext != nil {
            avformat_free_context(formatContext)
            formatContext = nil
        }
    }

    deinit { close() }
}

// MARK: - Remuxer

public final class Remuxer: @unchecked Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let outputFormat: String?
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputStreamInfo: OutputStreamInfo?
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private var isCancelled = false
    public var progressHandler: ((Double) -> Void)?

    public init(inputURL: URL, outputURL: URL, outputFormat: String? = nil) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deallocate()
    }

    public func remux() async -> Bool {
        var formatCtx: UnsafeMutablePointer<AVFormatContext>?
        let inputPath = inputURL.path
        guard avformat_open_input(&formatCtx, inputPath, nil, nil) >= 0, let formatCtx else {
            KSLog("[remuxer] failed to open input: \(inputPath)")
            return false
        }
        inputFormatContext = formatCtx

        guard avformat_find_stream_info(formatCtx, nil) >= 0 else {
            KSLog("[remuxer] failed to find stream info")
            cleanup()
            return false
        }

        let outputPath = outputURL.path
        guard let info = OutputStreamInfo(url: outputPath,
                                          formatName: outputFormat,
                                          inputFormatContext: formatCtx) else {
            cleanup()
            return false
        }
        outputStreamInfo = info

        guard info.writeHeader() else {
            KSLog("[remuxer] failed to write header")
            cleanup()
            return false
        }

        let duration = Double(formatCtx.pointee.duration) / Double(AV_TIME_BASE)
        var lastProgressTime = CACurrentMediaTime()
        let packet = av_packet_alloc()!

        while av_read_frame(formatCtx, packet) >= 0 {
            os_unfair_lock_lock(lock)
            let cancelled = isCancelled
            os_unfair_lock_unlock(lock)
            if cancelled { break }

            let streamIndex = Int(packet.pointee.stream_index)
            guard let outputIndex = info.streamMapping[streamIndex],
                  let inputStream = formatCtx.pointee.streams[streamIndex] else {
                av_packet_unref(packet)
                continue
            }

            let inputTimeBase = inputStream.pointee.time_base
            let outputTimeBase = info.timeBases[outputIndex] ?? inputTimeBase
            let context = info.transcodeMap[streamIndex] ?? CopyTranscodeContext.shared

            let outputPackets = context.process(packet: packet, timeBase: inputTimeBase, outputTimeBase: outputTimeBase)
            for outPkt in outputPackets {
                outPkt.pointee.stream_index = Int32(outputIndex)
                _ = info.writePacket(outPkt)
                if outPkt != packet {
                    av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
                }
            }

            let now = CACurrentMediaTime()
            if now - lastProgressTime >= 3.0, duration > 0 {
                let pts = Double(packet.pointee.pts) * av_q2d(inputTimeBase)
                let progress = min(pts / duration, 1.0)
                progressHandler?(progress)
                lastProgressTime = now
            }

            av_packet_unref(packet)
        }

        for (streamIndex, context) in info.transcodeMap {
            let flushed = context.flush()
            for outPkt in flushed {
                if let outputIndex = info.streamMapping[streamIndex] {
                    outPkt.pointee.stream_index = Int32(outputIndex)
                    _ = info.writePacket(outPkt)
                }
                av_packet_free(&UnsafeMutablePointer(mutating: Optional(outPkt)))
            }
        }

        av_packet_free(&UnsafeMutablePointer(mutating: Optional(packet)))
        progressHandler?(1.0)
        cleanup()
        return true
    }

    public func cancel() {
        os_unfair_lock_lock(lock)
        isCancelled = true
        os_unfair_lock_unlock(lock)
    }

    private func cleanup() {
        for (_, context) in outputStreamInfo?.transcodeMap ?? [:] {
            context.close()
        }
        outputStreamInfo?.close()
        outputStreamInfo = nil
        if inputFormatContext != nil {
            avformat_close_input(&inputFormatContext)
        }
    }
}
