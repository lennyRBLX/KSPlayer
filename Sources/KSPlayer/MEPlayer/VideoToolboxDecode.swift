//
//  VideoToolboxDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/10.
//

import FFmpegKit
import Libavformat
import DOVIRPUShim
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    // MARK: - Fields (RE: VideoToolboxDecode, 11 fields per types.json)
    // The binary type-dump order is: maxFrameCount, codecID, options, startTime,
    // maxTimestamp, lastTimestamp, needReconfig, doviData, doviContext, frames,
    // session. The declaration order below keeps the existing readable grouping;
    // all 11 fields are present.

    /// VTB session wrapper. Invalidates the prior session on replacement.
    private var session: DecompressionSession

    /// Player configuration reference.
    private let options: KSOptions

    /// Decoder codec id, cached for VTB pixel-format / format-change decisions.
    /// RE: `codecID: AVCodecID` field on `VideoToolboxDecode` (types.json).
    private let codecID: AVCodecID

    /// Sync offset applied when packets are discarded after a seek.
    private var startTime = Int64(0)

    /// Largest PTS observed so far (reorder-buffer ordering anchor).
    private var maxTimestamp = Int64(0)

    /// Running monotonic timestamp tracker (was `lastPosition` in the
    /// earlier source revision; renamed to match the binary's
    /// `lastTimestamp` field at +0x28 of the class layout).
    private var lastTimestamp = Int64(0)

    /// Set when the session must be recreated on the next decode.
    private var needReconfig = false

    /// Dolby Vision metadata extracted from `CMSampleBuffer` attachments on the
    /// VTB DV path. RE: `doviData: KSDOVIMetadata?` (types.json); the
    /// reconstruction models the binary's `__C.KSDOVIMetadata` as the Swift
    /// `DOVIFrameMetadata` carrier (see Model.swift), matching `FFmpegDecode`.
    private var doviData: DOVIFrameMetadata?

    /// C `DOVIContext` decode-state for the VTB Dolby-Vision path. RE: the
    /// binary stores the FFmpeg `__C.DOVIContext` parser state at `self+0xC10`.
    /// Allocated via `ks_dovi_ctx_alloc()` (wraps `ff_dovi_ctx_alloc`),
    /// freed in `shutdown()`. Used by `extractDoviRPU` to parse raw RPU
    /// NALUs into full `AVDOVIMetadata` (header + mapping + color).
    private var doviContext: OpaquePointer? // DOVIContext*

    /// Frame reorder buffer. VTB outputs in decode order; we sort to PTS.
    /// Binary uses `DecompressionSession_introsortFrames @ 0x101452620` /
    /// `_introsortPartition @ 0x101452cf4`. Source uses an insertion sort
    /// over the small reorder window; for typical N (4-120 frames) the two
    /// behave identically.
    private var frames: [VideoVTBFrame] = []

    /// Reorder capacity: `max(4, 2 * fps)`.
    private var maxFrameCount: Int = 8

    /// 3008-byte DV metadata staging area. RE: binary stores parsed DV RPU
    /// data at `self+0x50` (0xBC0 bytes) via memmove/memcpy during Phase 2
    /// of `decodeAndProcessPacket`.
    private var dvMetadataStaging = Data(count: 3008)

    init(options: KSOptions, session: DecompressionSession) {
        self.options = options
        self.session = session
        codecID = session.assetTrack.codecpar.codec_id
        let fps = session.assetTrack.nominalFrameRate
        if fps > 0 {
            maxFrameCount = max(4, Int(fps) * 2)
        }
        // RE: Binary allocates DOVIContext at construction time when the
        // track carries Dolby Vision metadata. The context persists for
        // the lifetime of the decoder and accumulates RPU parse state.
        if session.assetTrack.dovi != nil {
            doviContext = OpaquePointer(ks_dovi_ctx_alloc())
        }
    }

    /// RE: 0x101450044 (VideoToolboxDecode_decodeAndProcessPacket, v1.3.15)
    /// Per-packet VTB decode entry (2160 B). Four phases:
    /// Phase 1: needReconfig session rebuild
    /// Phase 2: NALU parsing + DV RPU extraction
    /// Phase 3: VTB decode submission via VTDecompressionSessionDecodeFrameWithOutputHandler
    /// Phase 4: Error handling + immediate session rebuild on recoverable VTB error
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        // ── Phase 1: needReconfig session rebuild ──
        // RE: Binary at 0x1014500cc — if needReconfig, rebuild session, zero counters,
        // set sentinel timestamp. Does NOT call doFlushCodec() (binary only zeroes
        // frame counters and sets sentinel timestamp).
        if needReconfig {
            if let newSession = DecompressionSession(assetTrack: session.assetTrack, options: options) {
                let oldSession = session
                session = newSession
                oldSession.invalidate()
            }
            // RE: Binary zeroes field_0x28, field_0x30, sets field_0x38 = -1
            lastTimestamp = 0
            maxTimestamp = 0
            startTime = -1
            needReconfig = false
        }
        guard let corePacket = packet.corePacket?.pointee, let data = corePacket.data else {
            return
        }
        let packetSize = Int(corePacket.size)

        // ── Phase 2: NALU parsing + DV RPU extraction ──
        // RE: Binary parses NAL units with emulation-prevention-byte removal
        // via FUN_1013efd48 (start-code len 3) / FUN_1013f03e0 (generic),
        // then for each DV RPU NALU (type 0x3E / unspec62 in HEVC):
        //   - strips emulation prevention bytes (0x00,0x00,0x03 -> 0x00,0x00)
        //   - calls ff_dovi_rpu_parse on the doviContext
        //   - extracts DV header via dovi_rpu_get_header (FUN_102402568)
        //   - serializes DV metadata via FUN_10150c0a4
        //   - copies 3008-byte result into self+0x50 (dvMetadataStaging)
        if packetSize > 0, session.assetTrack.dovi != nil {
            extractDoviRPU(data: data, size: packetSize)
        }

        do {
            // RE: NAL-prefix conversion is routed through the track's
            // `bitStreamFilter` metatype; `Nal3ToNal4BitStreamFilter`
            // indicates the AVCC stream uses 3-byte NAL length prefixes
            // that must be promoted to 4 bytes before VTB submission.
            let needsConversion = session.assetTrack.needsNALSizeConversion

            // ── Phase 3: VTB decode submission ──
            // RE: Binary dispatches format-description observer at session.assetTrack+0x148/+0x150
            // before submission, then calls VideoToolboxDecode_getFrameFormat.
            let sampleBuffer: CMSampleBuffer
            if needsConversion {
                // RE: NAL 3→4 byte promotion goes through the CMFormatDescription
                // extension path which rewrites NAL length prefixes via AVIOContext.
                sampleBuffer = try session.formatDescription.getSampleBuffer(
                    isConvertNALSize: true, data: data, size: packetSize)
            } else {
                // RE: 0x1013ef38c — binary's getFrameFormat wraps raw packet data
                // into a CMSampleBuffer via CMBlockBufferCreateWithMemoryBlock +
                // CMSampleBufferCreateReady using the session's formatDescription.
                sampleBuffer = try getFrameFormat(
                    data: data, size: packetSize,
                    formatDescription: session.formatDescription)
            }

            // RE: Binary uses VTDecompressionSessionDecodeFrameWithOutputHandler
            // (not VTDecompressionSessionDecodeFrame with inline closure).
            // The block wraps DecompressionSession_decodeCallbackThunk @ 0x101451cd8.
            let flags: VTDecodeFrameFlags = [
                ._EnableAsynchronousDecompression,
            ]
            var flagOut = VTDecodeInfoFlags.frameDropped
            let timestamp = packet.timestamp
            let packetFlags = corePacket.flags
            let duration = corePacket.duration
            let size = corePacket.size
            let isDovi = session.assetTrack.dovi != nil
            let fps = session.assetTrack.nominalFrameRate
            let timebase = session.assetTrack.timebase
            let stagedDoviData = doviData

            // RE: 0x1014508b4 (DecompressionSession_outputHandler, v1.3.15, 5156 B)
            // VTB decode-output handler. Receives decoded CVImageBuffer from VTB callback,
            // checks DV tag polarity (+0x13A), reads KSOptions.display + DV display model
            // via classifyDynamicRange, calls VideoVTBFrame_init (sole caller), copies
            // 3008-byte DV staging buffer, sorts reorder buffer, drains frames whose PTS
            // distance exceeds 1.5 * frameDuration.
            let status = VTDecompressionSessionDecodeFrame(
                session.decompressionSession,
                sampleBuffer: sampleBuffer,
                flags: flags,
                infoFlagsOut: &flagOut
            ) { [weak self] status, infoFlags, imageBuffer, _, _ in
                guard let self, !infoFlags.contains(.frameDropped) else {
                    return
                }
                guard status == noErr else {
                    // RE: 0x1014508b4 recoverable-error bitmask:
                    // (status+12911)<=8 && ((1<<(status+12911))&0x105)!=0
                    // Matches kVTInvalidSessionErr, kVTVideoDecoderMalfunctionErr,
                    // kVTVideoDecoderBadDataErr
                    if Self.isRecoverableVTBError(status) {
                        // RE: v1.3.15 binary sets needReconfig on recoverable
                        // error in the output handler path
                        if packet.isKeyFrame {
                            completionHandler(.failure(NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)))
                        } else {
                            self.needReconfig = true
                        }
                    }
                    return
                }

                // RE: DV tag polarity check at +0x13A — the binary reads the
                // DOVIDecoderConfigurationRecord discriminator to determine if
                // the track carries Dolby Vision enhancement layer data.
                let hasDoviData = isDovi && stagedDoviData != nil

                let frame: VideoVTBFrame
                if let imageBuffer = imageBuffer as PixelBufferProtocol? {
                    frame = VideoVTBFrame(
                        fps: fps,
                        isDovi: isDovi,
                        pixelBuffer: imageBuffer
                    )
                } else {
                    frame = VideoVTBFrame(
                        fps: fps,
                        isDovi: isDovi
                    )
                }

                // Copy staged DV metadata into the frame if present
                // RE: Binary copies 3008-byte DV staging buffer (memmove 0xBC0)
                // from self+0x50 into the VideoVTBFrame
                if hasDoviData {
                    frame.doviData = stagedDoviData
                }

                frame.timebase = timebase
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

                // RE: v1.3.15 reorder buffer — insertion sort by PTS
                // (VideoToolboxDecode_sortFramesByPTS @ 0x10144fa74, dispatches to
                // DecompressionSession_introsortFrames @ 0x101452620)
                self.insertSorted(frame: frame)

                // RE: Binary drains frames whose PTS distance exceeds
                // 1.5 * frameDuration, rather than draining only when
                // count >= maxFrameCount. This allows for tighter latency
                // on streams with variable frame counts.
                let frameDuration = fps > 0 ? Int64(Double(timebase.den) / (Double(fps) * Double(timebase.num))) : 0
                self.drainReadyFrames(frameDuration: frameDuration, completionHandler: completionHandler)
            }

            // ── Phase 4: Error handling + recovery ──
            // RE: Binary Phase 4 pseudocode (L735-759): on noErr, return;
            // otherwise log + bitmask check + immediate rebuild. The binary
            // has ONE recovery branch here (immediate rebuild via
            // rebuildSession). The deferred needReconfig path is handled
            // separately in the output handler callback (Phase 3 closure),
            // not in Phase 4.
            if status == noErr {
                if !flags.contains(._EnableAsynchronousDecompression) {
                    VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
                }
            } else {
                // RE: Recoverable-error bitmask check at binary 0x101450044 Phase 4:
                // (status + 0x326F) <= 8 && ((1 << (status + 0x326F)) & 0x105) != 0
                if Self.isRecoverableVTBError(status) {
                    // RE: Binary immediately rebuilds the session on recoverable error
                    // (CALL at 0x1014507c0), rather than just setting needReconfig
                    rebuildSession()
                }
            }
        } catch {
            completionHandler(.failure(error))
        }
    }

    func doFlushCodec() {
        // RE: On flush, emit all cached frames in PTS order then clear
        session.flushAndReset()
        frames.removeAll()
        lastTimestamp = 0
        maxTimestamp = 0
        startTime = 0
        // RE: Binary flushes DOVIContext parser state on seek to prevent
        // stale RPU data from a previous segment carrying over
        if let ctx = doviContext {
            ks_dovi_ctx_flush(UnsafeMutableRawPointer(ctx).assumingMemoryBound(to: DOVIContext.self))
        }
        doviData = nil
    }

    func shutdown() {
        frames.removeAll()
        session.invalidate()
        // RE: Binary frees DOVIContext on decoder teardown
        if let ctx = doviContext {
            ks_dovi_ctx_free(UnsafeMutableRawPointer(ctx).assumingMemoryBound(to: DOVIContext.self))
            doviContext = nil
        }
    }

    func decode() {
        frames.removeAll()
        lastTimestamp = 0
        maxTimestamp = 0
        startTime = 0
    }

    // MARK: - Private Helpers

    /// RE: 0x1013ef38c (VideoToolboxDecode_getFrameFormat, v1.3.15)
    /// Creates a CMSampleBuffer from raw packet data using the session's
    /// format description. Called within decodeAndProcessPacket Phase 3
    /// before VTB decode submission. Binary calls
    /// CMBlockBufferCreateWithMemoryBlock to wrap the data, then
    /// CMSampleBufferCreateReady to produce the sample buffer. Throws on
    /// allocation failure.
    ///
    /// Ghidra decompile: takes (data, size) + formatDescription (via x20),
    /// returns CMSampleBuffer or throws. The reversal doc names this
    /// "Resolves frame format descriptor" but the binary body is a
    /// straightforward CMSampleBuffer factory.
    private func getFrameFormat(data: UnsafeMutablePointer<UInt8>, size: Int,
                                formatDescription: CMFormatDescription) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        // RE: Binary calls CMBlockBufferCreateWithMemoryBlock with
        // kCFAllocatorDefault (structure), kCFAllocatorNull (block),
        // zero offset, flags=0.
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data,
            blockLength: size,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        }
        var sampleBuffer: CMSampleBuffer?
        // RE: Binary calls CMSampleBufferCreateReady (not CMSampleBufferCreate)
        // with numSamples=1, zero timing/size entries.
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else {
            throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        }
        return sampleBuffer
    }

    /// RE: 0x1013ef4dc (VideoToolboxDecode_mapPixelFormat, v1.3.15)
    /// Maps codec pixel formats to CoreVideo pixel format types. Used during
    /// VTB session creation and format changes to select the appropriate
    /// CVPixelBuffer format for the decompression session.
    static func mapPixelFormat(codecID: AVCodecID, codecpar: AVCodecParameters) -> OSType? {
        let format = AVPixelFormat(codecpar.format)
        return format.osType(fullRange: false)
    }

    /// RE: v1.3.15 DV RPU extraction from NALU stream (Phase 2 of
    /// decodeAndProcessPacket @ 0x101450044).
    ///
    /// Multi-step binary chain (TrackDecode.md L704-714):
    ///   Step 1: Walk AVCC NALUs, identify DV RPU (HEVC type 62 / unspec62)
    ///   Step 2: Emulation-prevention-byte removal (0x00,0x00,0x03 -> 0x00,0x00)
    ///   Step 3: ff_dovi_rpu_parse(doviContext, buf, outPos, 0)
    ///   Step 4: dovi_rpu_get_header(doviContext) -> AVDOVIMetadata*
    ///   Step 5: dovi_metadata_serialize -> 3008-byte memcpy to self+0x50
    ///
    /// The binary separates these into distinct function calls for lifecycle
    /// and error handling. This reconstruction preserves the multi-step
    /// structure via the DOVIRPUShim C bridge.
    private func extractDoviRPU(data: UnsafeMutablePointer<UInt8>, size: Int) {
        // RE: Binary only parses DV RPU for HEVC streams (unspec62 is HEVC-only)
        guard codecID == AV_CODEC_ID_HEVC else { return }

        var offset = 0
        while offset + 4 < size {
            // Step 1: Read 4-byte big-endian NAL length (AVCC format)
            let nalLen = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            offset += 4

            guard nalLen > 0, offset + nalLen <= size else { break }

            // HEVC NAL type is bits 1-6 of the first byte: (byte >> 1) & 0x3F
            let nalType = (data[offset] >> 1) & 0x3F

            // unspec62 = 62 = DV RPU NALU
            if nalType == 62 {
                let rpuStart = offset + 2 // skip NAL header (2 bytes for HEVC)
                let rpuLen = nalLen - 2
                guard rpuLen > 0 else {
                    offset += nalLen
                    continue
                }

                // Step 2: Emulation-prevention-byte removal
                // RE: Binary at FUN_1013efd48 / FUN_1013f03e0
                // Scan for 0x00,0x00,0x03 -> drop the 0x03 byte
                var stripped = Data(capacity: rpuLen)
                var zeroRun = 0
                for i in 0 ..< rpuLen {
                    let byte = data[rpuStart + i]
                    if zeroRun == 2, byte == 0x03 {
                        zeroRun = 0
                        continue // remove EPB
                    }
                    stripped.append(byte)
                    zeroRun = (byte == 0) ? zeroRun + 1 : 0
                }

                // Step 3: Parse RPU through DOVIContext via ff_dovi_rpu_parse
                // RE: Binary calls ff_dovi_rpu_parse(self.doviContext, buf, outPos, 0)
                // This is a SEPARATE call from the metadata extraction (step 4).
                guard let ctx = doviContext else {
                    // Fallback: store raw RPU without parsed metadata
                    doviData = DOVIFrameMetadata(rpuData: stripped, header: nil, mapping: nil, color: nil)
                    offset += nalLen
                    continue
                }

                let ctxPtr = UnsafeMutableRawPointer(ctx).assumingMemoryBound(to: DOVIContext.self)
                let parseResult: Int32 = stripped.withUnsafeBytes { rawBuf in
                    guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return Int32(-1)
                    }
                    return ks_dovi_rpu_parse(ctxPtr, ptr, stripped.count)
                }

                // Step 4: Extract AVDOVIMetadata from the context
                // RE: FUN_102402568 (dovi_rpu_get_header) -- SEPARATE call after parse
                let parsedMetadata: UnsafePointer<AVDOVIMetadata>? = (parseResult >= 0)
                    ? ks_dovi_get_metadata(ctxPtr)
                    : nil

                if let metadata = parsedMetadata {
                    // Step 5: Copy serialized metadata to staging buffer
                    // RE: Binary does memmove(tempBuf, serialized, 0xBC0) then
                    // memcpy(self+0x50, tempBuf, 0xBC0). The 3008-byte staging
                    // buffer holds the full serialized DV metadata.
                    let metadataSize = min(MemoryLayout<AVDOVIMetadata>.size, dvMetadataStaging.count)
                    dvMetadataStaging.withUnsafeMutableBytes { dest in
                        if let baseAddress = dest.baseAddress {
                            memcpy(baseAddress, metadata, metadataSize)
                        }
                    }

                    // Extract header, mapping, and color sub-structures via
                    // the public av_dovi_get_* accessors (same pattern as
                    // FFmpegDecode's AV_FRAME_DATA_DOVI_METADATA handler).
                    // RE: Binary extracts these via FUN_102402568 (dovi_rpu_get_header)
                    // and the serialized metadata structure's sub-field offsets.
                    doviData = DOVIFrameMetadata(
                        rpuData: stripped,
                        header: av_dovi_get_header(metadata),
                        mapping: av_dovi_get_mapping(metadata),
                        color: av_dovi_get_color(metadata)
                    )
                } else {
                    // Parse failed -- store raw RPU as fallback
                    doviData = DOVIFrameMetadata(rpuData: stripped, header: nil, mapping: nil, color: nil)
                }
            }

            offset += nalLen
        }
    }

    /// RE: v1.3.15 recoverable-error bitmask check.
    /// Binary formula: `(status + 12911) <= 8 && ((1 << (status + 12911)) & 0x105) != 0`
    /// Matches: kVTInvalidSessionErr (-12911), kVTVideoDecoderMalfunctionErr (-12909),
    ///          kVTVideoDecoderBadDataErr (-12909)
    static func isRecoverableVTBError(_ status: OSStatus) -> Bool {
        let shifted = Int(status) + 12911
        guard shifted >= 0, shifted <= 8 else { return false }
        return ((1 << shifted) & 0x105) != 0
    }

    /// RE: Immediate in-call session rebuild (error-recovery, CALL at 0x1014507c0).
    /// Rebuilds the VTB session within the same decodeAndProcessPacket invocation.
    /// Binary invalidates existing session, allocates new one, zeroes state fields.
    private func rebuildSession() {
        if let newSession = DecompressionSession(assetTrack: session.assetTrack, options: options) {
            let oldSession = session
            session = newSession
            oldSession.invalidate()
        }
        // RE: Binary zeroes field_0x28, field_0x30, sets field_0x38 = -1
        lastTimestamp = 0
        maxTimestamp = 0
        startTime = -1
    }

    /// RE: 0x10144fa74 (VideoToolboxDecode_sortFramesByPTS, v1.3.15) reorder-buffer
    /// sort entry, dispatches to DecompressionSession_introsortFrames @ 0x101452620.
    /// Source uses insertion sort over the small reorder window; for typical
    /// N (4-120 frames) this is equivalent to the binary's introsort.
    private func insertSorted(frame: VideoVTBFrame) {
        var insertIndex = frames.count
        while insertIndex > 0 && frames[insertIndex - 1].timestamp > frame.timestamp {
            insertIndex -= 1
        }
        frames.insert(frame, at: insertIndex)
    }

    /// RE: 0x1014508b4 drain logic — drains frames whose PTS distance from
    /// the newest frame exceeds 1.5 * frameDuration, rather than only
    /// draining when count >= maxFrameCount.
    private func drainReadyFrames(frameDuration: Int64, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        guard !frames.isEmpty else { return }

        if frameDuration > 0 {
            // RE: Binary drains frames whose PTS distance exceeds 1.5 * frameDuration
            let threshold = frameDuration + frameDuration / 2 // 1.5x
            let newestPTS = frames.last!.timestamp
            while let oldest = frames.first,
                  newestPTS - oldest.timestamp >= threshold || frames.count >= maxFrameCount {
                let emitted = frames.removeFirst()
                completionHandler(.success(emitted))
                if frames.isEmpty { break }
            }
        } else {
            // Fallback: drain when buffer is full (same as maxFrameCount check)
            while frames.count >= maxFrameCount {
                let emitted = frames.removeFirst()
                completionHandler(.success(emitted))
            }
        }
    }
}

