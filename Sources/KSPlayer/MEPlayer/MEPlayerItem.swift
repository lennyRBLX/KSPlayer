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
    private var io: Either<URL, AbstractAVIOContext>                 // 1 ⚑[tool=name_type_at_addr ref=io:0x103566d40 result=Either<_,AbstractAVIOContext>] first param URL (sibling KSAVPlayer.io)
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
    public private(set) var duration: TimeInterval = 0          // 35
    public private(set) var fileSize: Int64 = 0                // 36 MediaPlayback.fileSize Int64 (bin field-record Int? UNCHECKED — kept Int64 per protocol)
    public private(set) var naturalSize = CGSize.zero        // 37 ⚑ bin field-record CGSize? (init nil), but MediaPlayback requires non-optional CGSize → kept CGSize; CGSize? deferred with the protocol migration
    private var state = State.idle {                         // 38 RESOLVED: nested MEPlayerItem.State (10 cases; desc @0x1039ef8b0, Model.swift). Was base MESourceState.
        didSet {
            switch state {
            case .ready:                          // base `opened` (raw 2); renamed in Forward
                delegate?.sourceDidOpened()
            case .reading:
                timer?.fireDate = Date.distantPast
            case .closed:
                timer?.invalidate()
            case .failed:
                delegate?.sourceDidFailed(error: nil) // ⚑ UNRESOLVED: base passed removed `error` field; Forward error-source pending
                timer?.fireDate = Date.distantFuture
            case .idle, .opening, .seeking, .paused, .endOfStream, .finished:
                // ⚑ endOfStream (raw 6, NEW in Forward): base-derived no-op; Forward state.didSet body pending its own audit
                break
            }
        }
    }
    private var timer: Timer?                                // 39 Forward NSTimer? nil-init (base was `lazy var timer: Timer = .scheduledTimer`); scheduling site pending. Timer === NSTimer (reflection emits NSTimer)
    private let preloadClock = ContinuousClock()            // 40 ⚑ init calls Swift.ContinuousClock.init(); ContinuousClock vs .Instant pending
    private var lastPacketMediaType: AVFoundation.AVMediaType = .video // 41 init AVMediaTypeVideo (AVFoundation constant; codebase disambiguates from FFmpeg AVMediaType)
    public weak var delegate: MEPlayerDelegate?                    // 42

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

    public var isIdle: Bool {
        state == .idle
    }

    /// ⚑[tool=disassemble ref=MEPlayerItem.isReusable.getter:0x101a4b404 result=19-instr]
    /// Same `state` load, then a five-way set-membership test in the shape the compiler uses for a
    /// multi-case `switch`: four constants compared at once via `cmeq.4h` against the vector at
    /// 0x1044ea360, plus the fifth as a scalar at +0x4. Those five bytes read `01 02 03 04 05`.
    /// Against `MEPlayerItem.State` that is opening/ready/reading/seeking/paused — every state
    /// between `.idle` and the terminal group, which is what makes the name coherent.
    /// ⚑ The five happen to be contiguous, so a range test would compile to the same answer; the
    /// binary emits an explicit five-way membership, so the switch form is written.
    public var isReusable: Bool {
        switch state {
        case .opening, .ready, .reading, .seeking, .paused:
            return true
        default:
            return false
        }
    }

    public var currentPlaybackTime: TimeInterval {
        state == .seeking ? seekTime : mainClock().time.seconds // ⚑ UNRESOLVED: base subtracted removed `startTime`
    }

    // ⚑ Forward moved the per-stream FFmpegAssetTracks into FormatContext (FormatContext.swift:59 `assetTracks`
    //   @+0x40); MEPlayerItem's stored `assetTracks` field is removed. This computed bridge reads the migrated
    //   source so the external reader KSMEPlayer.tracks(mediaType:) stays green (Forward may instead read
    //   formatContext.assetTracks directly — resolved when KSMEPlayer.tracks migrates).
    var assetTracks: [FFmpegAssetTrack] { formatContext?.assetTracks ?? [] }

    public lazy var dynamicInfo = DynamicInfo {
        toDictionary(nil) // ⚑ UNRESOLVED: base read self.formatCtx.pointee.metadata (removed field); FormatContext raw-ptr accessor pending
    } bytesRead: {
        0 // ⚑ UNRESOLVED: base read self.formatCtx.pointee.pb.pointee.bytes_read (removed field)
    } audioBitrate: { [weak self] in
        Int(8 * (self?.audioTrack?.bitrate ?? 0))
    } videoBitrate: { [weak self] in
        Int(8 * (self?.videoTrack?.bitrate ?? 0))
    }

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

    public init(url: URL, options: KSOptions) {
        io = .left(url) // ⚑ Forward io: Either<URL, AbstractAVIOContext>; init wraps url (sibling KSAVPlayer.io = .left(url)); Forward init may take io: directly (caller builds the Either)
        self.options = options
        _ = MEPlayerItem.onceInitial
    }

    func select(track: some MediaPlayerTrack) -> Bool {
        // ⚑ UNRESOLVED (commit-1 stub): base body used the removed `assetTracks` field + findBestAudio/seek.
        //   Forward body deferred to its own commit (allPlayerItemTracks-based track selection).
        false
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
        // ⚑ UNRESOLVED: leading KSLog(.debug, …) gated on `2 < logLevel` (prologue global DAT_1044e5173) — message deferred.
        // ⚑ UNRESOLVED: a close/reset call precedes the open to reset prior state; method identity + body deferred.
        //   ⚑[tool=recover_swift_function_name ref=closeReset:0x101a531fc result=no-#function/739B]

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
        // ⚑ UNRESOLVED: pbArray append — allocs a PBClass and appends it to self.pbArray (field 29), then on a
        //   successful dynamic-cast writes KSOptions seekUsePacketCache=false + a formatContextOptions entry.
        //   ⚑[tool=decompile ref=pbClassAlloc:0x101a5a030 result=deferred-PBClass-body]

        options.formatName = formatContext.formatName        // String @+0x48 (DERIVED from iformat.name)
        self.fileSize = formatContext.fileSize               // +0x30
        self.duration = formatContext.duration               // +0x28
        // ⚑ UNRESOLVED: KSOptions rate×duration — `if options[+0x38] > 0 { options[+0x30] = options[+0x38] ×
        //   formatContext.duration }` (two KSOptions Double fields; offset→name mapping deferred).
        self.chapters = formatContext.chapters               // FormatContext.chapters getter (DONE, commit-2a)

        //   ⚑[tool=get_xrefs_to ref=createCodec:0x101a53c44 result=argless]
        createCodec()                                        // track-set builder (argless, reads self.formatContext; slice-1 reconstructed)
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
            KSLog(error)
        }
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
        guard let formatContext else { return }         // self.formatContext; nil → early return (no track build)

        // SLICE 2 (closure FUN_101a556b0): rebuild the subtitle tracks from formatContext.assetTracks. Every track
        //   is disabled (track.isEnabled = false — the disable-all reset; slices 3/4 re-enable the selected
        //   video/audio). The `discard` values the disasm writes (non-sub→ALL, image-sub→ALL, text-sub→DEFAULT) are
        //   exactly what the isEnabled setter yields for newValue=false, so this IS `isEnabled = false`. For subtitle
        //   tracks a SyncPlayerItemTrack<SubtitleFrame> is built: image subtitles share the single self.subtitleTrack
        //   (frameCapacity 8, built once); text subtitles get a per-track one (frameCapacity 128). BOTH branches were
        //   disasm-confirmed to build SyncPlayerItemTrack<SubtitleFrame> (metadata 0x10356ac50), which is why
        //   track.subtitle (+0x100) is homogeneous. delegate = self is a weak assign (+0x40).
        allPlayerItemTracks = []
        for track in formatContext.assetTracks {
            track.isEnabled = false
            if track.mediaType == .subtitle {
                if track.isImageSubtitle {
                    if subtitleTrack == nil {
                        // ⚑[tool=llvm-objdump ref=FUN_101a556b0:0x101a556b0 result=NO-CAP-8-CALL-SITE] This branch has
                        //   NO counterpart in the closure it reconstructs: a BL scan of 0x101a556b0..0x101a55de4 finds
                        //   exactly ONE track construction, 0x101a55918 (cap 128, the text branch below). So the
                        //   comment above is wrong on two counts — this body builds no cap-8 track at all, and the
                        //   image path elsewhere (subtitleAssetTrackMap 0x101a367b4) builds AsyncPlayerItemTrack, not
                        //   Sync. `expanding: false` is taken from the analogous image path (w3=0 @0x101a367a8); it is
                        //   NOT read from this function, which emits no such call. Re-deriving SLICE 2 is its own unit.
                        let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 8, options: options, expanding: false)
                        allPlayerItemTracks.append(subtitle)    // append BEFORE delegate: the binary's append endAccess barrier (0x101a55a74) precedes the delegate weakAssign (0x101a55a88) — matches the text branch order
                        subtitle.delegate = self
                        subtitleTrack = subtitle
                    }
                    track.subtitle = subtitleTrack
                } else {
                    // `expanding: true` is binary-read: w3=1 @0x101a55914, the call at 0x101a55918.
                    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                    subtitle.delegate = self
                    track.subtitle = subtitle
                    allPlayerItemTracks.append(subtitle)
                }
            }
        }
        // ⚑ UNRESOLVED (SLICE 2 — the 2nd-pass embed-subtitle registration, Forward-ADDED): the subtitle
        //   FFmpegAssetTracks are collected + cast to [any SubtitleInfo] (FFmpegAssetTrack: SubtitleInfo via
        //   EmbedDataSouce.swift; conformance witness 0x1041d7668) and passed to a KSOptions method at
        //   vtable[0x768], whose result gets a follow-on witness[+0x40](true) dispatch. That method is Forward-
        //   added: absent from source AND the origin/forward base, and statically unresolvable (metadata slot
        //   md+0x768 is an unbound pattern value 0x105395200 with no function).
        //   ⚠️ NAMED (session 63) — the P43 negative above is REFUTED. It concluded "statically
        //   unresolvable" from source ✗ / base ✗ / static metadata ✗; none of those three can see
        //   the ORPHANED export trie, which carries exactly one KSOptions member taking a subtitle
        //   track array:
        //       KSPlayer.KSOptions.wantedSubtitle(tracks: [KSPlayer.SubtitleInfo]) -> KSPlayer.SubtitleInfo?
        //   That signature matches this call site precisely: [any SubtitleInfo] in, an OPTIONAL out
        //   feeding the follow-on witness[+0x40](true) dispatch. The body is still not reconstructed
        //   — what changes is that the method is no longer nameless, and "absent from source AND the
        //   origin/forward base" is now a Forward-ADDED method with a known signature.
        // ⚑[tool=export_trie_oracle ref=KSOptions.wantedSubtitle(tracks:) result=NAMED — supersedes the get_function_by_address FAILED-SEARCH]
        // ⚑ UNRESOLVED (SLICE 3 — audio, closures FUN_101a36964/36cf0 + tail): audio sample-rate sampling
        //   (audioStreamBasicDescription) + max-reduction + the KSOptions.vtable[0x6f8] call + AudioPlayerItemTrack
        //   (FUN_101a383a8/33444) construction.
        // ⚑ UNRESOLVED (SLICE 4 — rotation/filter): isRotateByFilter → transpose_vt/videoFilters/hardwareDecode/
        //   asynchronousDecompression + the 90°-rotation angle math.
        // ⚑ UNRESOLVED (SLICE 5 — adaptation): videoAdaptation rebuild + naturalSize.

        isAudioStalled = false   // tail (@0x101a55d??): *(self + ::isAudioStalled) = 0, unconditional on the non-nil path
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

    private func reading() -> Int32 {
        // ⚑ UNRESOLVED → Stage-2 DEEP (a runtime-keystone CLUSTER, ioTask-reached, static-invisible).
        //   The Forward read machinery is a 3-function cluster driven from `ioTask: Task` (a thread entry
        //   the static Swift→Swift callee graph cannot see — topo_readiness v1 confirms the driver is NOT
        //   in its analyzed universe). Characterized here (named residuals + closure), NOT reconstructed —
        //   deferred to the Stage-2 EASY/DEEP partition (topo_readiness v2 seeds the ioTask thread-entry
        //   root so the cluster becomes a tracked keystone). The exact per-track reset requirement and all
        //   three names are #function-unrecoverable → the witness offset needs the PlayerItemTrackProtocol
        //   witness table decoded at reconstruction time. NOT fabricated.
        //     • DRIVER — the packet-read/demuxer loop; on a read error it calls the error handler.
        // ⚑[tool=get_function_by_address ref=FUN_101a512b4:0x101a512b4 result=read-loop driver ~575 insns; ioTask-reached runtime keystone, static-invisible (topo_readiness v1: absent from universe)]
        //     • ERROR HANDLER — decides per errno: AVERROR_EOF/feof → reconnect-or-finish; EIO/EPIPE →
        //       reconnect (below); else → a `readFrame_fail` KSPlayerError (s_readFrame_fail).
        // ⚑[tool=decompile ref=FUN_101a5685c:0x101a5685c result=read-error handler ~415 insns — EOF/reconnect/readFrame_fail decision; sole caller of the reconnect arm]
        //     • RECONNECT ARM — KSLog + `try? openAndFindStream()` + `allPlayerItemTracks.forEach { $0.<reset>() }`.
        // ⚑[tool=decompile ref=FUN_101a56ecc:0x101a56ecc result=reconnect arm ~40 insns — level-gated KSLog + openAndFindStream + per-track witness+0x58 reset (offset needs PlayerItemTrackProtocol WT decode; shutdown is witness+0x80)]
        0
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
}

