//
//  AVFoundationExtension.swift
//
//
//  Created by kintan on 2023/1/9.
//

import AVFoundation
import CoreMedia
import FFmpegKit
import Libavutil

extension OSType {
    var bitDepth: Int32 {
        switch self {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange, kCVPixelFormatType_422YpCbCr10BiPlanarFullRange, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
            return 10
        default:
            return 8
        }
    }
}

extension CVPixelBufferPool {
    static func create(width: Int32, height: Int32, bytesPerRowAlignment: Int32, pixelFormatType: OSType, bufferCount: Int = 24) -> CVPixelBufferPool? {
        let sourcePixelBufferOptions: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferBytesPerRowAlignmentKey: bytesPerRowAlignment.alignment(value: 64),
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ]
        var outputPool: CVPixelBufferPool?
        let pixelBufferPoolOptions: NSDictionary = [kCVPixelBufferPoolMinimumBufferCountKey: bufferCount]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, pixelBufferPoolOptions, sourcePixelBufferOptions, &outputPool)
        return outputPool
    }
}

extension AudioUnit {
    var channelLayout: UnsafeMutablePointer<AudioChannelLayout> {
        var size = UInt32(0)
        AudioUnitGetPropertyInfo(self, kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, &size, nil)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int8>.alignment)
        AudioUnitGetProperty(self, kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, data, &size)
        let layout = data.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        let tag = layout.pointee.mChannelLayoutTag
        KSLog("[audio] unit tag: \(tag)")
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            KSLog("[audio] unit channelDescriptions: \(layout.channelDescriptions)")
            return layout
        }
        if tag == kAudioChannelLayoutTag_UseChannelBitmap {
            return layout.pointee.mChannelBitmap.channelLayout
        } else {
            let layout = tag.channelLayout
            KSLog("[audio] unit channelDescriptions: \(layout.channelDescriptions)")
            return layout
        }
    }
}

extension AudioChannelLayoutTag {
    var channelLayout: UnsafeMutablePointer<AudioChannelLayout> {
        var tag = self
        var size = UInt32(0)
        AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag, UInt32(MemoryLayout<AudioChannelLayoutTag>.size), &tag, &size)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int8>.alignment)
        AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, UInt32(MemoryLayout<AudioChannelLayoutTag>.size), &tag, &size, data)
        let newLayout = data.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        newLayout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        return newLayout
    }
}

extension AudioChannelBitmap {
    var channelLayout: UnsafeMutablePointer<AudioChannelLayout> {
        var mChannelBitmap = self
        var size = UInt32(0)
        AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForBitmap, UInt32(MemoryLayout<AudioChannelBitmap>.size), &mChannelBitmap, &size)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int8>.alignment)
        AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForBitmap, UInt32(MemoryLayout<AudioChannelBitmap>.size), &mChannelBitmap, &size, data)
        let newLayout = data.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        newLayout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        return newLayout
    }
}

extension UnsafePointer<AudioChannelLayout> {
    var channelDescriptions: [AudioChannelDescription] {
        UnsafeMutablePointer(mutating: self).channelDescriptions
    }
}

extension UnsafeMutablePointer<AudioChannelLayout> {
    var channelDescriptions: [AudioChannelDescription] {
        let n = pointee.mNumberChannelDescriptions
        return withUnsafeMutablePointer(to: &pointee.mChannelDescriptions) { start in
            let buffers = UnsafeBufferPointer<AudioChannelDescription>(start: start, count: Int(n))
            return (0 ..< Int(n)).map {
                buffers[$0]
            }
        }
    }
}

extension AudioChannelLayout: CustomStringConvertible {
    public var description: String {
        "AudioChannelLayoutTag=\(mChannelLayoutTag), mNumberChannelDescriptions=\(mNumberChannelDescriptions)"
    }
}

