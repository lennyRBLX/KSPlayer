//
//  Resample.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/27.
//

import AVFoundation
import CoreGraphics
import CoreMedia
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
    private var imgConvertCtx: OpaquePointer?
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
            imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, self.format, width, height, dstFormat, SWS_BICUBIC, nil, nil, nil)
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

/// RE: VideoSwresample class (1.3.15) — pixel-format conversion via swscale,
/// CVPixelBuffer and IOSurface output paths, color-attachment metadata.
class VideoSwresample: FrameChange {
    /// RE: +0x10, OpaquePointer? (SwsContext), field imgConvertCtx
    private var imgConvertCtx: OpaquePointer?
    /// RE: +0x18, AVPixelFormat, field format
    private var format: AVPixelFormat = AV_PIX_FMT_NONE
    /// RE: +0x1C, Int32, field height
    private var height: Int32 = 0
    /// RE: +0x20, Int32, field width
    private var width: Int32 = 0
    /// RE: +0x28, CVPixelBufferPool?, field pool
    private var pool: CVPixelBufferPool?
    /// RE: +0x30, Int32?, field dstHeight
    private var dstHeight: Int32?
    /// RE: +0x38, Int32?, field dstWidth
    private var dstWidth: Int32?
    /// RE: +0x40, AVPixelFormat?, field dstFormat
    private let dstFormat: AVPixelFormat?
    /// RE: +0x48, Float, field fps
    private let fps: Float
    /// RE: +0x4C, Bool, field isDovi
    private let isDovi: Bool

    /// RE: 0x10144f1c4 (VideoSwresample.init, 1.3.15)
    /// Initializes the swscale context with all 10 stored properties.
    init(dstWidth: Int32? = nil, dstHeight: Int32? = nil, dstFormat: AVPixelFormat? = nil, fps: Float = 60, isDovi: Bool) {
        self.dstWidth = dstWidth
        self.dstHeight = dstHeight
        self.dstFormat = dstFormat
        self.fps = fps
        self.isDovi = isDovi
    }

    // MARK: - Binary API Surface (separate steps per API Surface Preservation)

    /// RE: 0x10144f2dc (VideoSwresample.getOutputFormat, 1.3.15)
    /// Output pixel-format selection. Determines the destination AVPixelFormat and
    /// corresponding OSType for the conversion, based on whether custom dst dimensions/format
    /// are specified or the source format can be used directly.
    /// Returns (outputFormat: AVPixelFormat?, pixelFormatType: OSType, needsSwscale: Bool).
    private func getOutputFormat(for format: AVPixelFormat) -> (outputFormat: AVPixelFormat?, pixelFormatType: OSType, needsSwscale: Bool) {
        if dstWidth == nil, dstHeight == nil, dstFormat == nil, let osType = format.osType() {
            // Source format can be used directly — no swscale conversion needed
            return (nil, osType, false)
        } else {
            let resolvedFormat = dstFormat ?? format.bestPixelFormat
            let osType = resolvedFormat.osType()!
            return (resolvedFormat, osType, true)
        }
    }

