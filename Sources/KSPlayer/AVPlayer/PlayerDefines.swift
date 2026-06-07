//
//  PlayerDefines.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import CoreServices
#if canImport(UIKit)
import UIKit

public extension KSOptions {
    @MainActor
    static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    @MainActor
    static var sceneSize: CGSize {
        let window = windowScene?.windows.first
        return window?.bounds.size ?? .zero
    }
}
#else
import AppKit
import SwiftUI

public typealias UIView = NSView
public typealias UIPasteboard = NSPasteboard
public extension KSOptions {
    static var sceneSize: CGSize {
        NSScreen.main?.frame.size ?? .zero
    }
}
#endif

// extension MediaPlayerTrack {
//    static func == (lhs: Self, rhs: Self) -> Bool {
//        lhs.trackID == rhs.trackID
//    }
// }

// RE (Forward 1.3.15): real KSPlayer enum, contiguous Int32 0..3, RawRepresentable.
// Anchors: audit/ENUM_CASES_1.3.15.md reflection dump "DynamicRange (4): 0 sdr; 1 hdr10;
// 2 hlg; 3 dolbyVision"; DynamicRange_toCGColorSpace @ 0x1013c7150 indexes a contiguous
// transfer-function table by (char)rawValue; the byte store in onVideoTrackOpened
// (FUN_10138d62c) writes only 0..3 and the same rawValue is fed to
// AVDisplayCriteria(videoDynamicRange:) at KSOptions.swift:500 — so contiguous 0..3 is
// load-bearing, not cosmetic. hdr10Fallback(4) is NOT a member here: it exists only in the
// classify-code space (Int return of KSOptions_classifyDynamicRange @ 0x1013c38fc, the
// null-CMFormatDescription outcome) and is collapsed to .hdr10 at the store boundary.
public enum DynamicRange: Int32 {
    case sdr = 0
    case hdr10 = 1
    case hlg = 2
    case dolbyVision = 3

    #if canImport(UIKit)
    var hdrMode: AVPlayer.HDRMode {
        switch self {
        case .sdr:
            return AVPlayer.HDRMode(rawValue: 0)
        case .hdr10:
            return .hdr10
        case .hlg:
            return .hlg
        case .dolbyVision:
            return .dolbyVision
        }
    }
    #endif
    public static var availableHDRModes: [DynamicRange] {
        #if os(macOS)
        if NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0 {
            return [.hdr10]
        } else {
            return [.sdr]
        }
        #else
        let availableHDRModes = AVPlayer.availableHDRModes
        if availableHDRModes == AVPlayer.HDRMode(rawValue: 0) {
            return [.sdr]
        } else {
            var modes = [DynamicRange]()
            if availableHDRModes.contains(.dolbyVision) {
                modes.append(.dolbyVision)
            }
            if availableHDRModes.contains(.hdr10) {
                modes.append(.hdr10)
            }
            if availableHDRModes.contains(.hlg) {
                modes.append(.hlg)
            }
            return modes
        }
        #endif
    }
}

extension DynamicRange: CustomStringConvertible {
    public var description: String {
        switch self {
        case .sdr:
            return "SDR"
        case .hdr10:
            return "HDR10"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "Dolby Vision"
        }
    }
}

extension DynamicRange {
    var colorPrimaries: CFString {
        switch self {
        case .sdr:
            return kCVImageBufferColorPrimaries_ITU_R_709_2
        case .hdr10, .hlg, .dolbyVision:
            return kCVImageBufferColorPrimaries_ITU_R_2020
        }
    }

    var transferFunction: CFString {
        switch self {
        case .sdr:
            return kCVImageBufferTransferFunction_ITU_R_709_2
        case .hdr10:
            return kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case .hlg, .dolbyVision:
            return kCVImageBufferTransferFunction_ITU_R_2100_HLG
        }
    }

