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

@MainActor
public protocol MediaPlayback: AnyObject {
    var duration: TimeInterval { get }
    var fileSize: Int64 { get }
    var naturalSize: CGSize { get }
    var chapters: [Chapter] { get }
    var currentPlaybackTime: TimeInterval { get }
    var playbackRate: Float { get set }
    var dynamicInfo: DynamicInfo { get }
    var ioContext: AbstractAVIOContext? { get }
    func prepareToPlay()
    func seek(time: TimeInterval, completion: @escaping (@MainActor @Sendable (Bool) -> Void))
    func startRecord(url: URL)
    func stopRecord()
    func stop()
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
    // Which of the two 16-byte slots is which is fixed by the slot-36 updater @0x1019df7d8: it reads
    // self+0x50 as an optional closure and sums `numberOfDroppedVideoFrames` over the array it returns
    // (⇒ accessLogEvent), and reads self+0x60 as an optional @MainActor closure whose result is stored
    // straight into the Float-typed `_displayFPS` Published (⇒ displayFPSBlock).
    // ⚑ access level NOT binary-recoverable (a `let` emits no vtable slot) — mirrors the sibling blocks.
    // ⚑ OPEN — now CONFIRMED, still deferred: the second initializer is a DISTINCT DESIGNATED init
    //   (vtable slot 35 @0x1019de4a8 is the allocating entry; its initializing entry is 0x1019df2f0) and
    //   it ASSIGNS both of these — x2:x3 → self+0x50, x0:x1 → self+0x60.
    //   ⚑[tool=disassemble_function ref=DynamicInfo.init#2-initializing-entry:0x1019df2f0 result=CONFIRMED]
    //   ⚑[tool=init_thunk_probe ref=DynamicInfo.init#2-allocating-entry:0x1019de4a8 result=LOCATED]
    //   DONE (session 62 audit): the two `= nil` defaults are dropped and the slot-34 init below assigns
    //   `nil` explicitly, which is what the binary says AND what lets slot 35 land later without a
    //   re-write. The defaults were not merely inconvenient, they were REFUTED, and the decisive proof
    //   needs no symbol table at all: slot 35 @0x1019df2f0 ASSIGNS both fields from its parameters
    //   (`stp x23,x22,[x20,#0x60]` → displayFPSBlock, `stp x21,x19,[x20,#0x50]` → accessLogEvent), and
    //   in Swift no initializer may assign a `let` that carries a declaration default. Corroborated by
    //   the export trie: a stored property with a default emits a `<name>…vpfi` (variable initialization
    //   expression) symbol, DynamicInfo emits exactly EIGHT, and they are exactly the eight stored
    //   properties this file gives defaults — the six closure `let`s emit no symbol of any kind. That
    //   8-for-8 correspondence is the evidence; an earlier note here said "five", which was an artifact
    //   of substring-searching a PREFIX-COMPRESSED trie (`audioVideoSyncDiffSfv` carries `pfi` in a
    //   CHILD edge, so a raw grep misses it — the trie must be walked structurally, not grepped).
    //   Absence is meaningful because it is calibrated on the `let` case specifically: `Chapter.start/
    //   end/title` are `let`s WITHOUT defaults and emit no vpfi, while `CircularBuffer.condition` and
    //   `MEPlayerItem.ioWaiterLock` are `let`s WITH defaults and do — so vpfi ⟺ declaration default,
    //   independent of let/var and of access level. ICF folds vpfi bodies but preserves distinct trie
    //   entries, so folding cannot explain an absence either.
    //   ⚑[tool=export_trie ref=DynamicInfo.accessLogEvent+displayFPSBlock:vpfi-absent result=CONFIRMED]
    private let accessLogEvent: (() -> [AVPlayerItemAccessLogEvent])?
    private let displayFPSBlock: (@MainActor @Sendable () -> Float)?
    // Fields 7-9 — the first three stores slot 34 makes after swift_allocObject:
    //   `str xzr,[x0, #0x70]`               → lastBytesRead = 0        (8 bytes)
    //   `strb wzr,[x0, #0x78]`              → videoDisplayCount = 0    (1 byte ⇒ UInt8, field record)
    //   `bl 0x103459d54 ; str d0,[x27,#0x80]` → lastMediaTime = CACurrentMediaTime()  (Double, field record)
    // ⚑ lastBytesRead's type is a symref (0x10536e600) that lands outside the mapped image, so it is not
    //   name-resolvable here. It is the SAME mangle as bytesReadBlock's return type (this class) and as
    //   VideoToolboxDecode.startTime/maxTimestamp/lastTimestamp — every one of which is already declared
    //   Int64 — and VideoToolboxDecode slot 32 writes -1 into one of them with a 64-bit `mov x8,#-0x1`
    //   (an integer, not a Double bit pattern). Int64 is therefore consistent-by-construction, not a guess.
    // Access level IS binary-recoverable here, and the old note claiming otherwise was wrong. Swift
    // mangles a `private`/`fileprivate` declaration with a per-file discriminator (`33_<hash>LL`), and
    // the export trie carries these three in the same class and the same file:
    //     lastBytesRead      …33_063281FC2A6ACCAECDC86E734AD47AE7LL s5Int64V vpfi   → private ✓
    //     lastMediaTime      …33_063281FC2A6ACCAECDC86E734AD47AE7LL Sd      vpfi   → private ✓
    //     videoDisplayCount   17videoDisplayCount                   s5UInt8V vpfi   → NOT private
    // Two of the three guesses were right; `videoDisplayCount` was not, so its modifier is dropped.
    // `internal` is POSITIVELY proven, not merely "not private": the class's three genuinely public
    // stored vars each carry {vg, vgTq, vpMV, vpWvd, vpfi}, whereas videoDisplayCount carries {vpfi}
    // alone — the same symbol shape as the private siblings. Not private AND not public ⇒ internal.
    // ⚑ `internal private(set)` remains indistinguishable from `internal` here; unresolvable, not a
    //   divergence.
    // ⚑[tool=export_trie ref=DynamicInfo.videoDisplayCount:no-private-discriminator result=CONFIRMED]
    private var lastBytesRead: Int64 = 0
    var videoDisplayCount: UInt8 = 0
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
    // Double-vs-Float, carried unsettled since the first pass, is now SETTLED — both are Float, and the
    // three signals agree: (1) the field records (scripts/dump_field_type_mangles.py DynamicInfo) read
    // `<Published>ySfG` at idx 10-11 and a bare `Sf` at idx 12; (2) BOTH inits zero audioVideoSyncDiff with
    // a 4-byte `str wzr` (@0x1019df144 in slot 34, @0x1019df3dc in the slot-35 body), never `str xzr`;
    // (3) the slot-36 updater @0x1019df7d8 feeds `Published._set_subscript` from a 32-bit float temp for
    // both _displayFPS and _networkSpeed. The two are not annotated for style — an unannotated `var x = 0.0`
    // reads back as UNCHECKED in l2_field_gate, which is exactly how a Double survived here.
    @Published
    public var displayFPS: Float = 0
    // ⚑ access level NOT binary-recoverable; `public` mirrors its Published sibling displayFPS.
    @Published
    public var networkSpeed: Float = 0
    public var audioVideoSyncDiff: Float = 0
    public var droppedVideoFrameCount: UInt32 = 0
    public var droppedVideoPacketCount: UInt32 = 0
    /// Binary: vtable slot 34 @0x1019df094 (66 instructions) — the allocating entry point with the
    /// designated init inlined (`swift_allocObject` 0x10345caf0, then every stored-property default above,
    /// then the four closure stores). ⚑ parameter labels are NOT recoverable (stripped;
    /// `recover_swift_function_name.py --addr 0x1019df094` finds no `#function` literal) — they are the
    /// pre-existing source labels, kept. The four closures arrive in x0-x7 and land as
    /// `stp x26,x25,[x27,#0x10]` / `[#0x20]` / `[#0x30]` / `[#0x40]`, which is the argument-to-field
    /// mapping below. All eight of x0-x7 are read (parked in x26…x19 across the alloc) and x8 is only
    /// WRITTEN, from the x20 metatype — so there is no ninth word and no indirect return, which is what
    /// pins the arity at exactly these four closures. The standalone initializing entry for the same init
    /// is 0x1019df19c — the same stores in the same order, so slot 34 is the allocating entry with that
    /// body inlined, not a stub.
    /// ⚑ OPEN: slot 35 @0x1019de4a8 is a SECOND, DISTINCT DESIGNATED init (it allocates and forwards to
    /// initializing entry 0x1019df2f0, which writes every stored property itself and never delegates to
    /// this one; arity = 4 words in x0-x3). Not reconstructed here — it is its own unit.
    @used init(metadata: @escaping () -> [String: String], bytesRead: @escaping () -> Int64, audioBitrate: @escaping () -> Int, videoBitrate: @escaping () -> Int) {
        metadataBlock = metadata
        bytesReadBlock = bytesRead
        audioBitrateBlock = audioBitrate
        videoBitrateBlock = videoBitrate
        // Explicit, because the declarations carry no default (see the vpfi evidence above). The binary
        // zero-fills both slots here; spelling it is what a `let` with no default requires, and it is
        // what leaves slot 35 free to assign its own values.
        accessLogEvent = nil
        displayFPSBlock = nil
    }

