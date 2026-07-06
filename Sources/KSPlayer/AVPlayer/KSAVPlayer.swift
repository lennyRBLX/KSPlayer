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
    private var cancellable: AnyCancellable?
    private var periodicTimeObserver: Any?
    private let playerView: KSAVPlayerView = KSAVPlayerView()
    private var io: Either<URL, AVAsset>
    private var shouldSeekTo: Double?
    private var playerLooper: AVPlayerLooper?
    private var mediaPlayerTracks: [any MediaPlayerTrack] = []
    private var subtitleTracks: [any MediaPlayerTrack] = []
    private var observerCancellables: Set<AnyCancellable> = []
    private var observerPlayerItemCancellables: Set<AnyCancellable> = []
    private var observerLoopCancellables: Set<AnyCancellable> = []
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
    public let chapters: [Chapter] = []
    public var naturalSize: CGSize = .zero
    private var shouldResumePlayback: Bool = false
    private var options: KSOptions {
        didSet {
            player.currentItem?.preferredForwardBufferDuration = options.preferredForwardBufferDuration
            cancellable = options.$preferredForwardBufferDuration.sink { [weak self] newValue in
                self?.player.currentItem?.preferredForwardBufferDuration = newValue
            }
        }
    }

    private var error: Error? {
        didSet {
            if let error {
                delegate?.finish(player: self, error: error)
            }
        }
    }

    // binary `$__lazy_storage_$_dynamicInfo` (reflection-filtered lazy backing); recon had `let dynamicInfo = nil`.
    // ⚑ UNRESOLVED → KSAVPlayer M2: the binary builds a DynamicInfo lazily (metadata/bytesRead/bitrate blocks).
    public lazy var dynamicInfo: DynamicInfo? = nil

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

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        playerView.player.playbackCoordinator
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
    let formatDescription: CMFormatDescription?
    let description: String
    private let track: AVPlayerItemTrack
    var nominalFrameRate: Float
    let trackID: Int32
    let rotation: Int16 = 0
    let bitDepth: Int32
    let bitRate: Int64
    let name: String
    let languageCode: String?
    let mediaType: AVFoundation.AVMediaType
    let isImageSubtitle = false
    var dovi: DOVIDecoderConfigurationRecord?
    let fieldOrder: FFmpegFieldOrder = .unknown
    var isPlayable: Bool
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
