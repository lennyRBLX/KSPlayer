//
//  AVFoundationExtension.swift
//
//
//  Created by kintan on 2023/1/9.
//

import AVFoundation
import CoreMedia
import FFmpegKit
import Libavcodec
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

// L7 lane 18: Forward places the CMFormatDescription extension (bitDepth … hevcExtradata, ending @0x101a0bc60)
// and the NAL cluster below in this file: its code runs 0x101a0aac0..0x101a0dc14, after AVFFmpegExtension.swift
// (ends ~0x101a0aa5c) and before AudioEnginePlayer.swift (0x101a0dc18) in sorted-path .o order, and Forward has
// no NALUnitParser.swift.
// L7 lane 22: the sibling members move here from MediaPlayerProtocol.swift, in Forward address order: bitDepth
// 0x101a0aac0, dynamicRange 0x101a0abb4, naturalSize 0x101a0aeac, colorPrimaries/transferFunction/yCbCrMatrix
// 0x101a0af48..0x101a0af6c (3-insn tails into one merged body), codecType 0x101a0b470, aspectRatio 0x101a0b4f4,
// displaySize 0x101a0b744, depth 0x101a0b904, fullRangeVideo 0x101a0b9cc, hevcExtradata 0x101a0ba94.
extension CMFormatDescription {
    public var bitDepth: Int32 {
        codecType.bitDepth
    }

    public var dynamicRange: DynamicRange {
        let contentRange: DynamicRange
        if codecType.string == "dvhe" || codecType == kCMVideoCodecType_DolbyVisionHEVC {
            contentRange = .dolbyVision
        } else if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { /// HDR
            // Forward @0x101a0abb4 has no bitDepth test: dvhe/dvh1 → PQ → HLG → (no transfer, BT.2020) → SDR.
            contentRange = .hdr10
        } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { /// HLG
            contentRange = .hlg
        } else if transferFunction == nil, colorPrimaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String {
            contentRange = .hlg
        } else {
            contentRange = .sdr
        }
        return contentRange
    }

    public var naturalSize: CGSize {
        let aspectRatio = aspectRatio
        return CGSize(width: Int(dimensions.width), height: Int(CGFloat(dimensions.height) * aspectRatio.height / aspectRatio.width))
    }

    public var colorPrimaries: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferColorPrimariesKey] as? String
        } else {
            return nil
        }
    }

    public var transferFunction: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferTransferFunctionKey] as? String
        } else {
            return nil
        }
    }

    public var yCbCrMatrix: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferYCbCrMatrixKey] as? String
        } else {
            return nil
        }
    }

    public var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    public var aspectRatio: CGSize {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            if let ratio = dictionary[kCVImageBufferPixelAspectRatioKey] as? NSDictionary,
               let horizontal = (ratio[kCVImageBufferPixelAspectRatioHorizontalSpacingKey] as? NSNumber)?.intValue,
               let vertical = (ratio[kCVImageBufferPixelAspectRatioVerticalSpacingKey] as? NSNumber)?.intValue,
               horizontal > 0, vertical > 0
            {
                return CGSize(width: horizontal, height: vertical)
            }
        }
        return CGSize(width: 1, height: 1)
    }

    /// @0x101a0b744 — extensions → DisplayWidth/DisplayHeight NSNumber.integerValue; both > 0 → size, else nil.
    public var displaySize: CGSize? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary?,
           let width = (dictionary[kCVImageBufferDisplayWidthKey] as? NSNumber)?.intValue,
           let height = (dictionary[kCVImageBufferDisplayHeightKey] as? NSNumber)?.intValue,
           width > 0, height > 0
        {
            return CGSize(width: width, height: height)
        }
        return nil
    }

    public var depth: Int32 {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_Depth] as? Int32 ?? 24
        } else {
            return 24
        }
    }

    public var fullRangeVideo: Bool {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_FullRangeVideo] as? Bool ?? false
        } else {
            return false
        }
    }

    /// @0x101a0ba94 — extensions as? [String: Any] → "SampleDescriptionExtensionAtoms" as? [String: Any] → "hvcC" as? Data.
    public var hevcExtradata: Data? {
        // Forward @0x101a0bc58: the `as? Data` failure `tbz`s to the shared nil return (no csel),
        // so the Data cast is the third binding of the chain, not a returned `as?`.
        if let extensions = CMFormatDescriptionGetExtensions(self) as? [String: Any],
           let atoms = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any],
           let hvcC = atoms["hvcC"] as? Data
        {
            return hvcC
        }
        return nil
    }
}