    // s100 — vtable slot 35, the SECOND designated init. Allocating entry 0x1019de4a8, initializing
    // entry 0x1019df2f0 (110 instr). Labels from the trie:
    // `KSPlayer.DynamicInfo.init(displayFPSBlock: @MainActor @Sendable () -> Float,
    //  accessLogEvent: () -> [AVPlayerItemAccessLogEvent])`.
    // Argument mapping read from the stores: arg 1 -> self+0x60 (displayFPSBlock), arg 2 ->
    // self+0x50 (accessLogEvent), matching the offsets the slot-36 updater uses.
    // The four block `let`s are SYNTHESIZED here rather than passed, each via a 2-instruction
    // adapter at 0x1019e0e38/40/48 that loads the captured closure out of its own
    // `_swift_allocObject(…, 0x20, 7)` box; all three derived blocks capture the SAME
    // accessLogEvent closure, which is why the body ends in `_swift_retain_n(param_5, 3)`.
    //   metadataBlock    0x1019df4a8 -> 0x1019c2f60 with `__swiftEmptyArrayStorage`
    //                    (⚑ bind_oracle 0x104112d00); the builder's `cbz` empty path returns
    //                    `__swiftEmptyDictionarySingleton` (⚑ bind_oracle 0x104112d08) ⇒ [:]
    //   bytesReadBlock   0x1019df4b4 sums `numberOfBytesTransferred` (Int64, `adds` with overflow trap)
    //   audioBitrateBlock 0x1019df598 reads last `averageAudioBitrate` — selref 0x10440a7d8 →
    //                    __objc_methname 0x10397b1c0 = "averageAudioBitrate"
    //   videoBitrateBlock 0x1019df6b8 reads last `averageVideoBitrate`
    // Ref helpers 0x1019df598/0x1019df6b8 read only the last event, then convert
    // its Double bitrate to Int with checked range/NaN guards. Empty events yield zero.
    // Evidence: M05-DynamicInfo-init35-helpers-disasm.json and M05-DynamicInfo-event-getters.json.
    init(displayFPSBlock: @escaping @MainActor @Sendable () -> Float,
         accessLogEvent: @escaping () -> [AVPlayerItemAccessLogEvent])
    {
        metadataBlock = { [:] }
        self.displayFPSBlock = displayFPSBlock
        bytesReadBlock = { accessLogEvent().reduce(0) { $0 + $1.numberOfBytesTransferred } }
        audioBitrateBlock = { Int(accessLogEvent().last?.averageAudioBitrate ?? 0) }
        videoBitrateBlock = { Int(accessLogEvent().last?.averageVideoBitrate ?? 0) }
        self.accessLogEvent = accessLogEvent
    }

