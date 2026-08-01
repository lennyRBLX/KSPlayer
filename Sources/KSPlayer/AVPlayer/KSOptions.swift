//
//  KSOptions.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
#if os(tvOS) || os(xrOS)
import DisplayCriteria
#endif
import Metal
import OSLog

#if canImport(UIKit)
import UIKit
#endif
open class KSOptions {
    // Instance stored properties in Forward 1.3.17 __swift5_fieldmd (binary reflection) ORDER —
    // reordered from the base cce7002 layout so the pre-commit l2_field_gate field-ORDER check passes
    // (the order was the SOLE block; the hook blocks on type-mismatch/order-diff only). Deterministic:
    // order taken verbatim from l2_field_gate's binary oracle. The field SET is still base cce7002 —
    // 38 Forward fields not yet added + the base-only fields grouped below not yet removed — both
    // WARN-level (excluded from the order check), tracked as the KSOptions→Forward layout migration.
    // Shared fields keep their reconstructed values/types unchanged.
    // ── Forward 1.3.17 __swift5_fieldmd (binary reflection) ORDER + full field SET (84 fields). The 38
    //    Forward-only fields were ADDED and the 9 base-only extras REMOVED (KSOptions→Forward layout
    //    migration — l2 REAL_FLAG 47→0). Field TYPES/ORDER = the deterministic binary oracle
    //    (dump_binary_field_types.py, desc 0x1039ec4c0). Inline DEFAULTS = KSOptions.init (FUN_1019b2f7c,  ⚑[tool=resolve_fun_pins ref=FUN_1019b2f7c:0x1019b2f7c result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.init() -> KSPlayer.KSOptions
    //    symbolic-offset stores). Removed extras (cache/probesize/maxAnalyzeDuration/nobuffer/codecLowDelay/
    //    autoDeInterlace/autoRotate/videoInterlacingType/idetTypeMap) migrated to their callers.
    public var context = ""
    public var avOptions = [String: Any]()
    public var isLive: Bool?
    public var startPlayTime: TimeInterval = 0
    public var startPlayTimePercentage = 0.0
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true // 默认支持来自系统控制中心的控制
    public var isAutoPlay = KSOptions.isAutoPlay
    public var enterForgeResumePlay = false
    public var isDLNARunning = false
    public var disableVideoFrameRateMatching = false
    /// 是否开启秒开
    public var isSecondOpen = KSOptions.isSecondOpen
    public var playbackTimeInterval = 0.04
    // playerTypes default reads the static KSOptions.playerTypes (not an inline literal).
    // ⚑[tool=decompile_function ref=FUN_1019b4334:0x1019b4334 result=static [KSAVPlayer.self,KSMEPlayer.self] — element class-descriptor names confirmed @0x1039ec148/@0x1039ef750]
    public var playerTypes: [MediaPlayerProtocol.Type] = KSOptions.playerTypes
    public var mixAudio = false
    public var canBackgroundPlay = true
    public var contentMode = UIViewContentMode.scaleAspectFit  // macOS: KSPlayer.ContentMode (== binary); iOS/tvOS: UIView.ContentMode
    /// Applies to short videos only
    public var isLoopPlay = KSOptions.isLoopPlay
    // ── SLOT→MEMBER ALIGNMENT (basis for every `vtable slot N` note in this class) ─────────────
    // `scripts/vtable_walk.py KSOptions` gives 284 slots in DECLARATION order;
    // `scripts/dump_field_bindings.py KSOptions` gives the 84 stored fields in the same order with
    // their var/let binding. The two align 1:1 and EXACTLY: 81 `var` fields × (Getter,Setter,
    // ModifyCoroutine) = 243 slots, the 3 `let` fields (useSystemHTTPProxy/yadifMode/
    // deInterlaceAddIdet) contribute ZERO slots (control: OSLog and FileLog are all-`let` and have
    // vtables of size 2 = init + log, no accessor slots), 1 lone Getter (slot 43) + 1 extra triple
    // (slots 112-117 region) = 2 computed properties, and 37 method/init slots. 243+1+3+37 = 284.
    // Four independent anchors confirm it — Ghidra resolves the field-offset globals by name in the
    // getters: slot 125 → _TtC8KSPlayer9KSOptions::syncDecodeAudio (field 37), slot 134 →
    // ::audioRecognizes (39), slot 217 → ::adjustBuffer (68), slot 226 → ::forceDisableDisplayLayer
    // (69); plus slots 56/61 read self+0x70/+0x71, the two adjacent Bools isLoopPlay/isAccurateSeek.
    //
    // Slots 59-60 are two methods declared HERE, between `isLoopPlay` and `isAccurateSeek`.
    // Slot 59 @0x1019b52fc is the `adaptable`-shaped body (maxBufferDuration * 0.5,
    // CACurrentMediaTime, bitRateStates.last, bitRates index walk).
    // Slot 60 @0x10047da30 is PINNED, not reconstructed: the member has no recoverable identity.
    // The binary is stripped and `scripts/recover_swift_function_name.py --addr 0x10047da30` returns
    // #function None / #file None; the entire body is `mov x0,#0x100000000; ret` (2 instructions),
    // so there is no callee, string, field access or trap to characterise it beyond its ABI — no
    // arguments past self (x20), ONE 8-byte direct result whose bit pattern is 0x0000000100000000.
    // The body is this method's OWN, not a linker-folded stub: its 5 xrefs are the KSOptions type
    // descriptor slot (0x1039ec6e4) + three class-metadata vtables (0x10448c198/0x10448ce48/
    // 0x1044e5818 — KSOptions and two subclasses inheriting it) + one __LINKEDIT entry, exactly the
    // shape slot 59's own body shows one word lower. Writing a name here would be invention.
    // ⚑[tool=vtable_walk+recover_swift_function_name ref=FUN_10047da30:0x10047da30 result=LOCATED pinned=member-identity-undetermined]
    /// 开启精确seek
    public var isAccurateSeek = KSOptions.isAccurateSeek
    /// seek完是否自动播放
    public var isSeekedAutoPlay = KSOptions.isSeekedAutoPlay
    /*
     AVSEEK_FLAG_BACKWARD: 1
     AVSEEK_FLAG_BYTE: 2
     AVSEEK_FLAG_ANY: 4
     AVSEEK_FLAG_FRAME: 8
     */
    public var seekFlags = Int32(1)
    //  record stream
    public var outputURL: URL?
    public var outputMediaType: AVMediaType?
    public internal(set) var formatName = ""
    public var formatContextOptions = [String: Any]()
    public var outputFormatContextOptions = [String: Any]()
    public var ioContext: AbstractAVIOContext?
    public var decoderOptions = [String: Any]()
    public var lowres = UInt8(0)
    public let useSystemHTTPProxy = KSOptions.useSystemHTTPProxy
    public var referer: String? {
        didSet {
            if let referer {
                formatContextOptions["referer"] = "Referer: \(referer)"
            } else {
                formatContextOptions["referer"] = nil
            }
        }
    }