    /// RE: 0x10144f344 (VideoSwresample.allocBuffer, 1.3.15)
    /// Buffer allocation for converted frame. Allocates a CVPixelBuffer from the pool.
    /// Returns nil if pool is not configured or allocation fails.
    private func allocBuffer() -> CVPixelBuffer? {
        guard let pool else {
            return nil
        }
        var pbuf: CVPixelBuffer?
        let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbuf)
        guard let pbuf, ret == kCVReturnSuccess else {
            return nil
        }
        return pbuf
    }

    /// RE: 0x10144f438 (VideoSwresample.createIOSurface, 1.3.15)
    /// IOSurface-backed output path. Creates an IOSurface-backed CVPixelBuffer directly
    /// (bypassing CVPixelBufferPool) for use cases that require direct IOSurface access,
    /// such as zero-copy Metal texture binding.
    func createIOSurface(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        let formatInfo = getOutputFormat(for: format)
        let dstWidth = dstWidth ?? width
        let dstHeight = dstHeight ?? height
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: formatInfo.pixelFormatType,
            kCVPixelBufferWidthKey: dstWidth,
            kCVPixelBufferHeightKey: dstHeight,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pbuf: CVPixelBuffer?
        let ret = CVPixelBufferCreate(kCFAllocatorDefault, Int(dstWidth), Int(dstHeight),
                                      formatInfo.pixelFormatType, attributes as CFDictionary, &pbuf)
        guard let pbuf, ret == kCVReturnSuccess else {
            return nil
        }
        // Configure swscale if format conversion is needed
        if formatInfo.needsSwscale {
            if self.format != format || self.width != width || self.height != height {
                self.format = format
                self.width = width
                self.height = height
                if let resolvedFormat = formatInfo.outputFormat {
                    imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, format, dstWidth, dstHeight, resolvedFormat, SWS_FAST_BILINEAR, nil, nil, nil)
                    if isDovi, let imgConvertCtx {
                        let srcCoeffs = sws_getCoefficients(SWS_CS_BT2020)
                        let dstCoeffs = sws_getCoefficients(SWS_CS_ITU709)
                        sws_setColorspaceDetails(imgConvertCtx, srcCoeffs, 1, dstCoeffs, 0, 0, 1 << 16, 1 << 16)
                    }
                }
            }
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
                let planeHeight = pbuf.heightOfPlane(at: i)
                let size = Int(linesize[i])
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pbuf, i)
                var contents = pbuf.baseAddressOfPlane(at: i)
                if bufferPlaneCount < planeCount, i + 2 == planeCount {
                    var sourceU = data[i]!
                    var sourceV = data[i + 1]!
                    var k = 0
                    while k < planeHeight {
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
                    contents?.copyMemory(from: data[i]!, byteCount: planeHeight * size)
                } else {
                    var j = 0
                    while j < planeHeight {
                        contents?.advanced(by: j * bytesPerRow).copyMemory(from: data[i]!.advanced(by: j * size), byteCount: size)
                        j += 1
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
        return pbuf
    }

    // MARK: - Main Conversion Entry

    /// RE: 0x10144aea8 (VideoSwresample.convert, 1.3.15)
    /// Main conversion entry point (1395 B). Performs pixel-format branching, calls
    /// createCVPixelBuffer, and sets CVBuffer color attachments (YCbCr matrix, color
    /// primaries, transfer function, gamma, chroma location).
    /// Maps to FrameChange.change(avframe:) protocol requirement.
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        let frame = VideoVTBFrame(fps: fps, isDovi: isDovi)
        if avframe.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            frame.corePixelBuffer = unsafeBitCast(avframe.pointee.data.3, to: CVPixelBuffer.self)
        } else {
            frame.corePixelBuffer = transfer(frame: avframe.pointee)
        }
        return frame
    }

    /// RE: 0x10144ba54 (VideoSwresample.convert_thunk, 1.3.15)
    /// Thin thunk to AudioFrame_createFromVideoSwresample; VWT entry, no callers (31 B).
    @inline(__always)
    static func convertThunk(_ swresample: VideoSwresample, frame: AVFrame) -> PixelBufferProtocol? {
        swresample.transfer(frame: frame)
    }

    // MARK: - Internal Setup

    /// RE: part of VideoSwresample_init / setup path (1.3.15)
    /// Configures swscale context and pixel buffer pool when source format changes.
    /// Delegates format selection to getOutputFormat (0x10144f2dc).
    private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize: Int32) {
        if self.format == format, self.width == width, self.height == height {
            return
        }
        self.format = format
        self.height = height
        self.width = width
        let dstWidth = dstWidth ?? width
        let dstHeight = dstHeight ?? height
        let formatInfo = getOutputFormat(for: format)
        if formatInfo.needsSwscale {
            let resolvedFormat = formatInfo.outputFormat!
            imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, self.format, dstWidth, dstHeight, resolvedFormat, SWS_FAST_BILINEAR, nil, nil, nil)
            if isDovi, let imgConvertCtx {
                let srcCoeffs = sws_getCoefficients(SWS_CS_BT2020)
                let dstCoeffs = sws_getCoefficients(SWS_CS_ITU709)
                sws_setColorspaceDetails(imgConvertCtx, srcCoeffs, 1, dstCoeffs, 0, 0, 1 << 16, 1 << 16)
            }
        } else {
            sws_freeContext(imgConvertCtx)
            imgConvertCtx = nil
        }
        pool = CVPixelBufferPool.create(width: dstWidth, height: dstHeight, bytesPerRowAlignment: linesize, pixelFormatType: formatInfo.pixelFormatType)
    }

    // MARK: - Transfer (CVPixelBuffer Path)

    /// RE: part of 0x10144aea8 (VideoSwresample.convert, 1.3.15)
    /// Converts an AVFrame to a PixelBufferProtocol, setting color attachments on the
    /// resulting CVPixelBuffer. For left-shifted formats, returns a PixelBuffer directly.
    func transfer(frame: AVFrame) -> PixelBufferProtocol? {
        let format = AVPixelFormat(rawValue: frame.format)
        let width = frame.width
        let height = frame.height
        if format.leftShift > 0 {
            return PixelBuffer(frame: frame)
        }
        let pbuf = createCVPixelBuffer(format: format, width: width, height: height, data: Array(tuple: frame.data), linesize: Array(tuple: frame.linesize))
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

    /// RE: 0x10144b41c (VideoSwresample.createCVPixelBuffer, 1.3.15)
    /// sws_scale + NV12 UV interleaving. Performs the actual pixel data conversion
    /// into a pool-allocated CVPixelBuffer. Uses allocBuffer (0x10144f344) for
    /// buffer allocation.
    func createCVPixelBuffer(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        setup(format: format, width: width, height: height, linesize: linesize[1] == 0 ? linesize[0] : linesize[1])
        guard let pbuf = allocBuffer() else {
            return nil
        }
        return autoreleasepool {
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

    /// RE: 0x10144b41c (VideoSwresample.createCVPixelBuffer, 1.3.15)
    /// Overload preserving the original `transfer` name for external callers
    /// (SubtitleDecode, ThumbnailController). Delegates to createCVPixelBuffer.
    func transfer(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        createCVPixelBuffer(format: format, width: width, height: height, data: data, linesize: linesize)
    }

    /// RE: shutdown path (VideoSwresample.deinit, 1.3.15)
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

    /// RE: 0x10144ba9c (AudioSwresample SwrContext (re)init, 1.3.15)
    /// alloc + configure + init a libswresample `SwrContext` from an `AudioDescriptor`.
    /// On `swr_init` success, records the negotiated OUT channel layout; on failure
    /// tears the half-built handle down via `shutdown()` (swr_free) and reports failure.
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

    /// RE: 0x10144be78 (AudioSwresample.change(avframe:), 1.3.15)
    /// Main resample path (1676 B): short-circuits on an unchanged descriptor
    /// (`matchesFrameFormat`), otherwise rebuilds the descriptor + `SwrContext`, then
    /// runs `swr_get_out_samples` -> `av_samples_get_buffer_size` -> `swr_convert`.
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        if !(descriptor == avframe.pointee) || outChannel != descriptor.outChannel {
            let newDescriptor = AudioDescriptor(frame: avframe.pointee)
            if setup(descriptor: newDescriptor) {
                descriptor = newDescriptor
            } else {
                throw NSError(errorCode: .audioSwrInit, userInfo: ["outChannel": newDescriptor.outChannel, "inChannel": newDescriptor.channel])
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

    /// RE: 0x10144ba74 (AudioSwresample freeSwrContext, 1.3.15)
    /// DEAD in the binary (vtable-only): frees `*(self+0x10)` and nulls the slot.
    /// Reconstructed per the no-skipping rule; `swr_free(&swrContext)` is the functional
    /// equivalent of the binary's deref + free-the-pointee + null.
    func shutdown() {
        swr_free(&swrContext)
    }
}

public class AudioDescriptor: Equatable {
//    static let defaultValue = AudioDescriptor()
    public let sampleRate: Int32
    public private(set) var audioFormat: AVAudioFormat
    fileprivate(set) var channel: AVChannelLayout
    fileprivate let sampleFormat: AVSampleFormat
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

    /// RE: 0x10144c7cc (AudioDescriptor ==, 1.3.15)
    /// Compares format(+0x38), sampleRate(+0x10), and AVChannelLayout(+0x20) via
    /// av_channel_layout_compare. (Ghidra mislabels this `AudioDescriptor_init`; the
    /// decompile confirms it is the `==` comparator, not an initializer.)
    public static func == (lhs: AudioDescriptor, rhs: AudioDescriptor) -> Bool {
        lhs.sampleFormat == rhs.sampleFormat && lhs.sampleRate == rhs.sampleRate && lhs.channel == rhs.channel
    }

    /// RE: 0x10144cb94 (AudioDescriptor matchesFrameFormat, 1.3.15)
    /// The doc names this `matchesFrameFormat`; reconstructed here as the `==(AudioDescriptor,
    /// AVFrame)` overload used by `change(avframe:)` as the short-circuit check. Compares
    /// format(+0x74), sampleRate(+0xb4, default 48000), and channelLayout(+0x180).
    public static func == (lhs: AudioDescriptor, rhs: AVFrame) -> Bool {
        var sampleRate = rhs.sample_rate
        if sampleRate <= 0 {
            sampleRate = 48000
        }
        return lhs.sampleFormat == AVSampleFormat(rawValue: rhs.format) && lhs.sampleRate == sampleRate && lhs.channel == rhs.ch_layout
    }

    /// RE: 0x10144c8ac (AudioDescriptor.audioFormat / audioSwrInit, 1.3.15)
    /// Output-AVAudioFormat builder. The binary's traced FUN_10144c8ac builds
    /// `[[AVAudioFormat alloc] initWithCommonFormat:1(=Float32) sampleRate: interleaved:
    /// channelLayout:]`. Two RE-verified facts drive the body:
    ///   - output PCM `commonFormat` is ALWAYS Float32 (no sampleFormat-derived
    ///     Int16/Int32/Float64 path, and no AudioUnitPlayer carve-out, in the binary);
    ///   - `interleaved` iff the active `audioPlayerType` == AudioRendererPlayer (else planar).
    /// The 3-tier channel-layout TAG retry (0x1013eb964 tag table) runs first.
    // TODO(re-verify): does 1.3.15 truly force Float32 for AudioUnitPlayer too, or is the
    // AUP int-passthrough an upstream KSPlayer addition the binary dropped? The doc marks
    // AudioDescriptor "No Forward modifications — identical to upstream KSPlayer", so this
    // is upstream behavior diverging from the traced binary; we follow the binary (Float32).
    static func audioFormat(sampleFormat: AVSampleFormat, sampleRate: Int32, outChannel: inout AVChannelLayout, channelCount: AVAudioChannelCount) -> AVAudioFormat {
        if channelCount != AVAudioChannelCount(outChannel.nb_channels) {
            av_channel_layout_default(&outChannel, Int32(channelCount))
        }
        // RE: 0x1013eb964 (channel-layout TAG lookup, DAT_104458ef0 table) drives this
        // 3-tier retry: requested-count default -> re-default -> stereo fallback; valid
        // counts {1,2,3,4,6,7,8,16,24}, miss sets bit 0x20 and forces the next tier.
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
        // Output PCM format is ALWAYS Float32 (binary, traced FUN_10144c8ac); interleaved
        // iff the active audioPlayerType is AudioRendererPlayer, else planar/non-interleaved.
        let commonFormat: AVAudioCommonFormat = .pcmFormatFloat32
        let interleaved = KSOptions.audioPlayerType == AudioRendererPlayer.self
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: Double(sampleRate), interleaved: interleaved, channelLayout: AVAudioChannelLayout(layoutTag: layoutTag)!)
        //        AVAudioChannelLayout(layout: outChannel.layoutTag.channelLayout)
    }

    /// RE: 0x1014195dc (AudioSwresample setDescriptor, 1.3.15)
    /// LIVE — rebuilds the output AVAudioFormat via the static `audioFormat(...)` builder
    /// and caches it (binary stores the AVAudioFormat at the output-format slot, self+0x30
    /// on AudioSwresample / +0x18 on AudioDescriptor).
    public func updateAudioFormat() {
        #if os(macOS)
        let channelCount = AVAudioChannelCount(2)
        #else
        let channelCount = KSOptions.outputNumberOfChannels(channelCount: AVAudioChannelCount(channel.nb_channels))
        #endif
        audioFormat = AudioDescriptor.audioFormat(sampleFormat: sampleFormat, sampleRate: sampleRate, outChannel: &outChannel, channelCount: channelCount)
    }
}
