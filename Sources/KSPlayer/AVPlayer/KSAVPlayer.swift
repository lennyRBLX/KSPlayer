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

/// Input source for `KSAVPlayer`. The binary's `io` field is an `Either<URL, AVAsset>`: the
/// player can be created from a URL (the common case, which derives an `AVURLAsset`) or from an
/// already-constructed `AVAsset` (e.g. a composition or a remux output).
/// RE: KSAVPlayer stored property #4 `io` (1.3.15).
public enum PlayerInputSource {
    case url(URL)
    case asset(AVAsset)

    /// Resolves the source to a concrete `AVAsset`. The URL case builds an `AVURLAsset` using
    /// the options' `avOptions`; the asset case is returned as-is.
    func asset(options: KSOptions) -> AVAsset {
        switch self {
        case let .url(url):
            return AVURLAsset(url: url, options: options.avOptions)
        case let .asset(asset):
            return asset
        }
    }

    /// The originating URL when the source is URL-backed (nil for direct-asset sources).
    var url: URL? {
        if case let .url(url) = self {
            return url
        }
        return nil
    }
}

public final class KSAVPlayerView: UIView {
    public let player = AVQueuePlayer()
    /// RE: 0x101387acc (KSAVPlayerView.init, 1.3.15). AVQueuePlayer render surface; on AppKit the
    /// backing layer is an AVPlayerLayer (UIKit supplies it via `layerClass`).
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

    /// RE: 0x101387f14 (get) / 0x1013881fc (set) (KSAVPlayerView.contentMode, 1.3.15).
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
public class KSAVPlayer {
    private var cancellable: AnyCancellable?
    private var options: KSOptions {
        didSet {
            player.currentItem?.preferredForwardBufferDuration = options.preferredForwardBufferDuration
            cancellable = options.$preferredForwardBufferDuration.sink { [weak self] newValue in
                self?.player.currentItem?.preferredForwardBufferDuration = newValue
            }
        }
    }

    private let playerView = KSAVPlayerView()
    /// Input source — the binary stores this as an enum that can hold either a URL
    /// or an already-constructed AVAsset (`Either<URL, AVAsset>`), so the player can be
    /// initialized directly from an asset, not only from a URL. Setting it invalidates the
    /// cached resolved asset so the next access rebuilds from the new source.
    /// RE: stored property #4 `io` (KSAVPlayer, 1.3.15).
    private var io: PlayerInputSource {
        didSet { _resolvedAsset = nil }
    }

    /// Cache for the resolved AVAsset so repeated `urlAsset` reads return the same instance
    /// (preserves loading/identity semantics for `cancelLoading`, thumbnails, and item creation).
    private var _resolvedAsset: AVAsset?
    /// The resolved input asset (AVURLAsset for the URL case, the supplied AVAsset otherwise).
    private var urlAsset: AVAsset {
        if let _resolvedAsset {
            return _resolvedAsset
        }
        let asset = io.asset(options: options)
        _resolvedAsset = asset
        return asset
    }
    private var shouldSeekTo = TimeInterval(0)
    /// Periodic AVPlayer time observation token. Added in `prepareToPlay`, removed in
    /// `shutdown`. Drives the per-tick `currentPlaybackTime` delegate callback via
    /// `notifyDelegate_currentTime`.
    /// RE: stored property #2 `periodicTimeObserver` (KSAVPlayer, 1.3.15).
    private var periodicTimeObserver: Any?
    /// Persisted resume-playback bit. Reflects whether playback should auto-resume after a
    /// background/PiP interruption — written by `saveShouldResumePlayback`.
    /// RE: stored property `shouldResumePlayback` (KSAVPlayer, 1.3.15), writer 0x1013923d4.
    private var shouldResumePlayback = false
    private var playerLooper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var loadedTimeRangesObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var bufferFullObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var loopCountObservation: NSKeyValueObservation?
    private var loopStatusObservation: NSKeyValueObservation?
    private var mediaPlayerTracks = [AVMediaPlayerTrack]()
    private var error: Error? {
        didSet {
            if let error {
                delegate?.finish(player: self, error: error)
            }
        }
    }