extension AVAudioChannelLayout {
    func channelLayout() -> AVChannelLayout {
        KSLog("[audio] channelLayout: \(layout.pointee.description)")
        var mask: UInt64?
        if layoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
            var newMask = UInt64(0)
            for description in layout.channelDescriptions {
                let label = description.mChannelLabel
                KSLog("[audio] label: \(label)")
                let channel = label.avChannel.rawValue
                KSLog("[audio] avChannel: \(channel)")
                if channel >= 0 {
                    newMask |= 1 << channel
                }
            }
            mask = newMask
        } else {
            mask = layoutMapTuple.first { tag, _ in
                tag == layoutTag
            }?.mask
        }
        var outChannel = AVChannelLayout()
        if let mask {
            // 不能用AV_CHANNEL_ORDER_CUSTOM
            av_channel_layout_from_mask(&outChannel, mask)
        } else {
            av_channel_layout_default(&outChannel, Int32(channelCount))
        }
        KSLog("[audio] out mask: \(outChannel.u.mask) nb_channels: \(outChannel.nb_channels)")
        return outChannel
    }

    public var channelDescriptions: String {
        "tag=\(layoutTag), channelDescriptions=\(layout.channelDescriptions)"
    }
}

extension AVAudioFormat {
    var sampleFormat: AVSampleFormat {
        switch commonFormat {
        case .pcmFormatFloat32:
            return isInterleaved ? AV_SAMPLE_FMT_FLT : AV_SAMPLE_FMT_FLTP
        case .pcmFormatFloat64:
            return isInterleaved ? AV_SAMPLE_FMT_DBL : AV_SAMPLE_FMT_DBLP
        case .pcmFormatInt16:
            return isInterleaved ? AV_SAMPLE_FMT_S16 : AV_SAMPLE_FMT_S16P
        case .pcmFormatInt32:
            return isInterleaved ? AV_SAMPLE_FMT_S32 : AV_SAMPLE_FMT_S32P
        case .otherFormat:
            return isInterleaved ? AV_SAMPLE_FMT_FLT : AV_SAMPLE_FMT_FLTP
        @unknown default:
            return isInterleaved ? AV_SAMPLE_FMT_FLT : AV_SAMPLE_FMT_FLTP
        }
    }

    var layout: UnsafePointer<AudioChannelLayout>? { channelLayout?.layout }
    var sampleSize: UInt32 {
        switch commonFormat {
        case .pcmFormatFloat32:
            return isInterleaved ? channelCount * 4 : 4
        case .pcmFormatFloat64:
            return isInterleaved ? channelCount * 8 : 8
        case .pcmFormatInt16:
            return isInterleaved ? channelCount * 2 : 2
        case .pcmFormatInt32:
            return isInterleaved ? channelCount * 4 : 4
        case .otherFormat:
            return isInterleaved ? channelCount * 4 : channelCount * 4
        @unknown default:
            return isInterleaved ? channelCount * 4 : channelCount * 4
        }
    }

    func isChannelEqual(_ object: AVAudioFormat) -> Bool {
        sampleRate == object.sampleRate && channelCount == object.channelCount && commonFormat == object.commonFormat && sampleRate == object.sampleRate && isInterleaved == object.isInterleaved
    }
}

