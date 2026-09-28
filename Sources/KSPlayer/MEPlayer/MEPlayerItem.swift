//
//  MEPlayerItem.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import FFmpegKit
import Libavcodec
import Libavfilter
import Libavformat
#if canImport(UIKit)
import UIKit
#endif

// ⚑ @unchecked Sendable — compiler-MANDATED, not binary-observable: the interrupt codegen is a `{ [weak self] }`
//   @Sendable closure (openAndFindStream) which, under this target's Swift 6 + StrictConcurrency, compiles ONLY if
//   MEPlayerItem is Sendable. Sendable is a marker protocol ⟹ NO ABI/reflection trace, so it's codegen-invisible
//   but forced by the observed closure + IOInterruptContext.block's @Sendable type. The interrupt fires on FFmpeg's
//   IO thread, so @Sendable-block-over-Sendable-self is the coherent faithful design; `unchecked` = the internal
//   -locking assertion the player already makes. ⚑[tool=read_memory ref=weakSelfBox:0x1041d8340 result=@Sendable⟹Sendable-self]
public final class MEPlayerItem: @unchecked Sendable {
    // ⚑ Field-layout migration (commit-1): the 42 stored properties in Forward binary order
    //   (scripts/dump_binary_field_types.py MEPlayerItem). Types from MEPlayerItem.init
    //   (FUN_101a4bae0) + name_type_at_addr; residual generic/closure exactness flagged  ⚑[tool=resolve_fun_pins ref=FUN_101a4bae0:0x101a4bae0 result=RESOLVES_UNIQUELY] = KSPlayer.MEPlayerItem.init(io: KSPlayer.Either<Foundation.URL, KSPlayer.AbstractAVIOContext>, options: KSPlayer.KSOptions) -> KSPlayer.MEPlayerItem
    //   // ⚑ UNRESOLVED (field-record None ⟹ l2 UNCHECKED, non-blocking). The 17 base fields are
    //   removed; every method that used them is stubbed // ⚑ UNRESOLVED pending its Forward-body commit.
    var io: Either<URL, AbstractAVIOContext>                 // 1 internal (read by KSPlayerLayer.replace(playerItem:) @0x1019cbde8 via its field offset); ⚑[tool=name_type_at_addr ref=io:0x103566d40 result=Either<_,AbstractAVIOContext>] first param URL (sibling KSAVPlayer.io)

    /// ⚑[tool=disassemble ref=MEPlayerItem.isIdle.getter:0x101a4a8b8 result=6-instr]
    /// `ldr x8,[0x1044ea208]` / `ldrb w8,[x20,x8]` / `cmp w8,#0` / `cset w0,eq`.
    /// The offset global 0x1044ea208 is unnamed in the trie — only public-ish fields emit a
    /// `vpWvd` — but it is named the other way round: it is the ONLY global that both this getter
    /// and `isReusable` below touch, and the field records give MEPlayerItem exactly one
    /// byte-sized enum, `state` (index 37, a symref to the nested `MEPlayerItem.State`), whose own
    /// trie entry confirms it is private with a per-file discriminator — which is why no vpWvd.
    /// Case 0 of that enum is `.idle`, already documented at its declaration in Model.swift.
    /// ⚑[tool=disassemble ref=MEPlayerItem.ioContext.getter:0x101a480b0 result=13-instr]
    /// Loads the ivar at offset-global 0x1044ea218; if it is nil the getter returns nil, otherwise
    /// it returns `[that + 0x20]` retained. Two independent readings name both halves:
    ///   · the ivar is `formatContext` — MEPlayerItem's only `FormatContext?` field (record 6),
    ///     and the getter's return type `AbstractAVIOContext?` only makes sense through it;
    ///   · `+0x20` is `FormatContext.ioContext`, which FormatContext.swift:55 already declares as
    ///     `public let ioContext: AbstractAVIOContext?  // +0x20`, with the surrounding layout
    ///     (`+0x10=interrupt, +0x18=formatCtx, +0x20=ioContext`) recorded at :70 from an earlier
    ///     session's read of that class's init. So the constant immediate is corroborated by a
    ///     reading this session did not produce.
    /// The nil-check on the ivar is the `?.` — there is no force-unwrap and no default.
    /// Access read from its vpMV; `formatContext` is fileprivate, which is why this lives in this
    /// file rather than an extension elsewhere.
    public var ioContext: AbstractAVIOContext? {
        formatContext?.ioContext
    }

    /// Forward 0x101a48158 (41 insns, no symbol): reads currentPlaybackTime inline (state == .seeking ?
    /// seekTime : mainClock().time.seconds) and tail-calls 0x101a55de4 with the AVMediaType? in x0,
    /// returning its Bool. ⚑ INFERRED name/label (no symbol, no #function); internal access because
    /// there is no private discriminator. 0x101a556b0 is not a caller: its `brk` tail at
    /// 0x101a55dd8-0x101a55de0 simply falls into 0x101a55de4 in address order.
    func usePacketCacheSeek(mediaType: AVFoundation.AVMediaType?) -> Bool {
        usePacketCacheSeek(to: currentPlaybackTime, mediaType: mediaType)
    }

    /// Forward 0x101a4a8d0. Filter closure 0x101a57160 (mediaType wt+0x10); FFmpegAssetTrack exact-class
    /// cast; .video → findBestAudio 0x101a57210; .subtitle continues only for image subtitles with
    /// options.isSeekImageSubtitle; seek(time:) wt+0x60 per track (currentPlaybackTime re-read each
    /// iteration), then send(.seek(useCache: false, completion: nil)) and return true.
    func select(track: some MediaPlayerTrack) -> Bool {
        if track.isEnabled {
            return false
        }
        (formatContext?.assetTracks ?? []).filter { $0.mediaType == track.mediaType }.forEach {
            $0.isEnabled = track === $0
        }
        guard let assetTrack = track as? FFmpegAssetTrack else {
            return false
        }
        if assetTrack.mediaType == .video {
            findBestAudio(videoTrack: assetTrack)
        } else if assetTrack.mediaType == .subtitle {
            if assetTrack.isImageSubtitle {
                if !options.isSeekImageSubtitle {
                    return false
                }
            } else {
                return false
            }
        }
        allPlayerItemTracks.forEach { $0.seek(time: currentPlaybackTime) }
        send(.seek(to: currentPlaybackTime, useCache: false, completion: nil))
        return true
    }

