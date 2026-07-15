//
//  VideoToolboxDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/10.
//

import DOVIRPUShim
import FFmpegKit
import Libavformat
import Libavutil
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    // P2 Task 3 field delta (reflection ORDER = layout; −lastPosition, +9 new). ⚑ = inferred/opaque → P3.
    private var maxFrameCount: Int = 0 // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private var codecID: AVCodecID = AV_CODEC_ID_NONE // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private let options: KSOptions
    private var flags: VTDecodeFrameFlags = [] // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private var startTime: Int64 = 0
    private var maxTimestamp: Int64 = 0
    private var lastTimestamp: Int64 = -1
    private var needReconfig: Bool = false
    // P3a (Phase A): KSDOVIMetadata = opaque 3008-byte inline DV buffer (DOVIRPUShim). Field-record name
    // `KSDOVIMetadata?`; an opaque blob has no nil-tag inhabitant in 3008B → NON-optional + optionality flagged → DV-render.
    private var doviData: KSDOVIMetadata = KSDOVIMetadata()
    // P3a (Phase A): DOVIContext = FFmpeg's private DV parser context, opaque 224-byte inline @+0xc10 (DOVIRPUShim).
    // Caller-owned inline value that the raw ff_dovi_*(&doviContext) calls populate/release (decodeFrame crash-loop → Phase B).
    private var doviContext: DOVIContext = DOVIContext()
    private var frames: [VideoVTBFrame] = []
    private var session: DecompressionSession {
        didSet {
            VTDecompressionSessionInvalidate(oldValue.decompressionSession)
            // Forward divergence (slot22 setter): the didSet also resets the timestamp state.
            startTime = 0
            maxTimestamp = 0
            lastTimestamp = -1
        }
    }
    private var formatDescriptionOut: CMFormatDescription? = nil // set in the deferred decodeFrame → P3

    init(options: KSOptions, session: DecompressionSession) {
        self.options = options
        self.session = session
    }

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        // P3a DONE: the DV RPU-extraction loop below (after the guard) reconstructs Forward's hardware-path
        // DV decode (binary L120-236 @0x101a6ce44; ff_dovi_rpu_parse→get_metadata→convertAVDOVIToKSDOVIMetadata),
        // body-audited FAITHFUL (commits c203481 + the 489b6a5 shutdown tail). STILL DEFERRED: each `maxTimestamp`
        // below marked ⚑P3 is an UNVERIFIED lastPosition→maxTimestamp placeholder (the removed field) — the
        // VTDecode output-handler timestamp semantics are a separate unit. Structural-diff → P8. Cached: VTBox_slot29_101a6ce44.txt.
        if needReconfig {
            // 解决从后台切换到前台，解码失败的问题
            session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
            doFlushCodec()
            needReconfig = false
        }
        guard let corePacket = packet.corePacket?.pointee, let data = corePacket.data else {
            return
        }
        // P3a Phase B Step 2 — Dolby-Vision RPU extraction (binary L120-236 @0x101a6ce44, ADDITIVE).
        let nalUnits = parseNALUnits(data: data, size: Int(corePacket.size), codecID: codecID)
        for nalUnit in nalUnits {
            // L155: HEVC (kind 1) DV-RPU NAL (type 0x3e = 62).
            guard nalUnit.kind == 1, nalUnit.type == 62 else { continue }
            // EPB-strip — H.265 emulation-prevention removal (decompile L162-214, transcribed).
            // allocLen = nalUnit.length - 2 (the 2-byte HEVC NAL header is skipped). src = data + offset + 2.
            let allocLen = Int(nalUnit.length) - 2
            let stripped = UnsafeMutablePointer<UInt8>.allocate(capacity: allocLen)
            let src = data + Int(nalUnit.offset) + 2
            var strippedLen = 0
            if allocLen != 0 {
                var outPos = 0
                var zeroRun = 0
                var readIdx = 0
                while true {
                    var nextIdx = readIdx + 1
                    var byte = src[readIdx]
                    if zeroRun == 2, byte == 0x03 {
                        strippedLen = outPos
                        if nextIdx == allocLen { break }
                        zeroRun = 0
                        byte = src[nextIdx]
                        nextIdx = readIdx + 2
                    }
                    stripped[outPos] = byte
                    strippedLen = outPos + 1
                    if byte == 0 {
                        zeroRun += 1
                        if nextIdx == allocLen { break }
                    } else {
                        if nextIdx == allocLen { break }
                        zeroRun = 0
                    }
                    outPos += 1
                    readIdx = nextIdx
                }
            } else {
                strippedLen = 0
            }
            // &doviContext ⇒ the compiler emits the exclusive begin/endAccess (decompile L216/218).
            ff_dovi_rpu_parse(&doviContext, stripped, strippedLen, 0)
            stripped.deallocate()
            var out: UnsafeMutablePointer<AVDOVIMetadata>? = nil
            ff_dovi_get_metadata(&doviContext, &out)
            if let out {
                doviData = convertAVDOVIToKSDOVIMetadata(out)
                av_free(out)
            }
        }
        do {
            let sampleBuffer = try session.formatDescription.getSampleBuffer(isConvertNALSize: session.assetTrack.isConvertNALSize, data: data, size: Int(corePacket.size))
            let flags: VTDecodeFrameFlags = [
                ._EnableAsynchronousDecompression,
            ]
            var flagOut = VTDecodeInfoFlags.frameDropped
            let timestamp = packet.timestamp
            let packetFlags = corePacket.flags
            let duration = corePacket.duration
            let size = corePacket.size
            let status = VTDecompressionSessionDecodeFrame(session.decompressionSession, sampleBuffer: sampleBuffer, flags: flags, infoFlagsOut: &flagOut) { [weak self] status, infoFlags, imageBuffer, _, _ in
                guard let self, !infoFlags.contains(.frameDropped) else {
                    return
                }
                guard status == noErr else {
                    if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                        if packet.isKeyFrame {
                            completionHandler(.failure(NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)))
                        } else {
                            // 解决从后台切换到前台，解码失败的问题
                            self.needReconfig = true
                        }
                    }
                    return
                }
                let frame = VideoVTBFrame(fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil)
                frame.pixelBuffer = imageBuffer
                frame.timebase = session.assetTrack.timebase
                if packet.isKeyFrame, packetFlags & AV_PKT_FLAG_DISCARD != 0, self.maxTimestamp > 0 { // ⚑P3 lastPosition→maxTimestamp
                    self.startTime = self.maxTimestamp - timestamp // ⚑P3 lastPosition→maxTimestamp
                }
                self.maxTimestamp = max(self.maxTimestamp, timestamp) // ⚑P3 lastPosition→maxTimestamp
                frame.position = packet.position
                frame.timestamp = self.startTime + timestamp
                frame.duration = duration
                frame.size = size
                self.maxTimestamp += frame.duration // ⚑P3 lastPosition→maxTimestamp
                completionHandler(.success(frame))
            }
            if status == noErr {
                if !flags.contains(._EnableAsynchronousDecompression) {
                    VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
                }
            } else if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                if packet.isKeyFrame {
                    throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
                } else {
                    // 解决从后台切换到前台，解码失败的问题
                    needReconfig = true
                }
            }
        } catch {
            completionHandler(.failure(error))
        }
    }

    func doFlushCodec() {
        startTime = 0
        maxTimestamp = 0
        lastTimestamp = -1
        VTDecompressionSessionFinishDelayedFrames(session.decompressionSession)
        VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
        frames = []
        if session.assetTrack.codecpar.pointee.codec_id == AV_CODEC_ID_H264 {
            needReconfig = true
        }
    }

    func shutdown() {
        VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
        VTDecompressionSessionInvalidate(session.decompressionSession)
        frames = []
        // P3a: free the DV parser context (slot31 0x101a6ec80, FUN_102a3b4e0 = ff_dovi_ctx_unref).
        // &doviContext ⇒ the compiler emits the exclusive begin/endAccess (decompile L30/32).
        ff_dovi_ctx_unref(&doviContext)
    }

    func decode() {
        startTime = 0
        maxTimestamp = 0
        lastTimestamp = -1
    }
}

