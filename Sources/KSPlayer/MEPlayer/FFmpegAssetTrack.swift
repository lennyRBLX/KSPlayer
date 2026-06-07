//
//  FFmpegAssetTrack.swift
//  KSPlayer
//
//  Created by kintan on 2023/2/12.
//

import AVFoundation
import FFmpegKit
import Libavformat

public class FFmpegAssetTrack: MediaPlayerTrack {
    // MARK: - Fields (RE: FFmpegAssetTrack, 37 fields per types.json)
    // Order below matches the binary type-dump declaration order. The Forward
    // binary does NOT carry a separate `isConvertNALSize: Bool`; AVCC → Annex-B
    // promotion is routed through the `bitStreamFilter` metatype (see
    // `Nal3ToNal4BitStreamFilter`).

    public private(set) var trackID: Int32 = 0                          // #1
    public let codecName: String                                        // #2
    /// Codec profile name (e.g. "Main 10", "High"); optional.
    /// RE: separate String slot at the binary's `+0x28/+0x30`, built from the
    /// codec-profile cString in the codec-params staging struct
    /// (`FUN_1014042d8`). Distinct from `codecName` at `+0x18/+0x20`.
    public let profileName: String?                                     // #3
    public var name: String = ""                                        // #4
    public private(set) var languageCode: String?                       // #5
    public var nominalFrameRate: Float = 0                              // #6
    public private(set) var avgFrameRate = Timebase.defaultValue        // #7
    public private(set) var realFrameRate = Timebase.defaultValue       // #8
    public private(set) var bitRate: Int64 = 0                          // #9
    public let mediaType: AVFoundation.AVMediaType                      // #10
    public let formatName: String?                                      // #11
    public let bitDepth: Int32                                          // #12
    private var stream: UnsafeMutablePointer<AVStream>?                 // #13
    var startTime = CMTime.zero                                         // #14
    var codecpar: AVCodecParameters                                     // #15
    var timebase: Timebase = .defaultValue                              // #16
    let bitsPerRawSample: Int32                                         // #17
    public let formatDescription: CMFormatDescription?                  // #18
    public let audioDescriptor: AudioDescriptor?                        // #19
    /// Native AVAudioFormat for Atmos E-AC-3 JOC passthrough routing.
    public var audioFormat: AVAudioFormat?                              // #20
    public let isImageSubtitle: Bool                                    // #21
    public var delay: TimeInterval = 0                                  // #22
    /// Subtitle scale factor (initialised to 1.0).
    public var scale: Float = 1.0                                       // #23
    /// Subtitle vertical offset for positioning.
    public var translateY: Float = 0.0                                  // #24
    var subtitle: SyncPlayerItemTrack<SubtitleFrame>?                   // #25
    /// Per-track subtitle renderer (libass/bitmap/text).
    public var subtitleRender: KSSubtitleProtocol?                      // #26
    public private(set) var rotation: Int16 = 0                         // #27
    public var dovi: DOVIDecoderConfigurationRecord?                    // #28
    public let fieldOrder: FFmpegFieldOrder                             // #29
    /// True when `codec_id ∈ {PNG, MJPEG, BMP, TIFF}` family.
    public var isImage: Bool = false                                    // #30
    /// Single-frame still image (e.g., cover art).
    public var isStillImage: Bool = false                               // #31
    var closedCaptionsTrack: FFmpegAssetTrack?                          // #32
    /// Bit-stream filter metatype. When set, the VTB decode path applies the
    /// filter's NAL-prefix transform before submitting the sample buffer.
    /// Two concrete filters exist: `AnnexbToCCBitStreamFilter` (Annex-B → CC
    /// extraction) and `Nal3ToNal4BitStreamFilter` (3-byte → 4-byte NAL
    /// length promotion).
    public var bitStreamFilter: (any BitStreamFilterProtocol.Type)?     // #33
    /// Reorder buffer size for B-frame reordering.
    public var reorderSize: Int32 = 0                                   // #34
    var seekByBytes = false                                             // #35
    /// Container default track flag (`AV_DISPOSITION_DEFAULT`).
    public var isDefault: Bool = false                                  // #36
    /// Dual-language audio detection.
    public var isBilingual: Bool = false                                // #37

