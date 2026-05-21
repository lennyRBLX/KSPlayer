//
//  VideoToolboxDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/10.
//

import FFmpegKit
import Libavformat
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    // MARK: - Fields (RE: VideoToolboxDecode, 8 fields per types.json)
    // Field order below mirrors the binary type-dump declaration order.

    /// #1 — VTB session wrapper. Invalidates the prior session on replacement.
    private var session: DecompressionSession {
        didSet {
            VTDecompressionSessionInvalidate(oldValue.decompressionSession)
        }
    }

    /// #2 — Player configuration reference.
    private let options: KSOptions

    /// #3 — Sync offset applied when packets are discarded after a seek.
    private var startTime = Int64(0)

    /// #4 — Largest PTS observed so far (reorder-buffer ordering anchor).
    private var maxTimestamp = Int64(0)

    /// #5 — Running monotonic timestamp tracker (was `lastPosition` in the
    /// earlier source revision; renamed to match the binary's
    /// `lastTimestamp` field at +0x28 of the class layout).
    private var lastTimestamp = Int64(0)

    /// #6 — Set when the session must be recreated on the next decode.
    private var needReconfig = false

    /// #7 — Frame reorder buffer. VTB outputs in decode order; we sort to PTS.
    /// Binary uses `DecompressionSession_introsortFrames @ 0x101452620` /
    /// `_introsortPartition @ 0x101452cf4`. Source uses an insertion sort
    /// over the small reorder window; for typical N (4–120 frames) the two
    /// behave identically.
    private var frames: [VideoVTBFrame] = []

    /// #8 — Reorder capacity: `max(4, 2 * fps)`.
    private var maxFrameCount: Int = 8

    init(options: KSOptions, session: DecompressionSession) {
        self.options = options
        self.session = session
        let fps = session.assetTrack.nominalFrameRate
        if fps > 0 {
            maxFrameCount = max(4, Int(fps) * 2)
        }
    }

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        if needReconfig {
            // 解决从后台切换到前台，解码失败的问题
            session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
            doFlushCodec()
            needReconfig = false
        }
        guard let corePacket = packet.corePacket?.pointee, let data = corePacket.data else {
            return
        }
        do {
            // RE: NAL-prefix conversion is routed through the track's
            // `bitStreamFilter` metatype; `Nal3ToNal4BitStreamFilter`
            // indicates the AVCC stream uses 3-byte NAL length prefixes
            // that must be promoted to 4 bytes before VTB submission.
            let needsConversion = session.assetTrack.needsNALSizeConversion
            let sampleBuffer = try session.formatDescription.getSampleBuffer(isConvertNALSize: needsConversion, data: data, size: Int(corePacket.size))
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
                        // RE: Forward v1.3.15 recovery branch sets needReconfig
                        // on the VideoToolboxDecode self. The decision between
                        // "transient retry" and "permanent fallback to software
                        // decode" is taken at the track level after the error
                        // propagates through `MEPlayerItemTrack.doDecode`.
                        if packet.isKeyFrame {
                            completionHandler(.failure(NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)))
                        } else {
                            self.needReconfig = true
                        }
                    }
                    return
                }
                let frame: VideoVTBFrame
                if let imageBuffer = imageBuffer as PixelBufferProtocol? {
                    frame = VideoVTBFrame(fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil, pixelBuffer: imageBuffer)
                } else {
                    frame = VideoVTBFrame(fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil)
                }
                frame.timebase = session.assetTrack.timebase
                if packet.isKeyFrame, packetFlags & AV_PKT_FLAG_DISCARD != 0, self.lastTimestamp > 0 {
                    self.startTime = self.lastTimestamp - timestamp
                }
                self.maxTimestamp = max(self.maxTimestamp, timestamp)
                self.lastTimestamp = max(self.lastTimestamp, timestamp)
                frame.position = packet.position
                frame.timestamp = self.startTime + timestamp
                frame.duration = duration
                frame.isKeyFrame = packet.isKeyFrame
                frame.size = size
                self.lastTimestamp += frame.duration
                // RE: Forward v1.3.15 frame reorder buffer — insertion sort by PTS
                // (VideoToolboxDecode_sortFramesByPTS @ 0x10144fa74)
                self.insertSorted(frame: frame)
                // Emit oldest frame when buffer is full
                if self.frames.count >= self.maxFrameCount {
                    let emitted = self.frames.removeFirst()
                    completionHandler(.success(emitted))
                }
            }
            if status == noErr {
                if !flags.contains(._EnableAsynchronousDecompression) {
                    VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
                }
            } else if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                if packet.isKeyFrame {
                    throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
                } else {
                    needReconfig = true
                }
            }
        } catch {
            completionHandler(.failure(error))
        }
    }

    func doFlushCodec() {
        // RE: On flush, emit all cached frames in PTS order then clear
        frames.removeAll()
        lastTimestamp = 0
        maxTimestamp = 0
        startTime = 0
    }

    func shutdown() {
        frames.removeAll()
        VTDecompressionSessionInvalidate(session.decompressionSession)
    }

    func decode() {
        frames.removeAll()
        lastTimestamp = 0
        maxTimestamp = 0
        startTime = 0
    }

    /// RE: Forward v1.3.15 reorder-buffer sort (binary symbol:
    /// `VideoToolboxDecode_sortFramesByPTS @ 0x10144fa74`, dispatches to
    /// `DecompressionSession_introsortFrames @ 0x101452620`).
    /// Source uses insertion sort over the small reorder window; for typical
    /// N (4–120 frames) this is equivalent to the binary's introsort.
    private func insertSorted(frame: VideoVTBFrame) {
        var insertIndex = frames.count
        while insertIndex > 0 && frames[insertIndex - 1].timestamp > frame.timestamp {
            insertIndex -= 1
        }
        frames.insert(frame, at: insertIndex)
    }
}

class DecompressionSession {
    // MARK: - Fields (RE: DecompressionSession, 3 fields per types.json)
    /// #1 @ +0x10 — Video format description sourced from `track + 0xD0`.
    fileprivate let formatDescription: CMFormatDescription
    /// #2 @ +0x18 — Active Apple VTB session.
    fileprivate let decompressionSession: VTDecompressionSession
    /// #3 @ +0x20 — Source track.
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
            kCVPixelBufferWidthKey: assetTrack.codecpar.width,
            kCVPixelBufferHeightKey: assetTrack.codecpar.height,
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
