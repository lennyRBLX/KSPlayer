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
import Foundation
import Metal
import OSLog
import QuartzCore
#if canImport(UIKit)
import UIKit

// ⚑ s112 — TWO divergences read here, both left UNAPPLIED because they belong to the isolation unit
//   that gates `KSOptions.displayEnumVR`/`displayEnumVRBox` (see KSOptions.swift), and that unit is
//   cross-cutting: `sceneSize` has five call sites. Recorded so it starts from evidence.
//
//   1. OWNER. `sceneSize` is not a `KSOptions` member in the binary. The only symbols carrying the
//      name are `$sSo13UIApplicationC8KSPlayerE9sceneSizeSo6CGSizeVvgZ` @0x101a01d1c and its
//      `vpZMV` — a KSPlayer extension on `__C.UIApplication`, public by the property descriptor.
//      No `KSOptions`-owned `sceneSize` symbol exists.
//      ⚑[tool=export_trie_oracle ref=UIApplication.sceneSize:0x101a01d1c result=owner-is-UIApplication]
//
//   2. ACCESS. `windowScene` has NO trie symbol at all — zero hits for the name — so it is not
//      public, while this `public extension` makes it public. Its code is real and factored
//      differently: the getter body is `UIApplication.shared` (classref 0x1044104f8) -> a private
//      55-instruction body @0x101a02de0 that sends `windows` and takes `.first` -> `bounds`, and
//      the `connectedScenes.first as? UIWindowScene` step is a further private body @0x101a02f64.
//      So the two-property split below is right in substance; only the owner and the access are not.
//      ⚑[tool=export_trie_oracle ref=KSOptions.windowScene:0x101a02f64 result=NOT_IN_TRIE]
//
//   ⚠️ The `@MainActor` on both is NOT settled by the above. The getter body shows no actor hop, but
//      a `@MainActor` static's isolation is enforced at the CALLER, so an unhopped getter is weak
//      evidence. The load-bearing test is whether `VRDisplayModel.init()` — which reads `sceneSize`
//      — reaches it without a hop; that init has no trie symbol and is reached by `blr` from the
//      once-init @0x1019bc664, so settling it means reading that chain. Do not delete `@MainActor`
//      on the strength of the getter alone.
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
// ⚑ L7 lane 10: protocol_surface's "drop set(frame:encoder:)" is a thunk_callee misattribution —
// both Forward witness tables carry it: PlaneDisplayModel wt 0x1041d9e18 [+0x10 = 0x101a82018,
// vtable +0x108 dispatch thunk], SphereDisplayModel wt 0x1041da228 [+0x10 = 0x101a8c5a4, vtable
// +0x198 thunk]. Isolation evidence points the other way from this @MainActor: both conformance
// descriptors have flags 0 (no isolated conformance), the witnesses have no executor check, and
// MetalRender 0x101a873b4 / 0x101a86090 call `set` with none. Kept @MainActor because a
// `nonisolated` requirement does not typecheck (L7 lane 12 probe, 11 errors): the witnesses read
// class-isolated state (pipeline(pixelBuffer:), posBuffer/uvBuffer/indexBuffer, modelViewMatrix) and
// SphereDisplayModel.set calls the @MainActor MotionSensor.shared.matrix() (Metal/MotionSensor.swift);
// DoviDisplayModel.set also overrides it. Unpicking that is a cross-file isolation unit (writer GAP).
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
    // ⚑[tool=field_surface ref=VideoAdaptationState.loadedCount result=forward Swift.UInt; vpfi 0x10002d9d4 = 0]
    public internal(set) var loadedCount: UInt = 0
}

// ⚑[tool=field_surface ref=ClockProcessType:0x1039edb30 result=7 records: dropFrame(count: Int), empty, remain, next, dropGOPPacket, flush, seek]
//   `dropNextFrame` → `dropFrame(count:)` (payload records sort first, so its source slot is not
//   fixed by the record). `dropNextPacket` had no producer and no Forward record: removed with its
//   switch arm. No declared conformances, so the payload case costs the synthesized `==`.
public enum ClockProcessType {
    case dropFrame(count: Int)
    case empty
    case remain
    case next
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
    // 7th requirement (wt+0x38): KSOptions.playable @0x1019b84b4 does `ldr x8,[x26,#0x38]; blr` and
    // stores d0 into the mapped array — `capacitys.map(\.loadedTime)`. Order +0x8..+0x30 above is
    // consistent with the same function (+0x10/+0x18 counts, +0x28 isEndOfFile).
    // ⚑ Forward packetCount/frameCount are UInt (`adds x22,x21,x0; b.hs` @0x1019b8598/0x1019b85ec);
    // types kept Int here — conformers are lane 11 (GAP).
    var loadedTime: TimeInterval { get } // INFERRED 0x1019b84b4 wt+0x38
}

extension CapacityProtocol {
    var loadedTime: TimeInterval {
        TimeInterval(packetCount + frameCount) / TimeInterval(fps)
    }

