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
    private let maxFrameCount: Int = 0 // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private let codecID: AVCodecID = AV_CODEC_ID_NONE // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private let options: KSOptions
    private let flags: VTDecodeFrameFlags = [] // ⚑ UNRESOLVED→P3: devirt-init-set; default placeholder
    private var startTime: Int64 = 0
    private var maxTimestamp: Int64 = 0
    private var lastTimestamp: Int64 = -1
    private var needReconfig: Bool = false
    // P3a (Phase A): KSDOVIMetadata = opaque 3008-byte inline DV buffer (DOVIRPUShim). Field-record name
    // `KSDOVIMetadata?`; an opaque blob has no nil-tag inhabitant in 3008B → NON-optional + optionality flagged → DV-render.
    // ⚑[tool=vpfi_initializer_oracle ref=VideoToolboxDecode.doviData:0x10199afc8 result=CONFIRMED]
    // Field record says `KSDOVIMetadata?` (Optional); the declaration default is NOT nil — its vpfi
    // is a 15-instruction body that constructs a value and memcpys 0xbc0 bytes, so the Optional is
    // initialised non-nil. Both halves are needed: the `?` alone would imply `= nil`.
    private var doviData: KSDOVIMetadata? = KSDOVIMetadata()
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
        // body-audited FAITHFUL (commits c203481 + the 489b6a5 shutdown tail).
        //
        // ⚠️ SCOPE CORRECTION — the ⚑P3 deferral does NOT belong to this body. This comment used to say
        // "each `maxTimestamp` below marked ⚑P3 is an UNVERIFIED placeholder", which reads as a deferral on
        // `decodeFrame`. The four ⚑P3 lines (150, 151, 153, 158) are lexically inside `decodeFrame` but they
        // sit in the `[weak self]` closure handed to VTDecompressionSessionDecodeFrame below — and that
        // closure is a SEPARATE binary function with its own address.
        //
        // Measured over this body's whole extent, 0x101a6ce44-0x101a6d734, 572 instructions: the only
        // touches of self+0x30 / +0x38 / +0x40 are TWO stores, `str x8,[x19,#0x40]` @0x101a6cf0c and
        // @0x101a6d65c — the two doFlushCodec resets. There is no read of any of the three, so nothing in
        // this extent implements the timestamp bookkeeping the ⚑P3 markers describe.
        // ⚑[tool=function_extents ref=VideoToolboxDecode.decodeFrame:0x101a6ce44 result=572-instr-two-0x40-stores]
        //
        // The deferral is real, but it is the CLOSURE's, and it needs the closure's own address and unit.
        // Cached: VTBox_slot29_101a6ce44.txt.
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
            let sampleBuffer = try session.formatDescription.getSampleBuffer(data: data, size: Int(corePacket.size))
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
                // VideoVTBFrame.pixelBuffer is non-optional in the binary, but the VT completion
                // handler hands us a CVImageBuffer?. How Forward's handler treats a nil buffer is
                // NOT read — its closure body @0x101a6eb44 is a separate, unnamed function — so this
                // unwrap is OURS, not Forward's.
                // ⚑[tool=export_trie_oracle ref=vt_output_handler_closure:0x101a6eb44 result=NOT_IN_TRIE]
                guard let imageBuffer else { return }
                let frame = VideoVTBFrame(pixelBuffer: imageBuffer, fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil)
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

    // slot30 @0x101a6ebf4. NAME PROVEN, not inferred: the DecodeProtocol witness table for
    // VideoToolboxDecode (scripts/decode_witness_table.py --wt 0x1041d95c8, conf_desc 0x10356bbd8)
    // lists its 4 requirements in protocol-declaration order —
    //   req0 0x101a6ecfc (direct) · req1 ->0x101a6ce44 · req2 ->0x101a6ebf4 · req3 ->0x101a6ec80
    // against DecodeProtocol's declaration order decode · decodeFrame · doFlushCodec · shutdown
    // (MEPlayerItemTrack.swift:293-298). So req2 = doFlushCodec = THIS body, and req0 = decode()
    // = the 4-instruction slot-32 body below. (This supersedes the earlier slot-ORDER argument,
    // which could only pin the {doFlushCodec, decode} PAIR, never which was which.)
    // Body, verbatim from disasm @0x101a6ebf4: `stp xzr,xzr,[x20,#0x30]` (startTime, maxTimestamp)
    // · `mov x8,#-0x1; str x8,[x20,#0x40]` (lastTimestamp) · two VTDecompressionSession calls on
    // session(+0xcf8).decompressionSession(+0x18) · beginAccess+__swiftEmptyArrayStorage on
    // frames(+0xcf0) · `cmp w8,#0x1b` on session.assetTrack.codecpar.codec_id → needReconfig(+0x48)=1.
    // ⚑ 0x1b = 27 = AV_CODEC_ID_H264, counted from AV_CODEC_ID_NONE in FFmpeg-n8.1.1
    // libavcodec/codec_id.h:79 — written symbolically below, never as the raw ordinal.
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

    // slot32 @0x101a6ecfc, whole body (4 instr): `stp xzr,xzr,[x20,#0x30]` · `mov x8,#-0x1` ·
    // `str x8,[x20,#0x40]` · `ret`. The two stored zeroes land on ONE `stp`, which is also the
    // layout proof for the three fields — startTime@+0x30, maxTimestamp@+0x38 (adjacent,
    // hence pairable) and lastTimestamp@+0x40. The -1 is a full-width 64-bit integer store,
    // so these three are Int64, NOT the Double that l2_field_gate's unscoped symbol lookup
    // reports for startTime (the gate itself marks that UNCHECKED / "verify via field-record mangle").
    // NAME PROVEN by the DecodeProtocol witness table, req0 → this address directly (see doFlushCodec).
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
        if let destinationDynamicRange = options.availableDynamicRange() {
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
    // ⚑ REMOVED (s106): the `isConvertNALSize` parameter and the AVCC→AnnexB rewrite it guarded
    //   (avio_open_dyn_buf → avio_wb32/avio_write → avio_close_dyn_buf). The flag's only producer,
    //   FFmpegAssetTrack's `extradata[4] == 0xFE` test, is proven absent from that class's designated
    //   init, so the branch is unreachable in Forward. Corroborated from the consumer side:
    //   VideoToolboxDecode.decodeFrame has 40 callees and exactly three in the FFmpeg band
    //   (ff_dovi_get_metadata CONFIRMED, one UNKNOWN, one an ICF-folded free/close family) — no
    //   avio_* call of any kind, where this branch would need four.
    //   ⚑ FAITHFUL-PARTIAL: proven the branch cannot be entered and that decodeFrame does not call
    //   avio_*; NOT proven that no outlined copy of this helper exists — it emits no symbol under
    //   this name (a real trie negative, since the trie does carry fileprivate members with
    //   discriminators), which is equally consistent with having been inlined.
    //   ⚑[tool=llvm-objdump ref=VideoToolboxDecode.decodeFrame:0x101a6ce44-0x101a6d734 result=no-avio-callee]
    //   ⚑[tool=export_trie_oracle ref=CMFormatDescription.getSampleBuffer:trie result=NOT-IN-TRIE]
    fileprivate func getSampleBuffer(data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
        try createSampleBuffer(data: data, size: size)
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