class DecompressionSession {
    fileprivate let formatDescription: CMFormatDescription
    fileprivate let decompressionSession: VTDecompressionSession
    fileprivate var assetTrack: FFmpegAssetTrack
    init?(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.assetTrack = assetTrack
        guard let pixelFormatType = assetTrack.pixelFormatType, let formatDescription = assetTrack.formatDescription else {
            return nil
        }
        self.formatDescription = formatDescription
        #if os(macOS)
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
        if #available(macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(formatDescription.mediaSubType.rawValue)
        }
        #endif
//        VTDecompressionSessionCanAcceptFormatDescription(<#T##session: VTDecompressionSession##VTDecompressionSession#>, formatDescription: <#T##CMFormatDescription#>)
        let attributes: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: assetTrack.codecpar.pointee.width,
            kCVPixelBufferHeightKey: assetTrack.codecpar.pointee.height,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ]
        var session: VTDecompressionSession?
        // swiftlint:disable line_length
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDescription, decoderSpecification: CMFormatDescriptionGetExtensions(formatDescription), imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session)
        // swiftlint:enable line_length
        guard status == noErr, let decompressionSession = session else {
            return nil
        }
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            VTSessionSetProperty(decompressionSession, key: kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata,
                                 value: kCFBooleanTrue)
        }
        if let destinationDynamicRange = options.availableDynamicRange(nil) {
            let pixelTransferProperties = [kVTPixelTransferPropertyKey_DestinationColorPrimaries: destinationDynamicRange.colorPrimaries,
                                           kVTPixelTransferPropertyKey_DestinationTransferFunction: destinationDynamicRange.transferFunction,
                                           kVTPixelTransferPropertyKey_DestinationYCbCrMatrix: destinationDynamicRange.yCbCrMatrix]
            VTSessionSetProperty(decompressionSession,
                                 key: kVTDecompressionPropertyKey_PixelTransferProperties,
                                 value: pixelTransferProperties as CFDictionary)
        }
        self.decompressionSession = decompressionSession
    }
}
#endif

