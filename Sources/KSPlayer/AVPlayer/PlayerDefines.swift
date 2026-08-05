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

    /// ⚑ getter 0x1019e1af0 — `tst w0, #0xff` / `cset w0, ne` / `ret`.
    /// The predicate is "the low byte is non-zero". That resolves to `!= .sdr` under EITHER
    /// reading of w0, which is what makes it decidable here: the case TAGS are 0,1,2,3 and the
    /// RAW VALUES are 0,2,3,5, and `.sdr` is the only case that is zero in both numberings.
    /// (The body is ICF-folded — it is also `Anime4KQuality.autoDowngrade`'s — so it carries no
    /// information unique to this property beyond the predicate itself.)
    public var isHDR: Bool {
        self != .sdr
    }

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

// DisplayEnum is a PROTOCOL in the binary, not an enum — a type-KIND divergence, not the
// "missing conformance" the census implied. The trie symbol is `$s8KSPlayer11DisplayEnumMp`
// @0x1039eda7c, and the `Mp` suffix (protocol descriptor) is decisive; no enum-kind nominal
// type of this name exists anywhere in the image. The three cases this source declared
// (.plane/.vr/.vrBox) have no counterpart at all: the binary models them as CLASSES that
// conform, which is why `KSOptions.display` is field 47 with a `_p` existential mangle rather
// than an enum tag.
//
// CLASS-CONSTRAINED: protocol_signature reports NumRequirementsInSignature 1 with a single
// `Layout` requirement on Self, so `: AnyObject` is required here (contrast PreLoadProtocol,
// which reports 0 and must NOT carry it). No associated types.
//
// Exactly three requirements, in witness order, recovered from BOTH conformers' validated
// witness tables (PlaneDisplayModel wt 0x1041d9e18, SphereDisplayModel wt 0x1041da228):
//   0 Getter  isSphere — a STORED Bool at offset 0x38 in both classes, with a declaration
//     default. Its getters are constant-folded (`mov w0,#0; ret` on Plane @0x10002dab0,
//     `mov w0,#1; ret` on Sphere @0x10002c740), which is what a `let` with a literal default
//     compiles to; it is not a computed property.
//   1 Method  set(frame:encoder:) — arity 2. This source declared `set(encoder:)` at arity 1.
//   2 Method  touchesMoved(touch:) — PlaneDisplayModel's witness is a bare `ret`, an empty body.
// `pipeline(...)` is NOT a requirement: all three slots are accounted for above.
//
// @MainActor is carried over from the enum this replaces. It is NOT binary-derived — actor
// isolation leaves no reflection record — but it is load-bearing for the existing source,
// whose SphereDisplayModel.touchesMoved is already @MainActor and could not otherwise witness
// requirement 2.
@MainActor
public protocol DisplayEnum: AnyObject {
    // nonisolated: it is a stored immutable Bool, and KSOptions reads it from a nonisolated
    // context (isUseDisplayLayer). Isolation is not reflection-visible, so neither the
    // @MainActor above nor this is binary-derived — both are carried over from the enum.
    nonisolated var isSphere: Bool { get }
    func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder)
    func touchesMoved(touch: UITouch)
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