    public var userAgent: String? = "KSPlayer" {
        didSet {
            formatContextOptions["user_agent"] = userAgent
        }
    }

    public var seekUsePacketCache = false
    /// 最低缓存视频时间
    @Published
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration
    /// 最大缓存视频时间
    public var maxBufferDuration = KSOptions.maxBufferDuration
    // audio
    public var audioFilters = [String]()
    public var syncDecodeAudio = false
    // Slots 128-130 are three methods declared HERE, between `syncDecodeAudio` (slots 125-127, the
    // named-anchor getter) and `fontsDir` (131-133, all three impls null in the descriptor).
    // Slot 129 @0x1019b91c8 is an audioFrameMaxCount-shaped body: when a once-initialised static
    // type equals one particular class it clamps the 2nd argument up to 6, computes
    // Int(fps) * that, >>1, capped at 0x1000; otherwise Int(fps) * arg, >>2, capped at 0x400.
    // Slot 130 @0x1019b9330 returns that same static-type equality as a Bool.
    // Slot 128 @0x10002db34 is PINNED: `mov x0,#0x0; mov x1,#0x0; ret` (3 instructions) — a
    // 16-byte all-zero direct result and nothing else. recover_swift_function_name --addr returns
    // #function None. The body is a LINKER-FOLDED (ICF) stub, so it carries no identifying
    // information whatsoever: it is 586-way ICF-folded (export_trie_oracle n_syms=586). dyld_info
    // -fixups shows exactly 12 rebases — the 12 class-metadata vtable slots that hold this address
    // (0x10411eb30, 0x10412b500, 0x104137858, 0x10413c0c0, 0x104147208, 0x10417c970,
    // 0x10417cef8/cf38, 0x10417d098/d300, 0x10448d068, 0x1044e5a38) — whereas the KSOptions
    // descriptor claims only 0x1039ec904. Position is exact; identity is not derivable.
    // (s68: corrected a prior "16 xrefs plus two call sites" tally that did not decompose; the
    //  independently verified count is 12 rebases — resolve_fun_pins verdict FOLDED_AMBIGUOUS.)
    // ⚑[tool=vtable_walk+get_xrefs_to ref=FUN_10002db34:0x10002db34 result=LOCATED pinned=member-identity-undetermined]
    internal var fontsDir: URL? // Tier 3a: read by SubtitleDecode.init (FUN_101a6914c @0x133 _TtC8KSPlayer9KSOptions::fontsDir) -> SubtitleDecode.fontsDir = fontsDir?.path  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    public var audioRecognizes: [AudioRecognize] = []
    // sutile
    public var autoSelectEmbedSubtitle = true
    public var isSeekImageSubtitle = false
    public let yadifMode = KSOptions.yadifMode
    public let deInterlaceAddIdet = KSOptions.deInterlaceAddIdet
    public var dynamicRange = DynamicRange.sdr
    // Field record 44 of 84 (FieldDescriptor 0x103cba11c, desc 0x1039ec4c0). Its mangled type is a
    // ctrl-0x02 SYMBOLIC REFERENCE, not a literal mangle: raw bytes `02 5f 43 4e 00 53 67`, i.e.
    // ctrl 0x02 + rel32 0x004e435f + tail `Sg`. Resolving per MEMORY rule 28 — add the rel32 to the
    // address of the offset field itself — gives __got 0x104112A00, which
    // `llvm-objdump --macho --bind` binds to libswiftCore `_$ss5UInt8VMn` = the nominal type
    // descriptor for Swift.UInt8; the `Sg` tail makes it Optional. So the binary field is UInt8?,
    // not Int?. Zero consumers in the tree (this declaration is the only reference), so the
    // narrowing ripples nowhere.
    public var doviProfile: UInt8?
    public var audioCodecName: String?
    public var audioChannelCount: UInt32 = 0
    // video
    public var display = DisplayEnum.plane
    public var videoPipeline: VideoPipeline?
    public var videoDelay = 0.0 // s
    public var isRotateByFilter = false
    public var destinationDynamicRange: DynamicRange?
    public var videoAdaptable = false // Forward default = false (init stores 0)
    public var videoFilters = [String]()
    public var syncDecodeVideo = false
    public var decodeType = DecodeType.avplayer
    public var hardwareDecode = KSOptions.hardwareDecode
    public var asynchronousDecompression = KSOptions.asynchronousDecompression
    public var videoDisable = false
    public var canStartPictureInPictureAutomaticallyFromInline = KSOptions.canStartPictureInPictureAutomaticallyFromInline
    public var automaticWindowResize = true
    public var videoSoftDecodeThreadCount = KSOptions.videoSoftDecodeThreadCount
    public var isDoubleRefreshRate = false
    public var renderUseDispatchSourceTimer = false
    public var brightness: Float = 1.0 {
        didSet {
            adjustBuffer = KSOptions.makeAdjustBuffer(brightness: brightness, contrast: contrast, saturation: saturation)
        }
    }
    public var contrast: Float = 1.0 {
        didSet {
            adjustBuffer = KSOptions.makeAdjustBuffer(brightness: brightness, contrast: contrast, saturation: saturation)
        }
    }
    public var saturation: Float = 1.0 {
        didSet {
            adjustBuffer = KSOptions.makeAdjustBuffer(brightness: brightness, contrast: contrast, saturation: saturation)
        }
    }
    // adjustBuffer holds a 16-byte MTLBuffer of SIMD4<Float>(brightness, contrast, saturation, enable),
    // rebuilt by each colour property's didSet; the default is folded from the (1,1,1) defaults → [1,1,1,0].
    // ⚑ INFERRED name `makeAdjustBuffer`: the builder is inlined at all four call sites (KSOptions.init +
    //   the 3 didSets), so its source symbol is unrecoverable — a shared static factory is the DRY reading,
    //   matching the MetalRender lazy-buffer idiom (label set on the returned MTLBuffer).
    public var adjustBuffer: MTLBuffer? = KSOptions.makeAdjustBuffer(brightness: 1, contrast: 1, saturation: 1)
    // (Corroboration for the ⚑ INFERRED `makeAdjustBuffer` above — POSITIONAL only, not a name
    // proof: slot 216 is a Method slot with a NULL impl in the descriptor, declared between
    // `saturation` (slots 213-215) and `adjustBuffer` (217-219) — exactly where a colour-adjust
    // builder would sit, and a null impl is what "inlined at every call site" leaves behind.)
    //
    // Slots 220-225 are SIX methods declared HERE, between `adjustBuffer` (217-219) and
    // `forceDisableDisplayLayer` (226-228) — both bracketing getters resolve their field-offset
    // global BY NAME, so the bracket is exact.
    //
    // ⚠️ SESSION 64 — "None of the six has a recoverable member identity" IS REFUTED. That rested
    // on recover_swift_function_name, which works off #function/#file literals that a release
    // build strips, and which cannot see the ORPHANED EXPORT TRIE. All six resolve by address
    // (P133/P135 — the same failure mode as SubtitlePart's "missing" inits and the PiP pin):
    //   220 @0x1019be928  preferredFrame(fps: Swift.Float) -> Swift.Bool
    //   221 @0x1019be98c  decodeSize(width: Swift.Int32, height: Swift.Int32) -> __C.CGSize
    //   222 @0x1019bea08  recreateContext(hasDecodeSuccess: Swift.Bool, isKeyFrame: Swift.Bool) -> Swift.Bool
    //   223 @0x1019bea14  wantedVideo(tracks: [MediaPlayerTrack]) -> MediaPlayerTrack?
    //   224 @0x1019bea54  videoFrameMaxCount(fps:naturalSize:isLive:reorderSize: Swift.Int32) -> Swift.UInt8
    //   225 @0x100232cd4  customizeDar(sar: __C.CGSize, par: __C.CGSize) -> __C.CGSize?
    // Each recovered name COHERES with the body an earlier session had already decoded
    // independently (220 = `staticBool || fps > 61.0`; 222 = `!arg0 || arg1`; 223 retains an
    // element when a field is non-nil) — corroboration, not just nomination.
    // 222 is now DECLARED below with its body; 224/225 are declared and audited FAITHFUL.
    // ⛔ 223 `wantedVideo` returns MediaPlayerTrack?, NOT the Int? this file declares — that is
    // the index->object migration (with wantedAudio and audioFrameMaxCount), a separate unit
    // with call-site ripple. NOT changed here.
    // 220/221 remain UNDECLARED: names recovered, bodies not yet reconstructed.
    // Context (not in this batch): slot 220 @0x1019be928 = `staticBool || fpsArg > 61.0` → Bool;
    // slot 221 @0x1019be98c reads UITraitCollection.current.userInterfaceIdiom; slot 223
    // @0x1019bea14 retains arg+0x20 when arg+0x10 is non-nil.
    //
    // Slot 222 @0x1019bea08 — DISCHARGED (s64): identity recovered, declared and audited below as
    // `recreateContext(hasDecodeSuccess:isKeyFrame:)`. Body `orn w8,w1,w0; and w0,w8,#0x1; ret` =
    // two Bool-shaped argument words (w0, w1) and a 1-bit result equal to `!arg0 || arg1`.
    // ⚠️ The xref count here read "5 = 1 descriptor + 3 metadata vtables + 1 linkedit"; that is
    // FALSE for this slot — `dyld_info -fixups` reports TWO rebases, so it is 4 = 1 descriptor +
    // 2 metadata vtables + 1 LC_FUNCTION_STARTS entry. The same sentence was written for slot 224,
    // where 3 IS correct. The CONCLUSION ("its own impl, not a folded stub") stands, but it rests
    // on the one-symbol trie count and the byte pattern being unique in __text, not on this tally.
    //
    // Slot 224 @0x1019bea54 — PINNED. Body is `cmp w1,#0x2; mov w8,#0x4; mov w9,#0x8;
    // csel w0,w9,w8,gt; ret` — i.e. the only input the body reads is w1 (a signed 32-bit word;
    // self rides x20, so w1 is the SECOND argument word) and the 4-byte result is 8 when w1 > 2,
    // else 4. 5 xrefs = 1 descriptor + 3 metadata vtables + 1 linkedit (own impl).
    // ⚑[tool=vtable_walk+recover_swift_function_name ref=FUN_1019bea54:0x1019bea54 result=LOCATED pinned=member-identity-undetermined]  ⚑[tool=resolve_fun_pins ref=FUN_1019bea54:0x1019bea54 result=RESOLVES_UNIQUELY] = KSPlayer.KSOptions.videoFrameMaxCount(fps: Swift.Float, naturalSize: __C.CGSize, isLive: Swift.Bool, reorderSize: Swift.Int32) -> Swift.UInt8
    //
    // Slot 225 @0x100232cd4 — PINNED. Body `mov x0,#0x0; mov x1,#0x0; mov w2,#0x1; ret`: the
    // three-register `nil` of an Optional whose payload is two 8-byte words (x0, x1 payload +
    // w2 tag = 1). Shape-identical to how slot 59's `adaptable`-style result is returned, but the
    // body is LINKER-FOLDED — besides the KSOptions descriptor slot (0x1039ecc0c) it is also
    // claimed by a second, different type descriptor (0x1039efab4) — so the body proves the return
    // shape and nothing about which member this is.
    // ⚑[tool=vtable_walk+get_xrefs_to ref=FUN_100232cd4:0x100232cd4 result=LOCATED pinned=member-identity-undetermined]
    public var forceDisableDisplayLayer = false
    public var onPossibleDisplayLayerFlicker: (@MainActor @Sendable () -> Void)?
    private var videoClockDelayCount = 0
    public internal(set) var lastVideoClockDropLogTime = 0.0
    public internal(set) var prepareTime = 0.0
    public internal(set) var dnsStartTime = 0.0
    public internal(set) var tcpStartTime = 0.0
    public internal(set) var tcpConnectedTime = 0.0
    public internal(set) var openTime = 0.0
    public internal(set) var findTime = 0.0
    public internal(set) var readyTime = 0.0
    public internal(set) var readAudioTime = 0.0
    public internal(set) var readVideoTime = 0.0
    public internal(set) var decodeAudioTime = 0.0
    public internal(set) var decodeVideoTime = 0.0
    public internal(set) var firstPlayableTime = 0.0