// L7 lane 21: the two helpers Forward places between hevcExtradata (ends @0x101a0bc60) and the helper below
// (@0x101a0be50), moved here from VideoToolboxDecode.swift.
extension CMFormatDescription {
    // ⚑ REMOVED (s106): the `isConvertNALSize` parameter and the AVCC→AnnexB rewrite it guarded
    //   (avio_open_dyn_buf → avio_wb32/avio_write → avio_close_dyn_buf); decodeFrame calls no avio_*.
    //   ⚑[tool=llvm-objdump ref=VideoToolboxDecode.decodeFrame:0x101a6ce44-0x101a6d734 result=no-avio-callee]
    /// @0x101a0bc64 (no symbol; called out of line from VideoToolboxDecode.decodeFrame). One body, no private
    /// wrapper: CMBlockBufferCreateWithMemoryBlock → CMSampleBufferCreateReady (@0x101a0bd5c: allocator,
    /// dataBuffer, self, 1, 0, nil, 0, nil, &out); both failure edges converge on one throw @0x101a0bcd4 with the
    /// live failing OSStatus and the 33-char codecVideoReceiveFrame text.
    func getSampleBuffer(data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var sampleBuffer: CMSampleBuffer?
        // swiftlint:disable line_length
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: size, blockAllocator: kCFAllocatorNull, customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &blockBuffer)
        if status == noErr {
            status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: self, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer {
                return sampleBuffer
            }
        }
        throw KSPlayerError(code: status, description: KSPlayerErrorCode.codecVideoReceiveFrame.rawValue)
        // swiftlint:enable line_length
    }
}

extension CMVideoCodecType {
    /// @0x101a0bda8 — Forward compares 'av01' → "av1C", 'hvc1' → "hvcC", 'mp4v' → "esds", 'vp09' → "vpcC",
    /// else "avcC" (the H264 case folds into the default).
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
        case kCMVideoCodecType_AV1:
            return "av1C"
        default: return "avcC"
        }
    }
}

/// ⚑ NAME INFERRED — Forward 0x101a0be50 (no symbol). x0 data, x1 nalUnitHeaderLength, x2 nalUnits; no self,
/// so it is written as a free func (owner undecidable). Called from KSOptions.makeDecode (@0x1019b6448..)
/// and FFmpegUtility.write (@0x101a1e144).
/// Three separate first-where scans (tag 1 = .h265, value 0x20/0x21/0x22) → nil on the first miss;
/// `formatDescription = nil` is stored only after the scans (@0x101a0bf10); pointers are unchecked
/// `data + start`; sizes are `count`; Int32(nalUnitHeaderLength) traps both ways (@0x101a0bf30..); the two
/// arrays are stack-promoted literals.
func formatDescription(data: UnsafePointer<UInt8>, nalUnitHeaderLength: Int, nalUnits: [PacketNalData.NALUnit]) -> CMFormatDescription? {
    guard let vps = nalUnits.first(where: { $0.type == .h265(.vps) }),
          let sps = nalUnits.first(where: { $0.type == .h265(.sps) }),
          let pps = nalUnits.first(where: { $0.type == .h265(.pps) })
    else {
        return nil
    }
    var formatDescription: CMFormatDescription?
    let parameterSetPointers = [data + vps.start, data + sps.start, data + pps.start]
    let parameterSetSizes = [vps.count, sps.count, pps.count]
    _ = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: parameterSetPointers, parameterSetSizes: parameterSetSizes, nalUnitHeaderLength: Int32(nalUnitHeaderLength), extensions: nil, formatDescriptionOut: &formatDescription)
    return formatDescription
}

// L7 lane 18: Forward emits AVPacket.timestamp @0x101a0bfb0 / isKeyFrame @0x101a0bfd0 before the
// PacketNalData helpers (0x101a0bfdc..), so this extension precedes PacketNalData.
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

// PacketNalData @0x1039ee6a4 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=PacketNalData:0x1039ee6a4 result=struct PacketNalData]
// ⚑[tool=field_surface ref=PacketNalData+NALUnit:fieldmd result=1 let / 3 let] Lazy owner (no build metadata); fields follow
// Forward's record order, IsVar bits and resolved types.
// L7 lane 18 access: `public`. Forward exports a property descriptor (vpMV) for nals, NALUnit.type/
// start/count, NALType.description and each NAL enum's rawValue/description. MV is emitted only for
// public properties; control: internal Average/PointerImagePipeline/ProAVPlayer export none. The
// helpers below have no trie symbol, so they stay non-public.
// ⚑[tool=export_trie_oracle ref=PacketNalData result=vg+vpMV-per-member]
public struct PacketNalData {
    public let nals: [PacketNalData.NALUnit]

