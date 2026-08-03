//
//  KSMEPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import AVKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// ⚑[tool=export_trie_oracle ref=MEPlayerItem.delegate:vpMV result=public ⇒ MEPlayerDelegate public ⇒ these five witness methods must be public too (Swift requires a witness to be at least as visible as its requirement). A forced consequence, not five independent observations]
public final class KSMEPlayer: NSObject {
    // Forward 1.3.17 stored fields — reflection order (desc 0x1039ef750); reconstructed session 16c (KSMEPlayer M1 fields).
    // Explicit `: Type` on every field. bufferingCountDownTimer removed (source-extra); seekable computed→stored;
    // shouldResumePlayback added; _pipController lazy→stored pipController; bufferingProgress Int→UInt8.
    private var loopCount: Int = 1
    public var playerItem: MEPlayerItem
    public let audioOutput: AudioOutput
    public var options: KSOptions
    // ⚑[tool=binding_gate ref=KSMEPlayer.videoOutput:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   The ONLY one of session 60's 95 binding mismatches that the compiler REFUTED. The
    //   binary's FieldRecord flags word is 0x00000000 (= `let`; a real `var` such as the
    //   sibling `options` reads 0x00000002), but this declaration cannot be `let`:
    //     • it carries a `didSet` — "'let' declarations cannot be observing properties";
    //     • `private(set)` is meaningless on a read-only property;
    //     • and it is assigned at three sites (:195 nil, :319 nil, :321 constructed).
    //   So EITHER Forward's videoOutput really is immutable — which would mean this whole
    //   replace-and-invalidate lifecycle (oldValue.invalidate + removeFromSuperview) is
    //   modelled wrongly and the three assignments belong somewhere else — OR the flag is not
    //   saying what it appears to. Both readings are substantive and neither is settled by the
    //   flag alone, so this is left as `var` and deferred as its own unit rather than forced.
    //   One of 33 such refutations across 15 classes; 62 of the 95 mismatches WERE fixed.
    //   Detail + the full 33, categorised: reconstruction/binding_refuted_s61.json
    // NON-OPTIONAL in the binary: the trie prints `KSMEPlayer.videoOutput.getter : __C.UIView &
    // KSPlayer.VideoOutput`, with no `?`. Written as the sanctioned IUO STAND-IN — the l2 gate's
    // own name for a binary non-optional reference whose real construction is not yet derived —
    // rather than as a true `let`, because three sites still assign nil and what the binary does
    // at those points has NOT been read. Composition order follows the binary; the parens are
    // Swift's requirement for attaching `!` to a composition, not a type difference.
    public private(set) var videoOutput: (UIView & VideoOutput)! {
        didSet {
            oldValue?.invalidate()
            runOnMainThread {
                oldValue?.removeFromSuperview()
            }
        }
    }

    public private(set) var bufferingProgress: UInt8 = 0 {
        willSet {
            runOnMainThread { [weak self] in
                guard let self else { return }
                delegate?.changeBuffering(player: self, progress: newValue)
            }
        }
    }

    // DIVERGENCE DISCHARGED (opened s16c, closed s98). Binary field 6 is the existential, and the
    // trie agrees on all five spellings — getter, setter, modify, property descriptor and direct
    // field offset all print `KSPlayer.KSPictureInPictureProtocol?`. KSPictureInPictureProtocol is
    // now declared (see KSPictureInPictureController.swift), so the concrete stand-in is gone.
    // Still open, and NOT part of this unit: ⚑ M2, the PiP-controller construction from
    // videoOutput's displayLayer. Was a `_pipController` lazy + computed; the binary stores it.
    public private(set) var pipController: (any KSPictureInPictureProtocol)?

