import AVFoundation
import AVKit
#if canImport(UIKit)
import UIKit
#else
import AppKit

public typealias UIImage = NSImage
#endif
import Combine
import CoreGraphics

public final class KSAVPlayerView: UIView {
    public let player = AVQueuePlayer()
    override public init(frame: CGRect) {
        super.init(frame: frame)
        #if !canImport(UIKit)
        layer = AVPlayerLayer()
        #endif
        playerLayer.player = player
        player.automaticallyWaitsToMinimizeStalling = false
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var contentMode: UIViewContentMode {
        get {
            switch playerLayer.videoGravity {
            case .resize:
                return .scaleToFill
            case .resizeAspect:
                return .scaleAspectFit
            case .resizeAspectFill:
                return .scaleAspectFill
            default:
                return .scaleAspectFit
            }
        }
        set {
            switch newValue {
            case .scaleToFill:
                playerLayer.videoGravity = .resize
            case .scaleAspectFit:
                playerLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                playerLayer.videoGravity = .resizeAspectFill
            case .center:
                playerLayer.videoGravity = .resizeAspect
            default:
                break
            }
        }
    }

    #if canImport(UIKit)
    override public class var layerClass: AnyClass { AVPlayerLayer.self }
    #endif
    fileprivate var playerLayer: AVPlayerLayer {
        // swiftlint:disable force_cast
        layer as! AVPlayerLayer
        // swiftlint:enable force_cast
    }
}

@MainActor
open class KSAVPlayer {
    // Forward 1.3.17 stored fields — reflection order (desc 0x1039ec148); reconstructed session 16 (KSAVPlayer M1 fields).
    // Recon KVO NSKeyValueObservations → Combine observer cancellables; `urlAsset` → `io: Either<URL, AVAsset>`.
    // Every stored field carries an explicit `: Type` annotation. Method bodies that used the removed fields are
    // grounded `⚑ UNRESOLVED → KSAVPlayer M2` stubs (the AVPlayer-wrapper bodies are M2).
    //
    // ⚑[tool=vtable_walk ref=KSAVPlayer.nominalTypeDescriptor:0x1039ec148 result=LOCATED] the 103-slot vtable
    //   (VTableDescriptorHeader @0x1039ec180) lays out one getter/setter/_modify triple per property in DECLARATION
    //   ⚠️ s97 — every "slot" number in this file's comments is really the vtable IDX; they are off
    //   by VTableOffset=38. Spot-checked: "slot 47 @0x1019a1380" is idx47 slot85 (chapters.setter),
    //   "slots 61–63" is idx61–63 (getter @0x1019a1a3c = idx61 slot99), and 18–20/46–48 likewise
    //   resolve in idx space and not in slot space. Record both as `idx<N> slot<M>`.
    //   order, and every one of those accessors is COMPILER-GENERATED for the stored fields below — there is no source
    //   text to recover for them. The live ones are slots 6 (io getter), 9–11 (shouldSeekTo), 18–20 (subtitleTracks),
    //   30–32 (pipController), 33–35 (delegate), 36–38 (duration), 39–41 (fileSize), 46–48 (chapters), 49–51
    //   (naturalSize) and 58/59 (error get/set). Proof of shape: each body does nothing but
    //   `swift_beginAccess(self + <field-offset global @0x104c63048…0x104c630a0>, …)` and then loads (getter, flags 0)
    //   / stores (setter, flags 1) / yields (`_modify`, flags 0x21 = Modify|Tracking) that address. Control: the same
    //   compiler's output for THIS file — KSAVPlayer.delegate.setter / .delegate.modify / .naturalSize.modify in
    //   reconstruction/KSPlayer_recon_s59.dylib — matches instruction-for-instruction (only the offset-global and stub
    //   addresses differ, plus a back-deployment `coroFrameAlloc` availability check Forward carries and the dylib does
    //   not), down to the `coroFrameAlloc(0x38, 0xbed)` frame magic. All-dropped accessors leave an all-null
    //   triple (playerLooper 12–14, mediaPlayerTracks 15–17, the three observer*Cancellables sets 21–29,
    //   shouldResumePlayback 52–54) — which is how the field↔slot alignment above was cross-checked.
    // ⚑[tool=dyld_info ref=KSPlayer.KSAVPlayer.io.setter:0x10198eb18 result=LOCATED] Forward's export trie carries 37
    //   KSAVPlayer accessor symbols, ALL aliasing one address, 0x10198eb18 = the shared `swift_deletedMethodError`
    //   stub — i.e. exactly the accessors the optimiser dropped (they match the all-null triples above). Their mangled
    //   names show `io`, `error`, `options` and `shouldResumePlayback` with NO fileprivate discriminator, in contrast
    //   to `(cancellable in _96682D5E1A2F36FD0BE1DC3A2D928BC7)`, so those four are NOT `private` in Forward. Left
    //   spelled `private` here on purpose: mangling cannot separate internal from public, and widening the access
    //   level re-scopes their l2 field checks from UNCHECKED to CHECKED for a reason unrelated to this batch.
    var cancellable: AnyCancellable?
    var periodicTimeObserver: Any?
    private let playerView: KSAVPlayerView = KSAVPlayerView()
    public var io: Either<URL, AVAsset>
    public var shouldSeekTo: Double?
    var playerLooper: AVPlayerLooper?
    var mediaPlayerTracks: [any MediaPlayerTrack] = []
    public var subtitleTracks: [any MediaPlayerTrack] = []
    var observerCancellables: Set<AnyCancellable> = []
    var observerPlayerItemCancellables: Set<AnyCancellable> = []
    var observerLoopCancellables: Set<AnyCancellable> = []
    // DIVERGENCE DISCHARGED (opened s16, closed s98). Binary field 11 is
    // `(any KSPictureInPictureProtocol)?` — field record `KSPictureInPictureProtocol_pSg`, and the
    // trie prints the same for this class's accessors. The protocol it needed is now declared.
    public private(set) var pipController: (any KSPictureInPictureProtocol)?
    public weak var delegate: MediaPlayerDelegate?
    public private(set) var duration: TimeInterval = 0
    // Forward 1.3.17: `fileSize` is `Int64` (known-answer control 0x10536e600 == Int64 via Foundation.Progress / Alamofire
    //   byte-count fields). MediaPlayback.fileSize migrated Double→Int64 (session 16b); l2 UNCHECKED (GOT-external field-record).
    public private(set) var fileSize: Int64 = 0
    public private(set) var playableTime: TimeInterval = 0
    // ⚑[tool=vtable_walk ref=KSAVPlayer.nominalTypeDescriptor:0x1039ec148 result=LOCATED] Forward declares ONE MORE
    //   member between `playableTime` and `chapters` that has no counterpart here: vtable slot 45, a lone live getter
    //   @0x1019a1244 (get-only — no setter/_modify slot follows it, and the playableTime triple 42–44 and the chapters
    //   triple 46–48 bracket it). What the body establishes without guessing: it returns an Array (one path returns
    //   `__swiftEmptyArrayStorage`), it reads the stored `duration` field and takes the empty-array path when
    //   `duration <= 0`, it performs a `swift_dynamicCast`, and it dispatches a method at metadata offset +0x458 on
    //   self. Type and name are not established — a genuinely un-reconstructed computed property, not an artifact.
    // Forward stores `chapters` MUTABLY, not as a `let`: the vtable carries a live setter (slot 47 @0x1019a1380,
    // tail-calling the module-shared outlined accessor @0x1005a07d4, fan-in 14) AND a live `_modify` coroutine
    // (slot 48 @0x1019a138c, `swift_beginAccess` flags 0x21 = Modify|Tracking on the `chapters` ivar-offset global
    // @0x104c63088) — neither is the deleted-method stub. Control: this file's own `public let chapters` compiles to a
    // getter ONLY — `nm reconstruction/KSPlayer_recon_s59.dylib | grep KSAVPlayerC8chapters` yields zero `vs`/`vM`
    // symbols — so a live setter+`_modify` pair can only come from a `var`.
    // The setter's ACCESS LEVEL *is* decidable, and it is plain `public` — `private(set)` is refuted. A
    // `private(set)` setter is not overridable, so the compiler emits NO modify coroutine for it; only plain
    // `public var` emits the getter/setter/modify triple that slots 46–48 carry. Compiled both spellings and read
    // `sil_vtable` (P110 — the same lever that settled the addSubtitle overload pair @108752e):
    //   public private(set) var chapters -> #chapters!getter, #chapters!setter                (2 entries, NO modify)
    //   public var chapters              -> #chapters!getter, #chapters!setter, #chapters!modify (3 entries)
    // Slot 48 @0x1019a138c is a live modify, so the declaration cannot be `private(set)`.
    // (Superseded reasoning, recorded so it is not re-derived: `private(set)` had been chosen on convention —
    //  MediaPlayerProtocol asks only for `{ get }` and the sibling MEPlayerItem.chapters is spelled that way —
    //  on the false premise that both spellings emit the same three slots. Convention lost to compilation.)
    public var chapters: [Chapter] = []
    public var naturalSize: CGSize = .zero
    var shouldResumePlayback: Bool = false
    public var options: KSOptions {
        didSet {
            player.currentItem?.preferredForwardBufferDuration = options.preferredForwardBufferDuration
            cancellable = options.$preferredForwardBufferDuration.sink { [weak self] newValue in
                self?.player.currentItem?.preferredForwardBufferDuration = newValue
            }
        }
    }

