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

public class KSMEPlayer: NSObject {
    private var loopCount = 1
    private var playerItem: MEPlayerItem
    public let audioOutput: AudioOutput
    private var options: KSOptions
    private var bufferingCountDownTimer: Timer?
    public private(set) var videoOutput: (VideoOutput & UIView)? {
        didSet {
            oldValue?.invalidate()
            runOnMainThread {
                oldValue?.removeFromSuperview()
            }
        }
    }

    public private(set) var bufferingProgress = 0 {
        willSet {
            runOnMainThread { [weak self] in
                guard let self else { return }
                delegate?.changeBuffering(player: self, progress: newValue)
            }
        }
    }

    private lazy var _pipController: Any? = {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *), let videoOutput {
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: videoOutput.displayLayer, playbackDelegate: self)
            let pip = KSPictureInPictureController(contentSource: contentSource)
            return pip
        } else {
            return nil
        }
    }()

    @available(tvOS 14.0, *)
    public var pipController: KSPictureInPictureController? {
        _pipController as? KSPictureInPictureController
    }

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

    public private(set) var playableTime = TimeInterval(0)
    public weak var delegate: MediaPlayerDelegate?
    public private(set) var isReadyToPlay = false
    public var allowsExternalPlayback: Bool = false
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool = false

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

    public private(set) var loadState = MediaLoadState.idle {
        didSet {
            if loadState != oldValue {
                playOrPause()
            }
        }
    }

    public private(set) var playbackState = MediaPlaybackState.idle {
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

    /// RE: field #18 (types.json `KSPlayer.KSMEPlayer`, stored offset for
    /// `0x101424db4`). Resume-after-interruption bit: latched when playback is
    /// suspended by a route change / audio-session interruption while playing, so
    /// recovery can decide whether to auto-resume. Persisted by
    /// `saveShouldResumePlayback()`.
    private var shouldResumePlayback = false

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

    // MARK: Spatial-audio routing
    //
    // Negative finding (RE constraint d, _isAtmos string 0x103314eb6 / dup
    // 0x103736956, descriptor 0x103c307e8): `_isAtmos` is NOT a KSPlayer routing
    // flag — its only xref is the reflection field descriptor, i.e. an app-layer
    // SwiftUI status-bar badge `@Published` ivar set from track metadata (play
    // repo / UIComponents.md). It participates in NEITHER renderer selection (the
    // existential bit-test + the outputNumberOfChannels channel-negotiation swap)
    // NOR spatial routing. Likewise the "Dolby … + Dolby Atmos" display strings
    // (E-AC-3 JOC 0x103494358, TrueHD 0x103494379) are __const codec display-name
    // LABELS, not runtime routing constants. KSMEPlayer therefore intentionally
    // contains NO `_isAtmos` field and NO codec-display-string routing — do not
    // add them in a later pass.

    /// RE: 0x10141ff94 (KSMEPlayer.handleSpatialCapabilityChange(notification:), 1.3.15)
    /// Reached via shim 0x1014205cc → shared bridge 0x101420efc.
    ///
    /// Structural mirror of `audioRouteChange` MINUS the userInfo/ReasonKey parse
    /// (a spatial-capability change carries no reason key). Runs the identical
    /// per-FFmpegAssetTrack channel-renegotiation loop, then a tail gate that —
    /// unlike the route handler — only re-sets-up the engine when the active
    /// renderer is the AVAudioEngine path: if `playbackState == .playing` and
    /// `audioOutput` is exactly AudioEnginePlayer (binary `_swift_dynamicCastClass`
    /// to 0x1013f3d50), schedule the MainActor async output-format rebuild. It does
    /// NOT check `loadState` or any reason. AudioRendererPlayer / AVPlayer renderers
    /// handle spatial natively, so they are intentionally skipped here.
    @objc private func spatialCapabilityChange(notification _: Notification) {
        KSLog("[audio] spatialCapabilityChange")
        #if !os(macOS)
        renegotiateAudioTrackChannels()
        // Tail gate: spatial re-setup is only meaningful for the AVAudioEngine
        // (pull/PCM) path. AudioRendererPlayer pushes CMSampleBuffers to
        // AVSampleBufferAudioRenderer and lets the OS spatialize the bitstream —
        // it needs no manual rebuild. So cast to AudioEnginePlayer specifically.
        if playbackState == .playing, let enginePlayer = audioOutput as? AudioEnginePlayer {
            scheduleAudioEngineReconfigure(enginePlayer)
        }
        #endif
    }

    /// RE: 0x1013aa640 (KSMEPlayer.checkSpatialAudioAndSetMultichannel, 1.3.15)
    /// Thunk at 0x1013a78d0 trampolines to this body.
    ///
    /// Scans `AVAudioSession.currentRoute.outputs` for any port with
    /// `isSpatialAudioEnabled` set, pushes that result to the session via
    /// `setSupportsMultichannelContent(_:)` (selref 0x103c53250) — passed
    /// unconditionally, matching the `KSOptions.isSpatialAudioEnabled` sibling —
    /// and returns whether any port supports spatial audio.
    ///
    /// The scan is gated on the spatial-audio-enabled flag (binary global
    /// DAT_104458748, written when `enhanceDolby` is on; mapped here to the
    /// per-instance `options.isSpatialAudioEnabled`, distinct from the
    /// active-player-type global DAT_104458738 → `KSOptions.audioPlayerType`).
    /// enhanceDolby → DAT_104458748 → this scan → channel negotiation
    /// (outputNumberOfChannels) → AudioRendererPlayer selection is the Atmos
    /// activation chain; enhanceDolby itself is owned by DolbyVision.md.
    #if !os(macOS)
    @discardableResult
    private func checkSpatialAudioAndSetMultichannel() -> Bool {
        guard #available(iOS 15.0, tvOS 15.0, *) else { return false }
        // Gate on the spatial-enabled flag (DAT_104458748). When spatial output
        // has not been requested, do not negotiate multichannel — report stereo.
        guard options.isSpatialAudioEnabled else { return false }
        let route = AVAudioSession.sharedInstance().currentRoute
        let hasSpatial = route.outputs.contains { $0.isSpatialAudioEnabled }
        KSLog("[audio] checkSpatialAudio: hasSpatial=\(hasSpatial)")
        try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(hasSpatial)
        return hasSpatial
    }

    /// RE: 0x1013aa894 (KSMEPlayer.outputNumberOfChannels(channelCount:), 1.3.15)
    /// Channel-count negotiation — the ONLY runtime path that swaps the active
    /// audio renderer toward AudioRendererPlayer for spatial/Atmos content.
    ///
    /// Decision matrix (verified decompile `uint FUN_1013aa894(uint param_1)`):
    ///  - `swift_once` the AudioEnginePlayer singleton (establishes
    ///    DAT_104458738, the active `audioPlayerType` class metadata).
    ///  - call `checkSpatialAudioAndSetMultichannel()` to refresh the live
    ///    spatial-capability reading.
    ///  - accumulate the MAX channel count across
    ///    `currentRoute.outputs[].channels`.
    ///  - if `channelCount < 3` → force stereo (return 2).
    ///  - else clamp to the port max and compare the active renderer
    ///    (DAT_104458738 ≡ `KSOptions.audioPlayerType`) against AudioUnitPlayer /
    ///    AudioEnginePlayer metadata plus the spatial flag: AudioRendererPlayer
    ///    (and AudioUnitPlayer) keep the full count, AudioEnginePlayer is clamped
    ///    to stereo in the non-spatial branch.
    ///
    /// The active-renderer identity comparison is expressed in the shared helper
    /// as `KSOptions.audioPlayerType == AudioRendererPlayer.self`.
    private func outputNumberOfChannels(channelCount: AVAudioChannelCount) -> AVAudioChannelCount {
        // Refresh spatial capability from the live route (matches the binary's
        // step-3 call into checkSpatialAudioAndSetMultichannel before negotiating).
        checkSpatialAudioAndSetMultichannel()
        // The full decision matrix (swift_once singleton, port-max accumulation,
        // active-player-type comparison vs AUP/AEP/ARP metadata) lives in the
        // shared static helper KSOptions.outputNumberOfChannels(channelCount:),
        // which performs the identical DAT_104458738 identity compare via
        // `KSOptions.audioPlayerType == AudioRendererPlayer.self`.
        return KSOptions.outputNumberOfChannels(channelCount: channelCount)
    }
    #endif

    /// RE: Forward v1.3.15 (0x1013085A4)
    /// Flushes the video output buffer and, if paused with a seekable source using
    /// hardware decode, re-seeks to the current position to refresh the displayed frame.
    private func flushVideoAndReseek() {
        videoOutput?.flush()
        let isPaused = playbackState == .paused
        if isPaused, playerItem.seekable, playerItem.duration > 0, options.hardwareDecode {
            let currentTime = playerItem.currentPlaybackTime
            playerItem.seek(time: currentTime) { _ in }
        }
    }

    /// RE: Forward v1.3.15 (0x101305968)
    /// Updates `playableTime` from current loading state and calculates buffering
    /// percentage from (loadedTime / preferredForwardBufferDuration). If buffering
    /// is complete (progress >= 100), transitions load state to playable.
    private func updateBufferingState() {
        let loadedTime = playableTime - currentPlaybackTime
        let targetDuration = options.preferredForwardBufferDuration
        let progress: Int
        if targetDuration == 0 {
            progress = 100
        } else {
            progress = min(100, Int(loadedTime * 100.0 / targetDuration))
        }
        if progress >= 100, loadState != .playable {
            loadState = .playable
        }
        if playbackState == .playing {
            runOnMainThread { [weak self] in
                self?.bufferingProgress = progress
            }
        }
    }

    /// RE: 0x1014205dc (KSMEPlayer.handleAudioRouteChange(notification:), 1.3.15)
    /// Reached via shim 0x101420eec → shared bridge 0x101420efc.
    ///
    /// 1. `userInfo` nil → fast-path return.
    /// 2. Extract `AVAudioSessionRouteChangeReasonKey` and cast to UInt; cast
    ///    failure → return.
    /// 3. Verbose-log gate when `KSOptions.logLevel` > 2; the renegotiation runs
    ///    regardless of log level.
    /// 4. Per-FFmpegAssetTrack channel renegotiation loop (see
    ///    `renegotiateAudioTrackChannels`).
    /// 5. Kick the renderer (binary invokes the MediaPlayerProtocol witness at
    ///    +0x18 → `flush()` here).
    /// 6. Gates: if `reason == .oldDeviceUnavailable` (2) → return without async
    ///    re-setup. Else if `playbackState == .playing` AND `loadState ==
    ///    .playable`, schedule the MainActor async output-format rebuild.
    #if !os(macOS)
    @objc private func audioRouteChange(notification: Notification) {
        KSLog("[audio] audioRouteChange")
        // (1) No userInfo → nothing to renegotiate.
        guard let userInfo = notification.userInfo else { return }
        // (2) Reason is required; a failed cast aborts the handler.
        guard let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else {
            return
        }
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        // (3) Verbose diagnostics only above warning level.
        if KSOptions.logLevel.rawValue > LogLevel.warning.rawValue {
            KSLog("[audio] audioRouteChange reason: \(String(describing: reason))")
        }
        // (4) Recompute per-track channel layouts against the new route.
        renegotiateAudioTrackChannels()
        // (5) Kick the active renderer so it picks up the new output format
        //     (binary calls MediaPlayerProtocol witness +0x18).
        audioOutput.flush()
        // (6) .oldDeviceUnavailable (e.g. headphones unplugged) must not trigger
        //     an async engine rebuild — playback is being paused/handled elsewhere.
        if reason == .oldDeviceUnavailable {
            return
        }
        // Only re-set-up when actively playing and ready, and only for the
        // AVAudioEngine path (ARP/AVPlayer spatialize natively).
        if playbackState == .playing, loadState == .playable,
           let enginePlayer = audioOutput as? AudioEnginePlayer
        {
            scheduleAudioEngineReconfigure(enginePlayer)
        }
    }

    /// RE: per-track renegotiation loop at 0x101420964 (shared by the route and
    /// spatial-capability handlers, 1.3.15).
    ///
    /// For each audio track that is exactly an `FFmpegAssetTrack` carrying an
    /// `AudioDescriptor`, recompute the renderer-facing channel count and rebuild
    /// the output `AVAudioFormat`. The binary performs this as three explicit
    /// steps the API-Surface-Preservation rule keeps separate:
    ///   1. read requested channelCount = AudioDescriptor+0x24 (`channel.nb_channels`)
    ///      → `outputNumberOfChannels(channelCount:)` (0x1013aa894), which itself
    ///      re-reads the live route + spatial capability;
    ///   2. read sampleRate = AudioDescriptor+0x10 → `audioSwrInit(sampleRate,
    ///      &outChannel(+0x40), adjustedCount)` (0x10144c8ac) to rebuild the
    ///      swresample context + output format/channel layout;
    ///   3. store the rebuilt `AVAudioFormat` back at AudioDescriptor+0x18.
    /// `AudioDescriptor.updateAudioFormat()` (Resample.swift) wraps exactly this
    /// `outputNumberOfChannels → audioFormat rebuild → store-back` sequence, so it
    /// is the in-cluster call site here. The explicit `audioSwrInit` /
    /// AudioDescriptor field semantics live in Resample.swift (AudioResample
    /// cluster); see the CROSS-FILE note for verification of that wrapping.
    private func renegotiateAudioTrackChannels() {
        for track in tracks(mediaType: .audio) {
            guard let assetTrack = track as? FFmpegAssetTrack,
                  let audioDescriptor = assetTrack.audioDescriptor
            else {
                continue
            }
            // Step 1 (binary AudioDescriptor+0x24 → outputNumberOfChannels): recompute
            // the renderer-facing count against the live route + spatial capability.
            // Kept as a discrete call per API-Surface-Preservation; the value also
            // drives the ARP-swap decision inside the shared helper.
            let adjustedCount = outputNumberOfChannels(channelCount: AVAudioChannelCount(audioDescriptor.channel.nb_channels))
            KSLog("[audio] renegotiated channelCount: \(adjustedCount) for track \(assetTrack.trackID)")
            // Steps 2+3 (audioSwrInit at AudioDescriptor+0x40 → store AVAudioFormat at
            // +0x18): AudioDescriptor.updateAudioFormat() wraps the swresample-context
            // rebuild and the store-back. See CROSS-FILE note re: Resample.swift.
            audioDescriptor.updateAudioFormat()
        }
    }

    /// RE: schedules the AudioEnginePlayer async output-format rebuild closure
    /// (0x1013f8b5c, dispatched via the generic MainActor task wrapper 0x1013ad160
    /// with asyncFn DAT_102eef760 [route] / DAT_102eef770 [spatial], 1.3.15).
    ///
    /// The binary's generic `swift_task_create` wrapper (9 call sites, not
    /// audio-specific) collapses to `Task { @MainActor in … }` in idiomatic Swift.
    /// The concrete reconfigure body (early-out if format unchanged, else
    /// stop/uninitialize the I/O unit, set preferred channels/sample-rate, rebuild
    /// the ASBD + channel layout + render callbacks, reinitialize, and re-dispatch
    /// start if it was running) is AudioEnginePlayer's, reached here through
    /// `prepare(audioFormat:)`. See CROSS-FILE note: the format-diff early-out and
    /// the I/O-unit teardown/rebuild belong in AudioEnginePlayer.swift
    /// (AudioEnginePlayerFamily cluster); KSMEPlayer only schedules it.
    private func scheduleAudioEngineReconfigure(_ enginePlayer: AudioEnginePlayer) {
        // The renegotiated format lives on the enabled audio track's descriptor
        // (mirrors sourceDidOpened's prepare path).
        guard let audioFormat = tracks(mediaType: .audio)
            .first(where: { $0.isEnabled })
            .flatMap({ $0 as? FFmpegAssetTrack })?
            .audioDescriptor?.audioFormat
        else {
            return
        }
        let wasPlaying = playbackState == .playing
        Task { @MainActor in
            enginePlayer.prepare(audioFormat: audioFormat)
            if wasPlaying {
                enginePlayer.play()
            }
        }
    }
    #endif

    /// RE: 0x101420bbc (KSMEPlayer.checkAudioRendererReady, 1.3.15)
    /// MainActor readiness gate (invoker chain: async descriptor → bootstrap
    /// 0x1014285dc → MainActor hop 0x101420b2c → here).
    ///
    /// Hard-gates playback start on the audio output being an
    /// `AudioRendererPlayer` (the Atmos CMSampleBuffer push path). If the active
    /// output has not yet resolved to AudioRendererPlayer (e.g. the spatial
    /// channel-negotiation swap is still settling), it `Task.sleep`s 1 s and
    /// retries; once the cast succeeds it starts the audio + video outputs.
    @MainActor
    private func checkAudioRendererReady() async {
        // Gate target type = _objc_opt_self(AudioRendererPlayer) (0x1013f7f80).
        while !(audioOutput is AudioRendererPlayer) {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                // Cancellation → abandon the gate (binary teardown path 0x101420eac).
                return
            }
        }
        audioOutput.play()
        videoOutput?.play()
    }

    /// RE: 0x1014234dc (KSMEPlayer.reset, 1.3.15; paired thunk 0x101425634)
    /// Distinct from `shutdown()` — `reset()` returns the engine to its idle
    /// baseline by delegating the consolidated timing-field clear to
    /// `options.resetOptions()` (binary `options` witness `[+0x310]`), then zeroes
    /// the four KSMEPlayer-owned state fields and drives the demux item to its
    /// terminal `.finished` state (state transition 6 — `MESourceState.finished`).
    ///
    /// Decompile order (verified): `options.resetOptions()` → `loadState = .idle`
    /// (0) → `playbackState = .idle` (0, with the state-change delegate forward) →
    /// `isReadyToPlay = false` → `loopCount = 0` → playerItem state→6 (.finished)
    /// via the relocated MEPlayerItem set-state dispatcher (0x10142a680) → tail
    /// clear-video gate on `KSOptions.isClearVideoWhereReplace`.
    ///
    /// API-Surface-Preservation: kept separate from `shutdown()`. The 11 inline
    /// timing-field zeroes that `shutdown()` previously inlined are the body of
    /// `options.resetOptions()`; both call sites now route through it.
    func reset() {
        // Consolidated timing-metrics reset (binary options witness [+0x310]).
        options.resetOptions()
        loadState = .idle
        playbackState = .idle
        isReadyToPlay = false
        loopCount = 0
        // Drive the demux/decode item to its terminal state (transition 6 =
        // MESourceState.finished). The binary calls the relocated MEPlayerItem
        // set-state dispatcher (0x10142a680) on the retained playerItem.
        // CROSS-FILE NEEDED: MEPlayerItem.swift has no public hook to request the
        // .finished(6) transition (its `state` is private). The closest public
        // surface that retires the read loop is `playerItem.shutdown()`, but that
        // also tears down I/O — heavier than the binary's bare state write. Until
        // MEPlayerItem exposes a finish hook, the playerItem state-6 transition is
        // left to the existing lifecycle (shutdown path), matching observable
        // behavior without an out-of-cluster edit.
        // Tail: clear the displayed frame when configured (mirrors shutdown()).
        if KSOptions.isClearVideoWhereReplace {
            if let metalPlayView = videoOutput as? MetalPlayView {
                metalPlayView.flushAndRemoveImage()
            } else {
                videoOutput?.flush()
            }
        }
    }

    /// RE: 0x10141fdb0 (KSMEPlayer.audioVideoFlushAndNotify, 1.3.15)
    /// Combined flush-and-notify used on recovery transitions. Guards
    /// `playbackState == .playing (1)` AND `loadState == .playable (2)` (the
    /// decompile additionally reads a bool at `options + 0x47`); when the guard
    /// holds it flushes BOTH the video and audio outputs, then notifies the
    /// delegate via the `MediaPlayerDelegate` witness `[+0x10]`
    /// (`changeLoadState(player:)`).
    private func audioVideoFlushAndNotify() {
        guard playbackState == .playing, loadState == .playable else {
            return
        }
        videoOutput?.flush()
        audioOutput.flush()
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.changeLoadState(player: self)
        }
    }

    /// RE: 0x101424db4 (KSMEPlayer.saveShouldResumePlayback, 1.3.15; paired thunk
    /// 0x101425638). Persists the resume-after-interruption bit (field #18,
    /// `shouldResumePlayback`): latch true only while actively playing, so an
    /// interruption/route-change recovery path can decide whether to auto-resume.
    private func saveShouldResumePlayback() {
        shouldResumePlayback = playbackState == .playing
    }
}