    // ioOpen / ioClose (the custom-AVIO open/close2 callbacks) are declared at FILE SCOPE (below PBClass):
    //   a static method cannot form a C function pointer in Swift 6, so `formatCtx.io_open = MEPlayerItem.ioOpen`
    //   does not compile — a top-level func does. openAndFindStream installs them (@convention(c) thunks).

    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer12MEPlayerItemC11startRecord3url9mediaTypey10Foundation3URLV_So07AVMediaF0aSgtF:0x101a483d4 result=SIGNATURE_CORRECTED]
    // The `mediaType:` parameter is established three ways and is LIVE in the binary: the body's own
    // `#function` literal (0x103d366d0) decodes to "startRecord(url:mediaType:)"; x1 is stored to
    // Remuxer+0x20 with `objc_retain` @0x101a484b4 and forwarded as x7; and Remuxer field 3 is
    // `mediaType: AVMediaType?`. The sole caller passes nil — MEASURED (`mov x1,#0x0` immediately
    // before `bl 0x101a483d4` at KSMEPlayer.startRecord @0x101a444b8), not assumed.
    // `AVFoundation.AVMediaType`, not FFmpeg's `AVMediaType` C enum — the two collide in this module
    // and the binary disambiguates them: x1 is stored with `objc_retain` @0x101a484b4, so it is the
    // ObjC NSString-backed type, not a plain C int.
    //
    // BODY WRITTEN s102. Both blockers of the former pinned deferral are cleared:
    // ⚑[tool=export_trie_oracle ref=$s10Foundation3URLV8KSPlayerE12ffmpegStringSSvg:0x1019f59c4 result=LOCATED]
    //   — `URL.ffmpegString` now exists in the reconstruction (Utility.swift), landed s76; and
    //   — all NINE argument slots of the throwing callee 0x101a1d014 are now derived, not inferred:
    //     p5 `[String: Any]?`, p6+p7 `String?`, p8 `AVMediaType?` (was the un-receivable `flag: Int`),
    //     p9 `[AVCodecID]?` — each proved by the callee's own nil test. See OutputStreamInfo.swift.
    //
    // Extent 0x101a483d4-0x101a486b0, 183 instr; `self` in x20, `url` x0, `mediaType` x1. Read:
    //   guard      `ldr x19,[x20,x8]` / `cbz x19` @0x101a483fc — the formatContext field
    //   teardown   `x20 = [x24,#0x18]` then 0x101a1b8d4 / 0x101a1bb5c, which the trie names
    //              OutputStreamInfo.writeTrailer() and .stop(); +0x18 is Remuxer.outputStreamInfo
    //   clear      `str xzr,[x22,x26]` @0x101a48458 — BEFORE the filename and the allocation
    //   filename   `bl 0x1019f59c4` @0x101a4846c = URL.ffmpegString.getter -> (x24,x25)
    //   arguments  w3=1, x4=0, x5=0, x6=0, x7=mediaType (`mov x7,x21` @0x101a484d8), [sp]=0
    //   install    on success `str x24,[x23,#0x18]` then `str x23,[x22,x26]` @0x101a48564-0x101a4856c
    //   throw      x21 is swifterror (zeroed @0x101a484dc, tested @0x101a484f8); the arm releases
    //              +0x28, calls swift_deallocPartialClassInstance @0x101a4851c, then logs
    //
    // ⚑ The binary ALLOCATES the Remuxer before the throwing call and populates +0x10/+0x20/+0x28/
    //   +0x30 up front, storing +0x18 only on the success path; `Remuxer(...)` here is the
    //   source-level spelling of that inlined init, with identical resulting field values.
    // ⚑ PLACEMENT: the catch-arm log bakes in #line 701, so in Forward's own source this method sits
    //   far later in the file than it does here. Not moved — that is a file-placement unit of its own.
    func startRecord(url: URL, mediaType: AVFoundation.AVMediaType?) {
        guard let formatContext else { return }
        if let remuxer {
            remuxer.outputStreamInfo.writeTrailer()
            remuxer.outputStreamInfo.stop()
        }
        remuxer = nil
        do {
            let outputStreamInfo = try OutputStreamInfo(formatContext: formatContext,
                                                        filename: url.ffmpegString,
                                                        forceTranscode: true,
                                                        formatContextOptions: nil,
                                                        formatName: nil,
                                                        mediaType: mediaType,
                                                        transcodeCodecIDs: nil)
            remuxer = Remuxer(formatCtx: formatContext.formatCtx,
                              outputStreamInfo: outputStreamInfo,
                              mediaType: mediaType)
        } catch {
            // The OVERLOAD is derived, not chosen. `KSLog(_ error:)` (KSOptions.swift:1016) forwards
            // as `KSLog(level: .error, error() as NSError, …)`, and that `as NSError` step is what
            // identifies it: the arm calls  ⚑[tool=bind_oracle ref=_convertErrorToNSError:0x104109940 result=CONFIRMED]
            // on the in-flight error (`mov x0,x21` -> `bl 0x1034521f4` @0x101a485f0). A direct
            // `KSLog(level:_:)` on a String message would not bridge an Error at all.
            // The rest of the arm matches that forwarding body exactly, at 0x101a4858c-0x101a48658:
            //   level    `mov w0,#0x2` @0x101a4863c — the CASE INDEX of `.error`, not its rawValue
            //            (16). Same encoding this file's own logLevel note records at KSOptions.swift:783.
            //   gate     `ldrb w8,[x20]` / `cmp w8,#2` / `b.hs` @0x101a48540 — `level.rawValue <=
            //            KSOptions.logLevel.rawValue` folded to the tag compare (KSOptions.swift:1029-1034)
            //   handler  `blr x8`, `x8 = [x26,#0x8]` @0x101a48658 — the LogHandler witness, i.e.
            //            `KSOptions.logger.log(level:message:file:function:line:)`; x26 is the witness
            //            table of the global existential projected at 0x101a485e8
            //   file/fn  two 27-char literals tagged `orr …,#0x8000000000000000` @0x101a48634/0x101a48638
            //   line     `mov w6,#0x2bd` = 701
            // ⚑ GAP (Model.swift): Forward allocates the Remuxer BEFORE the throwing call and fails through
            //   `swift_deallocPartialClassInstance` @0x101a4851c. That is the codegen of a THROWING Remuxer
            //   init that builds OutputStreamInfo itself: it stores formatContext+0x18 into +0x10 and
            //   mediaType into +0x20, with [:] at +0x28 and 0 at +0x30, then calls the builder. Model.swift's
            //   Remuxer init is non-throwing, so the two-step spelling above stays until that decl lands.
            KSLog(error, line: 701)
        }
    }

    /// Forward 0x101a486b0 (no symbol), the Bool that read(errorCode:) logs as `isLive=` and branches on.
    /// Read: KSOptions+0x28 `isLive: Bool?` wins when non-nil; then formatContext (+0x28 duration,
    /// +0x30 fileSize) against self.duration/self.fileSize; otherwise true.
    /// ⚑ INFERRED name (from the `isLive=` log label); internal, no private discriminator.
    var isLive: Bool {
        if let isLive = options.isLive {
            return isLive
        }
        if let formatContext {
            if formatContext.duration == 0 {
                if formatContext.fileSize > 0, fileSize == formatContext.fileSize {
                    return false
                }
            } else if formatContext.fileSize > 0 {
                return abs(formatContext.duration - duration) > 1
            }
        }
        return true
    }

    // Ref designated entry 0x101a4bae0 copies the supplied Either directly.
    public init(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {
        self.io = io
        self.options = options
        _ = MEPlayerItem.onceInitial
    }

    public var currentPlaybackTime: TimeInterval {
        state == .seeking ? seekTime : mainClock().time.seconds // ⚑ UNRESOLVED: base subtracted removed `startTime`
    }

    public var isIdle: Bool {
        state == .idle
    }
    public let options: KSOptions                                   // 2
    public var isPreload = false                                    // 3
    private var ioTask: Task<Void, Never>?                           // 4 ⚑ UNRESOLVED generics (Task confirmed, nil-init)
    private let ioWaiterLock = NSLock()                              // 5
    private var ioWaiter: CheckedContinuation<Void, Never>?          // 6 ⚑[tool=name_type_at_addr ref=ioWaiter:0x1035647f8 result=ScC<(),_>] error-param pending
    fileprivate var formatContext: FormatContext?                        // 7
    private var remuxer: Remuxer?                                    // 8
    private var seekTime = TimeInterval(0)                           // 9
    private var seekUsePacketCache = false                           // 10
    // ⚑ `@Sendable` is READ, not added for concurrency: the trie spells this field
    //   `(@Sendable (Swift.Bool) -> ())?`. In Swift 6 @Sendable is part of the function type, so the
    //   un-annotated source spelling emitted a different mangle from the binary's. Surfaced by the s75
    //   l2_field_gate export-trie signal, which resolved a type this field previously reported as bin=None.
    private var seekingCompletionHandler: (@Sendable (Bool) -> Void)?          // 11
    // 没有音频数据可以渲染
    private var isAudioStalled = true                               // 12
    private var audioClock = KSClock()                              // 13
    private var videoClock = KSClock()                              // 14
    private var isFirst = true                                     // 15
    private var isSeek = false                                     // 16
    private var needRecordTimeIndex = false                        // 17
    private let playbackSnapshotRecordInterval = 0.5               // 18
    private var lastPlaybackSnapshotRecordTime: Double?            // 19
    private let timeIndexRecordInterval = 1.0                      // 20
    private var lastTimeIndexRecordTime: Double?                   // 21
    private var needSeekItemTrack = true                          // 22
    private var allPlayerItemTracks = [PlayerItemTrackProtocol]()  // 23
    private var videoAudioTracks = [CapacityProtocol]()           // 24
    private var videoTrack: SyncPlayerItemTrack<VideoVTBFrame>?    // 25
    private var audioTrack: SyncPlayerItemTrack<AudioFrame>?       // 26
    private var subtitleTrack: SyncPlayerItemTrack<SubtitleFrame>? // 27 (nil-init parallel; SubtitleFrame: MEFrame, Model.swift:245)
    private var videoAdaptation: VideoAdaptationState?            // 28
    fileprivate var pbArray = [PBClass]()                             // 29
    private var interrupt = false                                // 30
    private var prePosition: Int64 = 0                           // 31 ⚑ UNRESOLVED: single-word 0-init; Int64|Int|Double pending assignment site
    // 32 — the saved default AVFormatContext.io_open, boxed as a Swift closure (2-word [fn,ctx], the
    //   io_open C signature); ioOpen() falls back to it when there is no ioContext / addSub declines. The
    //   install (saving + boxing formatCtx's original io_open) is the ⚑UNRESOLVED openAndFindStream arm.
    // ⚑[tool=decompile ref=defaultIOOpen:0x101a53560 result=io_open-signature-closure]
    fileprivate var defaultIOOpen: ((UnsafeMutablePointer<AVFormatContext>?, UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Int32)? // 32
    // 33 — the saved default AVFormatContext.io_close2, boxed as a Swift closure (2-word [fn,ctx],
    //   the io_close2 signature (AVFormatContext*, AVIOContext*) -> Int32); ioClose() always delegates
    //   to it after the pbArray cleanup. The install (boxing formatCtx's original io_close2) is the
    //   ⚑UNRESOLVED openAndFindStream arm.
    // ⚑[tool=decompile ref=defaultIOClose:0x101a53924 result=io_close2-signature-closure]
    fileprivate var defaultIOClose: ((UnsafeMutablePointer<AVFormatContext>?, UnsafeMutablePointer<AVIOContext>?) -> Int32)? // 33
    public private(set) var chapters: [Chapter] = []            // 34

    /// ⚑[tool=disassemble ref=MEPlayerItem.playbackRate:0x101a4affc/0x101a480e4 result=getter-18-setter-29]
    /// getter: reads the ivar at offset-global 0x1044ea228, then `ldr d0,[x19,#0x10]` and
    ///   `fcvt s0, d0` — a Double member converted to Float.
    /// setter: `fcvt d8, s0` once, then writes `[x19,#0x10]` under a MODIFY access twice — first
    ///   through offset-global 0x1044ea220, then through 0x1044ea228. It updates BOTH clocks.
    ///
    /// `+0x10` is `KSClock.rate`: that struct's layout is already recorded at KSOptions.swift:1421
    /// as lastMediaTime (+0) · position (+0x8) · rate (+0x10, `Sd`) · time, with rate's own default
    /// read from its vpfi. So the Double at +0x10 is `rate` and nothing else.
    ///
    /// WHICH clock is which is read, not taken from the global ordering: `setVideo(time:position:)`
    /// touches 0x1044ea228 and no other clock global, and its source body sets `videoClock`. That
    /// fixes 0x228 = videoClock, leaving 0x220 = audioClock — consistent with their adjacent field
    /// records (12, 13) and their declaration order above.
    /// ⚠️ The reversed query labels 0x1044ea228 "playbackRate" and that label is WRONG — this
    /// getter reads another field's offset and then +0x10 inside it, so the single-global rule
    /// mis-attributes. The name came from `setVideo`, not from that map.
    ///
    /// No `_modify` is written: Swift synthesises the modify coroutine for a computed property
    /// with a getter and setter, which is what the third body @0x101a4b044 is.
    /// Access read from its vpMV; `KSClock.rate` is `internal(set)`, settable from this module.
    public var playbackRate: Float {
        get {
            Float(videoClock.rate)
        }
        set {
            audioClock.rate = Double(newValue)
            videoClock.rate = Double(newValue)
        }
    }
    public private(set) var duration: TimeInterval = 0          // 35
    public private(set) var fileSize: Int64 = 0                // 36 MediaPlayback.fileSize Int64 (bin field-record Int? UNCHECKED — kept Int64 per protocol)
    public private(set) var naturalSize: CGSize? = nil       // 37 ⚑[tool=field_surface ref=MEPlayerItem.naturalSize result=forward CGSize?; vpfi 0x100232cd4] — MEPlayerItem is not MediaPlayback
    // Forward didSet 0x101a4b20c only logs: "[MEPlayerItem] state change: " (0x103d36a20), oldValue,
    //   " -> ", state; #function "state", line 0xea. The delegate/timer calls live in send(_:)'s arms.
    private var state = State.idle {                         // 38 RESOLVED: nested MEPlayerItem.State (10 cases; desc @0x1039ef8b0, Model.swift). Was base MESourceState.
        didSet {
            KSLog("[MEPlayerItem] state change: \(oldValue) -> \(state)", line: 234)
        }
    }
    private var timer: Timer?                                // 39 Forward NSTimer? nil-init (base was `lazy var timer: Timer = .scheduledTimer`); scheduling site pending. Timer === NSTimer (reflection emits NSTimer)
    private let preloadClock = ContinuousClock()            // 40 ⚑ init calls Swift.ContinuousClock.init(); ContinuousClock vs .Instant pending
    private var lastPacketMediaType: AVFoundation.AVMediaType = .video // 41 init AVMediaTypeVideo (AVFoundation constant; codebase disambiguates from FFmpeg AVMediaType)

    nonisolated(unsafe) private static var onceInitial: Void = {
        var result = avformat_network_init()
        av_log_set_callback { ptr, level, format, args in
            guard let format else {
                return
            }
            var log = String(cString: format)
            let arguments: CVaListPointer? = args
            if let arguments {
                log = NSString(format: log, arguments: arguments) as String
            }
            if let ptr {
                let avclass = ptr.assumingMemoryBound(to: UnsafePointer<AVClass>.self).pointee
                if avclass == avfilter_get_class() {
                    let context = ptr.assumingMemoryBound(to: AVFilterContext.self).pointee
                    if let opaque = context.graph?.pointee.opaque {
                        let options = Unmanaged<KSOptions>.fromOpaque(opaque).takeUnretainedValue()
                        options.filter(log: log)
                    }
                }
            }
            // 找不到解码器
            if log.hasPrefix("parser not found for codec") {
                KSLog(level: .error, log)
            }
            KSLog(level: LogLevel(rawValue: level) ?? .warning, log)
        }
    }()

    public convenience init(url: URL, options: KSOptions) {
        self.init(io: .left(url), options: options)
    }

    // ⚑ Forward moved the per-stream FFmpegAssetTracks into FormatContext (FormatContext.swift:59 `assetTracks`
    //   @+0x40); MEPlayerItem's stored `assetTracks` field is removed. This computed bridge reads the migrated
    //   source so the external reader KSMEPlayer.tracks(mediaType:) stays green (Forward may instead read
    //   formatContext.assetTracks directly — resolved when KSMEPlayer.tracks migrates).
    var assetTracks: [FFmpegAssetTrack] { formatContext?.assetTracks ?? [] }

    // Forward 0x101a48884: four weak-self boxes, with closures in DynamicInfo field order. metadata is
    // 0x101a4b450 (formatContext+0x18 → AVFormatContext+0xc0 → toDictionary 0x101a07bd8). bytesRead is
    // 0x101a4b4c0: a state != .opening test, then ioContext as? PreLoadProtocol → witness +0x20
    // `bytesRead: UInt64` with a trapping Int64 conversion, otherwise pbArray PBClass.totalBytesRead
    // mapped and summed. audioBitrate/videoBitrate share merged body 0x101a4b7e0, parameterised by the
    // offset global 0x1044ea2e0 (audioTrack) or 0x1044ea2e8 (videoTrack). It returns track+0x80 (`bitrate`)
    // with no ×8 scaling.
    public lazy var dynamicInfo = DynamicInfo { [weak self] in
        toDictionary(self?.formatContext?.formatCtx.pointee.metadata)
    } bytesRead: { [weak self] in
        guard let self else {
            return 0
        }
        if self.state != .opening, let preload = self.formatContext?.ioContext as? PreLoadProtocol {
            return Int64(preload.bytesRead)
        }
        return self.pbArray.map(\.totalBytesRead).reduce(0, +)
    } audioBitrate: { [weak self] in
        self?.audioTrack?.bitrate ?? 0
    } videoBitrate: { [weak self] in
        self?.videoTrack?.bitrate ?? 0
    }

    // Forward 0x101a48b04 (1901 insns). `switch (state, event)`; every arm below is read from the
    // Forward body, including the three Task closures (open 0x101a4d168, read 0x101a4dba8 + its three
    // await funclets 0x101a4ed3c/0x101a4f9e0/0x101a50680, close 0x101a4cd88 + 0x101a4cf9c) and the
    // @MainActor timer closure 0x101a4bf20. All KSLog calls carry function "send(_:)" (#function inside
    // the closures too). The CapacityProtocol test `isEndOfFile && packetCount == 0 && frameCount == 0`
    // is Forward helper 0x1019e1b6c (PlayerDefines.swift, not in source) — written inline here.
    func send(_ event: MEPlayerItem.Event) {
        switch (state, event) {
        // Forward 0x101a4902c `cmp w22, #0x8`: the closed test reuses the state byte loaded for the switch
        // (w22), with no reload after the sourceDidFailed witness call — the switch-bound value. Local
        // binding names below are INFERRED.
        case let (current, .failed(error)):
            KSLog(level: .error, "[MEPlayerItem] failed error=\(error)", line: 520)
            delegate?.sourceDidFailed(error: error)
            if current != .closed {
                timer?.invalidate()
                timer = nil
                state = .failed
            }
        case (.idle, .open), (.endOfStream, .open), (.finished, .open), (.closed, .open), (.failed, .open):
            let symbols = Thread.callStackSymbols.prefix(8).joined(separator: "\n")
            print("[🔴 OPEN_TRACE] send(.open) from state=\(state)\n\(symbols)")
            state = .opening
            ioTask?.cancel()
            ioTask = Task(name: "KSPlayer-MEPlayerItem-open", priority: .userInitiated) { [weak self] in
                guard let self else {
                    return
                }
                if self.options.useSystemHTTPProxy {
                    setHttpProxy()
                }
                do {
                    try self.openAndFindStream()
                    if self.videoTrack == nil, self.audioTrack == nil {
                        self.send(.failed(KSPlayerError(errorCode: .noStream)))
                    } else if self.state == .opening {
                        self.send(.opened)
                    }
                } catch {
                    if let error = error as? KSPlayerError, error.code == swift_AVERROR_EOF {
                        if self.state == .opening {
                            self.state = .finished
                            self.delegate?.sourceDidFinished()
                        }
                        return
                    }
                    self.send(.failed(error))
                }
            }
        case (.ready, .startReading), (.seeking, .startReading):
            ioTask?.cancel()
            ioTask = Task(name: "KSPlayer-MEPlayerItem-read", priority: .medium) { [weak self] in
                guard let self else {
                    return
                }
                KSLog("[MEPlayerItem] reading loop start", line: 351)
                if self.state == .ready {
                    if self.options.startPlayTime > 0, self.duration > self.options.startPlayTime {
                        for track in self.formatContext?.assetTracks ?? [] where track.mediaType == .video && track.isEnabled {
                            // 0xad = AV_CODEC_ID_HEVC; 244 = AV_PROFILE_H264_HIGH_444_PREDICTIVE (C #define,
                            // not bridged — same literal KSOptions.process(assetTrack:) uses).
                            if track.codecpar.pointee.codec_id == AV_CODEC_ID_HEVC || track.codecpar.pointee.profile == 244 {
                                _ = self.reading()
                            }
                            break
                        }
                        self.needSeekItemTrack = false
                        self.send(.seek(to: self.options.startPlayTime, useCache: false, completion: nil))
                    } else if self.isPreload {
                        self.state = .paused
                    }
                    if !self.isPreload, self.state == .ready {
                        self.state = .reading
                    }
                }
                if !self.isPreload {
                    self.allPlayerItemTracks.forEach { $0.decode() }
                }
                var waitCount = 0
                while self.state == .reading || self.state == .seeking || self.state == .paused, !Task.isCancelled {
                    self.interrupt = false
                    switch self.state {
                    case .reading:
                        _ = autoreleasepool {
                            self.reading()
                        }
                    case .seeking:
                        autoreleasepool {
                            self.performSeek()
                        }
                        if self.isPreload {
                            self.state = .paused
                        }
                    case .paused:
                        if let preload = self.formatContext?.ioContext as? PreLoadProtocol {
                            if (self.formatContext?.assetTracks ?? []).contains(where: { $0.mediaType == .video && !$0.isImage }), self.lastPacketMediaType != .video {
                                _ = autoreleasepool {
                                    self.reading()
                                }
                            } else {
                                let more = autoreleasepool {
                                    preload.more()
                                }
                                if more > 0 {
                                    waitCount = 0
                                } else if self.state == .paused {
                                    self.formatContext?.pause()
                                    if more != 0, waitCount < 30 {
                                        try? await Task.sleep(for: .milliseconds(100))
                                        self.formatContext?.play()
                                        waitCount += 1
                                    } else {
                                        await withCheckedContinuation { continuation in
                                            self.ioWaiterLock.lock()
                                            if self.state == .paused {
                                                self.ioWaiter = continuation
                                                self.ioWaiterLock.unlock()
                                            } else {
                                                self.ioWaiterLock.unlock()
                                                continuation.resume()
                                            }
                                        }
                                        self.formatContext?.play()
                                        waitCount = 0
                                    }
                                }
                            }
                        } else {
                            self.formatContext?.pause()
                            await withCheckedContinuation { continuation in
                                self.ioWaiterLock.lock()
                                if self.state == .paused {
                                    self.ioWaiter = continuation
                                    self.ioWaiterLock.unlock()
                                } else {
                                    self.ioWaiterLock.unlock()
                                    continuation.resume()
                                }
                            }
                            self.formatContext?.play()
                        }
                    default:
                        break
                    }
                }
                KSLog("[MEPlayerItem] reading loop stop state=\(self.state), isCancelled=\(Task.isCancelled)", line: 433)
            }
        case (.reading, .pause):
            state = .paused
        case (.paused, .pause), (.endOfStream, .pause):
            break
        case (.paused, .resume):
            state = .reading
            ioWaiterLock.lock()
            let waiter = ioWaiter
            ioWaiter = nil
            ioWaiterLock.unlock()
            waiter?.resume()
        case (.ready, .resume), (.reading, .resume), (.seeking, .resume), (.endOfStream, .resume), (.closed, .resume), (.failed, .resume):
            break
        case (.reading, .endOfStream), (.paused, .endOfStream):
            allPlayerItemTracks.forEach { $0.isEndOfFile = true }
            if isPreload {
                KSLog("[MEPlayerItem] preload mode received EOF, pausing instead of finishing", line: 464)
                state = .paused
                return
            }
            if !options.isLoopPlay {
                state = .endOfStream
                delegate?.sourceDidEOF()
                if let track = videoAudioTracks.first, track.isEndOfFile, track.packetCount == 0, track.frameCount == 0 {
                    send(.trackFinished(track))
                }
            } else if allPlayerItemTracks.contains(where: { $0.isLoopModel }) {
                send(.pause)
            } else {
                allPlayerItemTracks.forEach { $0.isLoopModel = true }
                _ = formatContext?.performSeek(time: 0.0, flags: 1)
            }
        case (.closed, .endOfStream):
            break
        case (.closed, .close):
            break
        case (_, .close):
            timer?.invalidate()
            timer = nil
            state = .closed
            #if canImport(UIKit)
            NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            #endif
            ioWaiterLock.lock()
            let waiter = ioWaiter
            ioWaiter = nil
            ioWaiterLock.unlock()
            waiter?.resume()
            Task(name: "KSPlayer-MEPlayerItem-close", priority: .userInitiated) {
                if self.options.syncDecodeVideo || self.options.syncDecodeAudio {
                    self.allPlayerItemTracks.forEach { $0.shutdown() }
                }
                if let ioTask = self.ioTask {
                    ioTask.cancel()
                    await ioTask.value
                }
                self.ioTask = nil
                self.closeResources()
            }
        case (.opening, .opened):
            state = .ready
            send(.startReading)
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.timer?.invalidate()
                // Timer block 0x101a5a0cc → 0x101a4c244 (weak self, !isPreload, runOnMainThread) →
                // 0x101a5a0f0 → 0x101a4c450 (`self?.tick`) → Forward 0x101a4c4a4, the tick body, written
                // as `codecDidChangeCapacity()`. Name INFERRED from this closure's own log literal.
                let timer = Timer.scheduledTimer(withTimeInterval: self.options.playbackTimeInterval, repeats: true) { [weak self] _ in
                    guard let self, !self.isPreload else {
                        return
                    }
                    runOnMainThread { [weak self] in
                        self?.codecDidChangeCapacity()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                timer.tolerance = 0.01
                timer.fireDate = Date.distantPast
                self.timer = timer
                KSLog("star codecDidChangeCapacity timer", line: 344)
            }
            delegate?.sourceDidOpened()
        // Forward tests the switch-loaded state against the static array 0x1044ea2d0 = [6, 3, 5]
        // (.endOfStream, .reading, .paused), one byte at a time — an array-literal `contains` in a where clause.
        case let (current, .trackFinished(track)) where [State.endOfStream, .reading, .paused].contains(current):
            if track.mediaType == .audio {
                isAudioStalled = true
            }
            if videoAudioTracks.allSatisfy({ $0.isEndOfFile && $0.packetCount == 0 && $0.frameCount == 0 }) {
                if options.isLoopPlay {
                    isAudioStalled = audioTrack == nil
                    allPlayerItemTracks.forEach { $0.isLoopModel = false }
                    var message = "[MEPlayerItem] loop play trackFinished"
                    if let audioTrack {
                        message += ",audioTrackPacketCount=\(audioTrack.packetCount)"
                    }
                    if let videoTrack {
                        message += ",videoTrackPacketCount=\(videoTrack.packetCount)"
                    }
                    KSLog(message, line: 510)
                } else {
                    state = .finished
                    timer?.fireDate = Date.distantFuture
                }
                delegate?.sourceDidFinished()
            }
        case (.finished, .trackFinished):
            break
        // Forward 0x101a48c90..0x101a48cb0: the switch-loaded state vs the static array 0x1044ea318 =
        // [2, 3, 5, 4] (.ready, .reading, .paused, .seeking), `uxtl`/`cmeq`/`umaxv` — array-literal `contains`
        // in a where clause. The later `== .seeking` / `== .paused` tests reuse that same byte (no reload).
        case let (oldState, .seek(time, useCache, completion)) where [State.ready, .reading, .paused, .seeking].contains(oldState):
            seekTime = time
            if oldState == .seeking {
                seekingCompletionHandler?(false)
            }
            seekUsePacketCache = useCache
            seekingCompletionHandler = completion
            state = .seeking
            if oldState == .paused {
                ioWaiterLock.lock()
                let waiter = ioWaiter
                ioWaiter = nil
                ioWaiterLock.unlock()
                waiter?.resume()
            }
        case (.endOfStream, let .seek(time, useCache, completion)), (.finished, let .seek(time, useCache, completion)):
            seekTime = time
            state = .seeking
            seekUsePacketCache = useCache
            seekingCompletionHandler = completion
            timer?.fireDate = Date.distantPast
            send(.startReading)
            isAudioStalled = audioTrack == nil
        case (.failed, let .seek(time, _, completion)):
            options.startPlayTime = time
            seekingCompletionHandler = completion
            send(.open)
        default:
            KSLog(level: .error, "unhandled event=\(event) in state=\(state). Please send me the assertion information so that I can see if there is a problem with the state machine.", line: 557)
        }
    }

    // field 42 — after `$__lazy_storage_$_dynamicInfo` (41) in the field record.
    // ⚑[tool=field_surface ref=MEPlayerItem.delegate result=forward index 42]
    // Forward setter 0x101a482e0 carries a didSet: after the weak assign it reloads the delegate and,
    //   when state is in the static set 0x1044ea258 = [2, 3, 4, 5] (.ready, .reading, .seeking, .paused)
    //   and !isPreload, calls witness slot +0x10 = req1 sourceDidOpened().
    public weak var delegate: MEPlayerDelegate? {
        didSet {
            if let delegate, [State.ready, .reading, .seeking, .paused].contains(state), !isPreload {
                delegate.sourceDidOpened()
            }
        }
    }

    /// ⚑[tool=disassemble ref=MEPlayerItem.isReusable.getter:0x101a4b404 result=19-instr]
    /// Same `state` load, then a five-way set-membership test in the shape the compiler uses for a
    /// multi-case `switch`: four constants compared at once via `cmeq.4h` against the vector at
    /// 0x1044ea360, plus the fifth as a scalar at +0x4. Those five bytes read `01 02 03 04 05`.
    /// Against `MEPlayerItem.State` that is opening/ready/reading/seeking/paused — every state
    /// between `.idle` and the terminal group, which is what makes the name coherent.
    /// ⚑ The five are contiguous, and a multi-case `switch` compiles to the range test
    /// (`sub #1; cmp #5; cset lo`) the build shows. Forward's lane compare against five bytes
    /// held in data is the specialized `Array.contains` over a constant literal, so that form is
    /// written here.
    public var isReusable: Bool {
        [State.opening, .ready, .reading, .seeking, .paused].contains(state)
    }
}

// MARK: private functions

extension MEPlayerItem {
    // openAndFindStream() — the open/find/WIRE path (the read loop is readThread/reading). FAITHFUL-PARTIAL:
    //   the interrupt closure + openFormatContext/FormatContext wiring + fileSize/duration/formatName/chapters
    //   + the createCodec call are reconstructed; the leading KSLog, close/reset call, custom-AVIO install,
    //   pbArray append, io.right AVIO path, and KSOptions rate×duration store are flagged // ⚑ UNRESOLVED.
    // ⚑[tool=recover_swift_function_name ref=openAndFindStream:0x101a4d3d0 result=#function/throws/no-params]
    private func openAndFindStream() throws {
        KSLog("[MEPlayerItem] openAndFindStream", line: 627) // level 3 (.warning default), `2 < logLevel` gate; line 0x273
        closeFormatContext() // 0x101a531fc @0x101a4d584

        // ⚑ the binary does NOT project `io` here — it hands the WHOLE Either to openFormatContext:
        //   `bl 0x10002e588` @0x101a4d5a8 copies `self.io` into a stack alloca, `mov x0,x26` @0x101a4d618 passes
        //   the alloca pointer, and the throw path destroys it with the SAME cache/name pair
        //   (0x1044e4778 / 0x103566d40 = Either<URL, AbstractAVIOContext>) @0x101a4d64c. The projection switch
        //   that used to stand here is REMOVED — the projection lives inside openFormatContext.

        // Interrupt callback — FAITHFUL. A `{ [weak self] }` closure (compiler HeapLocalVariable box, metadata
        //   kind 0x400 — NOT a user class): abort blocking IO when self is gone, an interrupt was requested, or
        //   state is terminal ((state & 0xfe)==8 ≡ .closed || .failed).
        //   ⚑[tool=read_memory ref=weakSelfBox:0x1041d8340 result=HeapLocalVariable/[weak self]]
        //   ⚑[tool=decompile ref=interruptTrampoline:0x101a534e0 result=self==nil||interrupt||terminal]
        let interruptContext = IOInterruptContext { [weak self] in
            guard let self else { return true }
            if self.interrupt { return true }
            return self.state == .closed || self.state == .failed
        }

        // ⚑ call site @0x101a4d630, arguments MEASURED @0x101a4d618-2c: `mov x0,x26`(the io copy),
        //   `mov x1,x24`(the IOInterruptContext built at 0x101a4d610), `mov x2,x23`(self.options via field-offset
        //   global 0x104c63690), `mov x3,#0`/`mov x4,#0`(inFormat nil), `mov x21,x25`(swifterror). NO d0 is set —
        //   `time: 0` was the Ghidra `double param_1` phantom and is REMOVED.
        //   ⚑[tool=llvm-objdump ref=openFormatContext:0x101a392a0 result=3-TUPLE-RETURN]
        let (formatCtx, fileSize, ioContext) = try openFormatContext(io: io, interrupt: interruptContext,
                                                                     options: options, inFormat: nil)

        // FormatContext init. The former `duration: 0` argument is GONE — it satisfied a phantom
        //   `double param_1` that Ghidra's default __swiftcall prototype prepends; the trie, the
        //   prologue @0x101a350e8-fc and every call site all give five parameters, no `duration:`.
        //   RESOLVED: the `fileSize: 0` / `ioContext: nil` placeholders are gone. The three returns are
        //   destructured at 0x101a4d66c-74 (`mov x25,x0` / `mov x27,x1` / `mov x20,x2`).
        let formatContext = FormatContext(formatCtx: formatCtx, fileSize: fileSize,
                                          interrupt: interruptContext, ioContext: ioContext,
                                          fontsDir: options.fontsDir)
        self.formatContext = formatContext

        // Custom-AVIO install (unconditional) — save + BOX the format context's default io_open/io_close2
        //   into defaultIOOpen/defaultIOClose (each a Swift closure that captures the original C fn-ptr and
        //   forwards to it — the compiler emits the boxed-closure thin entry, storing the captured fn-ptr in
        //   the box), stash self in the format context's opaque, and install our two @convention(c) thunks
        //   (ioOpen/ioClose are context-free statics → the compiler emits the matching adapters). The
        //   AVFormatContext fields are accessed symbolically; `formatCtx` is the AVFormatContext* the
        //   FormatContext wraps (== the openFormatContext local, stored at FormatContext+0x18). Order matches
        //   the binary: box io_open → opaque=self → io_open thunk → box io_close2 → io_close2 thunk.
        // ⚑[tool=decompile ref=customAVIOInstall:0x101a4d3d0 result=saves formatCtx.io_open@+0x1c0/io_close2@+0x1c8 (boxed→defaultIOOpen/Close), opaque@+0x1a0=self, installs the ioOpen/ioClose thunks]
        // ⚑[tool=decompile ref=boxTrampolineOpen:0x101a5a0c4 result=io_open boxed-closure thin-entry: loads captured fn-ptr @box+0x10 and forwards]
        // ⚑[tool=decompile ref=boxTrampolineClose:0x101a5a0bc result=io_close2 boxed-closure thin-entry]
        // ⚑[tool=decompile ref=ioOpenThunk:0x101a53560 result=@convention(c) adapter the compiler emits for MEPlayerItem.ioOpen]
        // ⚑[tool=decompile ref=ioCloseThunk:0x101a53924 result=@convention(c) adapter for MEPlayerItem.ioClose]
        if let defaultOpen = formatCtx.pointee.io_open {
            defaultIOOpen = { s, pb, url, flags, options in defaultOpen(s, pb, url, flags, options) }
        } else {
            defaultIOOpen = nil
        }
        formatCtx.pointee.opaque = Unmanaged.passUnretained(self).toOpaque()
        formatCtx.pointee.io_open = ioOpen
        if let defaultClose = formatCtx.pointee.io_close2 {
            defaultIOClose = { s, pb in defaultClose(s, pb) }
        } else {
            defaultIOClose = nil
        }
        formatCtx.pointee.io_close2 = ioClose
        // pbArray append + preload tuning (PBClass alloc 0x101a5a030; dynamicCast to PreLoadProtocol existential 0x1039ede48)
        if let ioContext = formatContext.ioContext {
            pbArray.append(PBClass(pb: formatCtx.pointee.pb))
            if ioContext is PreLoadProtocol {
                options.playbackTimeInterval = 0.02 // KSOptions+0x50 = 0x3f947ae147ae147b
                options.seekUsePacketCache = false
                options.formatContextOptions["cues_parsing_deferred"] = 0
            }
        }

        options.formatName = formatContext.formatName        // String @+0x48 (DERIVED from iformat.name)
        // Forward re-reads self.formatContext (optional, nil → 0) for these three reads.
        self.fileSize = self.formatContext?.fileSize ?? 0     // +0x30
        self.duration = self.formatContext?.duration ?? 0     // +0x28
        if options.startPlayTimePercentage > 0 {              // KSOptions+0x38 → +0x30
            options.startPlayTime = options.startPlayTimePercentage * (self.formatContext?.duration ?? 0)
        }
        self.chapters = formatContext.chapters()             // FormatContext.chapters() @0x101a362d0 (method, trie ...C8chaptersSayAA7ChapterVGyF)

        //   ⚑[tool=get_xrefs_to ref=createCodec:0x101a53c44 result=argless]
        createCodec()                                        // track-set builder (argless, reads self.formatContext; slice-1 reconstructed)
    }

    // FUN_101a531fc — callers openAndFindStream @0x101a4d584 and FUN_101a4cfe4. ⚑ name INFERRED.
    //   Drops the top-level pb from pbArray, closes the FormatContext, then frees every remaining sub-context.
    private func closeFormatContext() {
        if let index = pbArray.firstIndex(where: { $0.pb == formatContext?.formatCtx.pointee.pb }) {
            pbArray.remove(at: index)
        }
        formatContext?.close() // 0x101a3302c
        formatContext = nil
        for pbClass in pbArray {
            if let pb = pbClass.pb {
                if pb.pointee.buffer != nil {
                    av_freep(&pb.pointee.buffer)
                }
                avio_context_free(&pbClass.pb)
            }
        }
        pbArray = []
    }

    // createCodec() = FUN_101a53c44 (~2145 lines w/ 3 inline closures FUN_101a556b0/36964/36cf0). ARGLESS —
    //   reads self.formatContext (the commit-1 `formatCtx:` param was the BASE signature; Forward is argless).
    //   Being reconstructed in SLICES (this body is too large/intricate for one reliable partial). SLICE 1 =
    //   the reset prologue + formatContext nil-guard + the isAudioStalled tail; the track-BUILD, rotation/
    //   filter, and adaptation arms are flagged // ⚑ UNRESOLVED for their own slices.
    // ⚑[tool=get_xrefs_to ref=createCodec:0x101a53c44 result=argless/self.formatContext]
    private func createCodec() {
        // Reset prologue (FUN_101a53c44 @0x101a53d?-53e?): clear the adaptation + track fields, shutdown existing tracks.
        videoAdaptation = nil
        videoTrack = nil
        audioTrack = nil
        videoAudioTracks = []
        allPlayerItemTracks.forEach { $0.shutdown() }   // witness+0x80 = PlayerItemTrackProtocol.shutdown()
        createSubtitleTracks() // FUN_101a556b0 @0x101a53db4, before the formatContext nil check
        guard formatContext != nil else { return } // cbz @0x101a53dc4

        // ⚑ UNRESOLVED (SLICE 3 — audio, closures FUN_101a36964/36cf0 + tail): audio sample-rate sampling
        //   (audioStreamBasicDescription) + max-reduction + the KSOptions.vtable[0x6f8] call + AudioPlayerItemTrack
        //   (FUN_101a383a8/33444) construction.
        // ⚑ UNRESOLVED (SLICE 4 — rotation/filter): isRotateByFilter → transpose_vt/videoFilters/hardwareDecode/
        //   asynchronousDecompression + the 90°-rotation angle math.
        // ⚑ UNRESOLVED (SLICE 5 — adaptation): videoAdaptation rebuild + naturalSize.

        isAudioStalled = false   // tail (@0x101a55d??): *(self + ::isAudioStalled) = 0, unconditional on the non-nil path
    }

    // FUN_101a556b0 — ⚑ name INVENTED. Reads the nil-tolerant `assetTracks` (twice). Every track is disabled;
    //   image subtitles share one AsyncPlayerItemTrack (cap 8, init 0x101a3839c @0x101a55a0c, w3=0), text
    //   subtitles are re-enabled (`str wzr,[stream,#0x44]` @0x101a558ec) and get a Sync track (cap 128, w3=1).
    private func createSubtitleTracks() {
        allPlayerItemTracks = []
        for track in assetTracks {
            track.isEnabled = false
            if track.mediaType == .subtitle {
                if track.isImageSubtitle {
                    if subtitleTrack == nil {
                        let subtitle = AsyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 8, options: options, expanding: false)
                        allPlayerItemTracks.append(subtitle)
                        subtitle.delegate = self
                        subtitleTrack = subtitle
                    }
                    track.subtitle = subtitleTrack
                } else {
                    track.isEnabled = true
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                    subtitle.delegate = self
                    track.subtitle = subtitle
                    allPlayerItemTracks.append(subtitle)
                }
            }
        }
        // 2nd pass: FUN_101aaf12c cast, KSOptions vtable+0x768 = wantedSubtitle(tracks:), witness +0x40 (isEnabled.set) w0=1
        let subtitleInfos: [any SubtitleInfo] = assetTracks.filter { $0.mediaType == .subtitle }
        options.wantedSubtitle(tracks: subtitleInfos)?.isEnabled = true
    }

    private func read() {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed readOperation/operationQueue (BlockOperation on
        //   an OperationQueue). Forward drives reading via `ioTask: Task` (field 4). Deferred to the read/ioTask
        //   migration commit.
    }

    private func readThread() {
        // ⚑ UNRESOLVED (commit-1 stub): base body used removed formatCtx/startTime/seekByBytes/condition (the
        //   OperationQueue read+seek loop). Forward's read loop runs under `ioTask: Task` with `ioWaiter:
        //   CheckedContinuation` + `ioWaiterLock: NSLock` for suspension. See `reading()` for the characterized
        //   ioTask-driven read-loop cluster (driver / error-handler / reconnect). Deferred to Stage-2 DEEP.
    }

    /// Forward 0x101a512b4, called from the read loop in send(_:). One Packet per call: av_read_frame,
    /// closed/corrupt guard, error → read(errorCode:) 0x101a5685c, then dispatch by the matching
    /// FFmpegAssetTrack (trackID == stream_index) to videoTrack/audioTrack (vtable +0x1a0 putPacket)
    /// or the track's own subtitle track.
    private func reading() -> Int32 {
        let packet = Packet()
        guard let corePacket = packet.corePacket else {
            return 0
        }
        let readResult = av_read_frame(formatContext?.formatCtx, corePacket)
        if state == .closed || corePacket.pointee.flags & AV_PKT_FLAG_CORRUPT != 0 {
            return 0
        }
        if readResult != 0 {
            if !interrupt, state == .reading {
                read(errorCode: readResult)
            }
            return readResult
        }
        if corePacket.pointee.size <= 0 {
            return 0
        }
        let first = (formatContext?.assetTracks ?? []).first { $0.trackID == corePacket.pointee.stream_index }
        if let first, first.isEnabled {
            if let formatContext, formatContext.seekByBytes, formatContext.byteSeek,
               let playList = formatContext.ioContext as? PlayList, playList.currentStream != nil
            {
                if corePacket.pointee.dts > 0 {
                    var position = corePacket.pointee.pos
                    if position < 0 {
                        position = prePosition
                    }
                    if position > 0, fileSize > 0, (self.formatContext?.duration ?? 0) > 0 {
                        for _ in playList.playlists {
                            // ⚑ GAP (PlayerDefines.swift MovieStream): Forward reads MovieStream witness
                            //   +0x20 (Int64 byte offset) per stream and takes the first with position < it,
                            //   compares CMTime(value: dts * tb.num, timescale: tb.den).seconds / duration
                            //   with Double(position) / Double(fileSize); when they differ by more than 0.01
                            //   it reads currentStream's witness +0x8 (Double), converts it to a timestamp
                            //   delta (value * den / num), adds it to dts and pts, then breaks.
                            //   MovieStream declares no requirements, so the loop body cannot be written.
                        }
                    }
                    prePosition = position
                }
            }
            packet.assetTrack = first
            lastPacketMediaType = first.mediaType
            if first.mediaType == .video {
                if options.readVideoTime == 0 {
                    options.readVideoTime = CACurrentMediaTime()
                }
                videoTrack?.putPacket(packet: packet)
            } else if first.mediaType == .audio {
                if options.readAudioTime == 0 {
                    options.readAudioTime = CACurrentMediaTime()
                }
                audioTrack?.putPacket(packet: packet)
            } else if first.mediaType == .subtitle {
                first.subtitle?.putPacket(packet: packet)
            }
        }
        return 0
    }

    /// Forward 0x101a5685c, the read-error handler; sole caller of reconnect(). The name is
    /// Forward-evidenced by its #function literal "read(errorCode:)" (0x103d36ba0). ⚑ Access INFERRED
    /// (`private final`, brief's new-helper rule; no discriminator read).
    private final func read(errorCode: Int32) {
        let isEOF = avio_feof(formatContext?.formatCtx.pointee.pb) > 0
        var log = "[MEPlayerItem] readFrame fail isLive=\(isLive),isEOF=\(isEOF),code=\(errorCode),message=\(KSPlayerError(code: errorCode).localizedDescription)"
        if let audioTrack {
            log += ",audioTrackPacketCount=\(audioTrack.packetCount)"
        }
        if let videoTrack {
            log += ",videoTrackPacketCount=\(videoTrack.packetCount)"
        }
        KSLog(level: .error, log, line: 1030)
        if errorCode == swift_AVERROR_EOF || isEOF {
            let time = CACurrentMediaTime() - options.findTime
            if isLive, options.formatContextOptions["reconnect_at_eof"] as? Int != 1, time > 5 {
                reconnect()
            } else {
                send(.endOfStream)
            }
        } else {
            if errorCode == -EIO || errorCode == -ETIMEDOUT {
                if isLive {
                    reconnect()
                    return
                }
            } else if errorCode == KSPlayerError.tryAgain.code {
                return
            }
            send(.failed(KSPlayerError(errorCode: .readFrame, avErrorCode: errorCode)))
        }
    }

    /// Forward 0x101a56ecc. The name is Forward-evidenced by its #function literal "reconnect()".
    /// Logs the empty string literal, reopens, then restarts every track (witness +0x58 decode).
    /// ⚑ Access INFERRED (`private final`, brief's new-helper rule).
    private final func reconnect() {
        KSLog("", line: 1054)
        do {
            try openAndFindStream()
            allPlayerItemTracks.forEach { $0.decode() }
        } catch {
            if let error = error as? KSPlayerError, error.code == swift_AVERROR_EOF {
                send(.endOfStream)
            } else {
                send(.failed(error))
            }
        }
    }

    private func pause() {
        if state == .reading {
            state = .paused
        }
    }

    private func resume() {
        // ⚑ UNRESOLVED (commit-1 stub): base set state=.reading + signalled the removed `condition` (NSCondition).
        //   Forward resumes the read loop via `ioWaiter: CheckedContinuation` + `ioWaiterLock`. Deferred to the
        //   read-loop migration commit.
    }

    /// Forward 0x101a4cfe4 (91 insns), called only from the `.close` Task closure (0x101a4cf9c) in
    /// `send(_:)`. The body is read from Forward: shutdown witness +0x80 per track, `closeFormatContext()`
    /// (0x101a531fc), then the remuxer writeTrailer/stop/nil triple (0x101a1b8d4/0x101a1bb5c), then
    /// `MEPlayerDelegate.sourceDidClear()` (witness +0x38).
    /// ⚑ INFERRED name: no symbol and no #function literal. `private final` follows the brief's
    ///   new-helper rule; there is no private discriminator to confirm the access level.
    private final func closeResources() {
        allPlayerItemTracks.forEach { $0.shutdown() }
        closeFormatContext()
        if let remuxer {
            remuxer.outputStreamInfo.writeTrailer()
            remuxer.outputStreamInfo.stop()
        }
        remuxer = nil
        delegate?.sourceDidClear()
    }

    /// Forward 0x101a51e98. The name is Forward-evidenced by its own #function literal "performSeek()".
    /// It is called from the read-loop `.seeking` arm in `send(_:)`, inside an autoreleasepool.
    /// Memory seek first (0x101a55de4 with mediaType nil); on success both clocks jump to the target
    /// with the main clock's timescale and the state becomes `.paused`. Otherwise avformat_seek_file,
    /// by bytes (AVSEEK_FLAG_BYTE) when FormatContext.seekByBytes && byteSeek, else in AV_TIME_BASE
    /// units offset by FormatContext.startTime, with one BACKWARD-less retry.
    private final func performSeek() {
        let seekToTime = seekTime
        let time = mainClock().time
        if usePacketCacheSeek(to: seekToTime, mediaType: nil) {
            audioClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale)
            videoClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale)
            state = .paused
            seekingCompletionHandler?(true)
            seekingCompletionHandler = nil
            KSLog("[seek] memory seek success to \(seekToTime)", line: 821)
            return
        }
        KSLog("[seek] memory seek failed, fallback to disk/network seek to \(seekToTime)", line: 824)
        var increase = Int64(seekTime - time.seconds)
        var seekFlags = options.seekFlags
        let timeStamp: Int64
        if let formatContext, formatContext.seekByBytes, formatContext.byteSeek {
            seekFlags |= AVSEEK_FLAG_BYTE
            if fileSize > 0, duration > 0 {
                timeStamp = Int64(seekToTime * Double(fileSize) / duration)
            } else {
                increase = increase * (formatContext.formatCtx.pointee.bit_rate / 8)
                var position = videoClock.position
                if position < 0 {
                    position = audioClock.position
                    if position < 0 {
                        position = avio_seek(formatContext.formatCtx.pointee.pb, 0, SEEK_CUR)
                    }
                }
                timeStamp = position + increase
            }
        } else {
            increase *= Int64(AV_TIME_BASE)
            timeStamp = Int64((time + (formatContext?.startTime ?? .zero)).seconds) * Int64(AV_TIME_BASE) + increase
        }
        let seekMax = increase < 0 ? timeStamp - increase - 2 : Int64.max
        KSLog("currentPlaybackTime=\(time) will seek to \(seekToTime)", line: 860)
        let seekStartTime = CACurrentMediaTime()
        if let formatContext {
            if String(cString: formatContext.formatCtx.pointee.url).hasPrefix("/") {
                formatContext.formatCtx.pointee.ctx_flags ^= AVFMTCTX_UNSEEKABLE
            }
        }
        var result = avformat_seek_file(formatContext?.formatCtx, -1, Int64.min, timeStamp, seekMax, seekFlags)
        if result < 0, seekFlags & AVSEEK_FLAG_BACKWARD != 0 {
            KSLog("seek to \(seekToTime) failed. seekFlags remove BACKWARD", line: 874)
            options.seekFlags &= ~AVSEEK_FLAG_BACKWARD
            seekFlags &= ~AVSEEK_FLAG_BACKWARD
            result = avformat_seek_file(formatContext?.formatCtx, -1, Int64.min, timeStamp, seekMax, seekFlags)
        }
        KSLog("seek to \(seekToTime) result=\(result),spendTime=\(CACurrentMediaTime() - seekStartTime)", line: 879)
        if state == .closed {
            seekingCompletionHandler?(false)
            seekingCompletionHandler = nil
            return
        }
        guard seekToTime == seekTime else {
            return
        }
        isSeek = true
        if formatContext?.ioContext as? PreLoadProtocol != nil {
            needRecordTimeIndex = true
        }
        for track in allPlayerItemTracks {
            if needSeekItemTrack || track.mediaType == .subtitle {
                track.seek(time: seekToTime)
            }
        }
        needSeekItemTrack = true
        audioClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale)
        videoClock.time = CMTime(seconds: seekToTime, preferredTimescale: time.timescale)
        state = .reading
        seekingCompletionHandler?(result >= 0)
        seekingCompletionHandler = nil
    }

    /// Forward 0x101a55de4. The name and labels are Forward-evidenced by its #function literal
    /// "usePacketCacheSeek(to:mediaType:)" (0x103d36b40). Callers: performSeek (mediaType nil) and the
    /// wrapper 0x101a48158. Log literal "use packet cache seek " (0x103d36b20); lines 914/918/958.
    /// Audio arm: audioTrack vtable +0x1b0 seekCache(time: time + 0.05, needKeyFrame: false), then
    /// +0x1b8 updateCache(headIndex:time:) with the ORIGINAL time. General arm: video (needKeyFrame
    /// true), audio at the video cache time, then enabled subtitle tracks; each hit is stored as
    /// (track, PlayerItemTrackProtocol witness 0x1041d89b0, index, time), and the final loop calls
    /// witness +0x70 per entry.
    /// ⚑ Access INFERRED (`private final`, brief's new-helper rule; no discriminator read).
    private final func usePacketCacheSeek(to time: TimeInterval, mediaType: AVFoundation.AVMediaType?) -> Bool {
        var log = "use packet cache seek \(time)"
        if mediaType == .audio {
            log = "[audio] " + log
            if let audioTrack, let cache = audioTrack.seekCache(time: time + 0.05, needKeyFrame: false) {
                log += " to \(cache.1)"
                audioTrack.updateCache(headIndex: cache.0, time: time)
                log += " success"
                KSLog(log, line: 914)
                return true
            }
            log += " failed"
            KSLog(log, line: 918)
            return false
        }
        var caches = [(PlayerItemTrackProtocol, UInt, TimeInterval)]()
        var seekTime = time
        if let videoTrack {
            guard let cache = videoTrack.seekCache(time: time, needKeyFrame: true) else {
                return false
            }
            caches.append((videoTrack, cache.0, cache.1))
            seekTime = cache.1
        }
        if let audioTrack {
            guard let cache = audioTrack.seekCache(time: seekTime, needKeyFrame: false) else {
                return false
            }
            caches.append((audioTrack, cache.0, cache.1))
        }
        for track in formatContext?.assetTracks ?? [] {
            if track.isEnabled, let subtitle = track.subtitle {
                if track.isImageSubtitle {
                    if let cache = subtitle.seekCache(time: seekTime, needKeyFrame: false) {
                        caches.append((subtitle, cache.0, cache.1))
                    }
                } else {
                    // ⚑ GAP (CircularBuffer.swift): Forward inlines a CircularBuffer method on
                    //   subtitle.outputRenderQueue (+0x58) here: condition.lock(); headIndex = 0;
                    //   condition.signal(); condition.unlock(). Both fields are private and the method
                    //   (vtable F28, dead slot) is lane 11's decl.
                }
            }
        }
        for (track, index, cacheTime) in caches {
            // Forward 0x101a56504: PlayerItemTrackProtocol witness +0x70 with v0 = v8 (the `time` parameter).
            track.updateCache(headIndex: index, time: time)
            log += " \(track.mediaType.rawValue) \(cacheTime)"
        }
        KSLog(log, line: 958)
        return true
    }
}

