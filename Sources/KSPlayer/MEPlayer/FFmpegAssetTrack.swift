//
//  FFmpegAssetTrack.swift
//  KSPlayer
//
//  Created by kintan on 2023/2/12.
//

import AVFoundation
import FFmpegKit
import Libavformat

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

public class FFmpegAssetTrack: MediaPlayerTrack {
    // ⚑ Field-layout migration (session 37, commit-1): the 37 stored properties in Forward binary order
    //   (scripts/dump_binary_field_types.py FFmpegAssetTrack). NEW fields carry safe defaults = the
    //   confirmed unconditional prologue init values (scale 1.0, translateY 0) or ⚑ nil/false pending
    //   branch-conditional population (audit-gated commit-2). `codecpar` retyped value→pointer (+0xb8).
    //   `isConvertNALSize` is source-only (Forward dropped it; l2 WARNs extra, non-blocking) — kept
    //   trailing, read by the H.264 NAL-size path.
    public private(set) var trackID: Int32 = 0
    public let codecName: String
    public var profileName: String?                        // ⚑ 3 NEW · init population deferred (codec profile name via FUN_102e676a0); layout-first nil
    public var name: String = ""
    public private(set) var languageCode: String?
    public var nominalFrameRate: Float = 0
    public private(set) var avgFrameRate = Timebase.defaultValue
    public private(set) var realFrameRate = Timebase.defaultValue
    public private(set) var bitRate: Int64 = 0
    public let mediaType: AVFoundation.AVMediaType
    public let formatName: String?
    public let bitDepth: Int32
    public var stream: UnsafeMutablePointer<AVStream>?
    package var startTime = CMTime.zero        // ⚑ package (Forward-fidelity): RemuxerIOAction (ProAVPlayer module) reads this cross-module — binary-arbitrated; exact modifier under-included §1 (could be public)
    public var codecpar: UnsafeMutablePointer<AVCodecParameters>   // ⚑ retyped value→pointer (+0xb8); designated init derefs via `let codecpar = codecparPtr.pointee`
    package var timebase: Timebase = .defaultValue  // ⚑ package: see startTime — cross-module read by RemuxerIOAction.performRead/ptsToSeconds (FUN_101a32e28)  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
    let bitsPerRawSample: Int32
    public let formatDescription: CMFormatDescription?   // moved up to bin +0xd0 (before audioDescriptor)
    public let audioDescriptor: AudioDescriptor?
    public var audioFormat: AVAudioFormat?                 // ⚑ 20 NEW · init population deferred (audio branch AVAudioFormat(cmAudioFormatDescription:))
    public let isImageSubtitle: Bool
    public var delay: TimeInterval = 0
    public var scale: Float = 1.0                          // ⚑ 23 NEW · prologue init 1.0 (0x3f800000) — confirmed unconditional
    public var translateY: Float = 0                       // ⚑ 24 NEW · prologue init 0 — confirmed unconditional
    var subtitle: SyncPlayerItemTrack<SubtitleFrame>?
    public var subtitleRender: (any KSSubtitleProtocol)?   // ⚑ 26 NEW · 40b optional existential (+0x108..+0x130); protocol resolved via name_type_at_addr
    public private(set) var rotation: Int16 = 0     // ⚑ bin field-record reads UInt16 (unmapped/UNCHECKED); kept Int16 — MediaPlayerProtocol requires `var rotation: Int16`, layout-identical (2b)
    public var dovi: DOVIDecoderConfigurationRecord?
    public let fieldOrder: FFmpegFieldOrder
    public var isImage: Bool = false                       // ⚑ 30 NEW · init population deferred (disposition/side-data)
    public var isStillImage: Bool = false                  // ⚑ 31 NEW · init population deferred
    var closedCaptionsTrack: FFmpegAssetTrack?
    // ⚑[tool=export_trie_oracle ref=FFmpegAssetTrack.bitStreamFilter result=TYPE DIVERGENCE — the binary spells this
    //   `KSPlayer.BitStreamFilter.Type?`, a METATYPE, where this declares `(any BitStreamFilter & AnyObject)?`, an
    //   existential. Those are different things; changing it rewrites every use site, so it is PINNED as its own unit]
    public var bitStreamFilter: (any BitStreamFilter & AnyObject)?   // ⚑ 33 NEW · 16b class-existential (+0x148..+0x158); BitStreamFilter Forward-added (declared above)
    public var reorderSize: Int32 = 0                      // ⚑ 34 NEW · init param[0x1e]; population deferred
    var seekByBytes = false
    public var isDefault: Bool = false                     // ⚑ 36 NEW · init population deferred (disposition)
    public var isBilingual: Bool = false                   // ⚑ 37 NEW · init population deferred
    let isConvertNALSize: Bool                      // ⚑ source-only: Forward dropped this stored field (binary lacks it; l2 WARNs extra, non-blocking). Kept — read by H.264 NAL-size path.
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
        self.init(codecpar: stream.pointee.codecpar)   // ⚑ pass the pointer (stored field retyped +0xb8); local `codecpar` value serves the reads below
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
        // AV_DISPOSITION_DEFAULT
        if mediaType == .subtitle {
            isEnabled = !isImageSubtitle || stream.pointee.disposition & AV_DISPOSITION_FORCED == AV_DISPOSITION_FORCED
            if stream.pointee.disposition & AV_DISPOSITION_HEARING_IMPAIRED == AV_DISPOSITION_HEARING_IMPAIRED {
                name += "(hearing impaired)"
            }
        }
        //        var buf = [Int8](repeating: 0, count: 256)
        //        avcodec_string(&buf, buf.count, codecpar, 0)
    }

    init?(codecpar codecparPtr: UnsafeMutablePointer<AVCodecParameters>) {
        self.codecpar = codecparPtr
        let codecpar = codecparPtr.pointee   // ⚑ local value copy keeps the dense codecpar.X reads unchanged; stored field is the pointer (+0xb8)
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
            isConvertNALSize = false
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
            let extradata = codecpar.extradata
            let atomsData: Data?
            if let extradata {
                extradataSize = codecpar.extradata_size
                if extradataSize >= 5, extradata[4] == 0xFE {
                    extradata[4] = 0xFF
                    isConvertNALSize = true
                } else {
                    isConvertNALSize = false
                }
                atomsData = Data(bytes: extradata, count: Int(extradataSize))
            } else {
                // ⚑ REMOVED (session 37): the base VP9-synthetic-extradata path (avio_open_dyn_buf →
                //   the vpcC-box writer → avio_close_dyn_buf) is PROVEN dead-in-Forward — the designated init
                //   FUN_101a202a8 omits all three from its callee set, and the vpcC-box WRITER (libavformat's
                //   isom vpcc writer) is absent from the binary: only the READER FUN_1031606b0 survives, and no
                //   vpcC fourcc-immediate appears in code. Removing it keeps this layout commit gate-clean with
                //   no fabricated FFmpeg marker (the deleted call is a `-` line the diff-scoped gate ignores).
                //   ⚑ FAITHFUL-PARTIAL: proven Forward does NOT synthesize VP9 extradata via that writer; NOT
                //   proven it does nothing else for VP9-without-extradata → `atomsData = nil` is the minimal
                //   faithful form; exact VP9-no-extradata handling deferred to the init-body pass (commit-2).
                //   ⚑[tool=get_function_callees ref=isom_vpcc_writer:absent-in-FUN_101a202a8 result=FAILED-SEARCH] (writer confirmed dead-stripped; only the reader survives)
                atomsData = nil
                isConvertNALSize = false
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
        } else if codecpar.codec_type == AVMEDIA_TYPE_SUBTITLE {
            mediaType = .subtitle
            audioDescriptor = nil
            formatName = nil
            bitDepth = 0
            isConvertNALSize = false
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

    // ⚑ P55 (session 32): `options: KSOptions?` — SubtitleDecode.init forwards a nullable options through here
    //   (binary FUN_101a6914c → this createContext with nullable options); codecpar.createContext is already KSOptions?.  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    func createContext(options: KSOptions?) throws -> UnsafeMutablePointer<AVCodecContext> {
        try codecpar.pointee.createContext(options: options)
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
        let format = AVPixelFormat(codecpar.pointee.format)
        return format.osType(fullRange: formatDescription?.fullRangeVideo ?? false)
    }
}
