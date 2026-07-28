//
//  Resample.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/27.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import DOVIRPUShim
import Libavcodec
import Libswresample
import Libswscale

protocol FrameTransfer {
    func transfer(avframe: UnsafeMutablePointer<AVFrame>) -> UnsafeMutablePointer<AVFrame>
    func shutdown()
}

protocol FrameChange {
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame
    func shutdown()
}

class VideoSwscale: FrameTransfer {
    private var imgConvertCtx: UnsafeMutablePointer<SwsContext>?
    private var format: AVPixelFormat = AV_PIX_FMT_NONE
    private var height: Int32 = 0
    private var width: Int32 = 0
    private var outFrame: UnsafeMutablePointer<AVFrame>?
    private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize _: Int32) {
        if self.format == format, self.width == width, self.height == height {
            return
        }
        self.format = format
        self.height = height
        self.width = width
        if format.osType() != nil {
            sws_freeContext(imgConvertCtx)
            imgConvertCtx = nil
            outFrame = nil
        } else {
            let dstFormat = format.bestPixelFormat
            imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, self.format, width, height, dstFormat, Int32(SWS_BICUBIC.rawValue), nil, nil, nil)
            outFrame = av_frame_alloc()
            outFrame?.pointee.format = dstFormat.rawValue
            outFrame?.pointee.width = width
            outFrame?.pointee.height = height
        }
    }

    func transfer(avframe: UnsafeMutablePointer<AVFrame>) -> UnsafeMutablePointer<AVFrame> {
        setup(format: AVPixelFormat(rawValue: avframe.pointee.format), width: avframe.pointee.width, height: avframe.pointee.height, linesize: avframe.pointee.linesize.0)
        if let imgConvertCtx, let outFrame {
            sws_scale_frame(imgConvertCtx, outFrame, avframe)
            return outFrame
        }
        return avframe
    }

    func shutdown() {
        sws_freeContext(imgConvertCtx)
        imgConvertCtx = nil
    }
}

class VideoSwresample: FrameChange {
    // Field layout = reflection ORDER (Forward 1.3.17). The 5 DV/HDR fields below
    // (dovi…rpuBuffer) are Forward-NEW vs upstream; `isDovi: Bool` was REMOVED.
    private var imgConvertCtx: UnsafeMutablePointer<SwsContext>?
    private var format: AVPixelFormat = AV_PIX_FMT_NONE
    private var height: Int32 = 0
    private var width: Int32 = 0
    private var pool: CVPixelBufferPool?
    private let dstHeight: Int32?
    private let dstWidth: Int32?
    private let dstFormat: AVPixelFormat?
    private let fps: Float
    // Forward-NEW DV/HDR fields (declared in reflection order after `fps`).
    // ⚑[tool=binding_gate ref=VideoSwresample:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • dovi — `var x: T?` gets an implicit nil; `let x: T?` would need an explicit `= nil`, asserting it is PERMANENTLY nil
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    private var dovi: DOVIDecoderConfigurationRecord?
    // P3a: KSDOVIMetadata = the serializer's flattened 3008-byte DV GPU buffer (DOVIRPUShim,
    // opaque). Binary +0x60 is EXACTLY 3008 B (=0xBC0), leaving no room for a nil tag in an
    // opaque blob → field reconstructed NON-optional (field-record name is `KSDOVIMetadata?`;
    // optionality flagged → DV-render, where the real layout may expose a spare-bit inhabitant).
    private var doviData = KSDOVIMetadata()
    private var edrMetaData: EDRMetaData?
    private var hdr10PlusData: Data? // ⚑ §7-walled → type inferred
    private var rpuBuffer: Data? // ⚑ §7-walled → the ~104-byte +0xc20 inline buffer; layout NOT guessed
    // UNRESOLVED → DV-render: init devirt; isDovi not stored (field removed); the DV/HDR fields are populated
    // decoder-side by s32 (see below), not in init.
    init(dstWidth: Int32? = nil, dstHeight: Int32? = nil, dstFormat: AVPixelFormat? = nil, fps: Float = 60, isDovi _: Bool) {
        self.dstWidth = dstWidth
        self.dstHeight = dstHeight
        self.dstFormat = dstFormat
        self.fps = fps
    }