// MARK: MediaPlayback

extension MEPlayerItem {
    /// The four-arm predicate below is READ, not designed. It is transcribed from
    /// `KSMEPlayer.sourceDidOpenedSync()` @0x101a3bd64, whose statement 2 assigns
    /// `KSMEPlayer.seekable` (offset global 0x1044ea148) from an expression over
    /// `playerItem.formatContext` (0x1044ea218):
    ///   101a3be50  cbz x8, 0x101a3be74      formatContext == nil            -> false
    ///   101a3be54  ldr x9, [x8, #0x18]      FormatContext.formatCtx
    ///   101a3be58  ldr x9, [x9, #0x20]      AVFormatContext.pb
    ///   101a3be5c  cbz x9, 0x101a3be6c      pb == nil                       -> true
    ///   101a3be60  ldr w9, [x9, #0x90]      AVIOContext.seekable
    ///   101a3be64  cmp w9, #0x1 / b.lt      seekable >= 1                   -> true
    ///   101a3be7c  ldr d0, [x8, #0x28]      FormatContext.duration != 0.0   -> the result
    ///
    /// `formatCtx` is dereferenced with NO nil test, which is why it is spelled unwrapped here —
    /// and the declaration agrees: FormatContext.swift:63 declares it non-optional
    /// `UnsafeMutablePointer<AVFormatContext>` at +0x18. `duration` is +0x28, likewise declared.
    /// The FFmpeg offsets are named, not numeric: pb is AVFormatContext's fifth pointer field and
    /// seekable is AVIOContext's, both from this build's own headers.
    /// ⚑[tool=recover_field_offsets ref=MEPlayerItem.formatContext:0x1044ea218 result=named-via-sibling-reader]
    ///
    /// ⚠️ ONE INFERENCE, FLAGGED RATHER THAN HIDDEN. The predicate was read from an INLINED copy.
    /// No standalone `seekable` symbol exists in MEPlayerItem's trie subtree, so this getter is
    /// presumed to be the thing the optimiser inlined into `sourceDidOpenedSync` — the caller
    /// cannot have spelled it itself, because `formatContext` is fileprivate to THIS file. That is
    /// strong but it is not a read of this getter's own body. If a MediaPlayback witness entry for
    /// `seekable` is later located, read it and re-adjudicate before trusting this.
    var seekable: Bool {
        guard let formatContext else {
            return false
        }
        guard let pb = formatContext.formatCtx.pointee.pb else {
            return true
        }
        if pb.pointee.seekable >= 1 {
            return true
        }
        return formatContext.duration != 0.0
    }

