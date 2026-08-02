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

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        // DEFERRED → DV-render/HDR-pixelBuffer phase (COUPLED unit): Forward moved this inline side-data loop (L71-142)
        // into VideoSwresample.s32 (0x101a67274; sole caller = this method @decompile-L182). s32 writes VideoSwresample's
        // DV/HDR fields that change s28 CONSUMES → frame, so loop-removal + s32 + change + transfer reconstruct as ONE unit
        // (landing s32 + removing this loop without change REGRESSES the edrMetaData path — change s28 grep-confirmed reads
        // +0x60/+0xc20../+0xc50/+0xc60). Gated on the protocol-witness verifier. Cached: FFmpegDecode_slot13/slot18.
        guard let codecContext, avcodec_send_packet(codecContext, packet.corePacket) == 0 else {
            return
        }
        // 需要avcodec_send_packet之后，properties的值才会变成FF_CODEC_PROPERTY_CLOSED_CAPTIONS
        if packet.assetTrack.mediaType == .video {
            // ⚑ Forward retyped FFmpegAssetTrack.codecpar value→pointer, so the synthetic CC codecpar is
            //   heap-allocated (stable pointer the track stores) — the alloc folds into the compound `if`
            //   to match the binary (FUN_101a23404 L33-38: alloc-fail skips the block, not a return).
            //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_alloc:0x1029f543c result=CONFIRMED]
            //   ⚑ ownership/free deferred to the FFmpegAssetTrack lifecycle audit (the alloc'd params are now owned by the track; the base value-copy had no free step).
            if Int32(codecContext.pointee.properties) & FF_CODEC_PROPERTY_CLOSED_CAPTIONS != 0,
               packet.assetTrack.closedCaptionsTrack == nil,
               let codecpar = avcodec_parameters_alloc() {
                codecpar.pointee.codec_type = AVMEDIA_TYPE_SUBTITLE
                codecpar.pointee.codec_id = AV_CODEC_ID_EIA_608
                if let subtitleAssetTrack = FFmpegAssetTrack(codecpar: codecpar) {
                    subtitleAssetTrack.name = "Closed Captions"
                    subtitleAssetTrack.startTime = packet.assetTrack.startTime
                    subtitleAssetTrack.timebase = packet.assetTrack.timebase
                    // ⚑[tool=export_trie_oracle ref=FUN_101a23404:0x101a23404 result=NOT_IN_TRIE — enclosing function
                    //   unnamed (a real negative, not a lookup failure); identified by its own body, below]
                    // Call @0x101a235a0 (thunk 0x101a3340c) inside that function: `w1 = 0x80` @0x101a23594 and
                    // `w3 = 1` @0x101a2359c, both binary-read — so frameCapacity is 128 here, not the 255 source
                    // carried. Site identified by its own body: `str d0,[x0]` @0x101a23480 writes the
                    // codec_type/codec_id pair, swift_allocObject(351) @0x101a23498 is the FFmpegAssetTrack, and
                    // the result is stored to +0x100 (`subtitle`) @0x101a235ac.
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                    subtitleAssetTrack.subtitle = subtitle
                    packet.assetTrack.closedCaptionsTrack = subtitleAssetTrack
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
                                if let closedCaptionsTrack = packet.assetTrack.closedCaptionsTrack,
                                   let subtitle = closedCaptionsTrack.subtitle
                                {
                                    let closedCaptionsPacket = Packet()
                                    if let corePacket = packet.corePacket {
                                        closedCaptionsPacket.corePacket?.pointee.pts = corePacket.pointee.pts
                                        closedCaptionsPacket.corePacket?.pointee.dts = corePacket.pointee.dts
                                        closedCaptionsPacket.corePacket?.pointee.pos = corePacket.pointee.pos
                                        closedCaptionsPacket.corePacket?.pointee.time_base = corePacket.pointee.time_base
                                        closedCaptionsPacket.corePacket?.pointee.stream_index = corePacket.pointee.stream_index
                                    }
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
                                    options.sei(string: str, time: packet.assetTrack.timebase.cmtime(for: max(0, seiTimestamp)) - packet.assetTrack.startTime)
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
                        if let videoFrame = frame as? VideoVTBFrame, let pixelBuffer = videoFrame.pixelBuffer {
                            if let pixelBuffer = pixelBuffer as? PixelBuffer {
                                pixelBuffer.formatDescription = packet.assetTrack.formatDescription
                            }
                            if displayData != nil || contentData != nil || ambientViewingEnvironment != nil {
                                videoFrame.edrMetaData = EDRMetaData(displayData: displayData, contentData: contentData, ambientViewingEnvironment: ambientViewingEnvironment)
                            }
                        }
                        frame.timebase = filter.timebase
                        //                frame.timebase = Timebase(avframe.pointee.time_base)
                        frame.size = packet.size
                        frame.position = packet.position
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
                    let error = NSError(errorCode: packet.assetTrack.mediaType == .audio ? .codecAudioReceiveFrame : .codecVideoReceiveFrame, avErrorCode: result)
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