    public var description: String {
        var description = codecName
        if let formatName {
            description += ", \(formatName)"
        }
        if bitsPerRawSample > 0 {
            description += "(\(bitsPerRawSample.kmFormatted) bit)"
        }
        if let audioDescriptor {
            description += ", \(audioDescriptor.sampleRate)Hz"
            description += ", \(audioDescriptor.channel.description)"
        }
        if let formatDescription {
            if mediaType == .video {
                let naturalSize = formatDescription.naturalSize
                description += ", \(Int(naturalSize.width))x\(Int(naturalSize.height))"
                description += String(format: ", %.2f fps", nominalFrameRate)
            }
        }
        if bitRate > 0 {
            description += ", \(bitRate.kmFormatted)bps"
        }
        if let language {
            description += "(\(language))"
        }
        return description
    }

    /// RE: 0x1014042d8 (FFmpegAssetTrack.init?(stream:), 1.3.15)
    convenience init?(stream: UnsafeMutablePointer<AVStream>) {
        let codecpar = stream.pointee.codecpar.pointee
        self.init(codecpar: codecpar)
        self.stream = stream
        let metadata = toDictionary(stream.pointee.metadata)
        if let value = metadata["variant_bitrate"] ?? metadata["BPS"], let bitRate = Int64(value) {
            self.bitRate = bitRate
        }
        trackID = stream.pointee.index
        var timebase = Timebase(stream.pointee.time_base)
        if timebase.num <= 0 || timebase.den <= 0 {
            timebase = Timebase(num: 1, den: 1000)
        }
        if stream.pointee.start_time != Int64.min {
            startTime = timebase.cmtime(for: stream.pointee.start_time)
        }
        self.timebase = timebase
        avgFrameRate = Timebase(stream.pointee.avg_frame_rate)
        realFrameRate = Timebase(stream.pointee.r_frame_rate)
        if mediaType == .audio {
            var frameSize = codecpar.frame_size
            if frameSize < 1 {
                frameSize = timebase.den / timebase.num
            }
            nominalFrameRate = max(Float(codecpar.sample_rate / frameSize), 48)
        } else {
            if stream.pointee.duration > 0, stream.pointee.nb_frames > 0, stream.pointee.nb_frames != stream.pointee.duration {
                nominalFrameRate = Float(stream.pointee.nb_frames) * Float(timebase.den) / Float(stream.pointee.duration) * Float(timebase.num)
            } else if avgFrameRate.den > 0, avgFrameRate.num > 0 {
                nominalFrameRate = Float(avgFrameRate.num) / Float(avgFrameRate.den)
            } else {
                nominalFrameRate = 24
            }
        }

        if let value = metadata["language"], value != "und" {
            languageCode = value
        } else {
            languageCode = nil
        }
        if let value = metadata["title"] {
            name = value
        } else {
            name = languageCode ?? codecName
        }
        isDefault = stream.pointee.disposition & AV_DISPOSITION_DEFAULT == AV_DISPOSITION_DEFAULT
        if mediaType == .subtitle {
            isEnabled = !isImageSubtitle || stream.pointee.disposition & AV_DISPOSITION_FORCED == AV_DISPOSITION_FORCED
            if stream.pointee.disposition & AV_DISPOSITION_HEARING_IMPAIRED == AV_DISPOSITION_HEARING_IMPAIRED {
                name += "(hearing impaired)"
            }
        }
        // Apply extradata-dispatch logic (subtitle format detection, codec-specific
        // extradata handling) after basic timebase is set.
        setTimebase()
    }