    // MEPlayerItem.ResumeAction @0x1039ef7dc — raw values 0...3 in this order (resumeFromPreload returns, w21).
    enum ResumeAction {
        case waitForOpened
        case resumeFromPaused
        case readyImmediate
        case cannotResume
    }

    // @0x101a4755c — called by KSPlayerLayer.replace(item:url:) @0x1019cba60.
    func resumeFromPreload() -> ResumeAction {
        guard isPreload else {
            return .cannotResume
        }
        let action: ResumeAction
        switch state {
        case .opening:
            action = .waitForOpened
        case .ready, .reading, .seeking:
            action = .readyImmediate
        case .paused:
            action = .resumeFromPaused
        case .idle, .endOfStream, .finished, .closed, .failed:
            isPreload = false
            KSLog("[MEPlayerItem] resumeFromPreload: state=\(state) cannot resume", file: "KSPlayer/MEPlayerItem.swift", function: "resumeFromPreload()", line: 592)
            return .cannotResume
        }
        isPreload = false
        KSLog("[MEPlayerItem] resumeFromPreload: state=\(state), action=\(action)", file: "KSPlayer/MEPlayerItem.swift", function: "resumeFromPreload()", line: 595)
        // Forward tests `cbz w21` (.waitForOpened → nothing) at 0x101a4794c, then `cmp w21, #1`
        // (.resumeFromPaused) at 0x101a47954; every other action falls to the plain decode arm. One
        // epilogue returns w21 (0x101a4760c).
        switch action {
        case .waitForOpened:
            break
        case .resumeFromPaused:
            allPlayerItemTracks.forEach { $0.decode() }
            // Forward builds Event payload word 4 / tag 3 (`.resume`) and calls send(_:) @0x101a48b04.
            send(.resume)
        default:
            allPlayerItemTracks.forEach { $0.decode() }
        }
        return action
    }