    /// @0x1019df7d8, 204 instructions — the "slot-36 updater" the field notes above already refer to.
    /// The trie gives the signature: `KSPlayer.DynamicInfo.update() -> ()`, one symbol, no ICF fold,
    /// with a method descriptor, so it is a vtable member declared in the class body.
    /// ⚑[tool=export_trie_oracle ref=DynamicInfo.update:0x1019df7d8 result=updateyyF]
    ///
    /// Read in order: `CACurrentMediaTime()` (__got 0x10410a7f8) into d8; `interval = time -
    /// lastMediaTime` (self+0x80); `fmov d0,#1.5` / `fcmp` / `b.le` @0x1019df814-81c is the gate,
    /// and it skips the whole body including the two trailing stores. Then the `accessLogEvent`
    /// optional closure (self+0x50/+0x58), an array walk summing the ObjC
    /// `numberOfDroppedVideoFrames` (selref 0x10440c450) into a UInt32 accumulator that clamps
    /// negatives (`asr`/`bic` @0x1019df924-928) and traps on overflow, stored to
    /// `droppedVideoFrameCount` through offset global 0x104c63580. Then the `displayFPSBlock`
    /// if/else, `videoDisplayCount = 0` (`strb wzr` @0x1019dfa3c), `bytesReadBlock()`, and the
    /// clamped `networkSpeed`. Both Published writes go through `swift_getKeyPath` ×2 and
    /// `Combine.Published._enclosingInstance:wrapped:storage:`, with the keypath pairs pinned by
    /// their computed-component id words to `displayFPS`/`_displayFPS` and
    /// `networkSpeed`/`_networkSpeed`.
    ///
    /// ⚑ `@MainActor` IS DERIVED, not stylistic, and the argument does not rest on the executor
    ///   assertion. `displayFPSBlock` is `(@MainActor @Sendable () -> Float)?` — field record 5,
    ///   mangling `SfyYbScMYccSg` — and @0x1019df994 this body calls it with a bare `blr` after only
    ///   the `?.` nil check and a retain: no thunk, no executor check, no async hop. A compiled probe
    ///   settles what that means: calling such a value from a synchronous NONISOLATED context is a
    ///   hard error ("call to main actor-isolated function in a synchronous nonisolated context"),
    ///   and the same file compiles clean once the caller is `@MainActor`. So the enclosing context
    ///   is main-actor isolated.
    ///   ⚑[tool=fieldrec ref=DynamicInfo.displayFPSBlock:0x103cba814 result=SfyYbScMYccSg]
    ///
    /// ⚑ WHICH DECLARATION carries the isolation is NOT recoverable: `@MainActor` on the method and
    ///   `@MainActor` on the class compile to byte-identical assembly. It is written on the method as
    ///   the minimal claim. Note also that the ABSENCE of an entry-level executor check proves
    ///   nothing here — this image emits none for any isolated synchronous function (six SwiftUI
    ///   `View.body` getters, isolated by the protocol, carry zero), so
    ///   `-enable-actor-data-race-checks` is refuted for this build.
    ///
    /// ⚑ The in-loop assertion at 0x1019df8fc carries `#fileID` 'KSPlayer/MediaPlayerProtocol.swift'
    ///   (length 34) and `#line` 138 — THIS file. Five sibling `MediaPlayerProtocol` extension
    ///   getters in it each emit the same construct at their own lines (265, 277, 289, 295, 301).
    ///   ⚑[tool=decode_string_literal ref=DynamicInfo.update:0x103d34c50 result='KSPlayer/MediaPlayerProtocol.swift']
    ///
    /// ⚑ Four spellings the binary does not decide, written as the plainer of each pair: `reduce`
    ///   vs a `for` loop over a local, `guard` vs `if` on the 1.5 s gate, `max(0,·)` vs a ternary for
    ///   the two clamps, and every local identifier (local names survive nowhere in a stripped
    ///   binary).
    @MainActor
    public func update() {
        let time = CACurrentMediaTime()
        let interval = time - lastMediaTime
        guard interval > 1.5 else {
            return
        }
        if let accessLogEvent {
            #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 138)
            droppedVideoFrameCount = accessLogEvent().reduce(0) {
                $0 + UInt32(max(0, $1.numberOfDroppedVideoFrames))
            }
            #sourceLocation()
        }
        if let displayFPSBlock {
            displayFPS = displayFPSBlock()
        } else {
            displayFPS = Float(videoDisplayCount) / Float(interval)
        }
        videoDisplayCount = 0
        let bytesRead = bytesReadBlock()
        // Forward `fcmp s0,#0.0` / `fcsel s9, <0>, s0, ls` = max(x, 0) (`0 >= x ? 0 : x`), not max(0, x).
        networkSpeed = max(Float(bytesRead - lastBytesRead) / Float(interval), 0)
        lastBytesRead = bytesRead
        lastMediaTime = time
    }
}

public struct Chapter {
    public let start: TimeInterval
    public let end: TimeInterval
    public let title: String
}

@MainActor
public protocol MediaPlayerProtocol: MediaPlayback {
    var delegate: MediaPlayerDelegate? { get set }
    /// ⚑ NON-OPTIONAL, corrected from `UIView?`. Witness slot 4 of
    /// `KSMEPlayer : MediaPlayerProtocol` (wt 0x1041d7c68) is named directly in the trie as
    /// `KSPlayer.KSMEPlayer.view.getter : __C.UIView` — mangled `…C4viewSo6UIViewCvg`, with NO
    /// `Sg` suffix. Swift requires a property witness to match the requirement's type exactly
    /// (property requirements are invariant), so the requirement is `UIView`, not `UIView?`.
    /// This is read from a NAMED witness, not from a slot count — slot 4 also happens to be where
    /// the source's own ordering puts `view`, and slot 5 independently resolves to
    /// `KSMEPlayer.playableTime.getter`, the next member in that same order.
    /// ⚑[tool=decode_witness_table ref=KSMEPlayer:MediaPlayerProtocol:0x1041d7c68 result=slot4=view.getter:UIView]
    var view: UIView { get }
    var playableTime: TimeInterval { get }
    var cachedTimeRanges: [CachedTimeRange] { get }
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
    var playbackVolume: Float { get set }
    var contentMode: UIViewContentMode { get set }
    // ⚑ RETYPED to the refined protocol. Requirement index 28 of this protocol's 45; byte +0xe8 of
    //   BOTH conformer witness tables holds the getter DIRECTLY with no reabstraction thunk, so the
    //   requirement's own type is the refined one, not `SubtitleDataSource` with a thunked witness.
    //   `SubtitleDataSource` is a true empty marker in the binary (NumRequirements 0, 8 conformers);
    //   `ConstantSubtitleDataSource` refines it with the single `infos()` method, which is what
    //   `KSPlayerLayer.readyToPlay` awaits through witness +0x10.
    var subtitleDataSource: (any ConstantSubtitleDataSource)? { get }
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    var playbackCoordinator: AVPlaybackCoordinator { get }
    @available(tvOS 14.0, *)
    // The existential, not the concrete class. Both conformers agree in the trie:
    // `KSMEPlayer.pipController` and `KSAVPlayer.pipController` each print
    // `KSPlayer.KSPictureInPictureProtocol?` on getter, setter, modify, property descriptor
    // and direct field offset. Rippled only after verifying BOTH conformers, which is the
    // precondition this migration carries.
    var pipController: (any KSPictureInPictureProtocol)? { get set }
    init(url: URL, options: KSOptions)
    func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions)
    func play()
    func pause()
    func reset()
    func enterBackground()
    func checkShouldResume()
    func enterForeground()
    @MainActor func thumbnailImageAtCurrentTime() async -> CGImage?
    func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack]
    func select(track: some MediaPlayerTrack)
    func configPIP()
}