    var yCbCrMatrix: CFString {
        switch self {
        case .sdr:
            return kCVImageBufferYCbCrMatrix_ITU_R_709_2
        case .hdr10, .hlg, .dolbyVision:
            return kCVImageBufferYCbCrMatrix_ITU_R_2020
        }
    }
}

// RE (Forward 1.3.15): the former DynamicRange.init(forwardValue:)/var forwardValue side
// channel is removed. With the corrected contiguous rawValues, rawValue IS the compact code
// (sdr=0, hdr10=1, hlg=2, dolbyVision=3), so AVDisplayCriteria(videoDynamicRange: rawValue)
// at KSOptions.swift:500 is correct without translation. The classify-code space's extra
// member (4 = hdr10Fallback) lives only in the Int return of classifyDynamicRange and is
// never stored as a DynamicRange (FUN_10138d62c writes only 0..3).

// MARK: - isDolbyVision Global Toggle

/// "Honor Dolby Vision Profile 7" master toggle. When `true`, Profile-7 content
/// is classified and decoded as Dolby Vision; when `false`, it falls back to HDR10.
///
/// RE: getter 0x1013a3658, setter 0x1013a3698, modify 0x1013a36dc, unsafeAddr 0x1013a364c
/// (Forward 1.3.15). Backed by `DAT_103d097d8`; reflection field name `_isDolbyVision`
/// at `0x103314ea7`.
///
/// Part of the `_isSubtitleDownloading` / `_isDolbyVision` / `_isAtmos` trio of global
/// property-wrapper-backed state Bools bound through the accessor-association table at
/// `0x103c307a8` via the common metadata pointer `0x103d2c460`. The witness triple for
/// this member is at `0x104820ece/ecf/ed0`.
///
/// **Distinct from `KSOptions.enhanceDolby`.** `enhanceDolby` gates whether the Metal
/// `DoviDisplayModel` reshape path runs (render-side); `isDolbyVision` gates whether
/// Profile-7 content is *classified as DV* in the first place (decode/classify-side).
///
/// **Binary readers (12 distinct, excluding accessors):** `KSOptions_classifyDynamicRange`,
/// `FUN_10138d62c` (onVideoTrackOpened), `FUN_10138dfec`, `FUN_101405bb8`
/// (MEPlayerItemTrack_createDecoder), `FUN_101408ce4`, `FUN_101409930`, `FUN_10140b594`,
/// `FUN_101415b84`, `FUN_101417f90`, `FUN_10141bbe4`, `FUN_101436de0`, `FUN_1014508b4`.
///
/// **Key read sites:**
/// - `classifyDynamicRange @ 0x1013c38fc`: `(codecTag & 0xff0000) == 0x70000` (Profile 7)
///   -> `isDolbyVision ? .dolbyVision : .hdr10`.
/// - `KSAVPlayer.onVideoTrackOpened` (`FUN_10138d62c`): track profile byte `== 7`
///   -> `dynamicRange = isDolbyVision ? .dolbyVision : .hdr10`.
/// - ME-decode track setup (`FUN_101405bb8`): profile byte at `param_1+0x134 == 7`
///   -> `isDovi = isDolbyVision`, passed to decoder config.
///
/// Default: `true` (DV honored). The binary's backing storage has no explicit
/// initializer observed in Ghidra; zero-initialized Bool = `false` in raw memory,
/// but the app's launch path sets it to `true` before any classification runs.
/// Defaulting to `true` here matches the runtime-observed default.
public nonisolated(unsafe) var isDolbyVision: Bool = true

// MARK: - DOVIDecoderConfigurationRecord (cross-reference)
// RE (DolbyVision.md lines 1028-1036): DOVIDecoderConfigurationRecord belongs to the
// PlayerDefines-DV doc cluster. The actual struct definition lives in
// MediaPlayerProtocol.swift (same KSPlayer module) with all 8 correct UInt8 fields
// (dv_version_major, dv_version_minor, dv_profile, dv_level, rpu_present_flag,
// el_present_flag, bl_present_flag, dv_bl_signal_compatibility_id), correctly omitting
// the __C record's trailing dv_md_compression. No move needed -- same module visibility.

