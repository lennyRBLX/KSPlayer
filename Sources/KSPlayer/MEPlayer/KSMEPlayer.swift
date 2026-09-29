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
// ⚑ @unchecked Sendable — compiler-MANDATED, not binary-observable, and it follows the MEPlayerItem
//   precedent at MEPlayerItem.swift:14 exactly. `ConstantSubtitleDataSource` is declared `Sendable`
//   because the binary genuinely SENDS a conformer across an executor boundary: readyToPlay's Task
//   awaits `infos()` through witness +0x10, whose requirement flags are 0x31 (Method|IsInstance|
//   IsAsync) and whose entry hops to the GENERIC executor, so the receiver leaves MainActor. Under
//   this target's Swift 6 that call compiles only if the existential is Sendable.
//   Sendable is a MARKER protocol — no witness table, no conformance record, no reflection trace —
//   so it is invisible in the image and cannot be read from it either way. What IS read is the hop,
//   and Sendable is the spelling that makes the source express it. `unchecked` covers the one
//   stored property the compiler flags, `loopCount`; every other stored property already satisfies
//   the check. Recorded as a judgement call, approved=jweaver.
// ⚑[tool=decode_witness_table ref=ConstantSubtitleDataSource.infos:0x1041d76d8 result=req1-flags-0x31-IsAsync]
public final class KSMEPlayer: NSObject, @unchecked Sendable {
    // Forward 1.3.17 stored fields — reflection order (desc 0x1039ef750); reconstructed session 16c (KSMEPlayer M1 fields).
    // Explicit `: Type` on every field. bufferingCountDownTimer removed (source-extra); seekable computed→stored;
    // shouldResumePlayback added; _pipController lazy→stored pipController; bufferingProgress Int→UInt8.
    private var loopCount: Int = 1
    public var playerItem: MEPlayerItem

    public let audioOutput: AudioOutput
    public var options: KSOptions
    // Ref field record 4 has flags 0; init 0x101a3e818 always creates this output.
    // Evidence: M05-KSME-videoOutput-field.json, M05-KSME-output-init-raw.json.
    public let videoOutput: UIView & VideoOutput

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
    public var pipController: (any KSPictureInPictureProtocol)?

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
    // ⚑ L7 lane 13: export trie has seekable vg/vs/vM/vpMV/vpWvd/vpfi (setter 0x101a3dc04, modify 0x101a3dc50),
    //   unlike isReadyToPlay/playableTime (vg only) → the setter is public, not private(set).
    public var seekable: Bool = false // ⚑ M2: binary caches this (recon was computed `playerItem.seekable`)

    // ⚑ L7: Forward didSet 0x101a3dc90 (416 insns; reached from setter 0x101a3bd0c, modify 0x101a3e354 and
    //   sourceDidChange 0x101a41814). `oldValue != playbackRate` gate; KSLog "[audio] playbackRate=" level 3,
    //   function "playbackRate", line 0x44; MEPlayerItem.playbackRate's setter INLINED (audioClock then
    //   videoClock +0x10, modify accesses); displayLayer (VideoOutput +0x40) controlTimebase → CMTimebaseSetRate;
    //   KSOptions vtable +0x700 = isAudioRateByFilter() picks the filter arm, else AudioOutput +0x30 setter.
    // ⚑ L7 lane 14 ISOLATION: @MainActor. The inlined filter closure carries a MainActor executor check
    //   (0x101a3dc90 reportUnexpectedExecutor "KSPlayer/KSMEPlayer.swift" line 0x4a = 74, pinned via
    //   #sourceLocation); its no-hop caller is the @MainActor sourceDidChange(loadingState:) (0x101a41ed0).
    // ⚑ L7: filter arm tail (0x101a3e248-0x101a3e270): `playbackState != .idle` → MEPlayerItem 0x101a48158
    //   (AVMediaType.audio), result discarded.
    @MainActor
    public var playbackRate: Float = 1 {
        didSet {
            if oldValue != playbackRate {
                KSLog("[audio] playbackRate=\(playbackRate)", line: 68)
                playerItem.playbackRate = playbackRate
                if let controlTimebase = videoOutput.displayLayer.controlTimebase {
                    CMTimebaseSetRate(controlTimebase, rate: Double(playbackRate))
                }
                if options.isAudioRateByFilter() {
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 74)
                    var audioFilters = options.audioFilters.filter {
                        !$0.hasPrefix("atempo=")
                    }
#sourceLocation()
                    if playbackRate != 1 {
                        audioFilters.append("atempo=\(playbackRate)")
                    }
                    options.audioFilters = audioFilters
                    if playbackState != .idle {
                        _ = playerItem.usePacketCacheSeek(mediaType: .audio)
                    }
                } else {
                    audioOutput.playbackRate = playbackRate
                }
            }
        }
    }

    // ⚑ L7: Forward setter+didSet 0x101a3e44c — store, then `cbz` on the NEW value (.idle = 0) before the
    //   `cmp` with the old one, then runOnMainThread(playOrPause closure 0x101a47374). The idle guard is why
    //   reset()'s constant `.idle` store runs no observer.
    public private(set) var loadState: MediaLoadState = .idle {
        didSet {
            if loadState != .idle, loadState != oldValue {
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
        options.setAudioSession()
        audioOutput = KSOptions.audioPlayerType.init()
        playerItem = MEPlayerItem(url: url, options: options)
        videoOutput = KSOptions.videoPlayerType.init(options: options)
        self.options = options
        super.init()
        playerItem.delegate = self
        audioOutput.renderSource = playerItem
        videoOutput.renderSource = playerItem
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChange), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        if #available(tvOS 15.0, iOS 15.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(spatialCapabilityChange), name: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification, object: nil)
        }
        #endif
    }

    // ⚑ L7: Forward 0x101a3eca0 (255 insns) — init(url:options:)'s body with the item injected: the same
    //   stored-property defaults, then `item.options` (plain load, retained) feeds setAudioSession
    //   (0x1019b2cac), the videoPlayerType init (witness +0x78) and `self.options`; `playerItem = item`
    //   lands between the audioOutput and videoOutput stores; after super.init the tail is identical
    //   (delegate setter 0x101a482e0, both renderSource witnesses +0x18, the two addObserver calls).
    public init(item: MEPlayerItem) {
        let options = item.options
        options.setAudioSession()
        audioOutput = KSOptions.audioPlayerType.init()
        playerItem = item
        videoOutput = KSOptions.videoPlayerType.init(options: options)
        self.options = options
        super.init()
        playerItem.delegate = self
        audioOutput.renderSource = playerItem
        videoOutput.renderSource = playerItem
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChange), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        if #available(tvOS 15.0, iOS 15.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(spatialCapabilityChange), name: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification, object: nil)
        }
        #endif
    }

    // ⚑ No `deinit`: Forward's __deallocating_deinit is 0x1000dd4d4 (13 insns), the shared ICF'd
    //   NSObject-subclass body (`objc_msgSendSuper2(dealloc)` only). The audio-session /
    //   removeObserver / invalidate statements live in `stop()` (0x101a43b60) in Forward.
    /// ⚑[tool=export_trie_oracle ref=KSPlayer.KSMEPlayer.ioContext.getter:0x101a42340 result=24-instr]
    /// A forward, with `MEPlayerItem.ioContext` INLINED — which is why the body reads two field
    /// globals and a literal offset rather than making a call:
    ///   `ldr x19, [0x1044ea140]` / `swift_beginAccess` / `ldr x8, [self, x19]` — `playerItem`,
    ///   named from its `vpWvd`.
    ///   `ldr x9, [0x1044ea218]` / `ldr x8, [x8, x9]` — the ivar `MEPlayerItem.ioContext` itself
    ///   loads, recorded at MEPlayerItem.swift:109 from an earlier session's read; that member is
    ///   `formatContext?.ioContext`.
    ///   `cbz x8` → nil, else `ldr x0, [x8, #0x20]` — and `+0x20 = ioContext` is the constant that
    ///   same file records at :115 from a read of the owning class's init.
    /// So all three loads line up with the existing `MEPlayerItem.ioContext` declaration, and this
    /// getter is that expression reached through `playerItem`.
    public var ioContext: AbstractAVIOContext? {
        playerItem.ioContext
    }

    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.checkShouldResume():0x101a43f40 result=50-instr]
    /// Three of the four names come from tools; the fourth is elimination:
    ///   · `options` +0x47 = `isDLNARunning`, +0x46 = `enterForgeResumePlay` — both from
    ///     `recover_field_offsets` (KSOptions is `metadata_init=1`, so its static offset vector is
    ///     unreadable and `field_offset_vector` refuses it).
    ///     ⚑[tool=recover_field_offsets ref=KSOptions result=enterForgeResumePlay@0x46,isDLNARunning@0x47]
    ///   · global 0x1044ea1a8 = `playbackState` (`vpWvd`-named), compared `cmp #1` /
    ///     `cset eq` — MediaPlaybackState case **1** is `.playing` (idle=0).
    ///   · the field WRITTEN, global 0x1044ea1c0, has NO `vpWvd` and is NOT_IN_TRIE. It is
    ///     `shouldResumePlayback` by elimination on TYPE and COUNT: this class has five `Bool`
    ///     fields and exactly four carry a `vpWvd` (0x138, 0x148, 0x190, 0x198), leaving this one.
    ///     Its `strb` also confirms a 1-byte store. Scanning `__text` for 0x1044ea1c0 finds only
    ///     three sites — both inits and this method — so no type-revealing use site exists and
    ///     elimination is the available route.
    ///
    /// ⚑ THE FIRST STORE IS DEAD, and that is transcribed rather than tidied away: the `b.ne` on
    ///   `isDLNARunning` and its fall-through BOTH reach the second store to the same global, so
    ///   the `false` is immediately overwritten. Collapsing it would be a cleaner body than the
    ///   binary has; the redundancy most likely marks an early exit the optimiser removed.
    public func checkShouldResume() {
        if options.isDLNARunning {
            shouldResumePlayback = false
        }
        shouldResumePlayback = options.enterForgeResumePlay || playbackState == .playing
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
                self.videoOutput.pause()
            } else {
                self.audioOutput.play()
                self.videoOutput.play()
            }
            self.delegate?.changeLoadState(player: self)
        }
    }

    // ⚑ L7 lane 14 ISOLATION: @MainActor. The @objc thunk 0x101a3f960 → shared 0x101a402e8 runs
    //   swift_task_isCurrentExecutor / reportUnexpectedExecutor("KSPlayer/KSMEPlayer.swift", line 0xf3 = 243);
    //   body 0x101a3f338 KSLog line 0xf4 = 244. Lines pinned via #sourceLocation.
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 243)
    @MainActor @objc private func spatialCapabilityChange(notification _: Notification) {
        KSLog("[audio] spatialCapabilityChange")
        for track in tracks(mediaType: .audio) {
            (track as? FFmpegAssetTrack)?.audioDescriptor?.updateAudioFormat()
        }
    }