let layoutMapTuple =
    [(tag: kAudioChannelLayoutTag_Mono, mask: swift_AV_CH_LAYOUT_MONO),
     (tag: kAudioChannelLayoutTag_Stereo, mask: swift_AV_CH_LAYOUT_STEREO),
     (tag: kAudioChannelLayoutTag_WAVE_2_1, mask: swift_AV_CH_LAYOUT_2POINT1),
     (tag: kAudioChannelLayoutTag_ITU_2_1, mask: swift_AV_CH_LAYOUT_2_1),
     (tag: kAudioChannelLayoutTag_MPEG_3_0_A, mask: swift_AV_CH_LAYOUT_SURROUND),
     (tag: kAudioChannelLayoutTag_DVD_10, mask: swift_AV_CH_LAYOUT_3POINT1),
     (tag: kAudioChannelLayoutTag_Logic_4_0_A, mask: swift_AV_CH_LAYOUT_4POINT0),
     (tag: kAudioChannelLayoutTag_Logic_Quadraphonic, mask: swift_AV_CH_LAYOUT_2_2),
     (tag: kAudioChannelLayoutTag_WAVE_4_0_B, mask: swift_AV_CH_LAYOUT_QUAD),
     (tag: kAudioChannelLayoutTag_DVD_11, mask: swift_AV_CH_LAYOUT_4POINT1),
     (tag: kAudioChannelLayoutTag_Logic_5_0_A, mask: swift_AV_CH_LAYOUT_5POINT0),
     (tag: kAudioChannelLayoutTag_WAVE_5_0_B, mask: swift_AV_CH_LAYOUT_5POINT0_BACK),
     (tag: kAudioChannelLayoutTag_Logic_5_1_A, mask: swift_AV_CH_LAYOUT_5POINT1),
     (tag: kAudioChannelLayoutTag_WAVE_5_1_B, mask: swift_AV_CH_LAYOUT_5POINT1_BACK),
     (tag: kAudioChannelLayoutTag_Logic_6_0_A, mask: swift_AV_CH_LAYOUT_6POINT0),
     (tag: kAudioChannelLayoutTag_DTS_6_0_A, mask: swift_AV_CH_LAYOUT_6POINT0_FRONT),
     (tag: kAudioChannelLayoutTag_DTS_6_0_C, mask: swift_AV_CH_LAYOUT_HEXAGONAL),
     (tag: kAudioChannelLayoutTag_Logic_6_1_C, mask: swift_AV_CH_LAYOUT_6POINT1),
     (tag: kAudioChannelLayoutTag_DTS_6_1_A, mask: swift_AV_CH_LAYOUT_6POINT1_FRONT),
     (tag: kAudioChannelLayoutTag_DTS_6_1_C, mask: swift_AV_CH_LAYOUT_6POINT1_BACK),
     (tag: kAudioChannelLayoutTag_AAC_7_0, mask: swift_AV_CH_LAYOUT_7POINT0),
     (tag: kAudioChannelLayoutTag_Logic_7_1_A, mask: swift_AV_CH_LAYOUT_7POINT1),
     (tag: kAudioChannelLayoutTag_Logic_7_1_SDDS_A, mask: swift_AV_CH_LAYOUT_7POINT1_WIDE),
     (tag: kAudioChannelLayoutTag_AAC_Octagonal, mask: swift_AV_CH_LAYOUT_OCTAGONAL),
     //     (tag: kAudioChannelLayoutTag_Logic_Atmos_5_1_2, mask: swift_AV_CH_LAYOUT_7POINT1_WIDE_BACK),
    ]

// Some channel abbreviations used below:
// Lss - left side surround
// Rss - right side surround
// Leos - Left edge of screen
// Reos - Right edge of screen
// Lbs - Left back surround
// Rbs - Right back surround
// Lt - left matrix total. for matrix encoded stereo.
// Rt - right matrix total. for matrix encoded stereo.