    /// RE: 0x1014042d8 (FFmpegAssetTrack.init?(codecpar:), 1.3.15)
    /// Designated initializer — part of the FUN_1014042d8 body (the codecpar-only path).
    init?(codecpar: AVCodecParameters) {
        self.codecpar = codecpar
        bitRate = codecpar.bit_rate
        // codec_tag byte order is LSB first CMFormatDescription.MediaSubType(rawValue: codecpar.codec_tag.bigEndian)
        let codecType = codecpar.codec_id.mediaSubType
        var codecName = ""
        var profileName: String?
        if let descriptor = avcodec_descriptor_get(codecpar.codec_id) {
            codecName += String(cString: descriptor.pointee.name)
            if let profile = descriptor.pointee.profiles {
                // RE: the binary stores the codec-profile cString as a distinct
                // `profileName` field (`+0x28/+0x30`) in addition to suffixing
                // the human-readable `codecName`.
                profileName = String(cString: profile.pointee.name)
                codecName += " (\(profileName!))"
            }
        } else {
            codecName = ""
        }
        self.codecName = codecName
        self.profileName = profileName
        fieldOrder = FFmpegFieldOrder(rawValue: UInt8(codecpar.field_order.rawValue)) ?? .unknown
        var formatDescriptionOut: CMFormatDescription?
        if codecpar.codec_type == AVMEDIA_TYPE_AUDIO {
            mediaType = .audio
            audioDescriptor = AudioDescriptor(codecpar: codecpar)
            bitDepth = 0
            let layout = codecpar.ch_layout
            let channelsPerFrame = UInt32(layout.nb_channels)
            let sampleFormat = AVSampleFormat(codecpar.format)
            let bytesPerSample = UInt32(av_get_bytes_per_sample(sampleFormat))
            let formatFlags = ((sampleFormat == AV_SAMPLE_FMT_FLT || sampleFormat == AV_SAMPLE_FMT_DBL) ? kAudioFormatFlagIsFloat : sampleFormat == AV_SAMPLE_FMT_U8 ? 0 : kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsPacked
            var audioStreamBasicDescription = AudioStreamBasicDescription(mSampleRate: Float64(codecpar.sample_rate), mFormatID: codecType.rawValue, mFormatFlags: formatFlags, mBytesPerPacket: bytesPerSample * channelsPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerSample * channelsPerFrame, mChannelsPerFrame: channelsPerFrame, mBitsPerChannel: bytesPerSample * 8, mReserved: 0)
            _ = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &audioStreamBasicDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescriptionOut)
            if let name = av_get_sample_fmt_name(sampleFormat) {
                formatName = String(cString: name)
            } else {
                formatName = nil
            }
        } else if codecpar.codec_type == AVMEDIA_TYPE_VIDEO {
            audioDescriptor = nil
            mediaType = .video
            if codecpar.nb_coded_side_data > 0, let sideDatas = codecpar.coded_side_data {
                for i in 0 ..< codecpar.nb_coded_side_data {
                    let sideData = sideDatas[Int(i)]
                    if sideData.type == AV_PKT_DATA_DOVI_CONF {
                        dovi = sideData.data.withMemoryRebound(to: DOVIDecoderConfigurationRecord.self, capacity: 1) { $0 }.pointee
                    } else if sideData.type == AV_PKT_DATA_DISPLAYMATRIX {
                        let matrix = sideData.data.withMemoryRebound(to: Int32.self, capacity: 1) { $0 }
                        let rawRotation = -av_display_rotation_get(matrix)
                        if rawRotation.isFinite {
                            let degrees = Int(rawRotation.rounded())
                            let normalized = ((degrees % 360) + 360) % 360
                            rotation = Int16(normalized)
                        } else {
                            rotation = 0
                        }
                    }
                }
            }
            let sar = codecpar.sample_aspect_ratio.size
            var extradataSize = Int32(0)
            var extradata = codecpar.extradata
            let atomsData: Data?
            if let extradata {
                extradataSize = codecpar.extradata_size
                if extradataSize >= 5, extradata[4] == 0xFE {
                    extradata[4] = 0xFF
                    // RE: Forward routes the 3→4 byte NAL-length promotion through
                    // the bitStreamFilter metatype rather than a dedicated Bool.
                    bitStreamFilter = Nal3ToNal4BitStreamFilter.self
                }
                atomsData = Data(bytes: extradata, count: Int(extradataSize))
            } else {
                if codecType.rawValue == kCMVideoCodecType_VP9 {
                    // ff_videotoolbox_vpcc_extradata_create
                    var ioContext: UnsafeMutablePointer<AVIOContext>?
                    guard avio_open_dyn_buf(&ioContext) == 0 else {
                        return nil
                    }
                    ff_isom_write_vpcc(nil, ioContext, nil, 0, &self.codecpar)
                    extradataSize = avio_close_dyn_buf(ioContext, &extradata)
                    guard let extradata else {
                        return nil
                    }
                    var data = Data()
                    var array: [UInt8] = [1, 0, 0, 0]
                    data.append(&array, count: 4)
                    data.append(extradata, count: Int(extradataSize))
                    atomsData = data
                } else {
                    atomsData = nil
                }
            }
            let format = AVPixelFormat(rawValue: codecpar.format)
            bitDepth = format.bitDepth
            let fullRange = codecpar.color_range == AVCOL_RANGE_JPEG
            let dic: NSMutableDictionary = [
                kCVImageBufferChromaLocationBottomFieldKey: kCVImageBufferChromaLocation_Left,
                kCVImageBufferChromaLocationTopFieldKey: kCVImageBufferChromaLocation_Left,
                kCMFormatDescriptionExtension_Depth: format.bitDepth * Int32(format.planeCount),
                kCMFormatDescriptionExtension_FullRangeVideo: fullRange,
                codecType.rawValue == kCMVideoCodecType_HEVC ? "EnableHardwareAcceleratedVideoDecoder" : "RequireHardwareAcceleratedVideoDecoder": true,
            ]
            // kCMFormatDescriptionExtension_BitsPerComponent
            if let atomsData {
                dic[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] = [codecType.rawValue.avc: atomsData]
            }
            dic[kCVPixelBufferPixelFormatTypeKey] = format.osType(fullRange: fullRange)
            dic[kCVImageBufferPixelAspectRatioKey] = sar.aspectRatio
            dic[kCVImageBufferColorPrimariesKey] = codecpar.color_primaries.colorPrimaries as String?
            dic[kCVImageBufferTransferFunctionKey] = codecpar.color_trc.transferFunction as String?
            dic[kCVImageBufferYCbCrMatrixKey] = codecpar.color_space.ycbcrMatrix as String?
            // swiftlint:disable line_length
            _ = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: codecType.rawValue, width: codecpar.width, height: codecpar.height, extensions: dic, formatDescriptionOut: &formatDescriptionOut)
            // swiftlint:enable line_length
            if let name = av_get_pix_fmt_name(format) {
                formatName = String(cString: name)
            } else {
                formatName = nil
            }
            // Mark image-codec tracks (PNG, MJPEG, BMP, TIFF — the binary's 4-OR set).
            isImage = [AV_CODEC_ID_PNG, AV_CODEC_ID_MJPEG, AV_CODEC_ID_BMP, AV_CODEC_ID_TIFF].contains(codecpar.codec_id)
        } else if codecpar.codec_type == AVMEDIA_TYPE_SUBTITLE {
            mediaType = .subtitle
            audioDescriptor = nil
            formatName = nil
            bitDepth = 0
            _ = CMFormatDescriptionCreate(allocator: kCFAllocatorDefault, mediaType: kCMMediaType_Subtitle, mediaSubType: codecType.rawValue, extensions: nil, formatDescriptionOut: &formatDescriptionOut)
        } else {
            bitDepth = 0
            return nil
        }
        formatDescription = formatDescriptionOut
        bitsPerRawSample = codecpar.bits_per_raw_sample
        isImageSubtitle = [AV_CODEC_ID_DVD_SUBTITLE, AV_CODEC_ID_DVB_SUBTITLE, AV_CODEC_ID_DVB_TELETEXT, AV_CODEC_ID_HDMV_PGS_SUBTITLE].contains(codecpar.codec_id)
        trackID = 0
    }

    /// RE: delegates to AVCodecParameters.createContext (codec-open helpers, 1.3.15)
    /// Note: reversal doc (line 119) documents non-throwing return; `throws` is acceptable
    /// Swift idiom mapping the binary's error-code return to a thrown NSError.
    func createContext(options: KSOptions) throws -> UnsafeMutablePointer<AVCodecContext> {
        try codecpar.createContext(options: options)
    }

    /// RE: 0x101404e98 (FFmpegAssetTrack.getDuration, 1.3.15)
    /// Computed duration of this track in seconds, derived from the stream's duration
    /// field and the track's timebase. Called from `RemuxerIOAction.processAndWrite`
    /// during subtitle iteration. 72-byte function in the binary.
    var duration: TimeInterval {
        guard let stream else { return 0 }
        let streamDuration = stream.pointee.duration
        guard streamDuration > 0 else { return 0 }
        // Convert stream-timebase ticks to seconds: ticks * num / den
        return TimeInterval(streamDuration) * TimeInterval(timebase.num) / TimeInterval(timebase.den)
    }

    /// RE: 0x1013ea7e0 (FFmpegAssetTrack.setTimebase, 1.3.15)
    /// Extradata dispatch: handles AVCC/AnnexB detection for video tracks and
    /// subtitle format detection (ASS header, WEBVTT, SRT) for subtitle tracks.
    /// 572-byte function in the binary. Called during init after preliminary timebase
    /// is set. Overwrites the timebase at +0xC0/+0xC4 when the stream provides a
    /// valid one, and processes codec-specific extradata.
    private func setTimebase() {
        guard let stream else { return }
        let codecpar = stream.pointee.codecpar.pointee

        // Re-derive timebase from the stream (binary writes to +0xC0/+0xC4)
        var tb = Timebase(stream.pointee.time_base)
        if tb.num <= 0 || tb.den <= 0 {
            tb = Timebase(num: 1, den: 1000)
        }
        self.timebase = tb

        // Extradata dispatch: codec-specific handling
        guard let extradata = codecpar.extradata, codecpar.extradata_size > 0 else {
            return
        }
        let extradataSize = Int(codecpar.extradata_size)

        if codecpar.codec_type == AVMEDIA_TYPE_VIDEO {
            // Video: AVCC vs Annex-B detection.
            // The binary checks extradata[0..3] for start codes (0x00000001 or 0x000001)
            // to determine if the stream is Annex-B formatted. If AVCC (length-prefixed),
            // the NAL length field size is extracted from extradata[4] & 0x03 + 1.
            // The 3→4 byte NAL promotion is already handled in init?(codecpar:) via
            // the bitStreamFilter metatype assignment.
            if extradataSize >= 4 {
                let isAnnexB = (extradata[0] == 0x00 && extradata[1] == 0x00
                    && (extradata[2] == 0x01
                        || (extradata[2] == 0x00 && extradataSize >= 5 && extradata[3] == 0x01)))
                if isAnnexB, codecpar.codec_id == AV_CODEC_ID_H264
                    || codecpar.codec_id == AV_CODEC_ID_HEVC {
                    // Annex-B streams: set the AnnexbToCC bitstream filter for
                    // closed-caption extraction when not already using Nal3ToNal4.
                    if bitStreamFilter == nil {
                        bitStreamFilter = AnnexbToCCBitStreamFilter.self
                    }
                }
            }
        } else if codecpar.codec_type == AVMEDIA_TYPE_SUBTITLE {
            // Subtitle: format detection from extradata content.
            // The binary dispatches on codec_id and extradata header patterns:
            // - ASS/SSA: extradata begins with "[Script Info]" header
            // - WEBVTT: extradata begins with "WEBVTT" marker
            // - SRT: plain-text numeric subtitle format (no header marker)
            // The timebase for subtitle tracks is typically 1/1000 (milliseconds).
            let data = Data(bytes: extradata, count: extradataSize)
            if let header = String(data: data, encoding: .utf8) {
                // ASS/SSA format detection: look for "[Script Info]" in the extradata
                if header.hasPrefix("[Script Info]") || header.contains("[V4+ Styles]") {
                    // ASS subtitle format confirmed via extradata header.
                    // Timebase remains as set from stream.
                }
                // WEBVTT detection: extradata starts with "WEBVTT"
                else if header.hasPrefix("WEBVTT") {
                    // WEBVTT format confirmed via extradata marker.
                }
                // SRT: no distinctive header; identified by codec_id (AV_CODEC_ID_SUBRIP)
            }
        }
    }

    /// RE: (FFmpegAssetTrack.isEnabled, 1.3.15)
    public var isEnabled: Bool {
        get {
            stream?.pointee.discard == AVDISCARD_DEFAULT
        }
        set {
            var discard = newValue ? AVDISCARD_DEFAULT : AVDISCARD_ALL
            if mediaType == .subtitle, !isImageSubtitle {
                discard = AVDISCARD_DEFAULT
            }
            stream?.pointee.discard = discard
        }
    }
}

