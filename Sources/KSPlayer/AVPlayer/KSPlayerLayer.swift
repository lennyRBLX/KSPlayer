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
    func player(layer: KSPlayerLayer, url: URL)
    func playerDidEOF(layer: KSPlayerLayer)
    func playerOnTick(layer: KSPlayerLayer)
    func playerDidReplace(layer: KSPlayerLayer)
    func playerDidClear(layer: KSPlayerLayer)
    func playerDidAddSubtitle(_: UIView)
    func playerDidSelectSubtitle()
}

public extension KSPlayerLayerDelegate {
    func player(layer _: KSPlayerLayer, url _: URL) {}
    func playerDidEOF(layer _: KSPlayerLayer) {}
    func playerOnTick(layer _: KSPlayerLayer) {}
    func playerDidReplace(layer _: KSPlayerLayer) {}
    func playerDidClear(layer _: KSPlayerLayer) {}
    func playerDidAddSubtitle(_: UIView) {}
    func playerDidSelectSubtitle() {}
}

@MainActor
open class KSPlayerLayer: NSObject {
    public weak var delegate: KSPlayerLayerDelegate?
    @Published
    public var bufferingProgress: UInt8 = 0
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
                        // `start(layer:)` IS a protocol requirement, so no cast is needed — but it takes a
                        // KSComplexPlayerLayer, the only PiP-start entry the binary has. A plain KSPlayerLayer
                        // cannot be passed. `isPipActive` is itself source-only scaffolding (zero trie hits),
                        // so narrowing here is OURS, not a claim about Forward.
                        if let layer = self as? KSComplexPlayerLayer {
                            pipController.start(layer: layer)
                        }
                    }
                } else {
                    pipController.stop(restoreUserInterface: true)
                }
            }
        }
    }

    public private(set) var options: KSOptions
    // Binary field 5, between options and player. `KSPlayerLayer.subtitleView.getter :
    // KSPlayer.MetalSubtitleView` in the trie; the type already exists in Subtitle/.
    // internal, not public: MetalSubtitleView is an internal type, so `public` cannot compile.
    // The binary's access level for this field is not tool-readable (the impl oracle is
    // final-types-only and this class is open), so the narrowest spelling that builds is used.
    private(set) var subtitleView = MetalSubtitleView()

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

    public private(set) var url: URL {
        didSet {
            let firstPlayerType: MediaPlayerProtocol.Type
            if isWirelessRouteActive {
                // airplay的话，默认使用KSAVPlayer
                firstPlayerType = KSAVPlayer.self
            } else if options.display.isSphere {
                // AR模式只能用KSMEPlayer
                // swiftlint:disable force_cast
                firstPlayerType = NSClassFromString("KSPlayer.KSMEPlayer") as! MediaPlayerProtocol.Type
                // swiftlint:enable force_cast
            } else {
                firstPlayerType = KSOptions.firstPlayerType
            }
            if type(of: player) == firstPlayerType {
                if url == oldValue {
                    if isAutoPlay {
                        play()
                    }
                } else {
                    stop()
                    player.replace(url: url, options: options)
                    if isAutoPlay {
                        prepareToPlay()
                    }
                }
            } else {
                stop()
                player = firstPlayerType.init(url: url, options: options)
            }
        }
    }

    /// 播发器的几种状态

    // PROPERTY-WRAPPED in the binary: the trie carries `property wrapper backing initializer of
    // KSPlayer.KSPlayerLayer.state : KSPlayer.KSPlayerState` and a `property wrapped field init
    // accessor`, and the field record for the storage is named `_state`. A plain stored property
    // emits neither. @Published is the wrapper the rest of this class already uses.
    @Published
    public private(set) var state = KSPlayerState.initialized {
        willSet {
            if state != newValue {
                // The inlined observer logs 'state change <old> -> <new>' — both values, not just
                // the new one — and then calls change(state:), a real KSPlayerLayer method the
                // source did not declare. The delegate notification moves into it: the observer's
                // only two acts in the binary are this log and that call.
                KSLog("state change \(state) -> \(newValue)")
                change(state: newValue)
            }
        }
    }

    // Slot 58 @0x1019cc0ac, exported as `KSPlayer.KSPlayerLayer.change(state:)` — note the mangling
    // is `$s8KSPlayer0A5LayerC6change5state...`, with `0A5Layer` word-substituting "KSPlayer", which
    // is why a hand-built `13KSPlayerLayerC` spelling reads as a false trie negative.
    // OVERRIDDEN by KSComplexPlayerLayer, which carries its own change(state:).
    // UNRESOLVED → P8: the interior. All three of this body's callees — 0x10002d984, 0x101a04674
    // and 0x101a03fd4 — are real trie negatives, so what it does beyond notifying the delegate is
    // not read.
    // ⚑[tool=export_trie_oracle ref=change_state_callee:0x101a04674 result=NOT_IN_TRIE]
    open func change(state: KSPlayerState) {
        delegate?.player(layer: self, state: state)
    }

    private lazy var timer: Timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
            guard let self, self.player.isReadyToPlay else {
                return
            }
            self.delegate?.player(layer: self, currentTime: self.player.currentPlaybackTime, totalTime: self.player.duration)
            if self.player.playbackState == .playing, self.player.loadState == .playable, self.state == .buffering {
                // 一个兜底保护，正常不能走到这里
                self.state = .bufferFinished
            }
            if self.player.isPlaying {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.player.currentPlaybackTime
            }
        }
    }

    private var urls = [URL]()
    // Binary fields 9 and 10, between the `state` backing store and isAutoPlay.
    // `variable initialization expression of KSPlayerLayer.playerTickClock : Swift.ContinuousClock`
    // gives both the type and the fact that it carries a declaration default;
    // `KSPlayerLayer.playerTickTask.getter : Swift.Task<(), Swift.Never>?` gives the other.
    private var playerTickClock = ContinuousClock()
    private var playerTickTask: Task<(), Never>?
    var isAutoPlay: Bool
    private var isWirelessRouteActive = false
    private var bufferedCount = 0
    private var shouldSeekTo: TimeInterval = 0
    // RENAMED from the source's `startTime`: binary field 15 is `bufferingStartTime`, and this is the Double
    // that changeLoadState reads and clears.
    private var bufferingStartTime: TimeInterval = 0
    // Binary fields 16 and 17. `KSPlayerLayer.subtitleModel.getter : KSPlayer.SubtitleModel` and
    // `KSPlayerLayer.isAutoReplaceAndConstrainPlayerView.getter : Swift.Bool`.
    public private(set) var subtitleModel = SubtitleModel()
    public var isAutoReplaceAndConstrainPlayerView = false
    public init(url: URL, isAutoPlay: Bool = KSOptions.isAutoPlay, options: KSOptions, delegate: KSPlayerLayerDelegate? = nil) {
        self.url = url
        self.options = options
        self.delegate = delegate
        let firstPlayerType: MediaPlayerProtocol.Type
        if options.display.isSphere {
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
            registerRemoteControllEvent()
        }
        player.delegate = self
        player.contentMode = .scaleAspectFit
        if isAutoPlay {
            prepareToPlay()
        }
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

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            (player.pipController as? KSPictureInPictureController)?.contentSource = nil
        }
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().stopCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackRateCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipForwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipBackwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().enableLanguageOptionCommand.removeTarget(nil)
        options.playerLayerDeinit()
    }

    // ⚑ p2 OPTIONALITY DERIVED s102, closing divergence 1 of KSPlayerLayer_setUrlOptions_slot55_s84.
    //   The trie INDEX (57,138 names — the only complete source for an overload set) carries exactly
    //   TWO `KSPlayerLayer.set` symbols: this method and its `method descriptor`. So there is ONE
    //   overload, it has a vtable slot, and its second parameter mangles `AA9KSOptionsCSg` — Optional.
    //   ⚑[tool=export_trie_oracle ref=$s8KSPlayer0A5LayerC3set3url7optionsy10Foundation3URLV_AA9KSOptionsCSgtF:0x1019cb674 result=KSOptions-optional]
    //   The `if let` is read, not styled around the compiler: `cbz x24, 0x1019cb760` @0x1019cb6fc
    //   guards the options block, and the non-nil arm takes exclusive access on the field, reads the
    //   old value and stores the new one (`str x24,[x22,x21]` @0x1019cb71c) — i.e. `self.options =
    //   options`. The nil arm REJOINS at 0x1019cb760 rather than returning, and the non-nil block
    //   falls through to that same address, so only the assignment is guarded.
    // ⚑ BODY STILL DIVERGENT — divergence 2 of the same verdict is unaddressed here. The binary body
    //   is 251 instr (0x1019cb674-0x1019cba60) and does far more than these statements.
    public func set(url: URL, options: KSOptions?) {
        if let options {
            self.options = options
        }
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

    // FIVE SOURCE STATEMENTS ARE ABSENT FROM THE BINARY BODY and are removed here:
    //   · `runOnMainThread { UIApplication.shared.isIdleTimerDisabled = true }` — the extent's ONLY
    //     swift_allocObject is the seek completion box below, and there is no UIApplication reference;
    //   · `timer.fireDate = Date.distantPast`;
    //   · `state = player.loadState == .playable ? .bufferFinished : .buffering` — there is NO Combine
    //     Published SETTER anywhere in the extent; all four `state` touches are getter reads;
    //   · `MPNowPlayingInfoCenter.default().playbackState = .playing`;
    //   · `KSPictureInPictureController.mute()` — and that method does not exist in the binary at all.
    // ORDER: the binary's very first instruction pair writes isAutoPlay, so it leads the body.
    // GUARD: the binary's prepareToPlay guard has a THIRD arm reaching the same call —
    // `state == .playedToTheEnd && !player.seekable`.
    open func play() {
        isAutoPlay = true
        if state == .error || state == .initialized || (state == .playedToTheEnd && !player.seekable) {
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
        }
    }

    open func pause() {
        isAutoPlay = false
        player.pause()
    }

    // SIX SOURCE STATEMENTS HAVE NO COUNTERPART and are removed: bufferedCount = 0,
    // shouldSeekTo = 0, player.playbackRate = 1, player.playbackVolume = 1, the
    // MPNowPlayingInfoCenter clear, and the isIdleTimerDisabled runOnMainThread block.
    // THREE STATEMENTS EXIST ONLY IN THE BINARY and are added: the subtitleModel clear, the
    // subtitleView removal, and options.playerLayerDeinit().
    // THE LOG ARGUMENT DIFFERS: the binary builds "stop " + self.description — it sends objc
    // `description` to self and bridges the NSString before appending — not a plain literal.
    public func stop() {
        KSLog("stop \(self)")
        state = .initialized
        player.stop()
        // UNRESOLVED → P8: the subtitleModel call the binary makes here with (nil, nil). Its callee
        // 0x101ab2540 is 507 instructions and a real trie negative, so it is pinned, not named.
        // ⚑[tool=export_trie_oracle ref=subtitle_clear:0x101ab2540 result=NOT_IN_TRIE]
        subtitleModel.selectedSubtitleInfo = nil
        subtitleView.removeFromSuperview()
        options.playerLayerDeinit()
    }

    // Forward 1.3.17 declares TWO overridable seeks, idx64 slot91 and idx65 slot92 (VTableOffset 27).
    // Both carry a method descriptor, so both are class-body declarations; the one-argument
    // seek(time:) at the bottom of this file has NO method descriptor, which is why it stays an
    // extension member.
    open func seek(time: TimeInterval, completion: (@MainActor @Sendable (Bool) -> Void)?) {
        seek(time: time, autoPlay: options.isSeekedAutoPlay, completion: completion)
    }

    // THE NON-FINITE ARM RETURNS. The source fell through into the isReadyToPlay test; the binary's
    // arm is `cbnz x19 -> completion(false)` followed by `b` to the epilogue, and no edge re-enters
    // the finite path.
    // THE DISTANCE SHORT-CIRCUIT was missing from the source entirely. At 0x1019cd154 the binary
    // computes `fabd d0, d8, d9` — |time - player.currentPlaybackTime| — then `fmov d1, #1.0`,
    // `fcmp d0, d1`, `b.pl` away. So below 1.0 it plays (when autoPlay), completes with TRUE and
    // returns, never reaching player.seek.
    open func seek(time: TimeInterval, autoPlay: Bool, completion: (@MainActor @Sendable (Bool) -> Void)?) {
        if time.isInfinite || time.isNaN {
            completion?(false)
            return
        }
        if player.isReadyToPlay, player.seekable {
            if abs(time - player.currentPlaybackTime) < 1.0 {
                if autoPlay {
                    play()
                }
                completion?(true)
                return
            }
            // Called immediately before the player seek; subtitleModel is binary field 16.
            subtitleModel.invalidateParts()
            player.seek(time: time) { [weak self] finished in
                guard let self else { return }
                if finished, autoPlay {
                    self.play()
                }
                completion?(finished)
            }
        } else {
            isAutoPlay = autoPlay
            shouldSeekTo = time
            completion?(false)
        }
    }

    // The eight members below are CLASS-BODY declarations in Forward 1.3.17, not extension
    // members: each occupies a slot in KSPlayerLayer's vtable (descriptor 0x1039ecf38,
    // VTableDescriptorHeader 0x1039ecf70, VTableSize 82), and a Swift extension member never
    // receives a vtable slot. They were previously written into extensions below. Declaration
    // order follows the vtable: 68 prepareToPlay 0x1019cd5e0, 69 readyToPlay 0x1019cda08,
    // 70 changeLoadState 0x1019ce474, 71 changeBuffering 0x1019ce730, 72 playBack 0x1019ce740,
    // 74 finish 0x1019ce7d0, 78 wirelessRouteActiveDidChange 0x1019cedcc,
    // 79 audioInterrupted 0x1019cef60. Bodies are unchanged by this move.
    // ⚑[tool=vtable_walk ref=KSPlayerLayer:0x1039ecf38 result=82-slots-vtable-offset-27]
    // TWO OF THE FOUR SOURCE STATEMENTS ARE ABSENT and are removed: `bufferingStartTime =
    // CACurrentMediaTime()` — the body contains no time call of any kind — and `bufferedCount = 0`,
    // which would be a store to a field of self, and the extent has none outside the Published
    // setter.
    open func prepareToPlay() {
        state = .preparing
        player.prepareToPlay()
    }

    public func readyToPlay(player: some MediaPlayerProtocol) {
        state = .readyToPlay
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
                (player.pipController as? KSPictureInPictureController)?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        }
        #endif
        updateNowPlayingInfo()
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

    // THE `bufferedCount == 0` BLOCK IS A DIFFERENT PIECE OF CODE. The source built an 8-to-11
    // entry timing dictionary out of options.dnsStartTime / tcpStartTime / tcpConnectedTime /
    // openTime / findTime / readyTime / readVideoTime / readAudioTime / decodeVideoTime /
    // decodeAudioTime and called KSLog(dic). The binary has NO KSLog anywhere in this body and
    // reads none of those timing fields; it reads `player.subtitleDataSource` and, when non-nil,
    // appends it into self.subtitleModel.
    // NESTING: the binary tests loadState, then bufferedCount == 0, then SEPARATELY
    // bufferingStartTime > 0 — the source guarded loadState and the time together — and it
    // increments bufferedCount TWICE, once in the bufferedCount == 0 block and once after the
    // delegate call.
    // THE SECOND GUARD TESTS A DIFFERENT OBJECT: the binary re-reads the PLAYER's playbackState,
    // not the layer's own `state`, and carries a `.paused -> state = .paused` arm the source
    // lacked before requiring `.playing`.
    public func changeLoadState(player: some MediaPlayerProtocol) {
        guard player.playbackState != .seeking else { return }
        if player.loadState == .playable {
            if bufferedCount == 0 {
                if let subtitleDataSource = player.subtitleDataSource {
                    subtitleModel.addSubtitle(dataSource: subtitleDataSource)
                }
                bufferedCount += 1
            }
            if bufferingStartTime > 0 {
                let diff = CACurrentMediaTime() - bufferingStartTime
                delegate?.player(layer: self, bufferedCount: bufferedCount, consumeTime: diff)
                bufferedCount += 1
                bufferingStartTime = 0
            }
        }
        if player.playbackState == .paused {
            state = .paused
        }
        guard player.playbackState == .playing else { return }
        if player.loadState == .playable {
            state = .bufferFinished
        } else {
            if state == .bufferFinished {
                bufferingStartTime = CACurrentMediaTime()
            }
            state = .buffering
        }
    }

    public func changeBuffering(player _: some MediaPlayerProtocol, progress: UInt8) {
        bufferingProgress = progress
    }

    public func playBack(player _: some MediaPlayerProtocol, loopCount: Int) {
        self.loopCount = loopCount
    }

    // THE SECOND-PLAYER FALLBACK IS ABSENT from the binary: the error arm goes straight from the
    // error retain to the state write, with no type(of:) comparison and no KSOptions read. Three
    // further statements are absent too — `timer.fireDate = Date.distantFuture`, `bufferedCount = 1`
    // (the extent stores to no field of self except through the Published setter) and the
    // `if error == nil { nextPlayer() }` tail.
    // ORDER: on the nil arm the binary writes state BEFORE reading player.duration and calling the
    // delegate; the source had it the other way round.
    // LOG OVERLOAD: the binary converts with Foundation._convertErrorToNSError and logs through the
    // __C.NSObject : CustomStringConvertible conformance — that is `KSLog(_ error: Error)`
    // (KSOptions.swift:985), not the `CustomStringConvertible` overload the source used, which would
    // have carried the error existential directly.
    public func finish(player: some MediaPlayerProtocol, error: Error?) {
        if let error {
            state = .error
            KSLog(error)
        } else {
            state = .playedToTheEnd
            let duration = player.duration
            delegate?.player(layer: self, currentTime: duration, totalTime: duration)
        }
        delegate?.player(layer: self, finish: error)
    }

    #if canImport(UIKit) && !os(xrOS)
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
    @objc private func audioInterrupted(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }
        // The binary logs the interruption before switching on it; the source had no KSLog here at all.
        KSLog("[audio] audioInterrupted \(type)")
        switch type {
        case .began:
            pause()

        case .ended:
            // An interruption ended. Resume playback, if appropriate.

            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // THE RESUME IS DELAYED. The source called play() bare; the binary wraps it in a Task
                // that first awaits Task.sleep(nanoseconds: 800_000_000) and only then runs play() on
                // the MainActor, through a weak self.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self?.play()
                }
            }

        default:
            break
        }
    }
    #endif
}