/// Display geometry mode selector. Binary type: protocol `KSPlayer.DisplayEnum` with
/// conformer singletons (PlaneDisplayModel, SphereDisplayModel, VRDisplayModel,
/// VRBoxDisplayModel, DoviDisplayModel, ThumbnailDoviDisplayModel). Reconstructed as a
/// Swift enum for idiomatic dispatch -- behavior equivalent, see DisplayModel.swift for
/// the full binary witness-table mapping.
/// RE: protocol descriptor Plane/Dovi 0x102ef0bf0, VR/VRBox 0x102ef0ea8
/// Binary conformer factory typos "vrDiaplay"/"vrBoxDiaplay" corrected.
@MainActor
public enum DisplayEnum {
    /// RE: PlaneDisplayModel singleton at DAT_104458870
    case plane
    // swiftlint:disable identifier_name
    /// RE: VRDisplayModel singleton at DAT_104458880 (binary: "vrDiaplay" -- typo corrected)
    case vr
    // swiftlint:enable identifier_name
    /// RE: VRBoxDisplayModel singleton at DAT_104458888 (binary: "vrBoxDiaplay" -- typo corrected)
    case vrBox
    /// Content-based automatic display selection (AVSBDL vs Metal).
    /// Reconstruction addition -- not in the binary.
    case auto
    /// Force PQ (SMPTE ST 2084) colorspace in Metal rendering pipeline.
    /// Reconstruction addition -- not in the binary.
    case metalPQ

    /// Whether this display model handles touch interaction (rotation/pan).
    /// RE: existential witness slot [wt+0x08]. Returns false for PlaneDisplayModel/
    /// DoviDisplayModel (0x10002a3cc), true for the sphere/VR family (0x10028e848).
    /// This is the gate MetalPlayView.touchesMoved tests before choosing rotation vs super.
    public var isInteractive: Bool {
        switch self {
        case .vr, .vrBox:
            return true
        case .plane, .auto, .metalPQ:
            return false
        }
    }
}

public struct VideoAdaptationState {
    public struct BitRateState {
        let bitRate: Int64
        let time: TimeInterval
    }

    public let bitRates: [Int64]
    public let duration: TimeInterval
    public internal(set) var fps: Float
    public internal(set) var bitRateStates: [BitRateState]
    public internal(set) var currentPlaybackTime: TimeInterval = 0
    public internal(set) var isPlayable: Bool = false
    public internal(set) var loadedCount: Int = 0
}

// RE (Forward 1.3.15): case set/order/payload from the ClockProcessType field-record
// name table at 0x103744d4f (dropFrame, empty, remain, next, dropGOPPacket, flush, seek);
// type-name 'ClockProcessType' at 0x102eed870. Sole producer is videoClockSync
// (sym 0x104749df0); sole switch consumer is getVideoOutputRender(force:) (reflstr
// 0x1033385c0) driven by MetalPlayView.renderFrameImpl @ 0x10144529c via the
// VideoOutputRenderSourceDelegate witness. Only case 0 carries a payload.
public enum ClockProcessType {
    /// Drop `count` already-decoded, stale frames from the front of the output
    /// render queue before returning the next displayable frame. `count` is the
    /// number of buffered frames whose PTS lies behind the current sync clock
    /// (always >= 1; a zero-drop advance is expressed as `.next`).
    /// Binary: ClockProcessType case 0, payload mangling `Si5count_t`.
    case dropFrame(count: Int)
    /// Output render queue holds no frame at/before the target time. Nothing to
    /// evaluate: keep the current displayed frame, no dequeue. Binary case 1.
    case empty
    /// Next queued frame's PTS is still in the future vs the sync clock: keep the
    /// current displayed frame, return nil. Binary case 2.
    case remain
    /// Normal advance: next queued frame is due now -- dequeue and return one
    /// frame. Binary case 3.
    case next
    /// Sync is far enough behind that per-frame dropping is insufficient: drop
    /// forward to the next GOP/keyframe boundary. Logged with " drop gop Packet".
    /// Binary case 4.
    case dropGOPPacket
    /// Flush the entire output render queue (reset decode output state) when
    /// buffered frames are worthless. Binary case 5.
    case flush
    /// Seek-class discontinuity from the clock comparison: flush output and
    /// re-baseline against the new clock. Binary case 6.
    case seek
}