#sourceLocation()

    #if !os(macOS)
    // ⚑ L7 lane 14 ISOLATION: @MainActor. The @objc thunk 0x101a402d8 → shared 0x101a402e8 checks the MainActor
    //   executor at line 0x104 = 260; body 0x101a3f970 KSLog line 0x109 = 265.
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 260)
    @MainActor @objc private func audioRouteChange(notification: Notification) {
        KSLog("[audio] audioRouteChange", line: 265)
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
#sourceLocation()
    #endif
}

extension KSMEPlayer: MEPlayerDelegate {
    /// @0x101a3bd64, 1524 B / 381 instructions, one trie symbol, no ICF fold. Synchronous, not
    /// async — the mangle ends `yyF`, the frame is an ordinary callee-save prologue and there is no
    /// `swift_task_alloc`. Its own `#fileID`/`#function` literals place it in this file under this
    /// name, with an isolation check at line 300 and the KSLog at 305.
    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.sourceDidOpenedSync:0x101a3bd64 result=OWNER_MATCH]
    ///
    /// It is NOT `sourceDidOpened()` renamed. That one takes `tracks(mediaType: .video)`, nils
    /// `videoOutput`, marshals through `runOnMainThread` and calls `delegate?.readyToPlay(player:)`
    /// — none of which appear in this extent — and this one adds the `seekable` assignment and the
    /// `startRecord` branch. The two coexist in the binary; 0x101a40420 is the other.
    ///
    /// Statement order is the binary's. The `seekable` source is `playerItem.seekable`, not an
    /// inline predicate: `MEPlayerItem.formatContext` is fileprivate to MEPlayerItem.swift and
    /// cannot be read from here at all, which is why the four-arm predicate lives in that file's
    /// own `seekable` accessor. Writing it inline here would not compile.
    ///
    /// ⚑ PLACEMENT UNPROVEN. The access level is not derivable — the mangled symbol carries none
    ///   and no method descriptor exists — and nothing establishes that this belongs to the
    ///   MEPlayerDelegate conformance rather than a plain extension. It is `internal` because its
    ///   two callers, `KSPlayerLayer.init(item:url:delegate:)` @0x1019caaf4 and
    ///   `KSPlayerLayer.replace(item:url:)` @0x1019cba60, are in another file of the same module,
    ///   which is a lower bound, not a reading. Sited next to `sourceDidOpened()` for adjacency.
    ///
    /// ⚑ ISOLATION: `@MainActor` is Forward-evidenced — the `first { $0.isEnabled }` closure in
    ///   0x101a3bd64 carries `swift_task_isCurrentExecutor` +
    ///   `reportUnexpectedExecutor("KSPlayer/KSMEPlayer.swift", line 300)` (0x101a3c09c `mov w3,#0x12c`),
    ///   which Swift 6 emits only for a closure formed in a MainActor-isolated context; the build
    ///   (nonisolated) has none. Both callers are in the `@MainActor` class KSPlayerLayer.
    ///   The closure line is pinned to 300 via `#sourceLocation`; the KSLog line literal is
    ///   0x131 = 305 (0x101a3c2b8 `mov w6,#0x131`; build had 0x114 = 276).
    @MainActor
    func sourceDidOpenedSync() {
        isReadyToPlay = true
        seekable = playerItem.seekable
        options.readyTime = CACurrentMediaTime()
        if let outputURL = options.outputURL {
            playerItem.startRecord(url: outputURL, mediaType: options.outputMediaType)
        }
        // Forward retains the descriptor ONCE (0x101a3c13c) and releases it once at the end: the guard binds the
        // chain directly (a separate optional `let` + `guard let` shadow costs a second retain / release_n 2).
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 300)
        guard let audioDescriptor = (tracks(mediaType: .audio).first { $0.isEnabled } as? FFmpegAssetTrack)?.audioDescriptor else {
            return
        }