// MARK: - MediaPlayerDelegate

// The five witnesses (readyToPlay, changeLoadState, changeBuffering, playBack, finish) are
// declared in the class body above, where their vtable slots put them. Where Forward 1.3.17
// declares the CONFORMANCE itself is not decidable from the binary, so it is left exactly where
// this reconstruction already had it rather than moved onto the class line.
extension KSPlayerLayer: MediaPlayerDelegate {}

// MARK: - AVPictureInPictureControllerDelegate

@available(tvOS 14.0, *)
extension KSPlayerLayer: @preconcurrency AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        player.pipController?.stop(restoreUserInterface: false)
    }

    public func pictureInPictureController(_: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler _: @escaping (Bool) -> Void) {
        isPipActive = false
    }
}

// MARK: - private functions

extension KSPlayerLayer {
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

    private func nextPlayer() {
        if urls.count > 1, let index = urls.firstIndex(of: url), index < urls.count - 1 {
            isAutoPlay = true
            url = urls[index + 1]
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

    public func registerRemoteControllEvent() {
        let remoteCommand = MPRemoteCommandCenter.shared()
        remoteCommand.playCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.play()
            return .success
        }
        remoteCommand.pauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.pause()
            return .success
        }
        remoteCommand.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            if self.state.isPlaying {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }
        remoteCommand.stopCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.player.stop()
            return .success
        }
        remoteCommand.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.nextPlayer()
            return .success
        }
        remoteCommand.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.previousPlayer()
            return .success
        }
        remoteCommand.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            self.options.isLoopPlay = event.repeatType != .off
            return .success
        }
        remoteCommand.changeShuffleModeCommand.isEnabled = false
        // remoteCommand.changeShuffleModeCommand.addTarget {})
        remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
        remoteCommand.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self.player.playbackRate = event.playbackRate
            return .success
        }
        remoteCommand.skipForwardCommand.preferredIntervals = [15]
        remoteCommand.skipForwardCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            self.seek(time: self.player.currentPlaybackTime + event.interval)
            return .success
        }
        remoteCommand.skipBackwardCommand.preferredIntervals = [15]
        remoteCommand.skipBackwardCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            self.seek(time: self.player.currentPlaybackTime - event.interval)
            return .success
        }
        remoteCommand.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(time: event.positionTime)
            return .success
        }
        remoteCommand.enableLanguageOptionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeLanguageOptionCommandEvent else {
                return .commandFailed
            }
            let selectLang = event.languageOption
            if selectLang.languageOptionType == .audible,
               let trackToSelect = self.player.tracks(mediaType: .audio).first(where: { $0.name == selectLang.displayName })
            {
                self.player.select(track: trackToSelect)
            }
            return .success
        }
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
}