    private lazy var _playbackCoordinator: Any? = {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, *) {
            let coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
            coordinator.suspensionReasonsThatTriggerWaiting = [.stallRecovery]
            return coordinator
        } else {
            return nil
        }
    }()

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        // swiftlint:disable force_cast
        _playbackCoordinator as! AVPlaybackCoordinator
        // swiftlint:enable force_cast
    }

    public private(set) var playableTime: TimeInterval = 0
    public weak var delegate: MediaPlayerDelegate?
    public private(set) var isReadyToPlay: Bool = false
    public var allowsExternalPlayback: Bool = false
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool = false
    public private(set) var seekable: Bool = false // ⚑ M2: binary caches this (recon was computed `playerItem.seekable`)

    public var playbackRate: Float = 1 {
        didSet {
            if playbackRate != audioOutput.playbackRate {
                audioOutput.playbackRate = playbackRate
                if audioOutput is AudioUnitPlayer {
                    var audioFilters = options.audioFilters.filter {
                        !$0.hasPrefix("atempo=")
                    }
                    if playbackRate != 1 {
                        audioFilters.append("atempo=\(playbackRate)")
                    }
                    options.audioFilters = audioFilters
                }
            }
        }
    }

    public private(set) var loadState: MediaLoadState = .idle {
        didSet {
            if loadState != oldValue {
                playOrPause()
            }
        }
    }

    public private(set) var playbackState: MediaPlaybackState = .idle {
        didSet {
            if playbackState != oldValue {
                playOrPause()
                if playbackState == .finished {
                    runOnMainThread { [weak self] in
                        guard let self else { return }
                        delegate?.finish(player: self, error: nil)
                    }
                }
            }
        }
    }

    // ⚑[tool=export_trie_oracle ref=KSMEPlayer.shouldResumePlayback result=no property descriptor ⇒ the GETTER is not public; private(set) is preserved because the binary speaks to the getter only]
    private(set) var shouldResumePlayback: Bool = false // ⚑ M2: binary sets this (NEW field, absent from recon)

    public required init(url: URL, options: KSOptions) {
        KSOptions.setAudioSession()
        audioOutput = KSOptions.audioPlayerType.init()
        playerItem = MEPlayerItem(url: url, options: options)
        if options.videoDisable {
            videoOutput = nil
        } else {
            videoOutput = KSOptions.videoPlayerType.init(options: options)
        }
        self.options = options
        super.init()
        playerItem.delegate = self
        audioOutput.renderSource = playerItem
        videoOutput?.renderSource = playerItem
        videoOutput?.displayLayerDelegate = self
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChange), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        if #available(tvOS 15.0, iOS 15.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(spatialCapabilityChange), name: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification, object: nil)
        }
        #endif
    }

    deinit {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(2)
        #endif
        NotificationCenter.default.removeObserver(self)
        videoOutput?.invalidate()
        playerItem.shutdown()
    }
}

// MARK: - private functions

private extension KSMEPlayer {
    func playOrPause() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            let isPaused = !(self.playbackState == .playing && self.loadState == .playable)
            if isPaused {
                self.audioOutput.pause()
                self.videoOutput?.pause()
            } else {
                self.audioOutput.play()
                self.videoOutput?.play()
            }
            self.delegate?.changeLoadState(player: self)
        }
    }

    @objc private func spatialCapabilityChange(notification _: Notification) {
        KSLog("[audio] spatialCapabilityChange")
        for track in tracks(mediaType: .audio) {
            (track as? FFmpegAssetTrack)?.audioDescriptor?.updateAudioFormat()
        }
    }

    #if !os(macOS)
    @objc private func audioRouteChange(notification: Notification) {
        KSLog("[audio] audioRouteChange")
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
            return
        }
//        let routeChangeReason = AVAudioSession.RouteChangeReason(rawValue: reason)
//        guard [AVAudioSession.RouteChangeReason.newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange].contains(routeChangeReason) else {
//            return
//        }
        for track in tracks(mediaType: .audio) {
            (track as? FFmpegAssetTrack)?.audioDescriptor?.updateAudioFormat()
        }
        audioOutput.flush()
    }
    #endif
}

extension KSMEPlayer: MEPlayerDelegate {
    public func sourceDidOpened() {
        isReadyToPlay = true
        options.readyTime = CACurrentMediaTime()
        let vidoeTracks = tracks(mediaType: .video)
        if vidoeTracks.isEmpty {
            videoOutput = nil
        }
        let audioDescriptor = tracks(mediaType: .audio).first { $0.isEnabled }.flatMap {
            $0 as? FFmpegAssetTrack
        }?.audioDescriptor
        runOnMainThread { [weak self] in
            guard let self else { return }
            if let audioDescriptor {
                KSLog("[audio] audio type: \(audioOutput) prepare audioFormat )")
                audioOutput.prepare(audioFormat: audioDescriptor.audioFormat)
            }
            if let controlTimebase = videoOutput?.displayLayer.controlTimebase, options.startPlayTime > 1 {
                CMTimebaseSetTime(controlTimebase, time: CMTimeMake(value: Int64(options.startPlayTime), timescale: 1))
            }
            delegate?.readyToPlay(player: self)
        }
    }