// 缓冲情况
public protocol CapacityProtocol {
    var fps: Float { get }
    var packetCount: Int { get }
    var frameCount: Int { get }
    var frameMaxCount: Int { get }
    var isEndOfFile: Bool { get }
    var mediaType: AVFoundation.AVMediaType { get }
}

extension CapacityProtocol {
    var loadedTime: TimeInterval {
        TimeInterval(packetCount + frameCount) / TimeInterval(fps)
    }
}

public struct LoadingState {
    public let loadedTime: TimeInterval
    // RE (Forward 1.3.15): field #2 is buffering progress 0–100 as a UInt8
    // (types.json), not a TimeInterval. See .reversal/PlayerCore.md §LoadingState.
    public let progress: UInt8
    public let packetCount: Int
    public let frameCount: Int
    public let isEndOfFile: Bool
    public let isPlayable: Bool
    public let isFirst: Bool
    public let isSeek: Bool
}

public let KSPlayerErrorDomain = "KSPlayerErrorDomain"

/// The engine's FFmpeg open/decode/subtitle failure taxonomy.
///
/// RE (Forward 1.3.15): 19 cases, declaration index == raw value. Reordered to the
/// RE-verified binary taxonomy (audit/ENUM_CASES_1.3.15.md "KSPlayerErrorCode (19):
/// 0 formatCreate … 18 subtitleParamsEmpty"). The prior source used the upstream
/// ordering, which injected a leading `unknown` (shifting every rawValue by 1), omitted
/// the binary cases `avioOpen` (2) and `noStream` (7), and added the non-binary cases
/// `codecContextFindDecoder`, `codecVideoSendPacket`, `codecAudioSendPacket`,
/// `audioSwrInit`. With the corrected ordering, e.g. `subtitleParamsEmpty == 18` matches
/// the binary (was 21 upstream).
///
/// The binary spells case 10 `codesContextOpen` (sic) — per project rules the typo is
/// fixed on the Swift side to `codecContextOpen`; `.reversal/` preserves the binary
/// spelling verbatim.
public enum KSPlayerErrorCode: Int {
    case formatCreate           // 0
    case formatOpenInput        // 1
    case avioOpen               // 2
    case formatOutputCreate     // 3
    case formatWriteHeader      // 4
    case formatFindStreamInfo   // 5
    case readFrame              // 6
    case noStream               // 7
    case codecContextCreate     // 8
    case codecContextSetParam   // 9
    case codecContextOpen       // 10 (binary: "codesContextOpen" — typo fixed)
    case codecVideoReceiveFrame // 11
    case codecAudioReceiveFrame // 12
    case codecSubtitleSendPacket // 13
    case videoTracksUnplayable  // 14
    case subtitleUnEncoding     // 15
    case subtitleUnParse        // 16
    case subtitleFormatUnSupport // 17
    case subtitleParamsEmpty    // 18

    // Upstream-only cases (NOT in the binary's 19-case taxonomy). Appended after index 18
    // so the RE-verified raw values 0–18 above stay exact (load-bearing — e.g.
    // subtitleParamsEmpty == 18). These two are still referenced by sibling decode files
    // (AVFFmpegExtension.codecContextFindDecoder @ ~line 174, Resample.audioSwrInit @
    // ~line 425); kept compilable per "implement everything, scrap later". The review
    // phase should decide whether to migrate those call sites and drop these.
    // The binary's other two upstream-only cases (codecVideoSendPacket,
    // codecAudioSendPacket) had zero references and were removed.
    case codecContextFindDecoder // 19 (upstream-only)
    case audioSwrInit            // 20 (upstream-only)
}

