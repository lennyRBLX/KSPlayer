//
//  FFmpegDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import Foundation
import Libavcodec
#if canImport(VideoToolbox)
import VideoToolbox
#endif

class FFmpegDecode: DecodeProtocol {
    // MARK: - Fields (RE: FFmpegDecode, 9 fields per types.json + 1 reconstruction addition)
    // Field order below mirrors the binary type-dump declaration order. The
    // binary additionally reserves a 3008-byte inline DV-metadata staging
    // buffer at `self + 0x70` that is not represented as a named field in
    // the type dump; it is allocated by the initializer and is the
    // destination of the side-data type-`0x18` copy (see decode loop).
    //
    // NOTE: `assetTrack` (#10) is NOT in the types.json 9-field list. The
    // binary accesses the asset track through the caller's closure capture
    // or a class-level reference not visible in the type-metadata dump. We
    // add it as a stored property because the HW->SW fallback re-open path
    // (`reopenCodecInSoftwareMode`) needs the track's codec parameters to
    // re-create the codec context — without it, there is no way to call
    // `assetTrack.createContext(options:)` after tearing down the old one.

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

    /// #10 — Reconstruction addition (not in types.json 9-field list).
    /// The track this decoder was created for. Retained for the HW->SW
    /// fallback codec re-open path which needs to re-create the codec
    /// context from the asset track's codec parameters. In the binary,
    /// the init caller's closure capture or a MEPlayerItemTrack-level
    /// reference provides this; we surface it as a stored property for
    /// the `reopenCodecInSoftwareMode()` path.
    private let assetTrack: FFmpegAssetTrack

    // MARK: - Inline buffers (not in the Swift type dump)
    /// 3008-byte DV metadata staging area at the binary's `self + 0x70`.
    /// Holds a copy of `AV_FRAME_DATA_DOVI_RPU_BUFFER` (side-data type 0x18)
    /// before it is wrapped into a `DOVIFrameMetadata` for the renderer.
    private var dvMetadataStaging = Data(count: 3008)

    // MARK: - Init

    /// RE: 0x101405bb8 (FFmpegDecode_init, 1.3.15)
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

    /// RE: 0x1001e6af4 (FFmpegDecode_deinit, 1.3.15)
    deinit {
        shutdown()
    }

    // MARK: - Helper functions

    /// RE: 0x1013ea4e4 (FFmpegDecode_applyOptionsFromDictionary, 1.3.15)
    /// Applies decoder options from a Swift dictionary to the codec context
    /// via av_opt_set. Part of the codec-open path used by init and HW->SW
    /// fallback re-open.
    private func applyOptionsFromDictionary(_ dict: [String: Any], to ctx: UnsafeMutablePointer<AVCodecContext>) {
        for (key, value) in dict {
            if let strValue = value as? String {
                setAVOptionValue(ctx, key: key, value: strValue)
            } else if let intValue = value as? Int {
                setAVOptionValue(ctx, key: key, value: String(intValue))
            } else if let int64Value = value as? Int64 {
                setAVOptionValue(ctx, key: key, value: String(int64Value))
            }
        }
    }

    /// RE: 0x1013e9e54 (FFmpegDecode_parseDictionaryFromAVDict, 1.3.15)
    /// Parses an FFmpeg AVDictionary into a Swift [String: String] dictionary.
    private static func parseDictionaryFromAVDict(_ dict: OpaquePointer?) -> [String: String] {
        var result = [String: String]()
        var entry: UnsafeMutablePointer<AVDictionaryEntry>?
        while true {
            entry = av_dict_get(dict, "", entry, AV_DICT_IGNORE_SUFFIX)
            guard let entry else { break }
            let key = String(cString: entry.pointee.key)
            let value = String(cString: entry.pointee.value)
            result[key] = value
        }
        return result
    }

    /// RE: 0x1013e9ddc (FFmpegDecode_getCodecDescription, 1.3.15)
    /// Reads the codec long_name from AVCodecDescriptor into a Swift String.
    private static func getCodecDescription(for codecID: AVCodecID) -> String {
        if let descriptor = avcodec_descriptor_get(codecID),
           let longName = descriptor.pointee.long_name
        {
            return String(cString: longName)
        }
        return ""
    }