extension AudioChannelLabel {
    var avChannel: AVChannel {
        switch self {
        case kAudioChannelLabel_Left:
            // L - left
            return AV_CHAN_FRONT_LEFT
        case kAudioChannelLabel_Right:
            // R - right
            return AV_CHAN_FRONT_RIGHT
        case kAudioChannelLabel_Center:
            // C - center
            return AV_CHAN_FRONT_CENTER
        case kAudioChannelLabel_LFEScreen:
            // Lfe
            return AV_CHAN_LOW_FREQUENCY
        case kAudioChannelLabel_LeftSurround:
            // Ls - left surround
            return AV_CHAN_SIDE_LEFT
        case kAudioChannelLabel_RightSurround:
            // Rs - right surround
            return AV_CHAN_SIDE_RIGHT
        case kAudioChannelLabel_LeftCenter:
            // Lc - left center
            return AV_CHAN_FRONT_LEFT_OF_CENTER
        case kAudioChannelLabel_RightCenter:
            // Rc - right center
            return AV_CHAN_FRONT_RIGHT_OF_CENTER
        case kAudioChannelLabel_CenterSurround:
            // Cs - center surround "Back Center" or plain "Rear Surround"
            return AV_CHAN_BACK_CENTER
        case kAudioChannelLabel_LeftSurroundDirect:
            // Lsd - left surround direct
            return AV_CHAN_SURROUND_DIRECT_LEFT
        case kAudioChannelLabel_RightSurroundDirect:
            // Rsd - right surround direct
            return AV_CHAN_SURROUND_DIRECT_RIGHT
        case kAudioChannelLabel_TopCenterSurround:
            // Ts - top surround
            return AV_CHAN_TOP_CENTER
        case kAudioChannelLabel_VerticalHeightLeft:
            // Vhl - vertical height left Top Front Left
            return AV_CHAN_TOP_FRONT_LEFT
        case kAudioChannelLabel_VerticalHeightCenter:
            // Vhc - vertical height center Top Front Center
            return AV_CHAN_TOP_FRONT_CENTER
        case kAudioChannelLabel_VerticalHeightRight:
            // Vhr - vertical height right Top Front right
            return AV_CHAN_TOP_FRONT_RIGHT
        case kAudioChannelLabel_TopBackLeft:
            // Ltr - left top rear
            return AV_CHAN_TOP_BACK_LEFT
        case kAudioChannelLabel_TopBackCenter:
            // Ctr - center top rear
            return AV_CHAN_TOP_BACK_CENTER
        case kAudioChannelLabel_TopBackRight:
            // Rtr - right top rear
            return AV_CHAN_TOP_BACK_RIGHT
        case kAudioChannelLabel_RearSurroundLeft:
            // Rls - rear left surround
            return AV_CHAN_BACK_LEFT
        case kAudioChannelLabel_RearSurroundRight:
            // Rrs - rear right surround
            return AV_CHAN_BACK_RIGHT
        case kAudioChannelLabel_LeftWide:
            // Lw - left wide
            return AV_CHAN_WIDE_LEFT
        case kAudioChannelLabel_RightWide:
            // Rw - right wide
            return AV_CHAN_WIDE_RIGHT
        case kAudioChannelLabel_LFE2:
            // LFE2
            return AV_CHAN_LOW_FREQUENCY_2
        case kAudioChannelLabel_Mono:
            // C - center
            return AV_CHAN_FRONT_CENTER
        case kAudioChannelLabel_LeftTopMiddle:
            // Ltm - left top middle
            return AV_CHAN_NONE
        case kAudioChannelLabel_RightTopMiddle:
            // Rtm - right top middle
            return AV_CHAN_NONE
        case kAudioChannelLabel_LeftTopSurround:
            // Lts - Left top surround
            return AV_CHAN_TOP_SIDE_LEFT
        case kAudioChannelLabel_RightTopSurround:
            // Rts - Right top surround
            return AV_CHAN_TOP_SIDE_RIGHT
        case kAudioChannelLabel_LeftBottom:
            // Lb - left bottom
            return AV_CHAN_BOTTOM_FRONT_LEFT
        case kAudioChannelLabel_RightBottom:
            // Rb - Right bottom
            return AV_CHAN_BOTTOM_FRONT_RIGHT
        case kAudioChannelLabel_CenterBottom:
            // Cb - Center bottom
            return AV_CHAN_BOTTOM_FRONT_CENTER
        case kAudioChannelLabel_HeadphonesLeft:
            return AV_CHAN_STEREO_LEFT
        case kAudioChannelLabel_HeadphonesRight:
            return AV_CHAN_STEREO_RIGHT
        default:
            return AV_CHAN_NONE
        }
    }
}