public extension MediaPlayerProtocol {

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.shutdown():0x1019de8e4 result=3-instr]
    /// Forwards to `#0x78` = word 15 = req14, which KSAVPlayer implements at 0x1019aa34c =
    /// `stop()`.
    func shutdown() {
        stop()
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.checkShouldResume():0x10000e52c result=empty-ICF-fold]
    /// The body IS 0x10000e52c, the canonical ICF-folded empty extension default — so the
    /// default implementation is empty. This is the fold's documented meaning, not an
    /// unresolved address.
    func checkShouldResume() {}

    /// ⚑ s106: the remaining FOUR defaults on this protocol are read but NOT yet transcribed —
    /// `dynamicRange` @0x1019e01dc (94), `videoFormat` @0x1019e04f0 (101),
    /// `audioFormat` @0x1019e0354 (103) and `subtitlesTracks` @0x1019dffb8 (130). They are left
    /// out rather than guessed; each is a real body needing its own read.
    /// ⚑[tool=member_missing_triage ref=MediaPlayerProtocol:4-of-15 result=deferred]

    /// ⚑[tool=decode_string_literal ref=MediaPlayerProtocol.typeName.getter:0x1019dfd34 result='NSStringFromClass(Self.self)']
    /// ⚠️ Transcribed as read, not as intended. The body materialises one 28-character literal
    /// and returns it — `mov x0,#0x1c` / `movk x0,#0xd000,lsl #48` is the count-and-flags word
    /// and x1 the biased pointer; there is no call to NSStringFromClass anywhere in the 7
    /// instructions. Forward ships the EXPRESSION as a string. The decoder confirms the bias
    /// (a wrong-bias read would yield 'ayerProtocol.swift…', the neighbouring #fileID literal).
    var typeName: String {
        "NSStringFromClass(Self.self)"
    }

    /// @0x1019dfdd0 (24 insns) — `(extension in KSPlayer):MediaPlayerProtocol.isPlaying.getter`:
    /// witness +0x48 (playbackState) `== 1` (.playing), then witness +0x50 (loadState) `== 2` (.playable).
    var isPlaying: Bool {
        playbackState == .playing && loadState == .playable
    }

    /// @0x10002dab0 — `(extension in KSPlayer):MediaPlayerProtocol.isExternalPlaybackActive.getter`,
    /// ICF-folded into the shared `mov w0,#0; ret`.
    var isExternalPlaybackActive: Bool {
        false
    }
    /// get @0x1019de638 / set @0x1019de670 / modify @0x1019de718 —
    /// `(extension in KSPlayer):MediaPlayerProtocol.contentMode`: witness +0x28 (`view`) then the
    /// UIView `contentMode` message.
    var contentMode: UIViewContentMode {
        get {
            view.contentMode
        }
        set {
            view.contentMode = newValue
        }
    }

    // Ref 0x1019de7f8 wraps URL, then calls requirement 34.
    func replace(url: URL, options: KSOptions) {
        replace(io: .left(url), options: options)
    }

    // Forward's MainActor closure check in this getter reports #line 265 (`mov w3,#0x109`).
    var nominalFrameRate: Float {
        #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 265)
        tracks(mediaType: .video).first { $0.isEnabled }?.nominalFrameRate ?? 0
        #sourceLocation()
    }

    // ── s106: protocol-extension defaults, each read from its own body ─────────────
    // These are NOT "signature only". Every one is a real default implementation in
    // `(extension in KSPlayer):KSPlayer.MediaPlayerProtocol.*`, 528 instructions in total.
    //
    // The forwarding targets below were DECODED from the witness tables, never counted off
    // declaration order. A protocol-extension body receives the conformance witness table in
    // x1; word 1 of MediaPlayerProtocol's table is its inherited MediaPlayback table (that
    // table's own address, 0x1041d40e8, is literally req0), and within a table requirement i
    // sits at byte offset 8*(i+1). Names come from KSAVPlayer's conformance, whose
    // implementations ARE in the trie:
    //   MediaPlayback req0  0x1019a106c  duration.getter
    //   MediaPlayback req4  0x1019a47e4  currentPlaybackTime.getter
    //   MediaPlayback req11 0x1019ab808  seek(time:completion:)
    //   MediaPlayback req14 0x1019aa34c  stop()            (the note at line 23 above agrees)
    //   MediaPlayerProtocol req42 0x1019aad54  tracks(mediaType:)
    //   MediaPlayerProtocol req43 0x1019aaf58  select(track:)
    // ⚑[tool=decode_witness_table ref=KSAVPlayer:MediaPlayback@0x1041d40e8 result=15-requirements]
    // ⚑[tool=decode_witness_table ref=KSAVPlayer:MediaPlayerProtocol@0x1041d3f78 result=45-requirements]

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.frameRate.getter:0x1019dffb4 result=1-instr]
    /// A single `b 0x1019dfe30`, and the trie names that target
    /// `MediaPlayerProtocol.nominalFrameRate.getter` — the extension member declared above.
    var frameRate: Float {
        nominalFrameRate
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerProtocol.subtitlesTracks.getter:0x1019dffb8 result=130-instr]
    /// The fourth and last `PAAE` extension member of this protocol; `vpMV` proves public.
    ///
    /// Unlike the three above it does NOT filter on `isEnabled` — there is no predicate call in
    /// the loop at all. The only `tbnz` in the body is the tail of the main-actor executor check
    /// (`swift_task_isCurrentExecutor`), which is easy to misread as a filter; the element test
    /// here is the conformance cast, nothing else.
    ///
    ///   · __got 0x104108738 binds `AVMediaTypeSubtitle`, dereferenced into the same
    ///     `[x2,#0x158]` witness that the siblings use — `tracks(mediaType: .subtitle)`.
    ///     ⚑[tool=bind_oracle ref=__got:0x104108738 result=AVMediaTypeSubtitle]
    ///   · the accumulator is seeded from __got 0x104112d00 `_swiftEmptyArrayStorage`, so it
    ///     starts `[]` with no reserved capacity.
    ///   · per element: `swift_conformsToProtocol(track, 0x1039f18dc)` where that descriptor is
    ///     `SubtitleInfo`'s own `…12SubtitleInfoMp`. A null result (`cbz x20`) skips the element —
    ///     that IS the `as?`, and skipping-on-nil is what makes it `compactMap` rather than `map`.
    ///     ⚑[tool=bind_oracle ref=__got:0x104112db8 result=swift_conformsToProtocol]
    ///   · on success it appends the TWO-word existential with
    ///     `stp x27, x20, [x9,#0x20]` — instance and witness table together — after the usual
    ///     uniqueness check and a `cmp x21, x8, lsr #1` capacity test.
    ///
    /// ⚑ `compactMap` vs `filter`-then-`map` is not decidable from this body: both lower to one
    ///   append loop over an empty seed. `compactMap` is written because the cast and the skip are
    ///   the SAME test here — there is no separate predicate pass to correspond to a `filter`.
    // Forward's MainActor closure check reports #line 277.
    var subtitlesTracks: [any SubtitleInfo] {
        #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 277)
        tracks(mediaType: .subtitle).compactMap { $0 as? SubtitleInfo }
        #sourceLocation()
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.audioTracks.getter:0x1019e01c0 result=7-instr]
    /// Loads `__got 0x104108730`, which binds `_AVMediaTypeAudio`, and tail-calls `#0x158` =
    /// word 43 = req42 = `tracks(mediaType:)`.
    /// ⚑[tool=bind_oracle ref=__got:0x104108730 result=_AVMediaTypeAudio]
    var audioTracks: [MediaPlayerTrack] {
        tracks(mediaType: .audio)
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerProtocol.dynamicRange.getter:0x1019e01dc result=94-instr]
    /// A `PAAE` extension member with a `vpMV` — public proven, no witness slot. Same track search
    /// as `videoFormat` above: __got 0x104108740 (`AVMediaTypeVideo`) into the witness at
    /// `[x2,#0x158]`, then the loop picks the first track whose `[x26,#0x58]` getter is true.
    ///
    /// The two exits are read, and they are what pin the return type's representation:
    ///   · loop exhausted → release the array and `mov w0, #0x4`. `DynamicRange` has four cases
    ///     (tags 0…3), so case index **4 is `Optional.none`** — this arm returns nil.
    ///   · a hit → release the array and tail-call 0x1019de560, the track's own `dynamicRange`
    ///     (trie: `…MediaPlayerTrackPAAE12dynamicRange…`), returning its value unchanged.
    ///
    /// ⚑ That `mov w0,#4` independently confirms the five-entry table decoded for `videoFormat`
    ///   above, whose index 4 held the `(0,0)` word pair: two unrelated bodies agree that 4 is the
    ///   nil inhabitant of `DynamicRange?`.
    // Forward's MainActor closure check reports #line 289 (`mov w3,#0x121`).
    var dynamicRange: DynamicRange? {
        #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 289)
        tracks(mediaType: .video).first { $0.isEnabled }?.dynamicRange
        #sourceLocation()
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerProtocol.audioFormat.getter:0x1019e0354 result=103-instr]
    /// An EXTENSION member, not a protocol requirement: the symbol mangles `…PAAE11audioFormat…`
    /// (`PAAE` = extension-of-protocol), so it occupies no witness slot. It carries a `vpMV`, so
    /// **public is proven**, not inherited from the enclosing `public extension`.
    ///
    /// Placement is fixed by the body's own literal, not by the neighbours: the isolation-check
    /// diagnostic passes the 34-character StaticString 'KSPlayer/MediaPlayerProtocol.swift' with
    /// line 295, which is inside this very extension.
    /// ⚑[tool=decode_string_literal ref=0x103d34c50 result='KSPlayer/MediaPlayerProtocol.swift']
    ///
    /// Read end to end:
    ///   · `ldr x8,[0x104108730]` → __got bind `AVMediaTypeAudio`, dereferenced and passed to the
    ///     witness at `[x2,#0x158]`, whose result is an array — that is `tracks(mediaType: .audio)`.
    ///     ⚑[tool=bind_oracle ref=__got:0x104108730 result=AVMediaTypeAudio]
    ///   · the loop walks that array by index (`x22`, stride 0x10, bound `[x19,#0x10]`) and calls
    ///     the element witness at `[x26,#0x58]`, testing the result with `tbnz w20,#0` — a BIT
    ///     test, so the requirement returns Bool. `b.hs` past the count traps at `brk #0x1`.
    ///   · falling out of the loop releases the array and returns nil (`x0=0`,`x1=0`).
    ///   · on a hit it compares the element's type against class metadata 0x1044e91c8 and, when
    ///     equal and non-nil, loads 16 bytes at `+0x18` and returns them as the String.
    ///
    /// The two names in that last step are READ, never guessed:
    ///   · 0x1044e91c8 is `FFmpegAssetTrack`'s metadata (trie).
    ///   · `+0x18` is `codecName` — field index 1 in that class's own field-offset vector
    ///     (@0x1044e9218), not an offset inferred from this access site.
    /// ⚑[tool=field_offset_vector ref=FFmpegAssetTrack:0x1039ef114 result=codecName@0x18]
    ///
    /// `isEnabled` is identified STRUCTURALLY, not by counting slots. MediaPlayerTrack's
    /// requirement kinds are `B GGGGGGGGGG SM GGGG` — exactly ONE `{get set}` triple in the whole
    /// protocol, at 10/11/12 — and `[x26,#0x58]` is its getter. Of the source's settable members
    /// only `isEnabled` is Bool, and the `tbnz` proves the return is a bit, which excludes the
    /// Float one. ⚑[tool=protocol_signature ref=MediaPlayerTrack:0x1039ed8b4 result=one-get-set-triple]
    ///
    /// ⚑ The type test is an EXACT metadata compare (`cmp x0, x8`), not a subclass-tolerant check,
    ///   even though `FFmpegAssetTrack` is not declared `final`. That is the whole-module form of
    ///   `as?` when no subclass exists in the module; it is recorded here because it would also be
    ///   consistent with `type(of:) ==`, and those two are not distinguishable from this body.
    // Forward's MainActor closure check reports #line 295 (`mov w3,#0x127`).
    var audioFormat: String? {
        #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 295)
        (tracks(mediaType: .audio).first { $0.isEnabled } as? FFmpegAssetTrack)?.codecName
        #sourceLocation()
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerProtocol.videoFormat.getter:0x1019e04f0 result=101-instr]
    /// Also a `PAAE` extension member with a `vpMV` — public proven, no witness slot.
    ///
    /// ⚠️ It is NOT the audio getter with the media type swapped, which is what its near-identical
    /// size suggests. The track search is the same shape — __got 0x104108740 binds
    /// `AVMediaTypeVideo`, the same witness `[x2,#0x158]` returns the array, the same
    /// `[x26,#0x58]`/`tbnz` picks the first enabled track — but the TAIL is a different mechanism
    /// entirely, so the two were read separately.
    /// ⚑[tool=bind_oracle ref=__got:0x104108740 result=AVMediaTypeVideo]
    ///
    /// Where `audioFormat` reads a stored String off a cast, this one calls
    /// `MediaPlayerTrack.dynamicRange` (0x1019de560, trie:
    /// `…MediaPlayerTrackPAAE12dynamicRange…` — itself an extension member) and turns the result
    /// into a String through an INLINED table rather than a call:
    ///   `ubfiz x8, x19, #3, #8` scales the returned case index by 8 and indexes two parallel
    ///   word tables at 0x1035684a8 and 0x1035684d0 — the (bytes, count/flags) halves of a Swift
    ///   String. The tables sit 0x28 apart, so there are exactly FIVE entries, matching
    ///   `DynamicRange?`: four cases plus nil.
    ///
    /// The five entries were decoded, not assumed:
    ///   0 → 'SDR' · 1 → 'HDR10' · 2 → 'HLG' · 3 → 'Dolby Vision' · 4 → (0,0)
    /// That is `DynamicRange.description` (PlayerDefines.swift:105) inlined verbatim — the strings
    /// and their tag order match that already-reconstructed switch exactly, which cross-checks both
    /// this decode and that earlier body.
    ///
    /// ⚑ There is NO branch on the dynamicRange result, and that is not a missing nil check: entry
    ///   4 is the (0,0) word pair, which IS `String?.none`. The optional chain is folded into the
    ///   table, so `?.description` returning nil for a nil range is the table lookup itself.
    ///
    /// ⚑ L7: the chain is spelled out here, NOT the sibling call. The prologue matches the sibling
    ///   `dynamicRange` getter, but its MainActor closure check reports line 0x12d (301) where the
    ///   sibling's reports 0x121 (289) — a closure of its own, six lines after `audioFormat`'s
    ///   (0x127, 295). An inlined sibling would carry the sibling's line.
    var videoFormat: String? {
        #sourceLocation(file: "KSPlayer/MediaPlayerProtocol.swift", line: 301)
        tracks(mediaType: .video).first { $0.isEnabled }?.dynamicRange?.description
        #sourceLocation()
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.progress.getter:0x1019e0684 result=24-instr]
    /// Calls req0 into d8; `movi.2d v0,#0` then `fcmp d8,#0.0` / `b.eq` returns 0 when the
    /// duration is zero; otherwise calls req4 and `fdiv d0, d0, d8`.
    var progress: CGFloat {
        // Forward calls req0 (duration) ONCE and keeps it in d8 for both the zero test and the fdiv.
        let total = duration
        return total == 0 ? 0 : currentPlaybackTime / total
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.totalTime.getter:0x1019e06e4 result=3-instr]
    /// `ldr x1,[x1,#0x8]` takes the inherited MediaPlayback table, `ldr x2,[x1,#0x8]` takes its
    /// word 1 = req0 = `duration`, then tail-calls it.
    var totalTime: TimeInterval {
        duration
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.currentTime.getter:0x1019e06f0 result=3-instr]
    /// Same shape at `#0x28` = word 5 = req4 = `currentPlaybackTime`.
    var currentTime: TimeInterval {
        currentPlaybackTime
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.remainingTime.getter:0x1019e06fc result=21-instr]
    /// Calls req0 into d8, then req4, then `fsub d0, d8, d0`.
    var remainingTime: TimeInterval {
        duration - currentPlaybackTime
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.set(audioTrack:):0x1019e0750 result=7-instr]
    /// Pure argument shuffle into a tail-call of `#0x160` = word 44 = req43 = `select(track:)`.
    func set(audioTrack: some MediaPlayerTrack) {
        select(track: audioTrack)
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerProtocol.updateProgress(to:):0x1019e076c result=23-instr]
    /// `fmul d0, d8, d0` multiplies the incoming CGFloat by req0 (`duration`), then tail-calls
    /// word 12 = req11 = `seek(time:completion:)`. The completion is passed as function pointer
    /// 0x10000e52c with a null context — 0x10000e52c is the canonical ICF-folded empty body, so
    /// the closure is empty.
    func updateProgress(to progress: CGFloat) {
        seek(time: progress * duration) { _ in }
    }
}