    // @0x1019e1b6c (just before LoadingState.isSeek 0x1019e1bd4): wt+0x28 isEndOfFile, then
    // wt+0x10 packetCount == 0, then wt+0x18 frameCount == 0, short-circuit in that order.
    var isFinished: Bool { // INFERRED 0x1019e1b6c
        isEndOfFile && packetCount == 0 && frameCount == 0
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
    // ⚑[tool=field_surface ref=LoadingState.maxLoadedTime result=forward var (IsVar); siblings let]
    public var maxLoadedTime: TimeInterval
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

// ⚑ RAW TYPE AND CASE SET REBUILT FROM THE BINARY. This enum was `: Int` with 22 cases; the image
//   says `: String` with 19, and the raw values ARE the message strings — which is why the
//   `CustomStringConvertible` extension that used to sit below is GONE rather than edited.
//
//   The raw type is read, not inferred: the trie carries `rawValue.getter` as `SSvg` (String) and
//   `init(rawValue: String)`, while `init(rawValue: Int)` and `description.getter` are real trie
//   NEGATIVES. `KSPlayerErrorCode` exports 9 symbols in total — rawValue ×3, init(rawValue:),
//   Ma/Mn/N, and SH/SQ/SY — and no CustomStringConvertible conformance at all. That conformance
//   belongs to `KSPlayerError` instead (getter 0x1019e2150), not to this enum.
//
//   The 19 case NAMES and their ORDER come from the field records on descriptor 0x1039edbb8. The 19
//   raw VALUES were each decoded by the orchestrator from the `rawValue` getter's own 19-arm byte
//   table (getter 0x1019e1be0-0x1019e1e38, table @0x103568513): sixteen are heap literals, decoded
//   individually with decode_string_literal; three are register-form small strings whose bytes were
//   read straight out of the immediates — `avio_ope`+`n fail` (x0=0x65706F5F6F697661,
//   x1=0xEE006C696166206E), `readFram`+`e fail`, and `no strea`+`m found`.
//
//   Relative to the old 22: ADDED `avioOpen` and `noStream`; REMOVED `unknown`,
//   `codecContextFindDecoder`, `codecVideoSendPacket`, `codecAudioSendPacket` and `auidoSwrInit`;
//   and the order differs. Every removed case had its source references re-pointed in this change.
//
//   FFmpeg provenance (P32) for this whole change. The names below occur inside DECODED STRING
//   LITERALS rather than at call sites, but each is also confirmed at its real call address by
//   ffmpeg_name_oracle, re-run for this commit rather than quoted from an older marker:
// ⚑[tool=ffmpeg_name_oracle ref=avformat_alloc_context:0x1031b85bc result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avformat_open_input:0x1030e5dac result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avformat_find_stream_info:0x1030e8520 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avformat_alloc_output_context2:0x103193858 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avformat_write_header:0x1031941d8 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_to_context:0x1029f5974 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avcodec_open2:0x10294caf8 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
// ⚑[tool=ffmpeg_name_oracle ref=av_frame_alloc:0x103240100 result=CONFIRMED]
//   ONE symbol resists confirmation and is deliberately NOT claimed as confirmed: the codec-context
//   allocator whose name appears inside case `codecContextCreate`'s raw value below. Its call site in
//   this image is 0x102d5394c — adjacent to the confirmed avcodec_free_context in the same
//   avcodec/options.o — and the oracle answers UNKNOWN there, refuting the candidate at instruction
//   index 41 ('add x8, x8, @' vs 'ldr x8, [x8, @]'), i.e. the built library differs from this image at
//   that function. That name survives in this file only as decoded string DATA, never as a claim
//   about a call. Recorded in reconstruction/deferral_s118_avcodec_alloc_context3.md.
// ⚑[tool=fieldrec ref=KSPlayerErrorCode:0x1039edbb8 result=19-cases-String-raw]
public enum KSPlayerErrorCode: String {
    case formatCreate = "avformat_alloc_context return nil"
    case formatOpenInput = "avformat can't open input"
    case avioOpen = "avio_open fail"
    case formatOutputCreate = "avformat_alloc_output_context2 fail"
    case formatWriteHeader = "avformat_write_header fail"
    case formatFindStreamInfo = "avformat_find_stream_info return nil"
    case readFrame = "readFrame fail"
    case noStream = "no stream found"
    case codecContextCreate = "avcodec_alloc_context3 return nil"
    case codecContextSetParam = "avcodec can't set parameters to context"
    case codesContextOpen = "codesContext can't Open"
    case codecVideoReceiveFrame = "avcodec can't receive video frame"
    case codecAudioReceiveFrame = "avcodec can't receive audio frame"
    case codecSubtitleSendPacket = "avcodec can't decode subtitle"
    case videoTracksUnplayable = "VideoTracks are not even playable."
    case subtitleUnEncoding = "Subtitle encoding format is not supported."
    case subtitleUnParse = "Subtitle parsing error"
    case subtitleFormatUnSupport = "Current subtitle format is not supported"
    case subtitleParamsEmpty = "Subtitle Params is empty"
}

// ⚑ THE `CustomStringConvertible` EXTENSION IS REMOVED, and its absence is the finding.
//   `KSPlayerErrorCode.description.getter` is a real trie NEGATIVE — the enum exports 9 symbols and
//   none of them is a description getter, nor is there a CustomStringConvertible conformance record
//   for it. The switch that stood here returned exactly the strings that are now the enum's raw
//   values, so nothing is lost: every `.description` call site becomes `.rawValue`, which is the
//   same String by construction. The conformance the binary DOES carry is on `KSPlayerError`
//   (getter 0x1019e2150), which is a different type and its own unit.
//   Its `default: return "unknown"` arm is gone with the `unknown` case it existed to serve, and
//   its `auidoSwrInit` arm is gone with that case — neither exists in the image.

/// Forward-new error type. The shipped 1.3.17 binary replaces the upstream `extension NSError` error
/// model with this struct — descriptor 0x1039edbd4 (kind=struct), ~70+ uses app-wide (KSPlayer core +
/// FFmpeg wrappers + ProAVPlayer). Binary-confirmed fields: `code: KSPlayerErrorCode` (a symbolic-ref
/// nominal — corrects the prior recon's `Int32`; stdlib Int32 would use standard mangling, not a
/// symbolic ref), `message: String?` (mangle `SSSg`). ⚑ the initializers are inferred: the binary
/// inlines construction (`_swift_allocError` + store {code, message}), so no distinct init survives to
/// decompile. ⚑ base-regression: the reconstruction base still carries the upstream `extension NSError`
/// (below); migrating its call sites to this struct is a tracked structural gap.
// ⚑[tool=type_surface ref=KSPlayerError:0x1039edbd4 result=CustomNSError@0x103568710,CustomStringConvertible@0x103568750]
// (Error is implied by CustomNSError; LocalizedError is the extension below.)
public struct KSPlayerError: CustomNSError, CustomStringConvertible {
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
    public init(errorCode: KSPlayerErrorCode) {
        code = 0
        message = errorCode.rawValue
    }

    // ⚑ s105: the label is `description:`, not `message:` — pin_sweep compares this init's
    // labels against the mangled name the linker wrote and reports (code, description). The
    // STORED PROPERTY is still `message` (that name comes from the field record); only the
    // parameter label differs, which is exactly the kind of difference the trie can settle and
    // reflection cannot.
    // ⚑ TWO SEPARATE INITS, not one with a defaulted parameter. The trie carries
    //   `init(code:)` at 0x1019e1f88 (3 instructions — store code, store a nil message, return) and
    //   `init(code:description:)` at 0x10000e52c as DISTINCT symbols. A defaulted `description:`
    //   would emit one init plus a default-argument generator, not two inits, and the trie has no
    //   such generator here.
    //   The label is `description:` and its type is **String, NOT String?** — the optionality lives
    //   on the stored property `message` (`SSSg`), which the nil-message init writes directly.
    //   ⚑[tool=export_trie_oracle ref=KSPlayerError.init(code:):0x1019e1f88 result=3-instr-message-nil]
    public init(code: Int32) {
        self.code = code
        message = nil
    }

    public init(code: Int32, description: String) {
        self.code = code
        message = description
    }

    /// ⚑ The only one of KSPlayerError's four inits that is actually CALLED — once, from
    /// `FFmpegDecode.decodeFrame` at 0x101a229fc. The trie names it at 0x1019e1f94, which is a
    /// ONE-instruction forwarder `b 0x1019e429c`; the real body is at 0x1019e429c and contains
    /// ZERO `bl`. It does NOT call `.description`, does NOT call FFmpeg's error-string helper, and wraps no
    /// `AVError`: it stores `avErrorCode` into `code` verbatim — an x8 pass-through, untouched on
    /// all 19 exits — and inlines the enum's own `rawValue` switch for `message` as a 19-way jump
    /// table at 0x103568526, the same literal set the `rawValue` getter uses.
    /// ⚑[tool=export_trie_oracle ref=KSPlayerError.init(errorCode:avErrorCode:):0x1019e1f94 result=1-instr-forwarder-to-0x1019e429c]
    public init(errorCode: KSPlayerErrorCode, avErrorCode: Int32) {
        code = avErrorCode
        message = errorCode.rawValue
    }

    // ⚑ `init(description:)` IS REMOVED — it was an inferred convenience with NO trie symbol, and
    //   the trie's four KSPlayerError inits are `init(code:)`, `init(code:description:)`,
    //   `init(errorCode:)` and `init(errorCode:avErrorCode:)`. Its three call sites carried a
    //   literal `code = 0`, which every one of them now spells outright as
    //   `KSPlayerError(code: 0, description:)`. Nothing about the constructed value changes; what
    //   changes is that the source no longer declares an initializer the image does not have.
    //   Dead-strip is excluded as an explanation: `init(errorCode:)` and `init(code:)` both survive
    //   in the trie with zero call sites, so an unused init is NOT stripped from this image.

    /// ⚑ getter 0x1019e223c — `sxtw x0, w0` / `ret`, the whole body. `self.code` is the struct's
    /// first field and arrives in w0, so this is a plain sign-extension of the Int32 to Int: no
    /// field is loaded, no branch is taken, and nothing else is consulted.
    /// Trie: `KSPlayer.KSPlayerError.errorCode.getter : Swift.Int`.
    public var errorCode: Int {
        Int(code)
    }

    public var description: String {
        "Error Domain=KSPlayerError Code=\(code) Message=\(localizedDescription)"
    }
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
            let string = String(cString: buffer)
            buffer.deallocate()
            array.append(string)
        }
        return array.joined(separator: "|")
    }