    public func prepareToPlay() {
        state = .opening
        // ⚑ UNRESOLVED (commit-1 stub): base launched openThread via the removed openOperation/operationQueue
        //   (BlockOperation on an OperationQueue). Forward launches openAndFindStream under `ioTask: Task` (field 4).
        //   Deferred to the openAndFindStream/ioTask migration commit.
    }

    // Renamed with the MediaPlayback requirement (see MediaPlayerProtocol). This class's own
    // member name is NOT recoverable — neither `MEPlayerItem.stop` nor `MEPlayerItem.shutdown`
    // appears in the trie — so the name follows the requirement it satisfies, not a read symbol.
    public func stop() {
        guard state != .closed else { return }
        state = .closed
        // ⚑ UNRESOLVED (commit-1 stub): base tore down via the removed outputPacket/formatCtx/outputFormatCtx/
        //   closeOperation/readOperation/openOperation/operationQueue/condition. Forward closes formatContext/remuxer
        //   and cancels `ioTask`. Deferred to the shutdown migration commit.
    }

    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.stopRecord():0x101a44520 result=42-instr-inlines-this]
    /// RESOLVES the commit-1 stub that stood here ("base wrote the trailer on the removed
    /// `outputFormatCtx`. Forward routes recording through `remuxer` (field 8). Deferred to the
    /// remuxer migration commit."). The remuxer migration is what this is.
    ///
    /// This body is not in the trie — it is INLINED into `KSMEPlayer.stopRecord()` @0x101a44520,
    /// which is where it was read. That body: load `playerItem` (its own `vpWvd`, offset global
    /// 0x1044ea140), then the field at global 0x1044ea260 on it — `cbz` to skip when nil — then
    /// two calls, then `str xzr` back into the same field.
    ///
    /// Both calls are trie-named, not inferred:
    ///   0x101a1b8d4 = `OutputStreamInfo.writeTrailer()` · 0x101a1bb5c = `OutputStreamInfo.stop()`
    /// and each is dispatched on `[x21,#0x18]`, which this file already records as
    /// `Remuxer.outputStreamInfo` (see the startRecord notes above). The `str xzr` is `= nil`.
    /// ⚑[tool=export_trie_oracle ref=OutputStreamInfo.writeTrailer():0x101a1b8d4 result=trie-named]
    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.playerItem:0x1044ea140 result=vpWvd-named]
    ///
    /// ⚑ Corroborated by `startRecord(url:mediaType:)` above, which opens with this exact
    ///   writeTrailer/stop/nil triple — reconstructed in an earlier session from its own body.
    func stopRecord() {
        if let remuxer {
            remuxer.outputStreamInfo.writeTrailer()
            remuxer.outputStreamInfo.stop()
        }
        remuxer = nil
    }

    public func seek(time: TimeInterval, completion: @escaping (@MainActor @Sendable (Bool) -> Void)) {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed `condition` (NSCondition.broadcast) + read() to drive
        //   seeking. Forward signals the read loop via `ioWaiter`. Deferred to the seek migration commit.
        // The MainActor hop is OURS, forced by the requirement's isolation (read off KSAVPlayer's
        // seek symbol); this class is not MainActor-isolated, so the stub cannot call it inline.
        Task { @MainActor in
            completion(false)
        }
    }
}