@MainActor
/// ⚑ s107: the descriptor declares **8** requirements and this protocol listed 5. The full order is
/// READ, by walking `KSPlayerLayer`'s witness table @0x1041d49b8 slot by slot — some slots name
/// their witness outright, the rest are thunks whose `ldr x3, [x8, #imm]` maps through
/// `KSPlayerLayer`'s vtable (`VTableOffset = 27 words`, so slot = (imm − 0xd8) / 8):
///
///   req0 +0x08 → slot 69 `readyToPlay(player:)`        req4 +0x28 `playBack(player:loopCount:)`
///   req1 +0x10 → slot 70 `changeLoadState(player:)`    req5 +0x30 → slot 73 **`reachEndOfStream(player:)`**
///   req2 +0x18 `changeBuffering(player:progress:)`     req6 +0x38 → slot 74 `finish(player:error:)`
///   req3 +0x20 → slot 59 **`changePlaybackTime(player:time:)`**   req7 +0x40 **`playerDidClear(player:)`**
///
/// A requirement's index IS its witness-table slot, so the two added below sit at 5 and 7 rather
/// than being appended.
///
/// ⚑ req3 `changePlaybackTime(player:time:)` is the `KSPlayerLayer` witness at slot 59
/// (body 0x1019cc2b8..0x1019cc5f8); its declaration and implementation are paired below.
public protocol MediaPlayerDelegate: AnyObject {
    func readyToPlay(player: some MediaPlayerProtocol)
    func changeLoadState(player: some MediaPlayerProtocol)
    // 缓冲加载进度，0-100
    func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8)
    func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval)
    func playBack(player: some MediaPlayerProtocol, loopCount: Int)
    func reachEndOfStream(player: some MediaPlayerProtocol)
    func finish(player: some MediaPlayerProtocol, error: Error?)
    func playerDidClear(player: some MediaPlayerProtocol)
}

