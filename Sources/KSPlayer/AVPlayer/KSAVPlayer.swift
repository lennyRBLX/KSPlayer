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
    // ⚑ DIVERGENCE-DEFERRED (user-gated s16): binary field 11 `pipController` is `(any KSPictureInPictureProtocol)?`
    //   — a NEW protocol absent from recon (field-record `KSPictureInPictureProtocol_pSg`). Kept the recon concrete type to
    //   avoid a MediaPlayerProtocol version-ripple; l2 UNCHECKED (no class-scoped symbol). → MediaPlayerProtocol-version follow-on.
    public private(set) var pipController: KSPictureInPictureController?
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
            delegate?.changeBuffering(player: self, progress: Int(bufferingProgress))
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

    public func replaceCurrentItem(playerItem: AVPlayerItem?) {   // public (was private, P34): ProAVPlayer (separate module) slot15 item-swap closure installs its ProPlayerItem via this cross-module call (FUN_1019a563c)
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
    public var view: UIView? { playerView }
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

    public func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        let time = max(time, 0)
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

    public func shutdown() {
        KSLog("shutdown \(self)")
        isReadyToPlay = false
        playbackState = .stopped
        loadState = .idle
        // ⚑ M2: cancelLoading on the `io` asset (was urlAsset.cancelLoading())
        replaceCurrentItem(playerItem: nil)
    }

    public func replace(url: URL, options: KSOptions) {
        KSLog("replaceUrl \(self)")
        shutdown()
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
    // ⚑[tool=dump_binary_field_types ref=AVMediaPlayerTrack.reorderSize:idx8 result=pinned]
    //   The binary has 16 fields; this source has 15. `reorderSize: Swift.Int32` sits at
    //   index 8, between `trackID` and `bitDepth`, and is NOT declared here. It is left out
    //   rather than invented: adding a stored property changes the layout, and nothing in
    //   this class reads or writes it, so there is no body to derive its use from. The gate
    //   reports it as `field in binary, absent in source` — that FLAG is the marker.
    private let track: AVPlayerItemTrack
    let mediaType: AVFoundation.AVMediaType
    let name: String
    let description: String
    var nominalFrameRate: Float
    let bitRate: Int64
    let trackID: Int32
    // reorderSize: Int32 — binary index 8, undeclared (see the pin above)
    let bitDepth: Int32
    let rotation: Int16 = 0
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
    // Task 6 (session 20). Witness 0x1019aba18 (async trampoline) → FUN_1019ab818 (task_switch hop) → FUN_1019ab830:
    // reads the stored `subtitleTracks: [any MediaPlayerTrack]` (_swift_beginAccess) and collects the SubtitleInfo
    // conformers (_swift_getObjectType + _swift_conformsToProtocol per element). Return element PROVEN `[any SubtitleInfo]`,
    // NOT rippled to [URLSubtitleInfo] (P55/P60, opposite of the Search/URL siblings): each element is stored as a 2-word
    // class-existential {object@+0x20, witnessTable@+0x28} at stride 0x10 (FUN_1019ab830) — boxing PRESENT ⇒ existential.
    public func searchSubtitle() async throws -> [any SubtitleInfo] {
        subtitleTracks.compactMap { $0 as? (any SubtitleInfo) }
    }
}