    // UNRESOLVED → DV-render/HDR-pixelBuffer-decoration: Forward's change (slot28 @0x101a660dc) copies the
    // DV/HDR state into the VideoVTBFrame AND decorates the pixelBuffer via Forward-NEW infra: the shared
    // FUN_101a88b68 colorspace helper (PQ/HLG from dovi.dv_bl_signal_compatibility_id) + a PixelBufferProtocol
    // HDR-attachment EXPANSION (binary 40 reqs vs source 28; the Data→CVBufferSetAttachment cluster FUN_101a8a180).
    // That ~12-requirement protocol layer is unverifiable with current tools (no witness-table verifier) →
    // DEFERRED as a unit with transfer (slot30). Kept upstream with isDovi → `dovi != nil` to compile.
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        let frame = VideoVTBFrame(fps: fps, isDovi: dovi != nil)
        if avframe.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            frame.pixelBuffer = unsafeBitCast(avframe.pointee.data.3, to: CVPixelBuffer.self)
        } else {
            frame.pixelBuffer = transfer(frame: avframe.pointee)
        }
        return frame
    }

    // T2 — slot29 @0x101a662e8. sws spine FAITHFUL (body-audited).
    // P3a (2026-06-29): RECONSTRUCTED the deferred 2nd early-return (decompile L57-62, NEON umaxv 4-way
    // test → goto epilogue, a pure early-return that skips CVPixelBufferPool.create). Fires when
    // dstWidth==nil && dstHeight==nil && format ∈ {RGBA, YUV420P10LE, YUV422P10LE, YUV444P10LE}
    // — compile-confirmed AV_PIX_FMT_{RGBA=26, YUV420P10LE=62, YUV422P10LE=64, YUV444P10LE=68}. NOTE:
    // the earlier "passthrough/hardware-class formats" label (P2 deferral prose) was WRONG; these are
    // RGBA + 10-bit planar YUV. For these direct-use formats with no scaling requested, no pool is made.
    private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize: Int32) {
        if self.format == format, self.width == width, self.height == height {
            return
        }
        self.format = format
        self.height = height
        self.width = width
        if self.dstWidth == nil, self.dstHeight == nil,
           format == AV_PIX_FMT_RGBA || format == AV_PIX_FMT_YUV420P10LE
               || format == AV_PIX_FMT_YUV422P10LE || format == AV_PIX_FMT_YUV444P10LE {
            return
        }
        let dstWidth = dstWidth ?? width
        let dstHeight = dstHeight ?? height
        let pixelFormatType: OSType
        if self.dstWidth == nil, self.dstHeight == nil, dstFormat == nil, let osType = format.osType() {
            pixelFormatType = osType
            sws_freeContext(imgConvertCtx)
            imgConvertCtx = nil
        } else {
            let dstFormat = dstFormat ?? format.bestPixelFormat
            pixelFormatType = dstFormat.osType()!
//            imgConvertCtx = sws_getContext(width, height, self.format, width, height, dstFormat, SWS_FAST_BILINEAR, nil, nil, nil)
            // AV_PIX_FMT_VIDEOTOOLBOX格式是无法进行swscale的
            imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, self.format, dstWidth, dstHeight, dstFormat, Int32(SWS_FAST_BILINEAR.rawValue), nil, nil, nil)
        }
        pool = CVPixelBufferPool.create(width: dstWidth, height: dstHeight, bytesPerRowAlignment: linesize, pixelFormatType: pixelFormatType)
    }

    // UNRESOLVED → DV-render/HDR-pixelBuffer-decoration: Forward's transfer(frame:) (slot30 @0x101a666f8) adds a
    // DV-format branch (FUN_101a8a318 builds a 224B DV pixel-buffer type) + the shared FUN_101a88b68 colorspace
    // helper — the same Forward-NEW HDR-pixelBuffer-decoration layer as change (deferred together; see change()).
    // Kept upstream (color attributes only; no isDovi).
    func transfer(frame: AVFrame) -> PixelBufferProtocol? {
        let format = AVPixelFormat(rawValue: frame.format)
        let width = frame.width
        let height = frame.height
        if format.leftShift > 0 {
            return PixelBuffer(frame: frame)
        }
        let pbuf = transfer(format: format, width: width, height: height, data: Array(tuple: frame.data), linesize: Array(tuple: frame.linesize))
        if let pbuf {
            pbuf.aspectRatio = frame.sample_aspect_ratio.size
            pbuf.yCbCrMatrix = frame.colorspace.ycbcrMatrix
            pbuf.colorPrimaries = frame.color_primaries.colorPrimaries
            pbuf.transferFunction = frame.color_trc.transferFunction
            // vt_pixbuf_set_colorspace
            if pbuf.transferFunction == kCVImageBufferTransferFunction_UseGamma {
                let gamma = NSNumber(value: frame.color_trc == AVCOL_TRC_GAMMA22 ? 2.2 : 2.8)
                CVBufferSetAttachment(pbuf, kCVImageBufferGammaLevelKey, gamma, .shouldPropagate)
            }
            if let chroma = frame.chroma_location.chroma {
                CVBufferSetAttachment(pbuf, kCVImageBufferChromaLocationTopFieldKey, chroma, .shouldPropagate)
            }
            pbuf.colorspace = KSOptions.colorSpace(ycbcrMatrix: pbuf.yCbCrMatrix, transferFunction: pbuf.transferFunction)
        }
        return pbuf
    }

    // RECONSTRUCT FAITHFUL (T2) — slot31 @0x101a66c6c, PURE-sws (field-offset-verified DV-free):
    // sws_scale path + manual plane pixel-copy (CVPixelBuffer plane ops + memmove).
    func transfer(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        setup(format: format, width: width, height: height, linesize: linesize[1] == 0 ? linesize[0] : linesize[1])
        guard let pool else {
            return nil
        }
        return autoreleasepool { () -> CVPixelBuffer? in
            var pbuf: CVPixelBuffer?
            let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbuf)
            guard let pbuf, ret == kCVReturnSuccess else {
                return nil
            }
            CVPixelBufferLockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
            let bufferPlaneCount = pbuf.planeCount
            if let imgConvertCtx {
                let bytesPerRow = (0 ..< bufferPlaneCount).map { i in
                    Int32(CVPixelBufferGetBytesPerRowOfPlane(pbuf, i))
                }
                let contents = (0 ..< bufferPlaneCount).map { i in
                    pbuf.baseAddressOfPlane(at: i)?.assumingMemoryBound(to: UInt8.self)
                }
                _ = sws_scale(imgConvertCtx, data.map { UnsafePointer($0) }, linesize, 0, height, contents, bytesPerRow)
            } else {
                let planeCount = format.planeCount
                let byteCount = format.bitDepth > 8 ? 2 : 1
                for i in 0 ..< bufferPlaneCount {
                    let height = pbuf.heightOfPlane(at: i)
                    let size = Int(linesize[i])
                    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pbuf, i)
                    var contents = pbuf.baseAddressOfPlane(at: i)
                    var source = data[i]!
                    if bufferPlaneCount < planeCount, i + 2 == planeCount {
                        var sourceU = data[i]!
                        var sourceV = data[i + 1]!
                        var k = 0
                        while k < height {
                            var j = 0
                            while j < size {
                                contents?.advanced(by: 2 * j).copyMemory(from: sourceU.advanced(by: j), byteCount: byteCount)
                                contents?.advanced(by: 2 * j + byteCount).copyMemory(from: sourceV.advanced(by: j), byteCount: byteCount)
                                j += byteCount
                            }
                            contents = contents?.advanced(by: bytesPerRow)
                            sourceU = sourceU.advanced(by: size)
                            sourceV = sourceV.advanced(by: size)
                            k += 1
                        }
                    } else if bytesPerRow == size {
                        contents?.copyMemory(from: source, byteCount: height * size)
                    } else {
                        var j = 0
                        while j < height {
                            contents?.advanced(by: j * bytesPerRow).copyMemory(from: source.advanced(by: j * size), byteCount: size)
                            j += 1
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
            return pbuf
        }
    }

    // DEFERRED → DV-render/HDR-pixelBuffer phase (COUPLED unit): s32 (slot32 @0x101a67274, serializer @0x101b31c6c)
    // = the side-data loop Forward moved out of FFmpegDecode.decodeFrame (sole caller @decompile-L182). It WRITES this
    // class's DV/HDR fields (doviData +0x60, rpuBuffer +0xc50, hdr10PlusData +0xc60, EDRMetaData +0xc20..) that change
    // s28 CONSUMES → VideoVTBFrame (grep-confirmed). Cannot land standalone (regresses edrMetaData) → reconstructs as
    // ONE unit with change s28 + transfer s30 + the decodeFrame loop-removal, gated on the protocol-witness verifier.
    // Cached: VideoSwresample_slot32.

    // UNRESOLVED → DV-render: Forward may also free the DV buffer/rpuBuffer (devirt; not verifiable here).
    func shutdown() {
        sws_freeContext(imgConvertCtx)
        imgConvertCtx = nil
    }
}

extension BinaryInteger {
    func alignment(value: Self) -> Self {
        let remainder = self % value
        return remainder == 0 ? self : self + value - remainder
    }
}

typealias SwrContext = OpaquePointer

class AudioSwresample: FrameChange {
    private var swrContext: SwrContext?
    private var descriptor: AudioDescriptor
    private var outChannel: AVChannelLayout
    init(audioDescriptor: AudioDescriptor) {
        descriptor = audioDescriptor
        outChannel = audioDescriptor.outChannel
        _ = setup(descriptor: descriptor)
    }

    private func setup(descriptor: AudioDescriptor) -> Bool {
        var result = swr_alloc_set_opts2(&swrContext, &descriptor.outChannel, descriptor.audioFormat.sampleFormat, Int32(descriptor.audioFormat.sampleRate), &descriptor.channel, descriptor.sampleFormat, descriptor.sampleRate, 0, nil)
        result = swr_init(swrContext)
        if result < 0 {
            shutdown()
            return false
        } else {
            outChannel = descriptor.outChannel
            return true
        }
    }

    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        if !(descriptor == avframe.pointee) || outChannel != descriptor.outChannel {
            let newDescriptor = AudioDescriptor(frame: avframe.pointee)
            if setup(descriptor: newDescriptor) {
                descriptor = newDescriptor
            } else {
                throw NSError(errorCode: .auidoSwrInit, userInfo: ["outChannel": newDescriptor.outChannel, "inChannel": newDescriptor.channel])
            }
        }
        let numberOfSamples = avframe.pointee.nb_samples
        let outSamples = swr_get_out_samples(swrContext, numberOfSamples)
        var frameBuffer = Array(tuple: avframe.pointee.data).map { UnsafePointer<UInt8>($0) }
        let channels = descriptor.outChannel.nb_channels
        var bufferSize = [Int32(0)]
        // 返回值是有乘以声道，所以不用返回值
        _ = av_samples_get_buffer_size(&bufferSize, channels, outSamples, descriptor.audioFormat.sampleFormat, 1)
        let frame = AudioFrame(dataSize: Int(bufferSize[0]), audioFormat: descriptor.audioFormat)
        frame.numberOfSamples = UInt32(swr_convert(swrContext, &frame.data, outSamples, &frameBuffer, numberOfSamples))
        return frame
    }

    func shutdown() {
        swr_free(&swrContext)
    }
}

