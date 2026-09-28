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
import Libavutil
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
    // `let`, supplied by the init: every Forward construction site (e.g. FFmpegDecode 0x101a21d60, the
    // PixelBufferProtocol scaler 0x101a8acd4) stores dovi at +0x4c/+0x54 right after fps.
    private let dovi: DOVIDecoderConfigurationRecord?
    // P3a: KSDOVIMetadata is the serializer's imported-C 3008-byte DV metadata layout.
    // Its nested Bool at metadata offset 0x457 supplies Optional's extra inhabitant; keep this
    // field optional so MemoryLayout<KSDOVIMetadata?> remains 0xbc0.
    // The field record identifies this as KSDOVIMetadata? (l2_field_gate, field 11 of 14).
    // The declaration default remains unchanged pending the initializer check below.
    // ⚑[tool=export_trie_oracle ref=VideoSwresample.doviData:vpfi result=NO_SUBTREE] The DEFAULT is
    //   NOT verifiable: VideoSwresample is internal and has no trie subtree ("no orphan subtree
    //   found"); exactly 1 of 57138 trie names mentions the type, and that is ThumbnailSession.reScale's
    //   field type, not a member of this class. Initializer left exactly as it stood.
    private var doviData: KSDOVIMetadata? = KSDOVIMetadata()
    private var edrMetaData: EDRMetaData?
    private var hdr10PlusData: Data? // ⚑ §7-walled → type inferred
    private var rpuBuffer: Data? // ⚑ §7-walled → the ~104-byte +0xc20 inline buffer; layout NOT guessed
    // The DV/HDR side-data fields are populated decoder-side by processSideData (s32), not in init.
    init(dstWidth: Int32? = nil, dstHeight: Int32? = nil, dstFormat: AVPixelFormat? = nil, fps: Float = 60, dovi: DOVIDecoderConfigurationRecord?) {
        self.dstWidth = dstWidth
        self.dstHeight = dstHeight
        self.dstFormat = dstFormat
        self.fps = fps
        self.dovi = dovi
    }

    // slot28 @0x101a660dc: transfer(frame:) → pixelBuffer.hdr10PlusData = hdr10PlusData → VideoVTBFrame
    // (whose inlined init runs the colorspace helper; change itself does not call it).
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        let pixelBuffer = try transfer(frame: avframe.pointee)
        pixelBuffer.hdr10PlusData = hdr10PlusData
        return VideoVTBFrame(pixelBuffer: pixelBuffer, fps: fps, isKeyFrame: avframe.pointee.flags & AV_FRAME_FLAG_KEY != 0, dovi: dovi, edrMetaData: edrMetaData, doviData: doviData, rpuBuffer: rpuBuffer)
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
    // THROWS and returns NON-OPTIONAL. Slot 54 @0x101a666f8, 349 instr. Its single `ret`
    // returns the pair (x20, x24), and x24 — the witness-table word — is only ever set to
    // 0x1041d9f98 (CVBuffer's PixelBufferProtocol witness table) or 0x1041da0e0
    // (PixelBuffer's); it is never zeroed, and neither is x20 by any constant. The error
    // path is explicit: _swift_allocError @0x10345cae4 with type metadata 0x1041d5790 =
    // `KSPlayer.KSPlayerError`, `str wzr,[x1]` writing code 0 (.unknown) and
    // `stp x19,x20,[x1,#8]` writing the message String, then _swift_willThrow.
    //
    // The thrown message is READ IN FULL, not inferred. It is a string interpolation built
    // inline at 0x101a66a64-0x101a66b3c from three literal pieces:
    //   · head @0x103d36e50, len 0x24=36 — "pixelBufferPool Create fail. format=". The
    //     register holds 0x103d36e30 because the pointer carries the 0x20 nativeBias
    //     (`sub x8,x8,#0x20`); the UTF-8 starts at the adrp+add result, not the biased value.
    //   · ", width="  — REGISTER-FORM small string, x0 = 0x3d68746469772 02c, x1 = 0xE8..(count 8)
    //   · " height="  — REGISTER-FORM small string, x0 = 0x3d746867696568 20, same discriminator
    // The first interpolated value goes through a type-metadata ACCESSOR (mov x0,#0 /
    // bl 0x10199c2c0) while the other two take Int32's metadata straight from the GOT
    // (0x104112928/0x104112950) — which is why the first is `format` (AVPixelFormat) and not
    // `format.rawValue`, an Int32 that would have used the same GOT pair.
    // 0x1019b2bec is NOT a message builder: its result becomes x1 of _swift_allocError, i.e.
    // the `KSPlayerError: Error` conformance witness table.
    func transfer(frame: AVFrame) throws -> PixelBufferProtocol {
        let format = AVPixelFormat(rawValue: frame.format)
        let pbuf: PixelBufferProtocol
        if format == AV_PIX_FMT_VIDEOTOOLBOX {
            pbuf = unsafeBitCast(frame.data.3, to: CVPixelBuffer.self)
        } else if dstWidth == nil, dstHeight == nil,
                  format == AV_PIX_FMT_RGBA || format == AV_PIX_FMT_YUV420P10LE
                  || format == AV_PIX_FMT_YUV422P10LE || format == AV_PIX_FMT_YUV444P10LE {
            let pixelBuffer = PixelBuffer(frame: frame)
            // Forward 0x101a666f8: a direct class-field store (beginAccess on PixelBuffer+0x30) in this
            // branch, ahead of the common-tail witness set below.
            pixelBuffer.aspectRatio = frame.sample_aspect_ratio.size
            pbuf = pixelBuffer
        } else {
            let width = frame.width
            let height = frame.height
            guard let pixelBuffer = transfer(format: format, width: width, height: height, data: Array(tuple: frame.data), linesize: Array(tuple: frame.linesize)) else {
                throw KSPlayerError(code: 0, description: "pixelBufferPool Create fail. format=\(format), width=\(width) height=\(height)")
            }
            pixelBuffer.yCbCrMatrix = frame.colorspace.ycbcrMatrix
            pixelBuffer.colorPrimaries = frame.color_primaries.colorPrimaries
            pixelBuffer.transferFunction = frame.color_trc.transferFunction
            if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_UseGamma {
                let gamma = NSNumber(value: frame.color_trc == AVCOL_TRC_GAMMA22 ? 2.2 : 2.8)
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferGammaLevelKey, gamma, .shouldPropagate)
            }
            if let chroma = frame.chroma_location.chroma {
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferChromaLocationTopFieldKey, chroma, .shouldPropagate)
            }
            pbuf = pixelBuffer
        }
        pbuf.aspectRatio = frame.sample_aspect_ratio.size
        configureColorSpace(dovi: dovi, pixelBuffer: pbuf)
        return pbuf
    }

    // RECONSTRUCT FAITHFUL (T2) — slot31 @0x101a66c6c, PURE-sws (field-offset-verified DV-free):
    // sws_scale path + manual plane pixel-copy (CVPixelBuffer plane ops + memmove).
    func transfer(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        // Forward 0x101a66c6c: empty `linesize` returns nil before setup; a 1-element array takes linesize[0].
        guard !linesize.isEmpty else {
            return nil
        }
        setup(format: format, width: width, height: height, linesize: linesize.count == 1 || linesize[1] == 0 ? linesize[0] : linesize[1])
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
    // ⚑[invented=processSideData addr=0x101a67274 exhaustion=name_exhaustion_gate approved=orchestrator]
    func processSideData(frame: AVFrame, assetTrack: FFmpegAssetTrack, options: KSOptions, packet: UnsafeMutablePointer<AVPacket>?) {
        edrMetaData = nil
        hdr10PlusData = nil
        rpuBuffer = nil

        var displayData: MasteringDisplayMetadata?
        var contentData: ContentLightMetadata?
        var ambientViewingEnvironment: AmbientViewingEnvironment?
        var isVIVID = false

        if frame.nb_side_data > 0 {
            for i in 0 ..< frame.nb_side_data {
                guard let sideData = frame.side_data[Int(i)]?.pointee else {
                    continue
                }
                if sideData.type == AV_FRAME_DATA_A53_CC {
                    if let closedCaptionsTrack = assetTrack.closedCaptionsTrack,
                       let subtitle = closedCaptionsTrack.subtitle {
                        let closedCaptionsPacket = Packet()
                        if let sourcePacket = packet,
                           let destinationPacket = closedCaptionsPacket.corePacket {
                            destinationPacket.pointee.pts = sourcePacket.pointee.pts
                            destinationPacket.pointee.dts = sourcePacket.pointee.dts
                            destinationPacket.pointee.pos = sourcePacket.pointee.pos
                            destinationPacket.pointee.time_base = sourcePacket.pointee.time_base
                            destinationPacket.pointee.stream_index = sourcePacket.pointee.stream_index
                        }
                        if let destinationPacket = closedCaptionsPacket.corePacket {
                            destinationPacket.pointee.flags |= AV_PKT_FLAG_KEY
                            destinationPacket.pointee.size = Int32(sideData.size)
                        }
                        // Forward 0x101a67670: av_buffer_ref runs unconditionally, after the corePacket nil test.
                        let buffer = av_buffer_ref(sideData.buf)
                        if let destinationPacket = closedCaptionsPacket.corePacket {
                            destinationPacket.pointee.data = buffer?.pointee.data
                            destinationPacket.pointee.buf = buffer
                        }
                        closedCaptionsPacket.assetTrack = closedCaptionsTrack
                        subtitle.putPacket(packet: closedCaptionsPacket)
                    }
                } else if sideData.type == AV_FRAME_DATA_SEI_UNREGISTERED {
                    if sideData.size >= 17 {
                        let str = String(cString: sideData.data.advanced(by: Int(AV_UUID_LEN)))
                        var timestamp = frame.best_effort_timestamp
                        if timestamp < 0 {
                            timestamp = frame.pts
                        }
                        if timestamp < 0 {
                            timestamp = frame.pkt_dts
                        }
                        options.sei(string: str, time: assetTrack.timebase.cmtime(for: max(0, timestamp)) - assetTrack.startTime)
                    }
                } else if sideData.type == AV_FRAME_DATA_DOVI_METADATA {
                    sideData.data.withMemoryRebound(to: AVDOVIMetadata.self, capacity: 1) { data in
                        doviData = convertAVDOVIToKSDOVIMetadata(data)
                    }
                    if assetTrack.dovi == nil,
                       frame.color_trc == AVCOL_TRC_UNSPECIFIED,
                       options.hardwareDecode,
                       options.display !== KSOptions.displayEnumDovi {
                        options.display = KSOptions.displayEnumDovi
                    }
                } else if sideData.type == AV_FRAME_DATA_DOVI_RPU_BUFFER {
                    if assetTrack.dovi?.dv_profile != 7 {
                        rpuBuffer = Data(bytes: sideData.data, count: Int(sideData.size))
                    }
                } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_PLUS {
                    var output: UnsafeMutablePointer<UInt8>?
                    var outputSize = 0
                    let result = sideData.data.withMemoryRebound(to: AVDynamicHDRPlus.self, capacity: 1) { data in
                        av_dynamic_hdr_plus_to_t35(data, &output, &outputSize)
                    }
                    if result >= 0, let output, outputSize >= 1 {
                        hdr10PlusData = Data(bytes: output, count: outputSize)
                        av_free(output)
                    }
                } else if sideData.type == AV_FRAME_DATA_MASTERING_DISPLAY_METADATA {
                    let data = sideData.data.withMemoryRebound(to: AVMasteringDisplayMetadata.self, capacity: 1) { $0 }.pointee
                    displayData = MasteringDisplayMetadata(
                        display_primaries_r_x: UInt16(truncatingIfNeeded: data.display_primaries.0.0.num),
                        display_primaries_r_y: UInt16(truncatingIfNeeded: data.display_primaries.0.1.num),
                        display_primaries_g_x: UInt16(truncatingIfNeeded: data.display_primaries.1.0.num),
                        display_primaries_g_y: UInt16(truncatingIfNeeded: data.display_primaries.1.1.num),
                        display_primaries_b_x: UInt16(truncatingIfNeeded: data.display_primaries.2.1.num),
                        display_primaries_b_y: UInt16(truncatingIfNeeded: data.display_primaries.2.1.num),
                        white_point_x: UInt16(truncatingIfNeeded: data.white_point.0.num),
                        white_point_y: UInt16(truncatingIfNeeded: data.white_point.1.num),
                        minLuminance: UInt32(truncatingIfNeeded: data.min_luminance.num),
                        maxLuminance: UInt32(truncatingIfNeeded: data.max_luminance.num)
                    )
                } else if sideData.type == AV_FRAME_DATA_CONTENT_LIGHT_LEVEL {
                    let data = sideData.data.withMemoryRebound(to: AVContentLightMetadata.self, capacity: 1) { $0 }.pointee
                    contentData = ContentLightMetadata(
                        MaxCLL: UInt16(data.MaxCLL),
                        MaxFALL: UInt16(data.MaxFALL)
                    )
                } else if sideData.type == AV_FRAME_DATA_AMBIENT_VIEWING_ENVIRONMENT {
                    let data = sideData.data.withMemoryRebound(to: AVAmbientViewingEnvironment.self, capacity: 1) { $0 }.pointee
                    ambientViewingEnvironment = AmbientViewingEnvironment(
                        ambient_illuminance: UInt32(truncatingIfNeeded: data.ambient_illuminance.num),
                        ambient_light_x: UInt16(truncatingIfNeeded: data.ambient_light_x.num),
                        ambient_light_y: UInt16(truncatingIfNeeded: data.ambient_light_y.num)
                    )
                } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_VIVID {
                    isVIVID = true
                }
            }
        }

        if displayData != nil || contentData != nil || ambientViewingEnvironment != nil {
            edrMetaData = EDRMetaData(
                displayData: displayData,
                contentData: contentData,
                ambientViewingEnvironment: ambientViewingEnvironment,
                isVIVID: isVIVID
            )
        }
    }

    func shutdown() {
        sws_freeContext(imgConvertCtx)
        imgConvertCtx = nil
    }
}

