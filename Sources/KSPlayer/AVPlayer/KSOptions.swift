//
//  KSOptions.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
// ⚑ s109: required by `process(url:interrupt:)` / `resolveIO(for:interrupt:)` below, whose
// `AVIOInterruptCB` parameter is read from the binary. PlayerDefines.swift in this same module
// already imports FFmpegKit for that very type. It must sit OUTSIDE the tvOS/xrOS conditional.
import FFmpegKit
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

    open func playerLayerDeinit() {
        #if os(tvOS) || os(xrOS)
        runOnMainThread {
            UIApplication.shared.windows.first?.avDisplayManager.preferredDisplayCriteria = nil
        }
        #endif
    }

    private func udpateAdjustBuffer() { fatalError("L7: KSOptions.udpateAdjustBuffer — Forward body unread") }
    public var avOptions: [String: Any] = [String: Any]()
    public var isLive: Bool?
    public var startPlayTime: TimeInterval = 0
    public var startPlayTimePercentage: Double = 0.0
    /// 最低缓存视频时间
    // Trie: `static KSPlayer.KSOptions.isHDRScreen : Swift.Bool?`, with getter, setter, modify,
    // property descriptor and unsafeMutableAddressor — a static Optional Bool. It is what feeds
    // isUseDisplayLayer's second parameter, and it was absent from this reconstruction.
    public nonisolated(unsafe) static var isHDRScreen: Bool?
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true // 默认支持来自系统控制中心的控制
    public nonisolated(unsafe) static var playerTypes: [MediaPlayerProtocol.Type] = [KSAVPlayer.self, KSMEPlayer.self]
    public nonisolated(unsafe) static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self
    public nonisolated(unsafe) static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    /// ⚑ swift_once init 0x1019b4814, read in full: `mov x0, #0` / `bl 0x1019d5d24` /
    /// `str x0, [x8, #0xe8]`. The call is a type-metadata accessor with request 0 and nothing
    /// else happens, so the stored value is a METATYPE — and the trie names 0x1019d5d24
    /// `type metadata accessor for KSPlayer.KSComplexPlayerLayer`, which is the subclass, not
    /// the declared `KSPlayerLayer` base.
    /// ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.metadataAccessor:0x1019d5d24 result=named]
    public nonisolated(unsafe) static var playerLayerType: KSPlayerLayer.Type = KSComplexPlayerLayer.self
    /// 是否开启秒开
    public nonisolated(unsafe) static var isSecondOpen = false
    /// Applies to short videos only
    public nonisolated(unsafe) static var isLoopPlay = false
    /// 是否自动播放，默认true
    public nonisolated(unsafe) static var isAutoPlay = true
    public var isAutoPlay: Bool = KSOptions.isAutoPlay
    public var enterForgeResumePlay: Bool = false
    public var isDLNARunning: Bool = false
    public var disableVideoFrameRateMatching: Bool = false
    /// seek完是否自动播放
    public nonisolated(unsafe) static var isSeekedAutoPlay = true
    /// 是否开启秒开
    public var isSecondOpen: Bool = KSOptions.isSecondOpen
    public var playbackTimeInterval: Double = 0.04
    // Forward vtable slot 43 is a get-only getter between playbackTimeInterval and playerTypes; the
    // trie names it at the shared dead stub 0x10198eb18 (fold 376) as the INSTANCE getter (no `Z`),
    // with no setter/modify and no property descriptor. The member existed; its slot is dead and
    // its body is unrecoverable. Distinct from the static twin above.
    // ⚑[tool=vtable_surface ref=KSOptions#43 result=G-dead-unnamed]
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer9KSOptionsC15firstPlayerTypeAA05MediaD8Protocol_pXpvg:0x10198eb18 result=instance-getter]
    var firstPlayerType: MediaPlayerProtocol.Type { fatalError("L7: KSOptions.firstPlayerType — Forward slot dead, body unreadable") }
    // playerTypes default reads the static KSOptions.playerTypes (not an inline literal).
    // ⚑[tool=decompile_function ref=FUN_1019b4334:0x1019b4334 result=static [KSAVPlayer.self,KSMEPlayer.self] — element class-descriptor names confirmed @0x1039ec148/@0x1039ef750]
    public var playerTypes: [MediaPlayerProtocol.Type] = KSOptions.playerTypes
    public var mixAudio: Bool = false
    public var canBackgroundPlay: Bool = true
    public var contentMode = UIViewContentMode.scaleAspectFit  // macOS: KSPlayer.ContentMode (== binary); iOS/tvOS: UIView.ContentMode
    /// Applies to short videos only
    public var isLoopPlay: Bool = KSOptions.isLoopPlay

    open func adaptable(state: VideoAdaptationState) -> (Int64, Int64)? {
        guard let last = state.bitRateStates.last, CACurrentMediaTime() - last.time > maxBufferDuration / 2, let index = state.bitRates.firstIndex(of: last.bitRate) else {
            return nil
        }
        let limit = Int(Double(state.fps) * maxBufferDuration / 2)
        let isUp = limit < 0 || state.loadedCount > UInt(limit)
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
    /// 开启精确seek
    public nonisolated(unsafe) static var isAccurateSeek = false
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
    // ⚑ s109: qualified because this file now imports FFmpegKit (for `AVIOInterruptCB`, below),
    // which introduces a second `AVMediaType`. The AVFoundation one is what this property has
    // always meant — the qualification changes nothing but the lookup.
    public var outputMediaType: AVFoundation.AVMediaType?
    // recordDir @0x1019b598c: `objc_opt_self(NSFileManager)` → `defaultManager` →
    // `URLsForDirectory:inDomains:` with w2=9 and w3=1. NSSearchPathDirectory is 1-based
    // (NSApplicationDirectory = 1), so 9 is NSDocumentDirectory and 1 is NSUserDomainMask. The
    // NSArray is bridged with `Array._unconditionallyBridgeFromObjectiveC<URL>`, then
    // `ldr x8,[x22,#0x10]` reads the Swift array's count and `cbz` splits the body in two:
    //   · count == 0 → `storeEnumTagSinglePayload(dest, 1, 1)` — the same `.none` encoding as above
    //   · otherwise → `initializeWithCopy` of element 0 (the `x9 = x8+0x20 / bic` pair rounds the
    //     32-byte array header up to the element alignment), then the string built inline as
    //     `mov x0,#0x6572 / movk 0x6f63,lsl#16 / movk 0x6472,lsl#32` with x1 = 0xE6… (count 6) —
    //     "record" — passed to `URL.appendingPathComponent`, then
    //     `storeEnumTagSinglePayload(dest, 0, 1)` = `.some`.
    // Nil exactly when the array is empty is `.first?`.
    // ⚑[tool=decode_objc_selector ref=0x10440a408 result=URLsForDirectory-inDomains]
    // ⚑[tool=bind_oracle ref=__got:0x104109a70 result=Foundation.URL.appendingPathComponent]
    public nonisolated(unsafe) static var recordDir: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("record")
    public internal(set) var formatName: String = ""
    public var formatContextOptions: [String: Any] = [String: Any]()
    public var outputFormatContextOptions: [String: Any] = [String: Any]()
    public var ioContext: AbstractAVIOContext?

    /// resolveIO @0x1019b5dc0, 63 instr. `public` from the method descriptor at 0x1039ec7c0.
    ///
    /// The dispatch is arithmetic: the call is at metadata `+0x5b8` and KSOptions' VTableOffset is
    /// 94 words (0x2f0), so the slot is (0x5b8-0x2f0)/8 = **89** — a Method whose Impl is the
    /// nil-returning fold above, i.e. `process(url:interrupt:)`.
    ///
    /// `cbz` on its result splits the two arms, and the arms are told apart by the tag written
    /// through the outlined enum-store 0x10345d048: **w2 = 0 on the nil arm, w2 = 1 on the other**.
    /// `Either` is `case left(Left), right(Right)`, so 0 is `.left` and 1 is `.right` — the same
    /// tag convention this reconstruction already relies on for `SubtitlePart.render`.
    ///
    /// The non-nil arm also STORES the result: offset global 0x104c63328 is
    /// `KSOptions.ioContext : AbstractAVIOContext?` (named by its vpWvd), written under a MODIFY
    /// access (`swift_beginAccess` flags 1) with the old value released after the new one is
    /// retained. The nil arm copies the `url` parameter into the indirect return through the
    /// value witness instead.
    /// ⚑[tool=export_trie_oracle ref=KSOptions.ioContext:0x104c63328 result=ioContext]
    public func resolveIO(for url: URL, interrupt: AVIOInterruptCB) -> Either<URL, AbstractAVIOContext> {
        guard let ioContext = process(url: url, interrupt: interrupt) else {
            return .left(url)
        }
        self.ioContext = ioContext
        return .right(ioContext)
    }

    /// ⚑ s109 RE-SIGNATURE: the `interrupt:` parameter was missing. Address→name is useless here —
    /// the body 0x10002d9d4 is the image's 605-symbol ICF fold — but name→address stays unique, and
    /// a demangled sweep of the whole trie resolves this member to
    /// `KSOptions.process(url: Foundation.URL, interrupt: __C.AVIOInterruptCB) -> AbstractAVIOContext?`
    /// at that address, with its method descriptor at 0x1039ec7c8.
    /// (A hand-built mangle for the one-parameter spelling returns NOT IN TRIE, which is the
    /// backreference-compression false negative the reading rules warn about — not evidence.)
    ///
    /// The body is unchanged: the fold is `mov x0, #0x0` / `ret`, i.e. `nil`. This is the
    /// overridable hook `resolveIO(for:interrupt:)` calls, which is where the second parameter goes.
    open func process(url _: URL, interrupt _: AVIOInterruptCB) -> AbstractAVIOContext? {
        nil
    }
    public var decoderOptions: [String: Any] = [String: Any]()
    public var lowres: UInt8 = UInt8(0)

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

    func makeDecode(packet: Packet) -> DecodeProtocol { fatalError("L7: KSOptions.makeDecode — Forward body unread") }
    public let useSystemHTTPProxy: Bool = KSOptions.useSystemHTTPProxy

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
    //   (e) `grow(0x1c)` = 24 literal bytes + 2 interps ⇒ "\(yadif)=mode=\(yadifMode):parity=-1:deint=1"; (f) isDoubleRefreshRate.
    open func deinterlace(assetTrack: FFmpegAssetTrack) {
        hardwareDecode = false
        let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
        var yadifMode = self.yadifMode
        if deInterlaceAddIdet {
            videoFilters.append("idet")
        }
        if assetTrack.nominalFrameRate > 30, yadifMode == 1 || yadifMode == 3 {
            yadifMode -= 1
        }
        videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")
        if yadifMode == 1 || yadifMode == 3 {
            isDoubleRefreshRate = true
        }
    }
    public nonisolated(unsafe) static var useSystemHTTPProxy = true
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
    private func appendAVPlayerHeader(_ p0: [String : String]) { fatalError("L7: KSOptions.appendAVPlayerHeader — Forward body unread") }

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
    public func removeHeader(key: String) { fatalError("L7: KSOptions.removeHeader — Forward body unread") }

    public func setCookie(_ cookies: [HTTPCookie]) {
        avOptions[AVURLAssetHTTPCookiesKey] = cookies
        let cookieStr = cookies.map { cookie in "\(cookie.name)=\(cookie.value)" }.joined(separator: "; ")
        appendHeader(["Cookie": cookieStr])
    }
    public nonisolated(unsafe) static var preferredForwardBufferDuration = 3.0
    /// 最大缓存视频时间
    public nonisolated(unsafe) static var maxBufferDuration = 30.0

    public var seekUsePacketCache: Bool = false
    /// 最低缓存视频时间
    @Published
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration
    /// 最大缓存视频时间
    public var maxBufferDuration: Double = KSOptions.maxBufferDuration

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

    // ── moved from Model.swift: the Forward decl groups sit between KSOptions.swift anchors
    public nonisolated(unsafe) static var audioPlayerType: AudioOutput.Type = AudioEnginePlayer.self
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
    public nonisolated(unsafe) static var isSpatialAudioEnable: Bool = false

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

    internal var fontsDir: URL? // Tier 3a: read by SubtitleDecode.init (FUN_101a6914c @0x133 _TtC8KSPlayer9KSOptions::fontsDir) -> SubtitleDecode.fontsDir = fontsDir?.path  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    // ── s109, four more lazily-initialised statics ───────────────────────────────────────────
    // All four share one addressor shape: `__swift_instantiateConcreteTypeFromMangledName` (or a
    // direct metadata accessor) for the property's type, then the generic value-buffer pair
    // @0x1000a538c / @0x1000a48f4 — allocateBuffer and projectBuffer, identified by the
    // `tbz w8,#0x11` on the IsNonInline bit of the value-witness flags word at VWT+0x50 — and a
    // store into the projected address. Types are read off the `vpZ` symbols, not chosen, and all
    // four carry a `vpZMV` property descriptor, so all four are public and stay unmarked in this
    // `public extension`. All four carry a `vsZ`, so all four are `var`.
    //
    // defaultFont is `nil`, and the encoding is read rather than assumed: the once-init
    // @0x1019b93a8 ends by loading VWT+0x38 — `storeEnumTagSinglePayload` — off *URL's* witness
    // table and calling it with whichCase=1 and numEmptyCases=1. For `Optional<URL>` case 1 is the
    // first empty case, i.e. `.none`. Nothing else is stored.
    // ⚑[tool=bind_oracle ref=__got:0x104109b18 result=Foundation.URL-metadata-accessor]
    public nonisolated(unsafe) static var defaultFont: URL? = nil

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
    public nonisolated(unsafe) static var enableHDRSubtitle: Bool = false
    public nonisolated(unsafe) static var subtitleExposure: Float = 0.0
    public nonisolated(unsafe) static var isASSUseImageRender: Bool = false
    public nonisolated(unsafe) static var isSRTUseImageRender: Bool = false
    public nonisolated(unsafe) static var preferEffectSubtitle: Bool = false
    public nonisolated(unsafe) static var isResizeImageSubtitle: Bool = false
    public nonisolated(unsafe) static var stripSubtitleStyle = true
    public nonisolated(unsafe) static var useMACaptionAppearance: Bool = false
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
    public nonisolated(unsafe) static var textColor: UIColor = .white
    public nonisolated(unsafe) static var textStrokeColor: UIColor = .black
    public nonisolated(unsafe) static var textStrokeWidth: CGFloat = 0.0
    public nonisolated(unsafe) static var textShadowOffset: CGSize = .zero
    public nonisolated(unsafe) static var textBackgroundColor: UIColor = .clear
    public nonisolated(unsafe) static var textShadowBlurRadius: Double = 0.0
    public nonisolated(unsafe) static var textShadowColor: UIColor = .black
    // translationTarget @0x1019ba494: `Locale` metadata is fetched first and its VWT size drives a
    // stack alloca; `Locale.current.getter` writes the temporary there (x8 = sret), then
    // `Locale.language.getter` is called with x8 = the projected storage and swiftself = x20 = that
    // temporary, and the temporary is destroyed through VWT+0x8. That is `Locale.current.language`.
    // ⚑[tool=bind_oracle ref=__got:0x104109ed0 result=Foundation.Locale.current.getter]
    // ⚑[tool=bind_oracle ref=__got:0x104109f00 result=Foundation.Locale.language.getter]
    public nonisolated(unsafe) static var translationTarget: Locale.Language = Locale.current.language
    public nonisolated(unsafe) static var isUseNewSubtitleRender = true

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
    public static func textFont(name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }
    public nonisolated(unsafe) static var textFontName = "SF Pro"
    public nonisolated(unsafe) static var subtitleFontSize = 11.0
    public nonisolated(unsafe) static var subtitleFontSizeScale = 1.0
    public nonisolated(unsafe) static var textBold: Bool = false
    public nonisolated(unsafe) static var textItalic: Bool = false
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
    public nonisolated(unsafe) static var secondaryTextStyle: SubtitleTextStyle?
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
    public nonisolated(unsafe) static var textPosition = TextPosition(leftMargin: 10, rightMargin: 10)
    public nonisolated(unsafe) static var secondaryTextPosition = TextPosition(leftMargin: 10, rightMargin: 10)
    public nonisolated(unsafe) static var subtitleOffset: CGFloat = 0.0
    public nonisolated(unsafe) static var subtitleImageScale = 1.0
    public nonisolated(unsafe) static var subtitleImageOffset: CGSize = .zero
    // subtitleDynamicRange @0x1019bb404: after the buffer pair, the value comes from a single
    // sret call to the stub @0x103455e90, whose __got slot is 0x104110650.
    // ⚠️ `bind_oracle` answered "NO BIND at this address" for that slot until s109 — its row regex
    //   anchored the symbol at end-of-line and so silently dropped every `(weak_import)` row, 377
    //   of them. The chained-fixup word there decodes to bind ordinal 0x10d2, one past its
    //   neighbour at 0x104110648, which is what proved the miss was the parser's and not the
    //   image's. With the regex fixed the slot names itself.
    // ⚑[tool=bind_oracle ref=__got:0x104110650 result=SwiftUI.Image.DynamicRange.high]
    public nonisolated(unsafe) static var subtitleDynamicRange: Image.DynamicRange = .high
    public nonisolated(unsafe) static var showTranslateSourceText: Bool = false
    public var audioRecognizes: [AudioRecognize] = []
    // sutile
    public var autoSelectEmbedSubtitle: Bool = true
    public var isSeekImageSubtitle: Bool = false

    /// 开启VR模式的陀飞轮
    public nonisolated(unsafe) static var enableSensor = true
    public nonisolated(unsafe) static var isClearVideoWhereReplace = true
    public nonisolated(unsafe) static var videoPlayerType: (VideoOutput & UIView).Type = MetalPlayView.self
    public nonisolated(unsafe) static var yadifMode = 1
    public nonisolated(unsafe) static var deInterlaceAddIdet = false
    public let yadifMode: Int = KSOptions.yadifMode
    public let deInterlaceAddIdet: Bool = KSOptions.deInterlaceAddIdet

    /// @0x1019bb974, 175 instructions. The signature is the trie's, not inferred:
    /// ⚑[tool=export_trie_oracle ref=KSOptions.wantedSubtitle(tracks:):0x1019bb974 result=OWNER_MATCH]
    /// This is the method MEPlayerItem.swift:464 identified at the call site and left unbuilt.
    ///
    ///   · the first statement reads `autoSelectEmbedSubtitle` through its own offset global
    ///     0x104c63378 under a (0, 0) beginAccess and `cmp w8,#1 / b.ne` straight to the nil
    ///     return — the guard, not a branch inside the loop.
    ///   · the loop walks the array at stride 0x10 from element 0 (`ldp x20,x26,[x23,#-0x8]` with
    ///     x23 starting at base+0x28), i.e. the two-word (instance, witness-table) existential.
    ///   · per element it dispatches witness **+0x28**. This file's own pinned ordering for the
    ///     URLSubtitleInfo:SubtitleInfo table is +0x10..+0x38 = subtitleID / name / delay /
    ///     languageCode / subtitleLanguage / isEnabled, so +0x28 is `languageCode`, and the
    ///     `cbz x1` on the second word of its result is the `String?` nil test (a nil
    ///     Optional<String> is (0,0) where a valid "" is (0, 0xE0…)).
    ///   · both sides are then `Locale.current.localizedString(forLanguageCode:)`
    ///     (`_$s10Foundation6LocaleV15localizedString15forLanguageCodeSSSgSS_tF`), the right-hand
    ///     one fed by `Locale.current.languageCode`. Both Locale temporaries are stack-allocated
    ///     from the VWT size and destroyed per iteration — the right-hand side is recomputed
    ///     INSIDE the loop, so it is not hoisted in the source either.
    ///   · the compare is `_stringCompareWithSmolCheck(_:_:expecting:)` with `w4 = 0` (.equal),
    ///     preceded by the two-word identity fast path. Crucially the nil/nil case at 0x1019bbb88
    ///     branches to the MATCH exit, so the comparison is on the OPTIONALS — which is what makes
    ///     the spelling `.flatMap`, not an `if let`.
    ///   · the loop-exhausted path (0x1019bbb9c) reloads element 0 and retains it, so a non-empty
    ///     no-match returns the first track. There is no `brk` anywhere in the extent, so that is
    ///     `.first` and not a subscript — the same rule `wantedVideo` above is spelled by.
    ///   · the tail is `_object_getClass` compared against `type metadata for FFmpegAssetTrack`
    ///     (0x1044e91c8), then `ldr x8,[x20,#0xb8]` / `ldr w8,[x8,#0x4]` / `sub w8,w8,#0x17000` /
    ///     `cmp w8,#0x7`. That is `isDVBTeletext` INLINED — byte-for-byte the body documented on
    ///     `FFmpegAssetTrack.isDVBTeletext` @0x101a1f2f0 — so it is spelled by its own name rather
    ///     than re-derived here. 0xb8 is `codecpar` by the field-offset vector, not by position.
    /// ⚑[tool=field_offset_vector ref=FFmpegAssetTrack.codecpar result=index-14@0xb8]
    /// ⚑[tool=decode_witness_table ref=URLSubtitleInfo:SubtitleInfo result=witness+0x28=languageCode]
    ///
    /// ⚑ ACCESS not independently proven. The trie name carries no private discriminator so it is
    ///   not `private`, and the call site MEPlayerItem.swift:464 records is a vtable dispatch at
    ///   md+0x768, which proves a class-body declaration with a slot but not which of `internal` /
    ///   `public` / `open` it is. `open` matches its two siblings above, which take a track array
    ///   and return an optional track; that is consistency, not evidence.
    open func wantedSubtitle(tracks: [any SubtitleInfo]) -> (any SubtitleInfo)? {
        guard autoSelectEmbedSubtitle else { return nil }
        let track = tracks.first { track in
            track.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
                == Locale.current.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
        } ?? tracks.first
        if let track = track as? FFmpegAssetTrack, track.isDVBTeletext {
            return nil
        }
        return track
    }
    public nonisolated(unsafe) static var hardwareDecode = true
    // 默认不用自研的硬解，因为有些视频的AVPacket的pts顺序是不对的，只有解码后的AVFrame里面的pts是对的。
    public nonisolated(unsafe) static var asynchronousDecompression = false
    public nonisolated(unsafe) static var canStartPictureInPictureAutomaticallyFromInline = true
    public nonisolated(unsafe) static var preferredFrame = false
    // ── s106, two more once-statics ──────────────────────────────────────────────────────────
    /// ⚑[tool=llvm-objdump ref=KSOptions.doviMatrix:once-init@0x1019bc3ac result=11-instr]
    /// The init copies 48 bytes of constant into the storage as three 16-byte columns, from
    /// 0x103564510 / 0x103564520 / 0x103564530. Read as floats those are
    /// (1,0,0,_) (0,1,0,_) (0,0,1,_) — the identity. Storage types as `__C.simd_float3x3`.
    /// ⚑ SPELLING is undecidable and that is recorded rather than hidden: `matrix_identity_float3x3`,
    /// `simd_float3x3(1)` and the explicit three-column form all constant-fold to these same 48
    /// bytes, so the binary cannot distinguish them. The identity spelling is used as the clearest.
    public nonisolated(unsafe) static var doviMatrix = matrix_identity_float3x3
    public nonisolated(unsafe) static var displayEnumPlane = defaultDisplayEnumPlane
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
    public nonisolated(unsafe) static var displayEnumDovi = DoviDisplayModel()
    /// ⚑ s113: NOW DECLARED. Everything the long note above establishes about these two still
    /// stands — the types, the storages (0x104c632b0 / 0x104c632b8), the `swift_once` addressors
    /// @0x1019bc684 / @0x1019bc74c and the no-argument construction through the shared tail
    /// @0x1019bc700 into `VRDisplayModel.init` @0x101a8c5b4. What changed is only the SPELLING of
    /// the declaration.
    ///
    /// Each carries exactly four symbols — addressor, static getter, the storage, and a property
    /// descriptor — and NO `vsZ`. No setter is `let`, and the property descriptor is the `vpMV`
    /// that makes them public; they sit in `public extension KSOptions`, so both stay unmarked,
    /// exactly like the three siblings above.
    /// ⚑[tool=export_trie_oracle ref=KSOptions.displayEnumVR:0x104c632b0 result=4-symbols-no-vsZ]
    /// ⚑[tool=export_trie_oracle ref=KSOptions.displayEnumVRBox:0x104c632b8 result=4-symbols-no-vsZ]
    ///
    /// ⚑ THE `@MainActor` IS NOT BINARY-DERIVED, and this is the one thing to carry forward.
    ///   Actor isolation leaves no reflection record, so NO spelling of it here is derived —
    ///   including the `nonisolated(unsafe)` the three siblings carry. What decided it is which
    ///   un-derived spelling costs least elsewhere:
    ///     · `nonisolated(unsafe) var` and `nonisolated(unsafe) let` were both measured (s109,
    ///       s112) and both fail identically — "main actor-isolated default value in a
    ///       nonisolated(unsafe) context" — because these two types, unlike PlaneDisplayModel and
    ///       DoviDisplayModel, declare `override required init()` and inherit isolation from the
    ///       `DisplayEnum` protocol.
    ///     · Unpicking that chain was also measured (s112) and needs three further isolation edits
    ///       — on `DisplayEnum`, `sceneSize` and `SphereDisplayModel` — none of them derived.
    ///     · `@MainActor` on the static itself was NOT probed by any of those sessions. It builds
    ///       4/4 and it changes NOTHING else in the tree: zero edits to any other declaration.
    ///   It is therefore the minimum, and it is consistent with the isolation model this tree
    ///   already carries, since `DisplayEnum` is `@MainActor` here.
    ///
    /// ⚠️ COUNTER-EVIDENCE, recorded so it is not lost: the binary argues the other way. The
    ///   once-init tail and both inits (`VRDisplayModel.init` @0x101a8c5b4, `SphereDisplayModel.init`
    ///   @0x101a8bf3c) carry NO actor machinery — no `ScMMa`, no `swift_task_isCurrentExecutor`,
    ///   no `swift_task_reportUnexpectedExecutor` — and that absence is evidence rather than a gap,
    ///   because `MetalPlayView.set` @0x101a60fc8 in this same image emits all three. So Forward's
    ///   `DisplayEnum` is probably NOT main-actor isolated at all. A session that takes the
    ///   isolation unit and unpicks that chain should revisit these two annotations first — they
    ///   are the cheapest thing to remove once `DisplayEnum` stops being `@MainActor`.
    /// ⚑[tool=body_fingerprint ref=VRDisplayModel.init:0x101a8c5b4 result=no-actor-machinery]
    @MainActor public static let displayEnumVR = VRDisplayModel()
    @MainActor public static let displayEnumVRBox = VRBoxDisplayModel()
    /// ⚑[tool=llvm-objdump ref=KSOptions.pictureInPictureType:once-init@0x1019bc7a8 result=11-instr]
    /// `mov x0,#0` / `bl 0x1019c7568` gets a type metadata, then `stp x0, x8` writes the pair
    /// (metatype, witness table) — an existential metatype, matching the storage's own type
    /// `KSPlayer.KSPictureInPictureProtocol.Type`.
    /// ⚑[tool=export_trie_oracle ref=0x1019c7568 result=metadata-accessor-KSPictureInPictureController]
    /// ⚑[tool=decode_witness_table ref=0x1041d45a0 result=KSPictureInPictureController:KSPictureInPictureProtocol]
    /// The witness table stored alongside is that class's conformance to the protocol, which is
    /// what makes the value `KSPictureInPictureController.self` rather than any other conformer.
    public nonisolated(unsafe) static var pictureInPictureType: KSPictureInPictureProtocol.Type = KSPictureInPictureController.self
    public nonisolated(unsafe) static var videoSoftDecodeThreadCount = 4
    public nonisolated(unsafe) static var forceDVForProfile7 = true

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
    public nonisolated(unsafe) static var audioVideoClockSync = true
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
    public var display: any DisplayEnum = KSOptions.defaultDisplayEnumPlane
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

    private func shouldLogVideoClockDrop() -> Bool { fatalError("L7: KSOptions.shouldLogVideoClockDrop — Forward body unread") }
    // adjustBuffer holds a 16-byte MTLBuffer of SIMD4<Float>(brightness, contrast, saturation, enable),
    // rebuilt by each colour property's didSet; the default is folded from the (1,1,1) defaults → [1,1,1,0].
    // ⚑ INFERRED name `makeAdjustBuffer`: the builder is inlined at all four call sites (KSOptions.init +
    //   the 3 didSets), so its source symbol is unrecoverable — a shared static factory is the DRY reading,
    //   matching the MetalRender lazy-buffer idiom (label set on the returned MTLBuffer).
    public var adjustBuffer: MTLBuffer? = KSOptions.makeAdjustBuffer(brightness: 1, contrast: 1, saturation: 1)

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

    // Forward 1.3.17 takes a 4th argument and branches on IT, not on `isLive`:
    //   cmp w1,#0x2 · mov w8,#4 · mov w9,#8 · csel w0,w9,w8,gt · ret
    // w1 is `reorderSize` (fps/naturalSize consume FP registers, `isLive` takes w0, self is x20);
    // w0 is only the csel DESTINATION, never a source operand, and a Swift Bool cannot make
    // `cmp #2 / csel gt` non-constant — so the tested value is provably not `isLive`.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSOptions.videoFrameMaxCount:0x1019bea54 result=signature+body-recovered]
    open func videoFrameMaxCount(fps _: Float, naturalSize _: CGSize, isLive _: Bool, reorderSize: Int32) -> UInt8 {
        reorderSize > 2 ? 8 : 4
    }

    /// customize dar
    /// - Parameters:
    ///   - sar: SAR(Sample Aspect Ratio)
    ///   - dar: PAR(Pixel Aspect Ratio)
    /// - Returns: DAR(Display Aspect Ratio)
    open func customizeDar(sar _: CGSize, par _: CGSize) -> CGSize? {
        nil
    }
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

    // 虽然只有iOS才支持PIP。但是因为AVSampleBufferDisplayLayer能够支持HDR10+。所以默认还是推荐用AVSampleBufferDisplayLayer
    // Forward 0x1019bec28 checks pixelBuffer.size.height before asking the pixelBuffer's HDR
    // requirements for CAEDRMetadata. The metadata helper at 0x101a88500 uses the pixelBuffer,
    // not VideoVTBFrame.edrMetaData; its HLG transfer path requires an available HLG mode.
    open func isUseDisplayLayer(frame: VideoVTBFrame, isHDRScreen: Bool) -> Bool {
        if forceDisableDisplayLayer {
            return false
        }
        if frame.pixelBuffer.size.height >= 6000 {
            return false
        }
        #if !os(tvOS)
        if !isHDRScreen, pixelBufferEDRMetadata(frame.pixelBuffer) != nil {
            return false
        }
        #endif
        guard display === KSOptions.defaultDisplayEnumPlane else {
            return false
        }
        guard brightness == 1, contrast == 1, saturation == 1 else {
            return false
        }
        return videoPipeline == nil
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

    @MainActor
    open func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        // Forward 0x1019bee98 (vtable slot 234): the iOS body is this one gated log (level .warning, line 0x3a4).
        KSLog("[video] refreshRate=\(refreshRate),dynamicRange=\(dynamicRange)", line: 932)
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
    private var videoClockDelayCount: Int = 0
    public internal(set) var lastVideoClockDropLogTime: Double = 0.0

    private func resetPreferredDisplayCriteria() { fatalError("L7: KSOptions.resetPreferredDisplayCriteria — Forward body unread") }

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

    // ⚑[tool=member_surface ref=KSOptions.videoClockSync result=frameCount Swift.UInt; ret Forward `ClockProcessType` (no Double)]
    // L7: return is still `(Double, ClockProcessType)` — the sole consumer (MEPlayerItem.getVideoOutputRender) writes
    //   the Double into DynamicInfo.audioVideoSyncDiff, whose Forward writer is not this path; body work.
    open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: UInt) -> (Double, ClockProcessType) {
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
                        return (diff, .dropFrame(count: 1)) // L7: Forward's count operand unread; 1 = the old single-frame drop
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
                        return (diff, .dropFrame(count: 1)) // L7: Forward's count operand unread; 1 = the old single-frame drop
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
    public nonisolated(unsafe) static var lockAspectRatio = true
    public nonisolated(unsafe) static var hudLog: Bool = false
    /// 日志级别
    // default = .error: the logLevel global byte @0x1044e5173 = 2, the CASE INDEX of .error
    // (a fieldless enum stores/reads as its case index, not the rawValue — 2 matches no LogLevel
    // rawValue [0/8/16/24/…], so it is unambiguously the index; see the KSLog gate note below).
    public nonisolated(unsafe) static var logLevel = LogLevel.error
    public nonisolated(unsafe) static var logger: LogHandler = OSLog(lable: "KSPlayer")
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

    #if !os(tvOS)
    @available(iOS 16, *)
    private final func pixelBufferEDRMetadata(_ pixelBuffer: PixelBufferProtocol) -> CAEDRMetadata? {
        if let displayInfo = pixelBuffer.displayInfo, let contentInfo = pixelBuffer.contentInfo {
            return CAEDRMetadata.hdr10(displayInfo: displayInfo, contentInfo: contentInfo, opticalOutputScale: 10000)
        }
        if let ambientViewingEnvironment = pixelBuffer.ambientViewingEnvironment {
            if #available(macOS 14.0, iOS 17.0, *) {
                return CAEDRMetadata.hlg(ambientViewingEnvironment: ambientViewingEnvironment)
            }
            return CAEDRMetadata.hlg
        }
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        }
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            if DynamicRange.availableHDRModes.contains(.hlg) {
                return CAEDRMetadata.hlg
            }
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        }
        return nil
    }
    #endif

    open func urlIO(log: String) {
        if log.starts(with: "Original list of addresses"), dnsStartTime == 0 {
            dnsStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Starting connection attempt to"), tcpStartTime == 0 {
            tcpStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Successfully connected to"), tcpConnectedTime == 0 {
            tcpConnectedTime = CACurrentMediaTime()
        }
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

    /// @0x1019c0938, 324 instructions. The trie gives the whole signature, return type included:
    /// `KSPlayer.KSOptions.firstTimeLog() -> [Swift.String : Swift.Double]`, mangled
    /// `$s8KSPlayer9KSOptionsC12firstTimeLogSDySSSdGyF`. A method descriptor exists at 0x1039ecdc8
    /// (`…yFTq`), so it is a vtable member declared in the class body, not an extension and not
    /// `final`; KSOptions has no override table, so it is an own entry rather than an override.
    /// ⚑[tool=export_trie_oracle ref=KSOptions.firstTimeLog:0x1019c0938 result=SDySSSdGyF]
    ///
    /// Every one of the twelve fields it reads is named by the offset resolver, not inferred:
    /// 0x104c63438 prepareTime · 0x440 dnsStartTime · 0x448 tcpStartTime · 0x450 tcpConnectedTime ·
    /// 0x458 openTime · 0x460 findTime · 0x468 readyTime · 0x470 readAudioTime · 0x478
    /// readVideoTime · 0x480 decodeAudioTime · 0x488 decodeVideoTime · 0x490 firstPlayableTime.
    /// Each is read as a direct `ldr d,[x19, <global>]` — no accessor call anywhere in the body.
    /// ⚑[tool=recover_field_offsets ref=KSOptions.firstPlayableTime:0x104c63490 result=firstPlayableTime]
    ///
    /// Structure, read in order: the body stack-promotes a ONE-element `[(String, Double)]` literal
    /// (the 16-byte header at 0x10347bd30 is count=1, capacityAndFlags=2), converts it to a
    /// Dictionary, then performs TEN subscript sets — matching the ten `bl 0x1019c1ca4`, which is
    /// the `Dictionary<String,Double>` subscript SETTER, not a lookup, and whose inout target is a
    /// LOCAL stack slot reloaded after each call, never a stored property.
    ///
    /// The single branch is `fcmp d0,#0.0` / `b.le` at 0x1019c0a50 on tcpConnectedTime. The
    /// `"openTime"` set is tail-merged at 0x1019c0b98: the then-arm loads openTime − tcpConnectedTime,
    /// the else-arm reloads openTime − prepareTime, and both fall into one `fsub`. Written per-branch
    /// here; a single set with a ternary subtrahend lowers identically, so the binary does not
    /// distinguish the two spellings.
    ///
    /// ⚑ The last key is built by CSE and a `mov`/`movk` scan misses it: x21 holds the trailing word
    ///   of `"decodeVideoTime"` and `add x1,x21,#0x400` at 0x1019c0e14 rewrites one byte, turning
    ///   `…deoTime` into `…dioTime` to spell `"decodeAudioTime"`. The literal never appears whole.
    ///
    /// ⚑ NOT a logging method despite the name: the complete `adrp` census over all 324 instructions
    ///   is four pages — the field-offset globals, the array header, two mangled-name records and the
    ///   metadata caches. There is no `__cstring` page, no KSLog call, and no `#file`/`#line`/
    ///   `#function` triple, which is also why this member's FILE placement is not decided by a
    ///   `#fileID` and rests on its owning class instead.
    ///   ⚑[tool=decode_string_literal ref=KSOptions.firstTimeLog:0x1019c0938 result=no-file-no-function]
    ///
    /// ⚑ ACCESS is not binary-determinable: the mangling carries no module-hash discriminator, so it
    ///   is not private, but nothing distinguishes internal from public. Spelled to match its sibling
    ///   `resetTimeLog()`, which is the same telemetry family on the same class.
    ///   ⚑[tool=export_trie_oracle ref=KSOptions.firstTimeLog:0x1039ecdc8 result=method-descriptor-no-discriminator]
    ///
    /// ⚑ The local's IDENTIFIER is unobservable — local names survive nowhere in a stripped binary,
    ///   so this spelling is arbitrary and carries no evidence. Only its type and its ten mutations
    ///   are read.
    ///   ⚑[tool=function_extents ref=KSOptions.firstTimeLog:0x1019c0938 result=local-name-unobservable]
    func firstTimeLog() -> [String: Double] {
        var log = ["firstTime": firstPlayableTime - prepareTime]
        if tcpConnectedTime > 0 {
            log["initTime"] = dnsStartTime - prepareTime
            log["dnsTime"] = tcpStartTime - dnsStartTime
            log["tcpTime"] = tcpConnectedTime - tcpStartTime
            log["openTime"] = openTime - tcpConnectedTime
        } else {
            log["openTime"] = openTime - prepareTime
        }
        log["findTime"] = findTime - openTime
        log["readyTime"] = readyTime - findTime
        log["readVideoTime"] = readVideoTime - readyTime
        log["readAudioTime"] = readAudioTime - readyTime
        log["decodeVideoTime"] = decodeVideoTime - readVideoTime
        log["decodeAudioTime"] = decodeAudioTime - readAudioTime
        return log
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
}

public enum VideoInterlacingType: String {
    case tff
    case bff
    case progressive
    case undetermined
}

public extension KSOptions {
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
    //
    //   s109 tried both escapes and MEASURED them, so a later session need not repeat the probe:
    //     · Deleting `@MainActor` from `SphereDisplayModel` builds 4/4 but changes NOTHING here —
    //       the isolation is inherited from the `DisplayEnum` protocol (PlayerDefines.swift:176),
    //       so that annotation is merely redundant and removing it does not unblock these two.
    //     · Marking both `override required init()` `nonisolated` moves the error INTO the inits:
    //       `KSOptions.sceneSize` "can not be referenced from a nonisolated context" and
    //       `super.init()` is "main actor-isolated". Landing these two rows that way would take
    //       three further isolation edits, on `DisplayEnum`, `sceneSize` and `SphereDisplayModel`,
    //       none of them binary-derived — PlayerDefines.swift:179 already states outright that the
    //       protocol's `@MainActor` is not. Two read values are not worth three invented
    //       annotations, so the s106 judgment stands and these stay blocked.
    //   Both are `vgZ`-only (no `vsZ` in the trie), so when they do land they are `let`, not `var`.
    //   ⚑[tool=export_trie_oracle ref=KSOptions.displayEnumVR:0x104c632b0 result=vgZ-no-vsZ]
    //   ⚑[tool=export_trie_oracle ref=KSOptions.displayEnumVRBox:0x104c632b8 result=vgZ-no-vsZ]
    //
    //   s112 closed two more escapes by MEASURING them, so no later session need re-probe:
    //     · The `let` spelling this note itself recommends fails IDENTICALLY. Declared as
    //       `nonisolated(unsafe) static let displayEnumVR = VRDisplayModel()` the compiler emits the
    //       same `error: main actor-isolated default value in a nonisolated(unsafe) context`, at the
    //       default-value column. Every error above was recorded against `var`; `let` is not a way
    //       out, and the `vgZ`-no-`vsZ` reading does not unblock these rows.
    //     · "Delete the invented init" is NOT available either. Both classes' stored properties are
    //       REAL: the field records carry `modelViewProjectionMatrix` (VRDisplayModel, NumFields=1)
    //       and `modelViewProjectionMatrixLeft`/`Right` (VRBoxDisplayModel, NumFields=2), all three
    //       at the same symbolic type as `SphereDisplayModel.modelViewMatrix`. Fields that must be
    //       assigned require the `override required init()` the reconstruction already declares, so
    //       the isolation it inherits cannot be removed by removing the initialiser.
    //   ⚑[tool=fieldrec ref=VRDisplayModel.modelViewProjectionMatrix:0x103cbdbf0 result=NumFields-1]
    //   ⚑[tool=fieldrec ref=VRBoxDisplayModel.modelViewProjectionMatrixLeft:0x103cbdc0c result=NumFields-2]
    //
    //   s112 then RAN the isolation experiment end to end and reverted it, which narrows the blocker
    //   from a judgement call to a readable body. Removing `@MainActor` from the `DisplayEnum`
    //   protocol and from both conforming classes (plus `SphereDisplayModel.init` and
    //   `touchesMoved`) leaves EXACTLY two unresolved references, and nothing else in the tree:
    //     · `MotionSensor.shared.start()` @DisplayModel.swift:145 and `.matrix()` @:177
    //     · `KSOptions.sceneSize` @DisplayModel.swift:274, :297, :311
    //   ❌ RETRACTED, same session, before anything was applied. The first draft of this paragraph
    //   said the MotionSensor lines were residue because `MotionSensor` has ZERO symbols in the
    //   export trie and `VRDisplayModel.init` "inlines SphereDisplayModel.init and makes no motion
    //   call". The trie fact is true; BOTH inferences from it were wrong, and acting on them would
    //   have deleted real binary-backed code.
    //     · `VRDisplayModel.init` @0x101a8c5b4 does NOT inline the superclass init. Its last call,
    //       0x101a8bf3c, IS `SphereDisplayModel.init` — 126 instructions of its own.
    //     · That body carries the sensor path in full: the `static KSOptions.enableSensor` gate
    //       @0x1044e5150, then `isDeviceMotionAvailable`, `isDeviceMotionActive`,
    //       `setDeviceMotionUpdateInterval:` and `startDeviceMotionUpdates`. It also carries
    //       genSphere @0x101a8cf1c and the three `newBufferWithBytes:length:options:` calls that
    //       build indexBuffer/posBuffer/uvBuffer, exactly as spelled at DisplayModel.swift:136-146.
    //   Zero trie symbols for `MotionSensor` means the TYPE is not separately exported — the
    //   CoreMotion sends are emitted straight into the init — NOT that the calls are absent. The
    //   same holds for `.matrix()` at :176, which this file already documents as binary-backed via
    //   the provider @0x101a880e4 and the 0x40-byte copy into modelViewMatrix.
    //   ⚑[tool=body_fingerprint ref=SphereDisplayModel.init:0x101a8bf3c result=enableSensor-and-CoreMotion-present]
    //
    //   So the isolation blocker is NOT residue and these two rows stay blocked for exactly the
    //   reason s106 and s109 gave. What the experiment DOES establish, and what is still worth
    //   inheriting, is the BOUND above: unpicking the @MainActor chain leaves those five references
    //   and nothing else, so the unit is small and fully enumerated — it is just not free.
    //
    //   The initialiser IS locatable, which the earlier note thought it was not, and this part
    //   stands: the once-init @0x1019bc664 hands metadata accessor 0x101a8d244, size 0x100 and
    //   storage 0x104c632b0 to a shared tail @0x1019bc700, which `swift_allocObject`s and `blr`s
    //   **0x101a8c5b4** = `VRDisplayModel.init`. Its 120 instructions match DisplayModel.swift:273-280
    //   statement for statement: the sceneSize computation inlined (`objc_opt_self` on the
    //   UIApplication classref 0x1044104f8, `sharedApplication`, the private body @0x101a02de0,
    //   `bounds`), the two simd_float4x4 builders, then `super.init()` = 0x101a8bf3c.
    //   It carries NO actor machinery — no `ScMMa`, no `swift_task_isCurrentExecutor`, no
    //   `swift_task_reportUnexpectedExecutor` — and neither does 0x101a8bf3c. That absence is
    //   EVIDENCE rather than a gap, because the async display path @0x101a60fc8 in this same
    //   reconstruction emits all three; the binary can show isolation here and does not.
    //   ⚠️ It is evidence about ISOLATION only. It says nothing about whether the sensor calls
    //   belong — they demonstrably do — so do not chain the two readings together as the retracted
    //   paragraph above did.
    //   ⚑[tool=body_fingerprint ref=VRDisplayModel.init:0x101a8c5b4 result=no-actor-machinery]
    //   ⚑[tool=body_fingerprint ref=MetalPlayView.set:0x101a60fc8 result=emits-ScMMa-and-task-checks]
    //
    //   One lead this note did NOT have, for whoever takes the isolation unit: `KSOptions.sceneSize`
    //   — the member s109's `nonisolated` probe tripped over — has no `KSOptions` symbol at all. The
    //   trie carries it as `UIApplication.sceneSize` (`$sSo13UIApplicationC8KSPlayerE9sceneSizeSo6CGSizeVvgZ`,
    //   with a `vpZMV`, so public) in a KSPlayer extension on `__C.UIApplication`. Its OWNER is a
    //   divergence in its own right, and it needs its own row before it is used as evidence here.
    //   ⚑[tool=export_trie_oracle ref=UIApplication.sceneSize:0x101a01d1c result=owner-is-UIApplication-not-KSOptions]
    private nonisolated(unsafe) static let defaultDisplayEnumPlane = PlaneDisplayModel()
    nonisolated(unsafe) static var isPipPopViewController = false
    internal static func deviceCpuCount() -> Int {
        var ncpu = UInt(0)
        var len: size_t = MemoryLayout.size(ofValue: ncpu)
        sysctlbyname("hw.ncpu", &ncpu, &len, nil, 0)
        return Int(ncpu)
    }

    // ⚑[tool=member_surface ref=KSOptions.setAudioSession result=instance (Forward mangling has no Z); body has no swift_task_*/ScM call → no isolation hop]
    func setAudioSession() {
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

    static func colorSpace(colorPrimaries: CFString?, transferFunction: CFString?, dovi: DOVIDecoderConfigurationRecord?) -> CGColorSpace? {
        switch colorPrimaries {
        case kCVImageBufferColorPrimaries_ITU_R_709_2:
            if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                return CGColorSpace(name: CGColorSpace.itur_709_PQ)
            } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                return CGColorSpace(name: "kCGColorSpaceITUR_709_HLG" as CFString)
            } else {
                return CGColorSpace(name: CGColorSpace.sRGB)
            }
        case kCVImageBufferColorPrimaries_ITU_R_2020:
            if transferFunction == nil {
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
            } else if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                if dovi != nil {
                    return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
                }
                if #available(macOS 15.0, iOS 18.0, tvOS 18.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
                } else {
                    return CGColorSpace(name: CGColorSpace.itur_2020)
                }
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020)
            }
        default:
            if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            } else {
                return CGColorSpace(name: CGColorSpace.sRGB)
            }
        }
    }

    /// ⚑[tool=llvm-objdump ref=KSOptions.colorSpace2020PQ.getter:0x1019c1048 result=4-instr]
    /// Identical shape to `colorSpace2020HLG`, through the adjacent got slot.
    /// ⚑[tool=bind_oracle ref=__got:0x104109068 result=_kCGColorSpaceITUR_2100_PQ]
    static var colorSpace2020PQ: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.itur_2100_PQ)
    }

    /// ⚑[tool=llvm-objdump ref=KSOptions.colorSpace2020HLG.getter:0x1019c1058 result=4-instr]
    /// The whole body loads `__got 0x104109060`, dereferences it and tail-calls the
    /// CGColorSpace creator — no branch, no availability check.
    /// ⚑[tool=bind_oracle ref=__got:0x104109060 result=_kCGColorSpaceITUR_2100_HLG]
    /// ⚑[tool=bind_oracle ref=__got:0x104108d50 result=_CGColorSpaceCreateWithName]
    /// ⚠️ The NAME says 2020 and the constant is 2100. Transcribed as read — that mismatch is
    /// Forward's, and `colorSpace(ycbcrMatrix:transferFunction:)` (Model.swift) picks `itur_2100_HLG`
    /// for the 2020 matrix too, so it is consistent rather than a decode error.
    /// Written WITHOUT the `#available` guard the neighbouring code uses: these four
    /// instructions contain no version check, so the guard would be source the binary refutes.
    static var colorSpace2020HLG: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.itur_2100_HLG)
    }

    static func pixelFormat(planeCount: Int, bitDepth: Int32) -> [MTLPixelFormat] {
        if planeCount == 3 {
            if bitDepth > 8 {
                return [.r16Unorm, .r16Unorm, .r16Unorm]
            } else {
                return [.r8Unorm, .r8Unorm, .r8Unorm]
            }
        } else if planeCount == 2 {
            if bitDepth > 8 {
                return [.r16Unorm, .rg16Unorm]
            } else {
                return [.r8Unorm, .rg8Unorm]
            }
        } else {
            return [colorPixelFormat(bitDepth: bitDepth)]
        }
    }

    static func colorPixelFormat(bitDepth: Int32) -> MTLPixelFormat {
        if bitDepth == 10 {
            return .bgr10a2Unorm
        } else {
            return .bgra8Unorm
        }
    }

    /// FUN_1019c4770. Out-param x8, w0 = role. Neither this nor the font builder below is in the trie.
    /// Callers are FUN_101abd03c (SubtitlePart.swift), textFont(width:) @0x1019ba6f8 (`.primary`),
    /// FUN_101a95810, FUN_101ac1da0 and FUN_101ac26a4.
    /// Only `.secondary` (w0 == 1) consults secondaryTextStyle; the other path is the nil tag (FUN_100b1a5bc).
    /// textBackgroundColor has no SubtitleTextStyle field, so it is read from KSOptions unconditionally
    /// (0x1019c5888).
    internal static func textStyle(role: SubtitleTextRole) -> ResolvedSubtitleTextStyle { // name inferred
        let style = role == .secondary ? KSOptions.secondaryTextStyle : nil
        return ResolvedSubtitleTextStyle(
            textColor: style?.textColor ?? KSOptions.textColor,
            textFontName: style?.textFontName ?? KSOptions.textFontName,
            subtitleFontSize: style?.subtitleFontSize ?? KSOptions.subtitleFontSize,
            subtitleFontSizeScale: style?.subtitleFontSizeScale ?? KSOptions.subtitleFontSizeScale,
            textBold: style?.textBold ?? KSOptions.textBold,
            textItalic: style?.textItalic ?? KSOptions.textItalic,
            textStrokeColor: style?.textStrokeColor ?? KSOptions.textStrokeColor,
            textStrokeWidth: style?.textStrokeWidth ?? KSOptions.textStrokeWidth,
            textShadowOffset: style?.textShadowOffset ?? KSOptions.textShadowOffset,
            textBackgroundColor: KSOptions.textBackgroundColor,
            textShadowBlurRadius: style?.textShadowBlurRadius ?? KSOptions.textShadowBlurRadius,
            textShadowColor: style?.textShadowColor ?? KSOptions.textShadowColor
        )
    }

    /// FUN_1019c5b9c (0xf8 B). d0 = width, x0 = &style. size = scale * floor(width * fontSize / 384)
    /// (frintm). Then fontWithName:size: ?? systemFontOfSize: (textFont(name:size:) inlined).
    /// Bold → UIFont.with(weight: .bold) @0x1019f1e40 (UIFontWeightBold via __got 0x10410b018).
    /// Italic → UIFont.italic @0x1019f2054, whose body is inlined here as with(traits: 1).
    internal static func textFont(width: Double, style: ResolvedSubtitleTextStyle) -> UIFont { // name inferred
        var font = textFont(name: style.textFontName, size: style.subtitleFontSizeScale * floor(width * style.subtitleFontSize / 384))
        if style.textBold {
            font = font.with(weight: .bold)
        }
        if style.textItalic {
            font = font.italic
        }
        return font
    }
    // localHLSServerPort / maxM3U8FileSize / minM3U8BufferDuration moved to ProAVPlayer.swift:
    // Forward mangles them `$s8KSPlayer9KSOptionsC11ProAVPlayerE…` (ProAVPlayer's extension).
    nonisolated(unsafe) static var seekInterruptIO = false
    nonisolated(unsafe) static var seekRequireConfirmation = true
    nonisolated(unsafe) static var thumbSize = CGSize(width: 15, height: 15)
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
    nonisolated(unsafe) static var trackHeight: CGFloat = 5.0
    internal nonisolated(unsafe) static var thumbColor: Color = .white
    internal nonisolated(unsafe) static var trackColor: Color = .white.opacity(0.5)
    internal nonisolated(unsafe) static var progressColor: Color = .green.opacity(0.8)
    internal nonisolated(unsafe) static var focusProgressColor: Color = .red.opacity(0.9)
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
    public func removeDuplicate(predicate: (Element, Element) -> Bool) -> [Element] { fatalError("L7: Array.removeDuplicate — Forward body unread") }
    public func asyncMap<T>(_ p0: (Element) async throws -> T) async throws -> [T] { fatalError("L7: Array.asyncMap — Forward body unread") }
    func toDictionary<Key: Hashable>(with selectKey: (Element) -> Key) -> [Key: Element] {
        var dict = [Key: Element]()
        forEach { element in
            dict[selectKey(element)] = element
        }
        return dict
    }
    public func removeAllAndReturn(where p0: (Element) throws -> Bool) throws -> [Element] { fatalError("L7: Array.removeAllAndReturn — Forward body unread") }
}


extension Array where Element == UInt8 {
    public func append(_ p0: UInt16) { fatalError("L7: Array.append — Forward body unread") }
    public func append(_ p0: UInt32) { fatalError("L7: Array.append — Forward body unread") }
}