extension CMFormatDescription {
    fileprivate func getSampleBuffer(isConvertNALSize: Bool, data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
        if isConvertNALSize {
            var ioContext: UnsafeMutablePointer<AVIOContext>?
            let status = avio_open_dyn_buf(&ioContext)
            if status == 0 {
                var nalSize: UInt32 = 0
                let end = data + size
                var nalStart = data
                while nalStart < end {
                    nalSize = UInt32(nalStart[0]) << 16 | UInt32(nalStart[1]) << 8 | UInt32(nalStart[2])
                    avio_wb32(ioContext, nalSize)
                    nalStart += 3
                    avio_write(ioContext, nalStart, Int32(nalSize))
                    nalStart += Int(nalSize)
                }
                var demuxBuffer: UnsafeMutablePointer<UInt8>?
                let demuxSze = avio_close_dyn_buf(ioContext, &demuxBuffer)
                return try createSampleBuffer(data: demuxBuffer, size: Int(demuxSze))
            } else {
                throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
            }
        } else {
            return try createSampleBuffer(data: data, size: size)
        }
    }

    private func createSampleBuffer(data: UnsafeMutablePointer<UInt8>?, size: Int) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var sampleBuffer: CMSampleBuffer?
        // swiftlint:disable line_length
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: size, blockAllocator: kCFAllocatorNull, customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &blockBuffer)
        if status == noErr {
            status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: self, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer {
                return sampleBuffer
            }
        }
        throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        // swiftlint:enable line_length
    }
}

extension CMVideoCodecType {
    var avc: String {
        switch self {
        case kCMVideoCodecType_MPEG4Video:
            return "esds"
        case kCMVideoCodecType_H264:
            return "avcC"
        case kCMVideoCodecType_HEVC:
            return "hvcC"
        case kCMVideoCodecType_VP9:
            return "vpcC"
        default: return "avcC"
        }
    }
}