    public var errorDescription: String? {
        localizedDescription
    }
}

// ⚑ THE UPSTREAM `extension NSError` ERROR MODEL IS REMOVED. This is the base regression the
//   reconstruction has tracked since the KSPlayerError struct was recovered, and it is now closed by
//   an exhaustive sweep rather than by preference.
//
//   All FOURTEEN `NSError(...)` sites in the tree were derived. THIRTEEN construct a `KSPlayerError`
//   inline — `_swift_allocError(0x1041d5790, …)`, then `str <code>,[x1]`, then `stp <message>,[x1,#8]`
//   — and one (VideoToolboxDecode's synchronous decodeFrame) constructs nothing at all. **No site
//   anywhere in the image constructs an NSError, sets an error domain, or builds a `userInfo`
//   dictionary.** Two catch sites confirm the type from the other direction: both call
//   `swift_dynamicCast` with destination type 0x1041d5790 — KSPlayerError's metadata — and then read
//   the Int32 at value-offset 0.
//
//   These two inits could not survive the enum's real shape in any case: `code: errorCode.rawValue`
//   needs an Int and the raw values are Strings, and `errorCode.description` needs a getter that is a
//   real trie negative. That incompatibility is evidence, not an obstacle — it is the compiler
//   showing the two error models are mutually exclusive.
// ⚑[tool=export_trie_oracle ref=KSPlayerError.metadata:0x1041d5790 result=13-of-14-sites-allocError-0-NSError]

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
    // @0x1019ecbec: scvtf/ucvtf into s0, then calls Float.kmFormatted @0x1019ecd98 (not Double's).
    var kmFormatted: String {
        Float(self).kmFormatted
    }
}

// @0x1019ecd98 — Forward-only Float overload (follows FixedWidthInteger.kmFormatted in the image).
// Thresholds are the s-register literals: 0x4eee6b28 = 2e9, 0x49742400 = 1e6, 0x461c4000 = 1e4;
// divisors 0x4e6e6b28 = 1e9, 1e6, 0x447a0000 = 1000. No upper-bound test on the K arm.
public extension Float {
    var kmFormatted: String {
        if self >= 2_000_000_000 {
            return String(format: "%.1fG", locale: Locale.current, self / 1_000_000_000)
        } else if self >= 1_000_000 {
            return String(format: "%.1fM", locale: Locale.current, self / 1_000_000)
        } else if self >= 10000 {
            return String(format: "%.1fK", locale: Locale.current, self / 1000)
        } else {
            return String(format: "%.0f", locale: Locale.current, self)
        }
    }
}

// Forward-only enum (binary-confirmed name `DecodeType`). Binary reflection (__swift5_fieldmd via the field-record
// oracle, desc @0x1039edfec): 5 no-payload cases in this ORDER, 1-byte storage. Case indices are binary-pinned —
// KSOptions.init (FUN_1019b2f7c) stores `decodeType = 1` = `.avplayer`. `vulka` is the binary's exact case name  ⚑[tool=resolve_fun_pins ref=FUN_1019b2f7c:0x1019b2f7c result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.init() -> KSPlayer.KSOptions
// (reflection-read; reads like a truncation of "vulkan" but is what Forward ships — searched, no standalone "vulkan").
// ⚑[tool=type_surface ref=DecodeType:0x1039edfec result=RawRepresentable(RawValue=String)@0x1035689e0]
// L7: raw values are the implicit case names; Forward's rawValue body was not read.
public enum DecodeType: String {
    case asynchronousHardware
    case avplayer
    case hardware
    case soft
    case vulka
}

// Forward-only protocol (binary-confirmed name `VideoPipeline`). Binary (conformance_walker, proto descriptor
// @0x1039edab8) validates five requirements in declaration order: one getter followed by four methods, with
// Anime4KPipeline as the validated conformer.
public protocol VideoPipeline {
    var inputTexture: MTLTexture? { get }
    func configure(pixelBuffer: any PixelBufferProtocol) -> CGSize?
    func encode(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture)
    func beginFrameRendering(force: Bool) -> Bool
    func cancelFrameRendering()
}