extension KSPlayerErrorCode: CustomStringConvertible {
    // Switch realigned to the 19-case binary taxonomy: adds `avioOpen`/`noStream`, drops
    // the unreferenced upstream-only `codecVideoSendPacket`/`codecAudioSendPacket`, and
    // keeps the still-referenced upstream-only `codecContextFindDecoder`/`audioSwrInit`
    // (appended at 19/20 above). Exhaustive (no `default`) so any future case change is a
    // compile error.
    public var description: String {
        switch self {
        case .formatCreate:
            return "avformat_alloc_context return nil"
        case .formatOpenInput:
            return "avformat can't open input"
        case .avioOpen:
            return "avio_open2 fail"
        case .formatOutputCreate:
            return "avformat_alloc_output_context2 fail"
        case .formatWriteHeader:
            return "avformat_write_header fail"
        case .formatFindStreamInfo:
            return "avformat_find_stream_info return nil"
        case .readFrame:
            return "av_read_frame fail"
        case .noStream:
            return "no stream to play"
        case .codecContextCreate:
            return "avcodec_alloc_context3 return nil"
        case .codecContextSetParam:
            return "avcodec can't set parameters to context"
        case .codecContextOpen:
            return "codecContext can't Open"
        case .codecVideoReceiveFrame:
            return "avcodec can't receive video frame"
        case .codecAudioReceiveFrame:
            return "avcodec can't receive audio frame"
        case .codecSubtitleSendPacket:
            return "avcodec can't decode subtitle"
        case .videoTracksUnplayable:
            return "VideoTracks are not even playable."
        case .subtitleUnEncoding:
            return "Subtitle encoding format is not supported."
        case .subtitleUnParse:
            return "Subtitle parsing error"
        case .subtitleFormatUnSupport:
            return "Current subtitle format is not supported"
        case .subtitleParamsEmpty:
            return "Subtitle Params is empty"
        case .codecContextFindDecoder:
            return "avcodec_find_decoder return nil"
        case .audioSwrInit:
            return "swr_init swrContext fail"
        }
    }
}

/// The player's error value type, paired with ``KSPlayerErrorCode``.
///
/// RE (Forward 1.3.15): `struct KSPlayer.KSPlayerError`, 2 fields (`types.json`).
/// Value struct — value-witness only (`$s8KSPlayer13KSPlayerErrorVwta` @ `0x1001c99d0`),
/// no named methods. `code` is typically a ``KSPlayerErrorCode`` raw value or a raw
/// FFmpeg error code; `message` is an optional human-readable string.
public struct KSPlayerError: Error {
    /// Error code (a ``KSPlayerErrorCode`` raw value or an FFmpeg error code).
    public let code: Int32
    /// Optional human-readable message.
    public let message: String?

    public init(code: Int32, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// Convenience: build from a ``KSPlayerErrorCode``, defaulting `message` to its
    /// `description`.
    public init(errorCode: KSPlayerErrorCode, message: String? = nil) {
        code = Int32(errorCode.rawValue)
        self.message = message ?? errorCode.description
    }
}

extension NSError {
    convenience init(errorCode: KSPlayerErrorCode, userInfo: [String: Any] = [:]) {
        var userInfo = userInfo
        userInfo[NSLocalizedDescriptionKey] = errorCode.description
        self.init(domain: KSPlayerErrorDomain, code: errorCode.rawValue, userInfo: userInfo)
    }

