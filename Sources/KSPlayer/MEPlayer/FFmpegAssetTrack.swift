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
    // MARK: - Fields (RE: FFmpegAssetTrack, 36 fields per types.json)
    // Order below matches the binary type-dump declaration order. The Forward
    // binary does NOT carry a separate `isConvertNALSize: Bool`; AVCC → Annex-B
    // promotion is routed through the `bitStreamFilter` metatype (see
    // `Nal3ToNal4BitStreamFilter`).

    public private(set) var trackID: Int32 = 0                          // #1
    public let codecName: String                                        // #2
    public var name: String = ""                                        // #3
    public private(set) var languageCode: String?                       // #4
    public var nominalFrameRate: Float = 0                              // #5
    public private(set) var avgFrameRate = Timebase.defaultValue        // #6
    public private(set) var realFrameRate = Timebase.defaultValue       // #7
    public private(set) var bitRate: Int64 = 0                          // #8
    public let mediaType: AVFoundation.AVMediaType                      // #9
    public let formatName: String?                                      // #10
    public let bitDepth: Int32                                          // #11
    private var stream: UnsafeMutablePointer<AVStream>?                 // #12
    var startTime = CMTime.zero                                         // #13
    var codecpar: AVCodecParameters                                     // #14
    var timebase: Timebase = .defaultValue                              // #15
    let bitsPerRawSample: Int32                                         // #16
    public let formatDescription: CMFormatDescription?                  // #17
    public let audioDescriptor: AudioDescriptor?                        // #18
    /// Native AVAudioFormat for Atmos E-AC-3 JOC passthrough routing.
    public var audioFormat: AVAudioFormat?                              // #19
    public let isImageSubtitle: Bool                                    // #20
    public var delay: TimeInterval = 0                                  // #21
    /// Subtitle scale factor (initialised to 1.0).
    public var scale: Float = 1.0                                       // #22
    /// Subtitle vertical offset for positioning.
    public var translateY: Float = 0.0                                  // #23
    var subtitle: SyncPlayerItemTrack<SubtitleFrame>?                   // #24
    /// Per-track subtitle renderer (libass/bitmap/text).
    public var subtitleRender: KSSubtitleProtocol?                      // #25
    public private(set) var rotation: Int16 = 0                         // #26
    public var dovi: DOVIDecoderConfigurationRecord?                    // #27
    public let fieldOrder: FFmpegFieldOrder                             // #28
    /// True when `codec_id ∈ {PNG, MJPEG, BMP, TIFF}` family.
    public var isImage: Bool = false                                    // #29
    /// Single-frame still image (e.g., cover art).
    public var isStillImage: Bool = false                               // #30
    var closedCaptionsTrack: FFmpegAssetTrack?                          // #31
    /// Bit-stream filter metatype. When set, the VTB decode path applies the
    /// filter's NAL-prefix transform before submitting the sample buffer.
    /// Two concrete filters exist: `AnnexbToCCBitStreamFilter` (Annex-B → CC
    /// extraction) and `Nal3ToNal4BitStreamFilter` (3-byte → 4-byte NAL
    /// length promotion).
    public var bitStreamFilter: (any BitStreamFilterProtocol.Type)?     // #32
    /// Reorder buffer size for B-frame reordering.
    public var reorderSize: Int32 = 0                                   // #33
    var seekByBytes = false                                             // #34
    /// Container default track flag (`AV_DISPOSITION_DEFAULT`).
    public var isDefault: Bool = false                                  // #35
    /// Dual-language audio detection.
    public var isBilingual: Bool = false                                // #36

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
        //        var buf = [Int8](repeating: 0, count: 256)
        //        avcodec_string(&buf, buf.count, codecpar, 0)
    }

    init?(codecpar: AVCodecParameters) {
        self.codecpar = codecpar
        bitRate = codecpar.bit_rate
        // codec_tag byte order is LSB first CMFormatDescription.MediaSubType(rawValue: codecpar.codec_tag.bigEndian)
        let codecType = codecpar.codec_id.mediaSubType
        var codecName = ""
        if let descriptor = avcodec_descriptor_get(codecpar.codec_id) {
            codecName += String(cString: descriptor.pointee.name)
            if let profile = descriptor.pointee.profiles {
                codecName += " (\(String(cString: profile.pointee.name)))"
            }
        } else {
            codecName = ""
        }
        self.codecName = codecName
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

    func createContext(options: KSOptions) throws -> UnsafeMutablePointer<AVCodecContext> {
        try codecpar.createContext(options: options)
    }

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