    // ⚑ INFERRED name `resetTime`: #function unrecoverable (direct call @0x1019c0798, no vtable slot).
    //   KSMEPlayer's prepare path (caller @0x101a432fc, logs "Preparing to Play") calls
    //   `options.<this>()` to zero the prepare-pipeline timing telemetry before a fresh measurement.
    //   Resets exactly the 12 *Time fields above (prepareTime…firstPlayableTime), in declaration
    //   order; each Double → 0. Access modifier not binary-determinable → internal (same-module caller).
    func resetTime() {
        prepareTime = 0
        dnsStartTime = 0
        tcpStartTime = 0
        tcpConnectedTime = 0
        openTime = 0
        findTime = 0
        readyTime = 0
        readAudioTime = 0
        readVideoTime = 0
        decodeAudioTime = 0
        decodeVideoTime = 0
        firstPlayableTime = 0
    }

    public init() {
        formatContextOptions["user_agent"] = userAgent
        // 参数的配置可以参考protocols.texi 和 http.c
        // 这个一定要，不然有的流就会判断不准FieldOrder
        formatContextOptions["scan_all_pmts"] = 1
        // ts直播流需要加这个才能一直直播下去，不然播放一小段就会结束了。
        formatContextOptions["reconnect"] = 1
        formatContextOptions["reconnect_streamed"] = 1
        // 这个是用来开启http的链接复用（keep-alive）。vlc默认是打开的，所以这边也默认打开。
        // 开启这个，百度网盘的视频链接无法播放
        // formatContextOptions["multiple_requests"] = 1
        // 下面是用来处理秒开的参数，有需要的自己打开。默认不开，不然在播放某些特殊的ts直播流会频繁卡顿。
//        formatContextOptions["auto_convert"] = 0
//        formatContextOptions["fps_probe_size"] = 3
//        formatContextOptions["rw_timeout"] = 10_000_000
//        formatContextOptions["max_analyze_duration"] = 300 * 1000
        // 默认情况下允许所有协议，只有嵌套协议才需要指定这个协议子集，例如m3u8里面有http。
//        formatContextOptions["protocol_whitelist"] = "file,http,https,tcp,tls,crypto,async,cache,data,httpproxy"
        // 开启这个，纯ipv6地址会无法播放。并且有些视频结束了，但还会一直尝试重连。所以这个值默认不设置
//        formatContextOptions["reconnect_at_eof"] = 1
        // 开启这个，会导致tcp Failed to resolve hostname 还会一直重试
//        formatContextOptions["reconnect_on_network_error"] = 1
        // There is total different meaning for 'listen_timeout' option in rtmp
        // set 'listen_timeout' = -1 for rtmp、rtsp
//        formatContextOptions["listen_timeout"] = 3
        decoderOptions["threads"] = "auto"
        decoderOptions["refcounted_frames"] = "1"
    }

