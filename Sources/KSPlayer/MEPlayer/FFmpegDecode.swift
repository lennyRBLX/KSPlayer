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
    // MARK: - Fields (RE: FFmpegDecode, 9 fields per types.json)
    // Field order below mirrors the binary type-dump declaration order. The
    // binary additionally reserves a 3008-byte inline DV-metadata staging
    // buffer at `self + 0x70` that is not represented as a named field in
    // the type dump; it is allocated by the initializer and is the
    // destination of the side-data type-`0x18` copy (see decode loop).

    /// #1 — Player configuration reference.
    private let options: KSOptions
    /// #2 — Reusable AVFrame for decode output.
    private var coreFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    /// #3 — Active codec context.
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    /// #4 — Last best-effort PTS from the decoder.
    private var bestEffortTimestamp = Int64(0)
    /// #5 — Existential-typed frame converter (24 B inline + 8 B type
    /// metadata + 8 B witness table in the binary layout).
    private let frameChange: FrameChange
    /// #6 — libavfilter post-processing graph.
    private let filter: MEFilter
    /// #7 — True after first successful frame decode. Gates the VTB fallback
    /// distinguishing in the track's fallback dispatcher.
    public var hasDecodeSuccess: Bool = false
    /// #8 — Cached `mediaType == .video` for the hot decode loop.
    public let isVideo: Bool
    /// #9 — Dolby Vision metadata extracted by the decode loop. Mirrors
    /// the per-frame `VideoVTBFrame.doviData` that is emitted downstream
    /// but is also held on the decoder itself per the binary layout.
    public var doviData: DOVIFrameMetadata?

    // MARK: - Inline buffers (not in the Swift type dump)
    /// 3008-byte DV metadata staging area at the binary's `self + 0x70`.
    /// Holds a copy of `AV_FRAME_DATA_DOVI_METADATA` (side-data type 0x18)
    /// before it is wrapped into a `DOVIFrameMetadata` for the renderer.
    private var dvMetadataStaging = Data(count: 3008)

    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.options = options
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
        guard let codecContext, avcodec_send_packet(codecContext, packet.corePacket) == 0 else {
            return
        }
        // 需要avcodec_send_packet之后，properties的值才会变成FF_CODEC_PROPERTY_CLOSED_CAPTIONS
        if packet.assetTrack.mediaType == .video {
            if Int32(codecContext.pointee.properties) & FF_CODEC_PROPERTY_CLOSED_CAPTIONS != 0, packet.assetTrack.closedCaptionsTrack == nil {
                var codecpar = AVCodecParameters()
                codecpar.codec_type = AVMEDIA_TYPE_SUBTITLE
                codecpar.codec_id = AV_CODEC_ID_EIA_608
                if let subtitleAssetTrack = FFmpegAssetTrack(codecpar: codecpar) {
                    subtitleAssetTrack.name = "Closed Captions"
                    subtitleAssetTrack.startTime = packet.assetTrack.startTime
                    subtitleAssetTrack.timebase = packet.assetTrack.timebase
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 255, options: options)
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
                var isVIVID = false
                var doviRPU: Data?
                var doviMetadataPtr: UnsafePointer<AVDOVIMetadata>?
                // Per-frame HDR / DV side-data dispatch. Mirrors the Forward
                // binary's `MEPlayerItem_processFrameSideData @ 0x101407908`
                // case table (per `.reversal/DolbyVision.md §"Side-data" table`):
                //
                //   0x01 / 1   AV_FRAME_DATA_A53_CC                      → CC packet → vtable+0x198
                //   0x0B / 11  AV_FRAME_DATA_MASTERING_DISPLAY_METADATA  → DynamicInfo.masteringDisplay
                //   0x0E / 14  AV_FRAME_DATA_CONTENT_LIGHT_LEVEL         → DynamicInfo.contentLightLevel
                //   0x11 / 17  AV_FRAME_DATA_DISPLAYMATRIX               → recognised and skipped
                //   0x14 / 20  AV_FRAME_DATA_SEI_UNREGISTERED            → C-string + CMTime → vtable+0xba8
                //   0x18 / 24  AV_FRAME_DATA_DOVI_RPU_BUFFER             → 3008-byte memmove + 3-cond. DV activation
                //                                                          (gate: track flag@+0x13a, AVFrame.format==2,
                //                                                           KSOptions.hardwareDecode==1)
                //                                                          The binary calls a `nullsub_2(stackBuf)`
                //                                                          stub between the memmove and the memcpy
                //                                                          to `self+0x70`.
                //   0x19 / 25  AV_FRAME_DATA_DOVI_METADATA               → sets `local_d98 | (1 << 32)` (flag only)
                //   0x1A / 26  AV_FRAME_DATA_AMBIENT_VIEWING_ENVIRONMENT → DynamicInfo ambient viewing environment
                //
                // The Swift branches below stash the parsed `AVDOVIMetadata` pointer (header /
                // mapping / color) from whichever FFmpeg side-data type carries it on this
                // build of FFmpeg, then surface it via `DOVIFrameMetadata` on the
                // `VideoVTBFrame`. The DV-singleton activation gate itself lives in
                // `MetalPlayView`'s draw path (mirrors the binary's three-condition guard).
                // 注释：filter之后，side_data信息会丢失，所以放在这里
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
                                    options.sei(string: str)
                                }
                            } else if sideData.type == AV_FRAME_DATA_DOVI_RPU_BUFFER {
                                doviRPU = Data(bytes: sideData.data, count: Int(sideData.size))
                            } else if sideData.type == AV_FRAME_DATA_DOVI_METADATA {
                                doviMetadataPtr = sideData.data.withMemoryRebound(to: AVDOVIMetadata.self, capacity: 1) { $0 }
                                // RE: Forward stages the 3008-byte DV metadata
                                // buffer at `self + 0x70`. Copy bounded by the
                                // smaller of side-data size and staging area.
                                let copyCount = min(Int(sideData.size), dvMetadataStaging.count)
                                dvMetadataStaging.withUnsafeMutableBytes { dest in
                                    if let baseAddress = dest.baseAddress {
                                        memcpy(baseAddress, sideData.data, copyCount)
                                    }
                                }
                            } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_PLUS { // AVDynamicHDRPlus
                                _ = sideData.data.withMemoryRebound(to: AVDynamicHDRPlus.self, capacity: 1) { $0 }.pointee
                            } else if sideData.type == AV_FRAME_DATA_DYNAMIC_HDR_VIVID { // AVDynamicHDRVivid
                                _ = sideData.data.withMemoryRebound(to: AVDynamicHDRVivid.self, capacity: 1) { $0 }.pointee
                                isVIVID = true
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
                if let doviMetadataPtr {
                    doviData = DOVIFrameMetadata(
                        rpuData: doviRPU,
                        header: av_dovi_get_header(doviMetadataPtr),
                        mapping: av_dovi_get_mapping(doviMetadataPtr),
                        color: av_dovi_get_color(doviMetadataPtr)
                    )
                }
                let stagedDovi = doviData
                filter.filter(options: options, inputFrame: inputFrame) { avframe in
                    do {
                        var frame = try frameChange.change(avframe: avframe)
                        if let videoFrame = frame as? VideoVTBFrame, let pixelBuffer = videoFrame.corePixelBuffer {
                            if let pixelBuffer = pixelBuffer as? PixelBuffer {
                                pixelBuffer.formatDescription = packet.assetTrack.formatDescription
                            }
                            if displayData != nil || contentData != nil || ambientViewingEnvironment != nil || isVIVID {
                                videoFrame.edrMetaData = EDRMetaData(displayData: displayData, contentData: contentData, ambientViewingEnvironment: ambientViewingEnvironment, isVIVID: isVIVID)
                            }
                            if let stagedDovi {
                                videoFrame.doviData = stagedDovi
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
                        hasDecodeSuccess = true
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
        avcodec_flush_buffers(codecContext)
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
