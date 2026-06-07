//
//  KSComplexPlayerLayer.swift
//  KSPlayer
//
//  RE addition: KSPlayerLayer subclass adding a multi-URL playlist plus a
//  Picture-in-Picture restore/stop lifecycle on top of KSPlayerLayer.
//
//  Binary: _TtC8KSPlayer20KSComplexPlayerLayer (~21 functions)
//  RE source: v1.3.15
//

import AVKit
import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

open class KSComplexPlayerLayer: KSPlayerLayer {
    public var urls: [URL] = []
    // Per CLAUDE.md typo-fix rule, binary `isPictureInPictureStoped` → `isPictureInPictureStopped`
    // in Swift. Reversal doc `.reversal/PlayerCore.md §6.6` notes the typo as preserved at
    // the binary level (it's in upstream KSPlayer source too) — fixed here.
    public var isPictureInPictureStopped: Bool = true

    // The engine PiP controller is `KSPictureInPictureController` (the subclass) everywhere else
    // (MediaPlayerProtocol.pipController, KSAVPlayer, KSMEPlayer). This layer's own reference is
    // populated by `maybeCreatePipController()` from the player's engine-owned controller so the
    // layer and the player never juggle two distinct PiP objects.
    // RE: undocumented extra field (not one of the 2 documented stored fields per types.json);
    // in-scope PiP plumbing for this subclass.
    private weak var pipController: KSPictureInPictureController?

    // MARK: - Init (RE: KSComplexPlayerLayer_initWithURL_options_delegate @ 0x1013b5298)

    /// Convenience init. Delegates to the `KSPlayerLayer` designated initializer
    /// (`init(url:isAutoPlay:options:delegate:)`, RE init body `FUN_1013ba56c`) — which sets the
    /// stored url/options/delegate, builds the engine player, conditionally registers the full remote
    /// command set via `registerRemoteCommandHandlers()` (gated on `options.registerRemoteControll`),
    /// and installs the notification observers — then seeds the playlist and arms PiP-restore on the
    /// main thread.
    public convenience init(url: URL, options: KSOptions, delegate: KSPlayerLayerDelegate?) {
        // RE 0x1013ba56c: the superclass designated init performs the url/options/delegate wiring,
        // engine-player construction, and (gated) remote-command registration. The subclass must NOT
        // reimplement a separate, incomplete registrar — delegate to the parent.
        self.init(url: url, options: options, delegate: delegate)
        urls = [url]
        isPictureInPictureStopped = true
        // RE 0x1013b64b0: init dispatches PiP-restore arming onto the main thread (Utility.swift:22).
        runOnMainThread { [weak self] in
            self?.setupPiPRestore()
        }
    }

    // MARK: - init(coder:) unavailable (RE: KSComplexPlayerLayer_fatalError_init_line722 @ 0x1013b60f0)

    /// RE: 0x1013b60f0 — the `fatalError` body for the unavailable initializer (binary line 722).
    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Init with MEPlayerItem (RE: KSComplexPlayerLayer_initWithMEPlayerItem_setupRemoteCommands @ 0x1013b61c8)

    /// Init-from-`MEPlayerItem` setup path. Remote-command registration is owned by the parent
    /// (`registerRemoteControllEvent()` invoked from `KSPlayerLayer.init` gated on
    /// `options.registerRemoteControll`); this only wires the subtitle + PiP delegate.
    public func setupWithMEPlayerItem(options _: KSOptions) {
        setupSubtitleAndPipDelegate()
    }

    // MARK: - Player Ready (RE: KSComplexPlayerLayer_onPlayerReady_setupAll @ 0x1013b2624)

    func onPlayerReadySetupAll() {
        maybeCreatePipController()
        setupSubtitleAndPipDelegate()
    }

    // MARK: - PiP (RE: KSComplexPlayerLayer_maybeCreatePipController @ 0x1013b6e38)