    /**
     you can add http-header or other options which mentions in https://developer.apple.com/reference/avfoundation/avurlasset/initialization_options

     to add http-header init options like this
     ```
     options.appendHeader(["Referer":"https:www.xxx.com"])
     ```
     */
    public func appendHeader(_ header: [String: String]) {
        var oldValue = avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [
            String: String
        ]()
        oldValue.merge(header) { _, new in new }
        avOptions["AVURLAssetHTTPHeaderFieldsKey"] = oldValue
        var str = formatContextOptions["headers"] as? String ?? ""
        for (key, value) in header {
            str.append("\(key):\(value)\r\n")
        }
        formatContextOptions["headers"] = str
    }

    public func setCookie(_ cookies: [HTTPCookie]) {
        avOptions[AVURLAssetHTTPCookiesKey] = cookies
        let cookieStr = cookies.map { cookie in "\(cookie.name)=\(cookie.value)" }.joined(separator: "; ")
        appendHeader(["Cookie": cookieStr])
    }

    // 缓冲算法函数
    open func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
        let packetCount = capacitys.map(\.packetCount).min() ?? 0
        let frameCount = capacitys.map(\.frameCount).min() ?? 0
        let isEndOfFile = capacitys.allSatisfy(\.isEndOfFile)
        let loadedTime = capacitys.map(\.loadedTime).min() ?? 0
        let progress = preferredForwardBufferDuration == 0 ? 100 : loadedTime * 100.0 / preferredForwardBufferDuration
        let isPlayable = capacitys.allSatisfy { capacity in
            if capacity.isEndOfFile && capacity.packetCount == 0 {
                return true
            }
            guard capacity.frameCount >= 2 else {
                return false
            }
            if capacity.isEndOfFile {
                return true
            }
            if (syncDecodeVideo && capacity.mediaType == .video) || (syncDecodeAudio && capacity.mediaType == .audio) {
                return true
            }
            if isFirst || isSeek {
                // 让纯音频能更快的打开
                if capacity.mediaType == .audio || isSecondOpen {
                    if isFirst {
                        return true
                    } else {
                        return capacity.loadedTime >= self.preferredForwardBufferDuration / 2
                    }
                }
            }
            return capacity.loadedTime >= self.preferredForwardBufferDuration
        }
        return LoadingState(loadedTime: loadedTime, progress: progress, packetCount: packetCount,
                            frameCount: frameCount, isEndOfFile: isEndOfFile, isPlayable: isPlayable,
                            isFirst: isFirst, isSeek: isSeek)
    }

    open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)? {
        guard let state, let last = state.bitRateStates.last, CACurrentMediaTime() - last.time > maxBufferDuration / 2, let index = state.bitRates.firstIndex(of: last.bitRate) else {
            return nil
        }
        let isUp = state.loadedCount > Int(Double(state.fps) * maxBufferDuration / 2)
        if isUp != state.isPlayable {
            return nil
        }
        if isUp {
            if index < state.bitRates.endIndex - 1 {
                return (last.bitRate, state.bitRates[index + 1])
            }
        } else {
            if index > state.bitRates.startIndex {
                return (last.bitRate, state.bitRates[index - 1])
            }
        }
        return nil
    }

    // vtable slot 222 @0x1019bea08 — three instructions, its own impl, NOT an ICF fold (the
    // address exports exactly one symbol, and the 12-byte pattern occurs once in all of __text).
    // 4 xrefs = 1 method descriptor + 2 metadata vtables + 1 LC_FUNCTION_STARTS entry; the two
    // vtables are KSOptions' own and TrailerPlayerOptions'. Verified by `dyld_info -fixups`,
    // which reports exactly TWO rebases to this address (0x10448D358, 0x1044E5D28).
    // ⚠️ Slot 224 @0x1019bea54 has THREE rebases, and an earlier session wrote "3 metadata
    // vtables" for BOTH slots — true there, false here. Count them per address; do not carry
    // the sentence across.
    //   orn w8, w1, w0   ·   and w0, w8, #0x1   ·   ret        =>  (w1 | ~w0) & 1
    // self rides x20, so w0/w1 are the two Bool argument words: hasDecodeSuccess, isKeyFrame.
    // ⚠️ The `||` operand ORDER is NOT recoverable: both spellings canonicalise to the same
    // branchless `orn`, so `isKeyFrame || !hasDecodeSuccess` is equally consistent with the code.
    // Declared immediately before `wantedVideo` because the binary orders these 222 then 223.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.recreateContext:0x1019bea08 result=name-recovered]
    open func recreateContext(hasDecodeSuccess: Bool, isKeyFrame: Bool) -> Bool {
        !hasDecodeSuccess || isKeyFrame
    }

    ///  wanted video stream index, or nil for automatic selection
    /// - Parameter : video track
    /// - Returns: The index of the track
    open func wantedVideo(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }

    /// wanted audio stream index, or nil for automatic selection
    /// - Parameter :  audio track
    /// - Returns: The index of the track
    open func wantedAudio(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }

    // Forward 1.3.17 takes a 4th argument and branches on IT, not on `isLive`:
    //   cmp w1,#0x2 · mov w8,#4 · mov w9,#8 · csel w0,w9,w8,gt · ret
    // w1 is `reorderSize` (fps/naturalSize consume FP registers, `isLive` takes w0, self is x20);
    // w0 is only the csel DESTINATION, never a source operand, and a Swift Bool cannot make
    // `cmp #2 / csel gt` non-constant — so the tested value is provably not `isLive`.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.videoFrameMaxCount:0x1019bea54 result=signature+body-recovered]
    open func videoFrameMaxCount(fps _: Float, naturalSize _: CGSize, isLive _: Bool, reorderSize: Int32) -> UInt8 {
        reorderSize > 2 ? 8 : 4
    }

    open func audioFrameMaxCount(fps: Float, channelCount: Int) -> UInt8 {
        let count = (Int(fps) * channelCount) >> 2
        if count >= UInt8.max {
            return UInt8.max
        } else {
            return UInt8(count)
        }
    }

    /// customize dar
    /// - Parameters:
    ///   - sar: SAR(Sample Aspect Ratio)
    ///   - dar: PAR(Pixel Aspect Ratio)
    /// - Returns: DAR(Display Aspect Ratio)
    open func customizeDar(sar _: CGSize, par _: CGSize) -> CGSize? {
        nil
    }

    // 虽然只有iOS才支持PIP。但是因为AVSampleBufferDisplayLayer能够支持HDR10+。所以默认还是推荐用AVSampleBufferDisplayLayer
    open func isUseDisplayLayer() -> Bool {
        display == .plane
    }

    open func urlIO(log: String) {
        if log.starts(with: "Original list of addresses"), dnsStartTime == 0 {
            dnsStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Starting connection attempt to"), tcpStartTime == 0 {
            tcpStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Successfully connected to"), tcpConnectedTime == 0 {
            tcpConnectedTime = CACurrentMediaTime()
        }
    }

    open func filter(log _: String) {
        // Forward DROPPED autoDeInterlace / videoInterlacingType / idetTypeMap from the KSOptions field set
        // (binary reflection: all three absent). The base's `Repeated Field:` idet auto-detection was built
        // entirely on those three, so it cannot exist in Forward. Forward's filter() body is // UNRESOLVED —
        // reconstruct from the binary if non-empty; the open API surface is preserved (MEPlayerItem's log
        // handler calls it). NOT fabricated (a guessed body would look done and mislead).
    }

    open func sei(string: String) {
        KSLog("sei \(string)")
    }

    // ⚑ INFERRED name `processHardwareDecode`: #function unrecoverable (direct call @0x1019b5fe0, no
    //   vtable slot; recover_swift_function_name → None). A KSOptions helper (called by the video-format
    //   setup @0x100a5d8d8) that forces software decoding for H.264 High 4:4:4 Predictive — a profile
    //   VideoToolbox can't hardware-decode. Binary: `assetTrack as? FFmpegAssetTrack` (WMO-optimized to
    //   an exact object_getClass compare vs the FFmpegAssetTrack metadata) then reads codecpar.pointee
    //   .profile (AVCodecParameters+0x40, FFmpegKit-8.1.1 header) == 244 = AV_PROFILE_H264_HIGH_444_PREDICTIVE
    //   (defs.h:122).
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer9KSOptionsC7process10assetTrackyx_tAA16MediaPlayerTrack_pRzlF:0x1019b5fe0 result=RENAMED]
    // NAME CORRECTED (session 65): this body was called `processHardwareDecode`, a name that occurs
    // ZERO times in the binary's 57k-symbol index. The trie names 0x1019b5fe0 — the address this
    // body's own FAITHFUL verdict audited — `process<A: MediaPlayerTrack>(assetTrack: A)`. The old
    // name was invented, and the prose above it ("Access modifier not binary-determinable →
    // internal") is refuted by the method descriptor at 0x1039ec800 and by two `Components`
    // subclasses overriding it, so it is `open`. Independently derived by two agents that did not
    // share findings. The body is unchanged; only the identity was wrong.
    open func process(assetTrack: some MediaPlayerTrack) {
        // 244 = AV_PROFILE_H264_HIGH_444_PREDICTIVE (a C `#define`, not bridged into Swift → literal,
        //   as the binary compares `cmp w8, #0xf4`).
        if let assetTrack = assetTrack as? FFmpegAssetTrack,
           assetTrack.codecpar.pointee.profile == 244 {
            hardwareDecode = false
        }
    }

    /**
            在创建解码器之前可以对KSOptions和assetTrack做一些处理。例如判断fieldOrder为tt或bb的话，那就自动加videofilters
     */
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer9KSOptionsC11deinterlace10assetTrackyAA17FFmpegAssetTrackC_tF:0x1019b66c4 result=RENAMED]
    // NAME + PARAMETER TYPE CORRECTED (session 65): this body was called `process(assetTrack:)`,
    // but the binary calls it `deinterlace(assetTrack: FFmpegAssetTrack)` — concrete, not generic.
    // Proven by the ONLY reference to the `:parity=-1:deint=1` literal (0x103d34560), which sits at
    // 0x1019b6828, inside this function's extent (0x1019b66c4..0x1019b6974). `deinterlace` was
    // already listed in member_missing_s63.json as a member the binary names and the source never
    // declares; this is why. Two independent agents reached the same pairing.
    // ⚑ BODY RECONSTRUCTED from 0x1019b66c4 (172 instr; verified via llvm-objdump, session 67).
    //   Straight-line, no mediaType/fieldOrder guard: (a) `hardwareDecode = false` unconditionally
    //   first (`strb wzr,[x19,x21]` @0x1019b6704, no preceding branch); (b) `if deInterlaceAddIdet`
    //   then append the "idet" literal (built @0x1019b6770 = 0x74656469); (c) yadifMode and
    //   deInterlaceAddIdet are read as STORED INSTANCE properties (`[x19,off]`), not statics;
    //   (d) yadifMode decremented when nominalFrameRate>30 (`ldr s0,[x20,#0x58]`; fcmp #30.0);
    //   (e) append "yadif=mode=\(yadifMode)" + ":parity=-1:deint=1" (18-char literal @0x103d34540);
    //   (f) tail sets `isDoubleRefreshRate = true` when yadifMode∈{1,3}. Verdict flipped FAITHFUL.
    open func deinterlace(assetTrack: FFmpegAssetTrack) {
        hardwareDecode = false
        if deInterlaceAddIdet {
            videoFilters.append("idet")
        }
        var yadifMode = self.yadifMode
        if assetTrack.nominalFrameRate > 30, yadifMode == 1 || yadifMode == 3 {
            yadifMode -= 1
        }
        videoFilters.append("yadif=mode=\(yadifMode):parity=-1:deint=1")
        if yadifMode == 1 || yadifMode == 3 {
            isDoubleRefreshRate = true
        }
    }

    // ⚑ INFERRED name (unrecoverable — inlined at every call site). Builds the colour-adjustment
    //   uniform buffer: SIMD4<Float>(brightness, contrast, saturation, enable), where `enable` is 0
    //   when no adjustment is active (all three == 1) and 1 otherwise. 16 bytes, label "adjust"
    //   (both verified from the binary: the packed q-register lanes + the Swift small-string 0xE6…"adjust").
    private static func makeAdjustBuffer(brightness: Float, contrast: Float, saturation: Float) -> MTLBuffer? {
        let enable: Float = brightness == 1 && contrast == 1 && saturation == 1 ? 0 : 1
        var adjust = SIMD4<Float>(brightness, contrast, saturation, enable)
        let buffer = MetalRender.device.makeBuffer(bytes: &adjust, length: MemoryLayout<SIMD4<Float>>.size)
        buffer?.label = "adjust"
        return buffer
    }

    @MainActor
    open func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        #if os(tvOS) || os(xrOS)
        /**
         快速更改preferredDisplayCriteria，会导致isDisplayModeSwitchInProgress变成true。
         例如退出一个视频，然后在3s内重新进入的话。所以不判断isDisplayModeSwitchInProgress了
         */
        guard let displayManager = UIApplication.shared.windows.first?.avDisplayManager,
              displayManager.isDisplayCriteriaMatchingEnabled
        else {
            return
        }
        if var dynamicRange = formatDescription?.dynamicRange {
            if dynamicRange == .dolbyVision {
                dynamicRange = .hdr10
            }
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, videoDynamicRange: dynamicRange.rawValue)
        }
        #endif
    }

    open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: Int) -> (Double, ClockProcessType) {
        let desire = main.getTime() - videoDelay
        let diff = nextVideoTime - desire
//        print("[video] video diff \(diff) nextVideoTime \(nextVideoTime) main \(main.time.seconds)")
        if diff >= 1 / fps / 2 {
            videoClockDelayCount = 0
            return (diff, .remain)
        } else {
            if diff < -4 / fps {
                videoClockDelayCount += 1
                let log = "[video] video delay=\(diff), clock=\(desire), delay count=\(videoClockDelayCount), frameCount=\(frameCount)"
                if frameCount == 1 {
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) drop gop Packet")
                        return (diff, .dropGOPPacket)
                    } else if videoClockDelayCount % 5 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                } else {
                    if diff < -8, videoClockDelayCount % 100 == 0 {
                        KSLog("\(log) seek video track")
                        return (diff, .seek)
                    }
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) flush video track")
                        return (diff, .flush)
                    }
                    if videoClockDelayCount % 2 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                }
            } else {
                videoClockDelayCount = 0
                return (diff, .next)
            }
        }
    }

    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer9KSOptionsC21availableDynamicRangeAA07DynamicF0OSgyF:0x1019bee0c result=SIGNATURE_CORRECTED]
    // The binary takes NO parameter (35-instruction body @0x1019bee0c; the descriptor at
    // 0x1039ecc48 confirms the arity, and the body touches no argument register). The source's
    // `contentRange` is removed; its only call site passed `nil`, so dropping it invents nothing.
    // ⚑ BODY RECONSTRUCTED (s67, verified via llvm-objdump over 0x1019bee0c, 35 instr): the binary is a
    //   3-line algorithm over a native [DynamicRange]. No #if split (the compiled branch is UIKit).
    //   (1) guard let destinationDynamicRange (nil == byte 4: `ldrb w19; cmp #4; b.eq` @0x1019bee3c;
    //       DynamicRange raws are 0/2/3/5, so 4 is the nil extra-inhabitant);
    //   (2) available = DynamicRange.availableHDRModes — the helper @0x1019e4078 (AVPlayer ObjC classref
    //       @0x104410cb0; bit-tests dolbyVision=bit2/hdr10=bit1/hlg=bit0 → [DynamicRange]); count@+0x10,
    //       1-byte elems@+0x20+i;
    //   (3) if available.contains(d) { return d } (loop+cmp @0x1019bee58-0x1019bee68);
    //   (4) return available.first (array[0], or nil/byte-4 when empty @0x1019bee7c).
    open func availableDynamicRange() -> DynamicRange? {
        guard let destinationDynamicRange else { return nil }
        let available = DynamicRange.availableHDRModes
        if available.contains(destinationDynamicRange) { return destinationDynamicRange }
        return available.first
    }

    open func playerLayerDeinit() {
        #if os(tvOS) || os(xrOS)
        runOnMainThread {
            UIApplication.shared.windows.first?.avDisplayManager.preferredDisplayCriteria = nil
        }
        #endif
    }

    open func liveAdaptivePlaybackRate(loadingState _: LoadingState) -> Float? {
        nil
//        if loadingState.isFirst {
//            return nil
//        }
//        if loadingState.loadedTime > preferredForwardBufferDuration + 5 {
//            return 1.2
//        } else if loadingState.loadedTime < preferredForwardBufferDuration / 2 {
//            return 0.8
//        } else {
//            return 1
//        }
    }

    open func process(url _: URL) -> AbstractAVIOContext? {
        nil
    }
}