    public var error: Error? {
        didSet {
            if let error {
                delegate?.finish(player: self, error: error)
            }
        }
    }

    // binary `$__lazy_storage_$_dynamicInfo` (reflection-filtered lazy backing); recon had `let dynamicInfo = nil`.
    // ⚑ UNRESOLVED → KSAVPlayer M2: the binary builds a DynamicInfo lazily (metadata/bytesRead/bitrate blocks).
    // The lazy triple is vtable slots 61–63; the getter @0x1019a1a3c is 0x4d4 bytes (vs. the 16-instruction generated
    // getters around it), i.e. it holds the whole lazy initialiser — that body is the M2 target.
    // ⚠️ s97 — THE DECLARED TYPE IS WRONG HERE, and the fix is NOT a one-line edit. All three of
    // Forward's accessors mangle the type as a CLASS with no `Sg`, i.e. NON-optional:
    //   getter @0x1019a1a3c  $s8KSPlayer10KSAVPlayerC11dynamicInfoAA07DynamicD0Cvg
    //   setter @0x1019a1f10  …Cvs        modify @0x1019a1f28  …CvM
    // all demangling to `dynamicInfo… : KSPlayer.DynamicInfo`. The lazy backing field carries
    // exactly ONE `Sg` (`$__lazy_storage_$_dynamicInfo … tail=b'Sg'`) — that `Sg` is the lazy
    // wrapper itself; a declared `DynamicInfo?` would put a SECOND one there. So the binary says
    // `DynamicInfo`, this file says `DynamicInfo?`.
    // NOT CHANGED HERE, and the blocker is not effort: `MediaPlayerProtocol` requires
    // `var dynamicInfo: DynamicInfo? { get }` (MediaPlayerProtocol.swift:191), and a non-optional
    // property cannot satisfy an optional property requirement — flipping this line alone does not
    // compile. The migration is protocol requirement + KSAVPlayer + KSMEPlayer:360 + 22 call sites
    // under Sources/ that use `?.`/`if let`. The protocol requirement's own optionality has NOT
    // been read from the binary yet (KSMEPlayer's vtable carries no dynamicInfo accessor to read it
    // off), and writing a type we have not read is the one thing this project never does.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.KSAVPlayer.dynamicInfo:0x1019a1a3c result=type-divergence-pinned]
    public lazy var dynamicInfo: DynamicInfo? = nil