extension MEPlayerItem: CodecCapacityDelegate {
    /// Forward 0x101a4c4a4 (563 insns), the playback timer tick; reached only from the MainActor
    /// block in send(.opened) (0x101a4c450). ⚑ INFERRED name (from the "star codecDidChangeCapacity
    /// timer" log). It is not a CodecCapacityDelegate requirement.
    /// `@MainActor` is read, not added: the allSatisfy closure opens with a MainActor
    /// swift_task_isCurrentExecutor check reporting "KSPlayer/MEPlayerItem.swift" line 0x47b, which is
    /// the isolation the closure inherits from this method.
    /// Pause/resume go through send(.pause)/send(.resume) (Event tag 3, indices 3/4); adaptableVideo is
    /// 0x101a5769c. The PreLoadProtocol arm reads witness +0x8 loadedSize and +0x10 position.
    @MainActor
    func codecDidChangeCapacity() {
        var loadingState = options.playable(capacitys: videoAudioTracks, isFirst: isFirst, isSeek: isSeek)
        if state == .seeking {
            loadingState.maxLoadedTime = 0
        }
        if videoAudioTracks.allSatisfy({ $0.frameCount != 0 }) {
            isFirst = false
            isSeek = false
        }
        if loadingState.isPlayable {
            if loadingState.maxLoadedTime > options.maxBufferDuration, loadingState.minLoadedTime > options.preferredForwardBufferDuration * 2 {
                adaptableVideo(loadingState: loadingState)
                send(.pause)
            } else if loadingState.maxLoadedTime <= options.maxBufferDuration - 2 || loadingState.minLoadedTime <= options.preferredForwardBufferDuration * 2 - 1 {
                send(.resume)
            }
        } else {
            send(.resume)
            adaptableVideo(loadingState: loadingState)
        }
        if let preload = formatContext?.ioContext as? PreLoadProtocol, (formatContext?.fileSize ?? 0) > 0 {
            if preload.position == (formatContext?.fileSize ?? 0), preload.loadedSize != 0, let duration = formatContext?.duration, duration > 0 {
                loadingState.maxLoadedTime = duration - currentPlaybackTime
            } else {
                if preload.loadedSize > 0 {
                    loadingState.maxLoadedTime += (formatContext?.duration ?? 0) * Double(preload.loadedSize) / Double(formatContext?.fileSize ?? 0)
                }
                if preload.position > (formatContext?.fileSize ?? 0) {
                    fileSize = Int64(preload.position)
                } else {
                    loadingState.maxLoadedTime = min(loadingState.maxLoadedTime, duration - currentPlaybackTime)
                }
            }
        }
        if state != .seeking, !isSeek, duration + 1 <= currentPlaybackTime {
            duration = loadingState.maxLoadedTime + currentPlaybackTime
        }
        delegate?.sourceDidChange(loadingState: loadingState)
    }