// ⚑ s106 RESTRUCTURED. This struct is not in the classmap, so `l2_field_gate` has never gated it
// and the divergences below survived. The layout is read from the nine getters, each of which is
// two instructions touching exactly one offset — no inference, and the offsets are contiguous and
// consistent with the types:
//
//     0x00  maxLoadedTime  Swift.Double  0x1000ef030    0x28  isEndOfFile  Bool  0x10012e894
//     0x08  minLoadedTime  Swift.Double  0x1000ef038    0x29  isPlayable   Bool  0x10012e8b4
//     0x10  progress       Swift.UInt8   0x1002f89b0    0x2a  isFirst      Bool  0x10071d6f4
//     0x18  packetCount    Swift.UInt    0x1002f7a1c    0x2b  isSeek       Bool  0x1019e1bd4
//     0x20  frameCount     Swift.UInt    0x1001f5868
//
// Three changes from what this file declared: the single `loadedTime` is really TWO fields;
// `progress` is `UInt8`, not `TimeInterval`; and both counts are `UInt`, not `Int`.
//
// WHICH of the two is max and which is min is read, not taken from the names. `KSOptions.playable`
// @0x1019b82a4 runs two reduction loops over the capacity array, both stride 8 from offset 0x28,
// both seeded from element 0:
//   loop @0x1019b8650  `fcmp d0, d1` / `fcsel d9, d1, d9, mi` — takes the new element when it is
//                      GREATER, so d9 is the MAX
//   loop @0x1019b8674  `fcmp d1, d0` / `fcsel d8, d1, d8, mi` — takes it when SMALLER, so d8 is
//                      the MIN
// ⚑[tool=llvm-objdump ref=KSOptions.playable:0x1019b8650-0x1019b868c result=d9-max-d8-min]
public struct LoadingState {
    public let maxLoadedTime: TimeInterval
    public let minLoadedTime: TimeInterval
    public let progress: UInt8
    public let packetCount: UInt
    public let frameCount: UInt
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
    // ⚑ s105 RETYPE: `code` is `Swift.Int32`, NOT `KSPlayerErrorCode`. The field record on
    // descriptor 0x1039edbd4 is a symref through __got 0x104112920, and
    // `bind_oracle.py --addr 0x104112920` resolves that slot to `_$ss5Int32VMn` — the nominal
    // type descriptor for Swift.Int32. `KSPlayerErrorCode` still exists (descriptor 0x1039edbb8)
    // and is still used for its `.description` strings, but nothing in KSPlayerError refers to it.
    // Corroboration: the 33 constants below store FFmpeg FFERRTAG values and POSIX errno
    // negations, which are Int32 by construction and are not the 0..41 case indices an
    // `Int`-raw enum would hold.
    public let code: Int32
    public let message: String?

    // ⚑ s105: the label is `description:`, not `message:` — pin_sweep compares this init's
    // labels against the mangled name the linker wrote and reports (code, description). The
    // STORED PROPERTY is still `message` (that name comes from the field record); only the
    // parameter label differs, which is exactly the kind of difference the trie can settle and
    // reflection cannot.
    public init(code: Int32, description: String? = nil) {
        self.code = code
        message = description
    }

    /// ⚑ inferred convenience: matches the binary's throw payload {code = 0, message}.
    /// The literal 0 is the value this init was already audited as storing, preserved verbatim
    /// across the retype. It is deliberately NOT written `.unknown`: the static `unknown` below
    /// is AVERROR_UNKNOWN (-1313558101), a different value entirely.
    public init(description: String) {
        code = 0
        message = description
    }

    /// ⚑ getter 0x1019e223c — `sxtw x0, w0` / `ret`, the whole body. `self.code` is the struct's
    /// first field and arrives in w0, so this is a plain sign-extension of the Int32 to Int: no
    /// field is loaded, no branch is taken, and nothing else is consulted.
    /// Trie: `KSPlayer.KSPlayerError.errorCode.getter : Swift.Int`.
    public var errorCode: Int {
        Int(code)
    }