// The default implementations below satisfy VideoPipeline requirements 3 and 4; their bodies remain unchanged.
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
// conformance_walker finds ZERO conformers, so no witness table names these requirements; the
// TYPES below are recovered from the Forward call sites that dispatch through the witness table,
// and the NAMES are INFERRED from how each value is used.
//   +0x8  String   — 0x101ae1c90 `playList.currentStream?.<req1>` → String?; keypath getter thunk
//                    0x101af4a2c returns String (the id of ForEach<[MovieStream], String, …>);
//                    0x101ae28ac builds `<req1> + " duration=" + …`.
//   +0x10 Double   — FormatContext.init 0x101a35338..0x101a3534c compares it against
//                    Double(durSecs + 3600) and stores `Int64(value * 1e6)` into formatCtx.duration;
//                    UI 0x101adfd14 filters playlists by `$0.<req2> > 120.0`.
//   +0x18 [any PlayFileProtocol] — 0x28-stride single-protocol existential array: FormatContext
//                    0x101a3538c..0x101a353ac `seekByBytes = <req3>.count >= 2`; MEPlayerItem.reading
//                    0x101a51634 walks it reading elem wt+0x8 (Double) and wt+0x20 (Int), which only
//                    PlayFileProtocol's 4-getter shape fits.
// ⚑[tool=conformance_walker ref=KSPlayer.MovieStream:0x1039edcd0 result=zero-conformers]
public protocol MovieStream {
    var name: String { get } // INFERRED 0x101ae1c90 / 0x101af4a2c
    var duration: TimeInterval { get } // INFERRED 0x101a35338 / 0x101adfd14
    var files: [any PlayFileProtocol] { get } // INFERRED 0x101a3538c / 0x101a51634
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
    // ⚑ s109 TYPE CORRECTION: `buffer` is `UnsafeMutablePointer`, not `UnsafePointer`. The trie
    //   carries `…read(buffer: Swift.UnsafeMutablePointer<Swift.UInt8>?, size: Swift.Int32)` at
    //   0x100137314, which is exactly this vtable's slot 4 impl, and the `UnsafePointer` spelling
    //   is ABSENT from the trie. `write` below keeps `UnsafePointer` — its own trie entry uses it.
    //   The two share impl 0x100137314 only because both bodies are `{ size }` and ICF folds
    //   byte-identical code; the shared impl says NOTHING about the signatures, which is why each
    //   was probed separately.
    // ⚑[tool=export_trie_oracle ref=AbstractAVIOContext.read(buffer:size:):0x100137314 result=UnsafeMutablePointer-not-UnsafePointer]
    open func read(buffer _: UnsafeMutablePointer<UInt8>?, size: Int32) -> Int32 {
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
// ⚑ s109: ALL EIGHT REQUIREMENTS ARE NOW NAMED, and the "deferred residue" note is discharged.
// Witness table 0x1041d5330 has 8 entries and each was resolved by reading its thunk, never by
// counting or by matching names:
//   req0 @0x8  read of `[self+0x10]` as a 32-bit word under a (0,0) READ beginAccess
//   req1 @0x10 store of a 32-bit word to `[self+0x10]` under a (1,0) MODIFY beginAccess
//   req2 @0x18 the same slot under flags 0x21 (Modify|Tracking) with a coroutine continuation
//        -> so +0x10 is a get/set/modify property. fieldrec gives this class exactly two fields,
//           `readLimit` (flags=2, i.e. var) at +0x10 and `bufferSize` (flags=0, i.e. let) at +0x14.
//   req3 @0x20 `ldr w0,[x8,#0x14]` with NO beginAccess at all — the missing exclusivity check is
//        itself the evidence: a `let` needs none. That is `bufferSize`, get-only.
//   req4 @0x28 dispatches metadata+0x80 -> vtable slot 4, impl 0x100137314
//   req5 @0x30 dispatches metadata+0x90 -> vtable slot 6, impl 0x10000e52c
//   req6 @0x38 dispatches metadata+0x98 -> vtable slot 7, impl 0x10047dae8
//   req7 @0x40 dispatches metadata+0xa0 -> vtable slot 8, impl 0x10000e52c
// The 11-slot vtable runs Getter/Setter/Modify (readLimit), Init, then the seven open methods in
// this file's declaration order: read, write, seek, fileSize, close, nextAVOptions, addSub. So
// slots 4/6/7/8 are read / seek / fileSize / close. Two impls corroborate that mapping rather than
// merely fitting it: slots 6 and 8 share 0x10000e52c because `seek` returns its own `offset`
// argument — already in x0, so a bare `ret` — and `close` is empty, and ICF folds only
// byte-identical bodies; slot 7 is 0x10047dae8 on its own because `fileSize` returns −1.
// NOTE what is NOT a requirement: `write` (slot 5), `nextAVOptions` (9) and `addSub` (10). The
// protocol is 8 requirements, not "the class's methods".
// ⚑[tool=decode_witness_table ref=AbstractAVIOContext:DownloadProtocol:0x1041d5330 result=8-requirements]
// ⚑[tool=vtable_walk ref=AbstractAVIOContext:0x1039edc0c result=11-slots-mapped]
public protocol DownloadProtocol {
    var readLimit: Int32 { get set }
    var bufferSize: Int32 { get }
    func read(buffer: UnsafeMutablePointer<UInt8>?, size: Int32) -> Int32
    func seek(offset: Int64, whence: Int32) -> Int64
    func fileSize() -> Int64
    func close()
}

// AbstractAVIOContext is DownloadProtocol's sole conformer (conformance_walker), so every AVIO
// subclass conforms via inheritance. The extension body is empty because the 8 requirements are the
// deferred residue documented above; the conformance itself is binary-grounded (validated witness
// table 0x1041d5330). An extension (vs the class's inheritance clause) keeps the vtable declaration
// order above untouched.
extension AbstractAVIOContext: DownloadProtocol {}

// Forward-only protocol, `$s8KSPlayer8DrawableMp` @0x1039eda20. It exists to type
// `MetalPlayView.drawable`, whose field record is a NON-optional existential (`_p`, no `Sg`) and
// whose accessors the trie names `KSPlayer.MetalPlayView.drawable.getter/setter/modify :
// KSPlayer.Drawable`.
//
// protocol_signature: 2 requirements, BOTH instance Methods; NumRequirementsInSignature 0, so it
// is NOT class-constrained and must not be written `: AnyObject`; no associated types.
//
// Requirement names come from the L7 lane 10/12 walk of __swift5_proto: all three witness tables
// (CAMetalLayer wt 0x1041d9e70, RealityKit.TextureResource wt 0x1041d9ea0, TextureResource.DrawableQueue
// wt 0x1041d9ed0) forward +0x8 to each conformer's exported
// `draw(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?)` (0x101a856dc → 0x101a854b0,
// 0x101a85e60 → 0x101a85778, 0x101a85ec8 → 0x101a85cac) and +0x10 to its exported `clear()`
// (0x101a856fc, 0x101a85e80, and DrawableQueue's ICF'd `ret` 0x10000e52c). The conformer descriptors are
// the ones in MetalRender.swift (cd 0x10356c4f8 / 0x10356c528 / 0x10356c548); the three types' draw and
// clear are exported, so public witnesses satisfy this public protocol.
//
// The trie's `(extension in KSPlayer):RealityKit.TextureResource.Drawable.present(commandBuffer:)` is
// RealityKit's NESTED TextureResource.Drawable (a KSDrawable conformer), not a requirement here.
// ⚑[tool=witness_walk ref=KSPlayer.Drawable:0x1039eda20 result=+0x8 draw(frame:display:pipeline:), +0x10 clear()]
public protocol Drawable {
    func draw(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?)
    func clear()
}

// DrawableRenderResult @0x1039eda48 (`$s8KSPlayer20DrawableRenderResultMp` is NOT in the export trie → internal),
// the descriptor right after Drawable's. protocol_signature: requirement +0x8 is the base-protocol
// entry `Self: Drawable`, +0x10 one instance method. Conformers CAMetalLayer (cd 0x10356c518,
// wt 0x1041d9e88 → 0x101a85750 → 0x101a854b0), TextureResource (cd 0x10356c538, wt 0x1041d9eb8 →
// 0x101a85ea0 → 0x101a85778) and DrawableQueue (cd 0x10356c558, wt 0x1041d9ee8 → 0x101a85ee8 →
// 0x101a85cac). The method name is the `#function` string each of those Bool bodies passes to KSLog,
// "drawWithResult(frame:display:pipeline:)", and the return is their `w0` Bool.
protocol DrawableRenderResult: Drawable {
    func drawWithResult(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?) -> Bool
}

//  Reconstructed binary-faithful from Forward 1.3.17 (KSPlayer module).
// In-memory cache record of the IO foundation. NOT final: vtable slots 9-12 (the binary's
// inits call `_swift_allocObject`; `init(from:)` calls
// `_swift_deallocPartialClassInstance`). Conforms to `Codable` — slots 11
// (`encode(to:)`) and 12 (`init(from:)`) are Swift's AUTO-SYNTHESIZED Codable
// methods (verified: ordered integer CodingKeys 0–4 = declaration order, with
// `encodeIfPresent` for the single Optional). Properties are declared in key
// order 0–4 so that synthesis matches the binary's key order.
// Forward-only protocol, `$s8KSPlayer18CacheEntryProtocolMp` @0x1039edec8 — module KSPlayer,
// NOT PreLoadIOContext (that spelling is a real trie negative). It is a LEAF: 2 requirements,
// both instance Getters, both stdlib scalars, and NumRequirementsInSignature 0 so it is not
// class-constrained. Two conformers, both with validated witness tables:
//   CacheEntry     wt 0x1041d5378  req0 0x1019e30a4 (position)  req1 0x1019e30b8 (size)
//   CacheFileEntry wt 0x1041e19e8  req0 0x101b90b48 (position)  req1 0x101b90b5c (size)
// Requirement ORDER and both widths are read off those witnesses: req0 returns x0 (64-bit),
// req1 returns w0 (32-bit); the trie independently names CacheEntry.position.getter : UInt64
// @0x1019e3094 and CacheEntry.size.getter : UInt32 @0x1019e2750.
// `public` because PreLoadIOContext.CacheFileEntry conforms to it across the module boundary
// and PreLoadIOContext exposes `[any CacheEntryProtocol]`. Public vs package is not decidable
// from the image — access level is not carried in the mangling and both export a descriptor —
// so this follows the in-tree precedent for Forward's other recovered protocols.
public protocol CacheEntryProtocol {
    var position: UInt64 { get }
    var size: UInt32 { get }
}

public class CacheEntry: CacheEntryProtocol, Codable {
    // field types pinned from mangled property descriptors (authoritative — demangled):
    //   CacheEntry.logicalPos : Swift.Int64   ·  .physicalPos : Swift.UInt64
    //   CacheEntry.size : Swift.UInt32  ·  .maxSize : Swift.UInt32?  ·  .eof : Swift.Bool
    //
    // logicalPos was UInt64 here and the comment asserting the mangling `logicalPoss6UInt64Vv`
    // was FALSE. Three independent reads say Int64:
    //   1. l2_field_gate raises a REAL_FLAG — source UInt64 vs binary Int64.
    //   2. The export trie HAS $s8KSPlayer10CacheEntryC10logicalPoss5Int64Vvg @0x100137008 and
    //      the `s6UInt64V` spelling is a real trie negative — no address exports that name.
    //   3. The CacheEntryProtocol `position` witness @0x1019e30a4 is
    //      `ldr x0,[x8,#0x10]` / `tbnz x0,#0x3f` / `ret` / `brk #0x1` — a sign-bit test that
    //      traps. That trap is Swift's UInt64(Int64) conversion guard and is only emitted when
    //      the source value is SIGNED; on a UInt64 field no test would exist at all.
    // The reflection field records corroborate the split: logicalPos resolves through the same
    // type __got slot as CacheIOContext.fetchedSize (gate-confirmed SIGNED), while physicalPos
    // resolves through the UInt64 slot that CacheFileEntry.position uses.
    public let logicalPos: Int64    // +0x10, 8B  (mangled: logicalPoss5Int64Vv)
    public let physicalPos: UInt64  // +0x18, 8B  (mangled: physicalPoss6UInt64Vv)
    public var size: UInt32         // +0x20, 4B  (mangled: size...s6UInt32V; bounds-check compares UNSIGNED)
    public var eof: Bool = false    // +0x24, 1B  (reflection `Sb`; initial value: 0x1019e2928 strb wzr precedes the param stores)
    public var maxSize: UInt32?     // +0x28 value / +0x2c discriminator (mangled: maxSizes6UInt32VSgv; encodeIfPresent)

    // Slot 9 memberwise init @0x1019e28dc: stores logicalPos(+0x10),
    // physicalPos(+0x18), size(+0x20) from params; eof(+0x24) defaults to
    // false (init writes 0); maxSize(+0x28/+0x2c) stored from the Optional
    // param. There is no `eof` parameter — the binary always initialises it false.
    @used init(logicalPos: Int64, physicalPos: UInt64, size: UInt32, maxSize: UInt32?) {
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        // eof: declaration default. maxSize: assigned after full init (0x1019e294c swift_beginAccess, flags 1).
        self.maxSize = maxSize
    }

    // Slot 10 method @0x1019e29e4 (bounds/space check).
    // ⚑ s105 RENAME+LABEL: this was `isExceeded(_ length:)` and the comment below claimed
    // "no symbol in binary (devirtualized)". That is refuted — the export trie names the address
    // `KSPlayer.CacheEntry.isOut(size: Swift.UInt32) -> Swift.Bool`, one symbol, not a fold. So
    // both the method name AND the argument label were invented; the label is `size:`, not `_`.
    // Written `size length:` so the external label matches the binary while the body keeps its
    // own name — `size` alone would shadow the stored property this method reads.
    // ⚑[tool=export_trie_oracle ref=CacheEntry.isOut:0x1019e29e4 result=name-recovered]
    // The BODY was already right and is unchanged. Behaviour is faithful to the decompile:
    //   reads size(+0x20) and maxSize(+0x28/+0x2c); returns Bool.
    //   if size >= 0x1000001 (> 16MB)                       -> true
    //   else if maxSize != nil && maxSize < size + length   -> true   (size+length
    //        is a checked UInt32 add: the binary traps on CARRY4 overflow)
    //   else                                                -> false
    func isOut(size length: UInt32) -> Bool {
        if size > 0x100_0000 {
            return true
        }
        if let maxSize, maxSize < size + length {
            return true
        }
        return false
    }

    // CacheEntryProtocol req0. COMPUTED, not stored: `position` appears nowhere in this class's
    // 5 field records. The witness @0x1019e30a4 is four instructions —
    //   ldr x0,[x8,#0x10]  ·  tbnz x0,#0x3f,+8  ·  ret  ·  brk #0x1
    // — i.e. load logicalPos (the first stored field, at the +0x10 header boundary) and trap if
    // it is negative. That is exactly `UInt64(logicalPos)`: the trapping, non-clamping
    // conversion. `UInt64(bitPattern:)` or `UInt64(clamping:)` would emit no test at all.
    // The class's own declared getter @0x1019e3094 is the same four instructions off x20.
    public final var position: UInt64 {
        UInt64(logicalPos)
    }

    // CacheEntryProtocol req1 is satisfied by the stored `size` above: the witness
    // @0x1019e30b8 takes a read access on self+0x20 and returns `ldr w0,[x19,#0x20]` — a plain
    // 32-bit stored-property read, no computation. +0x20 is where `size` sits given
    // logicalPos@+0x10 (8B) and physicalPos@+0x18 (8B).

    // Slots 11 (encode(to:)) + 12 (init(from:)) are SYNTHESIZED by `: Codable`.
    // Do NOT hand-write them — the binary uses standard Swift Codable synthesis.
    // `Codable` IS exactly `Decodable & Encodable`, so the binary listing those two separately
    // is a spelling equivalence, not a missing conformance.
}

// TimeIndexEntry — a value type recovered from __swift5_fieldmd (struct; not in the
// class classmap → no vtable). Referenced by PreLoadIOContext._timeIndex and
// LimitSeparatePreLoadIOContext._timeIndex (both `[TimeIndexEntry]`).
// s98 — MOVED from the PreLoadIOContext target to KSPlayer. The binary says
// `KSPlayer.TimeIndexEntry`: the trie carries
// `$s8KSPlayer14TimeIndexEntryV8positions6UInt64Vvg` and
// `nominal type descriptor for KSPlayer.TimeIndexEntry`, while the
// `$s16PreLoadIOContext14TimeIndexEntryMn` spelling is a real trie negative. It has to live
// here because `KSPlayer.PreLoadProtocol` names it in a requirement type, and
// PreLoadIOContext depends on KSPlayer rather than the other way round.
// s98 — the `position` type pin is DISCHARGED. It was flagged "field-record unmapped; UInt64
// by width + position-field pattern", i.e. a guess from the load width. The trie settles it
// outright: `position.getter : Swift.UInt64` and
// `init(position: Swift.UInt64, time: Swift.Double)`.
// Both properties are `let`, not `var`. The image exports a getter for each and NO setter and
// NO modify for either — the same negative that distinguishes them from, say,
// `KSOptions.display`, which carries getter, setter AND modify. Nothing mutates a member in
// place either: the one write site (LimitSeparatePreLoadIOContext.addTimeIndex) replaces the
// whole element with a freshly constructed value.
public struct TimeIndexEntry {
    public let position: UInt64
    public let time: Double

    // Spelled out rather than left to memberwise synthesis: a synthesized memberwise init is
    // `internal`, and this type is now consumed from the PreLoadIOContext module. The binary
    // agrees it is public — the trie exports
    // `init(position: Swift.UInt64, time: Swift.Double) -> KSPlayer.TimeIndexEntry`, and an
    // internal init of an internal-init'd struct would export nothing. The body is a bare
    // `ret` (both fields arrive in registers), i.e. plain memberwise assignment.
    public init(position: UInt64, time: Double) {
        self.position = position
        self.time = time
    }
}

// CachedTimeRange — absent from Sources/ entirely before s98, and required by
// `PreLoadProtocol.cachedTimeRanges(duration:) -> [CachedTimeRange]`. Also
// KSPlayer-module: `nominal type descriptor for KSPlayer.CachedTimeRange`, and both
// KSAVPlayer and KSMEPlayer expose `cachedTimeRanges.getter : [KSPlayer.CachedTimeRange]`.
//
// Members and order are read, not chosen: `init(start: Swift.Double, end: Swift.Double)`
// fixes the declaration order, and the two accessors confirm which register each field
// occupies — `start.getter` is a bare `ret` (the first field is already in d0) while
// `end.getter` @0x1000eef70 is `mov.16b v0, v1` / `ret`, moving the SECOND register into the
// return. Both are `let` by the same no-setter negative as above.
public struct CachedTimeRange {
    public let start: Double
    public let end: Double

    // Public for the same reason and on the same evidence as TimeIndexEntry's: the trie
    // exports `init(start: Swift.Double, end: Swift.Double) -> KSPlayer.CachedTimeRange`.
    // Its body is likewise a bare `ret`.
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    // COMPUTED, and the whole body is two instructions at 0x1019e30f4:
    //   fsub d0, d1, d0   ·   ret
    // With start in d0 and end in d1 that is exactly `end - start`. It carries its own
    // property descriptor and getter but no setter, so it is get-only.
    public var duration: Double {
        end - start
    }
}

// Forward-only protocol pair, both module KSPlayer, both recovered in s98.
// PreLoadProtocol             `$s8KSPlayer15PreLoadProtocolMp`                    @0x1039ede48
// PreLoadPlaybackPositionSync `$s8KSPlayer35PreLoadPlaybackPositionSyncProtocolMp` @0x1039edea8
// Note the length token on the second one is 35, not 37. A hand-built probe with the wrong
// count returns a plausible-looking "NOT IN TRIE", which is indistinguishable from a real
// negative — count the identifier rather than estimating it.
// NEITHER IS CLASS-CONSTRAINED. protocol_signature reports NumRequirementsInSignature 0 for
// both, so neither carries a Layout requirement on Self and neither may be written
// `: AnyObject`. (Contrast DisplayEnum, which reports 1 and IS class-constrained.) Neither
// has an associated type, so no requirement type is an abstract placeholder.
// Conformers, all witness tables validated by decode_witness_table:
//   PreLoadProtocol             <- LimitSeparatePreLoadIOContext  wt 0x1041e21b0
//                               <- PreLoadIOContext               wt 0x1041e2250
//   PreLoadPlaybackPositionSync <- PreLoadIOContext               wt 0x1041e22a0
// HOW THE NAMES AND TYPES WERE ESTABLISHED. Every one of the ten witness addresses in those
// three tables is NOT_IN_TRIE, so none of these names came from a witness. They were read
// off the CONFORMERS' own exported method symbols, found by dumping the whole orphan export
// trie (57138 mangled names) and searching the DEMANGLED text — e.g.
// `PreLoadIOContext.PreLoadIOContext.cachedTimeRanges(duration: Swift.Double) ->
// [KSPlayer.CachedTimeRange]`. The requirement ORDER below is the witness-table order, and
// the KINDS independently corroborate it: protocol_signature reports
// Getter,Getter,Getter,Getter,Method,Getter,Method,Method,Method, which is exactly the
// shape of the nine declarations as written.
// THE CONFORMANCES ARE NOT DECLARED YET, and that is deliberate rather than an oversight.
// Swift will not accept a conformance whose witnesses do not exist, and several of these
// members are absent from both conformers under any spelling — `more()` alone is 1183
// instructions on PreLoadIOContext and 433 on LimitSeparatePreLoadIOContext. Declaring the
// members with invented bodies to satisfy the compiler would be exactly the fabrication the
// reconstruction rules forbid, so the protocols land first and each conformance follows its
// members. Until then superclass_conformance_gate continues to FLAG both conformer files,
// which is the honest state.
public protocol PreLoadProtocol {
    // 0
    var loadedSize: Int64 { get }
    // 1 — shared witness ADDRESS, but see the correction below: an ICF fold, not a default.
    var position: UInt64 { get }
    // 2 — shared witness address; same correction.
    var downloadSpeed: Double { get }
    // 3 — shared witness address; same correction.
    var bytesRead: UInt64 { get }
    // 4
    func more() -> Int32
    // 5
    var timeIndex: [TimeIndexEntry] { get }
    // 6
    func addTimeIndex(position: UInt64, time: Double)
    // 7
    func cachedTimeRanges(duration: Double) -> [CachedTimeRange]
    // 8 — note the sibling protocol below declares a DIFFERENT overload of this name.
    func syncPlaybackPosition(time: Double, duration: Double)
}

// CORRECTION, and it is worth stating plainly because the first reading of this was wrong.
//
// Requirements 1, 2 and 3 resolve to the SAME witness address in BOTH conformance tables —
// req1 0x101ba66bc, req2 0x101b95bf8 (thunk -> 0x101b914d0), req3 0x101a65dd4 (thunk ->
// 0x101a63dec). That was first read as proof of protocol-extension defaults, on the reasoning
// that two unrelated conformers cannot share a witness body. THAT REASONING IS INVALID, and
// the bodies themselves refute it: req2's shared body is
//     ldr x8, [x20]  ·  ldr d0, [x8, #0x68]  ·  ret
// — a CONCRETE read of inherited offset 0x68, which is CacheIOContext._downloadSpeed, whose
// own exported getter @0x100d362bc is the same `ldr d0, [x20, #0x68]`. req3's body likewise
// reads offset 0x18 = CacheIOContext.bytesRead, and req1's reads 0x50 and 0x80 = urlPos and
// logicalPos. A generic protocol-extension body cannot hardcode an inherited stored-property
// offset.
//
// The two conformers are SIBLINGS under CacheIOContext, not one under the other, so they
// inherit an identical layout and their witnesses come out bit-identical — and the linker
// folds them. The shared address is an ICF fold, exactly the case AGENT_PROTOCOL warns about:
// a shared address is not an anchor mismatch, the code is genuinely each function's, it is
// merely also somebody else's.
//
// Protocol-extension defaults for two of these DO exist — the trie carries
// `(extension in KSPlayer):KSPlayer.PreLoadProtocol.downloadSpeed.getter` @0x10002dc44 and
// `...bytesRead.getter` @0x1001a1394 — but at addresses appearing in NEITHER witness table, so
// neither conformer uses them. No `position` or `loadedSize` extension default exists at all
// (both real trie negatives).
//
// The consequence for the conformances: these three are satisfied by members INHERITED from
// CacheIOContext, not by anything the protocol supplies. Source's CacheIOContext already has
// `bytesRead`; it does not yet have `downloadSpeed` (only the private stored `_downloadSpeed`
// at the same 0x68) or `position`.
// ⚑[tool=decode_witness_table ref=KSPlayer.PreLoadProtocol:0x1039ede48 result=reqs-1-2-3-ICF-folded]

// Sole requirement, and it is NOT a duplicate of PreLoadProtocol's req8 — it is a different
// overload of the same base name, distinguished by its second label and type. Both exist as
// separate symbols on the same class:
//   PreLoadIOContext.PreLoadIOContext.syncPlaybackPosition(time: Double, duration: Double)
//   PreLoadIOContext.PreLoadIOContext.syncPlaybackPosition(time: Double, position: UInt64?)
// Sole conformer PreLoadIOContext, wt 0x1041e22a0, whose single witness is 0x1002e67c0.
public protocol PreLoadPlaybackPositionSyncProtocol {
    func syncPlaybackPosition(time: Double, position: UInt64?)
}

public enum LogLevel: Int32, CustomStringConvertible {
    case panic = 0
    case fatal = 8
    case error = 16
    case warning = 24
    case info = 32
    case verbose = 40
    case debug = 48
    case trace = 56

    public var description: String {
        switch self {
        case .panic:
            return "panic"
        case .fatal:
            return "fault"
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info:
            return "info"
        case .verbose:
            return "verbose"
        case .debug:
            return "debug"
        case .trace:
            return "trace"
        }
    }
}

public extension LogLevel {
    var logType: OSLogType {
        switch self {
        case .panic, .fatal:
            return .fault
        case .error:
            return .error
        case .warning:
            return .debug
        case .info, .verbose, .debug:
            return .info
        case .trace:
            return .default
        }
    }
}

public protocol LogHandler {
    @inlinable
    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt)
}

public class OSLog: LogHandler {
    public let label: String
    // Forward's OSLog carries a DateFormatter, exactly like FileLog. Binary reflection lists TWO
    // stored fields for OSLog — `label: Swift.String` then `formatter: NSDateFormatter`, BOTH with
    // field-record flags 0x0 = `let` (scripts/dump_binary_field_types.py OSLog +
    // scripts/dump_field_bindings.py OSLog) — and the vtable has ZERO accessor slots
    // (vtable_walk.py OSLog: slot 0 Init, slot 1 Method), which is the `let`-only shape.
    // init @0x1019e19ec: swift_allocObject(size 0x28 = 16 header + 16 String @self+0x10/+0x18 (the
    // `lable` argument) + 8 @self+0x20), [[NSDateFormatter alloc] init] stored to self+0x20, then
    // -[NSDateFormatter setDateFormat:] with the SAME 18-char literal FileLog uses (see below).
    // Shape is ALLOCATING_INIT_INLINED, not a forwarding thunk: it stores fields directly after the
    // swift_allocObject call site (`str x21,[x20,#0x10]` / `stp x19,x0,[x20,#0x18]`). The call
    // COUNT is not the discriminator — this init makes seven calls after that alloc site (eight
    // `bl` in total) and still inlines; a session-61 golden mislabelled it a thunk on call count.
    // `mov w1,#0x28; mov w2,#0x7` pins instance size 40 / align mask 7, which is exactly the two
    // fields above and leaves room for no third. ARITY: only x0/x1 are read (the one String);
    // x2/x3 are never read, which refutes a second parameter AND a defaulted one, since a
    // default-argument generator would still have to materialise its value at the call site.
    // The class ref for the formatter is __objc_classrefs 0x1044105B0 = NSDateFormatter, so the
    // declaration-site default really is `DateFormatter()`.
    // ⚑[tool=nm ref=OSLog.init(lable:):0x1019e19ec result=UNRESOLVED] the argument LABEL `lable`
    // (the upstream typo) is carried from the base source and is NOT recoverable here: this binary
    // is stripped to 7609 symbols with no `5OSLogC`/`7FileLogC` entry, and Swift argument labels
    // appear in no reflection section. Only the label's TYPE and count are proven above.
    public let formatter = DateFormatter()
    public init(lable: String) {
        label = lable
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
    }