    // Declared HERE, between `dynamicInfo` and `bufferingProgress` — Forward's vtable puts this lone getter at slot 64,
    // after the dynamicInfo triple (61–63) and before the bufferingProgress triple (65–67, getter live / setter+_modify
    // dropped). Body (slot 64 @0x1019a1fa4, 10 instructions): load `playerView` from the fixed instance offset +0x38,
    // load the KSAVPlayerView `player` ivar, then `objc_msgSend(-[AVPlayer playbackCoordinator])` via the stub
    // @0x103466300 — so the receiver chain really is `playerView.player`, NOT the `player` extension property, and the
    // property is get-only (no setter/_modify slot follows).
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        playerView.player.playbackCoordinator
    }

    public private(set) var bufferingProgress: UInt8 = 0 {
        didSet {
            delegate?.changeBuffering(player: self, progress: bufferingProgress)
        }
    }

    public var playbackRate: Float = 1 {
        didSet {
            if playbackState == .playing {
                player.rate = playbackRate
            }
        }
    }

    public var playbackVolume: Float = 1.0 {
        didSet {
            if player.volume != playbackVolume {
                player.volume = playbackVolume
            }
        }
    }

    public private(set) var loadState: MediaLoadState = .idle {
        didSet {
            if loadState != oldValue {
                playOrPause()
                if loadState == .loading || loadState == .idle {
                    bufferingProgress = 0
                }
            }
        }
    }

    public private(set) var playbackState: MediaPlaybackState = .idle {
        didSet {
            if playbackState != oldValue {
                playOrPause()
                if playbackState == .finished {
                    delegate?.finish(player: self, error: nil)
                }
            }
        }
    }

    public private(set) var isReadyToPlay: Bool = false {
        didSet {
            if isReadyToPlay != oldValue {
                if isReadyToPlay {
                    options.readyTime = CACurrentMediaTime()
                    delegate?.readyToPlay(player: self)
                }
            }
        }
    }

    #if os(xrOS)
    public var allowsExternalPlayback = false
    public var usesExternalPlaybackWhileExternalScreenIsActive = false
    public let isExternalPlaybackActive = false
    #else
    public var allowsExternalPlayback: Bool {
        get {
            player.allowsExternalPlayback
        }
        set {
            player.allowsExternalPlayback = newValue
        }
    }

    #if os(macOS)
    public var usesExternalPlaybackWhileExternalScreenIsActive = false
    #else
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool {
        get {
            player.usesExternalPlaybackWhileExternalScreenIsActive
        }
        set {
            player.usesExternalPlaybackWhileExternalScreenIsActive = newValue
        }
    }
    #endif

    public var isExternalPlaybackActive: Bool {
        player.isExternalPlaybackActive
    }
    #endif

    public required init(url: URL, options: KSOptions) {
        KSOptions.setAudioSession()
        io = .left(url) // ⚑ M2: recon built AVURLAsset(url:options:avOptions)→urlAsset; binary stores io:Either<URL,AVAsset>
        self.options = options
        // ⚑ UNRESOLVED → KSAVPlayer M2: currentItem observation (was `itemObservation` KVO → observer(playerItem:)) via observerCancellables
    }