#sourceLocation()
        audioDescriptor.updateAudioFormat()
        KSLog("[audio] audio type=\(audioOutput) prepare audioFormat (sync)", line: 305)
        audioOutput.prepare(audioFormat: audioDescriptor.audioFormat)
    }

    // ⚑ Forward 0x101a40420 (outer, 267 insns) + closure 0x101a4084c (582 insns):
    //   · outer = the sourceDidOpenedSync prefix (isReadyToPlay, inlined playerItem.seekable, readyTime,
    //     outputURL → startRecord 0x101a483d4) then runOnMainThread { [weak self] } (weak box only; the
    //     track lookup happens INSIDE the closure).
    //   · closure: tracks(.audio) (0x101a3ccd0) `first { isEnabled }` — executor check line 0x140 = 320 —
    //     `as? FFmpegAssetTrack` → audioDescriptor; updateAudioFormat() (0x101a68a74); KSLog
    //     "[audio] audio type=" + audioOutput + " prepare audioFormat )" line 0x143 = 323;
    //     audioOutput.prepare(audioFormat:) (AudioOutput wt +0x90). audioDescriptor is released at closure end.
    //   · controlTimebase / startPlayTime > 1 → CMTimebaseSetTime(CMTimeMake(Int64(startPlayTime), 1)).
    //   · rotation block (written in the closure, `#if os(iOS)`), then delegate?.readyToPlay(player: self) (wt +0x8).
    // ⚑ L7 lane 14: rotation block written. `tracks(mediaType: .video).first { isEnabled }` carries the closure
    //   executor check line 0x149 = 329 (pinned via #sourceLocation); MediaPlayerTrack.rotation is wt +0x48;
    //   isLandscape is inlined through the connectedScenes helper 0x101a02f64; centerRotate is inlined as
    //   setTransform:. The observer block 0x101a473bc → 0x101a41164 has no Task, no assumeIsolated and no
    //   executor check (weak-load self → videoOutput → activeWindowScene interfaceOrientation → setTransform).
    public func sourceDidOpened() {
        isReadyToPlay = true
        seekable = playerItem.seekable
        options.readyTime = CACurrentMediaTime()
        if let outputURL = options.outputURL {
            playerItem.startRecord(url: outputURL, mediaType: options.outputMediaType)
        }
        runOnMainThread { [weak self] in
            guard let self else { return }
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 320)
            let audioDescriptor = (tracks(mediaType: .audio).first { $0.isEnabled }
                as? FFmpegAssetTrack)?
                .audioDescriptor
#sourceLocation()
            if let audioDescriptor {
                audioDescriptor.updateAudioFormat()
                KSLog("[audio] audio type=\(audioOutput) prepare audioFormat )", line: 323)
                audioOutput.prepare(audioFormat: audioDescriptor.audioFormat)
            }
            if let controlTimebase = videoOutput.displayLayer.controlTimebase, options.startPlayTime > 1 {
                CMTimebaseSetTime(controlTimebase, time: CMTimeMake(value: Int64(options.startPlayTime), timescale: 1))
            }
            #if os(iOS)
            if !options.isRotateByFilter {
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 329)
                if let videoTrack = tracks(mediaType: .video).first(where: { $0.isEnabled }) {
#sourceLocation()
                    if videoTrack.rotation != 0 {
                        let angle: UInt16 = UIApplication.isLandscape && videoTrack.rotation != 180 ? 0 : videoTrack.rotation
                        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self, videoTrack] _ in
                            guard let self else { return }
                            videoOutput.centerRotate(by: UIApplication.isLandscape ? 0 : videoTrack.rotation)
                        }
                        videoOutput.centerRotate(by: angle)
                    }
                }
            }
            #endif
            delegate?.readyToPlay(player: self)
        }
    }

    // ⚑[tool=member_surface ref=KSMEPlayer.sourceDidFailed:0x101a412bc result=param Swift.Error? (not NSError?); isolation: Forward+build bodies both load $sScMMa (MainActor metadata) via runOnMainThread — unchanged]
    public func sourceDidFailed(error: Error?) {
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.finish(player: self, error: error)
        }
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.KSMEPlayer.sourceDidEOF():0x101a41568 result=9-instr]
    /// The 9-instruction body is only a marshal: it loads four arguments and tail-calls a shared
    /// 107-instruction trampoline @0x101a420b8. **That trampoline is `runOnMainThread(block:)`**,
    /// which a prior pass could not identify and left as this row's single blocker. It is settled
    /// by content: the trampoline sends `isMainThread` to the `NSThread` class and branches on the
    /// result — exactly the `if Thread.isMainThread { block() } else { Task { … } }` shape of
    /// Utility.swift:368.
    ///   ⚑[tool=bind_oracle ref=__objc_classrefs:0x1044105a0 result=_OBJC_CLASS_$_NSThread]
    ///   ⚑[tool=decode_objc_selector ref=0x10440bdf8 result='isMainThread']
    ///   ⚑ The "four generic arguments" that ruled `runOnMainThread` out before are the closure's
    ///     function pointer and context plus the `Task`/`MainActor.run` metadata the specialization
    ///     threads through — not four user-visible parameters.
    ///
    /// The closure body @0x101a4158c does two weak loads: the `[weak self]` capture at +0x10
    /// (`cbz` = `guard let self`) and `delegate` (global 0x1044ea188, `vpWvd`-named), then
    /// dispatches `MediaPlayerDelegate` witness **+0x30**.
    /// ⚑[tool=vtable_walk ref=KSPlayerLayer:slot73 result=reachEndOfStream(player:)]
    public func sourceDidEOF() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.reachEndOfStream(player: self)
        }
    }

    public func sourceDidFinished() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            if self.options.isLoopPlay {
                self.loopCount += 1
                self.delegate?.playBack(player: self, loopCount: self.loopCount)
                self.audioOutput.play()
                self.videoOutput.play()
            } else {
                self.playbackState = .finished
            }
        }
    }

    // ⚑ L7: Forward 0x101a41814 (475 insns), read top to bottom:
    //   · playableTime: EOF (+0x28) → playerItem.duration, else currentPlaybackTime (0x101a41fe4) + maxLoadedTime.
    //   · `playerItem.ioContext` (formatContext +0x20) cast (w4 = 6) to PreLoadProtocol (0x103566c50); `duration > 0`
    //     after the cast, then witness +0x48 = req 8 `syncPlaybackPosition(time:duration:)`.
    //   · isFirst (+0x2a) || isSeek (+0x2b) → VideoOutput +0x48 pixelBuffer; nil → the isFirst / isSeek /
    //     `options.isAccurateSeek` (+0x71) ladder, then +0x80 readNextFrame().
    //   · .playable arm: bufferingProgress is set in place (willSet 0x101a3d128 + store), no runOnMainThread.
    //   · else arm: the firstPlayableTime/prepareTime stamp + KSLog(options.firstTimeLog()) (function
    //     "sourceDidChange(loadingState:)", line 0x19f) precede `loadState = .playable` (setter 0x101a3e44c).
    //   · tail: delegate witness +0x20 = changePlaybackTime(player:time:).
    //   · live-rate gate: MEPlayerItem 0x101a486b0 (`isLive`, 0x101a41e14) before the playbackState/loadState tests.
    //   · ISOLATION: @MainActor (MEPlayerDelegate req0, Model.swift); bare wt thunk 0x101a42328.
    @MainActor
    public func sourceDidChange(loadingState: LoadingState) {
        if loadingState.isEndOfFile {
            playableTime = duration
        } else {
            playableTime = currentPlaybackTime + loadingState.maxLoadedTime
        }
        if let ioContext = ioContext as? PreLoadProtocol, duration > 0 {
            ioContext.syncPlaybackPosition(time: currentPlaybackTime, duration: duration)
        }
        if loadingState.isFirst || loadingState.isSeek {
            if videoOutput.pixelBuffer == nil {
                if loadingState.isFirst || !loadingState.isSeek || !options.isAccurateSeek {
                    videoOutput.readNextFrame()
                }
            }
        }
        if loadState == .playable {
            if !loadingState.isEndOfFile, loadingState.frameCount == 0, loadingState.packetCount == 0, options.preferredForwardBufferDuration != 0 {
                loadState = .loading
                if playbackState == .playing {
                    bufferingProgress = 0
                }
            }
        } else {
            let progress: UInt8
            if loadingState.isPlayable {
                if options.firstPlayableTime == 0, options.prepareTime != 0 {
                    options.firstPlayableTime = CACurrentMediaTime()
                    KSLog(options.firstTimeLog(), line: 415)
                }
                loadState = .playable
                progress = 100
            } else {
                progress = min(loadingState.progress, 100)
            }
            if playbackState == .playing {
                bufferingProgress = progress
            }
        }
        if playerItem.isLive, playbackState == .playing, loadState == .playable {
            if let rate = options.liveAdaptivePlaybackRate(loadingState: loadingState) {
                playbackRate = rate
            }
        }
        // Forward 0x101a41ed4-0x101a41f40: weak load + getObjectType, then currentPlaybackTime (0x101a41fe4),
        //   then MediaPlayerDelegate wt +0x20 no-hop.
        delegate?.changePlaybackTime(player: self, time: currentPlaybackTime)
    }

    public func sourceDidChange(oldBitRate: Int64, newBitrate: Int64) {
        KSLog("oldBitRate \(oldBitRate) change to newBitrate \(newBitrate)")
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.KSMEPlayer.sourceDidClear():0x101a42094 result=9-instr]
    /// Byte-for-byte the same marshal as `sourceDidEOF` above — same `runOnMainThread` trampoline,
    /// same two weak loads — differing in exactly ONE instruction.
    ///
    /// ⚑ THAT ONE INSTRUCTION IS THE WHOLE POINT, and a prior pass got it wrong. §2l recorded both
    ///   bodies as dispatching `reachEndOfStream(player:)`. They do not: the EOF closure loads
    ///   `ldr x23, [x21, #0x30]` and this one loads **`[x21, #0x40]`**. Reading
    ///   `KSPlayerLayer`'s `MediaPlayerDelegate` witness table @0x1041d49b8 at that slot names it
    ///   outright.
    ///   ⚑[tool=export_trie_oracle ref=0x1019ceaf4 result=KSPlayerLayer.playerDidClear(player:)]
    public func sourceDidClear() {
        runOnMainThread { [weak self] in
            guard let self else { return }
            self.delegate?.playerDidClear(player: self)
        }
    }
}

