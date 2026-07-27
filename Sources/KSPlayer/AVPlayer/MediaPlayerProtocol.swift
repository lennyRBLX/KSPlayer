//
//  MediaPlayerProtocol.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public protocol MediaPlayback: AnyObject {
    var duration: TimeInterval { get }
    var fileSize: Int64 { get }
    var naturalSize: CGSize { get }
    var chapters: [Chapter] { get }
    var currentPlaybackTime: TimeInterval { get }
    func prepareToPlay()
    func shutdown()
    func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void))
}

// 14 stored fields; the source order below IS the binary reflection order (scripts/dump_field_bindings.py
// DynamicInfo — 6 `let`, then 8 `var`). The slot-34 allocating init @0x1019df094 is the single witness for
// every default value quoted below (disassemble_function, verbatim), and its `stp`/`str` widths are also the
// layout proof. Vtable (scripts/vtable_walk.py DynamicInfo, 37 entries) is the placement evidence: an
// immutable `let` is not overridable and takes no entry, so the entries are 3 var-triples (slots 0-8) ·
// 4 BARE getters (slots 9-12) · 7 var-triples (slots 13-33) · 2 Init (34, 35) · 1 Method (36). Exactly 4
// bare getters ⇒ the 4 read-only computed properties, and the only assignment of the 10 triples that closes
// the count WITHOUT inventing a member is 8 stored vars + the 2 @Published wrapper accessors. That is what
// puts lastBytesRead/videoDisplayCount/lastMediaTime AHEAD of the computed group.
public class DynamicInfo: ObservableObject {
    private let metadataBlock: () -> [String: String]
    private let bytesReadBlock: () -> Int64
    private let audioBitrateBlock: () -> Int
    private let videoBitrateBlock: () -> Int
    // Fields 5-6 — both `let`, both nil: slot 34 zeroes 32 bytes at self+0x50 in one shot
    // (`movi v0.2D,#0x0` ; `stp q0,q0,[x27, #0x50]` @0x1019df170-174), i.e. two 16-byte nil closures.
    // Types are the demangled raw field-record mangles (scripts/dump_field_type_mangles.py → swift-demangle):
    //   `SaySo26AVPlayerItemAccessLogEventCGycSg` → (() -> [AVPlayerItemAccessLogEvent])?
    //   `SfyYbScMYccSg`                           → (@MainActor @Sendable () -> Float)?
    // ⚑ access level NOT binary-recoverable (a `let` emits no vtable slot) — mirrors the sibling blocks.
    // ⚑ OPEN: the second initializer (vtable slot 35 @0x1019de4a8, not this unit) may take these two as
    //   parameters, in which case the `= nil` defaults here move into that init's parameter defaults.
    private let accessLogEvent: (() -> [AVPlayerItemAccessLogEvent])? = nil
    private let displayFPSBlock: (@MainActor @Sendable () -> Float)? = nil
    // Fields 7-9 — the first three stores slot 34 makes after swift_allocObject:
    //   `str xzr,[x0, #0x70]`               → lastBytesRead = 0        (8 bytes)
    //   `strb wzr,[x0, #0x78]`              → videoDisplayCount = 0    (1 byte ⇒ UInt8, field record)
    //   `bl 0x103459d54 ; str d0,[x27,#0x80]` → lastMediaTime = CACurrentMediaTime()  (Double, field record)
    // ⚑ lastBytesRead's type is a symref (0x10536e600) that lands outside the mapped image, so it is not
    //   name-resolvable here. It is the SAME mangle as bytesReadBlock's return type (this class) and as
    //   VideoToolboxDecode.startTime/maxTimestamp/lastTimestamp — every one of which is already declared
    //   Int64 — and VideoToolboxDecode slot 32 writes -1 into one of them with a 64-bit `mov x8,#-0x1`
    //   (an integer, not a Double bit pattern). Int64 is therefore consistent-by-construction, not a guess.
    // ⚑ access level NOT binary-recoverable (`private` does not trim vtable slots) — `private` chosen to
    //   match the other bookkeeping state; no in-source reader exists yet (the updater is slot 36).
    private var lastBytesRead: Int64 = 0
    private var videoDisplayCount: UInt8 = 0
    private var lastMediaTime: Double = CACurrentMediaTime()
    public var metadata: [String: String] {
        metadataBlock()
    }

    public var bytesRead: Int64 {
        bytesReadBlock()
    }

    public var audioBitrate: Int {
        audioBitrateBlock()
    }

    public var videoBitrate: Int {
        videoBitrateBlock()
    }