    // ── s106: KSAVPlayer members read from their own bodies ────────────────────────
    // These are the class's OWN members, not MediaPlayerProtocol requirements (none of
    // `ioContext`, `startRecord`, `stopRecord` or `nominalFrameRate(track:)` appears in that
    // protocol), so they are declared in the class body where they take a vtable slot rather
    // than in an extension where they would take none.

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.ioContext.getter:0x10002d9d4 result=mov-x0-0/ret]
    /// The whole body is `mov x0, #0x0` / `ret` — it returns nil unconditionally.
    /// The address is the image's 605-symbol ICF fold, so it carries nothing unique to this
    /// property; the two instructions are still genuinely this getter's code. The
    /// MetalRender.swift:26 note that also cites 0x10002d9d4 is another symbol at the same
    /// folded address, NOT a second name for this one.
    /// ⚑[tool=export_trie_oracle ref=0x10002d9d4 result=ICF-FOLD-605-symbols]
    public var ioContext: AbstractAVIOContext? {
        nil
    }

    /// cachedTimeRanges.getter @0x1019a1244, 76 instr, vtable slot 45 — so it belongs in the class
    /// body, not an extension. `public` is proven by the property descriptor
    /// $s8KSPlayer10KSAVPlayerC16cachedTimeRangesSayAA06CachedD5RangeVGvpMV @0x103566da0; there is
    /// no `…vs` and no `…vM`, so it is get-only.
    ///
    /// ⚑ Distinct from `PreLoadProtocol.cachedTimeRanges(duration:)` despite the shared name —
    /// different type, different arity. This getter CALLS that method.
    ///
    /// Every step is read:
    ///  · a vtable call at metadata `+0x458`; KSAVPlayer's VTableOffset is 38 words (0x130), so the
    ///    slot is (0x458-0x130)/8 = 101, whose Impl 0x10002d9d4 is `ioContext`'s own getter — the
    ///    same address this file already cites two declarations above. `cbz` on the result is the
    ///    optional test.
    ///  · `swift_dynamicCast` with `w4 = 6` (CONDITIONAL) from `AbstractAVIOContext` (metadata
    ///    accessor 0x1019e4db4) to the existential whose mangle at 0x103566c50 ends `_p`; `tbz` on
    ///    failure falls to the empty return.
    ///  · `duration` (offset global 0x104c63070, named) under a read access, then
    ///    `fcmp d8, #0.0` / `b.le` — the `> 0` test, ordered AFTER the cast.
    ///  · success calls witness slot **+0x40** with `d0 = duration`. PreLoadProtocol has 9
    ///    requirements, so +0x40 is requirement index 7 — which PreLoadProtocol.swift numbers
    ///    explicitly as `cachedTimeRanges(duration:)`, a Method, matching the descriptor's kind.
    ///  · both failure paths return `__swiftEmptyArrayStorage` (__got 0x104112d00), i.e. `[]`.
    /// ⚑[tool=conformance_walker ref=PreLoadProtocol:0x1039ede48 result=9-requirements]
    /// ⚑[tool=bind_oracle ref=_swiftEmptyArrayStorage:0x104112d00 result=libswiftCore]
    public var cachedTimeRanges: [CachedTimeRange] {
        guard let ioContext = ioContext as? PreLoadProtocol, duration > 0 else {
            return []
        }
        return ioContext.cachedTimeRanges(duration: duration)
    }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.startRecord(url:):0x10000e52c result=single-ret]
    /// The body IS 0x10000e52c, whose only instruction is `ret`. Empty, not unimplemented —
    /// this is the empty-body fold, distinct from the deleted-method stub at 0x10198eb18 which
    /// would have carried `bl swift_deletedMethodError` / `brk`.
    public func startRecord(url _: URL) {}

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.stopRecord():0x10000e52c result=single-ret]
    /// Same empty-body fold as `startRecord` above.
    public func stopRecord() {}

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.nominalFrameRate(track:):0x1019a5128 result=12-instr]
    /// `bl swift_getObjectType` on the incoming track to get its Self metadata, then
    /// `ldr x8,[x19,#0x20]` — word 4 of the track's MediaPlayerTrack witness table, i.e.
    /// requirement 3 — and calls it with self in x20, metadata in x0 and the table in x1.
    /// Requirement 3 is DECODED, not counted: FFmpegAssetTrack's table at 0x1041d78b8 gives
    /// req3 = 0x101a1f5bc, which the trie names `FFmpegAssetTrack.nominalFrameRate.getter`.
    /// ⚑[tool=bind_oracle ref=__got:0x104112f08 result=_swift_getObjectType]
    /// ⚑[tool=decode_witness_table ref=FFmpegAssetTrack:MediaPlayerTrack@0x1041d78b8 result=req3-nominalFrameRate]
    public func nominalFrameRate(track: some MediaPlayerTrack) -> Float {
        track.nominalFrameRate
    }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.thumbnailImage(atTime:handler:):0x1019a9a1c result=32-instr]
    /// ⚠️ The two paths are ASYMMETRIC, and that is read, not inferred. `ldrb` of the
    /// `isReadyToPlay` ivar (offset global 0x104c630d0) then `cmp w8,#0x1`:
    ///   · NOT ready — `mov x0,#0` and `blr` the handler, i.e. `handler(nil)`;
    ///   · ready — builds a CMTime from the incoming seconds with timescale 600
    ///     (`mov w0,#0x258` into CMTime.init(seconds:preferredTimescale:)) and then branches
    ///     STRAIGHT to the epilogue. The handler is never invoked on that path and the CMTime is
    ///     discarded.
    /// The construction survives dead-code elimination only because that initialiser can trap, so
    /// it is genuine evidence the conversion is in the source — but whatever consumed it (an
    /// AVAssetImageGenerator path, by analogy with the AVAsset extension at the bottom of this
    /// file) is NOT in this binary. Transcribed as read rather than completed by analogy.
    /// ⚑[tool=bind_oracle ref=__got:0x1041132c8 result=CMTime.init(seconds:preferredTimescale:)]
    public func thumbnailImage(atTime: TimeInterval, handler: @escaping @Sendable (CGImage?) -> Void) {
        guard isReadyToPlay else {
            handler(nil)
            return
        }
        _ = CMTime(seconds: atTime, preferredTimescale: 600)
    }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.checkShouldResume():0x1019aaa10 result=38-instr]
    /// Reads `options` (offset global 0x104c63098) then the Bool at `options + 0x46`. If that bit
    /// is set the result is 1 immediately and the second read is skipped — that short-circuit IS
    /// the `||`. Otherwise it reads `playbackState` (0x104c630b8) and compares against 1. The
    /// result is stored through 0x104c630d8.
    ///
    /// Three names, none guessed:
    ///   · `options + 0x46` = `enterForgeResumePlay`. KSOptions has metadata_init=1 so its offset
    ///     vector is unreadable, and this is a constant-immediate touch so no global names it.
    ///     Recovered instead from KSOptions' own trie-named accessors, 21 of which open
    ///     `add x0, x20, #IMM`; the resulting map is strictly increasing in field-record order.
    ///   · `playbackState == 1` is the CASE TAG. MediaPlaybackState is
    ///     idle/playing/paused/seeking/finished/stopped, so tag 1 is `.playing`.
    ///   · the store target 0x104c630d8 is `shouldResumePlayback`, by elimination: it is the only
    ///     KSAVPlayer offset global with no trie symbol, and the other Bool field
    ///     (`isReadyToPlay`) is already claimed by 0x104c630d0.
    /// ⚑[tool=recover_field_offsets ref=KSOptions:+0x46 result=enterForgeResumePlay]
    /// ⚑[tool=export_trie_oracle ref=KSAVPlayer:0x104c630d8 result=unnamed-only-Bool-left]
    public func checkShouldResume() {
        shouldResumePlayback = options.enterForgeResumePlay || playbackState == .playing
    }
}

extension KSAVPlayer {
    public var player: AVQueuePlayer { playerView.player }
    public var playerLayer: AVPlayerLayer { playerView.playerLayer }
    @objc private func moviePlayDidEnd(notification _: Notification) {
        if !options.isLoopPlay {
            playbackState = .finished
        }
    }