extension KSMEPlayer: MEPlayerDelegate {
    func sourceDidOpened() {
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
            if options.startPlayTime > 1 {
                if let metalPlayView = videoOutput as? MetalPlayView {
                    metalPlayView.displayView.seek(to: CMTimeMake(value: Int64(options.startPlayTime), timescale: 1))
                } else if let controlTimebase = videoOutput?.displayLayer.controlTimebase {
                    CMTimebaseSetTime(controlTimebase, time: CMTimeMake(value: Int64(options.startPlayTime), timescale: 1))
                }
            }
            delegate?.readyToPlay(player: self)
        }
    }

    func sourceDidFailed(error: NSError?) {
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.finish(player: self, error: error)
        }
    }

    func sourceDidFinished() {
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

    func sourceDidChange(loadingState: LoadingState) {
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
                    self?.bufferingProgress = progress
                }
            }
        }
        if duration == 0, playbackState == .playing, loadState == .playable {
            if let rate = options.liveAdaptivePlaybackRate(loadingState: loadingState) {
                playbackRate = rate
            }
        }
    }

    func sourceDidChange(oldBitRate: Int64, newBitrate: Int64) {
        KSLog("oldBitRate \(oldBitRate) change to newBitrate \(newBitrate)")
    }
}

extension KSMEPlayer: MediaPlayerProtocol {
    public var renderSynchronizer: AVSampleBufferRenderSynchronizer? {
        audioOutput.synchronizer
    }

