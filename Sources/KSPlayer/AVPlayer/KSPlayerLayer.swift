//
//  KSPlayerLayerView.swift
//  Pods
//
//  Created by kintan on 16/4/28.
//
//
import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/**
 Player status emun
 - setURL:      set url
 - readyToPlay:    player ready to play
 - buffering:      player buffering
 - bufferFinished: buffer finished
 - playedToTheEnd: played to the End
 - error:          error with playing
 */
public enum KSPlayerState: CustomStringConvertible {
    case initialized
    case preparing
    case readyToPlay
    case buffering
    case bufferFinished
    case paused
    case playedToTheEnd
    case error
    public var description: String {
        switch self {
        case .initialized:
            return "initialized"
        case .preparing:
            return "preparing"
        case .readyToPlay:
            return "readyToPlay"
        case .buffering:
            return "buffering"
        case .bufferFinished:
            return "bufferFinished"
        case .paused:
            return "paused"
        case .playedToTheEnd:
            return "playedToTheEnd"
        case .error:
            return "error"
        }
    }

    public var isPlaying: Bool { self == .buffering || self == .bufferFinished }
}

@MainActor
public protocol KSPlayerLayerDelegate: AnyObject {
    func player(layer: KSPlayerLayer, state: KSPlayerState)
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval)
    func player(layer: KSPlayerLayer, finish error: Error?)
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval)
}

/// Supplies rendered subtitle frames for the Picture-in-Picture overlay.
///
/// The PiP sample-buffer pipeline cannot reuse the on-screen Libass/`UIKit` subtitle views, so the
/// view layer adopts this protocol and is handed to the engine via `KSPlayerLayer.pipSubtitleProvider`.
/// `KSComplexPlayerLayer.setupSubtitleAndPipDelegate()` casts that provider to this protocol and wires
/// it onto the PiP controller's `subtitleDelegate`. Class-bound so it can be held as a `weak`
/// delegate alongside the other layer delegates.
@MainActor
public protocol KSPipSubtitleDelegate: AnyObject {
    /// The subtitle rendered to a bitmap for the requested presentation time, or `nil` when no
    /// cue is active. Used for image/bitmap subtitle tracks (PGS/VobSub) and rasterized Libass output.
    func pipSubtitleImage(at time: TimeInterval) -> UIImage?
    /// The subtitle as styled text for the requested presentation time, or `nil` when no cue is
    /// active. Used for text subtitle tracks (SRT/ASS) rendered into the PiP overlay.
    func pipSubtitleAttributedText(at time: TimeInterval) -> NSAttributedString?
}