// MARK: MediaPlayback

extension MEPlayerItem: MediaPlayback {
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
    func codecDidChangeCapacity() {
        let loadingState = options.playable(capacitys: videoAudioTracks, isFirst: isFirst, isSeek: isSeek)
        delegate?.sourceDidChange(loadingState: loadingState)
        if loadingState.isPlayable {
            isFirst = false
            isSeek = false
            // ⚑ s106: `loadedTime` split into maxLoadedTime/minLoadedTime, so these two reads had
            //   to pick one — and unlike the other consumers, this choice is NOT readable.
            //   MEPlayerItem's CodecCapacityDelegate witness table @0x1041d84c0 has BOTH
            //   requirements pointing at the stub 0x10345cc70, whose __got slot 0x104112df0 binds
            //   `_swift_deletedMethodError`. So `codecDidChangeCapacity` is declared in Forward
            //   with its code DELETED — there is no body here to read either way.
            //   `maxLoadedTime` is used for consistency with the two consumers that ARE readable
            //   (progress in KSOptions.playable, and KSMEPlayer.sourceDidChange), and the choice
            //   is pinned rather than presented as derived.
            //   ⚑[tool=bind_oracle ref=MEPlayerItem:CodecCapacityDelegate@0x1041d84c0 result=swift_deletedMethodError]
            if loadingState.maxLoadedTime > options.maxBufferDuration {
                adaptableVideo(loadingState: loadingState)
                pause()
            } else if loadingState.maxLoadedTime < options.maxBufferDuration / 2 {
                resume()
            }
        } else {
            resume()
            adaptableVideo(loadingState: loadingState)
        }
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

    public func setVideo(time: CMTime, position: Int64) {
//        print("[video] video interval \(CACurrentMediaTime() - videoClock.lastMediaTime) video diff \(time.seconds - videoClock.time.seconds)")
        videoClock.time = time
        videoClock.position = position
        // ⚑ UNRESOLVED (commit-1): base updated dynamicInfo.displayFPS via the removed videoDisplayCount/
        //   lastVideoDisplayTime fields. Forward's displayFPS accounting is deferred to that migration.
    }

    public func setAudio(time: CMTime, position: Int64) {
//        print("[audio] setAudio: \(time.seconds)")
        // 切换到主线程的话，那播放起来会更顺滑
        runOnMainThread {
            self.audioClock.time = time
            self.audioClock.position = position
        }
    }

    public func getVideoOutputRender(force: Bool) -> VideoVTBFrame? {
        guard let videoTrack else {
            return nil
        }
        var type: ClockProcessType = force ? .next : .remain
        let predicate: ((VideoVTBFrame, Int) -> Bool)? = force ? nil : { [weak self] frame, count -> Bool in
            guard let self else { return true }
            // DynamicInfo.audioVideoSyncDiff is Float in the binary (field record `Sf`), not Double, so
            // the base's one-line tuple assignment from the Double-returning videoClockSync has to spell
            // the narrowing out. Type change only — the arithmetic and the control flow are unchanged.
            // ⚑ UNRESOLVED: Forward may not compute the diff here at all. Every reader/writer of the field
            //   is an xref of its field-offset global
            //   ⚑[tool=get_xrefs_to ref=DynamicInfo.audioVideoSyncDiff:0x104c63578 result=CONFIRMED],
            //   and no getVideoOutputRender closure is among them; the only non-init writer is the
            //   videoClock/setVideo path
            //   ⚑[tool=decompile_function ref=MEPlayerItem.setVideo:0x101a5804c result=LOCATED].
            //   Deferred to the MEPlayerItem migration — settling it is not this unit's lane.
            let (syncDiff, syncType) = self.options.videoClockSync(main: self.mainClock(), nextVideoTime: frame.seconds, fps: Double(frame.fps), frameCount: count)
            self.dynamicInfo.audioVideoSyncDiff = Float(syncDiff)
            type = syncType
            return type != .remain
        }
        let frame = videoTrack.getOutputRender(where: predicate)
        switch type {
        case .remain:
            break
        case .next:
            break
        case .dropNextFrame:
            if videoTrack.getOutputRender(where: nil) != nil {
                dynamicInfo.droppedVideoFrameCount += 1
            }
        case .flush:
            let count = videoTrack.outputRenderQueue.count
            videoTrack.outputRenderQueue.flush()
            dynamicInfo.droppedVideoFrameCount += UInt32(count)
        case .seek:
            videoTrack.outputRenderQueue.flush()
            videoTrack.seekTime = mainClock().time.seconds
        case .dropNextPacket:
            if let videoTrack = videoTrack as? AsyncPlayerItemTrack {
                let packet = videoTrack.packetQueue.pop { item, _ -> Bool in
                    !item.isKeyFrame
                }
                if packet != nil {
                    dynamicInfo.droppedVideoPacketCount += 1
                }
            }
        case .dropGOPPacket:
            if let videoTrack = videoTrack as? AsyncPlayerItemTrack {
                var packet: Packet? = nil
                repeat {
                    packet = videoTrack.packetQueue.pop { item, _ -> Bool in
                        !item.isKeyFrame
                    }
                    if packet != nil {
                        dynamicInfo.droppedVideoPacketCount += 1
                    }
                } while packet != nil
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
    // ⚑ FORM (not behaviour): `frameCount == 0`, `outputRenderQueue.count == 0` and an `isEmpty` spelling
    //   all fold to the same `h == t` compare, so the binary cannot discriminate them. The file's existing
    //   idiom decides it here.
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
            first.add += removed.totalBytesRead()
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
private final class PBClass {
    var pb: UnsafeMutablePointer<AVIOContext>?   // +0x10 — fieldmd concrete
    var _bytesRead: Int64 = 0                    // +0x18 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init byte counter (incremented in the deferred custom-AVIO read cb); Int64 defensible, precise type pending that arm
    var add: Int64 = 0                           // +0x20 ⚑ UNRESOLVED type: fieldmd-unmapped; 0-init single word (name "add"); used only in the deferred custom-AVIO path — placeholder pending that arm

    // memberwise — construction inlined at the pbArray-append site (vtable slot devirtualized; no standalone init)
    init(pb: UnsafeMutablePointer<AVIOContext>?) {
        self.pb = pb
    }

    // FUN_101a59258 — total bytes read through this AVIO context: the accumulated `add` plus the
    //   current pb.bytes_read. Syncs _bytesRead to pb.bytes_read each call; when the live counter has
    //   gone backwards (the sub-context was replaced/reset) it first banks the prior _bytesRead into
    //   `add` so the running total never regresses. ⚑ name INFERRED (#function unrecoverable).
    // ⚑[tool=recover_swift_function_name ref=totalBytesRead:0x101a59258 result=inferred]
    func totalBytesRead() -> Int64 {
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
    private nonisolated(unsafe) static var avClass = AVClass(
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

    func getContext(writable: Bool) -> UnsafeMutablePointer<AVIOContext>? {
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