    private lazy var _pipController: Any? = {
        if #available(tvOS 14.0, *) {
            let pip = KSPictureInPictureController(playerLayer: playerView.playerLayer)
            return pip
        } else {
            return nil
        }
    }()

    @available(tvOS 14.0, *)
    public var pipController: KSPictureInPictureController? {
        _pipController as? KSPictureInPictureController
    }

    public var naturalSize: CGSize = .zero
    /// Lazy dynamic playback info (bytes transferred, bitrate estimates) sourced from the
    /// AVPlayerItem access log. The AVPlayer path exposes no per-frame decode stats, so the
    /// metadata block is empty and the FPS/sync fields stay at their defaults; only the byte
    /// counter and the estimated bitrate are live.
    /// RE: 0x101389230 (KSAVPlayer.dynamicInfo lazy getter, 1.3.15).
    public lazy var dynamicInfo: DynamicInfo? = DynamicInfo { [weak self] in
        // metadata — empty for the AVPlayer path (binary returns __swiftEmptyArrayStorage).
        self?.dynamicMetadata() ?? [:]
    } bytesRead: { [weak self] in
        self?.numberOfBytesTransferred ?? 0
    } audioBitrate: { [weak self] in
        Int(self?.mediaPlayerTracks.first { $0.mediaType == .audio }?.bitRate ?? 0)
    } videoBitrate: { [weak self] in
        Int(self?.mediaPlayerTracks.first { $0.mediaType == .video }?.bitRate ?? 0)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        playerView.player.playbackCoordinator
    }

    public private(set) var bufferingProgress = 0 {
        didSet {
            delegate?.changeBuffering(player: self, progress: bufferingProgress)
        }
    }

    public weak var delegate: MediaPlayerDelegate?
    public private(set) var duration: TimeInterval = 0
    public private(set) var fileSize: Double = 0
    public private(set) var playableTime: TimeInterval = 0
    public let chapters: [Chapter] = []
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

    public private(set) var loadState = MediaLoadState.idle {
        didSet {
            if loadState != oldValue {
                playOrPause()
                if loadState == .loading || loadState == .idle {
                    bufferingProgress = 0
                }
            }
        }
    }

    public private(set) var playbackState = MediaPlaybackState.idle {
        didSet {
            if playbackState != oldValue {
                playOrPause()
                if playbackState == .finished {
                    delegate?.finish(player: self, error: nil)
                }
            }
        }
    }