/// RE: 0x1013bacf4 (`$s8KSPlayer13KSPlayerLayerCMa`, KSPlayerLayer type metadata accessor, 1.3.15;
/// confirmed via class_addr_map.json). Superclass is **NSObject** (not CALayer); the type is
/// `@MainActor`-isolated and has one reconstructed subclass, `KSComplexPlayerLayer`.
open class KSPlayerLayer: NSObject {
    public weak var delegate: KSPlayerLayerDelegate?
    /// External provider for PiP subtitle rendering (set by the view layer).
    /// Typed as AnyObject to avoid availability constraints; cast to KSPipSubtitleDelegate at use site.
    public weak var pipSubtitleProvider: AnyObject?
    // RE field #2 (0x103B3D988) `_bufferingProgress`: @Published, UInt8-backed per types.json layout.
    // The 1.3.14 source declared this as `Int`; the binary storage is a single byte.
    @Published
    public var bufferingProgress: UInt8 = 0
    // RE field #3 (0x103B3D9A0) `_loopCount`: @Published Int.
    @Published
    public var loopCount: Int = 0
    @Published
    public var isPipActive = false {
        didSet {
            if #available(tvOS 14.0, *) {
                guard let pipController = player.pipController else {
                    return
                }

                if isPipActive {
                    // 一定要async才不会pip之后就暂停播放
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        pipController.start(view: self)
                    }
                } else {
                    pipController.stop(restoreUserInterface: true)
                }
            }
        }
    }

    // RE field #4 (0x1041F79A0) `options`.
    public private(set) var options: KSOptions

    // RE field #5 (0x1041F79A8) `subtitleVC`: the subtitle-overlay hosting controller, injected by
    // `insertSubtitleViewBelowPlayer`. The 1.3.15 layout corrected the type from a bare
    // `UIViewController?` to `UIHostingController<VideoSubtitleView>?`. SwiftUI hosting controllers are
    // platform-typed (`UIHostingController` on UIKit, `NSHostingController` on AppKit), so the storage
    // is guarded by platform; both wrap the same `VideoSubtitleView`.
    #if canImport(UIKit)
    public var subtitleVC: UIHostingController<VideoSubtitleView>?
    #else
    public var subtitleVC: NSHostingController<VideoSubtitleView>?
    #endif

    // RE field #6 (0x1041F79B0) `subtitleView`: the subtitle container view injected into the view
    // hierarchy below the player by `insertSubtitleViewBelowPlayer`.
    public lazy var subtitleView: UIView = .init()

    // RE field #7 (0x1041F79B8) `player`: corrected in 1.3.15 to `MediaPlayerProtocol` (the protocol),
    // NOT `any PlayerProtocol` (a stale older-dump type). Swapped by `swapPlayerAndOpenURL` /
    // `replacePlayerWithNewURL` / `replacePlayerFromMEPlayerItem`.
    public var player: MediaPlayerProtocol {
        didSet {
            KSLog("player is \(player)")
            state = .initialized
            runOnMainThread { [weak self] in
                guard let self else { return }
                if let oldView = oldValue.view, let superview = oldView.superview, let view = player.view {
                    #if canImport(UIKit)
                    superview.insertSubview(view, belowSubview: oldView)
                    #else
                    superview.addSubview(view, positioned: .below, relativeTo: oldView)
                    #endif
                    view.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        view.topAnchor.constraint(equalTo: superview.topAnchor),
                        view.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                        view.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                        view.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                    ])
                }
                oldValue.view?.removeFromSuperview()
            }
            player.playbackRate = oldValue.playbackRate
            player.playbackVolume = oldValue.playbackVolume
            player.delegate = self
            player.contentMode = .scaleAspectFit
            if isAutoPlay {
                prepareToPlay()
            }
        }
    }

    // RE field #8 (0x1041F79C0) `url`. Backed by `_url`: most writers go through the
    // computed `url` setter below, which runs the 3-way player-selection branch (the
    // binary's `url` property observer). `replacePlayerFromMEPlayerItem` (0x1013b07c4)
    // instead stores the field raw (value-witness copy, no observer) because it hands
    // the already-built item to the engine itself; it writes `_url` directly. `init`
    // likewise seeds `_url` directly (the observer cannot run before `super.init`).
    private var _url: URL
    public private(set) var url: URL {
        get { _url }
        set {
            // Manual oldValue capture (computed setter has no implicit `oldValue`).
            let oldValue = _url
            _url = newValue
            let firstPlayerType: MediaPlayerProtocol.Type
            if isWirelessRouteActive {
                // airplay的话，默认使用KSAVPlayer
                firstPlayerType = KSAVPlayer.self
            } else if options.display != .plane {
                // AR模式只能用KSMEPlayer
                // swiftlint:disable force_cast
                firstPlayerType = NSClassFromString("KSPlayer.KSMEPlayer") as! MediaPlayerProtocol.Type
                // swiftlint:enable force_cast
            } else {
                firstPlayerType = KSOptions.firstPlayerType
            }
            // RE: setURLAndConfigurePlayer (interior 0x10129D104 inside FUN_10129d8e0) — 3-way branch.
            if isMatchingPlayerClass(firstPlayerType) {
                if url == oldValue {
                    // Branch 1: same URL + same player type — just auto-play, no teardown.
                    if isAutoPlay {
                        play()
                    }
                } else {
                    // Branch 2: different URL + same player type — reuse player, swap URL.
                    stop()
                    replacePlayerWithNewURL(url: url, options: options)
                    if isAutoPlay {
                        prepareToPlay()
                    }
                }
            } else {
                // Branch 3: different player type — full swap.
                stop()
                swapPlayerAndOpenURL(firstPlayerType.init(url: url, options: options))
            }
        }
    }

    /// 播发器的几种状态
    // RE field #9 (0x103B3D9B8) `_state`: @Published KSPlayerState. The state transition is driven
    // through `playerStateDidChange_bridge` (which resets `shouldSeekTo`) and notifies the delegate.
    public private(set) var state = KSPlayerState.initialized {
        willSet {
            if state != newValue {
                playerStateDidChange(to: newValue)
            }
        }
    }

    // RE field #10 (0x1041F79D8) `playerTickClock` + field #11 (0x1041F79E0) `playerTickTask`.
    // The 1.3.14 source drove periodic UI updates from a `Timer`; the 1.3.15 Forward layout replaced
    // it with a `ContinuousClock` + a long-lived `Task` tick loop (`playerTickTask`). The tick loop
    // fires at the 0.1s interval, reports currentTime/duration to the delegate, advances
    // buffering→bufferFinished, and pushes the elapsed time into the now-playing center.
    //
    // DEPLOYMENT-TARGET NOTE: the binary stores a `ContinuousClock` (field #10), but that type — and
    // `Clock.sleep(for:)` / `Duration` — are iOS 16 / macOS 13 / tvOS 16 only, while this package's
    // floor is iOS 13 / macOS 10.15 / tvOS 13 (Package.swift). A non-optional `ContinuousClock`
    // therefore cannot be a stored property here. The clock field is preserved behind an
    // availability-gated accessor (`playerTickClock`) and the loop cadence is driven by
    // `Task.sleep(nanoseconds:)` (iOS 13+), which preserves the 0.1s tick behaviour on every target.
    private var playerTickTask: Task<(), Never>?
    private static let tickIntervalNanoseconds: UInt64 = 100_000_000 // 0.1s

    /// RE field #10 `playerTickClock`. Availability-gated to match the deployment floor (see note on
    /// `playerTickTask`); callers below schedule via `Task.sleep(nanoseconds:)` so the field is not
    /// required at runtime on pre-iOS-16 targets.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
    private var playerTickClock: ContinuousClock { ContinuousClock() }

    private var subtitleTimeObserver: Any?
    private var urls = [URL]()
    // RE field #12 (0x1041F79E8) `isAutoPlay`.
    private var isAutoPlay: Bool
    // RE field #13 (0x103B3D9C8) `isWirelessRouteActive` (updated by wirelessRouteActiveDidChange_handler).
    private var isWirelessRouteActive = false
    // RE field #14 (0x103B3D9D0) `_bufferedCount`: @Published Int (was a plain Int in 1.3.14).
    @Published
    public private(set) var bufferedCount = 0
    // RE field #15 (0x103B3D9D8) `shouldSeekTo`: Double (TimeInterval is a Double typealias). Reset to
    // 0 on every state transition by `playerStateDidChange_bridge`.
    private var shouldSeekTo: TimeInterval = 0
    // RE field #16 (0x103B3D9E0) `bufferingStartTime`: timestamp buffering began (Forward rename of the
    // upstream `startTime`).
    private var bufferingStartTime: TimeInterval = 0
    // RE field #17 (0x1041F79C8) `subtitleModel`: the subtitle selection / render model. Synced from
    // the layer's url/options by `resetPlayerUI`; user selection applied by `setSelectedSubtitleInfo`.
    public let subtitleModel = SubtitleModel()
    // RE field #18 (0x1041F79D0) `isAutoReplaceAndConstrainPlayerView`: when set, a player swap
    // auto-replaces the rendered view and re-pins its constraints in the hierarchy.
    public var isAutoReplaceAndConstrainPlayerView = true

    // RE: designated init body FUN_1013ba56c (0x1013ba56c). Sets delegate, conditionally registers the
    // remote command handlers (gated on `options.registerRemoteControll`), then factors notification
    // observer registration into `initNotificationObservers`.
    public init(url: URL, isAutoPlay: Bool = KSOptions.isAutoPlay, options: KSOptions, delegate: KSPlayerLayerDelegate? = nil) {
        // Seed the backing field directly: the computed `url` setter runs the
        // player-selection branch and cannot execute before `super.init()` / before
        // `player` is set. The designated-init player wiring happens explicitly below.
        _url = url
        self.options = options
        self.delegate = delegate
        let firstPlayerType: MediaPlayerProtocol.Type
        if options.display != .plane {
            // AR模式只能用KSMEPlayer
            // swiftlint:disable force_cast
            firstPlayerType = NSClassFromString("KSPlayer.KSMEPlayer") as! MediaPlayerProtocol.Type
            // swiftlint:enable force_cast
        } else {
            firstPlayerType = KSOptions.firstPlayerType
        }
        player = firstPlayerType.init(url: url, options: options)
        self.isAutoPlay = isAutoPlay
        super.init()
        player.playbackRate = options.startPlayRate
        if options.registerRemoteControll {
            registerRemoteCommandHandlers()
        }
        player.delegate = self
        player.contentMode = .scaleAspectFit
        // Keep the subtitle model in sync with the initial url/options.
        subtitleModel.url = url
        if isAutoPlay {
            prepareToPlay()
        }
        initNotificationObservers()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            player.pipController?.contentSource = nil
        }
        playerTickTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterAllRemoteCommandTargets()
        options.playerLayerDeinit()
    }

    public func set(url: URL, options: KSOptions) {
        self.options = options
        runOnMainThread {
            self.url = url
        }
    }

    public func set(urls: [URL], options: KSOptions) {
        self.options = options
        self.urls.removeAll()
        self.urls.append(contentsOf: urls)
        if let first = urls.first {
            runOnMainThread {
                self.url = first
            }
        }
    }

    open func play() {
        runOnMainThread {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        isAutoPlay = true
        if state == .error || state == .initialized {
            prepareToPlay()
        }
        if player.isReadyToPlay {
            if state == .playedToTheEnd {
                player.seek(time: 0) { [weak self] finished in
                    guard let self else { return }
                    if finished {
                        self.player.play()
                    }
                }
            } else {
                player.play()
            }
            startPlayerTick()
            addSubtitleTimeObserver()
        }
        state = player.loadState == .playable ? .bufferFinished : .buffering
        MPNowPlayingInfoCenter.default().playbackState = .playing
        if #available(tvOS 14.0, *) {
            KSPictureInPictureController.mute()
        }
    }

    /// RE: 0x1013b1b2c `play_withSeekAndCompletion` (0x394/916B). Play with an optional seek: when the
    /// player is ready, seekable, and the requested target is at least 1.0s away from the current
    /// position, it clears the active subtitle parts (so stale cues do not flash during the jump) and
    /// seeks with the completion handler. When the player is not yet ready it stashes the seek target
    /// (`shouldSeekTo`) and the auto-play intent, then fires completion(false).
    ///
    /// RE: the verified decompile clears `SubtitleModel.parts` (Combine `_parts` key-path write,
    /// `parts = []`) before seeking, so stale cues do not flash during the jump. `SubtitleModel.parts`
    /// is `private(set)`; the in-class write is exposed via `SubtitleModel.clearParts()`.
    open func play(time: TimeInterval, autoPlay: Bool, completion: ((Bool) -> Void)? = nil) {
        guard time.isFinite else {
            completion?(false)
            return
        }
        if player.isReadyToPlay, player.seekable {
            if abs(time - player.currentPlaybackTime) >= 1.0 {
                // RE: clear subtitles before the seek (subtitleModel.parts = [], `_parts` Published
                // write) so stale cues do not flash during the jump.
                subtitleModel.clearParts()
                player.seek(time: time) { [weak self] finished in
                    guard let self else { return }
                    if autoPlay {
                        self.play()
                    }
                    completion?(finished)
                }
            } else {
                if autoPlay {
                    player.play()
                }
                completion?(true)
            }
        } else {
            isAutoPlay = autoPlay
            shouldSeekTo = time
            completion?(false)
        }
    }

    open func pause() {
        isAutoPlay = false
        player.pause()
        stopPlayerTick()
        removeSubtitleTimeObserver()
        state = .paused
        MPNowPlayingInfoCenter.default().playbackState = .paused
        runOnMainThread {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    public func stop() {
        KSLog("stop Player")
        state = .initialized
        removeSubtitleTimeObserver()
        player.shutdown()
        bufferedCount = 0
        shouldSeekTo = 0
        player.playbackRate = 1
        player.playbackVolume = 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        runOnMainThread {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// RE: 0x1013b1044 `resumePlayback` (0x2E8/744B). Resume strategy used after a PiP dismiss. Forces
    /// auto-play on, and — unless the player is already in a terminal/initial state for which a fresh
    /// prepare is required — re-prepares. When the player is ready it either re-seeks to 0 (if it had
    /// played to the end, via `resumePlayback_seekCompletion`) or simply resumes.
    open func resumePlayback() {
        isAutoPlay = true
        // Re-prepare unless we can resume in place: i.e. unless the state is non-terminal and either
        // we are at the end with a ready player (rewind path) or otherwise ready to resume.
        let canResumeInPlace = state != .error && state != .initialized
            && (state == .playedToTheEnd ? player.isReadyToPlay : true)
        if !canResumeInPlace {
            prepareToPlay()
        }
        if player.isReadyToPlay {
            if state == .playedToTheEnd {
                player.seek(time: 0) { [weak self] finished in
                    self?.resumePlayback(seekCompletion: finished)
                }
            } else {
                player.play()
            }
        }
    }

    /// RE: 0x1013b132c `resumePlayback_seekCompletion`. Seek-completion callback paired with
    /// `resumePlayback`: once the rewind to 0 finishes, resume playback.
    private func resumePlayback(seekCompletion finished: Bool) {
        if finished {
            player.play()
        }
    }

    open func seek(time: TimeInterval, autoPlay: Bool, completion: @escaping ((Bool) -> Void)) {
        if time.isInfinite || time.isNaN {
            completion(false)
        }
        if player.isReadyToPlay, player.seekable {
            player.seek(time: time) { [weak self] finished in
                guard let self else { return }
                if finished, autoPlay {
                    self.play()
                }
                completion(finished)
            }
        } else {
            isAutoPlay = autoPlay
            shouldSeekTo = time
            completion(false)
        }
    }

    private func addSubtitleTimeObserver() {
        guard subtitleTimeObserver == nil, let synchronizer = player.renderSynchronizer else {
            return
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        subtitleTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.player.isReadyToPlay else {
                return
            }
            self.delegate?.player(layer: self, currentTime: time.seconds, totalTime: self.player.duration)
        }
    }

    private func removeSubtitleTimeObserver() {
        guard let observer = subtitleTimeObserver, let synchronizer = player.renderSynchronizer else {
            return
        }
        synchronizer.removeTimeObserver(observer)
        subtitleTimeObserver = nil
    }
}

// MARK: - MediaPlayerDelegate

extension KSPlayerLayer: MediaPlayerDelegate {
    /// Hook for subclasses to perform setup when the player becomes ready.
    /// Called from `readyToPlay(player:)` after state is set.
    /// RE: KSComplexPlayerLayer overrides this to set up PiP and subtitle delegates.
    open func onPlayerReady() {}

    public func readyToPlay(player: some MediaPlayerProtocol) {
        state = .readyToPlay
        if options.firstPlayableTime == 0 {
            options.firstPlayableTime = CACurrentMediaTime()
            // RE: Build playback timing metrics on first readyToPlay transition.
            // (KSOptions.buildPlaybackTimingMetrics @ 0x1013a71e0 — defined in KSOptions, cluster 7.)
            let metrics = options.buildPlaybackTimingMetrics()
            KSLog("[timing] First playback timing metrics: \(metrics)")
        }
        onPlayerReady()
        #if os(macOS)
        runOnMainThread { [weak self] in
            guard let self else { return }
            if let window = player.view?.window {
                window.isMovableByWindowBackground = true
                if options.automaticWindowResize {
                    let naturalSize = player.naturalSize
                    if naturalSize.width > 0, naturalSize.height > 0 {
                        window.aspectRatio = naturalSize
                        var frame = window.frame
                        frame.size.height = frame.width * naturalSize.height / naturalSize.width
                        window.setFrame(frame, display: true)
                    }
                }
            }
        }
        #endif
        #if !os(macOS) && !os(tvOS)
        if #available(iOS 14.2, *) {
            if options.canStartPictureInPictureAutomaticallyFromInline {
                player.pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        }
        #endif
        updateNowPlayingInfo()
        notifyDelegatePlayerReady()
        if isAutoPlay {
            if shouldSeekTo > 0 {
                seek(time: shouldSeekTo, autoPlay: true) { [weak self] _ in
                    guard let self else { return }
                    self.shouldSeekTo = 0
                }

            } else {
                play()
            }
        }
    }

    public func changeLoadState(player: some MediaPlayerProtocol) {
        guard player.playbackState != .seeking else { return }
        if player.loadState == .playable, bufferingStartTime > 0 {
            let diff = CACurrentMediaTime() - bufferingStartTime
            runOnMainThread { [weak self] in
                guard let self else { return }
                delegate?.player(layer: self, bufferedCount: bufferedCount, consumeTime: diff)
            }
            if bufferedCount == 0 {
                var dic = ["firstTime": diff]
                if options.tcpConnectedTime > 0 {
                    dic["initTime"] = options.dnsStartTime - bufferingStartTime
                    dic["dnsTime"] = options.tcpStartTime - options.dnsStartTime
                    dic["tcpTime"] = options.tcpConnectedTime - options.tcpStartTime
                    dic["openTime"] = options.openTime - options.tcpConnectedTime
                    dic["findTime"] = options.findTime - options.openTime
                } else {
                    dic["openTime"] = options.openTime - bufferingStartTime
                }
                dic["findTime"] = options.findTime - options.openTime
                dic["readyTime"] = options.readyTime - options.findTime
                dic["readVideoTime"] = options.readVideoTime - options.readyTime
                dic["readAudioTime"] = options.readAudioTime - options.readyTime
                dic["decodeVideoTime"] = options.decodeVideoTime - options.readVideoTime
                dic["decodeAudioTime"] = options.decodeAudioTime - options.readAudioTime
                KSLog(dic)
            }
            bufferedCount += 1
            bufferingStartTime = 0
        }
        guard state.isPlaying else { return }
        if player.loadState == .playable {
            state = .bufferFinished
        } else {
            if state == .bufferFinished {
                bufferingStartTime = CACurrentMediaTime()
            }
            state = .buffering
        }
    }

    public func changeBuffering(player _: some MediaPlayerProtocol, progress: Int) {
        bufferingProgress = UInt8(min(max(progress, 0), 100))
    }

    public func playBack(player _: some MediaPlayerProtocol, loopCount: Int) {
        self.loopCount = loopCount
    }

    public func finish(player: some MediaPlayerProtocol, error: Error?) {
        if let error {
            if type(of: player) != KSOptions.secondPlayerType, let secondPlayerType = KSOptions.secondPlayerType {
                self.player = secondPlayerType.init(url: url, options: options)
                return
            }
            state = .error
            KSLog(error as CustomStringConvertible)
        } else {
            let duration = player.duration
            runOnMainThread { [weak self] in
                guard let self else { return }
                delegate?.player(layer: self, currentTime: duration, totalTime: duration)
            }
            state = .playedToTheEnd
        }
        stopPlayerTick()
        bufferedCount = 1
        finishWithError(error)
        if error == nil {
            playNextURLInPlaylist()
        }
    }

    /// RE: 0x1013b3510 `finish_player_error_asyncEntry`. Async entry that hops the finish-with-error
    /// delegate notification onto the main actor. The synchronous body above performs the state
    /// transition; this routes only the delegate callback (mirrors the binary, which factored the
    /// delegate hop into its own async frame).
    private func finishWithError(_ error: Error?) {
        runOnMainThread { [weak self] in
            guard let self else { return }
            delegate?.player(layer: self, finish: error)
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(tvOS 14.0, *)
extension KSPlayerLayer: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        player.pipController?.stop(restoreUserInterface: false)
    }

    public func pictureInPictureController(_: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler _: @escaping (Bool) -> Void) {
        isPipActive = false
    }
}

// MARK: - KSPipSubtitleDelegate

@available(tvOS 14.0, *)
extension KSPlayerLayer: KSPipSubtitleDelegate {
    public func pipSubtitleImage(at time: TimeInterval) -> UIImage? {
        (pipSubtitleProvider as? KSPipSubtitleDelegate)?.pipSubtitleImage(at: time)
    }

    public func pipSubtitleAttributedText(at time: TimeInterval) -> NSAttributedString? {
        (pipSubtitleProvider as? KSPipSubtitleDelegate)?.pipSubtitleAttributedText(at: time)
    }
}

// MARK: - private functions

extension KSPlayerLayer {
    open func prepareToPlay() {
        state = .preparing
        bufferingStartTime = CACurrentMediaTime()
        bufferedCount = 0
        player.prepareToPlay()
    }

    private func updateNowPlayingInfo() {
        if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyPlaybackDuration: player.duration]
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = player.duration
        }
        if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] == nil, let title = player.dynamicInfo?.metadata["title"] {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] = title
        }
        if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] == nil, let artist = player.dynamicInfo?.metadata["artist"] {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] = artist
        }
        var current: [MPNowPlayingInfoLanguageOption] = []
        var langs: [MPNowPlayingInfoLanguageOptionGroup] = []
        for track in player.tracks(mediaType: .audio) {
            if let lang = track.language {
                let audioLang = MPNowPlayingInfoLanguageOption(type: .audible, languageTag: lang, characteristics: nil, displayName: track.name, identifier: track.name)
                let audioGroup = MPNowPlayingInfoLanguageOptionGroup(languageOptions: [audioLang], defaultLanguageOption: nil, allowEmptySelection: false)
                langs.append(audioGroup)
                if track.isEnabled {
                    current.append(audioLang)
                }
            }
        }
        if !langs.isEmpty {
            MPRemoteCommandCenter.shared().enableLanguageOptionCommand.isEnabled = true
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyAvailableLanguageOptions] = langs
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentLanguageOptions] = current
    }

    /// RE: 0x1013b77fc `playNextURLInPlaylist`. Advance to the next URL in the playlist. (1.3.14 named
    /// this `nextPlayer`.) `previousPlayer` is the upstream-only mirror, retained below.
    private func playNextURLInPlaylist() {
        if urls.count > 1, let index = urls.firstIndex(of: url), index < urls.count - 1 {
            isAutoPlay = true
            url = urls[index + 1]
        }
    }

    /// RE: 0x1013b86f0 `shuffleAndPlayNextURL`. Shuffle the playlist and play the next URL. Picks a
    /// random URL other than the current one; falls back to sequential advance when the playlist is
    /// too small to shuffle.
    public func shuffleAndPlayNextURL() {
        guard urls.count > 1 else {
            playNextURLInPlaylist()
            return
        }
        let candidates = urls.filter { $0 != url }
        if let next = candidates.randomElement() {
            isAutoPlay = true
            url = next
        }
    }

    private func previousPlayer() {
        if urls.count > 1, let index = urls.firstIndex(of: url), index > 0 {
            isAutoPlay = true
            url = urls[index - 1]
        }
    }

    func seek(time: TimeInterval) {
        seek(time: time, autoPlay: options.isSeekedAutoPlay) { _ in
        }
    }

    // MARK: - Player swap / replace

    /// RE: 0x1013ba470 `swapPlayerAndOpenURL`. Exclusive-access swap of the `player` ivar: stores the
    /// new player, releases the old one. Routed through the `player` didSet (which re-pins the rendered
    /// view and re-applies rate/volume/delegate) so the swap also reconstrains the view hierarchy when
    /// `isAutoReplaceAndConstrainPlayerView` is set.
    private func swapPlayerAndOpenURL(_ newPlayer: MediaPlayerProtocol) {
        player = newPlayer
    }

    /// RE: 0x1013c3bac `replacePlayerWithNewURL`. Branch 2 of the player-type selection: keep the same
    /// player instance and player type, swap only the URL via `player.replace(url:options:)`.
    private func replacePlayerWithNewURL(url: URL, options: KSOptions) {
        player.replace(url: url, options: options)
    }

    /// RE: 0x1013b07c4 `replacePlayerFromMEPlayerItem` (0x304/772B). Branch 3 of player-type selection:
    /// replace the inner player from an already-constructed `MEPlayerItem`. Per the verified decompile
    /// it copies the item's `options` into the layer, swaps the layer URL to the item's source URL
    /// (`MEPlayerItem.io.url`), resets the UI (`resetPlayerUI`), re-publishes `state = .initialized`,
    /// then hands the item to the engine (`KSMEPlayer.replace(playerItem:)`, FUN_10141d328 — which in
    /// turn runs `KSMEPlayer.reset()`). Carries ZERO `enhanceDolby`/`DAT_104450978` references — the
    /// DV/player-type routing decision is owned by `PlayerCenter` (see PlayerCore.md §enhanceDolby);
    /// this method only swaps in the chosen player after that decision is made.
    ///
    /// Cross-file decls this depends on (all reinstated): `MEPlayerItem.options` and the source URL
    /// (`MEPlayerItem.url`; the binary's `io.url` is the demuxer-I/O source URL) are now module-internal
    /// reads, and `KSMEPlayer.replace(playerItem:)` performs the engine hand-off.
    func replacePlayerFromMEPlayerItem(_ playerItem: MEPlayerItem) {
        // The current player must be an MEPlayer-family engine for the item swap to apply
        // (binary: `player as? KSMEPlayer` cast gate — the whole body is skipped when nil).
        guard let mePlayer = player as? KSMEPlayer else { return }
        // RE: self.options = playerItem.options (verified decompile; retain/release of the KSOptions
        // reference). `options` has no observer, so the direct property write is faithful.
        options = playerItem.options
        // RE: self.url = playerItem.io.url — the item's source URL. Written to the backing field
        // directly (binary does a raw value-witness field store, NOT the property observer): the
        // engine hand-off below performs the player swap, so the `url` setter's 3-way selection branch
        // must NOT run here.
        _url = playerItem.url
        // RE: resetPlayerUI() — push url/options into the subtitle model + reload sources.
        resetPlayerUI()
        // RE: state = .initialized (FUN_1013aebc0(0) observer log/notify + the `_state` Published
        // write). Re-publish so observers see the freshly-swapped item.
        state = .initialized
        // RE: hand the constructed item to the engine (FUN_10141d328 → KSMEPlayer.replace(playerItem:),
        // which calls KSMEPlayer.reset() and re-points the audio/video outputs + delegate at the item).
        mePlayer.replace(playerItem: playerItem)
    }

    /// RE: 0x1013ae954 `resetPlayerUI` (0x150/336B). Reset the UI-side state to defaults after a
    /// player/item swap: pushes the layer's current `url` into the subtitle model (whose `url` didSet
    /// reloads the subtitle data sources for that URL — matching the binary's
    /// `SubtitleModel_resetAndReloadSubtitleSources` call), then copies the layer's `options` into the
    /// subtitle model so HDR/positioning preferences track the new media.
    func resetPlayerUI() {
        // RE: assigning `url` triggers SubtitleModel.url.didSet → reload of subtitle data sources.
        subtitleModel.url = url
        // RE: self.options copied into subtitleModel.options (verified decompile tail; retain/release
        // of the KSOptions reference). SubtitleModel.options is `KSOptions?` (KSSubtitle.swift:588).
        subtitleModel.options = options
    }

    // MARK: - Class predicates

    /// RE: 0x1013b7550 `isMatchingPlayerClass`. MainActor-isolated check: does the current `player`'s
    /// ObjC class match the requested player class? Used by `setURLAndConfigurePlayer` to pick between
    /// the reuse and full-swap branches.
    private func isMatchingPlayerClass(_ playerClass: MediaPlayerProtocol.Type) -> Bool {
        type(of: player) == playerClass
    }

    /// RE: 0x1013ab274 `buildRegisteredClassNameSet` (verified decompile). Iterates the registered
    /// player classes and builds a `Set<String>` of their class names via `NSStringFromClass`. Feeds
    /// the player-class matching path. Reconstructed per the no-skip rule.
    private func buildRegisteredClassNameSet() -> Set<String> {
        var names = Set<String>()
        for playerType in KSPlayerLayer.registeredPlayerClasses {
            if let cls = playerType as? AnyClass {
                names.insert(NSStringFromClass(cls))
            }
        }
        return names
    }

    /// The set of player classes the layer may instantiate, in selection order. Mirrors the binary's
    /// registered-class array consulted by `buildRegisteredClassNameSet`.
    private static var registeredPlayerClasses: [MediaPlayerProtocol.Type] {
        var classes: [MediaPlayerProtocol.Type] = [KSOptions.firstPlayerType]
        if let second = KSOptions.secondPlayerType {
            classes.append(second)
        }
        return classes
    }

    /// RE: 0x1013b5050 `getPlayer_ivar`. Vtable-dispatch getter for the `player` ivar (the binary
    /// tail-jumps through `isa+0x308`). In Swift the stored property already synthesizes a getter; this
    /// discrete accessor is preserved (no-skip rule) for callers that went through the vtable slot.
    func getPlayer_ivar() -> MediaPlayerProtocol {
        player
    }

    // MARK: - Player tick loop (RE fields #10/#11: ContinuousClock + Task)

    /// Start the periodic UI tick. Replaces the 1.3.14 `Timer` with a `ContinuousClock`-driven `Task`
    /// (`playerTickTask`): every 0.1s it reports currentTime/duration to the delegate (unless the
    /// sample-buffer time observer is active), advances buffering→bufferFinished, and pushes the
    /// elapsed time into `MPNowPlayingInfoCenter`.
    private func startPlayerTick() {
        guard playerTickTask == nil else { return }
        playerTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // RE: ContinuousClock.sleep(for: .milliseconds(100)); driven via Task.sleep on the
                // iOS-13 floor (see deployment-target note on the tick fields).
                try? await Task.sleep(nanoseconds: KSPlayerLayer.tickIntervalNanoseconds)
                if Task.isCancelled { break }
                guard let self else { break }
                self.playerTick()
            }
        }
    }

    private func stopPlayerTick() {
        playerTickTask?.cancel()
        playerTickTask = nil
    }

    private func playerTick() {
        guard player.isReadyToPlay else { return }
        if subtitleTimeObserver == nil {
            delegate?.player(layer: self, currentTime: player.currentPlaybackTime, totalTime: player.duration)
        }
        if player.playbackState == .playing, player.loadState == .playable, state == .buffering {
            state = .bufferFinished
        }
        if player.isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentPlaybackTime
        }
    }

    // MARK: - State transition bridge

    /// RE: 0x1013b30ac `playerStateDidChange_bridge` (weak-self) + 0x1013b3100
    /// `playerStateDidChange_callback`. On every state transition the bridge resets the pending seek
    /// target (`shouldSeekTo = 0`) and hops the delegate notification onto the main thread. The 1.3.14
    /// source notified the delegate from `state.willSet` but never cleared `shouldSeekTo`.
    private func playerStateDidChange(to newValue: KSPlayerState) {
        shouldSeekTo = 0
        runOnMainThread { [weak self] in
            guard let self else { return }
            KSLog("playerStateDidChange - \(newValue)")
            self.playerStateDidChangeCallback(newValue)
        }
    }

    /// RE: 0x1013b3100 — the state-change callback body paired with the bridge above.
    private func playerStateDidChangeCallback(_ newValue: KSPlayerState) {
        delegate?.player(layer: self, state: newValue)
    }

    /// RE: 0x1013afe70 `notifyDelegatePlayerReady`. MainActor-isolated: weak-loads the delegate and
    /// notifies it that the player reached `.readyToPlay`.
    private func notifyDelegatePlayerReady() {
        delegate?.player(layer: self, state: .readyToPlay)
    }

    /// RE: 0x1013b0cec `handlePlaybackStateUpdate` (0x358/856B). Per-tick playback-state update:
    /// (1) syncs the video `dynamicRange` from options into the subtitle model and repositions the
    /// subtitle container against the player view frame, (2) notifies the delegate of
    /// currentTime/totalTime, and (3) auto-advances buffering(3)→bufferFinished(4) when the load state
    /// reports playable.
    ///
    private func handlePlaybackStateUpdate(currentTime: TimeInterval, totalTime: TimeInterval) {
        if player.isReadyToPlay {
            // (1a) Sync the video dynamic range from options into the subtitle model so HDR-aware
            // subtitle rendering tracks the current media. RE: single-byte copy
            // `KSOptions::dynamicRange` → `SubtitleModel::dynamicRange` (both non-optional
            // `DynamicRange`; KSOptions.swift:68, KSSubtitle.swift:584).
            subtitleModel.dynamicRange = options.dynamicRange
            // (1b) Keep the subtitle container aligned with the current player-view geometry.
            subtitleView.frame = player.view?.frame ?? subtitleView.frame
        }
        // (2) Delegate notification.
        delegate?.player(layer: self, currentTime: currentTime, totalTime: totalTime)
        // (3) State auto-advance.
        if state == .buffering, player.loadState == .playable {
            state = .bufferFinished
        }
    }

    /// RE: 0x1013b2ec8 `dispatchResumePlayOnMainActor` (weak-self). Hops `resumePlayback` onto the main
    /// actor, taking the direct path when already on the main thread (`NSThread.isMainThread`,
    /// Utility.swift:22) and dispatching otherwise.
    private func dispatchResumePlayOnMainActor() {
        runOnMainThread { [weak self] in
            self?.resumePlayback()
        }
    }

    // MARK: - Subtitle integration

    /// RE: 0x1013b38c0 `setSelectedSubtitleInfo`. Apply a user subtitle selection. When the selection
    /// is enabled and `options.isSeekImageSubtitle` is set, also routes the selection into the player's
    /// image-subtitle track path. Compares against the model's current (primary or secondary)
    /// selection by `subtitleID` to avoid redundant reselection, then stores the new selection on the
    /// `SubtitleModel` (primary → `selectedSubtitleInfo`, secondary → `selectedSecondSubtitleInfo`).
    public func setSelectedSubtitleInfo(_ info: (any SubtitleInfo)?, isSecondary: Bool = false) {
        if let info {
            if info.isEnabled, options.isSeekImageSubtitle, let track = info as? (any MediaPlayerTrack) {
                player.select(track: track)
            }
        }
        if isSecondary {
            if subtitleModel.selectedSecondSubtitleInfo?.subtitleID != info?.subtitleID {
                subtitleModel.selectSecondSubtitle(info)
            }
        } else {
            if subtitleModel.selectedSubtitleInfo?.subtitleID != info?.subtitleID {
                subtitleModel.selectedSubtitleInfo = info
            }
        }
    }

    /// RE: 0x1013b4a24 `insertSubtitleViewBelowPlayer`. Inject `subtitleView` into the view hierarchy
    /// directly below the player's render view, match its frame, and pin it edge-to-edge. When the
    /// player view is not auto-layout-managed the binary falls back to an autoresizing mask
    /// (flexible width+height, raw `0x12`) instead of activating constraints.
    func insertSubtitleViewBelowPlayer() {
        #if canImport(UIKit)
        guard let playerView = player.view, let superview = playerView.superview else { return }
        superview.insertSubview(subtitleView, belowSubview: playerView)
        subtitleView.frame = playerView.frame
        if playerView.translatesAutoresizingMaskIntoConstraints {
            // Fallback path (binary 0x12 == flexibleWidth | flexibleHeight).
            subtitleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        } else {
            subtitleView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                subtitleView.topAnchor.constraint(equalTo: superview.topAnchor),
                subtitleView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                subtitleView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                subtitleView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            ])
        }
        #else
        guard let playerView = player.view, let superview = playerView.superview else { return }
        superview.addSubview(subtitleView, positioned: .below, relativeTo: playerView)
        subtitleView.frame = playerView.frame
        subtitleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subtitleView.topAnchor.constraint(equalTo: superview.topAnchor),
            subtitleView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            subtitleView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            subtitleView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
        ])
        #endif
    }

    // MARK: - Picture in Picture

    /// RE: 0x1013b79dc `stopPictureInPicture` (0x88/136B). Stop PiP and clean up: stop the engine PiP
    /// controller with `restoreUserInterface: true`. The binary additionally writes the
    /// `KSComplexPlayerLayer.isPictureInPictureStoped = false` flag FIRST — but that field lives on the
    /// subclass, so the flag write is performed by `KSComplexPlayerLayer.stopPictureInPicture()`
    /// (override), which sets the flag and then calls `super` for this controller teardown. (In the
    /// binary the single method resolves the field into the subclass storage because `self` is always a
    /// `KSComplexPlayerLayer` at the relevant call sites.)
    open func stopPictureInPicture() {
        if #available(tvOS 14.0, *) {
            player.pipController?.stop(restoreUserInterface: true)
        }
    }

    // MARK: - Notification observers

    /// RE: 0x1013b50dc `initNotificationObservers`. Register the NSNotificationCenter observers the
    /// layer relies on: app background/foreground (UIKit), AirPlay wireless-route change (non-xrOS),
    /// and audio-session interruption (non-macOS). Factored out of `init` per the Forward layout.
    private func initNotificationObservers() {
        #if canImport(UIKit)
        runOnMainThread { [weak self] in
            guard let self else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        #if !os(xrOS)
        NotificationCenter.default.addObserver(self, selector: #selector(wirelessRouteActiveDidChange(notification:)), name: .MPVolumeViewWirelessRouteActiveDidChange, object: nil)
        #endif
        #endif
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        #endif
    }

    /// RE: 0x1013b7624 `teardown_stopAndRemoveObservers` (verified decompile; carries an RE plate
    /// comment in the binary citing `39_ksplayerlayer_state_machine.md`). Callable teardown: stops the
    /// tick loop, shuts the player down (vtable+0xf8), finalizes the PiP delegate / clears its content
    /// source, removes the NSNotificationCenter + MPNowPlayingInfoCenter observers, and unregisters all
    /// remote-command targets. (1.3.14 performed this only in `deinit`.)
    public func teardown_stopAndRemoveObservers() {
        stopPlayerTick()
        player.shutdown()
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            player.pipController?.contentSource = nil
        }
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterAllRemoteCommandTargets()
    }

    /// RE: 0x1013b77f8 `unregisterAllRemoteCommandTargets` (paired thunk 0x1013bb1b4). Removes every
    /// MPRemoteCommandCenter target the layer registered. Factored out of `deinit`.
    private func unregisterAllRemoteCommandTargets() {
        let remoteCommand = MPRemoteCommandCenter.shared()
        remoteCommand.playCommand.removeTarget(nil)
        remoteCommand.pauseCommand.removeTarget(nil)
        remoteCommand.togglePlayPauseCommand.removeTarget(nil)
        remoteCommand.stopCommand.removeTarget(nil)
        remoteCommand.nextTrackCommand.removeTarget(nil)
        remoteCommand.previousTrackCommand.removeTarget(nil)
        remoteCommand.changeRepeatModeCommand.removeTarget(nil)
        remoteCommand.changePlaybackRateCommand.removeTarget(nil)
        remoteCommand.skipForwardCommand.removeTarget(nil)
        remoteCommand.skipBackwardCommand.removeTarget(nil)
        remoteCommand.changePlaybackPositionCommand.removeTarget(nil)
        remoteCommand.enableLanguageOptionCommand.removeTarget(nil)
    }

    @objc private func enterBackground() {
        guard state.isPlaying, !player.isExternalPlaybackActive else {
            return
        }
        if #available(tvOS 14.0, *), player.pipController?.isPictureInPictureActive == true {
            return
        }

        if KSOptions.canBackgroundPlay {
            player.enterBackground()
            return
        }
        pause()
    }

    @objc private func enterForeground() {
        if KSOptions.canBackgroundPlay {
            player.enterForeground()
        }
    }

    #if canImport(UIKit) && !os(xrOS)
    /// RE: 0x1013b3d00 `wirelessRouteActiveDidChange_handler` (verified decompile). On an AirPlay
    /// route change: cast the notification object to `MPVolumeView`, and if the active state actually
    /// changed, when the route became active force the player to use external playback (and, when the
    /// player does not natively allow external playback, latch `isWirelessRouteActive`). Finally mirror
    /// the volume view's `isWirelessRouteActive` into the ivar.
    @MainActor
    @objc private func wirelessRouteActiveDidChange(notification: Notification) {
        guard let volumeView = notification.object as? MPVolumeView, isWirelessRouteActive != volumeView.isWirelessRouteActive else { return }
        if volumeView.isWirelessRouteActive {
            if !player.allowsExternalPlayback {
                isWirelessRouteActive = true
            }
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
        }
        isWirelessRouteActive = volumeView.isWirelessRouteActive
    }
    #endif
    #if !os(macOS)
    /// RE: 0x1013b446c `audioInterruptedCompletionBlock` + 0x1013b4834 `audioInterruptedMainActorThunk`.
    /// On interruption begin → pause. On interruption end → if the system signals `.shouldResume`,
    /// resume via the MainActor thunk (`audioInterruptedResume`).
    @objc private func audioInterrupted(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }
        switch type {
        case .began:
            pause()

        case .ended:
            // An interruption ended. Resume playback, if appropriate.
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                audioInterruptedResume()
            }

        default:
            break
        }
    }

    /// RE: 0x1013b4834 `audioInterruptedMainActorThunk` — MainActor thunk for the interruption-resume
    /// block (`audioInterruptedCompletionBlock`, 0x1013b446c). The interruption notification can be
    /// delivered off the main thread, so the resume is hopped onto the main thread (matching the
    /// binary's dedicated MainActor thunk) before resuming playback.
    private func audioInterruptedResume() {
        runOnMainThread { [weak self] in
            self?.play()
        }
    }
    #endif

    // MARK: - Remote command handlers (RE: registerRemoteCommandHandlers @ 0x1013b555c, 0xB38/2872B)

    /// RE: 0x1013b555c `registerRemoteCommandHandlers` (0xB38/2872B). Wires the **12**
    /// MPRemoteCommandCenter handlers (1.3.15 verified — the prior rev under-counted at 10) and
    /// configures `changeShuffleModeCommand.isEnabled = false` without a handler. Each command's block
    /// closure tail-calls the corresponding named handler (the binary routes through
    /// `remoteCommandBlockBridge @ 0x1013b8970`); the named handlers are the `handle*Command` methods
    /// below. (1.3.14 named this `registerRemoteControllEvent` — typo + Forward-ism corrected.)
    public func registerRemoteCommandHandlers() {
        let remoteCommand = MPRemoteCommandCenter.shared()
        // cmd #1 playCommand → handlePlayCommand (0x1013b8864)
        remoteCommand.playCommand.addTarget { [weak self] event in
            self?.handlePlayCommand(event) ?? .commandFailed
        }
        // cmd #2 pauseCommand → handlePauseCommand (0x1013b89c0)
        remoteCommand.pauseCommand.addTarget { [weak self] event in
            self?.handlePauseCommand(event) ?? .commandFailed
        }
        // cmd #3 togglePlayPauseCommand → handleTogglePlayPauseCommand (0x1013b8acc)
        remoteCommand.togglePlayPauseCommand.addTarget { [weak self] event in
            self?.handleTogglePlayPauseCommand(event) ?? .commandFailed
        }
        // cmd #4 stopCommand → handleStopCommand (0x1013b8c3c)
        remoteCommand.stopCommand.addTarget { [weak self] event in
            self?.handleStopCommand(event) ?? .commandFailed
        }
        // cmd #5 nextTrackCommand → handleNextTrackCommand (0x1013b8d7c)
        remoteCommand.nextTrackCommand.addTarget { [weak self] event in
            self?.handleNextTrackCommand(event) ?? .commandFailed
        }
        // cmd #6 previousTrackCommand → handlePreviousTrackCommand (0x1013b8e88)
        remoteCommand.previousTrackCommand.addTarget { [weak self] event in
            self?.handlePreviousTrackCommand(event) ?? .commandFailed
        }
        // cmd #7 changeRepeatModeCommand → handleChangeRepeatModeCommand (0x1013b8f7c)
        remoteCommand.changeRepeatModeCommand.addTarget { [weak self] event in
            self?.handleChangeRepeatModeCommand(event) ?? .commandFailed
        }
        // Configure-only: changeShuffleModeCommand is disabled, never registered (verified 1.3.15).
        remoteCommand.changeShuffleModeCommand.isEnabled = false
        // cmd #8 changePlaybackRateCommand → handleChangePlaybackRateCommand (0x1013b9100)
        remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
        remoteCommand.changePlaybackRateCommand.addTarget { [weak self] event in
            self?.handleChangePlaybackRateCommand(event) ?? .commandFailed
        }
        // cmd #9 skipForwardCommand → handleSkipForwardCommand (0x1013b929c)
        remoteCommand.skipForwardCommand.preferredIntervals = [15]
        remoteCommand.skipForwardCommand.addTarget { [weak self] event in
            self?.handleSkipForwardCommand(event) ?? .commandFailed
        }
        // cmd #10 skipBackwardCommand → handleSkipBackwardCommand (0x1013b94b8)
        remoteCommand.skipBackwardCommand.preferredIntervals = [15]
        remoteCommand.skipBackwardCommand.addTarget { [weak self] event in
            self?.handleSkipBackwardCommand(event) ?? .commandFailed
        }
        // cmd #11 changePlaybackPositionCommand → handleChangePlaybackPositionCommand (0x1013b96d4)
        remoteCommand.changePlaybackPositionCommand.addTarget { [weak self] event in
            self?.handleChangePlaybackPositionCommand(event) ?? .commandFailed
        }
        // cmd #12 enableLanguageOptionCommand → handleChangeLanguageOptionCommand (0x1013b9880)
        remoteCommand.enableLanguageOptionCommand.addTarget { [weak self] event in
            self?.handleChangeLanguageOptionCommand(event) ?? .commandFailed
        }
    }

    /// RE: 0x1013b8864 `handlePlayCommand` — cmd #1, registered for `playCommand`.
    private func handlePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        play()
        return .success
    }

    /// RE: 0x1013b89c0 `handlePauseCommand` (268B) — cmd #2, registered for `pauseCommand`.
    private func handlePauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        pause()
        return .success
    }

    /// RE: 0x1013b8acc `handleTogglePlayPauseCommand` — cmd #3, registered for `togglePlayPauseCommand`.
    private func handleTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if state.isPlaying {
            pause()
        } else {
            play()
        }
        return .success
    }

    /// RE: 0x1013b8c3c `handleStopCommand` — cmd #4, registered for `stopCommand`.
    private func handleStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        player.shutdown()
        return .success
    }

    /// RE: 0x1013b8d7c `handleNextTrackCommand` (268B) — cmd #5, registered for `nextTrackCommand`.
    private func handleNextTrackCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        playNextURLInPlaylist()
        return .success
    }

    /// RE: 0x1013b8e88 `handlePreviousTrackCommand` — cmd #6, registered for `previousTrackCommand`.
    private func handlePreviousTrackCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        previousPlayer()
        return .success
    }

    /// RE: 0x1013b8f7c `handleChangeRepeatModeCommand` — cmd #7, registered for `changeRepeatModeCommand`.
    private func handleChangeRepeatModeCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPChangeRepeatModeCommandEvent else {
            return .commandFailed
        }
        options.isLoopPlay = event.repeatType != .off
        return .success
    }

    /// RE: 0x1013b9100 `handleChangePlaybackRateCommand` — cmd #8, registered for
    /// `changePlaybackRateCommand` (supportedPlaybackRates = [0.5, 1, 1.5, 2]).
    private func handleChangePlaybackRateCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPChangePlaybackRateCommandEvent else {
            return .commandFailed
        }
        player.playbackRate = event.playbackRate
        return .success
    }

    /// RE: 0x1013b929c `handleSkipForwardCommand` — cmd #9, registered for `skipForwardCommand`
    /// (preferredIntervals = [15]).
    private func handleSkipForwardCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPSkipIntervalCommandEvent else {
            return .commandFailed
        }
        seek(time: player.currentPlaybackTime + event.interval)
        return .success
    }

    /// RE: 0x1013b94b8 `handleSkipBackwardCommand` — cmd #10, registered for `skipBackwardCommand`
    /// (preferredIntervals = [15]).
    private func handleSkipBackwardCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPSkipIntervalCommandEvent else {
            return .commandFailed
        }
        seek(time: player.currentPlaybackTime - event.interval)
        return .success
    }

    /// RE: 0x1013b96d4 `handleChangePlaybackPositionCommand` — cmd #11, registered for
    /// `changePlaybackPositionCommand`.
    private func handleChangePlaybackPositionCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPChangePlaybackPositionCommandEvent else {
            return .commandFailed
        }
        seek(time: event.positionTime)
        return .success
    }

    /// RE: 0x1013b9880 `handleChangeLanguageOptionCommand` — cmd #12, registered for
    /// `enableLanguageOptionCommand`. Selects the audio track whose name matches the requested
    /// language option's display name.
    private func handleChangeLanguageOptionCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPChangeLanguageOptionCommandEvent else {
            return .commandFailed
        }
        let selectLang = event.languageOption
        if selectLang.languageOptionType == .audible,
           let trackToSelect = player.tracks(mediaType: .audio).first(where: { $0.name == selectLang.displayName })
        {
            player.select(track: trackToSelect)
        }
        return .success
    }
}