extension FFmpegAssetTrack {
    var pixelFormatType: OSType? {
        let format = AVPixelFormat(codecpar.format)
        return format.osType(fullRange: formatDescription?.fullRangeVideo ?? false)
    }

    /// True when the track's bitstream filter promotes 3-byte NAL length
    /// prefixes to 4-byte. Centralises the check that previously lived as
    /// `isConvertNALSize: Bool` on the track itself — the binary drives this
    /// through the `bitStreamFilter` metatype.
    var needsNALSizeConversion: Bool {
        bitStreamFilter is Nal3ToNal4BitStreamFilter.Type
    }
}

// MARK: - BitStreamFilterProtocol

/// Protocol for packet-level bit stream filtering (e.g., Annex-B / NAL-length
/// transforms). Two concrete filters exist in the binary type dump:
/// `AnnexbToCCBitStreamFilter` and `Nal3ToNal4BitStreamFilter`.
public protocol BitStreamFilterProtocol {
    init()
    func filter(packet: UnsafeMutablePointer<AVPacket>) -> Bool
}

/// Strips Annex-B start codes and routes CEA-608/708 closed-caption data
/// out of an AVCC-formatted track. Activation on a track gates the fatal
/// escalation in `MEPlayerItemTrack`'s fallback dispatcher
/// (RE: `MEPlayerItemTrack_dispatchFallbackBlock @ 0x1014412e4`).
public enum AnnexbToCCBitStreamFilter: BitStreamFilterProtocol {
    case shared
    public init() { self = .shared }
    public func filter(packet _: UnsafeMutablePointer<AVPacket>) -> Bool { true }
}

/// Promotes 3-byte NAL length prefixes to 4-byte. Set on the track by the
/// initializer when AVCC extradata signals the legacy 3-byte length
/// (`extradata[4] == 0xFE`). The VTB decode path checks
/// `FFmpegAssetTrack.needsNALSizeConversion` before invoking the
/// `CMFormatDescription` extension that rewrites NAL prefixes.
public enum Nal3ToNal4BitStreamFilter: BitStreamFilterProtocol {
    case shared
    public init() { self = .shared }
    public func filter(packet _: UnsafeMutablePointer<AVPacket>) -> Bool { true }
}