    /// ⚑ NAME INFERRED — no Forward body: this dispatcher is inlined, identically, into all three callers
    /// (KSOptions.makeDecode @0x1019b6448.., FFmpegUtility.write @0x101a1de74.., VideoToolboxDecode.decodeFrame
    /// @0x101a6cf14..). Written as an init because callers read only `.nals`; a free func returning
    /// `[NALUnit]` is equally consistent (undecidable).
    /// Shape read from the callers: `nals = []`; `size >= 1` (signed) gates everything; `size >= 4` (unsigned
    /// after the first test) and 00 00 00 01 → Annex-B with start-code length 4, 00 00 01 → length 3,
    /// anything else → length-prefixed. Every caller passes the same data pointer twice (see parseAnnexB).
    init(data: UnsafePointer<UInt8>, size: Int, codecID: AVCodecID) {
        var nals = [PacketNalData.NALUnit]()
        if size >= 1 {
            if size >= 4, data[0] == 0, data[1] == 0, data[2] == 0, data[3] == 1 {
                PacketNalData.parseAnnexB(size: size, startCodeLength: 4, data: data, nalData: data, codecID: codecID, nals: &nals)
            } else if size >= 4, data[0] == 0, data[1] == 0, data[2] == 1 {
                PacketNalData.parseAnnexB(size: size, startCodeLength: 3, data: data, nalData: data, codecID: codecID, nals: &nals)
            } else {
                PacketNalData.parseLengthPrefixed(size: size, data: data, nalData: data, codecID: codecID, nals: &nals)
            }
        }
        self.nals = nals
    }

    /// ⚑ NAME INFERRED — Forward 0x101a0bfdc (no symbol; w0 codecID, x1 pointer → packed NALType).
    /// Out of line only in parseAnnexB's tail (@0x101a0cc9c); inlined at every other append site.
    /// H264/HEVC/AV1 call the rawValue inits out of line (merged bodies 0x101a0d608 / 0x101a0d61c /
    /// 0x101a0d630); VP9's two-case init is inlined (`tst #0xe`). `switch` vs if-chain is undecidable.
    static func nalType(codecID: AVCodecID, pointer: UnsafePointer<UInt8>) -> NALType {
        let header = pointer.pointee
        switch codecID {
        case AV_CODEC_ID_H264:
            let value = header & 0x1F
            if let type = H264NALUnitType(rawValue: value) {
                return .h264(type)
            }
            return .unknown(value)
        case AV_CODEC_ID_HEVC:
            let value = (header >> 1) & 0x3F
            if let type = HEVCNALUnitType(rawValue: value) {
                return .h265(type)
            }
            return .unknown(value)
        case AV_CODEC_ID_VP9:
            let value = header & 0x0F
            if let type = VP9FrameType(rawValue: value) {
                return .vp9(type)
            }
            return .unknown(value)
        case AV_CODEC_ID_AV1:
            let value = (header >> 3) & 0x0F
            if let type = AV1OBUType(rawValue: value) {
                return .av1(type)
            }
            return .unknown(value)
        default:
            return .unknown(header)
        }
    }

    /// ⚑ NAME INFERRED — Forward 0x101a0c0b0 (no symbol; x0 packed type, x1 size, x2 pointer →
    /// (UInt16, Int, Int)? in x0–x2 with w3 = nil flag). `.h264(.sei)` skips the 1-byte header,
    /// `.h265(.seiPrefix/.seiSuffix)` (value - 0x27 <u 2) the 2-byte header: size - n and offset + n are
    /// overflow-checked, the pointer add is not; payloadType and payloadSize pass through.
    static func seiPayload(type: NALType, size: Int, pointer: UnsafePointer<UInt8>) -> (UInt16, Int, Int)? {
        switch type {
        case .h264(.sei):
            if let sei = PacketNalData.parseSEI(size: size - 1, pointer: pointer + 1) {
                return (sei.0, sei.1 + 1, sei.2)
            }
        case .h265(.seiPrefix), .h265(.seiSuffix):
            if let sei = PacketNalData.parseSEI(size: size - 2, pointer: pointer + 2) {
                return (sei.0, sei.1 + 2, sei.2)
            }
        default:
            break
        }
        return nil
    }

