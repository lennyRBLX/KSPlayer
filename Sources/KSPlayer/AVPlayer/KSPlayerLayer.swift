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

    /// ⚑ 0x10000e52c — a bare `ret`. The body is empty; `time` is never read.
    /// The address is heavily ICF-folded (it is the image's canonical empty body), so it carries
    /// no information unique to this method beyond the fact that the method does nothing — which
    /// is the whole of what is declared here. Signature from the trie:
    /// `KSPlayer.KSPlayerLayer.preview(time: Swift.Double?) -> ()`.
    open func preview(time _: Double?) {}

    /// ⚑ 0x10000e52c — a bare `ret`, the same canonical empty body as `preview` above. The
    /// parameter is never read.
    /// Trie: `KSPlayer.KSPlayerLayer.updateUIView(__C.UIView) -> ()` — ONE unlabelled parameter.
    /// It is NOT SwiftUI's `UIViewRepresentable.updateUIView(_:context:)`, which takes a second
    /// `context` argument; this is a plain method that happens to share the base name.
    /// `UIView` resolves on every platform here: PlayerDefines declares
    /// `public typealias UIView = NSView` in its non-UIKit branch.
    open func updateUIView(_: UIView) {}

    /// ⚑ 0x1019ceaf4 is a 3-instruction thunk (`mov x0,x1 / mov x1,x2 / b 0x1019d58f8`); the body
    /// is the 32 instructions there, read in full. Every callee named from the bind table:
    ///   swift_unknownObjectWeakLoadStrong  ⚑[tool=bind_oracle ref=0x1041130e8 result=libswiftCore]
    ///   swift_getObjectType                ⚑[tool=bind_oracle ref=0x104112f08 result=libswiftCore]
    ///   swift_unknownObjectRelease         ⚑[tool=bind_oracle ref=0x1041130a0 result=libswiftCore]
    /// Shape: weak-load `delegate`, return if nil, then dispatch witness-table slot +0x48 with
    /// self, then release. The `?.` is the nil check; the retain/release pair is what a weak load
    /// compiles to, not source.
    ///
    /// SLOT +0x48 WAS DECODED, NOT COUNTED off the protocol's declaration order — FrameOutput
    /// proved that order can be wrong. Coordinator's KSPlayerLayerDelegate witness table
    /// (0x1041d4d18, conformance descriptor 0x103567f38) has 11 requirements, and +0x48 is index
    /// 8. Reqs 0-4 carry real bodies and 5-10 all carry the canonical empty body 0x10000e52c —
    /// which matches this protocol exactly: five `player(...)` requirements Coordinator
    /// implements, six with empty extension defaults it does not. That 5/6 split is what
    /// corroborates the ordering, so index 8 is `playerDidClear(layer:)`.
    /// ⚑[tool=decode_witness_table ref=Coordinator:KSPlayerLayerDelegate:0x1041d4d18 result=req8]
    open func playerDidClear(player _: some MediaPlayerProtocol) {
        delegate?.playerDidClear(layer: self)
    }
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
                let oldView = oldValue.view
                if let superview = oldView.superview {
                    let view = player.view
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
                oldValue.view.removeFromSuperview()
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
            if let window = player.view.window {
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

    /// ⚑[tool=export_trie_oracle ref=KSPlayerLayer.pipStop(restoreUserInterface:):0x1019ced14 result=46-instr]
    /// `player` comes from its own `vpWvd` (offset global 0x104c634f0) and is loaded as the
    /// non-optional (instance, witness-table) pair with no null test, exactly as in `makeUIView`.
    ///
    /// BOTH witness slots are NAMED, neither is counted — the same discipline `makeUIView` needed,
    /// because this protocol's indices are shifted by unrecovered requirements:
    ///   · `ldr x24,[x21,#0xf8]` → witness 30 of MediaPlayerProtocol. `KSMEPlayer`'s table
    ///     (0x1041d7c68) names it `KSPlayer.KSMEPlayer.pipController.getter :
    ///     (any KSPictureInPictureProtocol)?`. Its result is a two-word optional existential, and
    ///     the `cbz x20` that follows is the `?.`.
    ///   · the second dispatch reloads the witness table from THAT result (`x21` is reassigned to
    ///     the returned `x1`), so `ldr x8,[x21,#0x48]` is witness 8 of KSPictureInPictureProtocol,
    ///     not of MediaPlayerProtocol. `KSPictureInPictureController`'s table (0x1041d45a0) names
    ///     it `stop(restoreUserInterface:)`.
    ///   · `and w0, w19, #0x1` narrows the incoming Bool to its low bit and passes it as that
    ///     call's only argument, which is what fixes the argument as `restoreUserInterface`.
    /// ⚑[tool=decode_witness_table ref=KSMEPlayer:MediaPlayerProtocol:0x1041d7c68 result=slot30=pipController.getter]
    /// ⚑[tool=decode_witness_table ref=KSPictureInPictureController:KSPictureInPictureProtocol:0x1041d45a0 result=slot8=stop(restoreUserInterface:)]
    public func pipStop(restoreUserInterface: Bool) {
        player.pipController?.stop(restoreUserInterface: restoreUserInterface)
    }

    /// @0x1019d007c, 47 instructions. Trie: `KSPlayerLayer.isPictureInPictureActive.getter
    /// : Swift.Bool`. It carries a `vpMV`, so it is public; there is no `vs` setter, so it is
    /// get-only, and no `Tq`, so it is not an overridable requirement.
    ///
    /// The body is `pipStop`'s shape with the tail swapped, and it reuses that member's two
    /// already-named witness slots rather than counting new ones:
    ///   · offset global 0x104c634f0 is `player`'s own `vpWvd`; `swift_beginAccess` is called with
    ///     flags (0, 0) — a READ — and `ldp x21, x19, [x19]` takes the (instance, witness-table)
    ///     pair with no null test, so `player` is the non-optional existential here too.
    ///   · `ldr x23,[x19,#0xf8]` is witness 30 of MediaPlayerProtocol =
    ///     `pipController.getter : (any KSPictureInPictureProtocol)?`, and the `cbz x20` on its
    ///     first returned word is the `?.`.
    ///   · the second dispatch reloads the witness table from THAT result, so `ldr x8,[x19,#0x8]`
    ///     is witness 0 of KSPictureInPictureProtocol, not of MediaPlayerProtocol. That table
    ///     (0x1041d45a0) puts req0 at 0x1019c7680, whose whole body is one `objc_msgSend` whose
    ///     selref 0x10440be40 decodes to `isPictureInPictureActive` — the same-named requirement,
    ///     confirmed by selector rather than assumed from the name matching.
    ///   · the `cbz` arm sets `w19 = 0` and both arms fall into `and w0, w19, #0x1`, which is the
    ///     `?? false`.
    /// ⚑[tool=decode_objc_selector ref=0x10440be40 result=isPictureInPictureActive]
    /// ⚑[tool=decode_witness_table ref=KSPictureInPictureController:KSPictureInPictureProtocol:0x1041d45a0 result=req0=0x1019c7680]
    public var isPictureInPictureActive: Bool {
        player.pipController?.isPictureInPictureActive ?? false
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayerLayer.makeUIView():0x1019cb5f4 result=32-instr]
    /// Mangled `…0A5LayerC10makeUIViewSo0D0CyF` — returns `UIView`, non-optional.
    ///
    ///   · offset global 0x104c634f0 is `player`'s own `vpWvd`
    ///     (`…0A5LayerC6playerAA19MediaPlayerProtocol_pvpWvd`), read by name. That type has no
    ///     `Sg`, so `player` is a non-optional existential — matching the body, which does
    ///     `ldp x20, x19, [x19]` for the (instance, witness-table) pair with NO null test.
    ///   · `ldr x22,[x19,#0x28]` selects witness 4 and `blr` returns its result unchanged.
    ///
    /// ⚑ Witness 4 is NAMED, not counted — which matters, because MediaPlayerProtocol's indices
    ///   are shifted by unrecovered requirements and an index argument would be worthless here.
    ///   `KSMEPlayer : MediaPlayerProtocol` slot 4 is `KSPlayer.KSMEPlayer.view.getter : UIView`.
    ///   That is also what forced the requirement's type correction above: the getter mangles
    ///   `So6UIViewCvg` with no `Sg`, and property witnesses are invariant, so the requirement is
    ///   `UIView`. Without that correction this body could only be spelled with a force-unwrap
    ///   the binary does not contain.
    /// ⚑[tool=decode_witness_table ref=KSMEPlayer:MediaPlayerProtocol:0x1041d7c68 result=slot4=view.getter:UIView]
    public func makeUIView() -> UIView {
        player.view
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayerLayer.reachEndOfStream(player:):0x1019ce750 result=32-instr]
    /// The generic `player` parameter is UNUSED — the body never touches the generic triple, only
    /// `self` and the delegate — so it is spelled `_`.
    ///
    ///   · offset global 0x1044e6138 is `delegate`'s own `vpWvd`
    ///     (`…0A5LayerC8delegateAA0aB8Delegate_pSgvpWvd`), read by name, not inferred.
    ///   · `bl 0x10345d180` → __got 0x1041130e8 → `swift_unknownObjectWeakLoadStrong`, and the
    ///     `cbz x0` on its result is the `?.` — this is the weak delegate load, which is why the
    ///     whole call is skipped when the delegate has been released.
    ///     ⚑[tool=bind_oracle ref=__got:0x1041130e8 result=swift_unknownObjectWeakLoadStrong]
    ///   · `ldr x19,[x19,#0x8]` takes the existential's witness table, then `ldr x8,[x19,#0x30]`
    ///     selects the witness and `blr` passes `self` with the loaded delegate as swiftself.
    ///
    /// ⚑ THE WITNESS INDEX IS SAFE HERE, and it is worth saying why, because the same move is NOT
    ///   safe on MediaPlayerProtocol. `decode_witness_table` reads witness *i* at `wt + 8 + 8i`, so
    ///   `#0x30` is index 5. KSPlayerLayerDelegate's requirement kinds are `FFFFFFFFFFF` — ELEVEN
    ///   requirements, every one a Method, no properties to expand into accessor triples and no
    ///   BaseProtocol slot — and the source declares exactly eleven methods. The counts and kinds
    ///   agree exactly, so index 5 is unambiguously the sixth, `playerDidEOF(layer:)`, which is
    ///   also what an end-of-stream notification should call.
    ///   ⚑[tool=protocol_signature ref=KSPlayerLayerDelegate:0x1039ecebc result=11-methods-exact-match]
    ///
    /// ⚑ NOT a MediaPlayerDelegate conformance method, despite the shape: that protocol does not
    ///   declare it. It carries its own `…Tq` method descriptor, i.e. a new overridable slot on
    ///   this class. (Separately, MediaPlayerDelegate's descriptor reports EIGHT requirements
    ///   against the source's five — three unrecovered methods — but nothing shows this is one of
    ///   them, so it was not added there.)
    public func reachEndOfStream(player _: some MediaPlayerProtocol) {
        delegate?.playerDidEOF(layer: self)
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
// ⚑ s106: placement is now CONFIRMED BY A #fileID, no longer merely inherited from the superclass.
// The note this replaces said "no body of this class has been decompiled far enough to surface
// one" — the PIP-error callback below is that body: its KSLog passes the literal
// 'KSPlayer/KSPlayerLayer.swift' (count 28), which is this file.
// ⚑[tool=decode_string_literal ref=KSComplexPlayerLayer.pictureInPictureController:0x1019d6430 result='KSPlayer/KSPlayerLayer.swift']
public class KSComplexPlayerLayer: KSPlayerLayer {
    public var urls: [URL] = []
    public var isPictureInPictureStoped: Bool = false
    // private, and the trie prints the module-hash discriminator on all three accessors:
    // `(enterBackgroundTask in _B3181C2628785004269C41BC3433122F) : Swift.Task<(), Swift.Never>?`
    private var enterBackgroundTask: Task<(), Never>?

    /// @0x1019d1bc0, 68 instructions. `override` is not inferred from the superclass having a
    /// `pause()` — `override_table.py --class KSComplexPlayerLayer --impl 0x1019d1bc0` answers
    /// YES at index 4, i.e. this address is an Impl in the class's own override table.
    ///
    ///   · `strb wzr` through offset global 0x104c63520 is the first statement. That global is NOT
    ///     `urls`, which is trie-pinned at 0x104c63528 — the three globals are not in field-record
    ///     order, so position proves nothing here. The BYTE store does: of this class's three
    ///     fields only `isPictureInPictureStoped` is a Bool, and `wzr` makes it `false`.
    ///   · `player` (offset global 0x104c634f0) is read under a (0, 0) beginAccess and dispatched
    ///     at witness offset 0x128. KSMEPlayer's MediaPlayerProtocol table (0x1041d7c68) holds a
    ///     thunk there whose whole body is `b 0x101a4390c` = `KSMEPlayer.pause()`, so the slot is
    ///     `pause()`.
    ///   · the MediaPlayer classref 0x104410a10 is `MPNowPlayingInfoCenter`; selref 0x10440b040 is
    ///     `defaultCenter` and selref 0x10440d8c8 is `setPlaybackState:` with the immediate 2,
    ///     which is `MPNowPlayingPlaybackState.paused`.
    ///   · `player` is re-read and dispatched at 0xf8 — `pipController.getter`, the same slot
    ///     `pipStop` and `isPictureInPictureActive` use — and the `cbz` on its first word is the
    ///     `?.`. The final dispatch is at offset 0x28 of THAT result's table, i.e. req4 of
    ///     KSPictureInPictureProtocol = `invalidatePlaybackState`.
    /// ⚑ req4 is a REAL requirement of the binary protocol but is pinned rather than declared, for
    ///   the availability reason recorded in KSPictureInPictureController.swift. The concrete
    ///   downcast below is OURS, not the binary's — the binary dispatches through the witness
    ///   table. It is the spelling `KSMEPlayer.play()` already uses for this same requirement, so
    ///   the two call sites stay consistent rather than each inventing a workaround.
    /// ⚑[tool=override_table ref=KSComplexPlayerLayer.pause:0x1019d1bc0 result=YES-index-4]
    /// ⚑[tool=decode_objc_selector ref=0x10440d8c8 result=setPlaybackState:]
    /// ⚑[tool=decode_witness_table ref=KSMEPlayer:MediaPlayerProtocol:0x1041d7c68 result=slot0x128=pause]
    override public func pause() {
        isPictureInPictureStoped = false
        player.pause()
        MPNowPlayingInfoCenter.default().playbackState = .paused
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            (player.pipController as? KSPictureInPictureController)?.invalidatePlaybackState()
        }
    }

    /// @0x1019d1a8c, 77 instructions. The `pause()` MIRROR, and the two corroborate each other at
    /// every shared address — but the shapes are NOT symmetric and the asymmetry is read, not
    /// assumed: `play()` calls `super.play()` where `pause()` calls `player.pause()` through the
    /// witness, and `play()` writes no field where `pause()` clears `isPictureInPictureStoped`.
    ///
    ///   · `bl 0x1019cc5f8` is a DIRECT call to `KSPlayer.KSPlayerLayer.play() -> ()`, named in the
    ///     trie. A direct (non-virtual) call to the superclass's own implementation of the method
    ///     this address overrides is `super.play()`. `override` is not inferred from that: it is
    ///     ⚑[tool=override_table ref=KSComplexPlayerLayer.play:0x1019d1a8c result=YES-index-3].
    ///   · classref 0x104410a10 is `MPNowPlayingInfoCenter`; the sends are `defaultCenter` then
    ///     `setPlaybackState:` with the immediate **1**. `pause()` reads 2 = `.paused` at the same
    ///     pair of selrefs, so 1 = `.playing` — the pairing is what makes both readings evidence
    ///     rather than one lookup. (`MPNowPlayingPlaybackState` is an imported NS_ENUM, so what
    ///     crosses `objc_msgSend` is the rawValue, not a Swift case index.)
    ///   · `player` (offset global 0x104c634f0, its own `vpWvd`) is read under a (0, 0)
    ///     beginAccess and dispatched at witness offset **0xf8** — `pipController.getter`, the same
    ///     slot `pause`, `pipStop` and `isPictureInPictureActive` use — and the `cbz x20` on the
    ///     first word of the returned two-word optional existential is the `?.`.
    ///   · the dispatch on THAT result is at offset **0x28** of its table = req4 of
    ///     KSPictureInPictureProtocol = `invalidatePlaybackState`, identical to `pause()`.
    ///   · the tail is offset **0x50** of `static KSOptions.pictureInPictureType`'s table (global
    ///     0x104c632c0, read under its own `swift_once` at token 0x1044e5178 with initialiser
    ///     0x1019bc7a8). 0x50 = 8*10, and word 0 of a witness table is the conformance descriptor,
    ///     so that is **req9** — `static play(layer: KSComplexPlayerLayer)`. The call passes
    ///     `x0 = self` with the METATYPE in x20 (swiftself), which is the static-method shape, and
    ///     the result is discarded because req9's witness is the bare-`ret` ICF fold, i.e. empty.
    /// ⚑[tool=decode_witness_table ref=KSPictureInPictureController:KSPictureInPictureProtocol:0x1041d45a0 result=req9@0x50=static-play]
    /// ⚑[tool=bind_oracle ref=0x104410a10 result=_OBJC_CLASS_$_MPNowPlayingInfoCenter]
    /// ⚑ The `#available` guard and the concrete `as?` downcast are OURS, carried over verbatim
    ///   from `pause()` above: the binary dispatches through the witness table and emits no
    ///   version check. req4 is iOS 15 while the protocol is tvOS 14, so every call site needs the
    ///   guard to compile. Keeping the two spellings identical is deliberate — see the note on
    ///   `pause()` for why this file does not let each call site invent its own workaround.
    override public func play() {
        super.play()
        MPNowPlayingInfoCenter.default().playbackState = .playing
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            (player.pipController as? KSPictureInPictureController)?.invalidatePlaybackState()
        }
        KSOptions.pictureInPictureType.play(layer: self)
    }

    /// @0x1019d1890, 127 instructions. `override` is read, not inferred from the superclass having
    /// a `change(state:)`: ⚑[tool=override_table ref=KSComplexPlayerLayer.change:0x1019d1890 result=YES-index-2]
    ///
    /// THE BODY IS THE SUPERCLASS'S 115-INSTRUCTION `change(state:)` FOLLOWED BY ONE STATEMENT.
    /// Instruction for instruction, 0x1019d1890+0 .. +0x1b4 is `KSPlayerLayer.change(state:)`
    /// @0x1019cc0ac: the same `str xzr` through offset global 0x1044e6190, the same
    /// `NSThread.isMainThread` fork, the same two arms (`MainActor.assumeIsolated` @0x101a04674 and
    /// `swift_task_create` @0x101a03fd4), the SAME closure body @0x1019cc278, and the same weak
    /// `delegate` load and witness dispatch. The subclass then adds 12 instructions the superclass
    /// does not have. Nothing else differs.
    ///
    /// ⚑ THE SUPER CALL IS INLINED, NOT EMITTED — there is no `bl 0x1019cc0ac` here, so this is a
    ///   READING and not a direct observation, and it is recorded as such. `play()` above proves a
    ///   `super.` call CAN survive as a direct `bl`, but the superclass's `play()` is 186
    ///   instructions against `change(state:)`'s 115, so an inliner threshold between the two is
    ///   consistent with both. What decides it is that the alternative — the author re-writing all
    ///   four of the superclass's statements here — would put four statements in THIS file that
    ///   nothing in the binary distinguishes from the superclass's own. `super.change(state:)` adds
    ///   none. That is the spelling with no invented content, so it is the one written.
    /// ⚑[tool=function_extents ref=KSPlayerLayer.change:0x1019cc0ac result=115-instr]
    /// ⚑[tool=body_fingerprint ref=KSComplexPlayerLayer.change:0x1019d1890 result=superclass-prefix-plus-12]
    ///
    /// ⚑ The superclass's interior is NOT reproduced here and is NOT this row's debt: the
    ///   `str xzr` at 0x1019cc114 goes through offset global 0x1044e6190, which is a genuine
    ///   2-way tie on KSPlayerLayer and stays OPEN under the session-113 A1 rule — it is
    ///   `double`-class (`str d8` in `seek(time:autoPlay:completion:)` @0x1019cd038, `ldr d8` in
    ///   `readyToPlay(player:)` @0x1019cda08), and the only two Double fields on the class are
    ///   `shouldSeekTo` and `bufferingStartTime`, NEITHER of which carries a vpWvd.
    /// ⚑[tool=recover_field_by_access ref=KSPlayerLayer:0x1044e6190 result=AMBIGUOUS-2]
    ///
    /// The one added statement, read in full at 0x1019d1a44-0x1019d1a70:
    ///   · `tst w19, #0xff` / `b.ne` — the same guard the body opens with, on the low byte of
    ///     `state`. KSPlayerState's case 0 is `.initialized`, so this arm runs on `.initialized`.
    ///     ⚠️ It is a SECOND, separate test: the delegate notification at the join is reached from
    ///     both edges of the first one, so it is unconditional and this guard covers only the
    ///     statement below it.
    ///   · classref 0x104410a10 is `MPNowPlayingInfoCenter` — the same classref `pause()` and
    ///     `play()` above already use — then `defaultCenter`, i.e. `.default()`.
    ///   · the send is `setNowPlayingInfo:` with `x2 = #0x0`, so the assigned value is **nil**.
    /// ⚑[tool=bind_oracle ref=0x104410a10 result=_OBJC_CLASS_$_MPNowPlayingInfoCenter]
    /// ⚑[tool=decode_objc_selector ref=0x10440d808 result=setNowPlayingInfo:]
    /// ⚑[tool=decode_objc_selector ref=0x10440b040 result=defaultCenter]
    /// ⚑ ACCESS is not independently provable for a method — see the note on
    ///   `removeRemoteControllEvent()` below. `public` is what the two overrides above this one
    ///   use for the same situation (an override of an `open` superclass method), and this file
    ///   does not let each override pick its own spelling.
    override public func change(state: KSPlayerState) {
        super.change(state: state)
        if state == .initialized {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    /// The trie address 0x1019d27a4 is a ONE-instruction thunk (`b 0x1019d5d38`); the body is the
    /// 181 instructions there. ⚑[tool=function_extents ref=KSComplexPlayerLayer.removeRemoteControllEvent:0x1019d5d38 result=181-instr]
    ///
    /// Twelve statements, all of one shape and every piece of each one decoded:
    ///   · classref 0x104410a18 is `MPRemoteCommandCenter`; the receiver comes from
    ///     `_objc_opt_self` on it and then a `sharedCommandCenter` send, i.e. `.shared()`.
    ///   · the twelve command selectors, IN THIS ORDER, are the twelve sends between them:
    ///     play, pause, togglePlayPause, stop, nextTrack, previousTrack, changeRepeatMode,
    ///     changePlaybackRate, skipForward, skipBackward, changePlaybackPosition,
    ///     enableLanguageOption.
    ///   · every `removeTarget:` passes `x2 = #0x0`. The argument is **nil**, not `self` — the
    ///     swiftself register is never read anywhere in the body, so this method does not touch
    ///     its own instance at all.
    ///
    /// ⚑ `.shared()` is re-sent for EVERY command rather than hoisted into a local, and that is
    ///   read rather than styled: a `let center = …` would emit one `sharedCommandCenter` send,
    ///   and the body emits twelve, one before each command getter.
    /// ⚑[tool=bind_oracle ref=0x104410a18 result=_OBJC_CLASS_$_MPRemoteCommandCenter]
    /// ⚑[tool=override_table ref=KSComplexPlayerLayer.removeRemoteControllEvent:0x1019d5d38 result=NO]
    /// ⚑ ACCESS not independently proven: the trie name carries no private discriminator, so it is
    ///   not `private`, and nothing distinguishes `internal` from `public` for a METHOD — the
    ///   `vpMV` proof applies only to properties and `vtable_impl_oracle` proves access only on a
    ///   `final` type or an actor, which this class is not. `internal` is the narrower of the two
    ///   remaining spellings and is what a helper with no external call site needs.
    func removeRemoteControllEvent() {
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
    }

    /// ⚑[tool=disassemble ref=KSComplexPlayerLayer.pictureInPictureController(_:failedToStartPictureInPictureWithError:):0x1019d342c result=2-instr-thunk]
    /// The row's own body is `mov x0, x1` / `b 0x1019d6430` — it DROPS the controller argument and
    /// tail-calls an 85-instruction handler. That handler is one KSLog call, and every piece of it
    /// is read:
    ///   · `ldrb w8,[0x1044e5173]` / `cmp w8,#2` / `b.lo` — the level gate. 2 is the CASE INDEX for
    ///     `.error`, the encoding this file's own KSLog notes already establish.
    ///   · `w6 = 0x398 = 920` — the line number, and `#file` is the 28-character
    ///     'KSPlayer/KSPlayerLayer.swift'. `#function` is the 69-character string at 0x103d34b80,
    ///     exactly the length of this member's own name.
    ///   · the error goes through `_convertErrorToNSError` (__got 0x104109940) and an NSError
    ///     class-metadata fetch (0x1019d5bd8) into the existential buffer.
    /// ⚑ There is NO message literal, and that absence is evidenced rather than assumed. The KSLog
    ///   commentary at KSOptions.swift:1370 describes this exact sequence for the `Error` overload,
    ///   and notes that a `.localizedDescription` message would instead carry a String through the
    ///   statically-known CustomStringConvertible witness and leave an accessor call — this body
    ///   has neither. So the spelling is the bare `KSLog(error)`, whose @inlinable body expands to
    ///   `KSLog(level: .error, error() as NSError, …)` — which is what the disassembly shows.
    /// ⚑ ACCESS not independently proven: the trie name carries no discriminator, so it is not
    ///   private, and `public` matches the sibling delegate callbacks on the superclass and the
    ///   ObjC visibility an @objc delegate method needs. It is not otherwise established.
    public func pictureInPictureController(_: AVPictureInPictureController,
                                           failedToStartPictureInPictureWithError error: Error)
    {
        KSLog(error)
    }

    /// ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.pictureInPictureControllerWillStartPictureInPicture:0x1019d29d0 result=34-instr]
    /// Two statements, both read:
    ///   · `strb wzr, [x20, <global 0x104c63530>]` writes a ZERO BYTE. Of this class's three
    ///     fields only `isPictureInPictureStoped: Bool` is one byte (`urls` is an Array,
    ///     `enterBackgroundTask` a Task?), so the target is identified by TYPE, not by adjacency —
    ///     which matters because that global carries no `vpWvd`.
    ///   · `player` comes from its own `vpWvd` (offset global 0x104c634f0) and is loaded as the
    ///     two-word existential; `ldr x22,[x19,#0xd8]` then selects witness **26**.
    ///
    /// ⚑ Witness 26 is NAMED, not counted — this protocol's indices are shifted by unrecovered
    ///   requirements, so an index argument would be worthless. Escalation: `KSMEPlayer`'s witness
    ///   at that slot is an unnamed forwarding thunk, so follow it — it loads `KSMEPlayer.videoOutput`
    ///   (global 0x1044ea160) and tail-calls 0x103468f80, whose selref 0x10440d1a8 decodes to
    ///   **`setContentMode:`**. So requirement 26 is `contentMode`'s SETTER, which also matches the
    ///   protocol's kind table (req25/26/27 = one `{get set}` triple).
    /// ⚑[tool=decode_objc_selector ref=0x10440d1a8 result='setContentMode:']
    /// ⚑[tool=protocol_signature ref=MediaPlayerProtocol:0x1039ed6c4 result=req26=Setter]
    ///
    /// ⚑ The argument is `mov w0, #1` — a CASE INDEX, not a rawValue. `UIViewContentMode` is
    ///   `UIView.ContentMode` (UIKitExtend.swift:167), whose case 1 is `.scaleAspectFit`.
    public func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {
        isPictureInPictureStoped = false
        player.contentMode = .scaleAspectFit
    }

    /// @0x1019d27a8, 96 instructions. Every operand is read, and the one that looked like a blocker
    /// was not a member at all.
    ///
    /// `bl 0x1019c835c` is NOT a private helper to be named: it reads the element STRIDE
    /// (`[vwt+0x48]`) and ALIGNMENT (`[vwt+0x50]`) out of the value-witness table, walks `urls` by
    /// that stride comparing through the generic `Equatable.==` witness thunk, and returns
    /// `(index, isNil)` — an unspecialized `firstIndex(of:)` over `[URL]`. It reached EXHAUSTED under
    /// the s112 invented-name authorisation and would have had a name invented for the Swift standard
    /// library; `name_exhaustion_gate` now refuses the shape.
    /// ⚑[tool=name_exhaustion_gate ref=KSComplexPlayerLayer.playNextURL:0x1019c835c result=ARTIFACT-stdlib-firstIndex]
    ///
    /// The one unnamed field global is DECIDED, not guessed: 0x104c63520 is written with `strb`, so
    /// it is byte-class, and of this class's three field records only `isPictureInPictureStoped` is
    /// byte-class (`urls` is an Array, `enterBackgroundTask` a Task?) — which is the same reasoning
    /// `pictureInPictureControllerWillStartPictureInPicture` above already records, reached here by
    /// tool rather than by hand.
    /// ⚑[tool=recover_field_by_access ref=KSComplexPlayerLayer.isPictureInPictureStoped:0x104c63520 result=UNIQUE-byte-class]
    ///
    /// Control flow, read in order: `ldr x8,[urls+0x10]` / `cmp #2` / `b.lo` is the count guard;
    /// the `firstIndex` result's `w1` is the nil flag, tested by `cmp w27,#1` / `b.eq`; then
    /// `x9 = count - 1` and `cmp x23,x9` / `b.ge` bounds the successor. The store of `#1` to
    /// `isPictureInPictureStoped` sits AFTER both guards and BEFORE the `set`, and `set(url:options:)`
    /// @0x1019cb674 is called with `x1 = #0`, i.e. `options: nil`.
    public func playNextURL() {
        guard urls.count >= 2 else {
            return
        }
        guard let index = urls.firstIndex(of: url), index < urls.count - 1 else {
            return
        }
        isPictureInPictureStoped = true
        set(url: urls[index + 1], options: nil)
    }

    /// ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.pictureInPictureControllerWillStopPictureInPicture:0x1019d2b98 result=1-instr-thunk]
    /// ⚑ The trie address is a THUNK (`b 0x1019d61b8`); the real body is the 77 instructions there.
    ///
    ///   · `player` and witness **26** are the same pair `WillStart` above uses — that slot is
    ///     `contentMode`'s setter, named by following KSMEPlayer's forwarding thunk to a
    ///     `setContentMode:` send. Here the value is NOT a literal case: it is read from
    ///     `self.options` (its own `vpWvd`, offset global 0x104c634e0) at `+0x68`.
    ///   · `+0x68` is `KSOptions.contentMode`, recovered by `recover_field_offsets` — KSOptions is
    ///     `metadata_init=1`, so `field_offset_vector` refuses it and the static vector reads 0x0.
    ///     ⚑[tool=recover_field_offsets ref=KSOptions result=contentMode@0x68]
    ///   So this RESTORES the player's content mode from options, where WillStart forced
    ///   `.scaleAspectFit`. The pairing is what makes both readings mutually corroborating.
    ///
    /// ⚑ The trailing call is `Swift.print(_:separator:terminator:)` (__got 0x104112a40) — the
    ///   `w1=0x20` / `w3=0x0a` operands are the one-character `" "` and `"\n"` defaults, which is
    ///   how the overload is identified. Its argument is a LARGE string: the pointer is stored
    ///   biased by `-0x20` with the high bit set, so the characters begin at 0x103d34bd0, and the
    ///   count word is `0x32` (50) tagged `0xD000…`. Decoded, those 50 bytes are exactly this
    ///   method's own name.
    ///   ⚑[tool=decode_string_literal ref=0x103d34bd0 result='pictureInPictureControllerWillStopPictureInPicture']
    /// ⚑ Written as a plain literal, not `#function`: `#function` would render
    ///   `pictureInPictureControllerWillStopPictureInPicture(_:)` including the argument label,
    ///   which is 4 characters longer than the 50 the count word states.
    public func pictureInPictureControllerWillStopPictureInPicture(_: AVPictureInPictureController) {
        player.contentMode = options.contentMode
        print("pictureInPictureControllerWillStopPictureInPicture")
    }

    /// ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.set(urls:):0x1019d181c result=29-instr]
    /// A NEW method, not an override: the superclass's nearest member is `set(urls:options:)`
    /// (this file, above), a different selector. vtable_walk puts this at the class's OWN slot 11,
    /// and it is one of only five KSComplexPlayerLayer symbols carrying a `…Tq` method descriptor
    /// — the same five that occupy the class's five non-null vtable slots. So `Tq` here tracks
    /// "new overridable slot", NOT access; access is taken from the sibling `set(urls:options:)`.
    ///
    /// Every callee in the body was resolved through the chained-fixup bind table, none assumed:
    ///   · 0x10345cb74 → __got 0x104112d88 → `swift_beginAccess`, flags `w2=0x21` = Modify|Tracking
    ///   · 0x10345cb80 → __got 0x104112d90 → `swift_bridgeObjectRelease`  (the OLD array)
    ///   · 0x10345cb98 → __got 0x104112da0 → `swift_bridgeObjectRetain`   (the NEW array)
    ///   · 0x10345cce8 → __got 0x104112e40 → `swift_endAccess`
    ///   · the stored word is __got 0x104112d00 → `_swiftEmptyArrayStorage` — the empty-array
    ///     literal's storage, which is what makes the first statement `= []` rather than a
    ///     `removeAll(keepingCapacity:)` (that form would leave the buffer in place).
    /// The single field global 0x104c63528 is `KSComplexPlayerLayer.urls`'s own `vpWvd`, recovered
    /// by name rather than inferred from the access site.
    ///
    /// The trailing `bl 0x1019c7a8c` is NOT_IN_TRIE, and it is identified STRUCTURALLY rather than
    /// by name: it takes the destination in the swiftself register (`add x20, x20, x21` makes x20
    /// `&self.urls`) and the source array in x0, then does `dst.count + src.count` with a `b.vs`
    /// overflow trap, `swift_isUniquelyReferenced_nonNull_native` (__got 0x104113000) for the COW
    /// check, a capacity compare against `[x19,#0x18] >> 1`, and `swift_arrayInitWithCopy`
    /// (__got 0x104112d70). That is `Array.append(contentsOf:)`. Its element type is pinned by the
    /// `Foundation.URL` metadata accessor it calls (__got 0x104109b18 → `$s10Foundation3URLVMa`),
    /// so the specialization is `Array<URL>`, matching this property.
    ///
    /// ⚑ SPELLING AMBIGUITY, recorded rather than hidden: `+=` and `append(contentsOf:)` are the
    ///   same call on Array, so those two spellings are indistinguishable here. The reset-then-
    ///   append shape itself is NOT ambiguous — a plain `self.urls = urls` emits no count
    ///   arithmetic, no overflow trap and no uniqueness check, and this body has all three.
    ///   Both statements sit inside ONE beginAccess/endAccess pair; that is the optimizer merging
    ///   two adjacent modify accesses to the same property, not evidence of a single statement.
    public func set(urls: [URL]) {
        self.urls = []
        self.urls.append(contentsOf: urls)
    }
}