    /// RE: 0x1013ea5b0 (FFmpegDecode_mapCodecToVTBPixelFormat, 1.3.15)
    /// Maps AVCodecID to a CoreVideo pixel format for VideoToolbox hardware
    /// decode probing. Called from the HW->SW fallback codec re-open path.
    private static func mapCodecToVTBPixelFormat(codecID: AVCodecID) -> OSType? {
        #if canImport(VideoToolbox)
        switch codecID {
        case AV_CODEC_ID_H264:
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case AV_CODEC_ID_HEVC:
            return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case AV_CODEC_ID_VP9:
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case AV_CODEC_ID_AV1:
            return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        default:
            return nil
        }
        #else
        return nil
        #endif
    }

    /// RE: 0x1013eb4ac (FFmpegDecode_mapAVCodecIDToMediaSubType, 1.3.15)
    /// Maps AVCodecID to CMFormatDescription.MediaSubType. Required for VTB
    /// format description creation.
    private static func mapAVCodecIDToMediaSubType(_ codecID: AVCodecID) -> CMFormatDescription.MediaSubType {
        // Delegates to the existing extension on AVCodecID in
        // AVFFmpegExtension.swift which already has the complete mapping table.
        return codecID.mediaSubType
    }

    /// RE: 0x101417518 (FFmpegDecode_freePacket, 1.3.15)
    /// Packet release helper. The binary has this as a separate named function
    /// on FFmpegDecode; Packet.deinit in Model.swift calls av_packet_free
    /// directly, but the named function is reconstructed here for API surface
    /// preservation.
    private static func freePacket(_ packet: UnsafeMutablePointer<AVPacket>?) {
        guard var pkt = packet else { return }
        av_packet_free(&pkt)
    }