public protocol MediaPlayerTrack: AnyObject, CustomStringConvertible {
    var mediaType: AVFoundation.AVMediaType { get }
    var name: String { get }
    // ⚑[tool=type_surface ref=MediaPlayerTrack:requirements result=getter-only] Forward's requirement
    // list has one lone getter here (the only setter/modify pair follows the tenth getter), and
    // AVMediaPlayerTrack stores it as `let` (field_surface), so no setter is required.
    var nominalFrameRate: Float { get }
    var bitRate: Int64 { get }
    var trackID: Int32 { get }
    var bitDepth: Int32 { get }
    // protocol_surface: Forward witness 0x40 `reorderSize` (Swift.Int32), between bitDepth 0x38 and rotation 0x48.
    var reorderSize: Int32 { get }
    // ⚑ s104: UInt16, not Int16. All THREE conformers spell it UInt16 in the binary —
    // KSPlayer.FFmpegAssetTrack.rotation.getter, KSPlayer.MetalPlayView.rotation.getter and
    // KSPlayer.AVMediaSelectionTrack.rotation.getter all demangle to `: Swift.UInt16`, and
    // FFmpegAssetTrack's field record resolves through __got 0x104112ad8 to the UInt16 nominal
    // type descriptor. Rippling the protocol only after every conformer agreed is the rule this
    // change was made under.
    var rotation: UInt16 { get }
    var fieldOrder: FFmpegFieldOrder { get }
    var isEnabled: Bool { get set }
    var isImageSubtitle: Bool { get }
    var languageCode: String? { get }
    var dovi: DOVIDecoderConfigurationRecord? { get }
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
    public var dv_bl_signal_compatibility_id: UInt8
    /// ⚑[tool=export_trie_oracle ref=DOVIDecoderConfigurationRecord.dv_md_compression.getter:0x100137314 result=UInt8]
    /// A ninth field the source lacked. Its getter is the whole of two instructions,
    /// `mov x0, x1` / `ret` — it returns the SECOND register, which for a 9-byte struct passed in
    /// registers is byte 8, i.e. the field after `dv_bl_signal_compatibility_id`.
    /// Placement is corroborated, not assumed from that alone: this struct mirrors FFmpeg's
    /// `AVDOVIDecoderConfigurationRecord`, and in THIS build's header
    /// (FFmpeg-n8.1.1/libavutil/dovi_meta.h) `dv_md_compression` is the ninth and last `uint8_t`,
    /// immediately after `dv_bl_signal_compatibility_id`. The first eight already match in order.
    /// `fieldrec` cannot arbitrate here — the struct is not in the classmap — so the header and
    /// the register position are the evidence.
    /// Access read: carries a vpMV, so public. No vpfi among its symbols, so no declaration
    /// default, which matches the other eight being plain `let`.
    /// ⚠️ The getter address is an 18-symbol ICF fold; the two instructions are genuinely this
    /// getter's code but carry nothing unique to it, which is why the placement rests on the
    /// header rather than on the body.
    public let dv_md_compression: UInt8
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