public enum VideoInterlacingType: String {
    case tff
    case bff
    case progressive
    case undetermined
}

public extension KSOptions {
    nonisolated(unsafe) static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    nonisolated(unsafe) static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self
    nonisolated(unsafe) static var playerTypes: [MediaPlayerProtocol.Type] = [KSAVPlayer.self, KSMEPlayer.self]
    /// 最低缓存视频时间
    nonisolated(unsafe) static var preferredForwardBufferDuration = 3.0
    /// 最大缓存视频时间
    nonisolated(unsafe) static var maxBufferDuration = 30.0
    /// 是否开启秒开
    nonisolated(unsafe) static var isSecondOpen = false
    /// 开启精确seek
    nonisolated(unsafe) static var isAccurateSeek = false
    /// Applies to short videos only
    nonisolated(unsafe) static var isLoopPlay = false
    /// 是否自动播放，默认true
    nonisolated(unsafe) static var isAutoPlay = true
    /// seek完是否自动播放
    nonisolated(unsafe) static var isSeekedAutoPlay = true
    nonisolated(unsafe) static var hardwareDecode = true
    // 默认不用自研的硬解，因为有些视频的AVPacket的pts顺序是不对的，只有解码后的AVFrame里面的pts是对的。
    nonisolated(unsafe) static var asynchronousDecompression = false
    nonisolated(unsafe) static var videoSoftDecodeThreadCount = 4
    nonisolated(unsafe) static var isPipPopViewController = false
    nonisolated(unsafe) static var canStartPictureInPictureAutomaticallyFromInline = true
    nonisolated(unsafe) static var preferredFrame = true
    nonisolated(unsafe) static var useSystemHTTPProxy = true
    /// 日志级别
    // default = .error: the logLevel global byte @0x1044e5173 = 2, the CASE INDEX of .error
    // (a fieldless enum stores/reads as its case index, not the rawValue — 2 matches no LogLevel
    // rawValue [0/8/16/24/…], so it is unambiguously the index; see the KSLog gate note below).
    nonisolated(unsafe) static var logLevel = LogLevel.error
    nonisolated(unsafe) static var logger: LogHandler = OSLog(lable: "KSPlayer")
    internal static func deviceCpuCount() -> Int {
        var ncpu = UInt(0)
        var len: size_t = MemoryLayout.size(ofValue: ncpu)
        sysctlbyname("hw.ncpu", &ncpu, &len, nil, 0)
        return Int(ncpu)
    }