    /// RE: 0x101417f3c (FFmpegDecode_allocThumbnailContext, 1.3.15)
    /// Thumbnail-only decode context allocation. Creates a lightweight codec
    /// context configured for single-frame thumbnail extraction (low thread
    /// count, no filter graph). The binary allocates a separate codec context
    /// without going through the full createContext path -- it manually sets
    /// up parameters, skips HW decode setup, and opens with minimal threading.
    static func allocThumbnailContext(assetTrack: FFmpegAssetTrack, options: KSOptions) -> UnsafeMutablePointer<AVCodecContext>? {
        guard let codecContext = avcodec_alloc_context3(nil) else {
            return nil
        }
        var codecpar = assetTrack.codecpar
        let result = avcodec_parameters_to_context(codecContext, &codecpar)
        guard result == 0 else {
            var ctxPtr: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&ctxPtr)
            return nil
        }
        guard let codec = avcodec_find_decoder(codecContext.pointee.codec_id) else {
            var ctxPtr: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&ctxPtr)
            return nil
        }
        // Thumbnail decode: minimal threading, skip loop filter for speed
        codecContext.pointee.thread_count = 1
        codecContext.pointee.skip_loop_filter = AVDISCARD_ALL
        codecContext.pointee.flags2 |= AV_CODEC_FLAG2_FAST
        codecContext.pointee.codec_id = codec.pointee.id
        let openResult = avcodec_open2(codecContext, codec, nil)
        guard openResult == 0 else {
            var ctxPtr: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&ctxPtr)
            return nil
        }
        return codecContext
    }

    /// RE: 0x1013ebba8 (FFmpegDecode_setAVOptionValue, 1.3.15)
    /// Wrapper around av_opt_set for applying individual options to the codec
    /// context.
    private func setAVOptionValue(_ ctx: UnsafeMutablePointer<AVCodecContext>, key: String, value: String) {
        av_opt_set(ctx, key, value, AV_OPT_SEARCH_CHILDREN)
    }

    // MARK: - Video Color-Space Descriptor

    /// RE: 0x10146eb24 (FFmpegDecode_configureVideoColorSpace, 1.3.15)
    /// Builds a video color-space descriptor from AVCodecContext. Populates
    /// bits-per-component, width/height, plane count, SAR-adjusted dimensions,
    /// colour-primaries family, interlaced flag, mapped color primaries/
    /// transfer/YCbCr CFStrings, cached codec_pix_fmt, chroma-plane arrays,
    /// output buffer arrays, and range slots.
    ///
    /// In the binary this writes to an sret buffer (not confirmed to be self);
    /// in our reconstruction we return a structured descriptor.
    static func configureVideoColorSpace(from ctx: UnsafeMutablePointer<AVCodecContext>) -> VideoColorSpaceDescriptor {
        let pixFmt = ctx.pointee.pix_fmt
        let desc = av_pix_fmt_desc_get(pixFmt)
        let bitsPerComponent = Int(desc?.pointee.comp.0.depth ?? 8)
        let width = Int(ctx.pointee.width)
        let height = Int(ctx.pointee.height)
        let planeCount: Int
        if let desc {
            switch desc.pointee.nb_components {
            case 3:
                planeCount = Int(desc.pointee.comp.2.plane + 1)
            case 2:
                planeCount = Int(desc.pointee.comp.1.plane + 1)
            default:
                planeCount = Int(desc.pointee.comp.0.plane + 1)
            }
        } else {
            planeCount = 1
        }

        // SAR-adjusted dimensions
        let sarNum = Double(ctx.pointee.sample_aspect_ratio.num)
        let sarDen = Double(max(ctx.pointee.sample_aspect_ratio.den, 1))
        let sarRatio = sarNum / sarDen
        let adjustedWidth = sarRatio > 0 ? Double(width) * sarRatio : Double(width)
        let adjustedHeight = Double(height)

        // Colour-primaries family enum: 6 if colorspace is BT.2020, else 0
        let colorspace = ctx.pointee.colorspace
        let colorPrimariesFamily: Int
        if colorspace == AVCOL_SPC_BT2020_NCL || colorspace == AVCOL_SPC_BT2020_CL {
            colorPrimariesFamily = 6
        } else {
            colorPrimariesFamily = 0
        }

        // Interlaced flag: true if field_order == 2 (TT)
        let isInterlaced = ctx.pointee.field_order.rawValue == 2

        // Mapped color properties via existing extensions
        let colorPrimaries = AVColorPrimaries(rawValue: UInt32(ctx.pointee.color_primaries)).colorPrimaries
        let transferFunction = AVColorTransferCharacteristic(rawValue: UInt32(ctx.pointee.color_trc)).transferFunction
        let ycbcrMatrix = AVColorSpace(rawValue: UInt32(ctx.pointee.colorspace)).ycbcrMatrix

        return VideoColorSpaceDescriptor(
            bitsPerComponent: bitsPerComponent,
            width: width,
            height: height,
            planeCount: planeCount,
            adjustedWidth: adjustedWidth,
            adjustedHeight: adjustedHeight,
            colorPrimariesFamily: colorPrimariesFamily,
            isInterlaced: isInterlaced,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            ycbcrMatrix: ycbcrMatrix,
            codecPixelFormat: UInt32(pixFmt.rawValue)
        )
    }

    // MARK: - CC Track Creation

    /// RE: 0x101407730 (FFmpegDecode_createCCTrack, 1.3.15)
    /// Video-only: creates a CC subtitle FFmpegAssetTrack if the A53_CC bit
    /// is set and no existing CC track exists. Binary size 472 B.
    private func createCCTrackIfNeeded(for packet: Packet) {
        guard isVideo, let codecContext else { return }
        guard Int32(codecContext.pointee.properties) & FF_CODEC_PROPERTY_CLOSED_CAPTIONS != 0 else { return }
        guard packet.assetTrack.closedCaptionsTrack == nil else { return }

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

    // MARK: - HW->SW Fallback Codec Re-open

    /// RE: 0x1013ea044 (decoder-open helper, 1.3.15)
    /// Re-opens the codec context in software mode. This is the SW codec
    /// re-open target used by both HW->SW fallback paths in decodeFrame.
    /// Reads KSOptions.{codecLowDelay, decoderOptions, videoSoftDecodeThreadCount,
    /// hardwareDecode, lowres}, runs AV1/HW-decode probing, and calls avcodec_open2.
    private func reopenCodecInSoftwareMode() -> Bool {
        // Tear down existing context
        avcodec_free_context(&codecContext)
        // Disable hardware decode for the re-open
        options.hardwareDecode = false
        do {
            // Re-create context from the track's codec parameters.
            // createContext on FFmpegAssetTrack checks options.hardwareDecode,
            // which we just set to false, so it will skip VT setup.
            codecContext = try assetTrack.createContext(options: options)
            codecContext?.pointee.time_base = assetTrack.timebase.rational
            // Apply additional decoder options
            if let ctx = codecContext {
                applyOptionsFromDictionary(options.decoderOptions, to: ctx)
                if options.videoSoftDecodeThreadCount > 0 {
                    ctx.pointee.thread_count = Int32(options.videoSoftDecodeThreadCount)
                }
            }
            return true
        } catch {
            KSLog("[decode] SW fallback codec re-open failed: \(error)")
            return false
        }
    }

    // MARK: - Core Decode Loop

    /// RE: 0x10140608c (FFmpegDecode_decodeFrame body, 1.3.15)
    /// Thunk at 0x1014080a8, vtable entry at 0x103a25160.
    /// Core decode loop (4100 B). Implements:
    ///   send packet -> receive frame loop -> side-data -> filter -> output
    /// with two distinct HW->SW fallback paths and drainMode handling.
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        guard let ctx = codecContext else { return }
        guard avcodec_send_packet(ctx, packet.corePacket) == 0 else {
            return
        }
        // CC track creation (binary: FUN_101407730, 472 B)
        // After avcodec_send_packet, the properties value will reflect
        // FF_CODEC_PROPERTY_CLOSED_CAPTIONS if the stream has them.
        createCCTrackIfNeeded(for: packet)

        while true {
            // Re-read self.codecContext each iteration so HW->SW fallback
            // re-open is visible. The guard-let above only covers the send.
            guard let activeCtx = codecContext else { break }
            let result = avcodec_receive_frame(activeCtx, coreFrame)
            if result == 0, let inputFrame = coreFrame {
                // -- HW->SW fallback path A (L393-396) --
                // When hardwareDecode==false AND the codec context still has a
                // VTB session (hw_device_ctx != nil), re-open in SW mode.
                if isVideo, !options.hardwareDecode, activeCtx.pointee.hw_device_ctx != nil {
                    if reopenCodecInSoftwareMode() {
                        // Re-enter loop from top after SW re-open
                        continue
                    }
                }

                hasDecodeSuccess = true

                var displayData: MasteringDisplayMetadata?
                var contentData: ContentLightMetadata?
                var ambientViewingEnvironment: AmbientViewingEnvironment?
                var isVIVID = false
                var doviRPU: Data?
                var doviMetadataPtr: UnsafePointer<AVDOVIMetadata>?
                // Per-frame HDR / DV side-data dispatch. Mirrors the Forward
                // binary's `MEPlayerItem_processFrameSideData @ 0x101407908`
                // case table (per `.reversal/DolbyVision.md §"Side-data" table`).
                //
                // PLACEMENT NOTE: The binary's address prefix (0x10140xxxx) maps
                // to MEPlayerItem, and the cluster map in DolbyVision.md names
                // "MEPlayerItem-RPU" as the owning file. In KSPlayer's
                // architecture the decode loop lives in FFmpegDecode (not
                // MEPlayerItem), and the AVFrame side_data array is only
                // accessible here — after avcodec_receive_frame and before
                // the filter pass strips side_data. Moving this dispatch to
                // MEPlayerItem would require threading raw side-data across
                // a protocol boundary for no benefit. The binary inlined
                // decode into its MEPlayerItem; we keep the separation.
                //
                //   0x01 / 1   AV_FRAME_DATA_A53_CC                      -> CC packet -> vtable+0x198
                //   0x0B / 11  AV_FRAME_DATA_MASTERING_DISPLAY_METADATA  -> DynamicInfo.masteringDisplay
                //   0x0E / 14  AV_FRAME_DATA_CONTENT_LIGHT_LEVEL         -> DynamicInfo.contentLightLevel
                //   0x11 / 17  AV_FRAME_DATA_DISPLAYMATRIX               -> recognised and skipped
                //   0x14 / 20  AV_FRAME_DATA_SEI_UNREGISTERED            -> C-string + CMTime -> vtable+0xba8
                //   0x18 / 24  AV_FRAME_DATA_DOVI_RPU_BUFFER             -> 3008-byte memmove + 3-cond. DV activation
                //                                                          (gate: track flag@+0x13a, AVFrame.format==2,
                //                                                           KSOptions.hardwareDecode==1)
                //                                                          The binary calls a `nullsub_2(stackBuf)`
                //                                                          stub between the memmove and the memcpy
                //                                                          to `self+0x70`.
                //   0x19 / 25  AV_FRAME_DATA_DOVI_METADATA               -> sets `local_d98 | (1 << 32)` (flag only)
                //   0x1A / 26  AV_FRAME_DATA_AMBIENT_VIEWING_ENVIRONMENT -> DynamicInfo ambient viewing environment
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
                                    display_primaries_b_x: UInt16(data.display_primaries.2.0.num).bigEndian,
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
                    // Carrier struct (176-byte copied pointees) consumed downstream by
                    // the renderer to rebuild the GPU buffer per frame.
                    doviData = DOVIFrameMetadata(
                        rpuData: doviRPU,
                        header: av_dovi_get_header(doviMetadataPtr),
                        mapping: av_dovi_get_mapping(doviMetadataPtr),
                        color: av_dovi_get_color(doviMetadataPtr)
                    )
                    // RE: 0x101407908 type-0x19 arm -- the binary calls
                    // `FUN_10150c0a4` (convertAVDOVIToKSDOVIMetadata) then
                    // `memcpy(self+0x70, serialized, 0xBC0)`. Reconstruct that exact
                    // data flow: serialize the AVDOVIMetadata into the 3008-byte
                    // KSDOVIMetadata buffer and stage it at `self+0x70`
                    // (`dvMetadataStaging`).
                    var gpuMetadata = convertAVDOVIToKSDOVIMetadata(doviMetadataPtr)
                    dvMetadataStaging.withUnsafeMutableBytes { dest in
                        if let baseAddress = dest.baseAddress {
                            withUnsafeBytes(of: &gpuMetadata) { src in
                                if let srcBase = src.baseAddress {
                                    memcpy(baseAddress, srcBase,
                                           min(dest.count, MemoryLayout<DoviGPUMetadata>.size))
                                }
                            }
                        }
                    }
                }
                let stagedDovi = doviData
                // -- Frame-output dispatcher (RE: 0x101407090, 1696 B) --
                // Step 1: Set decodeType for video frames
                if isVideo {
                    if activeCtx.pointee.codec_id == AV_CODEC_ID_H264 {
                        options.decodeType = .hardware
                    } else {
                        options.decodeType = .soft
                    }
                }
                filter.filter(options: options, inputFrame: inputFrame) { avframe in
                    do {
                        var frame = try frameChange.change(avframe: avframe)
                        if let videoFrame = frame as? VideoVTBFrame, let pixelBuffer = videoFrame.corePixelBuffer {
                            // Step 5: Copy formatDescription / CC track ref into PixelBuffer
                            if let pixelBuffer = pixelBuffer as? PixelBuffer {
                                pixelBuffer.formatDescription = packet.assetTrack.formatDescription
                            }
                            // Step 3: Copy EDR metadata into the frame
                            if displayData != nil || contentData != nil || ambientViewingEnvironment != nil || isVIVID {
                                videoFrame.edrMetaData = EDRMetaData(displayData: displayData, contentData: contentData, ambientViewingEnvironment: ambientViewingEnvironment, isVIVID: isVIVID)
                            }
                            // Step 4: Copy DV metadata staging buffer into MEFrame
                            if let stagedDovi {
                                videoFrame.doviData = stagedDovi
                            }
                        }
                        frame.timebase = filter.timebase
                        frame.size = packet.size
                        frame.position = packet.position
                        frame.duration = avframe.pointee.duration
                        // Step 6: Duration calculation
                        if frame.duration == 0, avframe.pointee.sample_rate != 0, frame.timebase.num != 0 {
                            // Audio: duration from sample_rate and nb_samples
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
                    // EOF: flush buffers and exit
                    avcodec_flush_buffers(activeCtx)
                    break
                } else if result == AVError.tryAgain.code {
                    // -- DrainMode handling (L426-428) --
                    // Binary reads KSOptions+0x13C (drainMode flag). In the
                    // reconstruction, isLoopPlay is the closest proxy: when
                    // loop playback is active and we've successfully decoded
                    // frames, re-send NULL packet to drain the decoder's
                    // internal buffer for seamless looping.
                    if options.isLoopPlay, hasDecodeSuccess {
                        avcodec_send_packet(activeCtx, nil)
                        continue
                    }
                    break
                } else {
                    // Other errors
                    if hasDecodeSuccess {
                        // Transient error after successful frames: bail silently
                        break
                    }
                    // -- HW->SW fallback path B (L432-437) --
                    // On non-EAGAIN error when isVideo and hardwareDecode==true:
                    // destroy current codecCtx, set hardwareDecode=false,
                    // re-open in SW mode.
                    if isVideo, options.hardwareDecode {
                        KSLog("[decode] HW decode failed, falling back to SW: error \(result)")
                        if reopenCodecInSoftwareMode(), let newCtx = codecContext {
                            // Re-send the packet to the new SW decoder and retry
                            if avcodec_send_packet(newCtx, packet.corePacket) == 0 {
                                continue
                            }
                        }
                    }
                    let error = NSError(errorCode: packet.assetTrack.mediaType == .audio ? .codecAudioReceiveFrame : .codecVideoReceiveFrame, avErrorCode: result)
                    KSLog(error)
                    completionHandler(.failure(error))
                    break
                }
            }
        }
    }

    // MARK: - Flush / Shutdown

    /// RE: 0x1014080ac / 0x1014080b0 / 0x1014081c8 (FFmpegDecode_flushBuffers, 1.3.15)
    /// Three flush-path variants in the binary (4 B / 60 B / 4 B; two are
    /// trampolines into the 60 B body).
    func doFlushCodec() {
        bestEffortTimestamp = Int64(0)
        // After seek, clear decoder buffers to prevent stale cached frames
        // from being returned.
        avcodec_flush_buffers(codecContext)
    }

    /// RE: 0x1014080ec (FFmpegDecode_destroy, 1.3.15)
    /// Tears down codec context, frame, and frameChange existential.
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

// MARK: - AVDOVIMetadata -> KSDOVIMetadata (3008-byte GPU buffer) conversion

/// Convert an FFmpeg `AVDOVIMetadata` into the 3008-byte (0xBC0) KSDOVIMetadata
/// GPU-upload buffer (`DoviGPUMetadata`).
///
/// RE: 0x10150c0a4 (convertAVDOVIToKSDOVIMetadata, 1.3.15)
///
/// Free function (file scope) because the binary's `FUN_10150c0a4` is a standalone
/// function with multiple live UNCONDITIONAL_CALL xrefs that this reconstruction must
/// route through a single named entry point:
///   * `MEPlayerItem_processFrameSideData` @ 0x101407908 (call at 0x101407be0), the
///     DV side-data arm -- reconstructed in MEPlayerItem.swift `processFrameSideData`.
///   * The decode-loop DV staging copy in `FFmpegDecode` (this file), mirroring the
///     binary's `FUN_10150c0a4` -> `memcpy(self+0x70, serialized, 0xBC0)`.
///   * The DV RPU parse chain (`DOVIRPUShim`, TrackDecode.md L704-714
///     `serialized = FUN_10150c0a4(outPtr)`) after `dovi_rpu_get_header`.
///   * FUN_10141462c, FUN_101450044 route the same way.
///
/// EQUIVALENCE PROOF (decompile 0x10150c0a4 vs this body):
///   * `param_1` is the `AVDOVIMetadata *`. The decompile dereferences the first
///     three machine words of `*param_1` -- `lVar23 = *param_1` (header sub-struct
///     base offset), `param_1[1]` (mapping), `param_1[2]` (color) -- which is the
///     exact ABI that FFmpeg's public accessors `av_dovi_get_header`/
///     `av_dovi_get_mapping`/`av_dovi_get_color` return (each yields a pointer to
///     the corresponding sub-struct embedded behind the metadata header). Cracking
///     via the accessors is therefore behaviorally identical to the decompile's
///     raw offset loads -- not a substitution but the documented input path.
///   * `_bzero(local_fd0, 0xbc0)` -> `DoviGPUMetadata()` zero-initializes the same
///     3008-byte layout (Ghidra-verified 176-byte header + 3x944-byte reshape
///     blocks at 176/1120/2064; see DoviDisplayModel.swift `DoviGPUMetadata`).
///   * The decompile's per-field float conversions -- `NEON_ucvtf` on u16 fields,
///     `/ 2048.0` with `-1.0`/`-0x800` bias on the color matrices/offsets,
///     `/ 4095` (`1 << bit_depth`-derived) on pivots, and the
///     `mapping_idc`/`poly_order`/`mmr_order` branch building coeffs vs MMR --
///     are reproduced field-for-field by `DoviGPUMetadata.from(header:mapping:color:)`
///     in DoviDisplayModel.swift. The serialization body therefore lives in
///     `DoviGPUMetadata.from`; this function is its address-anchored named wrapper.
///
/// - Parameter metadata: pointer to the parsed `AVDOVIMetadata` (from side data
///   type 0x19 or from the RPU shim parse). `nil`/empty metadata yields a
///   zero-initialized buffer, matching the decompile's `param_1 == NULL` early
///   return that leaves `local_fd0` cleared.
/// - Returns: the populated 3008-byte `DoviGPUMetadata` ready for Metal upload.
func convertAVDOVIToKSDOVIMetadata(_ metadata: UnsafePointer<AVDOVIMetadata>?) -> DoviGPUMetadata {
    guard let metadata else { return DoviGPUMetadata() }
    // Crack the metadata into its three sub-structs via the proven FFmpeg
    // accessors (= the decompile's *param_1 / param_1[1] / param_1[2] loads),
    // then run the 0xBC0 serialization body.
    return DoviGPUMetadata.from(
        header: av_dovi_get_header(metadata)?.pointee,
        mapping: av_dovi_get_mapping(metadata)?.pointee,
        color: av_dovi_get_color(metadata)?.pointee
    )
}

// MARK: - Video Color-Space Descriptor

/// Structured output from `FFmpegDecode.configureVideoColorSpace`.
/// Mirrors the sret buffer layout documented at 0x10146eb24.
struct VideoColorSpaceDescriptor {
    /// Bits per color component (from pixel-format descriptor, default 8).
    var bitsPerComponent: Int
    /// Coded width in pixels.
    var width: Int
    /// Coded height in pixels.
    var height: Int
    /// Number of planes in the pixel format.
    var planeCount: Int
    /// SAR-adjusted width (Double).
    var adjustedWidth: Double
    /// SAR-adjusted height (Double).
    var adjustedHeight: Double
    /// Colour-primaries family enum (6 for BT.2020 family, 0 otherwise).
    var colorPrimariesFamily: Int
    /// Interlaced flag (codecCtx.field_order == 2).
    var isInterlaced: Bool
    /// Mapped color primaries (CFString from mapColorPrimaries).
    var colorPrimaries: CFString?
    /// Mapped transfer function (CFString from mapTransferFunction).
    var transferFunction: CFString?
    /// Mapped YCbCr matrix (CFString from mapYCbCrMatrix).
    var ycbcrMatrix: CFString?
    /// Cached codec pixel format (UInt32).
    var codecPixelFormat: UInt32
}