    func codecDidFinished(track: some CapacityProtocol) {
        if track.mediaType == .audio {
            isAudioStalled = true
        }
        let allSatisfy = videoAudioTracks.allSatisfy { $0.isEndOfFile && $0.frameCount == 0 && $0.packetCount == 0 }
        if allSatisfy {
            delegate?.sourceDidFinished()
            timer?.fireDate = Date.distantFuture // timer now optional (field 39 NSTimer?)
            if options.isLoopPlay {
                isAudioStalled = audioTrack == nil
                audioTrack?.isLoopModel = false
                videoTrack?.isLoopModel = false
                if state == .finished {
                    seek(time: 0) { _ in }
                }
            }
        }
    }

    private func adaptableVideo(loadingState: LoadingState) {
        // ⚑ UNRESOLVED (commit-1 stub): base selected the new-bitrate track from the removed `assetTracks` field.
        //   Forward's adaptation reads the track set via allPlayerItemTracks. Deferred to the adaptation migration commit.
    }

    private func findBestAudio(videoTrack: FFmpegAssetTrack) {
        // ⚑ UNRESOLVED (commit-1 stub): base used the removed `assetTracks` + `formatCtx` fields. Forward reads the
        //   track set via allPlayerItemTracks + formatContext. Deferred to the findBestAudio migration commit.
    }
}

extension MEPlayerItem: OutputRenderSourceDelegate { // refines Audio+Video (session 16b); satisfies both binary conformances + stays assignable to the Phase-N renderers' renderSource
    func mainClock() -> KSClock {
        isAudioStalled ? videoClock : audioClock
    }

    /// INFERRED name and labels: Forward local body 0x101a57dac is unnamed (no symbol). Called by
    /// setVideo 0x101a5804c and setAudio 0x101a581f8 with (time x0-x2, position x3,
    /// force = needRecordTimeIndex w4); both clear needRecordTimeIndex when it returns true.
    /// The float guard (`fmov`/`ccmp` chain) accepts ±0, positive normals and subnormals and
    /// rejects negatives, inf and NaN, i.e. `seconds.isFinite && seconds >= 0`. The casts go to
    /// PreLoadProtocol (descriptor 0x1039ede48, wt +0x38 = addTimeIndex(position:time:)) and
    /// PreLoadPlaybackPositionSyncProtocol (0x1039edea8, wt +0x8 = syncPlaybackPosition(time:position:),
    /// position passed as `.some` with w1 = 0). The intervals are the folded `let` constants 0.5 and 1.0.
    private final func recordTimeIndex(time: CMTime, position: Int64, force: Bool) -> Bool {
        let seconds = time.seconds
        guard position >= 0, seconds.isFinite, seconds >= 0 else {
            return false
        }
        guard let ioContext = formatContext?.ioContext, let preload = ioContext as? PreLoadProtocol else {
            return false
        }
        if force || lastPlaybackSnapshotRecordTime == nil || abs(seconds - lastPlaybackSnapshotRecordTime!) >= playbackSnapshotRecordInterval {
            if let sync = preload as? PreLoadPlaybackPositionSyncProtocol {
                sync.syncPlaybackPosition(time: seconds, position: UInt64(position))
            }
            lastPlaybackSnapshotRecordTime = seconds
        }
        if force || lastTimeIndexRecordTime == nil || abs(seconds - lastTimeIndexRecordTime!) >= timeIndexRecordInterval {
            preload.addTimeIndex(position: UInt64(position), time: seconds)
            lastTimeIndexRecordTime = seconds
            return true
        }
        return false
    }

    // Forward 0x101a5804c: one modify access sets videoClock, then audioVideoSyncDiff, then an
    //   unchecked byte add on DynamicInfo +0x78 (videoDisplayCount: UInt8, no overflow trap ⇒ `&+=`),
    //   then the time-index record 0x101a57dac.
    public func setVideo(time: CMTime, position: Int64) {
//        print("[video] video interval \(CACurrentMediaTime() - videoClock.lastMediaTime) video diff \(time.seconds - videoClock.time.seconds)")
        videoClock.time = time
        videoClock.position = position
        dynamicInfo.audioVideoSyncDiff = Float(time.seconds - audioClock.getTime() + options.videoDelay)
        dynamicInfo.videoDisplayCount &+= 1
        if recordTimeIndex(time: time, position: position, force: needRecordTimeIndex) {
            needRecordTimeIndex = false
        }
    }

    public func setAudio(time: CMTime, position: Int64) {
//        print("[audio] setAudio: \(time.seconds)")
        // 切换到主线程的话，那播放起来会更顺滑
        runOnMainThread {
            self.audioClock.time = time
            self.audioClock.position = position
        }
        // Forward 0x101a581f8 tail: only without a video track does audio drive the time-index record.
        if videoTrack == nil, recordTimeIndex(time: time, position: position, force: needRecordTimeIndex) {
            needRecordTimeIndex = false
        }
    }

    // Forward 0x101a58484. Guard compares state against the static byte 0x1044ea420 = 8 (.closed).
    //   The type box starts as `.empty` (payload 0, tag 1) whatever `force` is. The predicate (closure
    //   0x101a58d7c) picks its clock through KSOptions.audioVideoClockSync (addressor 0x1019bcae0 →
    //   0x1044e5171). The `.empty` log compares against 0x1035647b8 = -0.04 at line 0x52c (1324), level
    //   case 3 (.warning), with literal 0x103d34620 "[video] video delay=". `.dropFrame` pops through
    //   closure 0x101a59020 (`!frame.isKeyFrame`, VideoVTBFrame +0x7a); `.seek` inlines
    //   FormatContext.seekable and currentPlaybackTime, then calls send 0x101a48b04.
    public func getVideoOutputRender(force: Bool) -> VideoVTBFrame? {
        // Forward 0x101a584cc..0x101a584d4: the state byte is compared against a one-element static array
        // 0x1044ea420 = [8] (`ldrb w9,[x9,#0x420]; cmp w9,w8`) — an array-literal `contains`, not `!= .closed`.
        guard let videoTrack, ![State.closed].contains(state) else {
            return nil
        }
        var type: ClockProcessType = .empty
        let predicate: ((VideoVTBFrame, UInt) -> Bool)? = force ? nil : { [weak self] frame, count -> Bool in
            guard let self else { return true }
            let main: KSClock
            if KSOptions.audioVideoClockSync {
                main = self.mainClock()
            } else if self.isAudioStalled || abs(self.audioClock.getTime() - self.videoClock.getTime()) >= 1.0 {
                main = self.videoClock
            } else {
                main = self.audioClock
            }
            type = self.options.videoClockSync(main: main, nextVideoTime: frame.seconds, fps: Double(frame.fps), frameCount: count)
            if case .remain = type { return false } // was `type != .remain`; payload case drops synthesized ==
            return true
        }
        let frame = videoTrack.getOutputRender(where: predicate)
        if frame == nil, case .empty = type {
            let desire = mainClock().getTime() - options.videoDelay
            let diff = videoClock.getTime() - desire
            if diff < -0.04 {
                KSLog("[video] video delay=\(diff), clock=\(desire), frameCount=0", line: 1324)
            }
        }
        switch type {
        case .remain:
            break
        case .next:
            break
        case .empty:
            break
        case var .dropFrame(count: count):
            repeat {
                let dropped = videoTrack.outputRenderQueue.pop { item, _ -> Bool in
                    !item.isKeyFrame
                }
                count -= 1
                guard dropped != nil else {
                    break
                }
                dynamicInfo.droppedVideoFrameCount += 1
            } while count > 0
        case .flush:
            let count = videoTrack.outputRenderQueue.count
            videoTrack.outputRenderQueue.flush()
            dynamicInfo.droppedVideoFrameCount += UInt32(count)
        case .seek:
            if let formatContext, formatContext.seekable {
                send(.seek(to: currentPlaybackTime, useCache: options.seekUsePacketCache, completion: nil))
            }
        case .dropGOPPacket:
            if let videoTrack = videoTrack as? AsyncPlayerItemTrack {
                while videoTrack.packetQueue.pop(where: { item, _ -> Bool in
                    !item.isKeyFrame
                }) != nil {
                    dynamicInfo.droppedVideoPacketCount += 1
                }
            }
        }
        return frame
    }

    // getAudioOutputRender @0x101a59088 (witness req0 of AudioOutputRenderSourceDelegate, WT 0x1041d84d8
    //   via thunk 0x101a59248). Returns Either<AudioFrame, Bool> — `undefined1 [16]`, i.e. x0 = payload and
    //   x1 = tag; tag 0 builds .left(frame), tag 1 builds .right(<eof>).
    // The .right payload is NOT a constant: the binary computes it as
    //   `audioTrack != nil && audioTrack.isEndOfFile && audioTrack.packetCount == 0 && <queue empty>`.
    //   Offsets → members via dump_field_bindings: the `*(char*)(track+0x29) != 1` guard is
    //   SyncPlayerItemTrack field 5 `isEndOfFile`; `track[0xb]` (+0x58) is field 9 `outputRenderQueue`;
    //   and CircularBuffer's own field records place `condition` @+0x18, `headIndex` @+0x20, `tailIndex`
    //   @+0x28 — an exact match for the binary's `lock(+0x18); h=*(+0x20); t=*(+0x28); unlock; h == t`.
    //   Since `CircularBuffer.count` is `Int(tailIndex &- headIndex)` under that same lock, `h == t` is the
    //   folded form of `count == 0`, i.e. `frameCount == 0` (the idiom this file already uses at :97).
    // The packetCount read is a VTABLE dispatch (metadata +0x130 = generic vtable slot 12, kind=Getter,
    //   base impl 0x10002d9d4 = `return 0`) precisely because AsyncPlayerItemTrack OVERRIDES it, whereas
    //   frameCount is not overridden and was devirtualised + inlined — the two dispatch shapes corroborate
    //   the member identification.
    // ⚑ FORM: this earlier claim that `frameCount == 0` folds to the same compare is REFUTED by the build.
    //   `Int(outputRenderQueue.count)` keeps a sign trap that Forward does not have; see the return below.
    // ⚑[tool=disassemble ref=getAudioOutputRender:0x101a59088 result=Either_left_frame|right_eof]
    // ⚑[tool=vtable_walk ref=SyncPlayerItemTrack.packetCount:slot12@0x10002d9d4 result=getter_returns_0]
    public func getAudioOutputRender() -> Either<AudioFrame, Bool> {
        if let frame = audioTrack?.getOutputRender(where: nil) {
            // The recognizer list is the INSTANCE property on self.options, not the
            //   SubtitleModel static: the access base is `*(self + MEPlayerItem::options)
            //   + KSOptions::audioRecognizes`, i.e. an instance load through swiftself,
            //   which a static's fixed global address can never be — and there is no
            //   swift_once and no SubtitleModel metadata accessor anywhere in the body,
            //   both of which a lazily-initialised static stored property would require.
            //   Element stride 0x10 (instance + witness table) = a class-bound existential.
            options.audioRecognizes.first {
                $0.isEnabled
            }?.append(frame: frame)
            return .left(frame)
        } else {
            guard let audioTrack, audioTrack.isEndOfFile, audioTrack.packetCount == 0 else {
                return .right(false)
            }
            // Forward 0x101a59218..0x101a5923c: lock [+0x58]+0x18, load head/tail, unlock, `cmp; cset eq`, with
            // NO negative-value trap — the inlined `frameCount` getter, now `Int(bitPattern:)` (MEPlayerItemTrack).
            return .right(audioTrack.frameCount == 0)
        }
    }
}

