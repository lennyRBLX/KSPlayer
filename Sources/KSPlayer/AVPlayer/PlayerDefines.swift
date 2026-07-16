//
//  PlayerDefines.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import CoreServices
import FFmpegKit // Forward: AbstractAVIOContext's addSub/urlContext are FFmpeg-typed vtable slots (AVIOContext / URLContext / AVIOInterruptCB)
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

public enum DynamicRange: Int32 {
    case sdr = 0
    case hdr10 = 2
    case hlg = 3
    case dolbyVision = 5

    #if canImport(UIKit)
    var hdrMode: AVPlayer.HDRMode {
        switch self {
        case .sdr:
            return AVPlayer.HDRMode(rawValue: 0)
        case .hdr10:
            return .hdr10 // 2
        case .hlg:
            return .hlg // 1
        case .dolbyVision:
            return .dolbyVision // 4
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

@MainActor
public enum DisplayEnum {
    case plane
    // swiftlint:disable identifier_name
    case vr
    // swiftlint:enable identifier_name
    case vrBox
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

public enum ClockProcessType {
    case remain
    case next
    case dropNextFrame
    case dropNextPacket
    case dropGOPPacket
    case flush
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
    public let progress: TimeInterval
    public let packetCount: Int
    public let frameCount: Int
    public let isEndOfFile: Bool
    public let isPlayable: Bool
    public let isFirst: Bool
    public let isSeek: Bool
}

public let KSPlayerErrorDomain = "KSPlayerErrorDomain"

public enum KSPlayerErrorCode: Int {
    case unknown
    case formatCreate
    case formatOpenInput
    case formatOutputCreate
    case formatWriteHeader
    case formatFindStreamInfo
    case readFrame
    case codecContextCreate
    case codecContextSetParam
    case codecContextFindDecoder
    case codesContextOpen
    case codecVideoSendPacket
    case codecAudioSendPacket
    case codecVideoReceiveFrame
    case codecAudioReceiveFrame
    case auidoSwrInit
    case codecSubtitleSendPacket
    case videoTracksUnplayable
    case subtitleUnEncoding
    case subtitleUnParse
    case subtitleFormatUnSupport
    case subtitleParamsEmpty
}

extension KSPlayerErrorCode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .formatCreate:
            return "avformat_alloc_context return nil"
        case .formatOpenInput:
            return "avformat can't open input"
        case .formatOutputCreate:
            return "avformat_alloc_output_context2 fail"
        case .formatWriteHeader:
            return "avformat_write_header fail"
        case .formatFindStreamInfo:
            return "avformat_find_stream_info return nil"
        case .codecContextCreate:
            return "avcodec_alloc_context3 return nil"
        case .codecContextSetParam:
            return "avcodec can't set parameters to context"
        case .codesContextOpen:
            return "codesContext can't Open"
        case .codecVideoReceiveFrame:
            return "avcodec can't receive video frame"
        case .codecAudioReceiveFrame:
            return "avcodec can't receive audio frame"
        case .videoTracksUnplayable:
            return "VideoTracks are not even playable."
        case .codecSubtitleSendPacket:
            return "avcodec can't decode subtitle"
        case .subtitleUnEncoding:
            return "Subtitle encoding format is not supported."
        case .subtitleUnParse:
            return "Subtitle parsing error"
        case .subtitleFormatUnSupport:
            return "Current subtitle format is not supported"
        case .subtitleParamsEmpty:
            return "Subtitle Params is empty"
        case .auidoSwrInit:
            return "swr_init swrContext fail"
        default:
            return "unknown"
        }
    }
}

/// Forward-new error type. The shipped 1.3.17 binary replaces the upstream `extension NSError` error
/// model with this struct — descriptor 0x1039edbd4 (kind=struct), ~70+ uses app-wide (KSPlayer core +
/// FFmpeg wrappers + ProAVPlayer). Binary-confirmed fields: `code: KSPlayerErrorCode` (a symbolic-ref
/// nominal — corrects the prior recon's `Int32`; stdlib Int32 would use standard mangling, not a
/// symbolic ref), `message: String?` (mangle `SSSg`). ⚑ the initializers are inferred: the binary
/// inlines construction (`_swift_allocError` + store {code, message}), so no distinct init survives to
/// decompile. ⚑ base-regression: the reconstruction base still carries the upstream `extension NSError`
/// (below); migrating its call sites to this struct is a tracked structural gap.
public struct KSPlayerError: Error {
    public let code: KSPlayerErrorCode
    public let message: String?