    var naturalSize: CGSize {
        formatDescription?.naturalSize ?? .zero
    }

    var dynamicRange: DynamicRange? {
        if let dovi {
            // Forward @0x1019de560: `(x0 & 0xff0000) == 0x70000` (dv_profile == 7) →
            // KSOptions.forceDVForProfile7 ? tag 3 (.dolbyVision) : tag 1 (.hdr10).
            if dovi.dv_profile == 7 {
                return KSOptions.forceDVForProfile7 ? .dolbyVision : .hdr10
            }
            return .dolbyVision
        } else {
            return formatDescription?.dynamicRange
        }
    }

    /// ⚑[tool=llvm-objdump ref=MediaPlayerTrack.isDovi.getter:0x1019de614 result=8-instr]
    /// `bl 0x1019de560` — which the trie names `MediaPlayerTrack.dynamicRange.getter` (the
    /// property directly above) — then `and w8,w0,#0xff` / `cmp w8,#0x3` / `cset w0,eq`.
    /// ⚠️ 3 is the CASE TAG, not the raw value. `DynamicRange`'s raw values are 0,2,3,5 but its
    /// tags are 0,1,2,3, so tag 3 is `.dolbyVision` — raw value 3 would have been `.hlg`. The
    /// note at PlayerDefines.swift:54 established that tag/raw split independently.
    var isDovi: Bool {
        dynamicRange == .dolbyVision
    }

    var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    /// ⚑ s106: the other TWO MediaPlayerTrack extension defaults are read but NOT transcribed —
    /// `videoRange` @0x1019e0d20 (53) and `codecs` @0x1019e0bc8 (86). videoRange is decoded as
    /// far as its three small-string immediates (0xE3 "HLG", 0xE2 "PQ", 0xE3 "SDR", selected on
    /// the dynamicRange tag) but it also branches on a second witness call at table word 16
    /// whose requirement is not yet named, so it is left out rather than half-written.
    /// ⚑[tool=member_missing_triage ref=MediaPlayerTrack:2-of-3 result=deferred]

    var colorSpace: CGColorSpace? {
        KSOptions.colorSpace(ycbcrMatrix: yCbCrMatrix as CFString?, transferFunction: transferFunction as CFString?)
    }

    var mediaSubType: CMFormatDescription.MediaSubType {
        formatDescription?.mediaSubType ?? .boxed
    }