    public struct NALUnit {
        public let type: PacketNalData.NALType
        public let start: Int
        public let count: Int
    }

    public enum NALType: CustomStringConvertible, Equatable {
        case h264(H264NALUnitType)
        case h265(HEVCNALUnitType)
        case vp9(VP9FrameType)
        case av1(AV1OBUType)
        case sei(UInt16)
        case unknown(UInt8)
        public var description: String {
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
public enum H264NALUnitType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case unspecified0, slice, dpa, dpb, dpc, idrSlice, sei, sps, pps, aud, endSequence, endStream, fillerData, spsExt, prefix, subSPS, dps, reserved17, reserved18, auxSlice, extSlice, depthExtSlice, reserved22, reserved23, unspecified24, unspecified25, unspecified26, unspecified27, unspecified28, unspecified29, unspecified30, unspecified31
    public var description: String { "h264 \(self) (\(rawValue))" }
}

// HEVCNALUnitType @0x1039ee714 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=HEVCNALUnitType:0x1039ee714 result=enum HEVCNALUnitType: UInt8]
public enum HEVCNALUnitType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case trailN, trailR, tsaN, tsaR, stsaN, stsaR, radlN, radlR, raslN, raslR, vclN10, vclR11, vclN12, vclR13, vclN14, vclR15, blaWLp, blaWRadl, blaNLp, idrWRadl, idrNLp, craNut, rsvIrapVcl22, rsvIrapVcl23, rsvVcl24, rsvVcl25, rsvVcl26, rsvVcl27, rsvVcl28, rsvVcl29, rsvVcl30, rsvVcl31, vps, sps, pps, aud, eosNut, eobNut, fdNut, seiPrefix, seiSuffix, rsvNvcl41, rsvNvcl42, rsvNvcl43, rsvNvcl44, rsvNvcl45, rsvNvcl46, rsvNvcl47, unspec48, unspec49, unspec50, unspec51, unspec52, unspec53, unspec54, unspec55, unspec56, unspec57, unspec58, unspec59, unspec60, unspec61, unspec62, unspec63
    public var description: String { "hevc \(self) (\(rawValue))" }
}

// VP9FrameType @0x1039ee730 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=VP9FrameType:0x1039ee730 result=enum VP9FrameType: UInt8]
public enum VP9FrameType: UInt8 {
    // L7: raw values are the implicit 0-based sequence; Forward's rawValue body was not read
    case keyFrame, interFrame
    public var description: String { "vp9 \(self) (\(rawValue))" }
}

// AV1OBUType @0x1039ee74c — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (AVFFmpegExtension.swift..AudioEnginePlayer.swift).
// ⚑[tool=type_surface ref=AV1OBUType:0x1039ee74c result=enum AV1OBUType: UInt8]
public enum AV1OBUType: UInt8 {
    // L7 lane 13: Forward raw-value table @0x103569fca = 0…8, 15 (padding = 15).
    case reserved0, sequenceHeader, temporalDelimiter, frameHeader, tileGroup, metadata, frame, redundantFrameHeader, tileList
    case padding = 15
    public var description: String { "av1 \(self) (\(rawValue))" }
}

// L7 lane 18: Forward emits the two scanners after NALType's Equatable witness (0x101a0c454) and parseSEI after
// the MergeFunctions rawValue thunks (0x101a0d2d0..) — the tail position of optimizer-made clones — so their
// source position is undecidable; they are placed here in address order.
extension PacketNalData {
    /// ⚑ NAME INFERRED — no out-of-line body: the per-NAL append is inlined at every site (3× in parseAnnexB,
    /// 1× in parseLengthPrefixed). Sequence read from 0x101a0cc90..0x101a0cd50: pointer = nalData + start;
    /// type = nalType(codecID, pointer); append NALUnit(type, start, count); if seiPayload(type, count, pointer)
    /// is non-nil, append NALUnit(.sei(payloadType), start + offset (checked), payloadSize).
    private static func appendNAL(start: Int, count: Int, nalData: UnsafePointer<UInt8>, codecID: AVCodecID, nals: inout [PacketNalData.NALUnit]) {
        let pointer = nalData + start
        let type = PacketNalData.nalType(codecID: codecID, pointer: pointer)
        nals.append(PacketNalData.NALUnit(type: type, start: start, count: count))
        if let sei = PacketNalData.seiPayload(type: type, size: count, pointer: pointer) {
            nals.append(PacketNalData.NALUnit(type: .sei(sei.0), start: start + sei.1, count: sei.2))
        }
    }