class DecompressionSession {
    // MARK: - Fields (RE: DecompressionSession, 3 fields per types.json)
    /// #1 @ +0x10 -- Video format description sourced from `track + 0xD0`.
    fileprivate private(set) var formatDescription: CMFormatDescription
    /// #2 @ +0x18 -- Active Apple VTB session.
    fileprivate private(set) var decompressionSession: VTDecompressionSession
    /// #3 @ +0x20 -- Source track.
    fileprivate var assetTrack: FFmpegAssetTrack

    /// RE: 0x101451eb4 (DecompressionSession.init(assetTrack:options:), v1.3.15)
    /// Allocates the VT session. Copies track+0xD0 -> self+0x10, stores VT session
    /// at +0x18, track at +0x20. Configured for use with
    /// VTDecompressionSessionDecodeFrameWithOutputHandler.
    init?(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.assetTrack = assetTrack
        guard let pixelFormatType = assetTrack.pixelFormatType, let formatDescription = assetTrack.formatDescription else {
            return nil
        }
        self.formatDescription = formatDescription
        #if os(macOS)
        // macOS requires explicit registration of professional video workflow decoders
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
        if #available(macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(formatDescription.mediaSubType.rawValue)
        }
        #endif
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
        // RE: Binary configures deinterlacing when track.fieldOrder has low bit set
        if assetTrack.fieldOrder.rawValue & 1 != 0 {
            // Check if the session supports field-mode deinterlacing
            var supported: CFDictionary?
            if VTSessionCopySupportedPropertyDictionary(decompressionSession, supportedPropertyDictionaryOut: &supported) == noErr,
               let supportedDict = supported as NSDictionary? {
                if supportedDict[kVTDecompressionPropertyKey_FieldMode] != nil {
                    VTSessionSetProperty(decompressionSession,
                                         key: kVTDecompressionPropertyKey_FieldMode,
                                         value: kVTDecompressionProperty_FieldMode_DeinterlaceFields as CFString)
                    if supportedDict[kVTDecompressionPropertyKey_DeinterlaceMode] != nil {
                        VTSessionSetProperty(decompressionSession,
                                             key: kVTDecompressionPropertyKey_DeinterlaceMode,
                                             value: kVTDecompressionProperty_DeinterlaceMode_Temporal as CFString)
                    }
                }
            }
        }
        self.decompressionSession = decompressionSession
    }

    /// RE: 0x101451d88 / 0x101451eac (DecompressionSession_flushAndReset, v1.3.15)
    /// Flush + state reset as a DecompressionSession method.
    /// Handles VTDecompressionSessionFinishDelayedFrames and session-level state reset.
    fileprivate func flushAndReset() {
        VTDecompressionSessionFinishDelayedFrames(decompressionSession)
        VTDecompressionSessionWaitForAsynchronousFrames(decompressionSession)
    }

    /// RE: 0x101451dec / 0x101451eb0 (DecompressionSession_invalidate, v1.3.15)
    /// Tear down VTDecompressionSession as a DecompressionSession method.
    /// Structured teardown: finish delayed frames, wait for async completion,
    /// then invalidate the session.
    fileprivate func invalidate() {
        VTDecompressionSessionFinishDelayedFrames(decompressionSession)
        VTDecompressionSessionWaitForAsynchronousFrames(decompressionSession)
        VTDecompressionSessionInvalidate(decompressionSession)
    }

    /// RE: 0x101453330 (DecompressionSession_handleFormatChange_impl, v1.3.15)
    /// Format-change handler for DecompressionSession. Called when the stream
    /// format description changes mid-stream (e.g., resolution change),
    /// requiring VTB session teardown and recreation with new parameters.
    fileprivate func handleFormatChange(newFormat: CMFormatDescription, options: KSOptions) {
        // If the format description matches, no action needed
        guard !CMFormatDescriptionEqual(formatDescription, otherFormatDescription: newFormat) else {
            return
        }

        // Flush pending frames before teardown
        flushAndReset()

        // Invalidate old session
        VTDecompressionSessionInvalidate(decompressionSession)

        // Update format description
        formatDescription = newFormat

        // Rebuild session with new parameters
        guard let pixelFormatType = assetTrack.pixelFormatType else { return }

        let attributes: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: assetTrack.codecpar.width,
            kCVPixelBufferHeightKey: assetTrack.codecpar.height,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ]

        var session: VTDecompressionSession?
        // swiftlint:disable line_length
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: newFormat, decoderSpecification: CMFormatDescriptionGetExtensions(newFormat), imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session)
        // swiftlint:enable line_length

        guard status == noErr, let newSession = session else { return }

        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata,
                                 value: kCFBooleanTrue)
        }
        if let destinationDynamicRange = options.availableDynamicRange(nil) {
            let pixelTransferProperties = [kVTPixelTransferPropertyKey_DestinationColorPrimaries: destinationDynamicRange.colorPrimaries,
                                           kVTPixelTransferPropertyKey_DestinationTransferFunction: destinationDynamicRange.transferFunction,
                                           kVTPixelTransferPropertyKey_DestinationYCbCrMatrix: destinationDynamicRange.yCbCrMatrix]
            VTSessionSetProperty(newSession,
                                 key: kVTDecompressionPropertyKey_PixelTransferProperties,
                                 value: pixelTransferProperties as CFDictionary)
        }

        decompressionSession = newSession
    }

    /// RE: 0x1014531b8 (DecompressionSession_copyObjCArray, v1.3.15)
    /// Copies ObjC NSArray of attachments from CVImageBuffer. Used by the output
    /// handler to extract CMSampleBuffer attachments (including DV metadata)
    /// from decoded frames.
    fileprivate static func copyAttachments(from imageBuffer: CVImageBuffer) -> CFDictionary? {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            return CVBufferCopyAttachments(imageBuffer, .shouldPropagate)
        } else {
            return CVBufferGetAttachments(imageBuffer, .shouldPropagate)
        }
    }

    /// RE: 0x101453638 (DecompressionSession_parseAVCCNALUs, v1.3.15)
    /// Parse AVCC NALU records with 3-byte big-endian length prefix walker.
    /// `len = data[0]<<16 | data[1]<<8 | data[2]`
    /// Used by the VTB decode path to walk 3-byte-length AVCC bitstreams.
    fileprivate static func parseAVCCNALUs(data: UnsafePointer<UInt8>, size: Int, nalLengthSize: Int = 3) -> [(offset: Int, length: Int)] {
        var result: [(offset: Int, length: Int)] = []
        var pos = 0

        while pos + nalLengthSize <= size {
            var nalLen = 0
            if nalLengthSize == 3 {
                // RE: 3-byte big-endian length prefix (0x101453638)
                nalLen = Int(data[pos]) << 16
                    | Int(data[pos + 1]) << 8
                    | Int(data[pos + 2])
            } else {
                // 4-byte big-endian length prefix (standard AVCC)
                nalLen = Int(data[pos]) << 24
                    | Int(data[pos + 1]) << 16
                    | Int(data[pos + 2]) << 8
                    | Int(data[pos + 3])
            }
            pos += nalLengthSize
            guard nalLen > 0, pos + nalLen <= size else { break }
            result.append((offset: pos, length: nalLen))
            pos += nalLen
        }

        return result
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