    // log @0x1019e3460 (vtable slot 1). The os_log format is a StaticString passed as x3 =
    // 0x103d34f80 with `mov w4,#0x17` = 23 UTF-8 bytes; read raw those 23 bytes are
    // "%@ %@ %@: %@:%d %@ | %@" (NUL at +23) — SEVEN specifiers, not the six of the base. The
    // argument array confirms seven independently: it is a 0x138-byte allocation = 0x20 array
    // header + 7 * 0x28 CVarArg existentials (payload +0x00, metadata +0x18, witness +0x20), and
    // every element's metadata word names its type — Swift.String (__got 0x104111500 =
    // _$sSSN) for six, Swift.UInt (0x104111B08 = _$sSuN, witness 0x104111B30 =
    // _$sSus7CVarArgsWP) for `line`, which is what pins `line` as UInt rather than Int. Element
    // order, by store offset into that array:
    //   +0x20   formatter.string(from: Date()) — self+0x20 is loaded, then Date.init ->
    //           Date._bridgeToObjectiveC -> -[NSDateFormatter stringFromDate:] ->
    //           String._unconditionallyBridgeFromObjectiveC. This leading timestamp is the seventh
    //           argument the base is missing, and it is why OSLog carries a formatter at all.
    //   +0x48   level.description   +0x70  label (self+0x10)   +0x98  file (params x2/x3)
    //   +0xC0   line (param x6)     +0xE8  function (params x4/x5)
    //   +0x110  message.description (via the CustomStringConvertible witness getter @0x103459364)
    // `dso:` and `log:` are DEFAULTED at this call site, so neither is spelled here: x1 =
    // 0x100000000 is #dsohandle and x2 comes from OSLog.default's getter @0x1034587c4 — a
    // default-argument generator runs at the CALL site, which is exactly what these are.
    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        os_log(level.logType, "%@ %@ %@: %@:%d %@ | %@", formatter.string(from: Date()), level.description, label, file, line, function, message.description)
    }
}

