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
#sourceLocation(file: "KSPlayer/KSAVPlayer.swift", line: 24)
        fatalError("init(coder:) has not been implemented")
#sourceLocation()
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
    public var pipController: (any KSPictureInPictureProtocol)?
    public weak var delegate: MediaPlayerDelegate?
    public private(set) var duration: TimeInterval = 0
    // Forward 1.3.17: `fileSize` is `Int64` (known-answer control 0x10536e600 == Int64 via Foundation.Progress / Alamofire
    //   byte-count fields). MediaPlayback.fileSize migrated Double→Int64 (session 16b); l2 UNCHECKED (GOT-external field-record).
    public var fileSize: Int64 = 0
    public private(set) var playableTime: TimeInterval = 0
    /// cachedTimeRanges.getter @0x1019a1244, Forward idx45 / absolute metadata slot83.
    /// It sits between playableTime and chapters. The ioContext virtual call at metadata +0x458
    /// is slot139 / index101. Exact access spelling remains unresolved; current public access is retained.
    /// The cast, duration check, and witness call are established; this placement
    /// does not claim full-body faithfulness.
    public var cachedTimeRanges: [CachedTimeRange] {
        guard let ioContext = ioContext as? PreLoadProtocol, duration > 0 else {
            return []
        }
        return ioContext.cachedTimeRanges(duration: duration)
    }

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
    nonisolated(unsafe) public var chapters: [Chapter] = []
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
                KSLog(error, line: 123)
                process(error: error)
            }
        }
    }

    // Ref getter 0x1019a1a3c uses two weak captures; only lazy backing storage is optional.
    // Evidence: M05-DynamicInfo-init35-helpers-disasm.json and M05-protocol-reference-contract.json.
    public lazy var dynamicInfo: DynamicInfo = DynamicInfo(displayFPSBlock: { [weak self] in
        self?.player.currentItem?.tracks.first { $0.assetTrack?.mediaType == .video }?.currentVideoFrameRate ?? 0
    }, accessLogEvent: { [weak self] in
        self?.player.currentItem?.accessLog()?.events ?? []
    })

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
            runOnMainThread { [weak self] in
                guard let self else { return }
                self.delegate?.changeBuffering(player: self, progress: self.bufferingProgress)
            }
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
            update(loadState: loadState, oldValue: oldValue)
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

    // ⚑[tool=member_surface ref=KSAVPlayer.init(io:options:):0x1019a2e18 result=designated; init(url:) 0x1019a2c5c / init(asset:) 0x1019a2d34 allocating-only]
    //   init(url:) builds Either tag 0 (`mov w2,#0`), init(asset:) tag 1 (`mov w2,#1`); both dispatch
    //   the allocating init through vtable +0x408, i.e. `self.init(io:options:)`. The designated body is
    //   shared FUN 0x1019b1b30 (called from both 0x1019a2dc0 and 0x1019a2e18).
    //   isolation: none of the three entries calls swift_task_*/ScM; class stays @MainActor as declared.
    public required convenience init(url: URL, options: KSOptions) {
        self.init(io: .left(url), options: options)
    }

    public convenience init(asset: AVAsset, options: KSOptions) {
        self.init(io: .right(asset), options: options)
    }

    public init(io: Either<URL, AVAsset>, options: KSOptions) {
        options.setAudioSession()
        self.io = io // ⚑ M2: recon built AVURLAsset(url:options:avOptions)→urlAsset; binary stores io:Either<URL,AVAsset>
        self.options = options
        // ⚑ UNRESOLVED → KSAVPlayer M2: currentItem observation (was `itemObservation` KVO → observer(playerItem:)) via observerCancellables
    }

    // ── s106: existing tail declarations follow Forward order. `init(io:options:)` and
    // `createPlayerItem()` remain pending separate body reconstruction; this note does not claim
    // complete layout or faithfulness.

    /// @0x1019a3ccc, vtable slot 92 (async). Entry `swift_task_switch(FUN_1019a3d5c, 0, 0)`.
    /// `.left(url)`: AVURLAsset(url:options: options.avOptions) (+0x20) → initWithAsset:.
    /// `.right(asset)`: hops to MainActor (FUN_1019a3f84) for initWithAsset:, then back.
    /// ⚑ ISOLATION: Forward is `nonisolated` (the generic-executor entry, and the .right MainActor hop is
    ///   what the SDK's MainActor `AVPlayerItem(asset:)` forces for a non-sending AVAsset). Spelled
    ///   MainActor here: nonisolated reads of `io`/`options` fail Swift 6 checks, and `options.didSet`
    ///   touches MainActor state, so `nonisolated(unsafe)` on the fields is not an option.
    open func createPlayerItem() async throws -> AVPlayerItem {
        switch io {
        case let .left(url):
            return AVPlayerItem(asset: AVURLAsset(url: url, options: options.avOptions))
        case let .right(asset):
            return AVPlayerItem(asset: asset)
        }
    }

    /// @0x1019a402c, 130 instructions, vtable slot 93 (kind Method). It is NOT an override —
    /// ⚑[tool=override_table ref=KSAVPlayer.readyToPlay:0x1019a402c result=NO-override-table]
    /// — and it carries a vtable slot, which is why it is declared in the CLASS body and not in
    /// the `extension KSAVPlayer` below: an extension member gets no slot.
    ///
    /// Two statements, both read end to end.
    ///   · `ldr x21,[x8,#0x98]` resolves 0x104c63098 = `direct field offset for
    ///     KSPlayer.KSAVPlayer.options`, read under a (0, 0) beginAccess; `ldr x22,[0x104c63468]`
    ///     resolves `direct field offset for KSPlayer.KSOptions.readyTime : Swift.Double`, and its
    ///     beginAccess passes `w2 = 1`, the WRITE flag. Between them sits `bl _CACurrentMediaTime`
    ///     with its result moved to `d8` and stored by `str d8,[x21,x22]`. So the write targets a
    ///     field on the KSOptions instance, not on self.
    ///   · the tail is `runOnMainThread`, inlined. It is `@inline(__always)`, which is why no call
    ///     survives: the body emits the `NSThread.isMainThread` fork directly, then
    ///     `MainActor.assumeIsolated` @0x101a04674 on one arm and `swift_task_create` @0x101a03fd4
    ///     on the other. Both are stdlib concurrency, not members to name.
    ///
    /// ⚑ THE BODY WRITES NO KSAVPlayer STATE. The complete non-stack store census is four
    ///   instructions and not one targets x20 (swiftself); in particular `isReadyToPlay` is NOT
    ///   set here, though it still exists as a field record.
    ///
    /// ⚑ CAPTURE LIST, derived (session-113 A3 requires this recorded explicitly): `[weak self]`.
    ///   The caller allocates a 24-byte box and calls `swift_weakInit` at 0x1019a40fc to store
    ///   self into it — not a retain. The closure body @0x1019a4234 (51 instructions) reads it
    ///   back with `swift_weakLoadStrong` at 0x1019a4268 and `cbz`-returns on nil, which is
    ///   `guard let self else { return }`. `delegate` is then loaded from 0x104c63068 with
    ///   `swift_unknownObjectWeakLoadStrong` and `cbz`-skipped, which is the `?.`; the call passes
    ///   `x1` = KSAVPlayer metadata and `x2` = 0x1041d3f78, the `KSAVPlayer : MediaPlayerProtocol`
    ///   witness table, i.e. self as `some MediaPlayerProtocol`. The dispatched slot is witness
    ///   table + 8 = requirement 0 of MediaPlayerDelegate = `readyToPlay(player:)`.
    ///
    /// ⚑ WHERE THIS CAME FROM, and what is NOT established: the same two statements sit in this
    ///   file inside `isReadyToPlay`'s `didSet`. Whether Forward's `didSet` still holds them or
    ///   now just calls this method CANNOT BE READ — the setter symbol
    ///   `$s8KSPlayer10KSAVPlayerC13isReadyToPlaySbvs` resolves to 0x10198eb18, the
    ///   swift_deletedMethodError fold, so its code is not in the binary, and no `vW` observer
    ///   symbol exists either. The `didSet` above is therefore left exactly as it was rather than
    ///   rewritten on a guess.
    /// ⚑[tool=export_trie_oracle ref=KSAVPlayer.isReadyToPlay.setter:0x10198eb18 result=DELETED-METHOD-FOLD]
    ///
    /// ⚑ ACCESS not independently proven: the method descriptor's flags encode kind and
    ///   instance-ness, not access; the trie name carries no private discriminator, so it is not
    ///   `private`; and `vtable_impl_oracle` proves access only on a `final` type or an actor,
    ///   which KSAVPlayer is not. `internal` is the narrower of the two remaining spellings and is
    ///   what a helper with no external call site needs — the same rule this reconstruction
    ///   applies to `KSComplexPlayerLayer.removeRemoteControllEvent()`.
    /// ⚑ THE MAIN-ACTOR HOP IS READ BUT CANNOT BE SPELLED YET, so it is pinned rather than
    ///   approximated. The statement is
    ///   `runOnMainThread { [weak self] in guard let self else { return }
    ///    delegate?.readyToPlay(player: self) }`, every piece of it derived above. It does not
    ///   compile against THIS tree because `runOnMainThread` is declared in Utility.swift with a
    ///   plain `@escaping @Sendable () -> Void` block, so the closure is non-isolated and passing
    ///   `any MediaPlayerDelegate` out of it is `error: sending value of non-Sendable type`.
    ///
    ///   The declaration is the thing that is wrong, and the trie says so outright: 0x101a03e88
    ///   demangles to `KSPlayer.runOnMainThread(block: @Swift.MainActor @Sendable () -> ()) -> ()`
    ///   — mangle `yyYbScMYcc`, carrying `Yb` (@Sendable) AND `ScMYc` (@MainActor). Utility.swift
    ///   drops the `@MainActor`, which is also why its `Thread.isMainThread` arm is a bare
    ///   `block()` where every inlined copy in the binary calls `MainActor.assumeIsolated`.
    ///
    ///   Correcting that declaration was measured, not guessed: of the 30+ call sites it breaks
    ///   exactly ONE — AudioBaseOutput.swift:179, where a non-Sendable `AudioBaseOutput` would
    ///   then have to cross into a @MainActor closure. Making that compile needs `AudioBaseOutput`
    ///   declared Sendable, and Sendable is a MARKER protocol that emits no conformance
    ///   descriptor anywhere in this image (0 in the whole KSPlayer module), so the binary can
    ///   neither confirm nor deny it. Writing it would be inventing a type. The fix is therefore
    ///   its own unit, and this statement waits for it rather than being half-written here.
    /// ⚑[tool=export_trie_oracle ref=KSPlayer.runOnMainThread:0x101a03e88 result=block-is-MainActor-Sendable]
    /// ⚑[tool=function_extents ref=KSAVPlayer.readyToPlay.closure:0x1019a4234 result=51-instr]
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx1 → KSAVPlayer desc 0x1039ec470] open: ProAVPlayer overrides it
    open func readyToPlay() {
        options.readyTime = CACurrentMediaTime()
        runOnMainThread { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.readyToPlay(player: self)
        }
    }

    // The completion carries @MainActor and @Sendable in the binary symbol; the source declared a
    // bare escaping closure.
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx8 → KSAVPlayer desc 0x1039ec478] open: ProAVPlayer overrides it
    open func seek(time: TimeInterval, completion: @escaping (@MainActor @Sendable (Bool) -> Void)) {
        // AN ENTIRE KSLog STATEMENT WAS MISSING. The binary opens with this gated log, and the
        // shouldSeekTo-vs-currentTime coalesce exists only to build the message — which is also why
        // it has to run BEFORE the `shouldSeekTo = time` store below, or it would read the new value
        // and the "from" half would always equal the "to" half.
        KSLog("\(self) seek from \(currentPlaybackTime) to \(time)", line: 269)
        let seekTime = max(time, 0)
        shouldSeekTo = seekTime
        playbackState = .seeking
        bufferingProgress = 0
        let tolerance: CMTime = options.isAccurateSeek ? .zero : .positiveInfinity
        player.seek(to: CMTime(seconds: seekTime), toleranceBefore: tolerance, toleranceAfter: tolerance) {
            [weak self] finished in
            guard let self else { return }
            runOnMainThread { [weak self] in
                guard let self else { return }
                self.shouldSeekTo = nil
                completion(finished)
            }
        }
    }
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx4 → KSAVPlayer desc 0x1039ec480] open: ProAVPlayer overrides it
    open func play() {
#sourceLocation(file: "KSPlayer/KSAVPlayer.swift", line: 286)
        KSLog("play \(self)")
#sourceLocation()
        playbackState = .playing }

    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx7 → KSAVPlayer desc 0x1039ec488] open: ProAVPlayer overrides it
    open func changePlaybackTime(time: TimeInterval) { delegate?.changePlaybackTime(player: self, time: time) }

    // KSPlayer.KSAVPlayer.update(loadState:oldValue:) @0x1019a4db8 — 167 instr, vtable slot 97.
    //   Trie-named `$s8KSPlayer10KSAVPlayerC6update9loadState8oldValueyAA09MediaLoadE0O_AHtF`, one
    //   symbol at the address, and the class's 281 trie symbols carry ZERO `33_<32hex>LL` manglings,
    //   so it is not file-private. The name is doubly grounded: the inlined KSLog's own `#function`
    //   literal decodes to "update(loadState:oldValue:)".
    //
    // ⚠️ THE `loadState` didSet ABOVE INLINES THIS BODY — and drops half of it. The didSet runs
    //   `playOrPause()` then `bufferingProgress = 0` for the non-playable states, but has NO
    //   `.playable` arm at all, so the firstPlayableTime stamp and its KSLog are simply absent from
    //   the reconstruction. (The two spellings of the other arm ARE equivalent: MediaLoadState is
    //   `idle, loading, playable`, so `else` and `.loading || .idle` cover the same cases.)
    //   Rewiring the didSet to CALL this is a separate unit — the didSet itself was not derived here,
    //   and this session has been bitten by assuming a caller's shape.
    //
    // Read from the binary: `cmp w19, w1, uxtb` / `b.eq` epilogue is the guard; `cmp w19, #0x2` picks
    //   the `.playable` arm (MediaLoadState tag 2); both `fcmp d0, #0.0` tests are on KSOptions fields
    //   (`firstPlayableTime` global 0x104c63490, `prepareTime` 0x104c63438) under a MODIFY access;
    //   the timestamp is `bl` QuartzCore `CACurrentMediaTime`. The body contains NO arithmetic at all
    //   — only `cmp`/`fcmp` against constants, no checked add, no CMTime.
    // ⚑ The logged value is `options.firstTimeLog()` @0x1019c0938, the member reconstructed earlier
    //   in this same session — an independent derivation arriving at it is a real cross-check.
    // ⚑ KSLog level constant is 3 = `.warning`, which is KSLog's declared default, so the bare form
    //   is the faithful spelling. Tag 3 is derived from the BINARY, not from source order: the
    //   `LogLevel.description` getter's `csel` ladder maps 0→panic 1→fatal 2→error 3→warning.
    // ⟨UNGROUNDED: `if a == 0, b != 0 { … }` versus two `guard … else { return }` — both arms exit to
    //  the same epilogue, so the source form is not separable from the codegen.⟩
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx6 → KSAVPlayer desc 0x1039ec490] open: ProAVPlayer overrides it
    open func update(loadState: MediaLoadState, oldValue: MediaLoadState) {
        guard loadState != oldValue else { return }
        playOrPause()
        if loadState == .playable {
            if options.firstPlayableTime == 0, options.prepareTime != 0 {
                options.firstPlayableTime = CACurrentMediaTime()
                KSLog(options.firstTimeLog(), line: 303)
            }
        } else {
            bufferingProgress = 0
        }
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
    @used func updatePlaybackBuffer() {
        guard let item = playerView.player.currentItem else {
            return
        }
        let isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
        let isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
        let isPlaybackBufferFull = item.isPlaybackBufferFull
        if isPlaybackLikelyToKeepUp || isPlaybackBufferFull {
            loadState = .playable
        } else if isPlaybackBufferEmpty {
            loadState = .loading
        } else {
            loadState = .loading
        }
    }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.nominalFrameRate(track:):0x1019a5128 result=12-instr]
    /// `bl swift_getObjectType` on the incoming track to get its Self metadata, then
    /// `ldr x8,[x19,#0x20]` — word 4 of the track's MediaPlayerTrack witness table, i.e.
    /// requirement 3 — and calls it with self in x20, metadata in x0 and the table in x1.
    /// Requirement 3 is DECODED, not counted: FFmpegAssetTrack's table at 0x1041d78b8 gives
    /// req3 = 0x101a1f5bc, which the trie names `FFmpegAssetTrack.nominalFrameRate.getter`.
    /// ⚑[tool=bind_oracle ref=__got:0x104112f08 result=_swift_getObjectType]
    /// ⚑[tool=decode_witness_table ref=FFmpegAssetTrack:MediaPlayerTrack@0x1041d78b8 result=req3-nominalFrameRate]
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx2 → KSAVPlayer desc 0x1039ec4a0] open: ProAVPlayer overrides it
    open func nominalFrameRate(track: any MediaPlayerTrack) -> Float {
        track.nominalFrameRate
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
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx5 → KSAVPlayer desc 0x1039ec4a8] open: ProAVPlayer overrides it
    open func process(error: Error) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            delegate?.finish(player: self, error: error)
        }
    }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.ioContext.getter:0x10002d9d4 result=mov-x0-0/ret]
    /// The whole body is `mov x0, #0x0` / `ret` — it returns nil unconditionally.
    /// The address is the image's 605-symbol ICF fold, so it carries nothing unique to this
    /// property; the two instructions are still genuinely this getter's code. The
    /// MetalRender.swift:26 note that also cites 0x10002d9d4 is another symbol at the same
    /// folded address, NOT a second name for this one.
    /// ⚑[tool=export_trie_oracle ref=0x10002d9d4 result=ICF-FOLD-605-symbols]
    // ⚑[tool=override_table ref=ProAVPlayer:0x1039f52c4 result=override idx3 → KSAVPlayer desc 0x1039ec4b0] open: ProAVPlayer overrides it
    open var ioContext: AbstractAVIOContext? {
        nil
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
    open func reset() {
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
}

extension KSAVPlayer {
    public var player: AVQueuePlayer { playerView.player }
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

    private func playOrPause() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            if self.playbackState == .playing {
                if self.loadState == .playable {
                    self.player.playImmediately(atRate: self.playbackRate)
                }
            } else {
                self.player.pause()
            }
            self.delegate?.changeLoadState(player: self)
        }
    }

    public func replaceCurrentItem(playerItem: AVPlayerItem?) {   // public (was private, P34): ProAVPlayer (separate module) slot15 item-swap closure installs its ProPlayerItem via this cross-module call (FUN_1019a563c)  ⚑[tool=resolve_fun_pins ref=FUN_1019a563c:0x1019a563c result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.replaceCurrentItem(playerItem: __C.AVPlayerItem?) -> ()
        bufferingProgress = 0
        player.currentItem?.cancelPendingSeeks()
        if options.isLoopPlay {
            observerLoopCancellables = Set()
            playerLooper?.disableLooping()
            guard let playerItem else {
                playerLooper = nil
                return
            }
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            playerLooper?.publisher(for: \.loopCount)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] loopCount in
                    guard let self else { return }
                    runOnMainThread { [weak self] in
                        guard let self else { return }
                        self.delegate?.playBack(player: self, loopCount: loopCount)
                    }
                }
                .store(in: &observerLoopCancellables)
            playerLooper?.publisher(for: \.status)
                .sink { [weak self] _ in
                    guard let self, let playerLooper = self.playerLooper else { return }
                    if playerLooper.status == .failed {
                        self.error = playerLooper.error
                    }
                }
                .store(in: &observerLoopCancellables)
        } else {
            player.replaceCurrentItem(with: playerItem)
        }
        player.actionAtItemEnd = .pause
        player.volume = playbackVolume
        error = nil
        isReadyToPlay = false
    }
    public var playerLayer: AVPlayerLayer { playerView.playerLayer }

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.startRecord(url:):0x10000e52c result=single-ret]
    /// The body IS 0x10000e52c, whose only instruction is `ret`. Empty, not unimplemented —
    /// this is the empty-body fold, distinct from the deleted-method stub at 0x10198eb18 which
    /// would have carried `bl swift_deletedMethodError` / `brk`.
    public func startRecord(url _: URL) {}

    /// ⚑[tool=llvm-objdump ref=KSAVPlayer.stopRecord():0x10000e52c result=single-ret]
    /// Same empty-body fold as `startRecord` above.
    public func stopRecord() {}

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

    /// @0x1019a9a9c, 116 instructions.
    ///
    /// It lives in an EXTENSION, and that is derived rather than stylistic: the whole export trie
    /// carries exactly ONE symbol containing `canQuickSeek` — the function
    /// `$s8KSPlayer10KSAVPlayerC12canQuickSeek4timeSbSd_tF` — and no `method descriptor`. No
    /// descriptor means no vtable slot, which is what distinguishes an extension member from a
    /// class-body one. Contrast `cachedTimeRanges` above, which has slot 45 and so must sit in the
    /// body.
    ///
    ///   · `self + 0x38` is `playerView` — the fixed instance offset this file already pins at the
    ///     `playbackCoordinator` note; the field global read off it is
    ///     `KSAVPlayerView.player : __C.AVQueuePlayer` (0x1044e46b0). So the receiver chain is
    ///     `playerView.player`, the same one line 194 establishes.
    ///   · `currentItem` is sent, and the `cbz x0` on the retained result is the `?.` — the nil
    ///     path falls to `mov w22,#0`, i.e. `false`.
    ///   · `loadedTimeRanges` is sent and bridged with
    ///     `Array._unconditionallyBridgeFromObjectiveC`, giving `[NSValue]`.
    ///   · the loop's `cset w22, ne` at the head is what is RETURNED: exhausting the array leaves
    ///     w22 = 0 and an early exit leaves it 1. That is `contains(where:)`, not a `for` loop
    ///     with a flag — nothing else writes w22.
    ///   · per element: `CMTimeRangeValue` (so `$0.timeRangeValue`), then
    ///     `CMTime(seconds:preferredTimescale:)` with `mov w0, #0x1e` = **30**, then
    ///     `_CMTimeRangeContainsTime`. The CMTime is built INSIDE the loop, not hoisted — the
    ///     call sits between the loop head at 0x1019a9b48 and the back-branch at 0x1019a9be4.
    /// ⚑[tool=export_trie_oracle ref=KSAVPlayer.canQuickSeek(time:):0x1019a9a9c result=OWNER_MATCH-no-method-descriptor]
    /// ⚑ ACCESS not independently proven: no private discriminator on the symbol, and a method
    ///   has no `vpMV` equivalent. `public` matches the two members above it in this extension.
    public func canQuickSeek(time: Double) -> Bool {
        guard let loadedTimeRanges = playerView.player.currentItem?.loadedTimeRanges else {
            return false
        }
        for value in loadedTimeRanges {
            if CMTimeRangeContainsTime(value.timeRangeValue, time: CMTime(seconds: time, preferredTimescale: 30)) {
                return true
            }
        }
        return false
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
    public var view: UIView { playerView }
    public var currentPlaybackTime: TimeInterval {
        get {
            if let shouldSeekTo {
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
    // ⚑ RETYPED to the refined protocol, from this getter's own mangled name:
    //   `$s8KSPlayer10KSAVPlayerC18subtitleDataSourceAA016ConstantSubtitledE0_pSgvg`
    //   = `KSAVPlayer.subtitleDataSource.getter : ConstantSubtitleDataSource?`. Getter-only — the
    //   binary carries no `vs`/`vM` for it. The body stays `nil`; returning nil needs no conformance.
    // ⚑[tool=export_trie_oracle ref=KSAVPlayer.subtitleDataSource.getter:0x1019a911c result=ConstantSubtitleDataSource-optional]
    public var subtitleDataSource: (any ConstantSubtitleDataSource)? { self }
    public var isPlaying: Bool { player.timeControlStatus == .playing }

    public var numberOfBytesTransferred: Int64 {
        guard let playerItem = player.currentItem, let accesslog = playerItem.accessLog(), let event = accesslog.events.first else {
            return 0
        }
        return event.numberOfBytesTransferred
    }

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        guard let playerItem = player.currentItem, isReadyToPlay else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            playerItem.asset.thumbnailImage(currentTime: playerItem.currentTime()) { @Sendable result in
                continuation.resume(returning: result)
            }
        }
    }

    public func pause() {
        KSLog("pause \(self)", line: 652)
        playbackState = .paused
    }

    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)", line: 657)
        options.prepareTime = CACurrentMediaTime()
        isReadyToPlay = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let playerItem = try await self.createPlayerItem()
                self.options.openTime = CACurrentMediaTime()
                self.replaceCurrentItem(playerItem: playerItem)
            } catch {
                self.error = error
            }
        }
    }

    public func stop() {
        KSLog("stop \(self)", line: 674)
        reset()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    // Ref 0x1019aa5d4 ignores custom IO and forwards URL to the asset path.
    public func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {
        if case let .left(url) = io {
            replace(io: Either<URL, AVAsset>.left(url), options: options)
        }
    }

    public func replace(io: Either<URL, AVAsset>, options: KSOptions) {
        KSLog("replaceUrl \(self)", line: 690)
        reset()
        self.io = io
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
        if shouldResumePlayback {
            playbackState = .playing
        } else {
            playbackState = .paused
        }
    }

    public var seekable: Bool {
        guard duration != 0, !duration.isNaN else {
            return false
        }
        return !(player.currentItem?.seekableTimeRanges.isEmpty ?? true)
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
        mediaPlayerTracks.filter { $0.mediaType == mediaType }
    }

    public func select(track: some MediaPlayerTrack) {
        mediaPlayerTracks.filter { $0.mediaType == track.mediaType }.forEach { $0.isEnabled = false }
        if track.mediaType == .subtitle {
            subtitleTracks.forEach { $0.isEnabled = false }
        }
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
    let nominalFrameRate: Float
    let bitRate: Int64
    let trackID: Int32
    // ⚑[tool=field_surface ref=AVMediaPlayerTrack.reorderSize:idx7 result=let Int32] declared now;
    // its value stays unread (dead-stripped init, above), so init assigns it under an L7 marker.
    let reorderSize: Int32
    let bitDepth: Int32
    let rotation: UInt16 = 0
    let fieldOrder: FFmpegFieldOrder = .unknown
    let isImageSubtitle = false
    let isPlayable: Bool
    let languageCode: String?
    let dovi: DOVIDecoderConfigurationRecord?
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
        reorderSize = 0 // L7: Forward's init is dead-stripped; the stored value was not read
        dovi = nil // L7: Forward's init is dead-stripped; the stored value was not read
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
    }

    final func load() {}
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

// AVMediaSelectionTrack @0x1039ec0e0 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_upper(inferred) (resource_bundle_accessor.swift..KSAVPlayer.swift).
// ⚑[tool=type_surface ref=AVMediaSelectionTrack:0x1039ec0e0 result=class AVMediaSelectionTrack: MediaPlayerTrack, SubtitleInfo]
final class AVMediaSelectionTrack: MediaPlayerTrack, SubtitleInfo {
    // ⚑[tool=field_surface ref=AVMediaSelectionTrack:fieldmd result=6 fields size 80] `group` and
    // `playerItem` export vpfi (declaration defaults). The only vtable entry, the initializer,
    // has a NULL Impl (dead-stripped), so no stored values are readable.
    let option: AVMediaSelectionOption
    var group: AVMediaSelectionGroup? = nil
    weak var playerItem: AVPlayerItem? = nil
    let name: String
    let trackID: Int32
    let languageCode: String?

    init() {
        option = AVMediaSelectionOption()
        name = ""
        trackID = 0
        languageCode = nil
    }

    func search(with query: KSSubtitleQuery) async -> [SubtitlePart] { [] }
    var mediaType: AVFoundation.AVMediaType { option.mediaType }
    var nominalFrameRate: Float { get { 1.0 } set {} }
    var bitRate: Int64 { 0 }
    var reorderSize: Int32 { 0 }
    var bitDepth: Int32 { 0 }
    var isEnabled: Bool {
        get {
            if let group, let playerItem {
                // `currentMediaSelection` is main-actor isolated in the SDK; read it through KVC
                // from this nonisolated class.
                return (playerItem.value(forKey: "currentMediaSelection") as? AVMediaSelection)?.selectedMediaOption(in: group) == option
            }
            return false
        }
        set {
            if let group, let playerItem {
                playerItem.select(newValue ? option : nil, in: group)
            }
        }
    }
    var isImageSubtitle: Bool { false }
    var rotation: UInt16 { 0 }
    var dovi: DOVIDecoderConfigurationRecord? { nil }
    var fieldOrder: FFmpegFieldOrder { .unknown }
    var formatDescription: CMFormatDescription? { nil }
    var subtitleID: String { String(describing: trackID) }
    var delay: TimeInterval { 0 }
    var renderMode: SubtitleRenderMode { .srtView }
    var description: String { name }
}
