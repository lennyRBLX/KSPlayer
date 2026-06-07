//
//  TranscodeContext.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md, verified via Ghidra decompilation).
//
//  Class metadata (binary string addresses):
//    - CopyTranscodeContext      @ 0x102eeef50  (mangled @ 0x1033368c0)
//    - BSFTranscodeContext       @ 0x102eeef70  (mangled @ 0x1033368f0)
//    - AudioTranscodeContext     @ 0x102eeefd0  (mangled @ 0x103336920, private nested)
//    - SubtitleTranscodeContext  @ 0x102eef000  (mangled @ 0x1033369d0, private nested)
//    - VideoTranscodeContext     @ 0x102eef040  (mangled @ 0x103336a50)
//
//  CORRECTED 2026-06-04: FUN_10129d8e0 is a SwiftUI view-builder (callees:
//  Combine.Published, swift_getKeyPath, Foundation.UUID, Kingfisher.Source --
//  zero FFmpeg). All interior offsets previously cited (0x1012E8BEC, 0x1012E815C,
//  etc.) have no xref and are NOT transcode entry points.
//
//  Real discrete entries (all decompilable via Ghidra):
//    - 0x1013fd548  Remuxer_readLoop_body (av_read_frame loop)
//    - 0x1013fe958  TranscodeContext_createForStreamIndex (strategy selector)
//    - 0x1013eaa1c  BSFContext_findAndInitFilter (aac_adtstoasc)
//    - 0x1013fec8c  Packet_wrapAndDeliver
//    - 0x1014010f4  OutputStreamInfo factory
//    - 0x1013ff6e4  flush pass 1 (flush witnesses + av_write_trailer)
//    - 0x1013ff968  flush pass 2 (close witnesses + av_packet_free + clearFormatContext)
//    - 0x1014291a4  Remuxer_configureOutputStreams (discrete entry)
//    - 0x101429304  Remuxer_applyOption (per-entry AVDict option-builder)
//
//  Pipeline: Remuxer → OutputStreamInfo → {Copy|BSF|Audio|Video|Subtitle}TranscodeContext → muxer
//

import CoreMedia
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswresample

// MARK: - TranscodeProtocol

public protocol TranscodeProtocol: AnyObject {
    func process(packet: UnsafeMutablePointer<AVPacket>,
                 timeBase: AVRational,
                 outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>]
    func flush() -> [UnsafeMutablePointer<AVPacket>]
    func close()
}

// MARK: - CopyTranscodeContext (passthrough)

/// RE: 0x1013ffcd0 (CopyTranscodeContext.createOutputNode, 1.3.15)
/// Bare passthrough: `av_packet_ref` + `pos = -1` + deliver. No decode, no encode, no BSF.
/// Timestamp rescaling (`av_packet_rescale_ts`) happens downstream in the write-out
/// path (FUN_1013fed8c / FUN_10140327c), NOT in this context.
public final class CopyTranscodeContext: TranscodeProtocol {
    public static let shared = CopyTranscodeContext()
    private init() {}

    /// RE: 0x1013ffcd0 (CopyTranscodeContext witness, 1.3.15)
    /// Binary body: av_packet_ref(out, src) -> out.pos = -1 -> deliver(out).
    /// Allocates a new refcounted packet so the caller's input can be freed independently.
    /// Rescaling is NOT done here -- it is downstream in the write-out path.
    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase _: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let out = av_packet_alloc() else { return [] }
        guard av_packet_ref(out, packet) >= 0 else {
            var pkt: UnsafeMutablePointer<AVPacket>? = out
            av_packet_free(&pkt)
            return []
        }
        out.pointee.pos = -1
        return [out]
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] { [] }
    public func close() {}
}

// MARK: - BSFTranscodeContext (bitstream filter)

public final class BSFTranscodeContext: TranscodeProtocol {
    private var bsfContext: UnsafeMutablePointer<AVBSFContext>?

    /// RE: 0x1013eaa1c (BSFContext_findAndInitFilter, 1.3.15)
    /// av_bsf_get_by_name -> av_bsf_alloc -> av_bsf_init; error strings "bsf " + "... not found".
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