    public private(set) var isReadyToPlay = false {
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

    /// RE: 0x101286520 (KSAVPlayer.init, 1.3.15). Builds the render surface, stores the input
    /// source, and installs the `currentItem` KVO publisher.
    public required init(url: URL, options: KSOptions) {
        KSOptions.setAudioSession()
        io = .url(url)
        self.options = options
        itemObservation = player.observe(\.currentItem) { [weak self] player, _ in
            guard let self else { return }
            self.observer(playerItem: player.currentItem)
        }
    }

    /// RE: 0x101286520 (KSAVPlayer.init, 1.3.15) — AVAsset-direct entry point. The binary's
    /// `io` field is `Either<URL, AVAsset>`; this initializer reaches the asset case that
    /// `init(url:options:)` cannot.
    public convenience init(asset: AVAsset, options: KSOptions) {
        self.init(url: URL(fileURLWithPath: "/"), options: options)
        io = .asset(asset)
    }

    /// RE: 0x10127A238 (KSAVPlayer.deinit, 1.3.15). Swift ARC releases the ~18 reference-typed
    /// ivars automatically; this body performs the explicit teardown the binary traced —
    /// invalidating KVO observations, removing the periodic time observer and NotificationCenter
    /// observers, and emitting the trace log (binary logs at logLevel >= 3).
    deinit {
        KSLog(level: .debug, "KSAVPlayer deinit \(self)")
        cancellable?.cancel()
        statusObservation?.invalidate()
        loadedTimeRangesObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferFullObservation?.invalidate()
        itemObservation?.invalidate()
        loopCountObservation?.invalidate()
        loopStatusObservation?.invalidate()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        NotificationCenter.default.removeObserver(self)
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

    /// RE: 0x10127d714 / 0x101390314 (KSAVPlayer.onStatusChanged, 1.3.15).
    private func updateStatus(item: AVPlayerItem) {
        if item.status == .readyToPlay {
            options.findTime = CACurrentMediaTime()
            mediaPlayerTracks = item.tracks.map {
                AVMediaPlayerTrack(track: $0)
            }
            let playableVideo = mediaPlayerTracks.first {
                $0.mediaType == .video && $0.isPlayable
            }
            if let playableVideo {
                naturalSize = playableVideo.naturalSize
            } else {
                error = NSError(errorCode: .videoTracksUnplayable)
                return
            }
            // 默认选择第一个声道
            item.tracks.filter { $0.assetTrack?.mediaType.rawValue == AVMediaType.audio.rawValue }.dropFirst().forEach { $0.isEnabled = false }
            duration = item.duration.seconds
            let estimatedDataRates = item.tracks.compactMap { $0.assetTrack?.estimatedDataRate }
            fileSize = Double(estimatedDataRates.reduce(0, +)) * duration / 8
            isReadyToPlay = true
        } else if item.status == .failed {
            error = item.error
        }
    }

    private func updatePlayableDuration(item: AVPlayerItem) {
        let first = item.loadedTimeRanges.first { CMTimeRangeContainsTime($0.timeRangeValue, time: item.currentTime()) }
        if let first {
            playableTime = first.timeRangeValue.end.seconds
            guard playableTime > 0 else { return }
            let loadedTime = playableTime - currentPlaybackTime
            guard loadedTime > 0 else { return }
            bufferingProgress = Int(min(loadedTime * 100 / item.preferredForwardBufferDuration, 100))
            if bufferingProgress >= 100 {
                loadState = .playable
            }
        }
    }

    /// Loaded-range membership test: returns whether `time` (seconds) falls inside any of the
    /// current AVPlayerItem `loadedTimeRanges`. The binary exposed this as a discrete helper
    /// (rather than fusing it into `updatePlayableDuration`), so it is preserved as a named
    /// method here.
    /// RE: 0x101391480 (KSAVPlayer.isCurrentTimeInLoadedRanges, 1.3.15).
    private func isCurrentTimeInLoadedRanges(_ time: TimeInterval) -> Bool {
        guard let loadedTimeRanges = player.currentItem?.loadedTimeRanges else { return false }
        // Decompile builds the probe CMTime at preferredTimescale 30 (0x1e).
        let probe = CMTime(seconds: time, preferredTimescale: 30)
        return loadedTimeRanges.contains { CMTimeRangeContainsTime($0.timeRangeValue, time: probe) }
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

    /// RE: 0x101279afc (KSAVPlayer.configurePlayerItem, 1.3.15). Resets buffering and, when
    /// looping, drives playback through an AVPlayerLooper instead of a plain item replacement.
    private func replaceCurrentItem(playerItem: AVPlayerItem?) {
        player.currentItem?.cancelPendingSeeks()
        if options.isLoopPlay {
            loopCountObservation?.invalidate()
            loopStatusObservation?.invalidate()
            playerLooper?.disableLooping()
            guard let playerItem else {
                playerLooper = nil
                return
            }
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            loopCountObservation = playerLooper?.observe(\.loopCount) { [weak self] playerLooper, _ in
                guard let self else { return }
                self.delegate?.playBack(player: self, loopCount: playerLooper.loopCount)
            }
            loopStatusObservation = playerLooper?.observe(\.status) { [weak self] playerLooper, _ in
                guard let self else { return }
                if playerLooper.status == .failed {
                    self.error = playerLooper.error
                }
            }
        } else {
            player.replaceCurrentItem(with: playerItem)
        }
    }

    private func observer(playerItem: AVPlayerItem?) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        statusObservation?.invalidate()
        loadedTimeRangesObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferFullObservation?.invalidate()
        guard let playerItem else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(moviePlayDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        statusObservation = playerItem.observe(\.status) { [weak self] item, _ in
            guard let self else { return }
            self.updateStatus(item: item)
        }
        loadedTimeRangesObservation = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let self else { return }
            // 计算缓冲进度
            self.updatePlayableDuration(item: item)
        }

        let changeHandler: (AVPlayerItem, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            guard let self else { return }
            // 在主线程更新进度
            if playerItem.isPlaybackBufferEmpty {
                self.loadState = .loading
            } else if playerItem.isPlaybackLikelyToKeepUp || playerItem.isPlaybackBufferFull {
                self.loadState = .playable
            }
        }
        bufferEmptyObservation = playerItem.observe(\.isPlaybackBufferEmpty, changeHandler: changeHandler)
        likelyToKeepUpObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, changeHandler: changeHandler)
        bufferFullObservation = playerItem.observe(\.isPlaybackBufferFull, changeHandler: changeHandler)
    }

    /// Fires the delegate's per-tick playback callback on each periodic time observation.
    /// `MediaPlayerDelegate` carries no dedicated currentTime method, so the tick is surfaced
    /// through `playBack(player:loopCount:)` (the looper's loop count, 0 when not looping) —
    /// the same callback the layer's tick clock consumes to refresh the scrubber.
    /// RE: 0x10138c2fc (KSAVPlayer.notifyDelegate_currentTime, 1.3.15).
    private func notifyDelegateCurrentTime() {
        guard let delegate else { return }
        delegate.playBack(player: self, loopCount: playerLooper?.loopCount ?? 0)
    }

    /// Persists the resume-playback bit. Mirrors the binary: when the options resume flag is
    /// set the player always resumes; otherwise it resumes only if it was actively playing.
    /// RE: 0x1013923d4 (KSAVPlayer.saveShouldResumePlayback, 1.3.15). Tail-call thunk 0x1013931b0.
    /// KSMEPlayer counterpart: 0x101424db4.
    private func saveShouldResumePlayback() {
        // options+0x46 — the "always resume" intent flag (loop playback keeps resuming).
        // TODO(re-verify): confirm the exact KSOptions field at byte offset 0x46 vs isLoopPlay.
        shouldResumePlayback = options.isLoopPlay || playbackState == .playing
    }

    /// Dynamic metadata for the AVPlayer path. The binary returns the empty-array storage
    /// (no key/value metadata is surfaced for AVPlayer-backed playback).
    /// RE: 0x101389324 (dynamicInfo metadata closure, 1.3.15).
    private func dynamicMetadata() -> [String: String] {
        [:]
    }
}

extension KSAVPlayer: MediaPlayerProtocol {
    public var subtitleDataSource: SubtitleDataSource? { nil }
    public var isPlaying: Bool { player.rate > 0 ? true : playbackState == .playing }
    public var view: UIView? { playerView }
    public var currentPlaybackTime: TimeInterval {
        get {
            if shouldSeekTo > 0 {
                return TimeInterval(shouldSeekTo)
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
        guard let playerItem = player.currentItem, isReadyToPlay else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            urlAsset.thumbnailImage(currentTime: playerItem.currentTime()) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// RE: 0x10127e47c (KSAVPlayer.seek, 1.3.15). MainActor hop trampoline at 0x100462fa4 gates
    /// entry to this body in the binary.
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

    /// RE: 0x10127efe0 (KSAVPlayer.prepareToPlay, 1.3.15). Records `prepareTime`, then hops to
    /// the main actor to build the player item, install the periodic time observer, and start
    /// buffering.
    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)")
        options.prepareTime = CACurrentMediaTime()
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.bufferingProgress = 0
            let playerItem = AVPlayerItem(asset: self.urlAsset)
            self.options.openTime = CACurrentMediaTime()
            self.replaceCurrentItem(playerItem: playerItem)
            self.player.actionAtItemEnd = .pause
            self.player.volume = self.playbackVolume
            self.addPeriodicTimeObserver()
        }
    }

