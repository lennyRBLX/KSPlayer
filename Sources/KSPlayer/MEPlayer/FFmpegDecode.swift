//
//  FFmpegDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import Foundation
import Libavcodec

class FFmpegDecode: DecodeProtocol {
    private let options: KSOptions
    private var coreFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var bestEffortTimestamp: Int64 = 0
    private let frameChange: FrameChange
    private let filter: MEFilter
    private var hasDecodeSuccess: Bool = false
    private let isVideo: Bool
    private let assetTrack: FFmpegAssetTrack
    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.options = options
        self.assetTrack = assetTrack
        isVideo = assetTrack.mediaType == .video
        do {
            codecContext = try assetTrack.createContext(options: options)
        } catch {
            KSLog(error as CustomStringConvertible)
        }
        codecContext?.pointee.time_base = assetTrack.timebase.rational
        filter = MEFilter(timebase: assetTrack.timebase, isAudio: assetTrack.mediaType == .audio, nominalFrameRate: assetTrack.nominalFrameRate, options: options)
        if assetTrack.mediaType == .video {
            frameChange = VideoSwresample(fps: assetTrack.nominalFrameRate, isDovi: assetTrack.dovi != nil)
        } else {
            frameChange = AudioSwresample(audioDescriptor: assetTrack.audioDescriptor!)
        }
    }

    // ⚠️ D1 CLOSED — the parameter is `UnsafeMutablePointer<AVPacket>`. Read over the whole extent
    // 0x101a2220c-0x101a22ca0 (677 instr, one exported symbol, no ICF fold): the parameter lives
    // in x24 and NEVER reaches an ARC helper (`mov x0, x24` does not occur anywhere), `[x24]` —
    // the isa word — is never read, and the ONLY offset dereferenced out of it is 0x28, read
    // three times and each time masked as a bit-field:
    //   101a222b8  ldr  w8,[x24,#0x28]  /  101a222c4  and  w1, w8, #0x1     AV_PKT_FLAG_KEY
    //   101a224b0  ldr  w8,[x24,#0x28]  /  101a224b4  tst  w8, #0x1         AV_PKT_FLAG_KEY
    //   101a22910  ldrb w8,[x24,#0x28]  /  101a22914  tbnz w8, #0x2         AV_PKT_FLAG_DISCARD
    // `Packet.size` also sits at 0x28, so the offset alone does NOT decide it — the flag masks
    // and the total absence of ARC traffic are what do. `Packet.assetTrack` is at 0x40 and is
    // never read out of the parameter at all.
    // ⚑[tool=field_offset_vector ref=FFmpegDecode:0x1039ef150 result=isVideo-0x61-assetTrack-0x68]
    // NOTE: `recover_field_offsets --module KSPlayer --class FFmpegDecode` recovers ZERO offsets
    // for this class — `field_offset_vector.py` is the tool that answers here (metadata
    // 0x1044e9418, FieldOffsetVectorOffset=10 words, InstanceSize 0x70).
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        // DEFERRED → DV-render/HDR-pixelBuffer phase (COUPLED unit): Forward moved this inline side-data loop (L71-142)
        // into VideoSwresample.s32 (0x101a67274; sole caller = this method @decompile-L182). s32 writes VideoSwresample's
        // DV/HDR fields that change s28 CONSUMES → frame, so loop-removal + s32 + change + transfer reconstruct as ONE unit
        // (landing s32 + removing this loop without change REGRESSES the edrMetaData path — change s28 grep-confirmed reads
        // +0x60/+0xc20../+0xc50/+0xc60). Gated on the protocol-witness verifier. Cached: FFmpegDecode_slot13/slot18.
        // The parameter is handed to the send call UNCHANGED — no field is loaded out of it first.
        // Four call sites, three passing it straight through and one draining with NULL:
        //   101a22254  mov x1, x24 / bl 0x102a1a424      (arg0 = self.codecContext @0x20)
        //   101a22614  mov x1, x24 / bl 0x102a1a424      (after codecContext re-create)
        //   101a22840  mov x1, #0x0 / bl 0x102a1a424     (the DRAIN call)
        //   101a228cc  mov x1, x24 / bl 0x102a1a424
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_send_packet:0x102a1a424 result=REFUTED]
        // ⚠️ THE ORACLE REFUTES THIS ONE, AND THE MARKER SAYS SO RATHER THAN ROUNDING UP. The sole
        // divergence from the reference build is a struct-offset immediate at instruction 11
        // (`ldr w8,[x21,#0x154]` against the stock `#0xa4`) — the known non-stock AVCodecContext
        // ABI — while all ten sibling candidates in the same fingerprint class diverge at index 0
        // or 3, and `--resolve` finds no instruction-for-instruction survivor at all. So the
        // identity rests on the ABI argument plus the company it keeps, NOT on the oracle.
        // Its three neighbours in this body ARE confirmed instruction-for-instruction:
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_receive_frame:0x10294dba0 result=CONFIRMED]
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_flush_buffers:0x10294d260 result=CONFIRMED]
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
        guard let codecContext, avcodec_send_packet(codecContext, packet) == 0 else {
            return
        }
        // 需要avcodec_send_packet之后，properties的值才会变成FF_CODEC_PROPERTY_CLOSED_CAPTIONS
        // ⚠️ D2 CLOSED, and it is forced by D1 — with a raw pointer there is no `packet.assetTrack`
        // to ask. The binary asks SELF, and it asks a precomputed Bool rather than re-deriving the
        // mediaType: `ldrb w28,[x19,#0x61]` / `cmp w28,#0x1` / `b.ne` at 0x101a2261c, and again at
        // 0x101a22264 gating the send-failure path. Offset 0x61 is `isVideo` (field 7) and 0x68 is
        // `assetTrack` (field 8); this class sets both in `init` (:21-25), which is where the
        // `assetTrack.mediaType == .video` test actually lives in Forward.
        if isVideo {
            // ⚑ Forward retyped FFmpegAssetTrack.codecpar value→pointer, so the synthetic CC codecpar is
            //   heap-allocated (stable pointer the track stores) — the alloc folds into the compound `if`
            //   to match the binary (FUN_101a23404 L33-38: alloc-fail skips the block, not a return).
            //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_alloc:0x1029f543c result=CONFIRMED]
            //   ⚑ ownership/free deferred to the FFmpegAssetTrack lifecycle audit (the alloc'd params are now owned by the track; the base value-copy had no free step).
            if Int32(codecContext.pointee.properties) & FF_CODEC_PROPERTY_CLOSED_CAPTIONS != 0,
               assetTrack.closedCaptionsTrack == nil,
               let codecpar = avcodec_parameters_alloc() {
                codecpar.pointee.codec_type = AVMEDIA_TYPE_SUBTITLE
                codecpar.pointee.codec_id = AV_CODEC_ID_EIA_608
                if let subtitleAssetTrack = FFmpegAssetTrack(codecpar: codecpar) {
                    subtitleAssetTrack.name = "Closed Captions"
                    subtitleAssetTrack.startTime = assetTrack.startTime
                    subtitleAssetTrack.timebase = assetTrack.timebase
                    // ⚑[tool=export_trie_oracle ref=FUN_101a23404:0x101a23404 result=NOT_IN_TRIE — enclosing function
                    //   unnamed (a real negative, not a lookup failure); identified by its own body, below]
                    // Call @0x101a235a0 (thunk 0x101a3340c) inside that function: `w1 = 0x80` @0x101a23594 and
                    // `w3 = 1` @0x101a2359c, both binary-read — so frameCapacity is 128 here, not the 255 source
                    // carried. Site identified by its own body: `str d0,[x0]` @0x101a23480 writes the
                    // codec_type/codec_id pair, swift_allocObject(351) @0x101a23498 is the FFmpegAssetTrack, and
                    // the result is stored to +0x100 (`subtitle`) @0x101a235ac.
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                    subtitleAssetTrack.subtitle = subtitle
                    assetTrack.closedCaptionsTrack = subtitleAssetTrack
                    subtitle.decode()
                }
            }
        }
        while true {
            let result = avcodec_receive_frame(codecContext, coreFrame)
            if result == 0, let inputFrame = coreFrame {
                var displayData: MasteringDisplayMetadata?
                var contentData: ContentLightMetadata?
                var ambientViewingEnvironment: AmbientViewingEnvironment?
                // filter之后，side_data信息会丢失，所以放在这里
                if inputFrame.pointee.nb_side_data > 0 {
                    for i in 0 ..< inputFrame.pointee.nb_side_data {
                        if let sideData = inputFrame.pointee.side_data[Int(i)]?.pointee {
                            if sideData.type == AV_FRAME_DATA_A53_CC {
                                if let closedCaptionsTrack = assetTrack.closedCaptionsTrack,
                                   let subtitle = closedCaptionsTrack.subtitle
                                {
                                    let closedCaptionsPacket = Packet()
                                    // The `if let corePacket = packet.corePacket` that used to wrap
                                    // these five copies is gone with D1: the parameter IS the core
                                    // pointer now and is non-Optional, so the copies are
                                    // unconditional. Only the unwrap disappeared — the five fields
                                    // and their order are unchanged.
                                    closedCaptionsPacket.corePacket?.pointee.pts = packet.pointee.pts
                                    closedCaptionsPacket.corePacket?.pointee.dts = packet.pointee.dts
                                    closedCaptionsPacket.corePacket?.pointee.pos = packet.pointee.pos
                                    closedCaptionsPacket.corePacket?.pointee.time_base = packet.pointee.time_base
                                    closedCaptionsPacket.corePacket?.pointee.stream_index = packet.pointee.stream_index
                                    closedCaptionsPacket.corePacket?.pointee.flags |= AV_PKT_FLAG_KEY
                                    closedCaptionsPacket.corePacket?.pointee.size = Int32(sideData.size)
                                    let buffer = av_buffer_ref(sideData.buf)
                                    closedCaptionsPacket.corePacket?.pointee.data = buffer?.pointee.data
                                    closedCaptionsPacket.corePacket?.pointee.buf = buffer
                                    closedCaptionsPacket.assetTrack = closedCaptionsTrack
                                    subtitle.putPacket(packet: closedCaptionsPacket)
                                }
                            } else if sideData.type == AV_FRAME_DATA_SEI_UNREGISTERED {
                                let size = sideData.size
                                if size > AV_UUID_LEN {
                                    let str = String(cString: sideData.data.advanced(by: Int(AV_UUID_LEN)))
                                    // `time` is READ, not chosen. Forward's only call to sei(string:time:) is the sole
                                    // slot-283 dispatch in the image, @0x101a6754c, inside the same
                                    // relocated side-data loop this method is pinned above as DEFERRED (VideoSwresample.s32,
                                    // 0x101a67274). There the argument is built @0x101a674fc-0x101a67544: best_effort_timestamp
                                    // (AVFrame+0x130), falling back on a sign-bit test to pts (+0x88) then pkt_dts (+0x90) —
                                    // offsets taken by NAME with offsetof against the ios-arm64 n8.1.1 headers that built the
                                    // image, and corroborated in the same body by nb_side_data(+0x110)/side_data(+0x108);
                                    // `bic x8,x8,x8,asr #63` = max(0,·); then Timebase.cmtime(for:) (the CMTime.init(value:
                                    // timescale:) bind at __got 0x1041132c0 over track.timebase num/den at +0xc0/+0xc4) minus
                                    // the track's startTime CMTime at +0xa0 (CMTime.- infix, __got 0x1041132b8). +0xa0/+0xc0
                                    // are FFmpegAssetTrack.startTime/timebase per field_offset_vector.py.
                                    var seiTimestamp = inputFrame.pointee.best_effort_timestamp
                                    if seiTimestamp < 0 {
                                        seiTimestamp = inputFrame.pointee.pts
                                    }
                                    if seiTimestamp < 0 {
                                        seiTimestamp = inputFrame.pointee.pkt_dts
                                    }
                                    options.sei(string: str, time: assetTrack.timebase.cmtime(for: max(0, seiTimestamp)) - assetTrack.startTime)
                                }
                            } else if sideData.type == AV_FRAME_DATA_DOVI_RPU_BUFFER {
                                let data = sideData.data.withMemoryRebound(to: [UInt8].self, capacity: 1) { $0 }
                            } else if sideData.type == AV_FRAME_DATA_DOVI_METADATA { // AVDOVIMetadata
                                let data = sideData.data.withMemoryRebound(to: AVDOVIMetadata.self, capacity: 1) { $0 }
                                let header = av_dovi_get_header(data)
                                let mapping = av_dovi_get_mapping(data)
                                let color = av_dovi_get_color(data)
//                                frame.pixelBuffer?.transferFunction = kCVImageBufferTransferFunction_ITU_R_2020
                            } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_PLUS { // AVDynamicHDRPlus
                                let data = sideData.data.withMemoryRebound(to: AVDynamicHDRPlus.self, capacity: 1) { $0 }.pointee
                            } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_VIVID { // AVDynamicHDRVivid
                                let data = sideData.data.withMemoryRebound(to: AVDynamicHDRVivid.self, capacity: 1) { $0 }.pointee
                            } else if sideData.type == AV_FRAME_DATA_MASTERING_DISPLAY_METADATA {
                                let data = sideData.data.withMemoryRebound(to: AVMasteringDisplayMetadata.self, capacity: 1) { $0 }.pointee
                                displayData = MasteringDisplayMetadata(
                                    display_primaries_r_x: UInt16(data.display_primaries.0.0.num).bigEndian,
                                    display_primaries_r_y: UInt16(data.display_primaries.0.1.num).bigEndian,
                                    display_primaries_g_x: UInt16(data.display_primaries.1.0.num).bigEndian,
                                    display_primaries_g_y: UInt16(data.display_primaries.1.1.num).bigEndian,
                                    display_primaries_b_x: UInt16(data.display_primaries.2.1.num).bigEndian,
                                    display_primaries_b_y: UInt16(data.display_primaries.2.1.num).bigEndian,
                                    white_point_x: UInt16(data.white_point.0.num).bigEndian,
                                    white_point_y: UInt16(data.white_point.1.num).bigEndian,
                                    minLuminance: UInt32(data.min_luminance.num).bigEndian,
                                    maxLuminance: UInt32(data.max_luminance.num).bigEndian
                                )
                            } else if sideData.type == AV_FRAME_DATA_CONTENT_LIGHT_LEVEL {
                                let data = sideData.data.withMemoryRebound(to: AVContentLightMetadata.self, capacity: 1) { $0 }.pointee
                                contentData = ContentLightMetadata(
                                    MaxCLL: UInt16(data.MaxCLL).bigEndian,
                                    MaxFALL: UInt16(data.MaxFALL).bigEndian
                                )
                            } else if sideData.type == AV_FRAME_DATA_AMBIENT_VIEWING_ENVIRONMENT {
                                let data = sideData.data.withMemoryRebound(to: AVAmbientViewingEnvironment.self, capacity: 1) { $0 }.pointee
                                ambientViewingEnvironment = AmbientViewingEnvironment(
                                    ambient_illuminance: UInt32(data.ambient_illuminance.num).bigEndian,
                                    ambient_light_x: UInt16(data.ambient_light_x.num).bigEndian,
                                    ambient_light_y: UInt16(data.ambient_light_y.num).bigEndian
                                )
                            }
                        }
                    }
                }
                filter.filter(options: options, inputFrame: inputFrame) { avframe in
                    do {
                        var frame = try frameChange.change(avframe: avframe)
                        if let videoFrame = frame as? VideoVTBFrame {
                            if let pixelBuffer = videoFrame.pixelBuffer as? PixelBuffer {
                                pixelBuffer.formatDescription = assetTrack.formatDescription
                            }
                            if displayData != nil || contentData != nil || ambientViewingEnvironment != nil {
                                videoFrame.edrMetaData = EDRMetaData(displayData: displayData, contentData: contentData, ambientViewingEnvironment: ambientViewingEnvironment)
                            }
                        }
                        frame.timebase = filter.timebase
                        //                frame.timebase = Timebase(avframe.pointee.time_base)
                        // CARRIED THROUGH D1, NOT RE-DERIVED. These two are inside the
                        // `filter.filter` closure, which is a SEPARATE binary function with its own
                        // address — the x24 scan that proves this method reads only AVPacket.flags
                        // covers 0x101a2220c-0x101a22ca0 and says nothing about the closure. The
                        // rewrite is the identity the source itself already asserts in
                        // `Packet.assetTrack.didSet` (Model.swift): `position = packet.pos` and
                        // `size = packet.size` off the same core pointer. The closure's own extent
                        // has NOT been read, so these two lines are unverified at their new
                        // spelling and are the first thing to check when that unit is opened.
                        // ⚑[tool=function_extents ref=FFmpegDecode.decodeFrame:0x101a2220c result=closure-extent-not-in-this-range]
                        frame.size = packet.pointee.size
                        frame.position = packet.pointee.pos
                        frame.duration = avframe.pointee.duration
                        if frame.duration == 0, avframe.pointee.sample_rate != 0, frame.timebase.num != 0 {
                            frame.duration = Int64(avframe.pointee.nb_samples) * Int64(frame.timebase.den) / (Int64(avframe.pointee.sample_rate) * Int64(frame.timebase.num))
                        }
                        var timestamp = avframe.pointee.best_effort_timestamp
                        if timestamp < 0 {
                            timestamp = avframe.pointee.pts
                        }
                        if timestamp < 0 {
                            timestamp = avframe.pointee.pkt_dts
                        }
                        if timestamp < 0 {
                            timestamp = bestEffortTimestamp
                        }
                        frame.timestamp = timestamp
                        bestEffortTimestamp = timestamp &+ frame.duration
                        completionHandler(.success(frame))
                    } catch {
                        completionHandler(.failure(error))
                    }
                }
            } else {
                if result == AVError.eof.code {
                    avcodec_flush_buffers(codecContext)
                    break
                } else if result == AVError.tryAgain.code {
                    break
                } else {
                    // ⚑ THE ONE SITE IN THE IMAGE THAT CALLS A KSPlayerError INITIALIZER — every
                    //   other error is constructed inline. The call is at 0x101a229fc, into the real
                    //   body 0x1019e429c behind the 1-instruction forwarder.
                    //   The ternary survives verbatim as arithmetic on the CASE INDEX rather than a
                    //   branch: `cmp w28,#0 / mov w8,#0xb / cinc w8,w8,eq` — base 11 is
                    //   `codecVideoReceiveFrame`, incremented to 12 `codecAudioReceiveFrame` when the
                    //   media-type discriminant is 0. `avErrorCode` is the live decode result.
                    //   The returned (code, message) pair is then boxed TWICE — once for KSLog and
                    //   once into the `.failure` payload — which is why both statements below stand.
                    let error = KSPlayerError(errorCode: assetTrack.mediaType == .audio ? .codecAudioReceiveFrame : .codecVideoReceiveFrame, avErrorCode: result)
                    KSLog(error)
                    completionHandler(.failure(error))
                }
            }
        }
    }

    func doFlushCodec() {
        bestEffortTimestamp = Int64(0)
        // seek之后要清空下，不然解码可能还会有缓存，导致返回的数据是之前seek的。
        if codecContext != nil {
            avcodec_flush_buffers(codecContext)
        }
    }

    func shutdown() {
        av_frame_free(&coreFrame)
        avcodec_free_context(&codecContext)
        frameChange.shutdown()
    }

    func decode() {
        bestEffortTimestamp = Int64(0)
        if codecContext != nil {
            avcodec_flush_buffers(codecContext)
        }
    }
}