    /// ⚑ NAME INFERRED — Forward 0x101a0c470 (no symbol; x0 size, x1 startCodeLength, x2 data (start-code scan),
    /// x3 data (NAL headers), w4 codecID, x5 &nals). Both pointers are the same value at every call site; the
    /// split (scan pointer + trailing data/codecID/&nals) is consistent with a closure-specialized clone whose
    /// trailing params are the captures. The post-specialization ABI is written directly (undecidable).
    /// Loop head `index + 3` (checked) `< size`; after a non-match `index += 1` is unchecked (the next head's
    /// add is checked). In-loop appends have no count guard; `index - start` is checked.
    /// Tail @0x101a0cc7c: non-trapping exits `start < 0` (tbnz #63), `size <= start` (subs/b.le) and
    /// `count < 1`; the exact guard spelling is undecidable.
    private static func parseAnnexB(size: Int, startCodeLength: Int, data: UnsafePointer<UInt8>, nalData: UnsafePointer<UInt8>, codecID: AVCodecID, nals: inout [PacketNalData.NALUnit]) {
        var start = startCodeLength
        var index = startCodeLength
        while index + 3 < size {
            if data[index] == 0, data[index + 1] == 0 {
                if data[index + 2] == 0 {
                    if data[index + 3] == 1 {
                        PacketNalData.appendNAL(start: start, count: index - start, nalData: nalData, codecID: codecID, nals: &nals)
                        index += 4
                        start = index
                        continue
                    }
                } else if data[index + 2] == 1 {
                    PacketNalData.appendNAL(start: start, count: index - start, nalData: nalData, codecID: codecID, nals: &nals)
                    index += 3
                    start = index
                    continue
                }
            }
            index &+= 1
        }
        if start >= 0, size > start {
            let count = size - start
            if count >= 1 {
                PacketNalData.appendNAL(start: start, count: count, nalData: nalData, codecID: codecID, nals: &nals)
            }
        }
    }

    /// ⚑ NAME INFERRED — Forward 0x101a0ce98 (no symbol; x0 size, x1 data (length words), x2 data (NAL headers),
    /// w3 codecID, x4 &nals); same pointer-twice shape as parseAnnexB.
    /// Per step: start = offset + 4 (checked) → return if size < start; count = big-endian UInt32 at
    /// data + offset (`ldr` + `rev`; `load` vs `loadUnaligned` is undecidable in release) → return if 0;
    /// offset = start + count (checked) → return if size < offset; then the inlined append.
    private static func parseLengthPrefixed(size: Int, data: UnsafePointer<UInt8>, nalData: UnsafePointer<UInt8>, codecID: AVCodecID, nals: inout [PacketNalData.NALUnit]) {
        var offset = 0
        while true {
            let start = offset + 4
            if size < start {
                return
            }
            let count = Int(UInt32(bigEndian: UnsafeRawPointer(data).loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            if count == 0 {
                return
            }
            offset = start + count
            if size < offset {
                return
            }
            PacketNalData.appendNAL(start: start, count: count, nalData: nalData, codecID: codecID, nals: &nals)
        }
    }

    /// ⚑ NAME INFERRED — Forward 0x101a0d2f8 (no symbol; x0 size, x1 pointer → (UInt16, Int, Int)?).
    /// payloadType starts at pointer[0] and gains 0xff per following 0xff byte (UInt16 add checked, tbnz #16);
    /// payloadSize starts at the next byte and gains 0xff per following 0xff byte; the returned index is the
    /// byte that ends the size run (not past it). All index/size adds are checked; the final `size <
    /// index + payloadSize` is a csel to nil. Read as written, not as the H.264 spec's SEI loop.
    private static func parseSEI(size: Int, pointer: UnsafePointer<UInt8>) -> (UInt16, Int, Int)? {
        if size < 2 {
            return nil
        }
        var payloadType = UInt16(pointer[0])
        var index = 1
        while pointer[index] == 0xFF {
            payloadType += 0xFF
            index += 1
        }
        var payloadSize = Int(pointer[index])
        index += 1
        while pointer[index] == 0xFF {
            payloadSize += 0xFF
            index += 1
        }
        if size < index + payloadSize {
            return nil
        }
        return (payloadType, index, payloadSize)
    }
}