    public init(code: KSPlayerErrorCode, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// ⚑ inferred convenience: matches the binary's throw payload {code = .unknown (0), message}.
    public init(description: String) {
        code = .unknown
        message = description
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

#if !SWIFT_PACKAGE
extension Bundle {
    static let module = Bundle(for: KSPlayerLayer.self).path(forResource: "KSPlayer_KSPlayer", ofType: "bundle").flatMap { Bundle(path: $0) } ?? Bundle.main
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

// Forward-only enum (binary-confirmed name `DecodeType`). Binary reflection (__swift5_fieldmd via the field-record
// oracle, desc @0x1039edfec): 5 no-payload cases in this ORDER, 1-byte storage. Case indices are binary-pinned —
// KSOptions.init (FUN_1019b2f7c) stores `decodeType = 1` = `.avplayer`. `vulka` is the binary's exact case name
// (reflection-read; reads like a truncation of "vulkan" but is what Forward ships — searched, no standalone "vulkan").
public enum DecodeType {
    case asynchronousHardware
    case avplayer
    case hardware
    case soft
    case vulka
}

// Forward-only protocol (binary-confirmed name `VideoPipeline`). Binary (conformance_walker, proto descriptor
// @0x1039edab8): 5 requirements — 1 getter + 4 methods — and NO in-binary conformer (external/call-site-inferred,
// exactly like PlayList). The requirement NAMES + SIGNATURES are UNRESOLVED (no witness bodies to ground them) —
// deferred to the PlayList/VideoPipeline protocol pass. Declared here (minimal) so `KSOptions.videoPipeline:
// VideoPipeline?` is layout-faithful: a protocol existential's size is fixed regardless of its requirements, so the
// KSOptions field type + offset are correct either way. ⚑ requirements deferred (not fabricated).
public protocol VideoPipeline {
    // 5 requirements (1 getter + 4 methods) UNRESOLVED — see the PlayList/VideoPipeline no-conformer protocol pass.
}

open class AbstractAVIOContext {
    // Forward addition (binary __swift5_fieldmd: readLimit@+0x10, bufferSize@+0x14;
    // vtable slots 0/1/2 are its synthesized getter/setter/read). Default -1
    // (binary init sets *(self+0x10) = 0xffffffff).
    public var readLimit: Int32 = -1
    let bufferSize: Int32
    // Forward dropped `writable` (not a stored field in the binary) + its init param.
    public init(bufferSize: Int32 = 32 * 1024) {
        self.bufferSize = bufferSize
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

    open func close() {}

    // ── Forward addition: the last two AbstractAVIOContext vtable slots (+0xa8, +0xb0).
    // Both are abstract `return nil` in the base (one coalesced binary body @0x10002d9d4) and
    // overridden per-subclass in the PreLoadIOContext module. Declaration order is load-bearing:
    // urlContext must precede addSub so addSub lands at slot +0xb0 (the io_open dispatch offset).

    // +0xa8 — computed getter exposing the terminal FFmpeg URLContext down the AVIO cache chain
    // (URLContextDownload returns self.context; HLSCacheIOContext returns download.context;
    // CacheIOContext dynamic-casts + recurses). Return type is binary-grounded: URLContextDownload's
    // first field `context: UnsafeMutablePointer<URLContext>?` @+0x18, and the getter's `return self+0x18`.
    // ⚑ name INFERRED — no #function on any override (0x100822e00 / 0x101b99cac / 0x101b8d8b8)
    // ⚑[tool=recover_swift_function_name ref=urlContext:0x100822e00 result=inferred]
    open var urlContext: UnsafeMutablePointer<URLContext>? { nil }

    // +0xb0 — open a sub-URL, returning the child AVIOContext* (the custom io_open dispatches here
    // via ioContext.metadata[+0xb0], storing the result into *pb and PBClass.pb). Sole concrete
    // override = HLSCacheIOContext.addSub. `interrupt:` is the format context's interrupt_callback
    // (AVIOInterruptCB, the 2-word s+0xd8/+0xe0 pair) the child reader polls to cancel.
    // ⚑[tool=recover_swift_function_name ref=addSub:0x101b97b2c result=high]
    open func addSub(url: URL, flags: Int32, options: UnsafeMutablePointer<OpaquePointer?>?, interrupt: AVIOInterruptCB) -> UnsafeMutablePointer<AVIOContext>? { nil }

    deinit {}
}