    convenience init(description: String) {
        var userInfo = [String: Any]()
        userInfo[NSLocalizedDescriptionKey] = description
        self.init(domain: KSPlayerErrorDomain, code: 0, userInfo: userInfo)
    }
}

/// Empty marker class used to locate the KSPlayer module's resource bundle via the
/// standard SwiftPM `Bundle(for: BundleFinder.self)` / `Bundle.module` pattern.
///
/// RE (Forward 1.3.15): `class KSPlayer.BundleFinder`, 0 fields, no distinct named
/// functions (`types.json`). Every SPM module in the binary (Alamofire, Components,
/// Kingfisher, Lottie, …) carries its own `BundleFinder`. See .reversal/PlayerCore.md
/// §BundleFinder.
final class BundleFinder {}

#if !SWIFT_PACKAGE
extension Bundle {
    // Use the dedicated BundleFinder marker (the documented binary locator type) rather
    // than KSPlayerLayer, matching the standard SwiftPM resource-bundle pattern.
    static let module = Bundle(for: BundleFinder.self).path(forResource: "KSPlayer_KSPlayer", ofType: "bundle").flatMap { Bundle(path: $0) } ?? Bundle.main
}
#endif

public enum TimeType {
    case min
    case hour
    case minOrHour
    case millisecond
}

public extension TimeInterval {
    func toString(for type: TimeType) -> String {
        Int(ceil(self)).toString(for: type)
    }
}

public extension Int {
    func toString(for type: TimeType) -> String {
        var second = self
        var min = second / 60
        second -= min * 60
        switch type {
        case .min:
            return String(format: "%02d:%02d", min, second)
        case .hour:
            let hour = min / 60
            min -= hour * 60
            return String(format: "%d:%02d:%02d", hour, min, second)
        case .minOrHour:
            let hour = min / 60
            if hour > 0 {
                min -= hour * 60
                return String(format: "%d:%02d:%02d", hour, min, second)
            } else {
                return String(format: "%02d:%02d", min, second)
            }
        case .millisecond:
            var time = self * 100
            let millisecond = time % 100
            time /= 100
            let sec = time % 60
            time /= 60
            let min = time % 60
            time /= 60
            let hour = time % 60
            if hour > 0 {
                return String(format: "%d:%02d:%02d.%02d", hour, min, sec, millisecond)
            } else {
                return String(format: "%02d:%02d.%02d", min, sec, millisecond)
            }
        }
    }
}

public extension FixedWidthInteger {
    var kmFormatted: String {
        Double(self).kmFormatted
    }
}

open class AbstractAVIOContext {
    /// RE: Forward v1.3.15 binary field 1 of 2 -- caps individual read sizes to
    /// prevent blocking the I/O thread on slow connections. `0` = no limit.
    public var readLimit: Int32
    /// RE: Forward v1.3.15 binary field 2 of 2 -- passed to `avio_alloc_context`
    /// as the internal buffer size (typically 32 KB--256 KB).
    let bufferSize: Int32
    let writable: Bool
    public init(bufferSize: Int32 = 32 * 1024, writable: Bool = false, readLimit: Int32 = 0) {
        self.bufferSize = bufferSize
        self.writable = writable
        self.readLimit = readLimit
    }

    open func read(buffer _: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        size
    }

    open func write(buffer _: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        size
    }

    /**
     #define SEEK_SET        0       /* set file offset to offset */
     #define SEEK_CUR        1       /* set file offset to current plus offset */
     #define SEEK_END        2       /* set file offset to EOF plus offset */
     */
    open func seek(offset: Int64, whence _: Int32) -> Int64 {
        offset
    }

    open func fileSize() -> Int64 {
        -1
    }

    /// RE: witness slot `[+0x38]` dispatched from `KSMEPlayer.cachedRanges`
    /// (0x10141e758, 1.3.15). Translates the context's buffered byte ranges into
    /// playback time ranges, given the item's total duration. The base context is
    /// not cache-backed, so it reports no buffered ranges; the cache subclasses
    /// (CacheIOContext / PreLoadIOContext) override this to map their downloaded
    /// byte extents → time via `duration`.
    open func cachedRanges(duration _: TimeInterval) -> [CachedTimeRange] {
        []
    }

    open func close() {}
    deinit {}
}