    public var chapters: [Chapter] {
        playerItem.chapters
    }

    public var subtitleDataSource: SubtitleDataSource? { self }
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
        options.display == .plane ? playerItem.naturalSize : KSOptions.sceneSize
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

    public var fileSize: Double { playerItem.fileSize }

    public var seekable: Bool { playerItem.seekable }

    /// RE: 0x10141e758 (KSMEPlayer.getIOContextCacheEntries → cachedRanges, 1.3.15;
    /// trampoline 0x1014255e8). The live PlayerCore consumer of
    /// `MEPlayerItem.ioContext` that feeds the seek-bar buffered-range rail.
    ///
    /// Verified decompile: read `playerItem.ioContext`; if nil → empty array. Else
    /// `_swift_dynamicCast` the `AbstractAVIOContext` existential, read
    /// `playerItem.duration`; if `duration <= 0` → empty array. Otherwise dispatch
    /// the cast type's witness `[+0x38]` with the duration to build the
    /// `[CachedTimeRange]` array. In source terms `[+0x38]` is the overridable
    /// `AbstractAVIOContext.cachedRanges(duration:)` — the cache-backed subclasses
    /// (CacheIOContext / PreLoadIOContext) translate their buffered byte ranges to
    /// time ranges via the duration; the base returns `[]`.
    ///
    /// CROSS-FILE NEEDED (two deltas, required for this property to compile):
    ///  1. MEPlayerItem.swift — `ioContext` is currently `private`; it must be
    ///     module-internal (drop `private`, i.e. `var ioContext: AbstractAVIOContext?`)
    ///     so this getter can read it. The binary reads the field directly from
    ///     KSMEPlayer (same-module field access at `MEPlayerItem::ioContext`).
    ///  2. PlayerDefines.swift — `AbstractAVIOContext` must declare
    ///     `open func cachedRanges(duration: TimeInterval) -> [CachedTimeRange] { [] }`
    ///     (the `+0x38` witness slot), and the cache subclasses in CacheHierarchy.swift
    ///     should override it (map buffered byte ranges → time via `_timeIndex` /
    ///     fetched extents).
    /// `CachedTimeRange` already lives in Core/CachedTimeRange.swift — do not redefine.
    /// Not a `MediaPlayerProtocol` requirement (no protocol dispatch in the binary),
    /// so it stays a concrete KSMEPlayer property.
    public var cachedRanges: [CachedTimeRange] {
        guard let ioContext = playerItem.ioContext, playerItem.duration > 0 else {
            return []
        }
        return ioContext.cachedRanges(duration: playerItem.duration)
    }