    public func sourceDidFailed(error: NSError?) {
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.finish(player: self, error: error)
        }
    }

    public func sourceDidFinished() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            if self.options.isLoopPlay {
                self.loopCount += 1
                self.delegate?.playBack(player: self, loopCount: self.loopCount)
                self.audioOutput.play()
                self.videoOutput?.play()
            } else {
                self.playbackState = .finished
            }
        }
    }

    public func sourceDidChange(loadingState: LoadingState) {
        if loadingState.isEndOfFile {
            playableTime = duration
        } else {
            playableTime = currentPlaybackTime + loadingState.loadedTime
        }
        if loadState == .playable {
            if !loadingState.isEndOfFile, loadingState.frameCount == 0, loadingState.packetCount == 0, options.preferredForwardBufferDuration != 0 {
                loadState = .loading
                if playbackState == .playing {
                    runOnMainThread { [weak self] in
                        // 在主线程更新进度
                        self?.bufferingProgress = 0
                    }
                }
            }
        } else {
            if loadingState.isFirst {
                if videoOutput?.pixelBuffer == nil {
                    videoOutput?.readNextFrame()
                }
            }
            var progress = 100
            if loadingState.isPlayable {
                loadState = .playable
            } else {
                if loadingState.progress.isInfinite {
                    progress = 100
                } else if loadingState.progress.isNaN {
                    progress = 0
                } else {
                    progress = min(100, Int(loadingState.progress))
                }
            }
            if playbackState == .playing {
                runOnMainThread { [weak self] in
                    // 在主线程更新进度
                    self?.bufferingProgress = UInt8(progress) // bufferingProgress Int→UInt8 (progress clamped [0,100])
                }
            }
        }
        if duration == 0, playbackState == .playing, loadState == .playable {
            if let rate = options.liveAdaptivePlaybackRate(loadingState: loadingState) {
                playbackRate = rate
            }
        }
    }

    public func sourceDidChange(oldBitRate: Int64, newBitrate: Int64) {
        KSLog("oldBitRate \(oldBitRate) change to newBitrate \(newBitrate)")
    }
}

extension KSMEPlayer: @preconcurrency MediaPlayerProtocol {
    public var chapters: [Chapter] {
        playerItem.chapters
    }

    public var subtitleDataSource: (any SubtitleDataSource)? { self }
    public var playbackVolume: Float {
        get {
            audioOutput.volume
        }
        set {
            audioOutput.volume = newValue
        }
    }

    public var isPlaying: Bool { playbackState == .playing }

    @MainActor
    public var naturalSize: CGSize {
        !options.display.isSphere ? playerItem.naturalSize : KSOptions.sceneSize
    }

    public var isExternalPlaybackActive: Bool { false }

    public var view: UIView? { videoOutput }

    public func replace(url: URL, options: KSOptions) {
        KSLog("replaceUrl \(self)")
        shutdown()
        playerItem.delegate = nil
        playerItem = MEPlayerItem(url: url, options: options)
        if options.videoDisable {
            videoOutput = nil
        } else if videoOutput == nil {
            videoOutput = KSOptions.videoPlayerType.init(options: options)
            videoOutput?.displayLayerDelegate = self
        }
        self.options = options
        playerItem.delegate = self
        audioOutput.flush()
        audioOutput.renderSource = playerItem
        videoOutput?.renderSource = playerItem
        videoOutput?.options = options
    }

    public var currentPlaybackTime: TimeInterval {
        get {
            playerItem.currentPlaybackTime
        }
        set {
            seek(time: newValue) { _ in }
        }
    }

    public var duration: TimeInterval { playerItem.duration }

    public var fileSize: Int64 { playerItem.fileSize }

    public var dynamicInfo: DynamicInfo? {
        playerItem.dynamicInfo
    }