// ⚑ CONFORMANCE RECOVERED FROM THE BINARY. KSMEPlayer conforms to `ConstantSubtitleDataSource`
//   (witness table 0x1041d76d8, conformance descriptor 0x10356a3e8); slot +0x8 holds the base
//   `KSMEPlayer : SubtitleDataSource` table 0x1041d76f0, which `conformance_walker.py` reports
//   independently, and slot +0x10 holds the async function pointer for `infos()`. That +0x10 slot
//   is exactly what `KSPlayerLayer.readyToPlay`'s Task awaits. Source carried neither the
//   conformance nor the method; `subtitleDataSource` returning `self` requires both.
// ⚑[tool=conformance_walker ref=SubtitleDataSource:0x1039f1a68 result=KSMEPlayer-wt-0x1041d76f0]
extension KSMEPlayer: ConstantSubtitleDataSource {
    /// @0x101a18f68 — a 6-instruction async entry into a single readable funclet
    /// 0x101a18f80-0x101a19144 (113 instr, two funclets total). It reads no field of `self`, holds
    /// no literal, and never actually throws — but the trie carries the `K`, so the declaration is
    /// `async throws`: `$s8KSPlayer10KSMEPlayerC5infosSayAA12SubtitleInfo_pGyYaKF`.
    ///
    ///   · `bl 0x101a3ccd0` = `tracks(mediaType:)`, its argument loaded from `_AVMediaTypeSubtitle`.
    ///   · the survivors are boxed with witness table 0x1041d7668 = `FFmpegAssetTrack : SubtitleInfo`
    ///     (declared in source at EmbedDataSouce.swift:11).
    ///
    /// The FILTER is settled by swiftc probe, not by eye — three candidate spellings were compiled
    /// and compared against the extent. `filter { $0 is T }.map` is refuted: it emits TWO
    /// `object_getClass` calls and an intermediate buffer, at 153 instructions. `for` + `if let` is
    /// refuted: it emits `swift_unknownObjectRetain_n`, while the binary calls the plain
    /// `swift_unknownObjectRetain` (stub 0x10345d12c → __got 0x1041130b0) and also
    /// `swift_isUniquelyReferenced_nonNull_native` (0x10345cf88 → __got 0x104113000), both of which
    /// `compactMap` emits. The local array-growth helper 0x1019acc10 is called twice, matching
    /// `compactMap`'s two buffer-growth calls.
    ///
    /// The exact-class test this lowers to — `object_getClass(elem) == FFmpegAssetTrack metadata`
    /// then `ccmp x21, #0x0, #0x4, eq`, where x21 is the element's instance word at stride 16 from
    /// base+0x20 — appears ONLY when the cast target is `final`, which is why FFmpegAssetTrack
    /// carries that keyword. See the pin at its declaration.
    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.infos:0x101a18f68 result=async-throws-SubtitleInfo-array]
    /// ⚑[tool=bind_oracle ref=swift_unknownObjectRetain:0x1041130b0 result=plain-retain-not-_n]
    ///   Full derivation: reconstruction/derivations/s118_infos_cast_lowering_probe.md (UNGROUNDED 0).
    public func infos() async throws -> [any SubtitleInfo] {
        tracks(mediaType: .subtitle).compactMap { $0 as? FFmpegAssetTrack }
    }
}