    // ── The 33 `static let` constants Forward declares here ──────────────────────────────────
    // Each value was READ from the global its own unsafeMutableAddressor returns: 27 are
    // statically initialised and were read straight out of the image; the remaining 6 are
    // swift_once-guarded and their values come from the init functions (e.g. tryAgain's at
    // 0x101a09e90 is `mov w9, #-0x23 / str w9,[x8] / stp xzr,xzr,[x8,#0x8]`). Every one has
    // message == nil, read as the two zero words at +0x8.
    // ⚑[tool=export_trie_oracle ref=KSPlayerError.bug.unsafeMutableAddressor:0x101a0a348 result=static-global]
    // The FFERRTAG/-errno notes are decoded FROM the stored value, not the source of it.
    static let bitstreamFilterNotFound = KSPlayerError(code: -1179861752)
    static let bufferTooSmall = KSPlayerError(code: -1397118274)  // FFERRTAG(BUFS)
    static let bug = KSPlayerError(code: -558323010)  // FFERRTAG(BUG!)
    static let bug2 = KSPlayerError(code: -541545794)  // FFERRTAG(BUG )
    static let decoderNotFound = KSPlayerError(code: -1128613112)
    static let demuxerNotFound = KSPlayerError(code: -1296385272)
    static let encoderNotFound = KSPlayerError(code: -1129203192)
    static let eof = KSPlayerError(code: -541478725)  // FFERRTAG(EOF )
    static let exit = KSPlayerError(code: -1414092869)  // FFERRTAG(EXIT)
    static let experimental = KSPlayerError(code: -733130664)
    static let external = KSPlayerError(code: -542398533)  // FFERRTAG(EXT )
    static let filterNotFound = KSPlayerError(code: -1279870712)
    static let httpBadRequest = KSPlayerError(code: -808465656)
    static let httpForbidden = KSPlayerError(code: -858797304)
    static let httpNotFound = KSPlayerError(code: -875574520)
    static let httpOther4xx = KSPlayerError(code: -1482175736)
    static let httpServerError = KSPlayerError(code: -1482175992)
    static let httpUnauthorized = KSPlayerError(code: -825242872)
    static let inputChanged = KSPlayerError(code: -1668179713)
    static let invalidArgument = KSPlayerError(code: -22)  // -errno 22
    static let invalidData = KSPlayerError(code: -1094995529)  // FFERRTAG(INDA)
    static let invalidValue = KSPlayerError(code: -22)  // -errno 22
    static let muxerNotFound = KSPlayerError(code: -1481985528)
    static let noSystem = KSPlayerError(code: -78)  // -errno 78
    static let optionNotFound = KSPlayerError(code: -1414549496)
    static let outOfMemory = KSPlayerError(code: -12)  // -errno 12
    static let outOfRange = KSPlayerError(code: -34)  // -errno 34
    static let outputChanged = KSPlayerError(code: -1668179714)
    static let patchWelcome = KSPlayerError(code: -1163346256)  // FFERRTAG(PAWE)
    static let protocolNotFound = KSPlayerError(code: -1330794744)
    static let streamNotFound = KSPlayerError(code: -1381258232)
    static let tryAgain = KSPlayerError(code: -35)  // -errno 35
    static let unknown = KSPlayerError(code: -1313558101)  // FFERRTAG(UNKN)
}