    public func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        let time = max(time, 0)
        playbackState = .seeking
        runOnMainThread { [weak self] in
            self?.bufferingProgress = 0
        }
        let seekTime: TimeInterval
        if time >= duration, options.isLoopPlay {
            seekTime = 0
        } else {
            seekTime = time
        }
        playerItem.seek(time: seekTime) { [weak self] result in
            guard let self else { return }
            if result {
                self.audioOutput.flush()
                runOnMainThread { [weak self] in
                    guard let self else { return }
                    if let controlTimebase = self.videoOutput?.displayLayer.controlTimebase {
                        CMTimebaseSetTime(controlTimebase, time: CMTimeMake(value: Int64(self.currentPlaybackTime), timescale: 1))
                    }
                }
            }
            completion(result)
        }
    }

    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)")
        options.prepareTime = CACurrentMediaTime()
        playerItem.prepareToPlay()
        bufferingProgress = 0
    }

    public func play() {
        KSLog("play \(self)")
        playbackState = .playing
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            // req4 `invalidatePlaybackState` is a REAL requirement of the binary protocol
            // (witness 0x1019c77d8 -> selref 0x10440bcb0), but it is iOS 15 / tvOS 15 while the
            // protocol is tvOS 14, so it is pinned rather than declared. The cast is OURS.
            (pipController as? KSPictureInPictureController)?.invalidatePlaybackState()
        }
    }

    public func pause() {
        KSLog("pause \(self)")
        playbackState = .paused
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            // req4 `invalidatePlaybackState` is a REAL requirement of the binary protocol
            // (witness 0x1019c77d8 -> selref 0x10440bcb0), but it is iOS 15 / tvOS 15 while the
            // protocol is tvOS 14, so it is pinned rather than declared. The cast is OURS.
            (pipController as? KSPictureInPictureController)?.invalidatePlaybackState()
        }
    }

    public func shutdown() {
        KSLog("shutdown \(self)")
        playbackState = .stopped
        loadState = .idle
        isReadyToPlay = false
        loopCount = 0
        playerItem.shutdown()
        options.prepareTime = 0
        options.dnsStartTime = 0
        options.tcpStartTime = 0
        options.tcpConnectedTime = 0
        options.openTime = 0
        options.findTime = 0
        options.readyTime = 0
        options.readAudioTime = 0
        options.readVideoTime = 0
        options.decodeAudioTime = 0
        options.decodeVideoTime = 0
        if KSOptions.isClearVideoWhereReplace {
            videoOutput?.flush()
        }
    }

    @MainActor
    public var contentMode: UIViewContentMode {
        get {
            view?.contentMode ?? .center
        }
        set {
            view?.contentMode = newValue
        }
    }

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        videoOutput?.pixelBuffer?.cgImage()
    }

    public func enterBackground() {}

    public func enterForeground() {}

    public var isMuted: Bool {
        get {
            audioOutput.isMuted
        }
        set {
            audioOutput.isMuted = newValue
        }
    }

    public func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack] {
        playerItem.assetTracks.compactMap { track -> MediaPlayerTrack? in
            if track.mediaType == mediaType {
                return track
            } else if mediaType == .subtitle {
                return track.closedCaptionsTrack
            }
            return nil
        }
    }

    public func select(track: some MediaPlayerTrack) {
        let isSeek = playerItem.select(track: track)
        if isSeek {
            audioOutput.flush()
        }
    }
}

@available(tvOS 14.0, *)
extension KSMEPlayer: AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureController(_: AVPictureInPictureController, setPlaying playing: Bool) {
        playing ? play() : pause()
    }

    public func pictureInPictureControllerTimeRangeForPlayback(_: AVPictureInPictureController) -> CMTimeRange {
        // Handle live streams.
        if duration == 0 {
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        return CMTimeRange(start: 0, end: duration)
    }

    public func pictureInPictureControllerIsPlaybackPaused(_: AVPictureInPictureController) -> Bool {
        !isPlaying
    }

    public func pictureInPictureController(_: AVPictureInPictureController, didTransitionToRenderSize _: CMVideoDimensions) {}
    public func pictureInPictureController(_: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        seek(time: currentPlaybackTime + skipInterval.seconds) { _ in }
    }

    public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_: AVPictureInPictureController) -> Bool {
        false
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
extension KSMEPlayer: AVPlaybackCoordinatorPlaybackControlDelegate {
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue playCommand: AVDelegatingPlaybackCoordinatorPlayCommand, completionHandler: @escaping () -> Void) {
        guard playCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        nonisolated(unsafe) let handler = completionHandler
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .playing {
                self.play()
            }
            handler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue pauseCommand: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping () -> Void) {
        guard pauseCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        nonisolated(unsafe) let handler = completionHandler
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .paused {
                self.pause()
            }
            handler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue seekCommand: AVDelegatingPlaybackCoordinatorSeekCommand) async {
        guard seekCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        let seekTime = fmod(seekCommand.itemTime.seconds, duration)
        if abs(currentPlaybackTime - seekTime) < CGFLOAT_EPSILON {
            return
        }
        seek(time: seekTime) { _ in }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue bufferingCommand: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping () -> Void) {
        guard bufferingCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        nonisolated(unsafe) let handler = completionHandler
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.loadState != .playable, let countDown = bufferingCommand.completionDueDate?.timeIntervalSinceNow else {
                handler()
                return
            }
            // ⚑ UNRESOLVED → KSMEPlayer M2: buffering countdown (recon retained a `bufferingCountDownTimer: Timer?`, removed source-extra)
            _ = countDown
            handler()
        }
    }
}

extension KSMEPlayer: DisplayLayerDelegate {
    public func change(displayLayer: AVSampleBufferDisplayLayer) {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
            pipController = KSPictureInPictureController(contentSource: contentSource) // stored (was _pipController lazy); binary field 6
            // 更改contentSource会直接crash
//            pipController?.contentSource = contentSource
        }
    }
}

public extension KSMEPlayer {
    func startRecord(url: URL) {
        playerItem.startRecord(url: url, mediaType: nil)
    }

    func stoptRecord() {
        playerItem.stopRecord()
    }
}