    /// Installs the AVPlayer periodic time observer that drives the per-tick currentTime
    /// delegate callback. Removes any prior observer first so prepare is idempotent.
    /// RE: 0x101286520 (KSAVPlayer.init / time-observer setup, 1.3.15).
    private func addPeriodicTimeObserver() {
        removePeriodicTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.notifyDelegateCurrentTime()
        }
    }

    /// Removes the periodic time observer from the AVPlayer and clears its storage.
    /// RE: 0x10127f844 (KSAVPlayer.stop — observer teardown, 1.3.15).
    private func removePeriodicTimeObserver() {
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    /// RE: 0x10127ebdc (KSAVPlayer.play, 1.3.15).
    public func play() {
        KSLog("play \(self)")
        playbackState = .playing
    }

    /// RE: 0x10127eddc (KSAVPlayer.pause, 1.3.15).
    public func pause() {
        KSLog("pause \(self)")
        playbackState = .paused
    }

    /// RE: 0x10127f844 (KSAVPlayer.stop, 1.3.15). Tears down playback: removes the periodic
    /// time observer, cancels asset loading, and drops the current item.
    public func shutdown() {
        KSLog("shutdown \(self)")
        isReadyToPlay = false
        playbackState = .stopped
        loadState = .idle
        removePeriodicTimeObserver()
        (urlAsset as? AVURLAsset)?.cancelLoading()
        replaceCurrentItem(playerItem: nil)
    }

    public func replace(url: URL, options: KSOptions) {
        KSLog("replaceUrl \(self)")
        shutdown()
        io = .url(url)
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
        // Persist whether playback should auto-resume before detaching the render layer.
        saveShouldResumePlayback()
        playerView.playerLayer.player = nil
    }

    public func enterForeground() {
        playerView.playerLayer.player = playerView.player
        // The persisted `shouldResumePlayback` bit is consumed by the owning KSPlayerLayer's
        // resume flow (RE: KSPlayerLayer_resumePlayback 0x1013b1044), not re-driven here.
    }

    /// RE: 0x1013925ac (KSAVPlayer.seekable getter, 1.3.15).
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

    /// RE: 0x10139278c (KSAVPlayer.tracks(mediaType:), 1.3.15).
    public func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack] {
        player.currentItem?.tracks.filter { $0.assetTrack?.mediaType == mediaType }.map { AVMediaPlayerTrack(track: $0) } ?? []
    }