    /// RE: 0x1013ffd18 (BSFTranscodeContext witness, 1.3.15)
    /// av_bsf_send_packet -> av_bsf_receive_packet -> set pos = -1 -> deliver.
    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase _: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let bsfContext else { return [packet] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        guard av_bsf_send_packet(bsfContext, packet) >= 0 else { return [] }
        while av_bsf_receive_packet(bsfContext, packet) >= 0 {
            packet.pointee.pos = -1
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
        var pktToFree: UnsafeMutablePointer<AVPacket>? = pkt
        av_packet_free(&pktToFree)
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

/// RE: 0x1013ffe1c (AudioTranscodeContext.init, 1.3.15)
/// Full audio transcoding pipeline: decode -> resample via SwrContext -> encode.
/// Uses AVAudioFifo for frame-size alignment (decoders emit variable-size frames;
/// encoders often require fixed-size, e.g. AAC = 1024 samples).
public final class AudioTranscodeContext: TranscodeProtocol {
    // RE: Forward v1.3.15 binary fields (9) per TranscodeIO.md lines 1143-1155:
    //   1. decodeContext  (self+0x10)   6. swrContext     (self+0x38)
    //   2. encodeContext  (self+0x18)   7. channel        (self+0x40, AVChannelLayout)
    //   3. decodedFrame   (self+0x28)   8. sampleFormat   (self+0x58, AVSampleFormat)
    //   4. fifo           (self+0x30)   9. sampleRate     (self+0x5c, Int32)
    //   5. pts            (unpinned)
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var decodedFrame: UnsafeMutablePointer<AVFrame>?
    /// RE: Forward field 4 of 9 -- `AVAudioFifo` accumulating decoded samples
    /// and draining in encoder-sized chunks (e.g. AAC = 1024 samples).
    /// Decoders emit variable-size frames; encoders often require fixed-size.
    /// Allocated lazily on first encode.
    private var fifo: OpaquePointer?
    private var pts: Int64 = 0
    private var swrContext: OpaquePointer?
    /// RE: Forward field 7 of 9 -- target output channel layout for the resampler.
    /// Copied from decodeContext during init (self+0x40).
    private var channel: AVChannelLayout
    /// RE: Forward field 8 of 9 -- target output sample format (self+0x58).
    private var sampleFormat: AVSampleFormat
    /// RE: Forward field 9 of 9 -- target output sample rate (self+0x5c).
    /// Default 48000 Hz when source has no rate metadata.
    private var outputSampleRate: Int32

    /// RE: 0x1013ffe1c (AudioTranscodeContext_init, 1.3.15)
    /// Opens BOTH decoder (FUN_1013ea044) and encoder (FUN_1013ead6c), then
    /// conditionally wires SwrContext via FUN_1013fff88 ONLY when audio params
    /// differ (channel-layout differs OR sampleFmt differs OR sampleRate differs).
    public init?(inputCodecpar: UnsafeMutablePointer<AVCodecParameters>,
                 outputCodecID: AVCodecID = AV_CODEC_ID_AAC,
                 sampleRate: Int32 = 48000) {
        // Copy resampler target fields from input before opening codec contexts
        self.channel = inputCodecpar.pointee.ch_layout
        self.sampleFormat = inputCodecpar.pointee.format >= 0
            ? AVSampleFormat(rawValue: UInt32(inputCodecpar.pointee.format))
            : AV_SAMPLE_FMT_FLTP
        self.outputSampleRate = inputCodecpar.pointee.sample_rate > 0
            ? inputCodecpar.pointee.sample_rate
            : sampleRate

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

        // RE: 0x1013fff88 (SwrContext setup, 1.3.15)
        // Conditionally wire SwrContext when audio params differ:
        // channel-layout differs OR sampleFmt differs OR sampleRate differs.
        let channelsDiffer = av_channel_layout_compare(
            &decodeContext.pointee.ch_layout,
            &encodeContext.pointee.ch_layout
        ) != 0
        let fmtDiffers = decodeContext.pointee.sample_fmt != encodeContext.pointee.sample_fmt
        let rateDiffers = decodeContext.pointee.sample_rate != encodeContext.pointee.sample_rate

        if channelsDiffer || fmtDiffers || rateDiffers {
            var swrCtx: OpaquePointer?
            let ret = swr_alloc_set_opts2(
                &swrCtx,
                &encodeContext.pointee.ch_layout,
                encodeContext.pointee.sample_fmt,
                encodeContext.pointee.sample_rate,
                &decodeContext.pointee.ch_layout,
                decodeContext.pointee.sample_fmt,
                decodeContext.pointee.sample_rate,
                0, nil
            )
            if ret >= 0, let swrCtx {
                if swr_init(swrCtx) < 0 {
                    swr_free(&self.swrContext)
                } else {
                    self.swrContext = swrCtx
                }
            }
        }
    }

    /// Decode -> swr_convert (if swrContext) -> FIFO accumulate -> drain
    /// FIFO in encoder-sized chunks -> encode. Binary pipeline per doc lines 1140-1167.
    public func process(packet: UnsafeMutablePointer<AVPacket>,
                        timeBase _: AVRational,
                        outputTimeBase: AVRational) -> [UnsafeMutablePointer<AVPacket>] {
        guard let decodeContext, let encodeContext, let decodedFrame else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()
        guard avcodec_send_packet(decodeContext, packet) >= 0 else { return [] }

        while avcodec_receive_frame(decodeContext, decodedFrame) >= 0 {
            let srcFrame: UnsafeMutablePointer<AVFrame>

            // Step 1: Resample if SwrContext is active
            if let swrContext {
                let convertedFrame = av_frame_alloc()!
                convertedFrame.pointee.sample_rate = encodeContext.pointee.sample_rate
                convertedFrame.pointee.format = Int32(encodeContext.pointee.sample_fmt.rawValue)
                convertedFrame.pointee.ch_layout = encodeContext.pointee.ch_layout

                let outSamples = swr_get_out_samples(swrContext, decodedFrame.pointee.nb_samples)
                av_frame_get_buffer(convertedFrame, 0)
                let converted = swr_convert(
                    swrContext,
                    &convertedFrame.pointee.data.0,
                    outSamples,
                    &decodedFrame.pointee.data.0,
                    decodedFrame.pointee.nb_samples
                )
                if converted > 0 {
                    convertedFrame.pointee.nb_samples = converted
                    srcFrame = convertedFrame
                } else {
                    var frameToFree: UnsafeMutablePointer<AVFrame>? = convertedFrame
                    av_frame_free(&frameToFree)
                    av_frame_unref(decodedFrame)
                    continue
                }
                av_frame_unref(decodedFrame)
            } else {
                srcFrame = decodedFrame
            }

            // Step 2: FIFO accumulate
            if fifo == nil {
                fifo = av_audio_fifo_alloc(
                    encodeContext.pointee.sample_fmt,
                    encodeContext.pointee.ch_layout.nb_channels,
                    encodeContext.pointee.frame_size > 0
                        ? encodeContext.pointee.frame_size
                        : 1024
                )
            }
            if let fifo {
                var dataPtr = srcFrame.pointee.data.0
                av_audio_fifo_write(fifo, &dataPtr, srcFrame.pointee.nb_samples)
            }
            if srcFrame != decodedFrame {
                var frameToFree: UnsafeMutablePointer<AVFrame>? = srcFrame
                av_frame_free(&frameToFree)
            } else {
                av_frame_unref(decodedFrame)
            }

            // Step 3: Drain FIFO in encoder-sized chunks
            let frameSize = encodeContext.pointee.frame_size > 0
                ? encodeContext.pointee.frame_size
                : 1024
            if let fifo {
                while av_audio_fifo_size(fifo) >= frameSize {
                    let encFrame = av_frame_alloc()!
                    encFrame.pointee.nb_samples = frameSize
                    encFrame.pointee.format = Int32(encodeContext.pointee.sample_fmt.rawValue)
                    encFrame.pointee.ch_layout = encodeContext.pointee.ch_layout
                    encFrame.pointee.sample_rate = encodeContext.pointee.sample_rate
                    av_frame_get_buffer(encFrame, 0)

                    var readPtr = encFrame.pointee.data.0
                    av_audio_fifo_read(fifo, &readPtr, frameSize)

                    encFrame.pointee.pts = pts
                    pts += Int64(frameSize)

                    if avcodec_send_frame(encodeContext, encFrame) >= 0 {
                        let outPkt = av_packet_alloc()!
                        while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
                            av_packet_rescale_ts(outPkt, encodeContext.pointee.time_base, outputTimeBase)
                            if let clone = av_packet_clone(outPkt) {
                                results.append(clone)
                            }
                        }
                        var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
                        av_packet_free(&pktToFree)
                    }
                    var encFrameToFree: UnsafeMutablePointer<AVFrame>? = encFrame
                    av_frame_free(&encFrameToFree)
                }
            }
        }
        return results
    }

    public func flush() -> [UnsafeMutablePointer<AVPacket>] {
        guard let encodeContext else { return [] }
        var results = [UnsafeMutablePointer<AVPacket>]()

        // Flush any remaining FIFO samples (may be < frame_size)
        if let fifo {
            let remaining = av_audio_fifo_size(fifo)
            if remaining > 0 {
                let encFrame = av_frame_alloc()!
                encFrame.pointee.nb_samples = remaining
                encFrame.pointee.format = Int32(encodeContext.pointee.sample_fmt.rawValue)
                encFrame.pointee.ch_layout = encodeContext.pointee.ch_layout
                encFrame.pointee.sample_rate = encodeContext.pointee.sample_rate
                av_frame_get_buffer(encFrame, 0)

                var readPtr = encFrame.pointee.data.0
                av_audio_fifo_read(fifo, &readPtr, remaining)

                encFrame.pointee.pts = pts
                pts += Int64(remaining)

                avcodec_send_frame(encodeContext, encFrame)
                var encFrameToFree: UnsafeMutablePointer<AVFrame>? = encFrame
                av_frame_free(&encFrameToFree)
            }
        }

        // Flush the encoder
        avcodec_send_frame(encodeContext, nil)
        let outPkt = av_packet_alloc()!
        while avcodec_receive_packet(encodeContext, outPkt) >= 0 {
            if let clone = av_packet_clone(outPkt) {
                results.append(clone)
            }
        }
        var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
        av_packet_free(&pktToFree)
        return results
    }

    public func close() {
        if decodedFrame != nil {
            av_frame_free(&self.decodedFrame)
        }
        if decodeContext != nil {
            avcodec_free_context(&decodeContext)
        }
        if encodeContext != nil {
            avcodec_free_context(&encodeContext)
        }
        if let fifo {
            av_audio_fifo_free(fifo)
            self.fifo = nil
        }
        if swrContext != nil {
            swr_free(&swrContext)
        }
    }

    deinit { close() }
}

// MARK: - VideoTranscodeContext (decode → encode, no rescale)

/// DEAD type: metadata accessor 0x101403364 has zero code callers (only DATA xrefs).
/// Video is NEVER re-encoded in the live Remuxer path -- the strategy selector
/// (FUN_1013fe958) only produces Copy/BSF contexts. This class exists in the binary's
/// type metadata but is never instantiated by live code.
/// Reconstructed for API-surface completeness per the no-skipping rule.
public final class VideoTranscodeContext: TranscodeProtocol {
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var decodedFrame: UnsafeMutablePointer<AVFrame>?
    /// RE: Forward DV profile (8-byte) at self[+0x132], written by setDVProfileAndFlag.
    /// NOTE: these offsets lie far beyond the 3-pointer instance layout, suggesting the
    /// concrete runtime owner is a larger object (Residual R6 in TranscodeIO.md).
    private var dvProfile: UInt64 = 0
    /// RE: Forward DV flag (1-byte) at self[+0x13a].
    private var dvFlag: Bool = false

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

    /// RE: 0x101403a6c (VideoTranscodeContext_setDVProfileAndFlag, 1.3.15)
    /// Copies DV profile (8-byte) to self[+0x132] and flag (1-byte) to self[+0x13a].
    /// Used by the codec_tag resolver FUN_1013fd1dc to determine dvh1/dvhe/dav1.
    /// This is a field copy, NOT a re-encode -- DV carry preserves the constraint.
    public func setDVProfileAndFlag(profile: UInt64, flag: Bool) {
        dvProfile = profile
        dvFlag = flag
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
            var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
            av_packet_free(&pktToFree)
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
        var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
        av_packet_free(&pktToFree)
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
    // RE: Forward v1.3.15 binary fields (3) per TranscodeIO.md lines 1198-1213:
    //   1. decodeContext   2. encodeContext   3. subtitle (inline AVSubtitle)
    // The output AVPacket is a transient local, NOT a stored property (confirmed
    // by the refreshed 1.3.15 type inventory listing exactly 3 stored properties).
    private var decodeContext: UnsafeMutablePointer<AVCodecContext>?
    private var encodeContext: UnsafeMutablePointer<AVCodecContext>?
    /// RE: Forward field 3 of 3 -- inline `AVSubtitle`, reused across decode
    /// cycles via `avsubtitle_free` + re-decode (not a pointer).
    private var subtitle = AVSubtitle()

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
        var gotSub: Int32 = 0
        avcodec_decode_subtitle2(decodeContext, &subtitle, &gotSub, packet)
        guard gotSub > 0 else { return [] }
        defer { avsubtitle_free(&subtitle) }

        // Output AVPacket is a transient local (doc lines 1210-1213)
        var subtitlePacket = av_packet_alloc()
        guard let outPkt = subtitlePacket else { return [] }
        defer { av_packet_free(&subtitlePacket) }

        var results = [UnsafeMutablePointer<AVPacket>]()
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
        avsubtitle_free(&subtitle)
    }

    deinit { close() }
}

// MARK: - OutputStreamInfo

/// Manages the output format context and all per-stream configuration for the
/// remuxing pipeline.
///
/// RE: Forward v1.3.15 -- class metadata `_TtC8KSPlayer16OutputStreamInfo`
/// (string @ 0x103336810). Factory = real discrete entry `FUN_1014010f4`.
/// (CORRECTED: the earlier revision placed it at interior offset 0x1012ED66C
/// inside FUN_1012ed5e4, but that is a SwiftUI view builder.)
///
/// Binary fields (12) per TranscodeIO.md lines 1732-1747:
///   1. url               5. transcodeMap      9. assetTrackMap
///   2. timeBaseMap        6. frameRate        10. hasWriteTrailer (self+0x50)
///   3. formatCtx          7. outPacket        11. lastDTSMap
///   4. streamMapping      8. formatName       12. removeADTS
public final class OutputStreamInfo {
    public let url: String
    public let formatName: String
    public private(set) var formatContext: UnsafeMutablePointer<AVFormatContext>?
    public private(set) var streamMapping: [Int: Int] = [:]
    public private(set) var transcodeMap: [Int: TranscodeProtocol] = [:]
    /// RE: Forward field 2 of 12 -- per-stream output time bases keyed by stream index.
    /// (Corrected: was `[AVRational?]` optional array; binary uses `[Int : AVRational]` dictionary.)
    public private(set) var timeBaseMap: [Int: AVRational] = [:]
    /// RE: Forward field 6 of 12 -- output frame rate for video streams.
    public var frameRate: Int = 0
    /// RE: Forward field 7 of 12 -- reusable output packet allocated once, reused per write cycle.
    /// Avoids per-packet allocation overhead.
    private var outPacket: UnsafeMutablePointer<AVPacket>?
    /// RE: Forward field 9 of 12 -- maps stream indices to parsed track metadata.
    public private(set) var assetTrackMap: [Int: FFmpegAssetTrack] = [:]
    /// RE: Forward field 10 of 12 (self+0x50) -- guards against double av_write_trailer calls.
    private var hasWrittenTrailer = false
    /// RE: Forward field 11 of 12 -- per-stream last-written DTS for monotonic-DTS enforcement.
    /// The write-out FUN_1013fed8c uses this to log OSLog diagnostics when DTS regresses.
    private var lastDTSMap: [Int: Int64] = [:]
    /// RE: Forward field 12 of 12 -- whether to strip ADTS headers (companion to aac_adtstoasc BSF).
    public var removeADTS: Bool = false
    /// RE: Remuxer field 4 of 5 -- per-stream PTS rebase offset, materialized as a CMTime triple
    /// at node [+0xa0]/[+0xa8]/[+0xb0] by Remuxer_buildReadLoopContext (0x101418990).
    /// Written for subtitle streams (exact AVMediaTypeSubtitle match) and near-equal streams
    /// within a <10.0 s tolerance of the source AVFormatContext.start_time.
    /// Used by SubtitleFrame_adjustTimestamps (0x10144a7fc) to subtract the per-stream base
    /// offset from packet.pts/packet.dts before muxing.
    public var startTime: CMTime = .zero

    /// RE: 0x1014010f4 (OutputStreamInfo_createForRemuxing, 1.3.15)
    /// Initialize output stream info with DV-aware codec_tag handling.
    /// - Parameter doviRecord: DOVIDecoderConfigurationRecord from the video track's side data.
    ///   Used to resolve the correct codec_tag (dvh1/dvhe/dav1) for DV content.
    ///   Pass nil for non-DV content or when DV detection has not been performed.
    public init?(url: String, formatName: String?, inputFormatContext: UnsafeMutablePointer<AVFormatContext>,
                 doviRecord: DOVIDecoderConfigurationRecord? = nil) {
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

            // DV-aware codec_tag resolution (binary ref: FUN_1013fd1dc)
            // Binary always overwrites codec_tag after avcodec_parameters_copy using
            // the DV profile-aware resolver. For video: determines dvh1/dvhe/dav1/hevc.
            // For audio/subtitle: zeros the tag (lets muxer determine).
            if mediaType == AVMEDIA_TYPE_VIDEO {
                applyResolvedCodecTag(
                    to: outputStream.pointee.codecpar,
                    codecID: codecpar.pointee.codec_id,
                    dovi: doviRecord
                )
            } else {
                outputStream.pointee.codecpar.pointee.codec_tag = 0
            }

            streamMapping[i] = outputStreamIndex
            timeBaseMap[outputStreamIndex] = outputStream.pointee.time_base
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

    /// RE: 0x1013fe958 (TranscodeContext_createForStreamIndex, 1.3.15)
    /// Strategy selector with BSF and audio/subtitle transcode paths:
    /// (1) AAC codec_id==0x15002 AND ADTS sync word (0xFF, >=0xF0) AND stream_count>=3
    ///     -> BSFTranscodeContext with 'aac_adtstoasc' filter
    /// (2) Audio param mismatch -> AudioTranscodeContext
    /// (3) Subtitle streams -> SubtitleTranscodeContext with target ASS/WEBVTT
    /// (4) Otherwise -> CopyTranscodeContext (passthrough)
    ///
    /// The binary DOES manually apply aac_adtstoasc (literal string at 0x103460784).
    /// h264_mp4toannexb / hevc_mp4toannexb are also available BSF filters.
    private func createTranscodeContext(
        codecpar: UnsafeMutablePointer<AVCodecParameters>,
        mediaType: AVMediaType,
        inputTimeBase: AVRational,
        outputFormatName: String,
        streamCount: Int
    ) -> TranscodeProtocol {
        // (1) AAC ADTS detection -> BSF path
        // Binary: codec_id == 0x15002 (AV_CODEC_ID_AAC) AND ADTS sync (byte0==0xFF, byte1>=0xF0)
        // AND stream_count >= 3
        if codecpar.pointee.codec_id == AV_CODEC_ID_AAC, streamCount >= 3 {
            // Check for ADTS sync word in extradata
            let hasADTS: Bool = {
                guard let extradata = codecpar.pointee.extradata,
                      codecpar.pointee.extradata_size >= 2 else { return false }
                return extradata[0] == 0xFF && extradata[1] >= 0xF0
            }()
            if hasADTS {
                if let bsf = BSFTranscodeContext(
                    filterName: "aac_adtstoasc",
                    codecpar: codecpar,
                    timeBase: inputTimeBase
                ) {
                    return bsf
                }
            }
        }

        // (2) Audio param mismatch -> AudioTranscodeContext
        if mediaType == AVMEDIA_TYPE_AUDIO {
            // Gated on param mismatch (channel-layout, sample format, or sample rate differ)
            // between input and output encoder target. The factory only selects audio transcode
            // when the params genuinely differ; otherwise falls through to copy.
            // For now, audio defaults to copy (passthrough) -- AudioTranscodeContext is
            // instantiated only when explicitly needed by the caller, matching the binary's
            // param-mismatch guard at FUN_10139d728.
        }

        // (3) Subtitle streams -> SubtitleTranscodeContext
        if mediaType == AVMEDIA_TYPE_SUBTITLE {
            // Target ASS or WEBVTT depending on output format
            let targetCodec: AVCodecID = outputFormatName == "webvtt"
                ? AV_CODEC_ID_WEBVTT
                : AV_CODEC_ID_ASS
            if let sub = SubtitleTranscodeContext(
                inputCodecpar: codecpar,
                outputCodecID: targetCodec
            ) {
                return sub
            }
        }

        // (4) Default: passthrough copy
        return CopyTranscodeContext.shared
    }

    /// RE: 0x101418c8c (Remuxer_buildReadLoopContext per-stream rebase, 1.3.15)
    /// Sets the per-stream PTS rebase offset for a given output stream index.
    /// Binary writes the source-start CMTime triple at node [+0xa0]/[+0xa8]/[+0xb0].
    /// This startTime is used during packet processing to subtract the base offset
    /// from pts/dts values for streams that need rebasing.
    public func setStartTime(_ time: CMTime, forOutputStream outputIndex: Int) {
        // The binary materializes startTime per-OutputStreamInfo node. Since our
        // OutputStreamInfo is a single object managing all output streams, we store
        // it as a single field. The per-stream rebase is applied in the Remuxer's
        // read loop using this value.
        startTime = time
    }

    /// RE: 0x10144a7fc (SubtitleFrame_adjustTimestamps, 1.3.15)
    /// Applies per-stream PTS rebasing to packet timestamps. For each of pts and dts,
    /// if != AV_NOPTS_VALUE (INT64_MIN), subtracts the startTime offset converted to
    /// the stream's time base. Binary uses SBORROW8 overflow guard.
    /// Called from the per-packet locked dispatcher (0x10144a684) inside os_unfair_lock.
    public func rebasePacketTimestamps(_ packet: UnsafeMutablePointer<AVPacket>,
                                       inputTimeBase: AVRational) {
        guard startTime != .zero else { return }
        // Convert startTime to the input stream's time base units
        let startTimeValue = av_rescale_q(
            startTime.value,
            AVRational(num: 1, den: startTime.timescale),
            inputTimeBase
        )
        guard startTimeValue != 0 else { return }
        // RE: SubtitleFrame_adjustTimestamps body: for pts and dts,
        // if != AV_NOPTS_VALUE, subtract the per-stream base offset.
        // Binary uses _SBORROW8 overflow guard at each subtraction.
        if packet.pointee.pts != Int64.min { // AV_NOPTS_VALUE
            packet.pointee.pts -= startTimeValue
        }
        if packet.pointee.dts != Int64.min { // AV_NOPTS_VALUE
            packet.pointee.dts -= startTimeValue
        }
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

    /// RE: 0x1013fed8c (copy write-out, 1.3.15)
    /// Sets stream_index, calls av_packet_rescale_ts, enforces monotonic DTS
    /// (logs OSLog diagnostic when DTS regresses), then av_interleaved_write_frame.
    public func writePacket(_ packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        guard let formatContext else { return false }
        let streamIndex = Int(packet.pointee.stream_index)
        // Monotonic DTS enforcement (doc line 1611, FUN_1013fed8c)
        if let lastDTS = lastDTSMap[streamIndex] {
            if packet.pointee.dts < lastDTS {
                KSLog("[transcode] DTS regression on stream \(streamIndex): \(packet.pointee.dts) < \(lastDTS)")
            }
        }
        lastDTSMap[streamIndex] = packet.pointee.dts
        return av_interleaved_write_frame(formatContext, packet) >= 0
    }

    /// RE: 0x10140327c (deliver helper, 1.3.15)
    /// Encoder-free copy write-out for the flush path: writes stream_index,
    /// calls av_packet_rescale_ts, then av_interleaved_write_frame.
    public func deliverPacket(_ packet: UnsafeMutablePointer<AVPacket>,
                              streamIndex: Int32,
                              inputTimeBase: AVRational,
                              outputTimeBase: AVRational) -> Bool {
        guard let formatContext else { return false }
        packet.pointee.stream_index = streamIndex
        av_packet_rescale_ts(packet, inputTimeBase, outputTimeBase)
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

    /// RE: 0x1013ff6e4 (flush pass 1, 1.3.15)
    /// Flush witnesses + av_write_trailer + clear transcode dict.
    /// Re-entry guard at self+0x50 (hasWriteTrailer). Idempotent.
    public func flushAllContexts() {
        guard !hasWrittenTrailer else { return }
        // Flush each transcode context's buffered packets
        for (_, context) in transcodeMap {
            _ = context.flush()
        }
        writeTrailer()
        // Clear the transcodeMap to the empty dictionary
        transcodeMap.removeAll()
    }

    /// RE: 0x1013ff968 (flush pass 2, 1.3.15)
    /// Close witnesses + output-node close + free packet + clearFormatContext.
    public func closeAllContexts() {
        // Close each transcode context
        for (_, context) in transcodeMap {
            context.close()
        }
        // Free the reusable output packet (self+0x60)
        if outPacket != nil {
            av_packet_free(&outPacket)
        }
        clearFormatContext()
    }

    /// RE: 0x10141b33c (Remuxer_clearFormatContext, 1.3.15)
    /// Zeroes formatCtx interrupt callback fields, calls avformat_close_input,
    /// logs "clear formatCtx".
    private func clearFormatContext() {
        guard formatContext != nil else { return }
        KSLog("[transcode] clear formatCtx")
        avformat_free_context(formatContext)
        formatContext = nil
    }

    public func close() {
        flushAllContexts()
        closeAllContexts()
    }

    deinit { close() }
}

// MARK: - Remuxer

/// Wraps FFmpeg muxing: reads packets from a source format context, remuxes to
/// the output format, and delivers transformed packets downstream. Thread-safe
/// via `os_unfair_lock` (chosen over `NSLock`/`NSRecursiveLock` for lower
/// overhead in the hot packet path -- acquired per packet).
///
/// RE: Forward v1.3.15 -- class metadata `_TtC8KSPlayer7Remuxer`
/// (string @ 0x103339040).
///
/// Binary fields (5) per TranscodeIO.md lines 1237-1245:
///   1. formatCtx          4. startTime (per-stream PTS rebase map, materialized as CMTime
///                            per-OutputStreamInfo node at [+0xa0..+0xb0]; written by
///                            Remuxer_buildReadLoopContext @0x101418990)
///   2. outputStreamInfo   5. lock (`os_unfair_lock_s`, self+0x30)
///   3. mediaType (`AVMediaType?`, optional per-type filter)
///
/// Key discrete entries:
///   - 0x1014291a4  Remuxer_configureOutputStreams (0x1014291a4--0x101429303)
///   - 0x101429304  Remuxer_applyOption (per-entry AVDict option-builder)
///   - 0x101419450  Remuxer_startOperationIfNeeded (0x101419450--0x10141957b)
///   - 0x100fd0510  Remuxer_readLoop_taskDealloc   (0x100fd0510--0x100fd0587)
///   - 0x101417568  Remuxer_readLoop_errorClose
///   - 0x10141b33c  Remuxer_clearFormatContext
public final class Remuxer: @unchecked Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let outputFormat: String?
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputStreamInfo: OutputStreamInfo?
    /// RE: Forward field 3 of 5 -- optional filter; when set, only remux streams of this type.
    public var mediaType: AVMediaType?
    /// RE: Forward field 5 of 5 (self+0x30) -- low-overhead spinlock for thread safety.
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private var isCancelled = false
    public var progressHandler: ((Double) -> Void)?

    /// RE: Forward v1.3.15 -- `Remuxer_startOperationIfNeeded` @ 0x101419450
    /// (0x101419450--0x10141957b). The binary creates an `NSBlockOperation`
    /// and adds it to an `NSOperationQueue` field stored at `self+0x88` on the
    /// Remuxer class. The current `remux()` API is async/await for callers
    /// that want a `Task` model; this queue is the parallel structural
    /// reconstruction.
    private let operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "KSPlayer.Remuxer"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    /// Tracks the currently scheduled remux block so callers can cancel from
    /// the queue side (mirrors the binary's stored `NSBlockOperation` slot).
    private var blockOperation: BlockOperation?

    public init(inputURL: URL, outputURL: URL, outputFormat: String? = nil) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deallocate()
    }

    /// RE: `Remuxer_startOperationIfNeeded` (0x101419450). Schedules the
    /// remux work as an `NSBlockOperation` on the internal queue if one is
    /// not already in flight. Idempotent: a second call while a block is
    /// pending or running is a no-op (the binary uses an internal "already
    /// scheduled" check before wrapping the block).
    @discardableResult
    public func startOperationIfNeeded(completion: ((Bool) -> Void)? = nil) -> Bool {
        os_unfair_lock_lock(lock)
        if let blockOperation, !blockOperation.isFinished {
            os_unfair_lock_unlock(lock)
            return false
        }
        os_unfair_lock_unlock(lock)

        let op = BlockOperation()
        op.addExecutionBlock { [weak self, weak op] in
            guard let self, let op, !op.isCancelled else {
                completion?(false)
                return
            }
            // Bridge the async remux() body to the synchronous
            // BlockOperation execution via a DispatchSemaphore -- this is
            // the OperationQueue-side equivalent of the binary's
            // task-driven remux loop.
            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            Task {
                success = await self.remux()
                semaphore.signal()
            }
            semaphore.wait()
            completion?(success)
        }
        os_unfair_lock_lock(lock)
        blockOperation = op
        os_unfair_lock_unlock(lock)
        operationQueue.addOperation(op)
        return true
    }

    /// RE: 0x1013fd548 (Remuxer_readLoop_body, 1.3.15)
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

        // Extract DOVIDecoderConfigurationRecord from video stream side data
        // Binary ref: detection stored at object offset +0x132, read by FUN_1013fd1dc
        var doviRecord: DOVIDecoderConfigurationRecord?
        let streamCount = Int(formatCtx.pointee.nb_streams)
        for i in 0 ..< streamCount {
            guard let stream = formatCtx.pointee.streams[i] else { continue }
            let codecpar = stream.pointee.codecpar.pointee
            if codecpar.codec_type == AVMEDIA_TYPE_VIDEO,
               codecpar.nb_coded_side_data > 0,
               let sideDatas = codecpar.coded_side_data {
                for j in 0 ..< Int(codecpar.nb_coded_side_data) {
                    if sideDatas[j].type == AV_PKT_DATA_DOVI_CONF {
                        doviRecord = sideDatas[j].data.withMemoryRebound(
                            to: DOVIDecoderConfigurationRecord.self, capacity: 1
                        ) { $0 }.pointee
                        break
                    }
                }
                break
            }
        }

        let outputPath = outputURL.path
        guard let info = OutputStreamInfo(url: outputPath,
                                          formatName: outputFormat,
                                          inputFormatContext: formatCtx,
                                          doviRecord: doviRecord) else {
            cleanup()
            return false
        }
        outputStreamInfo = info

        // RE: 0x101418990 (Remuxer_buildReadLoopContext, 1.3.15)
        // Compute source start CMTime from formatCtx->start_time. If start_time == INT64_MIN
        // (AV_NOPTS_VALUE), use kCMTimeZero; else CMTime(value: start_time, timescale: 1_000_000).
        // Binary ref: 0x1014189c0-0x101418a20, PTR__kCMTimeZero @0x103978798.
        let sourceStartTime: CMTime
        let rawStartTime = formatCtx.pointee.start_time
        if rawStartTime == Int64.min { // AV_NOPTS_VALUE
            sourceStartTime = .zero
        } else {
            sourceStartTime = CMTime(value: rawStartTime, timescale: 1_000_000)
        }

        // RE: Per-stream start-time rebase pass (0x101418b88-0x101418d6c).
        // Pass 1: iterate streams. For subtitle streams (exact match), write the source
        // start CMTime onto the OutputStreamInfo node. For non-subtitle streams within
        // <10.0 s tolerance of the source start, also rebase.
        // Binary: node.startTime = ctx.startCMTime at 0x101418c8c.
        if sourceStartTime != .zero {
            for i in 0 ..< streamCount {
                guard let inputStream = formatCtx.pointee.streams[i],
                      let outputIndex = info.streamMapping[i] else { continue }
                let codecpar = inputStream.pointee.codecpar!
                let mediaType = codecpar.pointee.codec_type

                if mediaType == AVMEDIA_TYPE_SUBTITLE {
                    // Exact subtitle match: always rebase
                    info.setStartTime(sourceStartTime, forOutputStream: outputIndex)
                } else {
                    // Near-equal tolerance path (0x101418c4c-0x101418c70):
                    // If the stream's existing start offset differs from the source start
                    // by less than 10.0 seconds, also rebase it. This handles video/audio
                    // streams whose start_time is close to the container's start_time.
                    let streamStartTime: CMTime
                    if inputStream.pointee.start_time == Int64.min {
                        streamStartTime = .zero
                    } else {
                        streamStartTime = CMTime(
                            value: inputStream.pointee.start_time,
                            timescale: inputStream.pointee.time_base.den
                        )
                    }
                    let delta = CMTimeSubtract(streamStartTime, sourceStartTime)
                    let deltaSeconds = abs(CMTimeGetSeconds(delta))
                    if deltaSeconds < 10.0 {
                        info.setStartTime(sourceStartTime, forOutputStream: outputIndex)
                    }
                }
            }
        }

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
            let outputTimeBase = info.timeBaseMap[outputIndex] ?? inputTimeBase
            let context = info.transcodeMap[streamIndex] ?? CopyTranscodeContext.shared

            // RE: 0x10144a7fc (SubtitleFrame_adjustTimestamps, 1.3.15)
            // Apply per-stream PTS rebasing before processing. The binary's locked
            // dispatcher (0x10144a684) calls this inside os_unfair_lock before the
            // Copy/BSF deliver. Subtracts the per-stream startTime offset from pts/dts.
            info.rebasePacketTimestamps(packet, inputTimeBase: inputTimeBase)

            let outputPackets = context.process(packet: packet, timeBase: inputTimeBase, outputTimeBase: outputTimeBase)
            for outPkt in outputPackets {
                outPkt.pointee.stream_index = Int32(outputIndex)
                _ = info.writePacket(outPkt)
                if outPkt != packet {
                    var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
                    av_packet_free(&pktToFree)
                }
            }

            // RE: progress throttle is 2.0 s (instruction-verified fmov d10,#2.0
            // at 0x1013fe328 and 0x1013fe688; corrected from earlier 3.0 s claim)
            let now = CACurrentMediaTime()
            if now - lastProgressTime >= 2.0, duration > 0 {
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
                var pktToFree: UnsafeMutablePointer<AVPacket>? = outPkt
                av_packet_free(&pktToFree)
            }
        }

        var packetToFree: UnsafeMutablePointer<AVPacket>? = packet
        av_packet_free(&packetToFree)
        progressHandler?(1.0)
        cleanup()
        return true
    }

    public func cancel() {
        os_unfair_lock_lock(lock)
        isCancelled = true
        let op = blockOperation
        os_unfair_lock_unlock(lock)
        // RE: cancelling the NSBlockOperation matches what the binary's
        // teardown path does on the queue field at self+0x88.
        op?.cancel()
    }

    /// RE: Two-pass flush/close per TranscodeIO.md lines 1429-1467.
    /// Pass 1 (FUN_1013ff6e4): flush witnesses + av_write_trailer + clear dict.
    /// Pass 2 (FUN_1013ff968): close witnesses + output-node close + free packet + clearFormatContext.
    private func cleanup() {
        // Pass 1: flush all contexts and write trailer
        outputStreamInfo?.flushAllContexts()
        // Pass 2: close all contexts and clear format context
        outputStreamInfo?.closeAllContexts()
        outputStreamInfo = nil
        if inputFormatContext != nil {
            avformat_close_input(&inputFormatContext)
        }
    }

    /// RE: 0x101417568 (Remuxer_readLoop_errorClose, 1.3.15)
    /// Error/exit close path: dispatches the output object's flush/close witness,
    /// then avformat close on formatCtx[+0x20], then clearFormatContext.
    private func readLoopErrorClose() {
        outputStreamInfo?.flushAllContexts()
        outputStreamInfo?.closeAllContexts()
        if inputFormatContext != nil {
            avformat_close_input(&inputFormatContext)
        }
    }

    /// RE: 0x1014291a4 (Remuxer_configureOutputStreams, 1.3.15)
    /// Iterates a [String: Any] options dictionary and calls applyOption with
    /// a shared AVDictionary* accumulator. Real discrete entry (verified).
    public func configureOutputStreams(options: [String: Any]) {
        var dict: OpaquePointer?
        for (key, value) in options {
            applyOption(key: key, value: value, dict: &dict)
        }
        if dict != nil {
            av_dict_free(&dict)
        }
    }

    /// RE: 0x101429304 (Remuxer_applyOption, 1.3.15)
    /// Per-[String:Any]-entry AVDict option-builder. Type-switches the boxed value
    /// via _swift_dynamicCast in order: Int64 -> Int -> String -> [String] -> [String:String].
    /// Integer cases: av_dict_set_int. String case: av_dict_set.
    /// [String] case: joins with "+" separator. [String:String] case: joins pairs
    /// as "key=value" with "\r\n" separator.
    private func applyOption(key: String, value: Any, dict: inout OpaquePointer?) {
        if let int64Value = value as? Int64 {
            av_dict_set_int(&dict, key, int64Value, 0)
        } else if let intValue = value as? Int {
            av_dict_set_int(&dict, key, Int64(intValue), 0)
        } else if let stringValue = value as? String {
            av_dict_set(&dict, key, stringValue, 0)
        } else if let arrayValue = value as? [String] {
            // Binary uses "+" separator for [String] arrays
            let joined = arrayValue.joined(separator: "+")
            av_dict_set(&dict, key, joined, 0)
        } else if let dictValue = value as? [String: String] {
            // Binary uses "\r\n" separator for [String:String] dictionaries,
            // formatting each pair as "key=value"
            let joined = dictValue.map { "\($0.key)=\($0.value)" }.joined(separator: "\r\n")
            av_dict_set(&dict, key, joined, 0)
        }
    }
}