// ⚑[invented=configureColorSpace addr=0x101a88b68 exhaustion=name_exhaustion_gate approved=orchestrator]
func configureColorSpace(dovi: DOVIDecoderConfigurationRecord?, pixelBuffer: PixelBufferProtocol) {
    if pixelBuffer.transferFunction == nil, let dovi {
        switch dovi.dv_bl_signal_compatibility_id {
        case 0, 1:
            pixelBuffer.transferFunction = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case 4:
            pixelBuffer.transferFunction = kCVImageBufferTransferFunction_ITU_R_2100_HLG
        default:
            break
        }
    }
    if let colorPrimaries = pixelBuffer.colorPrimaries {
        pixelBuffer.colorspace = KSOptions.colorSpace(
            colorPrimaries: colorPrimaries,
            transferFunction: pixelBuffer.transferFunction,
            dovi: dovi
        )
    }
    if pixelBuffer.colorspace == nil, let dovi {
        switch dovi.dv_bl_signal_compatibility_id {
        case 0, 1:
            pixelBuffer.colorspace = KSOptions.colorSpace2020PQ
        case 4:
            pixelBuffer.colorspace = KSOptions.colorSpace2020HLG
        default:
            break
        }
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

    // Slot 23 (vtable idx10) @0x101a67c34, 368 instr — one of only two non-NULL Impls in this
    // class's 13-entry vtable. The address is NOT_IN_TRIE, so the identification is the
    // vtable's plus the body's own arguments: the `#function` literal is the 18-char
    // `setup(descriptor:)` and the `#fileID` literal is the 23-char `KSPlayer/Resample.swift`,
    // both read off the log calls below — which also proves both sites are lexically inside
    // THIS method rather than inlined from elsewhere.
    //
    // Two error paths the previous reconstruction did not have at all. They are NOT one shared
    // message: the two 37-char literals differ, and both are followed by the same 11-char
    // ` inChannel=` segment. The string reserve constant 52 confirms the shape exactly —
    // (37 + 11) literal chars + 2*2 for two interpolations. Both interpolate through
    // `(extension in KSPlayer):__C.AVChannelLayout.description` @0x101a09460, first the
    // out_ch_layout argument (descriptor+0x40) then the in_ch_layout one (descriptor+0x20),
    // which are `outChannel` and `channel` respectively at the alloc call below.
    // Both sites are gated on `KSOptions.logLevel` >= case index 2 = `.error`, compared as a
    // 1-byte discriminant (NOT the Int32 rawValue 16).
    // ⚑[tool=ffmpeg_name_oracle ref=swr_alloc_set_opts2:0x103288ad4 result=CONFIRMED] (swresample.o)
    // ⚑[tool=ffmpeg_name_oracle ref=swr_free:0x10344997c result=CONFIRMED] (the teardown `shutdown()` reaches)
    private func setup(descriptor: AudioDescriptor) -> Bool {
        var result = swr_alloc_set_opts2(&swrContext, &descriptor.outChannel, descriptor.audioFormat.sampleFormat, Int32(descriptor.audioFormat.sampleRate), &descriptor.channel, descriptor.sampleFormat, descriptor.sampleRate, 0, nil)
        // The binary TESTS this first return value (`tbnz w20,#0x1f` @0x101a67d78) and only
        // reaches the second call when it is non-negative. The previous reconstruction
        // overwrote `result` unread on the next line, so this sign test was missing entirely.
        if result < 0 {
            KSLog(level: .error, "swr_alloc_set_opts2 fail. outChannel=\(descriptor.outChannel) inChannel=\(descriptor.channel)")
            // This path does NOT tear down — it branches straight to the `return false`
            // epilogue @0x101a68178. Only the second failure path frees the context.
            return false
        }
        result = swr_init(swrContext)
        if result < 0 {
            KSLog(level: .error, "swr_init swrContext fail. outChannel=\(descriptor.outChannel) inChannel=\(descriptor.channel)")
            shutdown()
            return false
        }
        outChannel = descriptor.outChannel
        return true
    }

    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        // Forward 0x101a681f4: the nil-context test comes first, and a change updates the EXISTING
        // descriptor in place (sampleFormat +0x38, sampleRate +0x10, channel +0x20, outChannel +0x40,
        // then updateAudioFormat 0x101a68a74 and setup 0x101a67c34) — no new AudioDescriptor is
        // allocated. `setup`'s Bool is never tested; the guard reads self.swrContext once and that
        // register feeds both swr_get_out_samples and swr_convert.
        if swrContext == nil || !(descriptor == avframe.pointee) || outChannel != descriptor.outChannel {
            // Forward loads format (+0x74), sample_rate (+0xb4) and ch_layout (+0x180..0x198) once,
            // before the first descriptor store, and stores the same ch_layout registers into both
            // channel (+0x20) and outChannel (+0x40): the frame is read as one value.
            let frame = avframe.pointee
            descriptor.sampleFormat = AVSampleFormat(rawValue: frame.format)
            descriptor.sampleRate = frame.sample_rate > 0 ? frame.sample_rate : 48000
            descriptor.channel = frame.ch_layout
            descriptor.outChannel = frame.ch_layout
            descriptor.updateAudioFormat()
            _ = setup(descriptor: descriptor)
        }
        // ⚑ `.auidoSwrInit` IS NOT A CASE IN THE IMAGE — and neither is a `userInfo` dictionary: the
        //   whole payload is one interpolated String built from the 30-byte literal at 0x103d36db0,
        //   " inChannel=", and two AVChannelLayout.description calls on descriptor+0x40 / +0x20.
        guard let swrContext else {
            throw KSPlayerError(code: 0, description: "swrContext is nil. outChannel=\(descriptor.outChannel) inChannel=\(descriptor.channel)")
        }
        let numberOfSamples = avframe.pointee.nb_samples
        let outSamples = swr_get_out_samples(swrContext, numberOfSamples)
        let channels = descriptor.outChannel.nb_channels
        var bufferSize = [Int32(0)]
        // 返回值是有乘以声道，所以不用返回值
        _ = av_samples_get_buffer_size(&bufferSize, channels, outSamples, descriptor.audioFormat.sampleFormat, 1)
        let frame = AudioFrame(dataSize: UInt32(bufferSize[0]), audioFormat: descriptor.audioFormat)
        // Forward builds the input pointer array AFTER AudioFrame.init (0x101a68454).
        var frameBuffer = Array(tuple: avframe.pointee.data).map { UnsafePointer<UInt8>($0) }
        // Forward clamps a negative result to 0 (`bic w19,w19,w19,asr #31`) instead of trapping.
        frame.numberOfSamples = UInt32(max(0, swr_convert(swrContext, &frame.data, outSamples, &frameBuffer, numberOfSamples)))
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

    /// Vtable F16: a dead slot of shape M, so Forward keeps no body, callers or strings. Name INFERRED;
    /// the declaration only holds the slot.
    func unreadSlot16() {}

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

    // ⚠️ DIVERGENT, and it is the ROOT of two divergences previously attributed to
    // `updateAudioFormat()`. Body @0x101a68c44, extent 0x101a68c44-0x101a68f3c, 190 instructions.
    //
    // Forward's helper DOES NOT SWITCH ON `sampleFormat`. Read from the binary:
    //   · no register-indirect dispatch anywhere in the extent (`br x` count 0), so no jump table
    //     and no switch;
    //   · its eight compares are cmp w2,w8 / cmp x8,x23 / cmp x8,x23 / cmp x8,x9 / cmp w8,#0x3 /
    //     cmn x8,#0x1 / cmn x8,#0x1 / cmp x23,x22 — none a multi-way dispatch on an AVSampleFormat;
    //   · the AVAudioFormat construction takes `commonFormat` UNCONDITIONALLY —
    //       101a68ea0: cmp   x23, x22
    //       101a68ea4: cset  w21, eq     <- `interleaved`, one equality test
    //       101a68ea8: scvtf d8, w19     <- Double(sampleRate)
    //       101a68eb8: mov   w2, #0x1    <- commonFormat = 1; no branch reaches this instruction
    //       101a68ec0: mov   x3, x21
    //       101a68ec4: mov   x4, x20     <- channelLayout
    //       101a68ec8: bl    0x103462d60
    //     so the eight-case switch below and the `if !(A || B) { commonFormat = ... }` after it
    //     have no counterpart in Forward at all.
    //
    // CONSEQUENCE, and why this matters beyond this one body: with the switch gone, `sampleFormat`
    // becomes unused, the optimizer dead-argument-eliminates it, and the emitted call takes three
    // registers (x0=sampleRate, x1=&outChannel, x2=channelCount) instead of four. That is what made
    // `updateAudioFormat()` look like it called a three-parameter helper and look like it never read
    // `self.sampleFormat`. Both were artifacts of THIS body, and the s84 verdict attributed them to
    // the caller. The DECLARATION is not in question: this callee materializes its own `#function`
    // literal as `audioFormat(sampleFormat:sampleRate:outChannel:channelCount:)` — 61 chars at
    // 0x103d36df0, four labels, with its `#file` companion — so Forward declares four parameters
    // exactly as we do.
    //
    // NOT REWRITTEN HERE: the two `cmp x8,x23` metatype comparisons and the `layoutTag` derivation
    // were not read instruction by instruction, so the replacement body is not written rather than
    // guessed. Its own unit.
    // ⚑[tool=recover_swift_function_name ref=AudioDescriptor.audioFormat:0x101a68c44 result=4-label-#function]
    // ⚑[tool=function_extents ref=AudioDescriptor.audioFormat:0x101a68c44 result=190-instr-no-switch]
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
        let commonFormat = AVAudioCommonFormat.pcmFormatFloat32 // 0x101a68eb8 `mov w2,#0x1`: unconditional
        // No sampleFormat switch in Forward (header above); upstream switch kept commented for reference:
        // switch sampleFormat {
        // case AV_SAMPLE_FMT_S16:
        //     commonFormat = .pcmFormatInt16
        //     interleaved = true
        // case AV_SAMPLE_FMT_S32:
        //     commonFormat = .pcmFormatInt32
        //     interleaved = true
        // case AV_SAMPLE_FMT_FLT:
        //     commonFormat = .pcmFormatFloat32
        //     interleaved = true
        // case AV_SAMPLE_FMT_DBL:
        //     commonFormat = .pcmFormatFloat64
        //     interleaved = true
        // case AV_SAMPLE_FMT_S16P:
        //     commonFormat = .pcmFormatInt16
        //     interleaved = false
        // case AV_SAMPLE_FMT_S32P:
        //     commonFormat = .pcmFormatInt32
        //     interleaved = false
        // case AV_SAMPLE_FMT_FLTP:
        //     commonFormat = .pcmFormatFloat32
        //     interleaved = false
        // case AV_SAMPLE_FMT_DBLP:
        //     commonFormat = .pcmFormatFloat64
        //     interleaved = false
        // default:
        //     commonFormat = .pcmFormatFloat32
        //     interleaved = false
        // }
        let interleaved = KSOptions.audioPlayerType == AudioRendererPlayer.self
        // if !(KSOptions.audioPlayerType == AudioRendererPlayer.self || KSOptions.audioPlayerType == AudioUnitPlayer.self) {
        //     commonFormat = .pcmFormatFloat32
        // }
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