    // Fields 10-11 — slot 34 builds BOTH with the same `Published.init` (0x1034532bc) and the same
    // `PTR___type_metadata_for_Swift_Float` (0x104111870), each from a 4-byte `str wzr` initial value:
    //   @0x1019df104-11c  _displayFPS   = Published(initialValue: Float(0))
    //   @0x1019df128-138  _networkSpeed = Published(initialValue: Float(0))
    // ⚑ PRE-EXISTING DIVERGENCE, deliberately NOT fixed in this unit: `displayFPS` is Double here but
    //   Published<Float> in the binary, and `audioVideoSyncDiff` is Double here but Float in the field
    //   record (slot 34 zeroes it with a 4-byte `str wzr`, not `str xzr`). Correcting either one changes a
    //   type that MEPlayerItem.swift:475 (`(dynamicInfo.audioVideoSyncDiff, type) = options.videoClockSync(…)`,
    //   a Double-returning tuple) and KSVideoPlayerView.swift:690-691 consume, so it is a multi-file unit.
    @Published
    public var displayFPS = 0.0
    // ⚑ access level NOT binary-recoverable; `public` mirrors its Published sibling displayFPS.
    @Published
    public var networkSpeed: Float = 0
    public var audioVideoSyncDiff = 0.0
    public var droppedVideoFrameCount = UInt32(0)
    public var droppedVideoPacketCount = UInt32(0)
    /// Binary: vtable slot 34 @0x1019df094 (66 instructions) — the allocating entry point with the
    /// designated init inlined (`swift_allocObject` 0x10345caf0, then every stored-property default above,
    /// then the four closure stores). ⚑ parameter labels are NOT recoverable (stripped;
    /// `recover_swift_function_name.py --addr 0x1019df094` finds no `#function` literal) — they are the
    /// pre-existing source labels, kept. The four closures arrive in x0-x7 and land as
    /// `stp x26,x25,[x27,#0x10]` / `[#0x20]` / `[#0x30]` / `[#0x40]`, which is the argument-to-field
    /// mapping below. ⚑ OPEN: slot 35 @0x1019de4a8 is a SECOND initializer, not reconstructed here.
    init(metadata: @escaping () -> [String: String], bytesRead: @escaping () -> Int64, audioBitrate: @escaping () -> Int, videoBitrate: @escaping () -> Int) {
        metadataBlock = metadata
        bytesReadBlock = bytesRead
        audioBitrateBlock = audioBitrate
        videoBitrateBlock = videoBitrate
    }
}

public struct Chapter {
    public let start: TimeInterval
    public let end: TimeInterval
    public let title: String
}

public protocol MediaPlayerProtocol: MediaPlayback {
    var delegate: MediaPlayerDelegate? { get set }
    var view: UIView? { get }
    var playableTime: TimeInterval { get }
    var isReadyToPlay: Bool { get }
    var playbackState: MediaPlaybackState { get }
    var loadState: MediaLoadState { get }
    var isPlaying: Bool { get }
    var seekable: Bool { get }
    //    var numberOfBytesTransferred: Int64 { get }
    var isMuted: Bool { get set }
    var allowsExternalPlayback: Bool { get set }
    var usesExternalPlaybackWhileExternalScreenIsActive: Bool { get set }
    var isExternalPlaybackActive: Bool { get }
    var playbackRate: Float { get set }
    var playbackVolume: Float { get set }
    var contentMode: UIViewContentMode { get set }
    var subtitleDataSource: (any SubtitleDataSource)? { get }
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    var playbackCoordinator: AVPlaybackCoordinator { get }
    @available(tvOS 14.0, *)
    var pipController: KSPictureInPictureController? { get }
    var dynamicInfo: DynamicInfo? { get }
    init(url: URL, options: KSOptions)
    func replace(url: URL, options: KSOptions)
    func play()
    func pause()
    func enterBackground()
    func enterForeground()
    @MainActor func thumbnailImageAtCurrentTime() async -> CGImage?
    func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack]
    func select(track: some MediaPlayerTrack)
}

public extension MediaPlayerProtocol {
    var nominalFrameRate: Float {
        tracks(mediaType: .video).first { $0.isEnabled }?.nominalFrameRate ?? 0
    }
}

@MainActor
public protocol MediaPlayerDelegate: AnyObject {
    func readyToPlay(player: some MediaPlayerProtocol)
    func changeLoadState(player: some MediaPlayerProtocol)
    // 缓冲加载进度，0-100
    func changeBuffering(player: some MediaPlayerProtocol, progress: Int)
    func playBack(player: some MediaPlayerProtocol, loopCount: Int)
    func finish(player: some MediaPlayerProtocol, error: Error?)
}