public class FileLog: LogHandler {
    public let fileHandle: FileHandle
    public let formatter = DateFormatter()
    public init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        // 18 chars, NOT the base's 21-char "…SSSSSS". init @0x1019e380c emits the literal as
        // `mov x0,#0x12; movk x0,#0xd000,LSL#48` → _StringObject count = 0x12 = 18, and
        // `adrp x8,0x103d34000; add x8,x8,#0x9c0; sub x22,x8,#0x20` → the object word is the literal
        // address MINUS _StringObject.nativeBias (32), so the literal itself is at 0x103d349c0 =
        // "MM-dd HH:mm:ss.SSS" (NUL at +18). The bias DIRECTION is proven by a control in this same
        // file's FileLog.log @0x1019e38d0: identical `add #0xfa0; sub #0x20` shape with count
        // 0x14 = 20, where the add result 0x103d34fa0 holds "%@ %@ %@:%d %@ | %@\n" (exactly 20
        // chars) while the sub result 0x103d34f80 holds a 23-char string — so the ADD result is the
        // literal. Both lengths therefore agree only for the add-side reading. (That 23-char
        // neighbour is now identified: it is OSLog.log's own format string. The wrong-bias read of
        // THIS literal would land on "ReadCacheIOContext", which is also 18 characters — length
        // alone would not have caught it, so the count field is checked against the add side.)
        // Shape is ALLOCATING_INIT_INLINED: stores land after the swift_allocObject call site as
        // `stp x19,x0,[x20,#0x10]` — fileHandle at self+0x10, formatter at self+0x18.
        // `mov w1,#0x20; mov w2,#0x7` pins instance size 32 / align mask 7 = exactly two pointers.
        // ARITY: only x0 is read; x1/x2/x3 are never read, refuting both a second parameter and a
        // defaulted one. Formatter class ref is __objc_classrefs 0x1044105B0 = NSDateFormatter.
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        let string = String(format: "%@ %@ %@:%d %@ | %@\n", formatter.string(from: Date()), level.description, file, line, function, message.description)
        if let data = string.data(using: .utf8) {
            // Forward calls the THROWING generic overload and DROPS the error, not the
            // non-throwing ObjC `write(_:)`. Read at FileLog.log @0x1019e38d0: `mov x21,#0x0`
            // @0x1019e3c00 zeroes the swifterror register, `bl 0x103458080` @0x1019e3c04 is
            // `_$sSo12NSFileHandleC10FoundationE5write10contentsOfyx_tKAC12DataProtocolRzlF`
            // = `FileHandle.write<T: DataProtocol>(contentsOf: T) throws`, then `cbz x21`
            // @0x1019e3c08 skips `bl _swift_errorRelease` @0x1019e3c10 — the error is
            // released and discarded, never rethrown. That is exactly `try?`.
            try? fileHandle.write(contentsOf: data)
        }
    }
}