    @objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
        var playError: Error?
        if let userInfo = notification.userInfo {
            if let error = userInfo["error"] as? Error {
                playError = error
            } else if let error = userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
                playError = error
            } else if let errorCode = (userInfo["error"] as? NSNumber)?.intValue {
                playError = NSError(domain: "AVMoviePlayer", code: errorCode, userInfo: nil)
            }
        }
        delegate?.finish(player: self, error: playError)
    }

    private func updateStatus(item: AVPlayerItem) {
        // ⚑ UNRESOLVED → KSAVPlayer M2: readyToPlay/failed handling rebuilt on the reworked fields
        //   (mediaPlayerTracks:[any MediaPlayerTrack] / subtitleTracks, naturalSize, duration, fileSize, error).
    }

    private func updatePlayableDuration(item: AVPlayerItem) {
        // ⚑ UNRESOLVED → KSAVPlayer M2: playableTime / bufferingProgress(UInt8) / loadState buffering computation.
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.KSAVPlayer.updatePlaybackBuffer():0x1019a5054 result=53-instr]
    /// `guard let` is the `cbz` after `objc_retainAutoreleasedReturnValue`; the receiver chain is
    /// `playerView.player` — `+0x38` is `playerView` (the fixed instance offset this file already
    /// records at :188) and 0x1044e46b0 is `direct field offset for KSAVPlayerView.player`.
    /// ⚑[tool=decode_objc_selector ref=0x10440af28 result='currentItem']
    /// ⚑[tool=decode_objc_selector ref=0x10440be68 result='isPlaybackLikelyToKeepUp']
    /// ⚑[tool=decode_objc_selector ref=0x10440be60 result='isPlaybackBufferFull']
    /// `tbnz` on the first and `cbnz` on the second both jump to `mov w21, #2`; the fall-through
    /// stores 1. `MediaLoadState` is `idle`/`loading`/`playable`, so 2 is `.playable` and 1 is
    /// `.loading`. The trailing vtable call is `loadState`'s own `didSet`, not a statement here.
    ///
    /// ⚑ `isPlaybackBufferEmpty` (0x10440be58) IS called, into x21, and its result provably does
    ///   NOT reach the outcome: the two `csel`s that consume it select between `#1` and `#1` and
    ///   between `sp+8` and `sp+8` — identical operands on both arms. So the branch value is
    ///   `.loading` either way. Whatever source expression consumed that flag was collapsed by the
    ///   optimizer and is NOT recoverable from this body; declaring a use for it would be
    ///   invention, and dropping the call is the only spelling the binary supports.
    ///
    /// ⚑ NOT `private`, unlike the siblings around it: the trie carries
    ///   `…20updatePlaybackBufferyyFTq`, a method descriptor, i.e. a real vtable slot — and a
    ///   `private` method takes none. The mangled name also carries no `33_…LL` discriminator.
    func updatePlaybackBuffer() {
        guard let item = playerView.player.currentItem else {
            return
        }
        loadState = item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull ? .playable : .loading
    }

    private func playOrPause() {
        if playbackState == .playing {
            if loadState == .playable {
                player.play()
                player.rate = playbackRate
            }
        } else {
            player.pause()
        }
        delegate?.changeLoadState(player: self)
    }

    public func replaceCurrentItem(playerItem: AVPlayerItem?) {   // public (was private, P34): ProAVPlayer (separate module) slot15 item-swap closure installs its ProPlayerItem via this cross-module call (FUN_1019a563c)  ⚑[tool=resolve_fun_pins ref=FUN_1019a563c:0x1019a563c result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.replaceCurrentItem(playerItem: __C.AVPlayerItem?) -> ()
        player.currentItem?.cancelPendingSeeks()
        if options.isLoopPlay {
            playerLooper?.disableLooping()
            guard let playerItem else {
                playerLooper = nil
                return
            }
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            // ⚑ UNRESOLVED → KSAVPlayer M2: loopCount/loopStatus observation (was 2 KVO NSKeyValueObservations → observerLoopCancellables)
        } else {
            player.replaceCurrentItem(with: playerItem)
        }
    }

    // reset() @0x1019a5410, 139 instr, vtable slot 102. Exactly one symbol at the address (no ICF
    // fold). `public` rests on the method descriptor $s8KSPlayer10KSAVPlayerC5resetyyFTq existing
    // @0x1039ec4b8 — a cross-module vtable entry. It is NOT `open`: no ProAVPlayer override of
    // this selector is in the trie. ⚑ access is the weakest claim here; the ACCESS bucket, not
    // this unit, is where it gets settled.
    //
    // Ten steps, in instruction order 0x1019a542c -> 0x1019a5618, each re-read from the binary:
    //  1 self.options (offset global 0x104c63098) then a VIRTUAL `ldr x8,[x20]; ldr x21,[x8,#0x310]`
    //    — KSOptions VTableOffset is 94 words (0x2f0), so (0x310-0x2f0)/8 = slot 4 = KSOptions.reset().
    //  2 isReadyToPlay (0x104c630d0) `strb wzr` = false.
    //  3 playbackState (0x104c630b8) read-then-write `mov w8,#0x5`. MediaPlaybackState's own
    //    descriptor 0x1039ed96c lists 6 cases, index 5 = .stopped. The old value then goes to the
    //    compiler-emitted didSet observer at 0x1019a24a8, which has no source spelling.
    //  4 loadState (0x104c630c8) read-then-write `strb wzr`. Descriptor 0x1039ed988, 3 cases,
    //    index 0 = .idle. Followed by the didSet's virtual call to update(loadState:oldValue:).
    //  5 duration (0x104c63070) `str xzr` = 0.
    //  6 subtitleTracks (0x104c63058) = the __swiftEmptyArrayStorage singleton, i.e. [].
    //  7 the same singleton into the UNEXPORTED global 0x1044e46f8. That is mediaPlayerTracks by
    //    a CLOSED elimination, not by position: the field records give KSAVPlayer 28 fields, of
    //    which exactly three are Arrays — mediaPlayerTracks (6) and subtitleTracks (7) share one
    //    element type, chapters (16) has another — and subtitleTracks (0x104c63058) and chapters
    //    (0x104c63088) are both independently named. mediaPlayerTracks is `internal`, which is
    //    precisely why it emits no vpWvd global to be named by.
    //    ⚑[tool=fieldrec ref=KSAVPlayer.mediaPlayerTracks:0x1044e46f8 result=elimination-over-28-field-records]
    //  8 playerView (the fixed instance offset +0x38) -> KSAVPlayerView.player (offset global
    //    0x1044e46b0) -> selectors 'currentItem', 'asset', 'cancelLoading', with the `cbz` after
    //    currentItem supplying the `?`.
    //  9 replaceCurrentItem with x0 = 0 — the nil literal, calling this file's own member @0x1019a563c.
    // 10 delegate (0x104c63068) is loaded with swift_weakLoadStrong and `cbz`-guarded, which is the
    //    `?`; field record 12 carries the `Xw` tail, so the weak-ness is reflection-visible. The
    //    call is witness slot +0x40 — which MediaPlayerProtocol.swift already pins as req7
    //    playerDidClear(player:) — and self is passed as the (object, metadata, witness) triple
    //    0x1041d3f78, matching that requirement's `some MediaPlayerProtocol` parameter.
    // ⚑[tool=bind_oracle ref=_swiftEmptyArrayStorage:0x104112d00 result=libswiftCore]
    // ⚑[tool=export_trie_oracle ref=KSAVPlayerView.player:0x1044e46b0 result=player]
    public func reset() {
        options.reset()
        isReadyToPlay = false
        playbackState = .stopped
        loadState = .idle
        duration = 0
        subtitleTracks = []
        mediaPlayerTracks = []
        playerView.player.currentItem?.asset.cancelLoading()
        replaceCurrentItem(playerItem: nil)
        delegate?.playerDidClear(player: self)
    }

    // process(error:) @0x1019a5158, 81 instr, vtable slot 100. No ICF fold. `public` on the same
    // basis as reset(): the method descriptor $s8KSPlayer10KSAVPlayerC7process5errorys5Error_p_tFTq
    // exists @0x1039ec4a8. ⚑ access is the weakest claim here, as it is for reset().
    //
    // The body itself does exactly ONE thing and takes no branch — control flow is fully linear
    // with a single `ret` — so every effect below is inside the closure:
    //  · swift_allocObject(0x1041d3e70, 0x18, 7) then swift_weakInit(box+0x10, self) — `[weak self]`.
    //  · MainActor.shared ($sScM6sharedScMvgZ) plus the MainActor:Actor witness table built from
    //    conformance descriptor 0x104113870 — the `@MainActor` isolation, not a hop written by hand.
    //  · swift_errorRetain(error) — the error is captured STRONGLY, unlike self.
    //  · swift_allocObject(0x1041d3f10, 0x30, 7) for the 48-byte context, filled
    //    `stp x20,x23,[x0,#0x10]` / `stp x22,x19,[x0,#0x20]` = MainActor.shared, its witness table,
    //    the weak-self box, the error.
    //  · the Task is created through 0x101a03fd4 with the async function pointer 0x103566c80, and
    //    the returned handle is immediately swift_release'd — a bare `Task { }` statement, never a
    //    stored handle.
    //
    // The operation resumes at 0x1019a529c (the @MainActor hop, ending in swift_task_switch) and
    // continues at 0x1019a532c, where the two `?`s are both explicit:
    //  · swift_weakLoadStrong on the box then `cbz` — `guard let self else { return }`.
    //  · swift_unknownObjectWeakLoadStrong on delegate (offset global 0x104c63068) then `cbz`.
    //  · the call is witness slot +0x38 with x1 = the captured error. This file's own requirement
    //    table maps +0x38 to req6 `finish(player:error:)`, and self is handed over as the
    //    (object, metadata, witness) triple 0x1041d3f78 — the `some MediaPlayerProtocol` form.
    // Both beginAccess sites pass flags 0, so both are reads and no endAccess is emitted.
    // ⚑[tool=bind_oracle ref=MainActor.shared:0x104113860 result=libswift_Concurrency]
    // ⚑[tool=bind_oracle ref=_swift_errorRetain:0x104112e50 result=libswiftCore]
    // ⚑[tool=bind_oracle ref=_swift_unknownObjectWeakLoadStrong:0x1041130e8 result=libswiftCore]
    public func process(error: Error) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            delegate?.finish(player: self, error: error)
        }
    }

    /// @0x1019ab4dc, 62 instructions. Trie: `KSAVPlayer.configPIP() -> ()`; no `Tq`, so it is not
    /// an overridable requirement.
    ///
    ///   · the `cmn x8,#1` on the token at 0x1044e5178 is the ordinary `swift_once` guard for a
    ///     lazily-initialised static, and the storage it returns, 0x104c632c0, demangles to
    ///     `static KSOptions.pictureInPictureType : KSPictureInPictureProtocol.Type`. It is read
    ///     under `swift_beginAccess` with flags (0, 0) and taken as the two-word
    ///     (metatype, witness-table) pair.
    ///   · `ldr x0,[x19,#0x38]` is `playerView` at the fixed instance offset this file already
    ///     documents for slot 64; the selector sent to it, selref 0x10440bf70, is `layer`, and the
    ///     result goes through `swift_dynamicCastObjCClassUnconditional` against the `AVPlayerLayer`
    ///     classref. That pair is exactly what `KSAVPlayerView.playerLayer` — `layer as! AVPlayerLayer`
    ///     — inlines to, so the receiver is spelled through this class's own `playerLayer`.
    ///   · `ldr x8,[x22,#0x18]` is witness 2 of KSPictureInPictureProtocol. This file's requirement
    ///     table maps req2 to 0x1019c779c, whose stub 0x103463520 carries selref 0x10440bb10 =
    ///     `initWithPlayerLayer:`.
    ///   · the `cmp x0,#0` / `csel x21, xzr, x22, eq` that follows rebuilds a NIL existential when
    ///     the instance came back null — i.e. the requirement is FAILABLE. That is what the
    ///     requirement's declaration was missing: KSPictureInPictureController.swift previously
    ///     recorded this init as undeclarable, predicting a `required`-initializer error, but the
    ///     compiler actually rejects it for failability ("non-failable initializer requirement
    ///     cannot be satisfied by a failable initializer"). Declared as `init?(playerLayer:)` it
    ///     builds 4/4 — and the binary's own null test is independent evidence for the `?`.
    ///   · the store is a `swift_beginAccess` with flags (1, 0) — an untracked MODIFY — on
    ///     offset global 0x104c63060, `pipController`, followed by `stp` of the new pair and a
    ///     release of the old.
    /// ⚑[tool=decode_objc_selector ref=0x10440bf70 result=layer]
    /// ⚑[tool=bind_oracle ref=__got:0x104112e20 result=_swift_dynamicCastObjCClassUnconditional]
    /// ⚑[tool=export_trie_oracle ref=KSOptions.pictureInPictureType:0x104c632c0 result=KSPictureInPictureProtocol.Type]
    public func configPIP() {
        pipController = KSOptions.pictureInPictureType.init(playerLayer: playerLayer)
    }

    private func observer(playerItem: AVPlayerItem?) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        // ⚑ UNRESOLVED → KSAVPlayer M2: the 5 KVO NSKeyValueObservations (status / loadedTimeRanges / bufferEmpty /
        //   likelyToKeepUp / bufferFull) → observerPlayerItemCancellables Combine sinks (updateStatus/updatePlayableDuration/loadState).
        guard let playerItem else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(moviePlayDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
    }
}