    var audioStreamBasicDescription: AudioStreamBasicDescription? {
        formatDescription?.audioStreamBasicDescription
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
    var language: String? {
        languageCode.flatMap {
            Locale.current.localizedString(forLanguageCode: $0)
        }
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerTrack.codecs.getter:0x1019e0bc8 result=86-instr]
    /// A `PAAE` extension member with a `vpMV` — public proven, no witness slot. It reaches the
    /// same `dovi` requirement `videoRange` below uses (`[x22,#0x80]`, optional tag in `w1`'s byte
    /// 1), and reads the same two bytes of it: `ubfx w26,w8,#16,#8` = `dv_profile` and
    /// `lsr x25,x8,#56` = `dv_bl_signal_compatibility_id`.
    ///
    /// The three FourCCs are read from the instructions, not from a codec table:
    ///   · `mov w0,#0x6831` + `movk w0,#0x6476,lsl#16` → 0x64766831 = 'dvh1'
    ///   · `mov w8,#0x3031` + `movk w8,#0x6176,lsl#16` → 0x61763031 = 'av01'
    ///   · the small-string immediate 0x31766164 with count byte 0xE4 → the 4-char String "dav1"
    ///
    /// ⚑ WHY THE THIRD ONE IS SPELLED DIFFERENTLY, and why that is evidence rather than style:
    ///   'dvh1' and 'av01' appear as bare immediates, so the source names existing CoreMedia
    ///   constants. 'dav1' instead goes through
    ///   `_CMFormatDescriptionFourCCConvertible.init(string:)` (__got 0x104113208) followed by
    ///   `CMFormatDescription.MediaSubType.rawValue` (__got 0x104113278), with the MediaSubType
    ///   metadata fetched at 0x103458488 and stack-allocated from its value witness. CoreMedia has
    ///   no constant for 'dav1', which is exactly why only that one is built from a string.
    ///
    /// Control flow, read off the branches:
    ///   profile 5 → 'dvh1'; profile 8 with compatibility 1 → 'dvh1' (`ccmp x25,#1,#0,eq`);
    ///   profile 10 AND `codecType == 'av01'` (`ccmp w0,w8,#0,eq`) AND compatibility 1 or 4
    ///   (`cmp w25,#4` / `cmp w25,#1`) → the "dav1" subtype; every other path falls to `codecType`.
    ///
    /// ⚑ Despite the `UInt32?` return every path yields `.some` — the returns go through
    ///   `mov w0, w0`, which zero-extends into the tag bits. There is no nil arm in this body.
    var codecs: UInt32? {
        if let dovi {
            if dovi.dv_profile == 5 {
                return kCMVideoCodecType_DolbyVisionHEVC
            }
            if dovi.dv_profile == 8, dovi.dv_bl_signal_compatibility_id == 1 {
                return kCMVideoCodecType_DolbyVisionHEVC
            }
            // Forward @0x1019e0c98 calls codecType BEFORE the profile test
            // (`bl codecType` / `cmp w26,#10` / `ccmp w0,'av01'`), so codecType is the first operand.
            if codecType == kCMVideoCodecType_AV1, dovi.dv_profile == 10,
               dovi.dv_bl_signal_compatibility_id == 1 || dovi.dv_bl_signal_compatibility_id == 4
            {
                return CMFormatDescription.MediaSubType(string: "dav1").rawValue
            }
        }
        return codecType
    }

    /// ⚑[tool=export_trie_oracle ref=MediaPlayerTrack.videoRange.getter:0x1019e0d20 result=53-instr]
    /// A `PAAE` extension member with a `vpMV` — public proven, no witness slot.
    ///
    /// It opens by calling the sibling `dynamicRange` (0x1019de560) and testing
    /// `and w8, w0, #0xff` / `cmp w8, #4`: case index 4 is `Optional.none`, so that is the nil
    /// guard. ⚑ This is the THIRD independent body to pin 4 as the nil inhabitant of
    /// `DynamicRange?` — the other two are `MediaPlayerProtocol.dynamicRange`'s `mov w0,#4` exit
    /// and the five-entry string table in `videoFormat`.
    ///
    /// The Dolby-Vision early-out is identified by STRUCT LAYOUT, not by witness index. The call
    /// through `[x22,#0x80]` returns a two-register value, and the bytes it tests land exactly on
    /// `DOVIDecoderConfigurationRecord`'s declared fields (this file, above):
    ///   · `ubfx w9, w0, #16, #8` → byte 2 = `dv_profile`, compared against 8 and 10.
    ///   · `lsr  x8, x0, #56`     → byte 7 = `dv_bl_signal_compatibility_id`, compared against 4
    ///     on BOTH profile branches (`b.eq` then `cmp x8,#4`, and a `ccmp x8,#4,#0,eq`).
    ///   · `and w8, w1, #0xff00` / `cmp w8, #0x100` → the optional tag in the second register;
    ///     equal means nil, which skips straight to the switch.
    /// That nine-`UInt8` layout is what makes the callee `dovi` — a nine-byte struct in two
    /// registers with the tag in x1 — rather than any other trailing requirement.
    ///
    /// The switch is read off the `csel` pair, not guessed: `ands w8, w21, #0xff` sets `eq` only
    /// for case 0, selecting 'SDR' (count 3) over 'PQ' (count 2); then `cmp w8, #2` selects 'HLG'
    /// (count 3) over that result. So .sdr→SDR, .hlg→HLG, and both .hdr10 and .dolbyVision→PQ.
    /// The three literals are small-string immediates: 0x474c48='HLG', 0x5150='PQ', 0x524453='SDR'.
    ///
    /// ⚑ The dovi condition's SPELLING is ambiguous — two `if`s, a `||`, or a comma-separated
    ///   `if let` all lower to this compare-and-branch pair. Only the predicate is established:
    ///   (profile == 8 || profile == 10) && compatibility_id == 4.
    var videoRange: String? {
        guard let dynamicRange else {
            return nil
        }
        // Forward @0x1019e0d80-0x1019e0d98: profile 8 branches to its own `cmp x8,#4`, profile 10 uses
        // `ccmp x8,#4` — two separate arms, not the merged `(p|2)==10` test the `||` form lowers to.
        // ⚑ Arm order: swiftc lays the SECOND source arm out as the `b.eq` branch and the first as the
        //   fall-through `ccmp`; Forward branches on 8 and ccmps 10, so the profile-10 arm is first
        //   (checked with Xcode 6.3 swiftc -O on an isolated copy: 8-first gives `cmp #0xa; b.eq`).
        if let dovi {
            if dovi.dv_profile == 10, dovi.dv_bl_signal_compatibility_id == 4 {
                return "HLG"
            } else if dovi.dv_profile == 8, dovi.dv_bl_signal_compatibility_id == 4 {
                return "HLG"
            }
        }
        // Forward csel chain: outer `cmp w8,#2` (hlg), inner `ands w8,#0xff` (sdr) — hlg is tested first.
        switch dynamicRange {
        case .hlg:
            return "HLG"
        case .sdr:
            return "SDR"
        default:
            return "PQ"
        }
    }
}

public extension CMFormatDescription {
    var dynamicRange: DynamicRange {
        let contentRange: DynamicRange
        if codecType.string == "dvhe" || codecType == kCMVideoCodecType_DolbyVisionHEVC {
            contentRange = .dolbyVision
        } else if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { /// HDR
            // Forward @0x101a0abb4 has no bitDepth test: dvhe/dvh1 → PQ → HLG → (no transfer, BT.2020) → SDR.
            contentRange = .hdr10
        } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { /// HLG
            contentRange = .hlg
        } else if transferFunction == nil, colorPrimaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String {
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
    /// @0x101a0b744 — extensions → DisplayWidth/DisplayHeight NSNumber.integerValue; both > 0 → size, else nil.
    public var displaySize: CGSize? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary?,
           let width = (dictionary[kCVImageBufferDisplayWidthKey] as? NSNumber)?.intValue,
           let height = (dictionary[kCVImageBufferDisplayHeightKey] as? NSNumber)?.intValue,
           width > 0, height > 0
        {
            return CGSize(width: width, height: height)
        }
        return nil
    }

    /// @0x101a0ba94 — extensions as? [String: Any] → "SampleDescriptionExtensionAtoms" as? [String: Any] → "hvcC" as? Data.
    public var hevcExtradata: Data? {
        // Forward @0x101a0bc58: the `as? Data` failure `tbz`s to the shared nil return (no csel),
        // so the Data cast is the third binding of the chain, not a returned `as?`.
        if let extensions = CMFormatDescriptionGetExtensions(self) as? [String: Any],
           let atoms = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any],
           let hvcC = atoms["hvcC"] as? Data
        {
            return hvcC
        }
        return nil
    }

    /// @0x101a6362c — ASBD +0x1c (mChannelsPerFrame), nil → 0.
    public var channelCount: UInt32 {
        CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee.mChannelsPerFrame ?? 0
    }

    /// @0x101a6364c — ASBD +0x0 (mSampleRate), nil → 0.
    public var sampleRate: Double {
        CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee.mSampleRate ?? 0
    }

    /// @0x101a6368c — `mov x0,x20; b objc_retain`.
    public var formatDescription: CMFormatDescription {
        self
    }

    /// @0x101a65204 — ASBD +0x20 (mBitsPerChannel), nil → 0.
    public var sampleSize: UInt32 {
        CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee.mBitsPerChannel ?? 0
    }

    /// @0x101a65224 — nil / non-'lpcm' → .otherFormat; float flag: 32 → Float32, 64 → Float64;
    /// integer: 16 → Int16, 24/32 → Int32; anything else → .otherFormat.
    public var commonFormat: AVAudioCommonFormat {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM
        else {
            return .otherFormat
        }
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            switch asbd.mBitsPerChannel {
            case 32:
                return .pcmFormatFloat32
            case 64:
                return .pcmFormatFloat64
            default:
                return .otherFormat
            }
        } else {
            // Forward @0x101a65258-0x101a65270: 16 branches; then `csel` (==32 inner, ==24 outer).
            switch asbd.mBitsPerChannel {
            case 16:
                return .pcmFormatInt16
            case 24:
                return .pcmFormatInt32
            case 32:
                return .pcmFormatInt32
            default:
                return .otherFormat
            }
        }
    }

    /// @0x101a652b0 — nil / non-'lpcm' → false; else !(flags & kAudioFormatFlagIsNonInterleaved).
    public var isInterleaved: Bool {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM
        else {
            return false
        }
        return asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    }

    /// @0x101a652f8 — tail call CMAudioFormatDescriptionGetChannelLayout(self, nil).
    public var layout: UnsafePointer<AudioChannelLayout>? {
        CMAudioFormatDescriptionGetChannelLayout(self, sizeOut: nil)
    }
}

/// Forward @0x101a04924 (150 insns): no `useSystemHTTPProxy` guard — the body opens with
/// CFNetworkCopySystemProxySettings; the caller (MEPlayerItem open) tests the option.
func setHttpProxy() {
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