public struct KSClock {
    public private(set) var lastMediaTime = CACurrentMediaTime()
    public internal(set) var position = Int64(0)
    // ⚑ s105: field record [2] of 4 on descriptor 0x1039edfd0, mangle `Sd` = Swift.Double, and it
    // sits BETWEEN `position` and `time` — so it is declared here, not appended, because a stored
    // property's order is its layout. Default read from its own variable-initialization
    // expression @0x1000b783c, which is `fmov d0, #1.00000000 / ret`.
    // ⚑[tool=vpfi_initializer_oracle ref=KSClock.rate:0x1000b783c result=1.0]
    // Access ⚑ INFERRED from the two fields it sits between; the trie exports getter, setter and
    // modify for it, which is what establishes `var` rather than `let`.
    public internal(set) var rate = 1.0
    public internal(set) var time = CMTime.zero {
        didSet {
            lastMediaTime = CACurrentMediaTime()
        }
    }

    // @0x101a58100..0x101a58124 (inlined copy): `time.seconds` is evaluated first, then
    // `rate * (CACurrentMediaTime() - lastMediaTime)` is added — the rate factor was missing.
    // Operand order is left as is: the two inlined copies disagree. MEPlayerItem @0x101a58120 is
    // `fmul d0, d11(rate), d0(now - last)` = `rate * (…)`, but KSOptions' copy @0x1019bf164 is
    // `fmul d0, d0(now - last), d1(rate)` = `(…) * rate`, and it also loads lastMediaTime/rate after
    // CACurrentMediaTime rather than before. fmul is commutative, so the binary cannot pick one.
    func getTime() -> TimeInterval {
        time.seconds + rate * (CACurrentMediaTime() - lastMediaTime)
    }
}