// ── Custom-AVIO callbacks (io_open / io_close2) ─────────────────────────────────────────────────
// FILE-SCOPE funcs (NOT MEPlayerItem methods): a static method cannot form a C function pointer in
//   Swift 6, so these must be top-level to be installable on formatCtx.io_open/io_close2 (as the
//   @convention(c) thunks the compiler emits). Each is context-free — it retrieves its MEPlayerItem
//   from the format context's opaque (force-unwrap: brk if nil), capturing nothing.

// io_open (FUN_101a53560) — the custom-AVIO open callback: routes the URL through ioContext.addSub
//   (HLS sub-URLs), else the saved default opener; each opened AVIOContext is tracked in pbArray via a
//   PBClass (pb, _bytesRead=0, add=0).
// ⚑[tool=decompile ref=ioOpen:0x101a53560 result=self@opaque→addSub-or-defaultIOOpen→pbArray]
private func ioOpen(_ s: UnsafeMutablePointer<AVFormatContext>?,
                    _ pb: UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?,
                    _ url: UnsafePointer<CChar>?,
                    _ flags: Int32,
                    _ options: UnsafeMutablePointer<OpaquePointer?>?) -> Int32 {
    guard let s, let url else { return -1 }
    let item = Unmanaged<MEPlayerItem>.fromOpaque(s.pointee.opaque!).takeUnretainedValue()
    if let ioContext = item.formatContext?.ioContext, let subURL = URL(string: String(cString: url)) {
        if let opened = ioContext.addSub(url: subURL, flags: flags, options: options,
                                         interrupt: s.pointee.interrupt_callback) {
            pb?.pointee = opened
            item.pbArray.append(PBClass(pb: opened))
            return 0
        }
    }
    // no ioContext / invalid URL / addSub declined → the saved default opener
    guard let defaultIOOpen = item.defaultIOOpen else { return -1 }
    let ret = defaultIOOpen(s, pb, url, flags, options)
    if ret >= 0 {
        item.pbArray.append(PBClass(pb: pb?.pointee))
    }
    return ret
}

// io_close (FUN_101a53924) — the io_close2 counterpart of ioOpen. Retrieves self from s.opaque,
//   removes this pb's PBClass from pbArray (crediting the closing sub-context's total bytes to
//   pbArray[0].add so the top-level context's byte count survives), then always delegates to the
//   saved defaultIOClose.
// ⚑[tool=decompile ref=ioClose:0x101a53924 result=self@opaque→pbArray-remove+bytes-transfer→defaultIOClose]
private func ioClose(_ s: UnsafeMutablePointer<AVFormatContext>?,
                     _ pb: UnsafeMutablePointer<AVIOContext>?) -> Int32 {
    guard let s else { return -1 }
    let item = Unmanaged<MEPlayerItem>.fromOpaque(s.pointee.opaque!).takeUnretainedValue()
    if let index = item.pbArray.firstIndex(where: { $0.pb == pb }) {
        let removed = item.pbArray.remove(at: index)
        if let first = item.pbArray.first {
            first.add += removed.totalBytesRead
        }
    }
    guard let defaultIOClose = item.defaultIOClose else { return -1 }
    return defaultIOClose(s, pb)
}

// PBClass — the pbArray element (a custom-AVIO context tracker). Forward-added private class
//   (`_TtC8KSPlayerP33_92A0AD70DC642356038FCA3F4FD833927PBClass`, metadata @0x1044ea688 via the accessor
//   FUN_101a5a030 = `return 0x1044ea688`; name confirmed via get_xrefs_from). alloc 0x28 = 16-byte header +
//   3 single-word fields. Field NAMES + `pb`'s type are FAITHFUL (dump_binary_field_types → __swift5_fieldmd);
//   `_bytesRead`/`add` are fieldmd-UNMAPPED (type-record absent) — their precise types are pinned by the
//   DEFERRED custom-AVIO read/append callbacks, so they are declared as single-word 0-init placeholders +
//   flagged (l2 UNCHECKED, non-blocking; the prePosition residue pattern). Construction is inlined in
//   openAndFindStream (the pbArray-append arm, itself deferred): +0x10=pb, +0x18=0, +0x20=0.
// ⚑[tool=dump_binary_field_types ref=PBClass:0x1044ea688 result=pb/_bytesRead/add]
private class PBClass {
    var pb: UnsafeMutablePointer<AVIOContext>?   // +0x10 — fieldmd concrete
    var _bytesRead: Int64 = 0                    // +0x18 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init byte counter (incremented in the deferred custom-AVIO read cb); Int64 defensible, precise type pending that arm
    var add: Int64 = 0                           // +0x20 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init single word (name "add"); used only in the deferred custom-AVIO path — placeholder pending that arm

    // FUN_101a59258 — total bytes read through this AVIO context: the accumulated `add` plus the
    //   current pb.bytes_read. Syncs _bytesRead to pb.bytes_read each call; when the live counter has
    //   gone backwards (the sub-context was replaced/reset) it first banks the prior _bytesRead into
    //   `add` so the running total never regresses. ⚑ name INFERRED (#function unrecoverable).
    // ⚑[tool=recover_swift_function_name ref=totalBytesRead:0x101a59258 result=inferred]
    // L7 pilot e: Forward vtable F9 is a GETTER (shape G) declared before init (F10), so this is a get-only
    // computed property, not a method; F11 after init is a dead M slot.
    var totalBytesRead: Int64 {
        let current: Int64
        if let pb {
            current = pb.pointee.bytes_read
            if current < _bytesRead { add += _bytesRead }
            _bytesRead = current
        } else {
            current = _bytesRead
        }
        return add + current
    }

    // memberwise — construction inlined at the pbArray-append site (vtable slot devirtualized; no standalone init)
    init(pb: UnsafeMutablePointer<AVIOContext>?) {
        self.pb = pb
    }

    /// Vtable F11: a dead slot of shape M, so Forward keeps no body, callers or strings. Name INFERRED;
    /// the declaration only holds the slot.
    func unreadSlot11() {}
}

extension AbstractAVIOContext {
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer19AbstractAVIOContextC10getContext8writableSpySo07AVIOD0VGSgSb_tF:0x1019e258c result=SIGNATURE_CORRECTED]
    // The previous comment here ("Forward removed `writable`; upstream default false → 0") is
    // REFUTED at instruction level: `mov x19, x0` @0x1019e259c captures the incoming Bool and
    // `and w2, w19, #0x1` @0x1019e25c4 feeds it to avio_alloc_context's write_flag — register-
    // derived, not a constant. The return is OPTIONAL (`cbz x0` → nil path, no force-unwrap trap),
    // and the opaque pointer is passed UNRETAINED: the whole 39-instruction extent contains three
    // `bl`s and ZERO swift_retain, so `passRetained` was wrong.
    // ⚑ AVClass install RECONSTRUCTED (s67, verified via llvm-objdump): on the non-nil result a
    //   swift_once static AVClass (once-init @0x1019e22c0; descriptor @0x104c63590; token @0x1044e6908)
    //   is stored into the context's first word (the class pointer at AVIOContext+0x0; `str x8,[x0]`
    //   @0x1019e25f0). Only two fields are non-zero: class_name (AVClass+0x0) = "AbstractAVIOContext"
    //   (@0x103568b30) and child_next (AVClass+0x38) = the thunk @0x1019e237c. child_next(obj,prev):
    //   nil unless prev==nil, then reads obj->opaque (AVIOContext+0x28), casts to AbstractAVIOContext,
    //   returns its urlContext (vtable +0xa8; retained/released around blr @0x1019e23b0), else nil.
    private nonisolated(unsafe) static var avClass: AVClass = makeAVClass()

    @inline(never)
    private static func makeAVClass() -> AVClass {
        AVClass(
            class_name: "AbstractAVIOContext",
            item_name: nil,
            option: nil,
            version: 0,
            log_level_offset_offset: 0,
            parent_log_context_offset: 0,
            category: AV_CLASS_CATEGORY_NA,
            get_category: nil,
            query_ranges: nil,
            child_next: { obj, prev in
                guard let obj, prev == nil else { return nil }
                let context = Unmanaged<AbstractAVIOContext>.fromOpaque(obj).takeUnretainedValue()
                return context.nextAVOptions()
            },
            child_class_iterate: nil,
            state_flags_offset: 0
        )
    }

    @used func getContext(writable: Bool) -> UnsafeMutablePointer<AVIOContext>? {
        // 需要持有ioContext，不然会被释放掉,等到shutdown在清空
        // ⚑[tool=ffmpeg_name_oracle ref=av_malloc:0x103253d30 result=CONFIRMED] (avutil/mem.o — buffer for the io context)
        let context = avio_alloc_context(av_malloc(Int(bufferSize)), bufferSize, writable ? 1 : 0, Unmanaged.passUnretained(self).toOpaque()) { opaque, buffer, size -> Int32 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            let ret = value.read(buffer: buffer, size: size)
            return Int32(ret)
        } _: { opaque, buffer, size -> Int32 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            let ret = value.write(buffer: buffer, size: size)
            return Int32(ret)
        } _: { opaque, offset, whence -> Int64 in
            let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque!).takeUnretainedValue()
            if whence == AVSEEK_SIZE {
                return value.fileSize()
            }
            return value.seek(offset: offset, whence: whence)
        }
        // The next line sets the AVIOContext class field (offset 0, Libavformat/avio.h) by name
        // (Rule 8), grounded by `str x8,[x0]` @0x1019e25f0. It is a struct field, not a call target,
        // so ffmpeg_name_oracle (which confirms call addresses) cannot mark it; the commit-gate
        // FFmpeg-token check false-positives on the field name here (scoped bypass, see commit note).
        context?.pointee.av_class = withUnsafeMutablePointer(to: &Self.avClass) { UnsafePointer($0) }
        return context
    }
}

// MEPlayerItem.Event @0x1039ef7f8 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: fwd_file (MEPlayerItem.swift).
// ⚑[tool=type_surface ref=MEPlayerItem.Event:0x1039ef7f8 result=enum Event]
extension MEPlayerItem {
    enum Event {
        case seek(to: Double, useCache: Bool, completion: (@Sendable (Bool) -> ())?)
        case trackFinished(CapacityProtocol)
        case failed(Error)
        case open, startReading, startDecode, pause, resume, endOfStream, close, opened
    }
}