extension KSAVPlayer: @preconcurrency MediaPlayerProtocol {
    public var subtitleDataSource: (any SubtitleDataSource)? { nil }
    public var isPlaying: Bool { player.rate > 0 ? true : playbackState == .playing }
    public var view: UIView { playerView }
    public var currentPlaybackTime: TimeInterval {
        get {
            if let shouldSeekTo, shouldSeekTo > 0 {
                return shouldSeekTo
            } else {
                // 防止卡主
                return isReadyToPlay ? player.currentTime().seconds : 0
            }
        }
        set {
            seek(time: newValue) { _ in
            }
        }
    }

    public var numberOfBytesTransferred: Int64 {
        guard let playerItem = player.currentItem, let accesslog = playerItem.accessLog(), let event = accesslog.events.first else {
            return 0
        }
        return event.numberOfBytesTransferred
    }

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        // ⚑ UNRESOLVED → KSAVPlayer M2: thumbnail from the `io` asset (was urlAsset.thumbnailImage(currentTime:))
        nil
    }

    // The completion carries @MainActor and @Sendable in the binary symbol; the source declared a
    // bare escaping closure.
    public func seek(time: TimeInterval, completion: @escaping (@MainActor @Sendable (Bool) -> Void)) {
        let time = max(time, 0)
        // AN ENTIRE KSLog STATEMENT WAS MISSING. The binary opens with this gated log, and the
        // shouldSeekTo-vs-currentTime coalesce exists only to build the message — which is also why
        // it has to run BEFORE the `shouldSeekTo = time` store below, or it would read the new value
        // and the "from" half would always equal the "to" half.
        KSLog("\(self) seek from \(shouldSeekTo ?? player.currentTime().seconds) to \(time)")
        shouldSeekTo = time
        playbackState = .seeking
        runOnMainThread { [weak self] in
            self?.bufferingProgress = 0
        }
        let tolerance: CMTime = options.isAccurateSeek ? .zero : .positiveInfinity
        player.seek(to: CMTime(seconds: time), toleranceBefore: tolerance, toleranceAfter: tolerance) {
            [weak self] finished in
            guard let self else { return }
            self.shouldSeekTo = 0
            completion(finished)
        }
    }

    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)")
        options.prepareTime = CACurrentMediaTime()
        // ⚑ UNRESOLVED → KSAVPlayer M2: build AVPlayerItem from `io` (was AVPlayerItem(asset: urlAsset)) on the main thread,
        //   install via replaceCurrentItem, set openTime / actionAtItemEnd / volume / bufferingProgress.
    }

    public func play() {
        KSLog("play \(self)")
        playbackState = .playing
    }

    public func pause() {
        KSLog("pause \(self)")
        playbackState = .paused
    }

    public func stop() {
        KSLog("shutdown \(self)")
        isReadyToPlay = false
        playbackState = .stopped
        loadState = .idle
        // ⚑ M2: cancelLoading on the `io` asset (was urlAsset.cancelLoading())
        replaceCurrentItem(playerItem: nil)
    }

    public func replace(url: URL, options: KSOptions) {
        KSLog("replaceUrl \(self)")
        stop()
        io = .left(url) // ⚑ M2: recon built AVURLAsset(url:options:avOptions)→urlAsset
        self.options = options
    }

    public var contentMode: UIViewContentMode {
        get {
            playerView.contentMode
        }
        set {
            playerView.contentMode = newValue
        }
    }

    public func enterBackground() {
        playerView.playerLayer.player = nil
    }

    public func enterForeground() {
        playerView.playerLayer.player = playerView.player
    }

    public var seekable: Bool {
        !(player.currentItem?.seekableTimeRanges.isEmpty ?? true)
    }

    public var isMuted: Bool {
        get {
            player.isMuted
        }
        set {
            player.isMuted = newValue
        }
    }

    public func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack] {
        player.currentItem?.tracks.filter { $0.assetTrack?.mediaType == mediaType }.map { AVMediaPlayerTrack(track: $0) } ?? []
    }

    public func select(track: some MediaPlayerTrack) {
        player.currentItem?.tracks.filter { $0.assetTrack?.mediaType == track.mediaType }.forEach { $0.isEnabled = false }
        track.isEnabled = true
    }
}