extension KSMEPlayer: @preconcurrency MediaPlayerProtocol {

    // Ref 0x101a3c358 preserves the output objects while replacing their source.
    @MainActor
    // ⚑ Forward 0x101a3c358: log literal is "replace item " + `\(item)` (generic _print_unlocked
    //   on MEPlayerItem metadata, not NSObject.description of self), line 0x1e2 = 482; the
    //   `contains` closure's executor check is line 0x1e7 = 487, pinned via #sourceLocation.
    func replace(item: MEPlayerItem) {
        KSLog("replace item \(item)", line: 482)
        reset()
        playerItem.delegate = nil
        let options = item.options // ⚑ Forward 0x101a3c518: options load/retain precedes the playerItem store.
        playerItem = item
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 487)
        if options.isAudioRateByFilter(), playbackRate != 1, !options.audioFilters.contains(where: { $0.hasPrefix("atempo=") }) {
            options.audioFilters.append("atempo=\(playbackRate)")
        }
#sourceLocation()
        self.options = options
        playerItem.delegate = self
        audioOutput.resetTime()
        audioOutput.renderSource = playerItem
        videoOutput.renderSource = playerItem
        videoOutput.options = options
    }

    nonisolated public func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack] {
        playerItem.assetTracks.compactMap { track -> MediaPlayerTrack? in
            if track.mediaType == mediaType {
                return track
            } else if mediaType == .subtitle {
                return track.closedCaptionsTrack
            }
            return nil
        }
    }

    /// cachedTimeRanges.getter @0x101a3d744, 90 instr. `public` from the property descriptor
    /// $s8KSPlayer10KSMEPlayerC16cachedTimeRangesSayAA06CachedD5RangeVGvpMV @0x10356add0; no
    /// `…vs` / `…vM`, so get-only. It occupies no vtable slot — `KSMEPlayer` is `final` — which is
    /// why it sits in this extension rather than the class body, the opposite of the KSAVPlayer
    /// twin at 0x1019a1244 (there it IS slot 45, because that class is not final).
    ///
    /// Source-identical to that twin; the extra indirection in the binary is `ioContext` and
    /// `duration` being INLINED, both of which this file already declares as `playerItem.…`:
    ///  · `self.playerItem` via offset global 0x1044ea140 (named), then a further field read, then
    ///    `+0x20` — that chain is `playerItem.ioContext`, `cbz`-guarded at two levels.
    ///  · `swift_dynamicCast` with `w4 = 6` (CONDITIONAL) from `AbstractAVIOContext` (metadata
    ///    accessor 0x1019e4db4) to the `_p` existential mangled at 0x103566c50.
    ///  · the `duration` read is against `playerItem`, not self — `ldr d8, [playerItem, <global>]`
    ///    then `fcmp d8, #0.0` / `b.le`, ordered AFTER the cast, exactly as in the twin.
    ///  · success calls witness slot **+0x40** with `d0 = duration`; PreLoadProtocol has 9
    ///    requirements, so that is index 7 = `cachedTimeRanges(duration:)`.
    ///  · both failure paths return `__swiftEmptyArrayStorage`, i.e. `[]`.
    /// ⚑[tool=recover_field_offsets ref=KSMEPlayer.playerItem:0x1044ea140 result=playerItem]
    /// ⚑[tool=conformance_walker ref=PreLoadProtocol:0x1039ede48 result=9-requirements]
    public var cachedTimeRanges: [CachedTimeRange] {
        guard let ioContext = ioContext as? PreLoadProtocol, duration > 0 else {
            return []
        }
        return ioContext.cachedTimeRanges(duration: duration)
    }

    nonisolated public var duration: TimeInterval { playerItem.duration }

    nonisolated public var currentPlaybackTime: TimeInterval {
        get {
            playerItem.currentPlaybackTime
        }
        set {
            seek(time: newValue) { _ in }
        }
    }
    public var chapters: [Chapter] {
        playerItem.chapters
    }

    // ⚑ RETYPED to the refined protocol. The getter's own mangled name carries the refined type:
    //   `$s8KSPlayer10KSMEPlayerC18subtitleDataSourceAA016ConstantSubtitledE0_pSgvg`
    //   = `KSMEPlayer.subtitleDataSource.getter : ConstantSubtitleDataSource?`. The binary has no
    //   `vs` and no `vM` symbol for it, so it is getter-only, which the protocol requirement's
    //   `{ get }` already matches. Returning `self` is what forces the conformance below.
    // ⚑[tool=export_trie_oracle ref=KSMEPlayer.subtitleDataSource.getter:0x101a42408 result=ConstantSubtitleDataSource-optional]
    public var subtitleDataSource: (any ConstantSubtitleDataSource)? { self }
    public var playbackVolume: Float {
        get {
            audioOutput.volume
        }
        set {
            audioOutput.volume = newValue
        }
    }

    nonisolated public var isPlaying: Bool { playbackState == .playing }

    @MainActor
    // Forward 0x101a4254c: isSphere, or playerItem.naturalSize == nil (tag byte +0x10), takes the scene path.
    // ⚑ L7: the scene path is UIApplication.sceneSize INLINED (UIKitExtend.swift:218): sharedApplication →
    //   0x101a02de0 (windows.first) → `bounds` (v2/v3 = size), nil → CGSize(1, 1) (fmov d8/d9 #1.0 @0x101a42698).
    //   The build called KSOptions.sceneSize's getter (whose fallback is .zero) instead. Same precedent as
    //   VRBoxDisplayModel.set(frame:encoder:) in SphereDisplayModel.swift.
    public var naturalSize: CGSize {
        #if canImport(CallKit)
        options.display.isSphere ? UIApplication.sceneSize : playerItem.naturalSize ?? UIApplication.sceneSize
        #else
        options.display.isSphere ? KSOptions.sceneSize : playerItem.naturalSize ?? KSOptions.sceneSize
        #endif
    }

    public var isExternalPlaybackActive: Bool { false }

    public var view: UIView { videoOutput }

    public func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {
        replace(item: MEPlayerItem(io: io, options: options))
    }

    // KSPlayer.KSMEPlayer.reset() @0x101a427b0 — 97 instr (0x101a427b0-0x101a42934), exactly one
    // exported symbol at the address (no ICF fold). NOT vtable-dispatched: KSMEPlayer's vtable is
    // 2 slots, both `Init`, and the class has no override table (kind flag 0x4000 clear). It is
    // reached three ways — `KSMEPlayer : MediaPlayerProtocol` witness req#37 (WT 0x1041d7c68,
    // slot 38 / offset 0x130, through the 1-instruction tail-call thunk 0x101a447a0) plus direct
    // `bl` from replace(item:) @0x101a3c4d8 and from stop() @0x101a43cf8.
    //
    // `public` is NOT invented. The trie carries no access-discriminating symbol for the method
    // itself, but a public protocol's requirement can only be witnessed by a public member, and
    // this is a witness of public `MediaPlayerProtocol` from inside that conformance extension.
    //
    // ⚠️ THREE DIVERGENCES THIS BODY EXPOSES, each left to its own unit rather than smuggled in:
    //  · `stop()` directly above INLINES this body; the binary factors it out and calls it.
    //  · req#37 makes `reset()` a MediaPlayerProtocol REQUIREMENT in Forward, and this tree's
    //    MediaPlayerProtocol does not declare it. Adding it cascades to every conformer.
    //  · the `loadState` store here runs NO observer, while the `playbackState` store two lines
    //    down loads its old value and calls its didSet at 0x101a3e510. Both properties carry an
    //    identical didSet in this tree, so the binary and the tree disagree about `loadState`'s
    //    observer — a fact about loadState's DECLARATION, not about this body.
    public func reset() {
        options.reset() //                         @0x101a427e0-0x101a42800, KSOptions vtable slot 4
        loadState = .idle //                       @0x101a4281c-0x101a42820, modify access, byte 0
        playbackState = .idle //                   @0x101a4283c-0x101a4284c, modify access + didSet
        isReadyToPlay = false //                   @0x101a42868-0x101a4286c, modify access, byte 0
        loopCount = 0 //                           @0x101a42870-0x101a42878, NO exclusivity check
        // playerItem.send(.close) @0x101a42894-0x101a428d0. The Event value is built on the stack
        // (payload word0 = 6, payload zeroed, tag byte = 3 = numPayloadCases, i.e. the no-payload
        // marker; empty-case ordinal 6 in declaration order is `close`) and handed to the
        // trie-named MEPlayerItem.send(MEPlayerItem.Event) — now declared (MEPlayerItem.swift Event :1012).
        // ⚑[tool=export_trie_oracle ref=MEPlayerItem.send:0x101a48b04 result=OWNER_MATCH]
        playerItem.send(.close)
        if KSOptions.isClearVideoWhereReplace { // @0x101a428ec-0x101a428f8, read access, 0x1044e5151
            videoOutput.flush() //                @0x101a428fc-0x101a4291c, FrameOutput witness req#2
        }
    }

    // ⚑ Forward 0x101a42944 (269 insns):
    //   · KSLog "\(self) seek from \(currentPlaybackTime) to \(time)" on the RAW `time` (grow(0x15),
    //     description, " seek from ", double _write, " to ", double _write), line 0x20a = 522.
    //   · bufferingProgress is set in place (willSet 0x101a3d128 + store), no runOnMainThread.
    //   · currentPlaybackTime (0x101a41fe4) == seekTime is captured as a Bool.
    //   · The seek goes through `playerItem.send(.seek(to:useCache:completion:))` (0x101a48b04), with
    //     `useCache` = options.seekUsePacketCache. Context 0x1041d7c10 = {weak self, Bool, videoOutput, completion}.
    //   · Completion 0x101a42e9c: weak-load self → re-box weak → inlined runOnMainThread { 0x101a430e8 }.
    //   · Main body 0x101a430e8: guard self; if result { loadState = .loading (0x101a3e44c(1));
    //     if !isSame { self.videoOutput.<VideoOutput wt +0x50>(nil) }; audioOutput.flush() (FrameOutput +0x18);
    //     if self.videoOutput === captured videoOutput, window != nil, let tb = displayLayer.controlTimebase
    //     { CMTimebaseSetTime(tb, CMTimeMake(Int64(currentPlaybackTime), 1)) } }; completion(result).
    // GAP (MetalPlayView.swift, VideoOutput): wt +0x50 is called with a 2-word nil — the setter of
    //   `pixelBuffer: PixelBufferProtocol? { get set }` (class-bound existential; getter is +0x48). This tree
    //   declares `pixelBuffer { get }`, so `videoOutput.pixelBuffer = nil` cannot be spelled; the arm is empty.
    nonisolated public func seek(time: TimeInterval, completion: @escaping (@MainActor @Sendable (Bool) -> Void)) {
        KSLog("\(self) seek from \(currentPlaybackTime) to \(time)", line: 522)
        let time = max(time, 0)
        playbackState = .seeking
        bufferingProgress = 0
        let seekTime: TimeInterval
        if time >= duration, options.isLoopPlay {
            seekTime = 0
        } else {
            seekTime = time
        }
        let isSameTime = currentPlaybackTime == seekTime
        // Forward 0x101a42944 reads the videoOutput existential (ldr q0 → sp+0x10) BEFORE the options.seekUsePacketCache
        // access and the weak box: a local ahead of the send, not a capture-list binding (evaluated at closure formation).
        let videoOutput = videoOutput
        playerItem.send(.seek(to: seekTime, useCache: options.seekUsePacketCache) { [weak self] result in
            guard let self else { return }
            runOnMainThread { [weak self] in
                guard let self else { return }
                if result {
                    loadState = .loading
                    if !isSameTime {
                        // GAP: self.videoOutput.pixelBuffer = nil (VideoOutput wt +0x50, undeclared setter)
                    }
                    audioOutput.flush()
                    if self.videoOutput === videoOutput, videoOutput.window != nil, let controlTimebase = videoOutput.displayLayer.controlTimebase {
                        CMTimebaseSetTime(controlTimebase, time: CMTimeMake(value: Int64(currentPlaybackTime), timescale: 1))
                    }
                }
                completion(result)
            }
        })
    }

    public var fileSize: Int64 { playerItem.fileSize }

    public var dynamicInfo: DynamicInfo {
        playerItem.dynamicInfo
    }

    // ⚑ L7: Forward 0x101a432fc (255 insns): KSLog line 0x22f; options.resetTimeLog() (0x1019c0798);
    //   isReadyToPlay store; bufferingProgress willSet 0x101a3d128 + store; `state != .idle` (isIdle inlined) →
    //   isPreload guard → resumeFromPreload() (0x101a4755c): 1/2 → sourceDidOpened() (0x101a40420), 0 → return,
    //   3 → KSLog (0x4a-char literal, line 0x244); then send(Event tag 3, word0 0 = .open) (0x101a48b04).
    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)", line: 559)
        options.resetTimeLog()
        isReadyToPlay = false
        bufferingProgress = 0
        if !playerItem.isIdle {
            guard playerItem.isPreload else {
                return
            }
            switch playerItem.resumeFromPreload() {
            case .resumeFromPaused, .readyImmediate:
                sourceDidOpened()
                return
            case .waitForOpened:
                return
            case .cannotResume:
                KSLog("[KSMEPlayer] prepareToPlay: preload item cannot resume, sending open event", line: 580)
            }
        }
        playerItem.send(.open)
    }

    // ⚑ L7 lane 13 ISOLATION: MainActor (the MediaPlayerProtocol requirement's), not nonisolated. Forward's
    //   witness thunk 0x101a44798 is a bare `b`, the body has no executor check, and the tail calls the
    //   @MainActor KSPictureInPictureProtocol req4 (wt +0x28) no-hop; every Forward caller is MainActor
    //   (setPlaying objc thunk 0x101a44838 checks MainActor; 0x101a46354 / 0x101a465a4 are the MainActor.run closures).
    public func play() {
        // ⚑ line literal 0x24c = 588 (Forward 0x101a43830 `mov w6,#0x24c`; build had 650).
        KSLog("play \(self)", line: 588)
        playbackState = .playing
        // Forward: pipController existential, getObjectType, wt +0x28 (req4 invalidatePlaybackState); no cast,
        // no #available.
        pipController?.invalidatePlaybackState()
    }

    // ⚑ L7 lane 13 ISOLATION: MainActor (the MediaPlayerProtocol requirement's), not nonisolated. Forward's
    //   witness thunk 0x101a4479c is a bare `b`, the body has no executor check, and the tail calls the
    //   @MainActor KSPictureInPictureProtocol req4 (wt +0x28) no-hop; every Forward caller is MainActor
    //   (setPlaying objc thunk 0x101a44838 checks MainActor; 0x101a46354 / 0x101a465a4 are the MainActor.run closures).
    public func pause() {
        // ⚑ line literal 0x254 = 596 (Forward 0x101a43a48 `mov w6,#0x254`; build had 661).
        KSLog("pause \(self)", line: 596)
        playbackState = .paused
        // Forward: pipController existential, getObjectType, wt +0x28 (req4 invalidatePlaybackState); no cast,
        // no #available.
        pipController?.invalidatePlaybackState()
    }

    /// ⚑[tool=llvm-objdump ref=KSMEPlayer.flushVideo():0x101a43b24 result=15-instr]
    /// Loads the ivar-offset global `0x1044ea160`, which reads **0x30** statically and which the
    /// trie names `direct field offset for KSPlayer.KSMEPlayer.videoOutput` — matching entry 4 of
    /// the offset vector. `ldp x20,x19,[x8]` splits the existential into object and witness table
    /// with no nil check, then `ldr x1,[x19,#0x8]` takes VideoOutput's word 1 (its inherited
    /// FrameOutput table) and `ldr x8,[x1,#0x18]` takes that table's word 3 = requirement 2.
    /// The requirement is DECODED, not counted: MetalPlayView's FrameOutput table 0x1041d8c80
    /// resolves req0-req3 through thunks to `play()`, `pause()`, `flush()`, `invalidate()`, so
    /// req2 is `flush()`.
    /// ⚑[tool=export_trie_oracle ref=0x1044ea160 result=KSMEPlayer.videoOutput-offset-0x30]
    /// ⚑[tool=decode_witness_table ref=MetalPlayView:FrameOutput@0x1041d8c80 result=req2-flush]
    public func flushVideo() {
        videoOutput.flush()
    }

    /// Forward 0x101a43b60: log "stop " + description (line 0x273 = 627), playbackState = .stopped
    /// (didSet 0x101a3e510), reset() (0x101a427b0), `try?` setPreferredOutputNumberOfChannels(2)
    /// (error bridged + released), NotificationCenter.default.removeObserver(self), then
    /// audioOutput / videoOutput FrameOutput req3 (base-table +0x20 = invalidate()).
    public func stop() {
        KSLog("stop \(self)", line: 627)
        playbackState = .stopped
        reset()
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(2)
        #endif
        NotificationCenter.default.removeObserver(self)
        audioOutput.invalidate()
        videoOutput.invalidate()
    }

    @MainActor
    public var contentMode: UIViewContentMode {
        get {
            view.contentMode
        }
        set {
            view.contentMode = newValue
        }
    }

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        videoOutput.pixelBuffer?.cgImage()
    }

    // ⚑ L7 GAP (MetalPlayView.swift, VideoOutput): Forward 0x101a44008 (15 insns) is exactly
    //   `videoOutput.<VideoOutput wt +0x88>()`, and enterForeground 0x101a44044 opens with wt +0x90. MetalPlayView
    //   has enterBackground()/enterForeground(), but this tree's VideoOutput ends at readNextFrame (Forward +0x80),
    //   so neither requirement is declared and the calls cannot be spelled. Body left empty.
    public func enterBackground() {}

    // ⚑ L7: Forward 0x101a44044 (106 insns): [VideoOutput wt +0x90 — GAP above]; playbackState == .paused (2);
    //   playerItem.seekable INLINED (formatContext / pb / pb.seekable > 0 / duration != 0); playerItem.duration > 0;
    //   options.hardwareDecode; then seek(time: currentPlaybackTime) (0x101a42944) with the [weak self] closure
    //   0x101a441ec: shouldResumePlayback (0x1044ea1c0) && !options.isDLNARunning (+0x47) → .playing, else .paused.
    public func enterForeground() {
        if playbackState == .paused, playerItem.seekable, duration > 0, options.hardwareDecode {
            seek(time: currentPlaybackTime) { [weak self] _ in
                guard let self else { return }
                if shouldResumePlayback, !options.isDLNARunning {
                    playbackState = .playing
                } else {
                    playbackState = .paused
                }
            }
        }
    }

    public var isMuted: Bool {
        get {
            audioOutput.isMuted
        }
        set {
            audioOutput.isMuted = newValue
        }
    }

    public func select(track: some MediaPlayerTrack) {
        let isSeek = playerItem.select(track: track)
        if isSeek {
            audioOutput.flush()
        }
    }
}