public class AudioDescriptor: Equatable {
//    static let defaultValue = AudioDescriptor()
    public var sampleRate: Int32
    public private(set) var audioFormat: AVAudioFormat
    fileprivate(set) var channel: AVChannelLayout
    fileprivate var sampleFormat: AVSampleFormat
    fileprivate var outChannel: AVChannelLayout

    private convenience init() {
        self.init(sampleFormat: AV_SAMPLE_FMT_FLT, sampleRate: 48000, channel: AVChannelLayout.defaultValue)
    }

    convenience init(codecpar: AVCodecParameters) {
        self.init(sampleFormat: AVSampleFormat(rawValue: codecpar.format), sampleRate: codecpar.sample_rate, channel: codecpar.ch_layout)
    }

    convenience init(frame: AVFrame) {
        self.init(sampleFormat: AVSampleFormat(rawValue: frame.format), sampleRate: frame.sample_rate, channel: frame.ch_layout)
    }

    init(sampleFormat: AVSampleFormat, sampleRate: Int32, channel: AVChannelLayout) {
        self.channel = channel
        outChannel = channel
        if sampleRate <= 0 {
            self.sampleRate = 48000
        } else {
            self.sampleRate = sampleRate
        }
        self.sampleFormat = sampleFormat
        #if os(macOS)
        let channelCount = AVAudioChannelCount(2)
        #else
        let channelCount = KSOptions.outputNumberOfChannels(channelCount: AVAudioChannelCount(outChannel.nb_channels))
        #endif
        audioFormat = AudioDescriptor.audioFormat(sampleFormat: sampleFormat, sampleRate: self.sampleRate, outChannel: &outChannel, channelCount: channelCount)
    }

