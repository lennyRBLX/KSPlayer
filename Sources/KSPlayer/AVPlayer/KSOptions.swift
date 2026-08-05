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
// ⚑ s106: required by the five `SwiftUI.Color` statics below. The import is implied by types read
// from the binary — each of those storage globals demangles to `… : SwiftUI.Color` — not chosen.
import SwiftUI

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
    public var context: String = ""
    public var avOptions: [String: Any] = [String: Any]()
    public var isLive: Bool?
    public var startPlayTime: TimeInterval = 0
    public var startPlayTimePercentage: Double = 0.0
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true // 默认支持来自系统控制中心的控制
    public var isAutoPlay: Bool = KSOptions.isAutoPlay
    public var enterForgeResumePlay: Bool = false
    public var isDLNARunning: Bool = false
    public var disableVideoFrameRateMatching: Bool = false
    /// 是否开启秒开
    public var isSecondOpen: Bool = KSOptions.isSecondOpen
    public var playbackTimeInterval: Double = 0.04
    // playerTypes default reads the static KSOptions.playerTypes (not an inline literal).
    // ⚑[tool=decompile_function ref=FUN_1019b4334:0x1019b4334 result=static [KSAVPlayer.self,KSMEPlayer.self] — element class-descriptor names confirmed @0x1039ec148/@0x1039ef750]
    public var playerTypes: [MediaPlayerProtocol.Type] = KSOptions.playerTypes
    public var mixAudio: Bool = false
    public var canBackgroundPlay: Bool = true
    public var contentMode = UIViewContentMode.scaleAspectFit  // macOS: KSPlayer.ContentMode (== binary); iOS/tvOS: UIView.ContentMode
    /// Applies to short videos only
    public var isLoopPlay: Bool = KSOptions.isLoopPlay
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
    // ⚠️ s97 — every number in the four anchors above is an IDX, not a slot; they are off by
    // VTableOffset=94. Checked against the vtable: idx125→slot219 syncDecodeAudio.getter,
    // idx134→slot228 audioRecognizes.getter, idx217→slot311 adjustBuffer.getter,
    // idx226→slot320 forceDisableDisplayLayer.getter — all four resolve in idx space and none in
    // slot space. The real slot217 is idx123, audioFilters.setter. Record both as `idx<N> slot<M>`.
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
    public var isAccurateSeek: Bool = KSOptions.isAccurateSeek
    /// seek完是否自动播放
    public var isSeekedAutoPlay: Bool = KSOptions.isSeekedAutoPlay
    /*
     AVSEEK_FLAG_BACKWARD: 1
     AVSEEK_FLAG_BYTE: 2
     AVSEEK_FLAG_ANY: 4
     AVSEEK_FLAG_FRAME: 8
     */
    public var seekFlags: Int32 = Int32(1)
    //  record stream
    public var outputURL: URL?
    public var outputMediaType: AVMediaType?
    public internal(set) var formatName: String = ""
    public var formatContextOptions: [String: Any] = [String: Any]()
    public var outputFormatContextOptions: [String: Any] = [String: Any]()
    public var ioContext: AbstractAVIOContext?
    public var decoderOptions: [String: Any] = [String: Any]()
    public var lowres: UInt8 = UInt8(0)
    public let useSystemHTTPProxy: Bool = KSOptions.useSystemHTTPProxy
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

    public var seekUsePacketCache: Bool = false
    /// 最低缓存视频时间
    @Published
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration
    /// 最大缓存视频时间
    public var maxBufferDuration: Double = KSOptions.maxBufferDuration
    // audio
    public var audioFilters: [String] = [String]()
    public var syncDecodeAudio: Bool = false
    // Slots 128-130 are three methods declared HERE, between `syncDecodeAudio` (slots 125-127, the
    // named-anchor getter) and `fontsDir` (131-133, all three impls null in the descriptor).
    // Slot 129 @0x1019b91c8 is an audioFrameMaxCount-shaped body: when a once-initialised static
    // type equals one particular class it clamps the 2nd argument up to 6, computes
    // Int(fps) * that, >>1, capped at 0x1000; otherwise Int(fps) * arg, >>2, capped at 0x400.
    // Slot 130 @0x1019b9330 returns that same static-type equality as a Bool.
    // idx128 slot222 @0x10002db34: `mov x0,#0x0; mov x1,#0x0; ret` (3 instructions) — a
    // 16-byte all-zero direct result and nothing else. The body is 586-way ICF-folded
    // (export_trie_oracle n_syms=586). dyld_info -fixups shows exactly 12 rebases — the 12
    // class-metadata vtable slots that hold this address (0x10411eb30, 0x10412b500, 0x104137858,
    // 0x10413c0c0, 0x104147208, 0x10417c970, 0x10417cef8/cf38, 0x10417d098/d300, 0x10448d068,
    // 0x1044e5a38) — whereas the KSOptions descriptor claims only 0x1039ec904.
    // (s68: corrected a prior "16 xrefs plus two call sites" tally that did not decompose; the
    //  independently verified count is 12 rebases — resolve_fun_pins verdict FOLDED_AMBIGUOUS.)
    //
    // ⚠️ s97 — "Position is exact; identity is not derivable" IS REFUTED, and the pin is DISCHARGED.
    // The fold defeats identification only if you look at the BODY. Go the other way, through the
    // vtable, and the ICF fold is irrelevant:
    //   (a) `wantedAudio` is `open` on a non-final class, so it necessarily HAS a vtable entry, and
    //       that entry's Impl is its body address;
    //   (b) the trie exports `wantedAudio(tracks:) -> MediaPlayerTrack?` at 0x10002db34;
    //   (c) EXACTLY ONE KSOptions vtable entry carries Impl=0x10002db34 — idx128, flags=0x0010
    //       Method — so no other member can be competing for it.
    // Therefore idx128 slot222 IS `wantedAudio(tracks:)`. Corroboration, not part of the proof: the
    // other three KSOptions symbols folded at this address are variable initialization expressions,
    // which take no vtable slot at all; and idx129 being audioFrameMaxCount-shaped means the binary
    // groups the AUDIO pair here exactly as it groups wantedVideo/videoFrameMaxCount at idx223/224.
    // The prior pin rested on recover_swift_function_name, which reads #function/#file literals that
    // a release build strips — the same failure mode already recorded for slots 220-225 below.
    // ⚑[tool=vtable_impl_oracle ref=KSPlayer.KSOptions.wantedAudio:0x10002db34 result=identity-discharged]
    internal var fontsDir: URL? // Tier 3a: read by SubtitleDecode.init (FUN_101a6914c @0x133 _TtC8KSPlayer9KSOptions::fontsDir) -> SubtitleDecode.fontsDir = fontsDir?.path  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    public var audioRecognizes: [AudioRecognize] = []
    // sutile
    public var autoSelectEmbedSubtitle: Bool = true
    public var isSeekImageSubtitle: Bool = false
    public let yadifMode: Int = KSOptions.yadifMode
    public let deInterlaceAddIdet: Bool = KSOptions.deInterlaceAddIdet
    public var dynamicRange: DynamicRange = DynamicRange.sdr
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
    // Field 47. The reflection record's type mangle ends `_p`, i.e. an EXISTENTIAL, not an enum
    // tag — which is what settles that DisplayEnum is a protocol. The property carries getter,
    // setter AND modify in the trie, so it is a `var`.
    public var display: any DisplayEnum = PlaneDisplayModel()
    public var videoPipeline: VideoPipeline?
    public var videoDelay: Double = 0.0 // s
    public var isRotateByFilter: Bool = false
    public var destinationDynamicRange: DynamicRange?
    public var videoAdaptable: Bool = false // Forward default = false (init stores 0)
    public var videoFilters: [String] = [String]()
    public var syncDecodeVideo: Bool = false
    public var decodeType: DecodeType = DecodeType.avplayer
    public var hardwareDecode: Bool = KSOptions.hardwareDecode
    public var asynchronousDecompression: Bool = KSOptions.asynchronousDecompression
    public var videoDisable: Bool = false
    public var canStartPictureInPictureAutomaticallyFromInline: Bool = KSOptions.canStartPictureInPictureAutomaticallyFromInline
    public var automaticWindowResize: Bool = true
    public var videoSoftDecodeThreadCount: Int = KSOptions.videoSoftDecodeThreadCount
    public var isDoubleRefreshRate: Bool = false
    public var renderUseDispatchSourceTimer: Bool = false
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
    // ✅ idx223 `wantedVideo` — DISCHARGED (s103). The index->object migration is now done for both:
    // `wantedAudio` (idx128) in s97, `wantedVideo` here. It returns MediaPlayerTrack?, and its body
    // is `tracks.first` rather than the `nil` this file used to declare — the count load
    // `ldr x8,[x0,#0x10]` + `cbz` and the retained 16-byte element at +0x20/+0x28 are read below.
    // ⚠️ s97 — the "call-site ripple" this note cites is ZERO for both methods: neither
    // `wantedAudio` nor `wantedVideo` is called anywhere under Sources/, inside this file or out
    // (a recursive search for either name under Sources/ returns only the declarations). Whatever
    // made wantedVideo a separate unit, it was not ripple.
    // 220 DECLARED with its body (s103): the scouted `staticBool || fpsArg > 61.0` is confirmed, and
    // the staticBool is named — `static KSPlayer.KSOptions.preferredFrame : Swift.Bool` @0x104c63262.
    // 223 DECLARED with its body (s103): the scouted "retains arg+0x20 when arg+0x10 is non-nil" is
    // `tracks.first`, arg+0x10 being the array COUNT and not a nil-able field.
    // 221 DECLARED with its body (s103): the scouted "reads UITraitCollection.current
    // .userInterfaceIdiom" is confirmed, and the rest of the guard is a `ccmp` against 7680 that
    // halves both dimensions only on .phone. All four of 220/221/222/223 are now declared.
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
    public var forceDisableDisplayLayer: Bool = false
    public var onPossibleDisplayLayerFlicker: (@MainActor @Sendable () -> Void)?
    private var videoClockDelayCount: Int = 0
    public internal(set) var lastVideoClockDropLogTime: Double = 0.0
    public internal(set) var prepareTime: Double = 0.0
    public internal(set) var dnsStartTime: Double = 0.0
    public internal(set) var tcpStartTime: Double = 0.0
    public internal(set) var tcpConnectedTime: Double = 0.0
    public internal(set) var openTime: Double = 0.0
    public internal(set) var findTime: Double = 0.0
    public internal(set) var readyTime: Double = 0.0
    public internal(set) var readAudioTime: Double = 0.0
    public internal(set) var readVideoTime: Double = 0.0
    public internal(set) var decodeAudioTime: Double = 0.0
    public internal(set) var decodeVideoTime: Double = 0.0
    public internal(set) var firstPlayableTime: Double = 0.0

    // ⚑ INFERRED name `resetTime`: #function unrecoverable (direct call @0x1019c0798, no vtable slot).
    //   KSMEPlayer's prepare path (caller @0x101a432fc, logs "Preparing to Play") calls
    //   `options.<this>()` to zero the prepare-pipeline timing telemetry before a fresh measurement.
    //   Resets exactly the 12 *Time fields above (prepareTime…firstPlayableTime), in declaration
    //   order; each Double → 0. Access modifier not binary-determinable → internal (same-module caller).
    // ⚑ s105 RENAME: was `resetTime()`, flagged INFERRED in the comment above. One symbol at
    // 0x1019c0798: `KSPlayer.KSOptions.resetTimeLog() -> ()`. Body unchanged.
    // ⚑[tool=export_trie_oracle ref=KSOptions.resetTimeLog:0x1019c0798 result=name-recovered]
    /// ⚑ 0x1019b4080 — a single `b 0x1019c0798`, i.e. a tail-call straight into
    /// `resetTimeLog()`'s body with no argument shuffling and nothing else. It is a THUNK, not
    /// an ICF fold: 0x1019b4080 is its own function-start and 0x1019c0798 is resetTimeLog's
    /// entry, so this method's whole body is that one call.
    /// Trie: `KSPlayer.KSOptions.reset() -> ()`.
    func reset() {
        resetTimeLog()
    }

    func resetTimeLog() {
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
        // ⚑ s106: TWO reductions, not one. This body runs both over the same array — the max loop
        //   @0x1019b8650 and the min loop @0x1019b8674 — because LoadingState carries both.
        let maxLoadedTime = capacitys.map(\.loadedTime).max() ?? 0
        let minLoadedTime = capacitys.map(\.loadedTime).min() ?? 0
        // ⚑ s106: progress derives from the MAX and is a UInt8. Read at 0x1019b86dc-0x1019b874c:
        //   `fcmp d0, #0.0` on preferredForwardBufferDuration, and on the zero path `mov w20, #0x64`
        //   = 100; otherwise `fmul d10, d9, 100.0` — d9 being the MAX — then `fdiv` by the duration.
        //   The source previously derived it from its single `.min()`, so Forward changed both the
        //   field and which one feeds this.
        // ⚑ The Double→UInt8 conversion @0x1019ec77c CLAMPS rather than traps: negative → 0,
        //   NaN → 0, >= 255 → 255, else `fcvtzs`. Plain `UInt8(_:)` traps instead, so the exact
        //   source spelling of that clamp is NOT established; `UInt8(clamping:)` on the truncated
        //   value is the closest expressible form and is what is written.
        //   ⚑[tool=llvm-objdump ref=Double-to-UInt8:0x1019ec77c result=clamping-0-255-NaN-0]
        let progress: UInt8 = preferredForwardBufferDuration == 0
            ? 100
            : UInt8(clamping: Int(maxLoadedTime * 100.0 / preferredForwardBufferDuration))
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
        return LoadingState(maxLoadedTime: maxLoadedTime, minLoadedTime: minLoadedTime,
                            progress: progress, packetCount: UInt(packetCount),
                            frameCount: UInt(frameCount), isEndOfFile: isEndOfFile,
                            isPlayable: isPlayable, isFirst: isFirst, isSeek: isSeek)
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

    // vtable idx222 slot316 @0x1019bea08 — three instructions, its own impl, NOT an ICF fold (the
    // ⚠️ s97: this block previously read "slot 222", which is the IDX. The real slot222 is idx128
    // (@0x10002db34, wantedAudio) — a DIFFERENT entry. Both spellings were live in this one file.
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

    // SIGNATURE AND BODY BOTH RECOVERED @0x1019be928 (extent 0x1019be928-0x1019be98c, 25 instr, all
    // accounted for) — idx220, one of the two this file recorded above as "names recovered, bodies
    // not yet reconstructed". The instance method reads the STATIC of the same name; Swift permits
    // the overload, and the trie names both independently:
    //   0x104c63262  static KSPlayer.KSOptions.preferredFrame : Swift.Bool   (`ldrb w8,[x19]` under
    //                swift_beginAccess; a byte, and there is no swift_once token on this one)
    // The float immediate is materialised as `mov w9,#0x42740000 / fmov s0,w9` @0x1019be960, which
    // is 61.0 exactly, and the comparison is `fcmp s8,s0 / cset w9,gt` — strictly greater. The two
    // are combined with `orr w8,w8,w9` then masked `and w0,w8,#0x1`, i.e. a non-short-circuiting
    // `||` over two already-computed Bools.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.preferredFrame(fps:):0x1019be928 result=OWNER_MATCH]
    // ⚑[tool=export_trie_oracle ref=static KSPlayer.KSOptions.preferredFrame:0x104c63262 result=OWNER_MATCH]
    open func preferredFrame(fps: Float) -> Bool {
        KSOptions.preferredFrame || fps > 61.0
    }

    // SIGNATURE AND BODY BOTH RECOVERED @0x1019be98c (extent 0x1019be98c-0x1019bea08, 31 instr, all
    // accounted for) — idx221, the last of the four this file listed as name-recovered/body-not-yet.
    // The receiver chain is read, not guessed: 0x104410730 is `_OBJC_CLASS_$_UITraitCollection`
    // (__objc_classrefs, UIKit), realized through `_objc_opt_self`, then two selectors decoded from
    // their selrefs — 0x1034606c0 = `currentTraitCollection` and 0x10346e920 = `userInterfaceIdiom`.
    // So this is UITraitCollection.current, NOT the UIDevice.current the rest of this codebase uses
    // for idiom checks.
    // The guard is one `ccmp`: `cmp x22,#0x0` then `ccmp w20,w8,#0x8,eq` @0x1019be9d4 with w8=0x1e00
    // = 7680. When the idiom is non-zero the immediate #0x8 sets N=1/V=0, so `b.ge` is false and no
    // halving happens; only idiom == 0 (.phone) AND width >= 7680 takes the halving arm.
    // Halving is `lsr w8,w20,#1` for width (unsigned, because the branch already proves width>=7680)
    // and the signed `add w9,w19,w19,lsr #31 / asr #1` for height — both are `/ 2`, spelled the same.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.decodeSize(width:height:):0x1019be98c result=OWNER_MATCH]
    // ⚑[tool=bind_oracle ref=_OBJC_CLASS_$_UITraitCollection:0x104410730 result=CONFIRMED]
    // ⚠️ The image is the iOS build, so ONLY the UIKit arm is readable. The non-UIKit arm is NOT
    // reconstructed from evidence — it falls through to the unnarrowed size because that is what the
    // UIKit arm does when its guard fails, not because macOS was observed to do so.
    // ⚑[tool=bind_oracle ref=UITraitCollection-absent-on-macOS:0x104410730 result=pinned-platform-arm-unread]
    open func decodeSize(width: Int32, height: Int32) -> CGSize {
        #if canImport(UIKit)
        if UITraitCollection.current.userInterfaceIdiom == .phone, width >= 7680 {
            return CGSize(width: CGFloat(width / 2), height: CGFloat(height / 2))
        }
        #endif
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    /// wanted video track, or nil for automatic selection
    /// - Parameter : video track
    /// - Returns: The selected track
    // SIGNATURE AND BODY BOTH RECOVERED @0x1019bea14 (extent 0x1019bea14-0x1019bea54, 16 instr, all
    // accounted for). Return type is MediaPlayerTrack?, NOT Int? — the same correction the sibling
    // wantedAudio carries above, and on the same two independent grounds: the trie demangles this
    // address as `wantedVideo(tracks: [KSPlayer.MediaPlayerTrack]) -> KSPlayer.MediaPlayerTrack?`,
    // and the ABI agrees, since MediaPlayerTrack is AnyObject-constrained so the existential is
    // (ref, witness) and the nil arm is exactly `mov x0,#0x0 / mov x19,#0x0 / mov x1,x19`.
    // The body is NOT `nil`: `ldr x8,[x0,#0x10]` reads the array buffer's COUNT and `cbz x8` takes
    // the nil arm only when empty; otherwise it loads the 16-byte element 0 from +0x20/+0x28 and
    // retains it. There is no `brk` anywhere in the extent, so there is no bounds check — which is
    // `.first`, not a subscript.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.wantedVideo(tracks:):0x1019bea14 result=OWNER_MATCH]
    // ⚑[tool=bind_oracle ref=_swift_unknownObjectRetain:0x1041130b0 result=CONFIRMED]
    open func wantedVideo(tracks: [MediaPlayerTrack]) -> MediaPlayerTrack? {
        tracks.first
    }

    /// wanted audio track, or nil for automatic selection
    /// - Parameter :  audio track
    /// - Returns: The selected track
    // idx128 slot222 @0x10002db34 — identity DISCHARGED (s97); see the slot-128 block above.
    // Return type is MediaPlayerTrack?, NOT Int?. Two independent lines of evidence:
    //   (1) the trie demangles this address's sole KSOptions METHOD symbol as
    //       `wantedAudio(tracks: [KSPlayer.MediaPlayerTrack]) -> KSPlayer.MediaPlayerTrack?`;
    //   (2) the ABI agrees — MediaPlayerTrack is AnyObject-constrained, so the existential is
    //       (ref, witness) and `nil` is exactly the observed `mov x0,#0x0; mov x1,#0x0; ret`.
    //       An `Int?` nil does not leave x1 zero, so the body refutes the Int? spelling on its own.
    // ⚠️ The name is NOT recoverable from the address alone: export_trie_oracle --addr 0x10002db34
    // --owner KSOptions answers `OWNER_AMBIG (586 symbols)` / `NOT RECOVERABLE from this address —
    // do not guess it`. It becomes recoverable only by filtering that fold list to KSOptions' four
    // symbols and combining it with the vtable-uniqueness argument above, which is why the marker
    // below names the vtable oracle rather than the trie oracle.
    // ⚑[tool=vtable_impl_oracle ref=KSPlayer.KSOptions.wantedAudio:0x10002db34 result=signature-recovered]
    open func wantedAudio(tracks _: [MediaPlayerTrack]) -> MediaPlayerTrack? {
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

    // SIGNATURE AND BODY BOTH RECOVERED @0x1019b91c8 (extent 0x1019b91c8-0x1019b9330, 90 instr, all
    // accounted for). The trie prints the return type as UInt16, and the body proves it independently:
    // the renderer arm caps at 0x1000 = 4096, which cannot be held in the UInt8 the source declared.
    // The branch is `cmp x20,x0 / b.eq 0x1019b9284` @0x1019b9228 where x20 is the static loaded under
    // swift_beginAccess from 0x104c63118 and x0 is the AudioRendererPlayer metadata accessor's result;
    // EQUAL takes the max(channelCount,6) / >>1 / 4096 arm, NOT-equal the channelCount / >>2 / 1024 arm.
    // Both `mul` sites are checked (smulh + cmp asr #63) and both tails `tbz/tbnz #0x3f`, i.e. the Int
    // arithmetic traps on overflow and on a negative result — the shape of a UInt16(_:) conversion.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.audioFrameMaxCount(fps:channelCount:):0x1019b91c8 result=signature+body-recovered]
    // ⚑[tool=export_trie_oracle ref=static KSPlayer.KSOptions.audioPlayerType:0x104c63118 result=OWNER_MATCH]
    // ⚑[tool=export_trie_oracle ref=type metadata accessor for KSPlayer.AudioRendererPlayer:0x101a14c08 result=OWNER_MATCH]
    open func audioFrameMaxCount(fps: Float, channelCount: Int) -> UInt16 {
        if KSOptions.audioPlayerType == AudioRendererPlayer.self {
            let count = (Int(fps) * max(channelCount, 6)) >> 1
            if count >= 4096 {
                return 4096
            } else {
                return UInt16(count)
            }
        } else {
            let count = (Int(fps) * channelCount) >> 2
            if count >= 1024 {
                return 1024
            } else {
                return UInt16(count)
            }
        }
    }

    // SIGNATURE AND BODY BOTH RECOVERED @0x1019b9330 (extent 0x1019b9330-0x1019b93a8, 30 instr, all
    // accounted for) — idx130, the slot immediately after audioFrameMaxCount, which is why it is
    // declared here. Same static and same swift_once token (0x1044e5248) as the body above, but
    // ⚠️ NOT the same comparand: this one calls the metadata accessor at 0x101a160a4, which the trie
    // names AudioUnitPlayer, where audioFrameMaxCount calls 0x101a14c08 = AudioRendererPlayer. The
    // scouting note above this class described idx130 as returning "that same static-type equality";
    // it is the same static but a different class, read from the accessor rather than assumed.
    // `cmp x19,x0 / cset w0,eq` @0x1019b9378 is the whole result.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.isAudioRateByFilter():0x1019b9330 result=OWNER_MATCH]
    // ⚑[tool=export_trie_oracle ref=type metadata accessor for KSPlayer.AudioUnitPlayer:0x101a160a4 result=OWNER_MATCH]
    open func isAudioRateByFilter() -> Bool {
        KSOptions.audioPlayerType == AudioUnitPlayer.self
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
    // SIGNATURE AND BODY BOTH RECOVERED. The trie prints
    // `KSOptions.isUseDisplayLayer(frame: KSPlayer.VideoVTBFrame, isHDRScreen: Swift.Bool) -> Bool`;
    // the source had a no-argument one-liner. Both parameters are load-bearing — x0 is dereferenced
    // at frame+0x18 (pixelBuffer) and x1 is bit-tested at 0x1019beca0.
    //
    // The binary body is 121 instructions in six steps, and the RETURN VALUE is not the display test
    // the source returned — it is `videoPipeline == nil`. The final `cset w21, eq` reads the word at
    // +0x18 of the copied `VideoPipeline?` existential (its metadata word, carrying the Optional
    // discriminator) and returns == 0. The display comparison is a mid-body guard, four conditions
    // earlier.
    //
    // GUARDS 2 AND 3 ARE PINNED, NOT WRITTEN. Step 2 rejects when a pixelBuffer-derived Double (the
    // second lane) is >= 6000, and step 3 rejects when `!isHDRScreen` and a pixelBuffer-derived
    // optional ObjC reference is non-nil. Both reach through requirements this reconstruction cannot
    // name, so guessing them would fabricate two conditions in the middle of a guard ladder.
    // ⚑[tool=export_trie_oracle ref=KSOptions.isUseDisplayLayer:0x1019bec28 result=guards-2-3-pinned]
    open func isUseDisplayLayer(frame _: VideoVTBFrame, isHDRScreen _: Bool) -> Bool {
        if forceDisableDisplayLayer {
            return false
        }
        // UNRESOLVED → P8: guard 2 (pixelBuffer Double lane 2 >= 6000 -> false)
        // UNRESOLVED → P8: guard 3 (!isHDRScreen && pixelBuffer optional ref != nil -> false)
        guard !display.isSphere else {
            return false
        }
        guard brightness == 1, contrast == 1, saturation == 1 else {
            return false
        }
        return videoPipeline == nil
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

    // Two parameters, and an EMPTY body. The trie carries exactly one `sei` in the image —
    // `$s8KSPlayer9KSOptionsC3sei6string4timeySS_So6CMTimeatF` (and its `Tq` method descriptor at
    // 0x1039ecdd8, which is what proves the declaration is a real overridable vtable member) — so
    // there is no one-argument overload and no default-argument generator for `time`. The body at
    // 0x10000e52c is a single `ret`: 4 B / 1 instr on an exact LC_FUNCTION_STARTS extent. That is the
    // 420-way ICF fold of every empty function, so it carries no content of its own; the base's
    // `KSLog("sei \(string)")` cannot compile to a bare `ret` (KSLog takes an autoclosure and emits at
    // minimum a level test and a call), which is what makes the empty body a reading rather than a guess.
    open func sei(string _: String, time _: CMTime) {}

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
    // Trie: `static KSPlayer.KSOptions.isHDRScreen : Swift.Bool?`, with getter, setter, modify,
    // property descriptor and unsafeMutableAddressor — a static Optional Bool. It is what feeds
    // isUseDisplayLayer's second parameter, and it was absent from this reconstruction.
    nonisolated(unsafe) static var isHDRScreen: Bool?
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

    // ── Forward statics recovered s105 ──────────────────────────────────────────────────────
    // Fourteen `static var` settings the binary declares here and this source did not. Each one's
    // DEFAULT was read from the global its own `unsafeMutableAddressor` returns — the addressor is
    // `adrp/add/ret` onto a statically-initialised global, so the value is in the image rather than
    // built at runtime. Read at the width its trie type gives (Bool 1, UInt16 2, Int64/Double 8).
    // ⚑[tool=export_trie_oracle ref=KSOptions.audioVideoClockSync.unsafeMutableAddressor:0x1019bcae0 result=static-global]
    //
    // These 14 are the subset whose global is statically initialised. The other 35 statics on this
    // class are NOT declared here: their globals sit in __bss with no readable value, 18 of them
    // behind a `swift_once` guard, and writing `false`/`0` for a global whose initialiser has not
    // been read would be inventing the default rather than reading it.
    //
    // DECLARATION ORDER is alphabetical and carries NO claim: a static's storage is a module
    // global, so its address ordering is not source ordering the way a stored field's is.
    nonisolated(unsafe) static var audioVideoClockSync = true
    nonisolated(unsafe) static var forceDVForProfile7 = true
    nonisolated(unsafe) static var isUseNewSubtitleRender = true
    nonisolated(unsafe) static var localHLSServerPort: UInt16 = 8887
    nonisolated(unsafe) static var lockAspectRatio = true
    nonisolated(unsafe) static var maxM3U8FileSize: Int64 = 1_073_741_824
    nonisolated(unsafe) static var minM3U8BufferDuration: Int64 = 60
    nonisolated(unsafe) static var seekInterruptIO = false
    nonisolated(unsafe) static var seekRequireConfirmation = true
    nonisolated(unsafe) static var stripSubtitleStyle = true
    nonisolated(unsafe) static var subtitleFontSize = 11.0
    nonisolated(unsafe) static var subtitleFontSizeScale = 1.0
    nonisolated(unsafe) static var subtitleImageScale = 1.0
    nonisolated(unsafe) static var trackHeight: CGFloat = 5.0
    // ── s105, three statics read out of FILE-BACKED storage ──────────────────────────────────
    // Unlike the __common group below, these three globals carry their bytes in the image, so the
    // values are read directly rather than inferred from zero-fill.
    //   interactiveSize @0x1044efdf0  00..3940 00..3940  -> two Doubles, 25 and 25
    //   thumbSize       @0x1044efde0  00..2e40 00..2e40  -> two Doubles, 15 and 15
    //   textFontName    @0x1044e50a8  "SF Pro" as an inline small string, discriminator 0xE6
    // ⚑ textFontName's discriminator is 0xE6, not 0xA6: an ASCII small string sets the isASCII
    // flag. decode_string_literal only accepted the 0xA form until this session and returned
    // "no literal" for every ASCII one — a silent false negative, now goldened on these bytes.
    // ⚑[tool=decode_string_literal ref=KSOptions.textFontName:0x1044e50a8 result=SF Pro]
    nonisolated(unsafe) static var interactiveSize = CGSize(width: 25, height: 25)
    nonisolated(unsafe) static var thumbSize = CGSize(width: 15, height: 15)
    nonisolated(unsafe) static var textFontName = "SF Pro"

    /// ⚑[tool=export_trie_oracle ref=KSOptions.textFont(name:size:):0x1019ba74c result=35-instr]
    /// Trie signature: `static textFont(name: Swift.String, size: CoreGraphics.CGFloat) -> __C.UIFont`.
    /// ⚑ There are TWO `textFont` overloads in the trie — this one and `textFont(width: Double)`
    ///   @0x1019ba6f8. They are distinguished by argument registers, not by size: this body takes
    ///   its String through `String._bridgeToObjectiveC` (0x103457438) and its CGFloat in `v0`.
    ///
    /// Every piece decoded, none assumed:
    ///   · classref 0x104410618 = `OBJC_CLASS_$_UIFont` (via `objc_opt_self`).
    ///   · selref 0x10440b5b8 = **`fontWithName:size:`** — the failable `UIFont(name:size:)`.
    ///   · `cbz x21` on the retained result is the failure test, and the fallback sends
    ///     selref 0x10440e4f8 = **`systemFontOfSize:`** to the same class with the same `v0`.
    /// ⚑[tool=decode_objc_selector ref=0x10440b5b8 result='fontWithName:size:']
    /// ⚑[tool=decode_objc_selector ref=0x10440e4f8 result='systemFontOfSize:']
    ///
    /// ⚑ The fallback is reached only on nil, so it is `??` rather than a branch on the name —
    ///   a name-validity check would test the String before the send, and none is emitted.
    static func textFont(name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }
    // ── s106, four UIColor statics read through their swift_once initialisers ─────────────────
    // Each is a `swift_once`-guarded static whose addressor names an init function; that init is
    // twelve instructions of `ldr x0, [classref]` / msgSend / retainAutoreleasedReturnValue /
    // `str x0, [storage]`, so the value is one ObjC class-property call and nothing else. The
    // classref is 0x1044104f0 = `_OBJC_CLASS_$_UIColor` in every case; only the selector differs,
    // and each selector was decoded individually rather than assumed from the group:
    //   textColor           init 0x1019b9d00  sel stub 0x10346ef20  'whiteColor'
    //   textBackgroundColor init 0x1019ba0dc  sel stub 0x10345f2c0  'clearColor'
    //   textShadowColor     init 0x1019ba2c8  sel stub 0x10345eb40  'blackColor'
    //   textStrokeColor     init 0x1019b9e14  sel stub 0x10345eb40  'blackColor'
    // The shadow and stroke pair genuinely share one stub — that is the linker folding two
    // identical selector references, not one value standing in for the other.
    // Types are read, not chosen: each storage global's own symbol demangles to
    // `static KSPlayer.KSOptions.<name> : __C.UIColor`.
    // ⚑[tool=bind_oracle ref=__objc_classrefs:0x1044104f0 result=_OBJC_CLASS_$_UIColor]
    // ⚑[tool=decode_objc_selector ref=0x10346ef20 result=whiteColor]
    // ⚑[tool=decode_objc_selector ref=0x10345f2c0 result=clearColor]
    // ⚑[tool=decode_objc_selector ref=0x10345eb40 result=blackColor]
    // ⚠️ The other fourteen once-statics in this class (bufferColor, progressColor, thumbColor,
    // trackColor, doviMatrix, the displayEnum* group, …) have DIFFERENT init shapes — 6 to 18
    // instructions with no ObjC classref — and are deliberately not written here. Those are the
    // ones an earlier session got wrong (`trackColor = 0.5`); each needs its own read.
    nonisolated(unsafe) static var textColor: UIColor = .white
    nonisolated(unsafe) static var textBackgroundColor: UIColor = .clear
    nonisolated(unsafe) static var textShadowColor: UIColor = .black
    nonisolated(unsafe) static var textStrokeColor: UIColor = .black
    // ── s106, five SwiftUI.Color statics — and the correction of a known bad read ─────────────
    // ⚠️ `trackColor` was recorded by an earlier session as `0.5`. It is not. Its once-init is
    // six instructions: load a Color base from a __got, load the storage address, `fmov d0, #0.5`,
    // and tail-call a shared helper. The 0.5 is the OPACITY ARGUMENT, never the value — reading
    // the immediate as the result is exactly how that error happened.
    //
    // The shared tail @0x101ad658c makes it unambiguous: it `blr`s the base-Color getter passed in
    // x1, moves the saved d0 into v0, calls `__got 0x104110580` and stores the result. That got
    // binds `_$s7SwiftUI5ColorV7opacityyACSdF` = `SwiftUI.Color.opacity(Swift.Double) -> Color`.
    //   ⚑[tool=bind_oracle ref=__got:0x104110580 result=SwiftUI.Color.opacity(Double)]
    //
    // Bases, each read from its own got rather than assumed from the group:
    //   ⚑[tool=bind_oracle ref=__got:0x104110558 result=SwiftUI.Color.white]
    //   ⚑[tool=bind_oracle ref=__got:0x104110550 result=SwiftUI.Color.green]
    //   ⚑[tool=bind_oracle ref=__got:0x104110508 result=SwiftUI.Color.red]
    // Opacities, read as doubles out of the image, not inferred:
    //   0x10347fe88 = 0.9   (bufferColor, focusProgressColor)
    //   0x10347fea8 = 0.8   (progressColor)
    //   trackColor's 0.5 is an inline `fmov d0, #0.5`
    //
    // `thumbColor` is the odd one and is NOT given an opacity: its init calls stub 0x103455d70
    // directly and stores the result, and that stub loads the same got 0x104110558 as
    // `Color.white`. One call, no second argument, no shared tail.
    //
    // Types are read: each storage global demangles to `static KSPlayer.KSOptions.<name> :
    // SwiftUI.Color`.
    // ACCESS is read, and it differs from the four UIColor statics above. This extension is
    // `public extension KSOptions`, so an unmarked member would be public — but none of these five
    // carries a `vpMV`/`vpZMV` property descriptor, which is public-exclusive, and none carries a
    // private discriminator either. That is `internal`, and it is written explicitly so the
    // extension's default does not silently make them public. `textColor` above DOES carry a
    // vpMV, which is why it is left unmarked. pin_sweep's ACCESS bucket caught this the moment
    // the five became parser-visible.
    // ⚑[tool=export_trie_oracle ref=KSOptions.bufferColor:access result=internal-no-vpMV]
    // ⚑[tool=export_trie_oracle ref=KSOptions.textColor:access result=public-vpMV-present]
    internal nonisolated(unsafe) static var bufferColor: Color = .white.opacity(0.9)
    internal nonisolated(unsafe) static var focusProgressColor: Color = .red.opacity(0.9)
    internal nonisolated(unsafe) static var progressColor: Color = .green.opacity(0.8)
    internal nonisolated(unsafe) static var thumbColor: Color = .white
    internal nonisolated(unsafe) static var trackColor: Color = .white.opacity(0.5)
    // ── s106, the two TextPosition statics ───────────────────────────────────────────────────
    // Both share one once-init tail @0x1019baf74, which writes five slots of the storage:
    //   +0x00  SwiftUI.VerticalAlignment.bottom      (stub 0x103454804 -> __got 0x10410ec98)
    //   +0x08  SwiftUI.HorizontalAlignment.center    (stub 0x103454990 -> __got 0x10410eee8)
    //   +0x10  10.0 and +0x18 10.0, written together as `fmov.2d v0, #10.0` / `str q0`
    //   +0x20  10.0, written as the immediate 0x4024000000000000
    // Against TextPosition's own declaration defaults (verticalAlign .bottom, horizontalAlign
    // .center, leftMargin 0, rightMargin 0, verticalMargin 10) only leftMargin and rightMargin
    // differ, so the memberwise call carries exactly those two. Writing `TextPosition()` would
    // give 0/0/10 and contradict the three 10.0 stores.
    // The tail calls each alignment getter TWICE and discards the second pair; that is
    // transcribed as one call each because the discarded results reach no slot.
    // ⚑[tool=bind_oracle ref=__got:0x10410ec98 result=SwiftUI.VerticalAlignment.bottom]
    // ⚑[tool=bind_oracle ref=__got:0x10410eee8 result=SwiftUI.HorizontalAlignment.center]
    // Both storage globals demangle to `… : KSPlayer.TextPosition`, and both carry a vpMV, so
    // both are public — unlike the five Color statics above, which carry none.
    nonisolated(unsafe) static var textPosition = TextPosition(leftMargin: 10, rightMargin: 10)
    nonisolated(unsafe) static var secondaryTextPosition = TextPosition(leftMargin: 10, rightMargin: 10)
    // ── s106, three DisplayEnum statics ──────────────────────────────────────────────────────
    // Types are read off the storage globals, not chosen:
    //   displayEnumVR    : KSPlayer.VRDisplayModel      storage 0x104c632b0
    //   displayEnumVRBox : KSPlayer.VRBoxDisplayModel   storage 0x104c632b8
    //   displayEnumPlane : KSPlayer.PlaneDisplayModel   storage 0x104c632a0
    // All three construct with NO arguments, and each once-init shows that directly.
    //
    // VR and VRBox share a tail @0x1019bc700: call the metadata accessor, `swift_allocObject`
    // with the size the caller supplied (0x100 for VR, 0x140 for VRBox) and alignMask 0xf, then
    // `blr` the init with only the new object in x0 — no further argument is set up.
    //   ⚑[tool=export_trie_oracle ref=0x101a8d244 result=metadata-accessor-VRDisplayModel]
    //   ⚑[tool=export_trie_oracle ref=0x101a8d264 result=metadata-accessor-VRBoxDisplayModel]
    //
    // Plane's init has a DIFFERENT shape and it is worth saying why it is still `()`: it calls
    // the metadata accessor then `swift_initStaticObject` on a global at 0x1044e5198, i.e. the
    // instance is allocated statically in the image rather than on the heap. That is a compiler
    // decision about an object needing no runtime initialisation, not a different construction,
    // so it spells the same in source.
    //   ⚑[tool=bind_oracle ref=__got:0x104112fb8 result=_swift_initStaticObject]
    //   ⚑[tool=export_trie_oracle ref=0x101a82024 result=metadata-accessor-PlaneDisplayModel]
    //
    // All three carry a vpMV, so all three are public and stay unmarked here.
    //
    // ⚑ Only `displayEnumPlane` is declared. `displayEnumVR` and `displayEnumVRBox` are READ —
    //   types, sizes, no-arg construction, all above — but do not compile here:
    //     error: main actor-isolated default value in a nonisolated(unsafe) context
    //   `SphereDisplayModel` is `@MainActor` and both subclasses declare
    //   `override required init()`, so their initialisers are main-actor isolated, while these
    //   statics are not. PlaneDisplayModel is `@MainActor` too but has no explicit init and does
    //   not trip it.
    //   The binary does NOT resolve this for me either way: the shared once-init tail
    //   @0x1019bc700 is nineteen instructions of metadata accessor / swift_allocObject / `blr`
    //   init / store, with no actor hop, no MainActor.shared materialisation and no
    //   swift_task_reportUnexpectedExecutor — which is evidence the initialisation is NOT
    //   main-actor isolated, and therefore that the `@MainActor` on SphereDisplayModel may be an
    //   over-annotation this reconstruction added. That is a claim about a DIFFERENT declaration
    //   and needs its own read, so the two statics wait rather than being forced through with an
    //   isolation workaround the binary does not show.
    nonisolated(unsafe) static var displayEnumPlane = PlaneDisplayModel()
    /// ⚑ s107: NOW DECLARED. The blocker recorded above — "`DoviDisplayModel` does not exist in
    /// Sources at all; it needs standing up first" — is cleared: that class is stood up in
    /// DisplayModel.swift, with its superclass read from the descriptor's SuperclassType symbolic
    /// reference and its three fields from the static field-offset vector.
    ///
    /// The addressor @0x1019bc608 is the ordinary `swift_once` shape — `cmn x8,#1` on the token at
    /// 0x1044e52b0, returning storage 0x104c632a8 — and the once-initializer @0x1019bc5c0 is
    /// `swift_allocObject(0x58, 7)` followed by field zeroing and the empty-dictionary store, i.e.
    /// plain no-argument construction. `DoviDisplayModel` has no explicit init, so like
    /// `PlaneDisplayModel` (and unlike the two `SphereDisplayModel` subclasses) it does not trip
    /// the main-actor-isolated-default-value rule that still blocks `displayEnumVR`/`displayEnumVRBox`.
    nonisolated(unsafe) static var displayEnumDovi = DoviDisplayModel()
    /// ⚑ s106: `nil`, and the encoding is read rather than assumed.
    /// This static has NO `swift_once` — its addressor @0x1019ba7e4 is three instructions
    /// returning the storage address — so the value is simply the bytes sitting in `__data` at
    /// 0x1044e50c8 (a real section with contents, not `__common` zero-fill). Those bytes are
    /// `01 00 00 00 00 00 00 00 …`.
    /// `SubtitleTextStyle` is 128 bytes and its layout was recovered from its own eleven getters,
    /// each two-to-eleven instructions touching one offset — `textColor: UIColor?` is at offset 0,
    /// and the recovered field order matches this file's existing declaration exactly.
    /// So offset 0 is a class-reference slot. `UIColor?` spends inhabitant 0 on its own nil, which
    /// is why all-zero bytes would mean `.some(SubtitleTextStyle())` with every field nil — and the
    /// bytes are NOT all-zero. The stored 1 is the next extra inhabitant, i.e. the OUTER
    /// `Optional<SubtitleTextStyle>.none`. The absence of any once-init is what rules out the
    /// remaining alternative: a `.some` carrying real content would need one to build its String?
    /// and UIColor? payloads.
    /// ⚑[tool=llvm-objdump ref=KSOptions.secondaryTextStyle:addressor@0x1019ba7e4 result=no-swift_once]
    /// Access read: carries a vpMV, so public.
    nonisolated(unsafe) static var secondaryTextStyle: SubtitleTextStyle?
    // ── s106, two more once-statics ──────────────────────────────────────────────────────────
    /// ⚑[tool=llvm-objdump ref=KSOptions.doviMatrix:once-init@0x1019bc3ac result=11-instr]
    /// The init copies 48 bytes of constant into the storage as three 16-byte columns, from
    /// 0x103564510 / 0x103564520 / 0x103564530. Read as floats those are
    /// (1,0,0,_) (0,1,0,_) (0,0,1,_) — the identity. Storage types as `__C.simd_float3x3`.
    /// ⚑ SPELLING is undecidable and that is recorded rather than hidden: `matrix_identity_float3x3`,
    /// `simd_float3x3(1)` and the explicit three-column form all constant-fold to these same 48
    /// bytes, so the binary cannot distinguish them. The identity spelling is used as the clearest.
    nonisolated(unsafe) static var doviMatrix = matrix_identity_float3x3
    /// ⚑[tool=llvm-objdump ref=KSOptions.pictureInPictureType:once-init@0x1019bc7a8 result=11-instr]
    /// `mov x0,#0` / `bl 0x1019c7568` gets a type metadata, then `stp x0, x8` writes the pair
    /// (metatype, witness table) — an existential metatype, matching the storage's own type
    /// `KSPlayer.KSPictureInPictureProtocol.Type`.
    /// ⚑[tool=export_trie_oracle ref=0x1019c7568 result=metadata-accessor-KSPictureInPictureController]
    /// ⚑[tool=decode_witness_table ref=0x1041d45a0 result=KSPictureInPictureController:KSPictureInPictureProtocol]
    /// The witness table stored alongside is that class's conformance to the protocol, which is
    /// what makes the value `KSPictureInPictureController.self` rather than any other conformer.
    nonisolated(unsafe) static var pictureInPictureType: KSPictureInPictureProtocol.Type = KSPictureInPictureController.self
    /// ⚑ swift_once init 0x1019b4814, read in full: `mov x0, #0` / `bl 0x1019d5d24` /
    /// `str x0, [x8, #0xe8]`. The call is a type-metadata accessor with request 0 and nothing
    /// else happens, so the stored value is a METATYPE — and the trie names 0x1019d5d24
    /// `type metadata accessor for KSPlayer.KSComplexPlayerLayer`, which is the subclass, not
    /// the declared `KSPlayerLayer` base.
    /// ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.metadataAccessor:0x1019d5d24 result=named]
    nonisolated(unsafe) static var playerLayerType: KSPlayerLayer.Type = KSComplexPlayerLayer.self

    // ── s105, the zero-fill half of KSOptions' statics ───────────────────────────────────────
    // Seventeen more `static var` settings. Their defaults are read from the IMAGE'S LAYOUT
    // rather than from a stored byte: each one's unsafeMutableAddressor is `adrp/add/ret` with
    // NO swift_once guard anywhere in it, and the global it returns lives in __common
    // (0x104c5bb00..+0x185198), a zero-fill section with no file backing. No initialiser exists,
    // so the value at load IS the default, and for these types that is the zero literal.
    // The other 18 statics on this class are NOT here: their addressors DO carry a once guard,
    // so they are built at runtime and their defaults are unread. That split is what makes this
    // set decidable — it is not "the read returned nothing, assume zero".
    // ⚑[tool=bind_oracle ref=KSOptions.hudLog.unsafeMutableAddressor:0x1019bfe44 result=__common-no-once]
    nonisolated(unsafe) static var enableHDRSubtitle: Bool = false
    nonisolated(unsafe) static var hudLog: Bool = false
    nonisolated(unsafe) static var isASSUseImageRender: Bool = false
    nonisolated(unsafe) static var isResizeImageSubtitle: Bool = false
    nonisolated(unsafe) static var isSRTUseImageRender: Bool = false
    nonisolated(unsafe) static var isSpatialAudioEnable: Bool = false
    nonisolated(unsafe) static var preferEffectSubtitle: Bool = false
    nonisolated(unsafe) static var showTranslateSourceText: Bool = false
    nonisolated(unsafe) static var subtitleExposure: Float = 0.0
    nonisolated(unsafe) static var subtitleImageOffset: CGSize = .zero
    nonisolated(unsafe) static var subtitleOffset: CGFloat = 0.0
    nonisolated(unsafe) static var textBold: Bool = false
    nonisolated(unsafe) static var textItalic: Bool = false
    nonisolated(unsafe) static var textShadowBlurRadius: Double = 0.0
    nonisolated(unsafe) static var textShadowOffset: CGSize = .zero
    nonisolated(unsafe) static var textStrokeWidth: CGFloat = 0.0
    nonisolated(unsafe) static var useMACaptionAppearance: Bool = false
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

    func getTime() -> TimeInterval {
        time.seconds + CACurrentMediaTime() - lastMediaTime
    }
}