// KSComplexPlayerLayer — a Forward-NEW class, absent from this reconstruction until now, and the
// reason KSPictureInPictureController could not be reduced (see that file's header). Nominal type
// descriptor 0x1039ed208; superclass_conformance_gate reads `super=KSPlayerLayer`.
//
// THE FIELD SET IS COMPLETE AND EXACT: dump_binary_field_types reports "total fields: 3", and all
// three carry a `variable initialization expression` in the trie, so all three have declaration
// defaults. Order is __swift5_fieldmd order.
//
// THE MEMBER SET IS NOT COMPLETE HERE. The trie carries 44 symbols under
// `KSPlayer.KSComplexPlayerLayer.`, including change(state:), finish(player:error:),
// readyToPlay(player:), pipStart(), play/pause/stop, playNextURL(), reCheckSubtitle(),
// set(urls:), register/removeRemoteControllEvent() and the six AVPictureInPictureControllerDelegate
// callbacks. Those are DECLARED NOWHERE YET — this unit reconstructs the class's SHAPE so that
// `KSPictureInPictureProtocol` can name it, which is what unblocks KSMEPlayer.pipController. Their
// bodies are a separate unit; writing them from the member list alone would be invention.
// ⚑[tool=export_trie_oracle ref=KSPlayer.KSComplexPlayerLayer:0x1039ed208 result=44-symbols-shape-only]
//
// Placement in this file follows the superclass, NOT a #fileID literal — no body of this class has
// been decompiled far enough to surface one.
public class KSComplexPlayerLayer: KSPlayerLayer {
    public var urls: [URL] = []
    public var isPictureInPictureStoped: Bool = false
    // private, and the trie prints the module-hash discriminator on all three accessors:
    // `(enterBackgroundTask in _B3181C2628785004269C41BC3433122F) : Swift.Task<(), Swift.Never>?`
    private var enterBackgroundTask: Task<(), Never>?
}