    /// RE: 0x1014257a4 (KSMEPlayer.seekableTimeRanges getter, 1.3.15). The
    /// seekable span(s) of the current item as time ranges. The FFmpeg engine
    /// exposes a single contiguous seekable span `[0, duration]` once the item is
    /// seekable; live/non-seekable sources report none.
    public var seekableTimeRanges: [CMTimeRange] {
        guard playerItem.seekable, playerItem.duration > 0 else {
            return []
        }
        return [CMTimeRange(start: .zero, end: CMTime(seconds: playerItem.duration))]
    }

    /// RE: 0x101421dd8 (KSMEPlayer.videoRotation getter, 1.3.15). Surfaces the
    /// enabled video track's display rotation (degrees, from the FFmpeg
    /// `displaymatrix` side data). KSMEPlayer has no rotation field of its own; it
    /// reads through to the active `FFmpegAssetTrack.rotation` (Int16).
    public var videoRotation: Int16 {
        tracks(mediaType: .video).first { $0.isEnabled }?.rotation ?? 0
    }

    public var dynamicInfo: DynamicInfo? {
        playerItem.dynamicInfo
    }

    /// RE: 0x101429304 (KSMEPlayer.setAVDictOption, 1.3.15). Thin wrapper that
    /// writes a single key/value into an FFmpeg `AVDictionary` during item/option
    /// setup (the binary's `av_dict_set(&dict, key, value, 0)` helper). Exposed so
    /// callers can layer format/codec options onto the player's FFmpeg context
    /// without reaching into the C dictionary directly.
    /// TODO(re-verify): exact owning dictionary (format-context vs codec options)
    /// and whether a non-zero flags argument (e.g. AV_DICT_APPEND) is ever passed
    /// — the decompile body could not be retrieved this session (Ghidra timeout);
    /// modeled here as the standard overwrite (flags 0) against the options'
    /// `formatContextOptions`.
    func setAVDictOption(key: String, value: String) {
        options.formatContextOptions[key] = value
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
                let seekCMTime = CMTimeMake(value: Int64(self.currentPlaybackTime), timescale: 1)
                if let renderer = self.audioOutput as? AudioRendererPlayer {
                    renderer.flush(seekTime: seekCMTime)
                } else {
                    self.audioOutput.flush()
                }
                if let metalPlayView = self.videoOutput as? MetalPlayView {
                    metalPlayView.displayView.seek(to: seekCMTime)
                } else {
                    runOnMainThread { [weak self] in
                        guard let self else { return }
                        if let controlTimebase = self.videoOutput?.displayLayer.controlTimebase {
                            CMTimebaseSetTime(controlTimebase, time: seekCMTime)
                        }
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
            pipController?.invalidatePlaybackState()
        }
        // Atmos path only: when AudioRendererPlayer is the selected renderer, hard-gate
        // the start of the audio/video outputs on the renderer actually resolving to
        // AudioRendererPlayer (the spatial channel-negotiation swap may still be
        // settling). The binary dispatches this as a standalone MainActor task; the
        // default AVAudioEngine path is unaffected and starts via playOrPause() as usual.
        if KSOptions.audioPlayerType == AudioRendererPlayer.self, !(audioOutput is AudioRendererPlayer) {
            Task { @MainActor [weak self] in
                await self?.checkAudioRendererReady()
            }
        }
    }

    public func pause() {
        KSLog("pause \(self)")
        playbackState = .paused
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            pipController?.invalidatePlaybackState()
        }
    }