extension AVFoundation.AVMediaType {
    var mediaCharacteristic: AVMediaCharacteristic {
        switch self {
        case .video:
            return .visual
        case .audio:
            return .audible
        case .subtitle:
            return .legible
        default:
            return .easyToRead
        }
    }
}

extension AVAssetTrack {
    func toMediaPlayerTrack() {}
}

class AVMediaPlayerTrack: @preconcurrency MediaPlayerTrack {
    // Stored properties are in the binary's own declaration order, read from
    // `__swift5_fieldmd` via `scripts/dump_binary_field_types.py AVMediaPlayerTrack`. Field
    // metadata records declaration order, so matching it is faithful by construction — this
    // is not cosmetic reshuffling, and `l2_field_gate` BLOCKs on `order differs` precisely
    // because a wrong order is a wrong layout.
    //
    // ⚑[tool=dump_binary_field_types ref=AVMediaPlayerTrack.reorderSize:idx7 result=pinned]
    //   The binary has 16 fields; this source has 15. `reorderSize` is field-record index 7
    //   (0-based), between `trackID` (6) and `bitDepth` (8). Both its TYPE and its POSITION are
    //   decidable and are recorded here; only its VALUE is not, which is what pins it:
    //     · type — the field record is a symref to `__got 0x104112920`, which binds
    //       `_$ss5Int32VMn`, the Swift.Int32 nominal type descriptor. Same slot as `trackID`
    //       and `bitDepth`, both of which this source already spells `Int32`.
    //       ⚑[tool=bind_oracle ref=__got:0x104112920 result=_$ss5Int32VMn]
    //     · value — UNREADABLE, for two independent reasons. (1) The class exports ZERO symbols
    //       in the trie, so there is no vpfi to read a declaration default from; absence here is
    //       ignorance, NOT the usual "no vpfi ⇒ no default" evidence, which only holds for a
    //       class that exports something. (2) The vtable's Init slot 3 carries a NULL Impl in
    //       the descriptor, i.e. the initializer is dead-stripped — there is no init body left
    //       to read a store from.
    //       ⚑[tool=export_trie_oracle ref=AVMediaPlayerTrack:trie result=0-symbols]
    //       ⚑[tool=vtable_walk ref=AVMediaPlayerTrack:slot3-Init result=null-Impl-dead-stripped]
    //   So no faithful spelling of the initializer exists anywhere in the image. Declaring it
    //   would mean inventing a value; leaving it out keeps the source honest at the cost of one
    //   standing `field in binary, absent in source` FLAG, which is carried as a DEFERRAL.
    //   (s104's note said the reason was "nothing in this class reads or writes it". That was
    //   the weaker claim — the decisive one is the dead-stripped init above.)
    private let track: AVPlayerItemTrack
    let mediaType: AVFoundation.AVMediaType
    let name: String
    let description: String
    var nominalFrameRate: Float
    let bitRate: Int64
    let trackID: Int32
    // reorderSize: Int32 — binary index 8, undeclared (see the pin above)
    let bitDepth: Int32
    let rotation: UInt16 = 0
    let fieldOrder: FFmpegFieldOrder = .unknown
    let isImageSubtitle = false
    var isPlayable: Bool
    let languageCode: String?
    var dovi: DOVIDecoderConfigurationRecord?
    let formatDescription: CMFormatDescription?
    @MainActor
    var isEnabled: Bool {
        get {
            track.isEnabled
        }
        set {
            track.isEnabled = newValue
        }
    }