    static func setAudioSession() {
        #if os(macOS)
//        try? AVAudioSession.sharedInstance().setRouteSharingPolicy(.longFormAudio)
        #else
        var category = AVAudioSession.sharedInstance().category
        if category != .playAndRecord {
            category = .playback
        }
        #if os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormAudio)
        #else
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormVideo)
        #endif
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    #if !os(macOS)
    static func isSpatialAudioEnabled(channelCount _: AVAudioChannelCount) -> Bool {
        if #available(tvOS 15.0, iOS 15.0, *) {
            let isSpatialAudioEnabled = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
            try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(isSpatialAudioEnabled)
            return isSpatialAudioEnabled
        } else {
            return false
        }
    }

    static func outputNumberOfChannels(channelCount: AVAudioChannelCount) -> AVAudioChannelCount {
        let maximumOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        let preferredOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().preferredOutputNumberOfChannels)
        let isSpatialAudioEnabled = isSpatialAudioEnabled(channelCount: channelCount)
        let isUseAudioRenderer = KSOptions.audioPlayerType == AudioRendererPlayer.self
        KSLog("[audio] maximumOutputNumberOfChannels: \(maximumOutputNumberOfChannels), preferredOutputNumberOfChannels: \(preferredOutputNumberOfChannels), isSpatialAudioEnabled: \(isSpatialAudioEnabled), isUseAudioRenderer: \(isUseAudioRenderer) ")
        let maxRouteChannelsCount = AVAudioSession.sharedInstance().currentRoute.outputs.compactMap {
            $0.channels?.count
        }.max() ?? 2
        KSLog("[audio] currentRoute max channels: \(maxRouteChannelsCount)")
        var channelCount = channelCount
        if channelCount > 2 {
            let minChannels = min(maximumOutputNumberOfChannels, channelCount)
            #if os(tvOS) || targetEnvironment(simulator)
            if !(isUseAudioRenderer && isSpatialAudioEnabled) {
                // 不要用maxRouteChannelsCount来判断，有可能会不准。导致多音道设备也返回2（一开始播放一个2声道，就容易出现），也不能用outputNumberOfChannels来判断，有可能会返回2
//                channelCount = AVAudioChannelCount(min(AVAudioSession.sharedInstance().outputNumberOfChannels, maxRouteChannelsCount))
                channelCount = minChannels
            }
            #else
            // iOS 外放是会自动有空间音频功能，但是蓝牙耳机有可能没有空间音频功能或者把空间音频给关了，。所以还是需要处理。
            if !isSpatialAudioEnabled {
                channelCount = minChannels
            }
            #endif
        } else {
            channelCount = 2
        }
        // 不在这里设置setPreferredOutputNumberOfChannels,因为这个方法会在获取音轨信息的时候，进行调用。
        KSLog("[audio] outputNumberOfChannels: \(AVAudioSession.sharedInstance().outputNumberOfChannels) output channelCount: \(channelCount)")
        return channelCount
    }
    #endif
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
            fileHandle.write(data)
        }
    }
}