// KSDrawable @0x1039ed9f8 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (MediaPlayerProtocol.swift..AudioPlayerView.swift).
// ⚑[tool=type_surface ref=KSDrawable:0x1039ed9f8 result=protocol KSDrawable]
// Exported (`$s8KSPlayer10KSDrawableMp` / `TL` in the export trie) → public.
// Requirements read off the sole Forward conformance, RealityKit.TextureResource.Drawable : KSDrawable
// (__swift5_proto record 0x10356c4e8, witness table 0x1041d9e58; trie `...DrawableC8KSPlayer10KSDrawableAFWP`):
//   +0x8  getter 0x101a84ac0 — `ldr x20,[x20]` then calls the RealityKit dispatch thunk
//         `TextureResource.Drawable.texture.getter : any MTLTexture` (stub 0x103452c38): a native witness.
//   +0x10 method 0x101a84ae0 — x0 = the command buffer; `MTLCommandBuffer.present(_: TextureResource.Drawable)`
//         (stub 0x1034581c4) then `commit`; same body as the exported extension method
//         `(extension in KSPlayer):TextureResource.Drawable.present(commandBuffer:)` (0x101a84a8c).
// No conformer in this source tree (the TextureResource.Drawable conformance is a MetalRender.swift gap).
// ⚑[tool=witness_walk ref=KSDrawable:0x1041d9e58 result=2 requirements, names from witnesses]
public protocol KSDrawable {
    var texture: any MTLTexture { get } // INFERRED 0x101a84ac0
    func present(commandBuffer: any MTLCommandBuffer) // INFERRED 0x101a84ae0
}

// PlayFileProtocol @0x1039edd00 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_unique(inferred) (MediaPlayerProtocol.swift..AudioPlayerView.swift).
// ⚑[tool=type_surface ref=PlayFileProtocol:0x1039edd00 result=protocol PlayFileProtocol]
// Exported (`$s8KSPlayer16PlayFileProtocolMp` / `TL` in the export trie) → public. 4 instance
// getter requirements; only two are typed by Forward uses (MEPlayerItem.reading 0x101a51634):
// +0x8 Double (seconds offset) and +0x20 Int (byte position). +0x10/+0x18 have no Forward use,
// so the requirements are deferred rather than invented. Element type of MovieStream.files.
public protocol PlayFileProtocol {}