    /// RE: 0x101392a10 (KSAVPlayer.select(track:), 1.3.15).
    public func select(track: some MediaPlayerTrack) {
        player.currentItem?.tracks.filter { $0.assetTrack?.mediaType == track.mediaType }.forEach { $0.isEnabled = false }
        track.isEnabled = true
    }
}

// MARK: - Subtitle auto-selection

extension KSAVPlayer {
    /// Automatically select the first subtitle track matching the current locale language.
    /// RE binary address: 0x10128F8E0. Iterates subtitle tracks, matches languageCode
    /// against the device locale, and enables the first match.
    ///
    /// FFmpeg subtitle codec IDs occupy the range 0x17000...0x17FFF. This method
    /// validates that tracks fall within the expected subtitle codec range before selection
    /// (only applicable when working with FFmpeg-backed tracks that expose codecID).
    /// Subtitle-specific track filter. The binary exposed this as a discrete named function
    /// (`filterSubtitleTracks`) rather than always going through the generic `tracks(mediaType:)`.
    /// RE: 0x10139331c (KSAVPlayer.filterSubtitleTracks, 1.3.15).
    private func subtitleTracks() -> [MediaPlayerTrack] {
        tracks(mediaType: .subtitle)
    }

    private func autoSelectMatchingSubtitleTrack() {
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let subtitleTracks = subtitleTracks()
        guard !subtitleTracks.isEmpty else { return }
        for track in subtitleTracks {
            if let langCode = track.languageCode,
               langCode.lowercased() == preferredLanguage.lowercased()
            {
                select(track: track)
                KSLog("[subtitle] auto-selected subtitle track: \(track.name) language: \(langCode)")
                return
            }
        }
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

class AVMediaPlayerTrack: MediaPlayerTrack {
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