    public static func == (lhs: AudioDescriptor, rhs: AudioDescriptor) -> Bool {
        lhs.sampleFormat == rhs.sampleFormat && lhs.sampleRate == rhs.sampleRate && lhs.channel == rhs.channel
    }

    public static func == (lhs: AudioDescriptor, rhs: AVFrame) -> Bool {
        var sampleRate = rhs.sample_rate
        if sampleRate <= 0 {
            sampleRate = 48000
        }
        return lhs.sampleFormat == AVSampleFormat(rawValue: rhs.format) && lhs.sampleRate == sampleRate && lhs.channel == rhs.ch_layout
    }

    static func audioFormat(sampleFormat: AVSampleFormat, sampleRate: Int32, outChannel: inout AVChannelLayout, channelCount: AVAudioChannelCount) -> AVAudioFormat {
        if channelCount != AVAudioChannelCount(outChannel.nb_channels) {
            av_channel_layout_default(&outChannel, Int32(channelCount))
        }
        let layoutTag: AudioChannelLayoutTag
        if let tag = outChannel.layoutTag {
            layoutTag = tag
        } else {
            av_channel_layout_default(&outChannel, Int32(channelCount))
            if let tag = outChannel.layoutTag {
                layoutTag = tag
            } else {
                av_channel_layout_default(&outChannel, 2)
                layoutTag = outChannel.layoutTag!
            }
        }
        KSLog("[audio] out channelLayout: \(outChannel)")
        var commonFormat: AVAudioCommonFormat
        var interleaved: Bool
        switch sampleFormat {
        case AV_SAMPLE_FMT_S16:
            commonFormat = .pcmFormatInt16
            interleaved = true
        case AV_SAMPLE_FMT_S32:
            commonFormat = .pcmFormatInt32
            interleaved = true
        case AV_SAMPLE_FMT_FLT:
            commonFormat = .pcmFormatFloat32
            interleaved = true
        case AV_SAMPLE_FMT_DBL:
            commonFormat = .pcmFormatFloat64
            interleaved = true
        case AV_SAMPLE_FMT_S16P:
            commonFormat = .pcmFormatInt16
            interleaved = false
        case AV_SAMPLE_FMT_S32P:
            commonFormat = .pcmFormatInt32
            interleaved = false
        case AV_SAMPLE_FMT_FLTP:
            commonFormat = .pcmFormatFloat32
            interleaved = false
        case AV_SAMPLE_FMT_DBLP:
            commonFormat = .pcmFormatFloat64
            interleaved = false
        default:
            commonFormat = .pcmFormatFloat32
            interleaved = false
        }
        interleaved = KSOptions.audioPlayerType == AudioRendererPlayer.self
        if !(KSOptions.audioPlayerType == AudioRendererPlayer.self || KSOptions.audioPlayerType == AudioUnitPlayer.self) {
            commonFormat = .pcmFormatFloat32
        }
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: Double(sampleRate), interleaved: interleaved, channelLayout: AVAudioChannelLayout(layoutTag: layoutTag)!)
        //        AVAudioChannelLayout(layout: outChannel.layoutTag.channelLayout)
    }

    public func updateAudioFormat() {
        #if os(macOS)
        let channelCount = AVAudioChannelCount(2)
        #else
        let channelCount = KSOptions.outputNumberOfChannels(channelCount: AVAudioChannelCount(channel.nb_channels))
        #endif
        audioFormat = AudioDescriptor.audioFormat(sampleFormat: sampleFormat, sampleRate: sampleRate, outChannel: &outChannel, channelCount: channelCount)
    }
}
