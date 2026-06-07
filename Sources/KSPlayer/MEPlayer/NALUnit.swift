//
//  NALUnit.swift
//  KSPlayer
//
//  Codec-bitstream NAL/OBU models sitting between a demuxed `Packet` and the
//  codec-specific NAL/OBU stream. Used by the AVCC ↔ Annex-B conversion path
//  (`BitStreamFilter` family) and by the VTB AVCC NALU walker
//  (RE: `DecompressionSession_parseAVCCNALUs @ 0x101453638`).
//
//  RE: Forward v1.3.15. All types below are pure Swift reflection-metadata
//  types — `types.json` lists their layout and `audit/ENUM_CASES_1.3.15.md`
//  lists every case in declaration order, but the binary emits no per-type
//  named methods (no `AV1OBUType_*`, `H264NALUnitType_*`, `PacketNalData_*`).
//  They are consumed positionally by the parsing code, not via dispatch.
//

import Foundation

/// A parsed-NAL container layered over a `Packet`'s payload. **1 field** per
/// `types.json`.
struct PacketNalData {
    /// Array of parsed NAL/OBU unit descriptors over the packet buffer.
    var nals: [NALUnit]

    /// A single parsed NAL/OBU unit. **3 fields** per `types.json`
    /// (declaration order).
    struct NALUnit {
        /// Tagged codec-specific NAL/OBU type.
        var type: NALType
        /// Byte offset of this unit's payload within the packet.
        var start: Int
        /// Byte length of this unit's payload.
        var count: Int
    }

    /// Discriminator union tying a parsed unit to its codec-specific type enum.
    /// **6 cases** per `audit/ENUM_CASES_1.3.15.md` (`PacketNalData.NALType (6)`),
    /// four of which carry a codec-specific payload enum.
    enum NALType {
        case h264(H264NALUnitType)
        case h265(HEVCNALUnitType)
        case vp9(VP9FrameType)
        case av1(AV1OBUType)
        case sei
        case unknown
    }
}

/// H.264 NAL unit type (the 5-bit `nal_unit_type` from the NAL header), used
/// when classifying units for AVCC → Annex-B conversion. **32 cases**
/// (`audit/ENUM_CASES_1.3.15.md`, declaration order = raw value), matching the
/// ITU-T H.264 `nal_unit_type` table.
enum H264NALUnitType: UInt8 {
    case unspecified0 = 0
    case slice = 1
    case dpa = 2
    case dpb = 3
    case dpc = 4
    case idrSlice = 5
    case sei = 6
    case sps = 7
    case pps = 8
    case aud = 9
    case endSequence = 10
    case endStream = 11
    case fillerData = 12
    case spsExt = 13
    case prefix = 14
    case subSPS = 15
    case dps = 16
    case reserved17 = 17
    case reserved18 = 18
    case auxSlice = 19
    case extSlice = 20
    case depthExtSlice = 21
    case reserved22 = 22
    case reserved23 = 23
    case unspecified24 = 24
    case unspecified25 = 25
    case unspecified26 = 26
    case unspecified27 = 27
    case unspecified28 = 28
    case unspecified29 = 29
    case unspecified30 = 30
    case unspecified31 = 31
}

/// HEVC (H.265) NAL unit type (the 6-bit `nal_unit_type`), used for the same
/// AVCC → Annex-B classification on HEVC tracks (including the `dvh1`/`dvhe`
/// Dolby-Vision HEVC variants). **64 cases** (`audit/ENUM_CASES_1.3.15.md`,
/// declaration order = raw value), matching the ITU-T H.265 table.
enum HEVCNALUnitType: UInt8 {
    case trailN = 0
    case trailR = 1
    case tsaN = 2
    case tsaR = 3
    case stsaN = 4
    case stsaR = 5
    case radlN = 6
    case radlR = 7
    case raslN = 8
    case raslR = 9
    case vclN10 = 10
    case vclR11 = 11
    case vclN12 = 12
    case vclR13 = 13
    case vclN14 = 14
    case vclR15 = 15
    case blaWLp = 16
    case blaWRadl = 17
    case blaNLp = 18
    case idrWRadl = 19
    case idrNLp = 20
    case craNut = 21
    case rsvIrapVcl22 = 22
    case rsvIrapVcl23 = 23
    case rsvVcl24 = 24
    case rsvVcl25 = 25
    case rsvVcl26 = 26
    case rsvVcl27 = 27
    case rsvVcl28 = 28
    case rsvVcl29 = 29
    case rsvVcl30 = 30
    case rsvVcl31 = 31
    case vps = 32
    case sps = 33
    case pps = 34
    case aud = 35
    case eosNut = 36
    case eobNut = 37
    case fdNut = 38
    case seiPrefix = 39
    case seiSuffix = 40
    case rsvNvcl41 = 41
    case rsvNvcl42 = 42
    case rsvNvcl43 = 43
    case rsvNvcl44 = 44
    case rsvNvcl45 = 45
    case rsvNvcl46 = 46
    case rsvNvcl47 = 47
    case unspec48 = 48
    case unspec49 = 49
    case unspec50 = 50
    case unspec51 = 51
    case unspec52 = 52
    case unspec53 = 53
    case unspec54 = 54
    case unspec55 = 55
    case unspec56 = 56
    case unspec57 = 57
    case unspec58 = 58
    case unspec59 = 59
    case unspec60 = 60
    case unspec61 = 61
    case unspec62 = 62
    case unspec63 = 63
}

/// VP9 frame-type flag (the `frame_type` bit in the VP9 uncompressed header).
/// **2 cases** (`audit/ENUM_CASES_1.3.15.md`).
enum VP9FrameType: UInt8 {
    case keyFrame = 0
    case interFrame = 1
}

/// AV1 Open Bitstream Unit type (the `obu_type` field of the OBU header), used
/// when walking AV1 elementary streams — relevant to the AV1 Dolby Vision
/// codec-tag path. **10 cases** (`audit/ENUM_CASES_1.3.15.md`, declaration
/// order = raw value).
///
/// Note: the AV1 spec reserves `obu_type` 9–14 and defines 15 as
/// `OBU_PADDING`; this enum collapses the trailing block so index 9 is the
/// single `padding` case. The raw values are the Swift declaration indices,
/// not the on-wire `obu_type` codes for the high end.
enum AV1OBUType: UInt8 {
    case reserved0 = 0
    case sequenceHeader = 1
    case temporalDelimiter = 2
    case frameHeader = 3
    case tileGroup = 4
    case metadata = 5
    case frame = 6
    case redundantFrameHeader = 7
    case tileList = 8
    case padding = 9
}

/// A caseless namespace enum holding FFmpeg helper statics for the decode layer
/// (the Swift idiom of an empty enum used as a static-only namespace).
///
/// RE: `audit/ENUM_CASES_1.3.15.md` records `FFmpegUtility: (no cases in
/// reflection metadata)`, and the binary emits no `FFmpegUtility_*` instance
/// methods — consistent with a caseless utility namespace rather than a
/// value-carrying enum.
enum FFmpegUtility {}