// ⚑ L7 lane 13 ISOLATION: the objc thunks of the sync witnesses all run the MainActor executor check
//   (swift_task_isCurrentExecutor / reportUnexpectedExecutor "KSPlayer/KSMEPlayer.swift"): setPlaying 0x101a44838
//   line 0x2d1, TimeRange 0x101a44a38 line 0x2d5, IsPlaybackPaused 0x101a44c4c line 0x2dd, didTransition
//   0x101a44d1c line 0x2e1, ShouldProhibit 0x101a451b8 line 0x2e6 → @MainActor witnesses of a nonisolated ObjC
//   protocol = @preconcurrency conformance. Lines pinned via #sourceLocation. skipByInterval stays the async GAP.
@available(tvOS 14.0, *)
extension KSMEPlayer: @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 721)
    @MainActor public func pictureInPictureController(_: AVPictureInPictureController, setPlaying playing: Bool) {
        playing ? play() : pause()
    }
#sourceLocation()

#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 725)
    @MainActor public func pictureInPictureControllerTimeRangeForPlayback(_: AVPictureInPictureController) -> CMTimeRange {
        // Handle live streams.
        if duration == 0 {
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        return CMTimeRange(start: 0, end: duration)
    }
#sourceLocation()

#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 733)
    @MainActor public func pictureInPictureControllerIsPlaybackPaused(_: AVPictureInPictureController) -> Bool {
        !isPlaying
    }
#sourceLocation()

#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 737)
    @MainActor public func pictureInPictureController(_: AVPictureInPictureController, didTransitionToRenderSize _: CMVideoDimensions) {}
#sourceLocation()
    /// ⚑ ISOLATION: `@MainActor` is Forward-evidenced — the async entry 0x101a44db4 loads
    ///   `MainActor.shared`, takes its `unownedExecutor` and `swift_task_switch`es to it before the
    ///   body 0x101a44e48; the nonisolated build switches to the generic executor (x2 = 0). Body
    ///   already matches (seek(time: currentPlaybackTime + skipInterval.seconds) + shared empty
    ///   completion 0x10000e52c). L7 lane 13: typechecks under the @preconcurrency conformance.
    @MainActor public func pictureInPictureController(_: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        seek(time: currentPlaybackTime + skipInterval.seconds) { _ in }
    }

#sourceLocation(file: "KSPlayer/KSMEPlayer.swift", line: 742)
    @MainActor public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_: AVPictureInPictureController) -> Bool {
        false
    }