// PacketNalData @0x1039ee6a4 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=PacketNalData:0x1039ee6a4 result=struct PacketNalData]
// ⚑[tool=field_surface ref=PacketNalData+NALUnit:fieldmd result=1 let / 3 let] Lazy owner (no build metadata); fields follow
// Forward's record order, IsVar bits and resolved types.
struct PacketNalData {
    let nals: [PacketNalData.NALUnit]

    struct NALUnit {
        let type: PacketNalData.NALType
        let start: Int
        let count: Int
    }

    enum NALType: CustomStringConvertible, Equatable {
        case h264(H264NALUnitType)
        case h265(HEVCNALUnitType)
        case vp9(VP9FrameType)
        case av1(AV1OBUType)
        case sei(UInt16)
        case unknown(UInt8)
        var description: String {
            switch self {
            case let .h264(type):
                return type.description
            case let .h265(type):
                return type.description
            case let .vp9(type):
                return type.description
            case let .av1(type):
                return type.description
            case let .sei(type):
                return "sei \(type)"
            case let .unknown(type):
                return "Unknown NAL type \(type)"
            }
        }
    }
}

// H264NALUnitType @0x1039ee6f8 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=H264NALUnitType:0x1039ee6f8 result=enum H264NALUnitType: UInt8]
enum H264NALUnitType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case unspecified0, slice, dpa, dpb, dpc, idrSlice, sei, sps, pps, aud, endSequence, endStream, fillerData, spsExt, prefix, subSPS, dps, reserved17, reserved18, auxSlice, extSlice, depthExtSlice, reserved22, reserved23, unspecified24, unspecified25, unspecified26, unspecified27, unspecified28, unspecified29, unspecified30, unspecified31
    var description: String { "h264 \(self) (\(rawValue))" }
}

// HEVCNALUnitType @0x1039ee714 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=HEVCNALUnitType:0x1039ee714 result=enum HEVCNALUnitType: UInt8]
enum HEVCNALUnitType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case trailN, trailR, tsaN, tsaR, stsaN, stsaR, radlN, radlR, raslN, raslR, vclN10, vclR11, vclN12, vclR13, vclN14, vclR15, blaWLp, blaWRadl, blaNLp, idrWRadl, idrNLp, craNut, rsvIrapVcl22, rsvIrapVcl23, rsvVcl24, rsvVcl25, rsvVcl26, rsvVcl27, rsvVcl28, rsvVcl29, rsvVcl30, rsvVcl31, vps, sps, pps, aud, eosNut, eobNut, fdNut, seiPrefix, seiSuffix, rsvNvcl41, rsvNvcl42, rsvNvcl43, rsvNvcl44, rsvNvcl45, rsvNvcl46, rsvNvcl47, unspec48, unspec49, unspec50, unspec51, unspec52, unspec53, unspec54, unspec55, unspec56, unspec57, unspec58, unspec59, unspec60, unspec61, unspec62, unspec63
    var description: String { "hevc \(self) (\(rawValue))" }
}

// VP9FrameType @0x1039ee730 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=VP9FrameType:0x1039ee730 result=enum VP9FrameType: UInt8]
enum VP9FrameType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case keyFrame, interFrame
    var description: String { "vp9 \(self) (\(rawValue))" }
}

// AV1OBUType @0x1039ee74c — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=AV1OBUType:0x1039ee74c result=enum AV1OBUType: UInt8]
enum AV1OBUType: UInt8 {
    // L7 lane 13: Forward raw-value table @0x103569fca = 0…8, 15 (padding = 15).
    case reserved0, sequenceHeader, temporalDelimiter, frameHeader, tileGroup, metadata, frame, redundantFrameHeader, tileList
    case padding = 15
    var description: String { "av1 \(self) (\(rawValue))" }
}

extension AVPacket {
    var timestamp: Int64 { @used get {
        if pts != Int64.min {
            return pts
        }
        if dts != Int64.min {
            return dts
        }
        return 0
    } }
    var isKeyFrame: Bool { @used get {
        flags & AV_PKT_FLAG_KEY != 0
    } }
}