    init(track: AVPlayerItemTrack) {
        self.track = track
        trackID = track.assetTrack?.trackID ?? 0
        mediaType = track.assetTrack?.mediaType ?? .video
        name = track.assetTrack?.languageCode ?? ""
        languageCode = track.assetTrack?.languageCode
        nominalFrameRate = track.assetTrack?.nominalFrameRate ?? 24.0
        bitRate = Int64(track.assetTrack?.estimatedDataRate ?? 0)
        #if os(xrOS)
        isPlayable = false
        #else
        isPlayable = track.assetTrack?.isPlayable ?? false
        #endif
        // swiftlint:disable force_cast
        if let first = track.assetTrack?.formatDescriptions.first {
            formatDescription = first as! CMFormatDescription
        } else {
            formatDescription = nil
        }
        bitDepth = formatDescription?.bitDepth ?? 0
        // swiftlint:enable force_cast
        description = (formatDescription?.mediaSubType ?? .boxed).rawValue.string
        #if os(xrOS)
        Task {
            isPlayable = await (try? track.assetTrack?.load(.isPlayable)) ?? false
        }
        #endif
    }

    func load() {}
}

public extension AVAsset {
    func createImageGenerator() -> AVAssetImageGenerator {
        let imageGenerator = AVAssetImageGenerator(asset: self)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        return imageGenerator
    }

    func thumbnailImage(currentTime: CMTime, handler: @escaping (CGImage?) -> Void) {
        let imageGenerator = createImageGenerator()
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: currentTime)]) { _, cgImage, _, _, _ in
            if let cgImage {
                handler(cgImage)
            } else {
                handler(nil)
            }
        }
    }
}

// §1/§7.2 — KSAVPlayer conforms SubtitleDataSource (empty marker) + ConstantSubtitleDataSource
// (method-bearing, CORRECTED s14). The refinement-aware superclass_conformance_gate resolves both
// from the binary's conformance records (the original task_e5456ff6 target).
extension KSAVPlayer: SubtitleDataSource {}

// @preconcurrency conformance (KSAVPlayer already uses it for MediaPlayerProtocol): lets the @MainActor witness read the
// main-actor `subtitleTracks` directly (matching the binary) and satisfy the nonisolated protocol req — it relaxes the
// non-Sendable [any SubtitleInfo] boundary that strict-concurrency (xcodebuild) rejects for a plain @MainActor witness.
extension KSAVPlayer: @preconcurrency ConstantSubtitleDataSource {
    // Task 6 (session 20). Witness 0x1019aba18 (async trampoline) → FUN_1019ab818 (task_switch hop) → FUN_1019ab830:  ⚑[tool=resolve_fun_pins ref=FUN_1019ab818:0x1019ab818 result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.infos() async throws -> [KSPlayer.SubtitleInfo]
    // reads the stored `subtitleTracks: [any MediaPlayerTrack]` (_swift_beginAccess) and collects the SubtitleInfo
    // conformers (_swift_getObjectType + _swift_conformsToProtocol per element). Return element PROVEN `[any SubtitleInfo]`,
    // NOT rippled to [URLSubtitleInfo] (P55/P60, opposite of the Search/URL siblings): each element is stored as a 2-word
    // class-existential {object@+0x20, witnessTable@+0x28} at stride 0x10 (FUN_1019ab830) — boxing PRESENT ⇒ existential.
    // ⚑ s106 RENAME searchSubtitle() -> infos(). The §4 address enumeration found this body was
    //   already reconstructed under the wrong name: the pin above resolves 0x1019ab818 and the
    //   trie demangles it `KSPlayer.KSAVPlayer.infos() async throws -> [KSPlayer.SubtitleInfo]`.
    //   Parameters, async/throws and return type all match, so only the name was wrong. The
    //   requirement in ConstantSubtitleDataSource is renamed with it.
    public func infos() async throws -> [any SubtitleInfo] {
        subtitleTracks.compactMap { $0 as? (any SubtitleInfo) }
    }
}