#sourceLocation()
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
extension KSMEPlayer: AVPlaybackCoordinatorPlaybackControlDelegate {
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue playCommand: AVDelegatingPlaybackCoordinatorPlayCommand) async {
        guard playCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        if playbackState != .playing {
            await MainActor.run {
                play()
            }
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue pauseCommand: AVDelegatingPlaybackCoordinatorPauseCommand) async {
        guard pauseCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        if playbackState != .paused {
            await MainActor.run {
                pause()
            }
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

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue bufferingCommand: AVDelegatingPlaybackCoordinatorBufferingCommand) async {
        guard bufferingCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        guard loadState != .playable, let countDown = bufferingCommand.completionDueDate?.timeIntervalSinceNow else {
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(countDown * 1_000_000_000))
    }
}

public extension KSMEPlayer {

    public func startRecord(url: URL) {
        playerItem.startRecord(url: url, mediaType: nil)
    }

    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.stopRecord():0x101a44520 result=42-instr]
    /// ⚑ RENAMED from `stoptRecord` — a typo that never existed in the binary. The trie carries
    /// `KSPlayer.KSMEPlayer.stopRecord() -> ()` and has ZERO hits for `stoptRecord`, so the old
    /// spelling was invented. One occurrence in the whole source, so the rename is self-contained.
    ///
    /// The forwarding body is confirmed by the binary rather than assumed: @0x101a44520 loads
    /// `playerItem` (its own `vpWvd`, offset global 0x1044ea140) and then inlines
    /// `MEPlayerItem.stopRecord()` — see that method, whose commit-1 stub this same read resolved.
    public func stopRecord() {
        playerItem.stopRecord()
    }
    /// @0x101a445c8, 64 instructions. Trie: `KSMEPlayer.configPIP() -> ()`; no `Tq`.
    ///
    /// The KSAVPlayer twin builds its controller from an `AVPlayerLayer`; this one has no such
    /// layer and goes through a content source instead, which is why the two bodies differ:
    ///   · offset global 0x1044ea160 is `videoOutput`'s own `vpWvd`
    ///     (`… videoOutput : __C.UIView & KSPlayer.VideoOutput`), and `ldp x20, x21` takes it as the
    ///     (instance, witness-table) pair. `ldr x8,[x21,#0x40]` is requirement 7 of VideoOutput,
    ///     which conformance_walker types as the protocol's ONLY bare read-only Getter. It is named
    ///     by the parameter it feeds, not by counting: the result goes straight into
    ///     `initWithSampleBufferDisplayLayer:playbackDelegate:`, whose first parameter is an
    ///     `AVSampleBufferDisplayLayer`, and `displayLayer` is this protocol's only property of
    ///     that type.
    ///   · `objc_allocWithZone` on the AVKit `AVPictureInPictureControllerContentSource` classref,
    ///     then selref 0x10440bb28 = `initWithSampleBufferDisplayLayer:playbackDelegate:` with
    ///     x2 = that layer and x3 = self. KSMEPlayer already conforms to
    ///     `AVPictureInPictureSampleBufferPlaybackDelegate`, so `self` type-checks as the delegate.
    ///   · then the same `swift_once` static as the KSAVPlayer twin — token 0x1044e5178, storage
    ///     0x104c632c0, `KSOptions.pictureInPictureType` — read under a (0, 0) beginAccess, and
    ///     `ldr x8,[x21,#0x20]` dispatches witness 3, which this protocol's requirement table maps
    ///     to `init(contentSource:)`. Unlike the KSAVPlayer twin there is NO `cmp`/`csel` on the
    ///     result, so this requirement is non-failable and the existential is stored unconditionally.
    ///   · the store is a beginAccess on offset global 0x1044ea170, `pipController`, then `stp` of
    ///     the new pair and a release of the old.
    /// ⚑[tool=decode_objc_selector ref=0x10440bb28 result=initWithSampleBufferDisplayLayer-playbackDelegate]
    /// ⚑[tool=export_trie_oracle ref=KSMEPlayer.videoOutput:0x1044ea160 result=UIView-and-VideoOutput]
    /// ⚑[tool=conformance_walker ref=KSPlayer.VideoOutput:0x1039efc54 result=req7-sole-readonly-getter]
    ///
    /// ⚑ `@MainActor` is NOT binary-derived — actor isolation leaves no reflection record, and this
    ///   body shows no hop. It is required because `KSPictureInPictureProtocol` carries `@MainActor`
    ///   (itself carried over, as KSPictureInPictureController.swift records) while `KSMEPlayer` is
    ///   a plain `final class: NSObject`. This file already marks individual members that way rather
    ///   than isolating the whole type, and the KSAVPlayer twin needs no marking only because that
    ///   class is `@MainActor` outright — so the two `configPIP`s end up equally isolated either way.
    @MainActor
    public func configPIP() {
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: videoOutput.displayLayer,
            playbackDelegate: self
        )
        pipController = KSOptions.pictureInPictureType.init(contentSource: contentSource)
    }
}