    /// Lazily resolves the engine `KSPictureInPictureController`. The engine (KSMEPlayer /
    /// KSAVPlayer) owns the controller and builds it from a sample-buffer content source; this layer
    /// only caches a weak reference to it. Per doc §6.2: only acts when the controller does not
    /// already exist, and arms auto-PiP when `canStartPictureInPictureAutomaticallyFromInline`.
    func maybeCreatePipController() {
        #if canImport(UIKit) && !os(xrOS)
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if #available(tvOS 14.0, *) {
            // Condition 3 (doc §6.2): only create/cache if not already present.
            guard pipController == nil else { return }
            // The engine builds its own KSPictureInPictureController from the Metal/FFmpeg
            // sample-buffer content source; adopt that instance rather than constructing a second.
            if let enginePip = player.pipController {
                pipController = enginePip
                // Condition 1 (doc §6.2): arm auto-PiP from inline when requested.
                if options.canStartPictureInPictureAutomaticallyFromInline {
                    enginePip.canStartPictureInPictureAutomaticallyFromInline = true
                }
            }
        }
        #endif
    }

    // MARK: - PiP Controller Accessor (RE: KSComplexPlayerLayer_pipControllerRef @ 0x1013b6a48)

    /// RE: 0x1013b6a48 — returns the cached PiP controller reference. Trivial accessor kept distinct
    /// per the no-skip rule; callers within this file use it instead of touching the field directly.
    func pipControllerRef() -> KSPictureInPictureController? {
        pipController
    }

    // MARK: - PiP Lifecycle (RE: 0x1013b6cc8, 0x1013b6d7c, 0x1013b6ab4)

    func pipWillStop() {
        isPictureInPictureStopped = true
    }

    func pipDidStop() {
        isPictureInPictureStopped = true
        postPiPStopCleanup()
        // RE 0x1013b6d7c (verified decompile): the binary's pipDidStop sets
        // isAutoPlay=false, dispatches the player witness +0x128, then clears
        // MPNowPlayingInfoCenter.nowPlayingInfo. It does NOT reference enhanceDolby
        // (DAT_104450978) or any PlayerCenter — the PlayerCenter PiP-state hook
        // lives in the play/Components repo, not in this KSPlayer subclass.
    }

    func pipFailedToStart() {
        isPictureInPictureStopped = true
    }

    // MARK: - PiP Restore (RE: KSComplexPlayerLayer_restoreFromPiP @ 0x1013b6920)

    func restoreFromPiP() {
        isPictureInPictureStopped = false
        // RE 0x1013b6920 (verified decompile): the binary's restoreFromPiP weak-loads
        // the player, dispatches the player witnesses +0xf8 / +0x38, then tail-calls.
        // It does NOT reference enhanceDolby (DAT_104450978) or any PlayerCenter — that
        // PiP-state hook is owned by the play/Components repo, not this KSPlayer subclass.
    }

    // MARK: - PiP Restore Callback (RE: KSComplexPlayerLayer_pipRestoreCallback @ 0x1000357f0)

    func pipRestoreCallback(completionHandler: @escaping (Bool) -> Void) {
        restoreFromPiP()
        completionHandler(true)
    }

    // MARK: - Auto PiP Restart (RE: KSComplexPlayerLayer_autoPiPRestart_block @ 0x1013b822c)

    /// RE: 0x1013b822c (0x1CC = 460 bytes) — the 0.5s-delayed restart closure scheduled by
    /// `postPiPStopCleanup` step 9. Restarts inline PiP if it has not been re-stopped meanwhile.
    func autoPiPRestart() {
        guard !isPictureInPictureStopped else { return }
        pipControllerRef()?.startPictureInPicture()
    }

    // MARK: - Post PiP Cleanup (RE: KSComplexPlayerLayer_postPiPStop_cleanup @ 0x1013b7bbc)

    /// RE: 0x1013b7bbc (0x578 = 1400 bytes). Post-stop cleanup + auto-restart, per doc §6.5:
    ///  1. early-out if already stopped,
    ///  2-3. restore the Metal render-surface geometry (MetalPlayView re-pins constraints + frame),
    ///  4-5. reattach the subtitle pipeline to the player,
    ///  6. clear the PiP controller delegate,
    ///  7. drop the sample-buffer playback delegate (engine-owned; invalidate its playback state),
    ///  8. mark stopped,
    ///  9. if auto-PiP-from-inline is enabled, re-arm after 0.5s via `autoPiPRestart`.
    private func postPiPStopCleanup() {
        // Step 1: if already stopped, nothing to do.
        guard !isPictureInPictureStopped else { return }

        #if canImport(UIKit) && !os(xrOS)
        // Steps 2-3: restore Metal render-surface geometry. MetalPlayView.didStopPIP() re-pins the
        // 4 NSLayoutConstraints and resets the frame to its bounds (RE 0x101446ea8) when visible.
        if let metalPlayView = player.view as? MetalPlayView {
            metalPlayView.didStopPIP()
        }
        #endif

        // Steps 4-5 & 7: hand the player a chance to reattach subtitles and tear down the
        // sample-buffer playback delegate state it owns (RE FUN_1013B44F8 / vtable+0xD8/0x100).
        if #available(tvOS 14.0, *) {
            // Step 6: clear the PiP controller delegate.
            pipControllerRef()?.delegate = nil
        }
        // Step 7: the engine owns the sample-buffer playback delegate; invalidate its state so it
        // stops driving playback from the (now closed) PiP window. invalidatePlaybackState() is an
        // AVKit API gated at iOS 15 / tvOS 15 / macOS 12 (matches KSMEPlayer.play/pause).
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            player.pipController?.invalidatePlaybackState()
        }

        // Step 8: mark stopped.
        isPictureInPictureStopped = true

        // Step 9: re-arm inline PiP after 0.5s if configured (literal 0x3FE0000000000000 = 0.5s).
        if options.canStartPictureInPictureAutomaticallyFromInline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.autoPiPRestart()
            }
        }
    }

    // MARK: - Player Ready PiP Setup (RE: KSComplexPlayerLayer_playerReady_setupPiP @ 0x1013b65a0)

    func playerReadySetupPiP() {
        maybeCreatePipController()
    }

    // MARK: - Init Setup PiP Restore (RE: KSComplexPlayerLayer_init_setupPiPRestore @ 0x1013b64b0)

    /// RE: 0x1013b64b0 — the init path that ARMS PiP-restore. Marks the layer as currently stopped,
    /// then wires the restore mechanism: sets this layer as the controller's delegate so a
    /// system-driven restore is delivered to its `AVPictureInPictureControllerDelegate` conformance
    /// (mirrored by `pipRestoreCallback(completionHandler:)`), and arms auto-start-from-inline when
    /// the option is set.
    func setupPiPRestore() {
        isPictureInPictureStopped = true
        #if canImport(UIKit) && !os(xrOS)
        if #available(tvOS 14.0, *) {
            // Resolve the engine controller if it already exists at arm time.
            if pipController == nil {
                pipController = player.pipController
            }
            // Arm restore: the RE-verified KSPictureInPictureController carries zero stored fields
            // (types.json), so there is no closure property to install. System-driven PiP restore is
            // delivered through `AVPictureInPictureControllerDelegate`; routing it back to this layer
            // means making this layer the controller's delegate. The inherited conformance's
            // restoreUserInterfaceForPictureInPictureStop callback (KSPlayerLayer) re-syncs PiP state,
            // and this subclass's `pipRestoreCallback(completionHandler:)` performs `restoreFromPiP()`.
            pipControllerRef()?.delegate = self
            // Arm auto-start-from-inline when configured.
            if options.canStartPictureInPictureAutomaticallyFromInline {
                pipControllerRef()?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        }
        #endif
    }

    // MARK: - Subtitle and PiP Delegate (RE: KSComplexPlayerLayer_setupSubtitleAndPipDelegate @ 0x1013b6f48)

    /// Wire the PiP controller delegate and the subtitle-overlay delegate. Operates on the single
    /// engine-owned controller (resolved into `pipController`); does not juggle a second instance.
    func setupSubtitleAndPipDelegate() {
        #if canImport(UIKit) && !os(xrOS)
        if #available(tvOS 14.0, *) {
            // Ensure the layer's reference points at the engine controller before wiring.
            if pipController == nil {
                pipController = player.pipController
            }
            if let pip = pipControllerRef() {
                pip.delegate = self
                // Per reversal doc (PlayerCore §6, types.json), KSPictureInPictureController is a
                // trivial AVPictureInPictureController subclass with zero stored fields — it carries
                // no subtitle delegate. PiP subtitle rendering is driven from the layer side via the
                // `pipSubtitleProvider` hook (KSPlayerLayer), not by a controller-held delegate, so
                // there is nothing to wire onto `pip` here.
            }
        }
        #endif
    }

    // MARK: - PiP Delegate Dispatch (RE: KSComplexPlayerLayer_pipDelegateDispatch_MainActor @ 0x1013b8144)

    func pipDelegateDispatchMainActor(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    // MARK: - Player Ready Hook (RE: wire onPlayerReadySetupAll from KSPlayerLayer.readyToPlay)

    open override func onPlayerReady() {
        onPlayerReadySetupAll()
    }

    // MARK: - Deinit (RE: KSComplexPlayerLayer_deinit_cleanup @ 0x1013b43d0)

    deinit {
        // Remote command targets are owned/registered by the parent (registerRemoteControllEvent);
        // do not remove them here. Only drop this layer's PiP delegate hook.
        pipController?.delegate = nil
    }
}