public protocol MediaPlayerTrack: AnyObject, CustomStringConvertible {
    var trackID: Int32 { get }
    var name: String { get }
    var languageCode: String? { get }
    var mediaType: AVFoundation.AVMediaType { get }
    var nominalFrameRate: Float { get set }
    var bitRate: Int64 { get }
    var bitDepth: Int32 { get }
    var isEnabled: Bool { get set }
    var isImageSubtitle: Bool { get }
    var rotation: Int16 { get }
    var dovi: DOVIDecoderConfigurationRecord? { get }
    var fieldOrder: FFmpegFieldOrder { get }
    var formatDescription: CMFormatDescription? { get }
}

// public extension MediaPlayerTrack: Identifiable {
//    var id: Int32 { trackID }
// }

public enum MediaPlaybackState: Int {
    case idle
    case playing
    case paused
    case seeking
    case finished
    case stopped
}

public enum MediaLoadState: Int {
    case idle
    case loading
    case playable
}

// swiftlint:disable identifier_name
public struct DOVIDecoderConfigurationRecord {
    public let dv_version_major: UInt8
    public let dv_version_minor: UInt8
    public let dv_profile: UInt8
    public let dv_level: UInt8
    public let rpu_present_flag: UInt8
    public let el_present_flag: UInt8
    public let bl_present_flag: UInt8
    public let dv_bl_signal_compatibility_id: UInt8
}

public enum FFmpegFieldOrder: UInt8 {
    case unknown = 0
    case progressive
    case tt // < Top coded_first, top displayed first
    case bb // < Bottom coded first, bottom displayed first
    case tb // < Top coded first, bottom displayed first
    case bt // < Bottom coded first, top displayed first
}

extension FFmpegFieldOrder: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown, .progressive:
            return "progressive"
        case .tt:
            return "top first"
        case .bb:
            return "bottom first"
        case .tb:
            return "top coded first (swapped)"
        case .bt:
            return "bottom coded first (swapped)"
        }
    }
}

// swiftlint:enable identifier_name
public extension MediaPlayerTrack {
    var language: String? {
        languageCode.flatMap {
            Locale.current.localizedString(forLanguageCode: $0)
        }
    }

    var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    var dynamicRange: DynamicRange? {
        if dovi != nil {
            return .dolbyVision
        } else {
            return formatDescription?.dynamicRange
        }
    }

    var colorSpace: CGColorSpace? {
        KSOptions.colorSpace(ycbcrMatrix: yCbCrMatrix as CFString?, transferFunction: transferFunction as CFString?)
    }

    var mediaSubType: CMFormatDescription.MediaSubType {
        formatDescription?.mediaSubType ?? .boxed
    }

    var audioStreamBasicDescription: AudioStreamBasicDescription? {
        formatDescription?.audioStreamBasicDescription
    }

    var naturalSize: CGSize {
        formatDescription?.naturalSize ?? .zero
    }

    var colorPrimaries: String? {
        formatDescription?.colorPrimaries
    }

    var transferFunction: String? {
        formatDescription?.transferFunction
    }

    var yCbCrMatrix: String? {
        formatDescription?.yCbCrMatrix
    }
}

public extension CMFormatDescription {
    var dynamicRange: DynamicRange {
        let contentRange: DynamicRange
        if codecType.string == "dvhe" || codecType == kCMVideoCodecType_DolbyVisionHEVC {
            contentRange = .dolbyVision
        } else if bitDepth == 10 || transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { /// HDR
            contentRange = .hdr10
        } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { /// HLG
            contentRange = .hlg
        } else {
            contentRange = .sdr
        }
        return contentRange
    }

    var bitDepth: Int32 {
        codecType.bitDepth
    }

    var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    var colorPrimaries: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferColorPrimariesKey] as? String
        } else {
            return nil
        }
    }

    var transferFunction: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferTransferFunctionKey] as? String
        } else {
            return nil
        }
    }

    var yCbCrMatrix: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferYCbCrMatrixKey] as? String
        } else {
            return nil
        }
    }

    var naturalSize: CGSize {
        let aspectRatio = aspectRatio
        return CGSize(width: Int(dimensions.width), height: Int(CGFloat(dimensions.height) * aspectRatio.height / aspectRatio.width))
    }

    var aspectRatio: CGSize {
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

    var depth: Int32 {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_Depth] as? Int32 ?? 24
        } else {
            return 24
        }
    }

    var fullRangeVideo: Bool {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_FullRangeVideo] as? Bool ?? false
        } else {
            return false
        }
    }
}

func setHttpProxy() {
    guard KSOptions.useSystemHTTPProxy else {
        return
    }
    guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? NSDictionary else {
        unsetenv("http_proxy")
        return
    }
    guard let proxyHost = proxySettings[kCFNetworkProxiesHTTPProxy] as? String, let proxyPort = proxySettings[kCFNetworkProxiesHTTPPort] as? Int else {
        unsetenv("http_proxy")
        return
    }
    let httpProxy = "http://\(proxyHost):\(proxyPort)"
    setenv("http_proxy", httpProxy, 0)
}