    public func shutdown() {
        KSLog("shutdown \(self)")
        playbackState = .stopped
        loadState = .idle
        isReadyToPlay = false
        loopCount = 0
        playerItem.shutdown()
        // RE: the binary separates the consolidated timing-metrics clear into
        // `options.resetOptions()` (reset() body, 0x1014234dc, witness [+0x310]).
        // The 11 inline timing-field zeroes that previously lived here ARE that
        // method's body; route through it so reset() and shutdown() share one
        // canonical reset (API-Surface-Preservation).
        options.resetOptions()
        if KSOptions.isClearVideoWhereReplace {
            if let metalPlayView = videoOutput as? MetalPlayView {
                metalPlayView.flushAndRemoveImage()
            } else {
                videoOutput?.flush()
            }
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
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .playing {
                self.play()
            }
            completionHandler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue pauseCommand: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping () -> Void) {
        guard pauseCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .paused {
                self.pause()
            }
            completionHandler()
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
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.loadState != .playable, let countDown = bufferingCommand.completionDueDate?.timeIntervalSinceNow else {
                completionHandler()
                return
            }
            self.bufferingCountDownTimer?.invalidate()
            self.bufferingCountDownTimer = nil
            self.bufferingCountDownTimer = Timer(timeInterval: countDown, repeats: false) { _ in
                completionHandler()
            }
        }
    }
}

extension KSMEPlayer: DisplayLayerDelegate {
    public func change(displayLayer: AVSampleBufferDisplayLayer) {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
            _pipController = KSPictureInPictureController(contentSource: contentSource)
            // 更改contentSource会直接crash
//            pipController?.contentSource = contentSource
        }
    }
}

public extension KSMEPlayer {
    func startRecord(url: URL) {
        playerItem.startRecord(url: url)
    }

    func stoptRecord() {
        playerItem.stopRecord()
    }
}
