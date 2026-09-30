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
import AVFoundation
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    // P2 Task 3 field delta (reflection ORDER = layout; −lastPosition, +9 new). ⚑ = inferred/opaque → P3.
    private let maxFrameCount: Int
    private let codecID: AVCodecID
    private let options: KSOptions
    private let flags: VTDecodeFrameFlags
    private var startTime: Int64 = 0
    private var maxTimestamp: Int64 = 0
    private var lastTimestamp: Int64 = -1
    private var needReconfig: Bool = false
    // P3a: KSDOVIMetadata uses the imported-C 3008-byte inline DV metadata layout. The nested Bool
    // at metadata offset 0x457 supplies Optional's extra inhabitant; keep doviData optional.
    // ⚑[tool=vpfi_initializer_oracle ref=VideoToolboxDecode.doviData:0x10199afc result=CONFIRMED]
    // Field record says `KSDOVIMetadata?` (Optional); the declaration default is NOT nil — its vpfi
    // is a 15-instruction body that constructs a value and memcpys 0xbc0 bytes, so the Optional is
    // initialised non-nil. Both halves are needed: the `?` and its non-nil declaration default.
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

    /// Vtable F24: a get-only unit with a dead slot, so Forward keeps no body, callers or strings.
    /// Name and type are INFERRED. The declaration only holds the slot so that init (F25) lines up.
    var unreadSlot24: Bool { false }

    // Forward 0x101a6cc94 is the exported allocating entry of init?(assetTrack:options:asynchronous:).
    // It is a CONVENIENCE init: the object is allocated only after DecompressionSession succeeds and
    // the nil path has no swift_deallocPartialClassInstance (a designated failable init allocates first).
    // The designated init (vtable slot 25) is dead-stripped; its labels are ours, its body is Forward's
    // store sequence: options, codecID, maxFrameCount, options.decodeType = 0, session, flags (9 : 8).
    init(options: KSOptions, session: DecompressionSession, asynchronous: Bool) {
        self.options = options
        codecID = session.assetTrack.codecpar.pointee.codec_id
        maxFrameCount = Int(max(session.assetTrack.reorderSize * 2, 4))
        options.decodeType = .asynchronousHardware
        self.session = session
        flags = asynchronous ? [._EnableAsynchronousDecompression, ._EnableTemporalProcessing] : [._EnableTemporalProcessing]
    }

    convenience init?(assetTrack: FFmpegAssetTrack, options: KSOptions, asynchronous: Bool) {
        guard let session = DecompressionSession(assetTrack: assetTrack, options: options) else {
            return nil
        }
        self.init(options: options, session: session, asynchronous: asynchronous)
    }

    // Declared AFTER init: Forward's vtable has the init at slot 25 and this var's get/set/modify at 26-28.
    private var formatDescriptionOut: CMFormatDescription? = nil // set in the deferred decodeFrame → P3

    // ⚠️ D1 CLOSED — the parameter is `UnsafeMutablePointer<AVPacket>`, and the guard below moved
    // with it. Read over the whole extent 0x101a6ce44-0x101a6d734:
    //   - the parameter (x0 -> x21) takes NO swift_retain/swift_release/objc_retain, has no isa
    //     load, and is never read at offset 0 — it is not a class instance.
    //   - there is NO cbz/cbnz on the parameter before its first dereference at 0x101a6cf14, so
    //     it is non-Optional. The only two conditional branches ahead of that point test
    //     self.needReconfig (self+0x48) and the return of the session builder.
    //   - the nil test that DOES exist is on the loaded `data`: `101a6cf14 ldr x24,[x21,#0x18]` /
    //     `101a6cf18 cbz x24, 0x101a6d664`, and 0x101a6d664 is the stack-guard + epilogue — it
    //     returns WITHOUT invoking completionHandler, which is why the guard has no else-call.
    //   - the offsets touched are exactly {0x8,0x10,0x18,0x20,0x28,0x40,0x48} = pts, dts, data,
    //     size, flags, duration, pos. Under the old `Packet` spelling 0x30/0x38 would be
    //     corePacket/isFlush; neither is ever read.
    // ⚑[tool=export_trie_oracle ref=VideoToolboxDecode.decodeFrame:0x101a6ce44 result=one-symbol-no-ICF-fold]
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
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
            needReconfig = false
        }
        let corePacket = packet.pointee
        guard let data = corePacket.data else {
            return
        }
        // P3a Phase B Step 2 — Dolby-Vision RPU extraction (binary L120-236 @0x101a6ce44, ADDITIVE).
        // L7 lane 18: the PacketNalData dispatcher is inlined here (@0x101a6cf14..; codecID = self+0x18,
        // Annex-B arm @0x101a6d6ac → 0x101a0c470, else 0x101a0ce98).
        let nalUnits = PacketNalData(data: data, size: Int(corePacket.size), codecID: codecID).nals
        for nalUnit in nalUnits {
            // L155: .h265 (tag 1) DV-RPU NAL (value 0x3e = 62) @0x101a6cfbc.
            guard nalUnit.type == .h265(.unspec62) else { continue }
            // EPB-strip — H.265 emulation-prevention removal. Forward (0x101a6ce44) computes offset+2 with
            // an overflow check BEFORE length-2, and bounds-checks each read with an unsigned
            // `readIdx <u allocLen` trap and no add-overflow check: Span's checked subscript, not raw pointer math.
            let start = nalUnit.start + 2
            let allocLen = nalUnit.count - 2
            let stripped = UnsafeMutablePointer<UInt8>.allocate(capacity: allocLen)
            let src = UnsafeBufferPointer(start: data + start, count: allocLen).span
            var strippedLen = 0
            if allocLen != 0 {
                var zeroRun = 0
                var readIdx = 0
                while true {
                    var byte = src[readIdx]
                    readIdx += 1
                    if zeroRun == 2, byte == 0x03 {
                        if readIdx == allocLen { break }
                        zeroRun = 0
                        byte = src[readIdx]
                        readIdx += 1
                    }
                    stripped[strippedLen] = byte
                    strippedLen += 1
                    if byte == 0 {
                        zeroRun += 1
                        if readIdx == allocLen { break }
                    } else {
                        if readIdx == allocLen { break }
                        zeroRun = 0
                    }
                }
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
            // ⚑ GAP (L7): Forward @0x101a6d170 first reads session.assetTrack.bitStreamFilter (+0x148) and, when
            //   set, runs its throwing static requirement (witness +8) on (data, size), then frees the filtered
            //   buffer after the decode call. BitStreamFilter declares no requirement here, so that step is absent.
            let sampleBuffer = try session.formatDescription.getSampleBuffer(data: data, size: Int(corePacket.size))
            var flagOut = VTDecodeInfoFlags(rawValue: 0)
            // THE HOIST IS FORWARD'S, NOT A COMPILE FIX. The closure below escapes, so nothing may
            // capture the raw pointer; the binary reads its packet fields ONCE, up front, and
            // spills them to the frame under construction before the decode call:
            //   101a6cf1c  ldp x12,x13,[x21,#0x8]   pts, dts     -> 101a6cf40  stp x13,x12,[sp,#0x38]
            //   101a6cf24  ldr w11,[x21,#0x28]      flags        -> 101a6cf3c  str w11,[sp,#0x24]
            //   101a6cf28  ldp x9,x10,[x21,#0x40]   duration,pos -> 101a6cf38  stp x10,x9,[sp,#0x28]
            // Forward @0x101a6d228: pts, else dts, else 0, rebased by the inlined
            // FFmpegAssetTrack.timestamp(for:) (timebase +0xc0 then startTime +0xa0).
            let timestamp = session.assetTrack.timestamp(for: corePacket.pts != Int64.min ? corePacket.pts : corePacket.dts != Int64.min ? corePacket.dts : 0)
            let packetFlags = corePacket.flags
            let duration = corePacket.duration
            let size = corePacket.size
            let position = corePacket.pos
            let isKeyFrame = packetFlags & AV_PKT_FLAG_KEY == AV_PKT_FLAG_KEY
            let status = VTDecompressionSessionDecodeFrame(session.decompressionSession, sampleBuffer: sampleBuffer, flags: flags, infoFlagsOut: &flagOut) { [weak self] status, infoFlags, imageBuffer, _, _ in
                guard let self, !infoFlags.contains(.frameDropped) else {
                    return
                }
                guard status == noErr else {
                    if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                        if isKeyFrame {
                            completionHandler(.failure(KSPlayerError(code: status, description: KSPlayerErrorCode.codecVideoReceiveFrame.rawValue)))
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
                let frame = VideoVTBFrame(pixelBuffer: imageBuffer, fps: session.assetTrack.nominalFrameRate, isKeyFrame: isKeyFrame, dovi: session.assetTrack.dovi, edrMetaData: nil, doviData: self.doviData, rpuBuffer: nil)
                frame.timebase = session.assetTrack.timebase
                if isKeyFrame, packetFlags & AV_PKT_FLAG_DISCARD != 0, self.maxTimestamp > 0 { // ⚑P3 lastPosition→maxTimestamp
                    self.startTime = self.maxTimestamp - timestamp // ⚑P3 lastPosition→maxTimestamp
                }
                self.maxTimestamp = max(self.maxTimestamp, timestamp) // ⚑P3 lastPosition→maxTimestamp
                frame.position = position
                frame.timestamp = self.startTime + timestamp
                frame.duration = duration
                frame.size = size
                self.maxTimestamp += frame.duration // ⚑P3 lastPosition→maxTimestamp
                completionHandler(.success(frame))
            }
            // Forward @0x101a6d3f0: no throw and no needReconfig here — log at .error (line 250), then
            // rebuild the session for the three VT failure codes (didSet invalidates the old one).
            if status != noErr {
                KSLog(level: .error, "[video] videoToolbox decode error \(status) isKeyFrame=\(isKeyFrame)", line: 250)
                if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                    if let session = DecompressionSession(assetTrack: session.assetTrack, options: options) {
                        self.session = session
                    }
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
        let storage = Unmanaged.passUnretained(self).toOpaque()
        storage.storeBytes(of: (Int64(0), Int64(0)), toByteOffset: 0x30, as: (Int64, Int64).self)
        storage.storeBytes(of: Int64(-1), toByteOffset: 0x40, as: Int64.self)
        VTDecompressionSessionFinishDelayedFrames(session.decompressionSession)
        VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
        frames = []
        let sessionStorage = storage.load(fromByteOffset: 0xcf8, as: UnsafeRawPointer.self)
        let trackStorage = sessionStorage.load(fromByteOffset: 0x20, as: UnsafeRawPointer.self)
        let codecParameters = trackStorage.load(fromByteOffset: 0xb8, as: UnsafeRawPointer.self)
        if codecParameters.load(fromByteOffset: 0x4, as: AVCodecID.self) == AV_CODEC_ID_H264 {
            storage.storeBytes(of: UInt8(1), toByteOffset: 0x48, as: UInt8.self)
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
    @used func decode() {
        let storage = Unmanaged.passUnretained(self).toOpaque()
        storage.storeBytes(of: (Int64(0), Int64(0)), toByteOffset: 0x30, as: (Int64, Int64).self)
        storage.storeBytes(of: Int64(-1), toByteOffset: 0x40, as: Int64.self)
    }
}

class DecompressionSession {
    fileprivate let formatDescription: CMFormatDescription
    fileprivate let decompressionSession: VTDecompressionSession
    fileprivate let assetTrack: FFmpegAssetTrack
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

// ⚑ Forward-added protocol (absent from KSPlayer source). Resolved from the FFmpegAssetTrack.bitStreamFilter
//   field-record symref → protocol descriptor 0x1039f0820 (kind=Protocol). Requirements deferred
//   (minimal no-conformer declare). The field is a 16-byte class-existential (init nil): the descriptor's
//   own class-constraint flag reads Any, so the class layout comes from the field-site `& AnyObject`,
//   not the protocol — kept faithful to the descriptor.
// ⚑[tool=name_type_at_addr ref=BitStreamFilter:0x1039f0820 result=protocol(kind=3,non-class-constrained)]
// ⚑ `public` is FORCED by type visibility: FFmpegAssetTrack.bitStreamFilter carries a
//   property descriptor (public-exclusive), and a public stored property's type must be
//   public. The protocol's own access is not separately observable.
// ⚑[tool=export_trie_oracle ref=FFmpegAssetTrack.bitStreamFilter:vpMV result=public ⇒ BitStreamFilter public by the type-visibility rule]
public protocol BitStreamFilter {}

// Nal3ToNal4BitStreamFilter @0x1039f0840 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_lower(inferred) (VideoToolboxDecode.swift..Anime4KPipeline.swift).
// ⚑[tool=type_surface ref=Nal3ToNal4BitStreamFilter:0x1039f0840 result=enum Nal3ToNal4BitStreamFilter: BitStreamFilter]
enum Nal3ToNal4BitStreamFilter: BitStreamFilter {}

// AnnexbToCCBitStreamFilter @0x1039f085c — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_lower(inferred) (VideoToolboxDecode.swift..Anime4KPipeline.swift).
// ⚑[tool=type_surface ref=AnnexbToCCBitStreamFilter:0x1039f085c result=enum AnnexbToCCBitStreamFilter: BitStreamFilter]
enum AnnexbToCCBitStreamFilter: BitStreamFilter {}