// The message existential carries the BRIDGED NSError itself, not its
// localizedDescription. At an inlined call site (AudioEnginePlayer.doPlay
// @0x101a0f438) the sequence is $_convertErrorToNSError -> an NSError class-metadata
// fetch -> a RUNTIME conformance lookup, with the NSError pointer stored straight into
// the existential buffer. A `.localizedDescription` message would instead be a String
// carried by the statically-known String : CustomStringConvertible witness and would
// leave a localizedDescription accessor call — that body has none.
@inlinable
public func KSLog(_ error: @autoclosure () -> Error, file: String = #file, function: String = #function, line: UInt = #line) {
    KSLog(level: .error, error() as NSError, file: file, function: function, line: line)
}

// `file` reaches the log handler UNTRANSFORMED — upstream's
// `(file as NSString).lastPathComponent` step is gone. At every inlined site the count
// word handed to the handler's witness is the FULL #file length (0x20 = 32 for
// "KSPlayer/AudioEnginePlayer.swift"; the basename would be 23), and no site performs a
// String->NSString bridge or a lastPathComponent call — prepare @0x101a0e0a8 has four
// inlined KSLogs across 792 instructions and neither appears.
//
// NOTE the level literals at inlined sites (2 for .error, 3 for .warning) are enum CASE
// INDICES, not raw values: a fieldless enum is stored and passed as its case index
// regardless of any RawValue conformance, so the gate compiles to `ldrb w8,[logLevel];
// cmp w8,#0x3`. The declared raw values are NOT merely assumed here — setLogCallback's
// body @0x101a0a8f8-0x101a0a95c emits the tag->rawValue switch as 0/8/0x10/0x18/0x20/
// 0x28/0x30 with `ubfiz w9,w20,#0x3,#0x8` (rawValue == tag * 8), byte-for-byte the
// AV_LOG_* values below. Since they are monotonic in declaration order, the constant
// folder reduces `level.rawValue <= KSOptions.logLevel.rawValue` to the tag compare, so
// this `<=` is faithful as written and must not be "corrected" to match the literals.
@inlinable
public func KSLog(level: LogLevel = .warning, _ message: @autoclosure () -> CustomStringConvertible, file: String = #file, function: String = #function, line: UInt = #line) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        KSOptions.logger.log(level: level, message: message(), file: file, function: function, line: line)
    }
}

@inlinable
public func KSLog(level: LogLevel = .warning, dso: UnsafeRawPointer = #dsohandle, _ message: StaticString, _ args: CVarArg...) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        os_log(level.logType, dso: dso, message, args)
    }
}

public extension Array {
    func toDictionary<Key: Hashable>(with selectKey: (Element) -> Key) -> [Key: Element] {
        var dict = [Key: Element]()
        forEach { element in
            dict[selectKey(element)] = element
        }
        return dict
    }
}

public struct KSClock {
    public private(set) var lastMediaTime = CACurrentMediaTime()
    public internal(set) var position = Int64(0)
    public internal(set) var time = CMTime.zero {
        didSet {
            lastMediaTime = CACurrentMediaTime()
        }
    }

    func getTime() -> TimeInterval {
        time.seconds + CACurrentMediaTime() - lastMediaTime
    }
}