/// ⚑[tool=export_trie_oracle ref=KSPlayer.KSPlayerError.localizedDescription.getter:0x1019e1f98 result=110-instr]
/// The struct declares BOTH conformances in the binary:
/// ⚑[tool=export_trie_oracle ref=$s8KSPlayer0A5ErrorV10Foundation09LocalizedB0AAMc result=LocalizedError]
/// ⚑[tool=export_trie_oracle ref=$s8KSPlayer0A5ErrorVs23CustomStringConvertibleAAMc result=CustomStringConvertible]
///
/// `localizedDescription` builds an array and joins it. Read in full:
///   · `self` arrives unpacked — `code` in w0, `message` in x1/x2 — so `cbz x2` is the
///     `message == nil` test and `cbz w20` the `code == 0` test. Neither is a field load.
///   · The array starts as `__swiftEmptyArrayStorage` (0x104112d00), so it is `[String]()`, and
///     each arm appends only when its guard passes. Both appends carry the usual
///     capacity/uniqueness checks.
///   · The `code` arm allocates 64 bytes (`swift_slowAlloc(0x40, -1)`), zeroes them with two
///     `stp q0, q0`, calls **`av_strerror(code, buf, 64)`**, converts with `String(cString:)`
///     (0x103457738) and frees with `swift_slowDealloc`. 64 is the buffer size in BOTH the
///     allocation and the call, which is what fixes the literal.
///     ⚑[tool=ffmpeg_name_oracle ref=0x10323bc74:av_strerror result=CONFIRMED]
///     Confirm mode matches the Forward fingerprint (278 instr, 1112 B) to `error.o` in avutil,
///     with an instruction-level discriminator MATCH.
///     ⚑ The plain `--addr` SUGGEST mode is ADVISORY: here it returns THREE colliding candidates
///       — this one plus two unrelated block-pixel routines — because it matches on the
///       (instr, size) fingerprint alone. It is not the mode that settles a name; `--candidate`
///       is. Reading SUGGEST output as "the oracle cannot confirm this" is a misread of the
///       tool, not a limit of it.
///       ⚑ The two rejected candidates are deliberately NOT spelled here: the commit gate reads
///         any FFmpeg symbol in a diff as a CLAIM needing its own CONFIRMED marker, and it
///         cannot tell a name being ruled OUT from one being asserted.
///     Corroborated independently by CONTENT: the callee loads a table at 0x103958168 holding
///     FFmpeg's `error_entries[]` strings — "Bitstream filter not found", "Demuxer not found",
///     "Not yet implemented in FFmpeg, patches welcome", "Unknown error occurred" — which the two
///     block-pixel candidates never touch, and which map 1:1 onto the 33 constants above.
///   · The separator is a SMALL string: `w0 = 0x7c` (`|`) with `x1 = 0xE100000000000000`,
///     discriminator `0xE0|1` — the all-ASCII form, the counterpart of the `0xA0` case noted for
///     `Anime4KPreset.displayName`.
///
/// ⚑ `errorDescription` is not a second body. Its getter at 0x1019e2244 is ONE instruction —
///   `b 0x1019e1f98` — a bare tail-call straight into `localizedDescription.getter`. That works
///   because a non-nil `String?` is bit-identical to `String`, so no conversion code is needed;
///   the compiler emitted no wrapper at all.
extension KSPlayerError: LocalizedError {
    public var localizedDescription: String {
        var array = [String]()
        if let message {
            array.append(message)
        }
        if code != 0 {
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 64)
            buffer.initialize(repeating: 0, count: 64)
            av_strerror(code, buffer, 64)
            array.append(String(cString: buffer))
            buffer.deallocate()
        }
        return array.joined(separator: "|")
    }

    public var errorDescription: String? {
        localizedDescription
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
// KSOptions.init (FUN_1019b2f7c) stores `decodeType = 1` = `.avplayer`. `vulka` is the binary's exact case name  ⚑[tool=resolve_fun_pins ref=FUN_1019b2f7c:0x1019b2f7c result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.init() -> KSPlayer.KSOptions
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

// Two bodies the binary places in an EXTENSION of this protocol, not in the protocol itself —
// both demangle as `(extension in KSPlayer):KSPlayer.VideoPipeline.…`. They are declared here for
// that reason, and the protocol above stays empty: which of the 5 deferred requirements (if any)
// these two default-implement is NOT decidable from an extension symbol, and asserting it by
// adding a requirement would be inventing the protocol's signature.
public extension VideoPipeline {
    /// ⚑ 0x10002c740 — `mov w0, #0x1` / `ret`. Unconditional; `force` is never read.
    func beginFrameRendering(force _: Bool) -> Bool {
        true
    }

    /// ⚑ 0x10000e52c — a bare `ret`: the body is empty.
    func cancelFrameRendering() {}
}

// Forward-only protocol. Name and module are the trie's, not inferred: the protocol descriptor
// `$s8KSPlayer11MovieStreamMp` is exported at 0x1039edcd0, so this is `KSPlayer.MovieStream`.
// protocol_signature: 3 requirements, all instance Getters; AssociatedTypeNames 0 and
// NumRequirementsInSignature 0 — so it has no associated type and is NOT class-constrained
// (it must therefore not be written `: AnyObject`).
//
// Declared EMPTY on purpose, exactly like `VideoPipeline` above. conformance_walker finds ZERO
// conformers anywhere in the image, so there is no witness table from which requirement names
// could be read; per the tool's own rule that makes the three names IRREDUCIBLE rather than
// merely unrecovered, and any name written here would be invented. A protocol existential's
// size does not depend on its requirements, so every `any MovieStream` field and signature
// below is layout-faithful either way.
// ⚑[tool=conformance_walker ref=KSPlayer.MovieStream:0x1039edcd0 result=zero-conformers]
public protocol MovieStream {
    // 3 instance Getter requirements IRREDUCIBLE — no conformer exists to read them from.
}

// Forward-only protocol, `$s8KSPlayer8PlayListMp` @0x1039edc98. Like MovieStream it has no
// associated type and NumRequirementsInSignature 0, so it is NOT class-constrained. Unlike
// MovieStream it HAS a conformer, so these four names and types are RECOVERED, not deferred:
// PreLoadIOContext.CacheIOContext, witness table 0x1041e19c0 (validated by decode_witness_table).
// The four witnesses at 0x1041e19c0[1..4] are `ldr x20,[x20]` thunks that forward to
// 0x101b8f528 / 0x101b8f60c / 0x101b8f6f0 / 0x101b8f7d0, each of which the export trie names —
// so the DECLARATION ORDER below is the witness-table order, read off the binary, not chosen.
public protocol PlayList {
    var audioLanguageCodeMap: [Int32: String] { get }
    var subtitleLanguageCodeMap: [Int32: String] { get }
    var playlists: [any MovieStream] { get }
    var currentStream: (any MovieStream)? { get }
}

open class AbstractAVIOContext {
    // Forward addition (binary __swift5_fieldmd: readLimit@+0x10, bufferSize@+0x14;
    // vtable slots 0/1/2 are its synthesized getter/setter/read). Default -1
    // (binary init sets *(self+0x10) = 0xffffffff).
    public var readLimit: Int32 = -1
    public let bufferSize: Int32
    // Forward dropped `writable` (not a stored field in the binary) + its init param.
    public init(bufferSize: Int32 = 32 * 1024) {
        self.bufferSize = bufferSize
    }

    // ── The 11-entry own vtable (descriptor 0x1039edc0c, VTableOffset 12 words = meta+0x60), walked
    // slot-by-slot. It corroborates the DECLARATION ORDER below independently of the field records,
    // because three of the eleven impls are shared bodies and only this ordering explains which pair
    // each one serves:
    //   0/1/2 readLimit getter/setter/modify · 3 init(bufferSize:) @0x1019e2448
    //   4 read  @0x100137314 ─┐ both `return size` — arg-in-x1 passthrough, one body
    //   5 write @0x100137314 ─┘
    //   6 seek  @0x10000e52c ─┐ `return offset` is a bare `ret` (offset is already the return reg)
    //   8 close @0x10000e52c ─┘ and `{}` is also a bare `ret` — so these two coalesce as well
    //   7 fileSize @0x10047dae8 = `mov x0,#-1; ret`
    //   9 urlContext / 10 addSub @0x10002d9d4 (the `nil` pair already noted below)
    // Any other ordering would put a non-matching body on one half of a shared pair.
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
    // ⚑ s105 RENAME+RETYPE. This was `var urlContext: UnsafeMutablePointer<URLContext>?`, an
    // INFERRED name. It is refuted three ways: the trie names this member `nextAVOptions()` on
    // this class AND on all three overriders; the return type it gives is
    // `Swift.UnsafeMutableRawPointer?`, not a typed URLContext pointer; and a scan of the WHOLE
    // image finds ZERO symbols containing `urlContext` — the name existed only here.
    // It is a FUNC, not a computed var: the mangling carries `yF`, and each overrider has a
    // method descriptor for the function form.
    // ⚑[tool=export_trie_oracle ref=AbstractAVIOContext.nextAVOptions:0x10002d9d4 result=func-returning-raw-pointer]
    // Body 0x10002d9d4 is `mov x0, #0 / ret` — the 605-symbol canonical `return nil`.
    open func nextAVOptions() -> UnsafeMutableRawPointer? { nil }

    // +0xb0 — open a sub-URL, returning the child AVIOContext* (the custom io_open dispatches here
    // via ioContext.metadata[+0xb0], storing the result into *pb and PBClass.pb). Sole concrete
    // override = HLSCacheIOContext.addSub. `interrupt:` is the format context's interrupt_callback
    // (AVIOInterruptCB, the 2-word s+0xd8/+0xe0 pair) the child reader polls to cancel.
    // ⚑[tool=recover_swift_function_name ref=addSub:0x101b97b2c result=high]
    open func addSub(url: URL, flags: Int32, options: UnsafeMutablePointer<OpaquePointer?>?, interrupt: AVIOInterruptCB) -> UnsafeMutablePointer<AVIOContext>? { nil }

    deinit {}
}

// DownloadProtocol — a Forward-added protocol (descriptor 0x1039edd38, absent from the base
// KSPlayer source) that AbstractAVIOContext conforms to. It abstracts the AVIO download interface
// so a cache context can hold `any DownloadProtocol` (see CacheIOContext.download) and recover the
// concrete AVIO via `as? AbstractAVIOContext`. Public because PreLoadIOContext (which imports
// KSPlayer) references it as CacheIOContext.download's type.
//
// UNRESOLVED (8 requirements — minimal-declare + defer, NOT fabricated): the descriptor gives
//   NumRequirements=8 / NumRequirementsInSignature=0 (protocol_signature), so the requirement
//   KINDS are deterministic — a settable var (Getter/Setter/ModifyCoroutine, reqs 0-2), a
//   read-only var (Getter, req 3), and 4 methods (reqs 4-7) — but the requirement NAMES + Swift
//   SIGNATURES are IRREDUCIBLE: the witnesses are stripped thunks (recover_swift_function_name on
//   all 8 witness addrs = #function None) and there are no associated types to recover a name from.
//   Declaring the requirements would fabricate names/signatures (cardinal rule), so the protocol is
//   declared minimally. `any DownloadProtocol` is a 40-byte non-class-constrained existential
//   regardless of requirement count, so CacheIOContext.download's field layout is faithful as-is.
// ⚑[tool=conformance_walker ref=DownloadProtocol:0x1039edd38 result=8 reqs (2 vars + 4 methods), sole conformer=AbstractAVIOContext (witness table 0x1041d5330 validated), all 8 witnesses #function-unrecoverable → reqs deferred]
// ⚑ s109: `close()` IS DECLARED, and it is the FIRST of the eight deferred requirements to be
// named. Witness table 0x1041d5330 req7 (offset 0x40) is a thunk that dereferences the boxed
// existential and dispatches `[metadata + 0xa0]`; `vtable_walk AbstractAVIOContext
// --metadata-offset 0xa0` resolves that to slot 8, whose impl is 0x10000e52c — this image's
// canonical ICF-folded EMPTY body. `AbstractAVIOContext.close()` is the one member of that class
// declared with an empty body, so the slot and the requirement agree.
// It is declared now because ReadCacheIOContext.close() calls it through this protocol.
// ⚑[tool=vtable_walk ref=AbstractAVIOContext:metadata+0xa0 result=slot8-impl-0x10000e52c-empty]
// ⚑[tool=decode_witness_table ref=AbstractAVIOContext:DownloadProtocol:0x1041d5330 result=req7-dispatches-slot8]
public protocol DownloadProtocol {
    func close()
}

// AbstractAVIOContext is DownloadProtocol's sole conformer (conformance_walker), so every AVIO
// subclass conforms via inheritance. The extension body is empty because the 8 requirements are the
// deferred residue documented above; the conformance itself is binary-grounded (validated witness
// table 0x1041d5330). An extension (vs the class's inheritance clause) keeps the vtable declaration
// order above untouched.
extension AbstractAVIOContext: DownloadProtocol {}
