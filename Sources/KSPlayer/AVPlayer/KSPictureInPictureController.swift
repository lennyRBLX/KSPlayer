//
//  KSPictureInPictureController.swift
//  KSPlayer
//
//  Created by kintan on 2023/1/28.
//
//  RE: Forward v1.3.15. AVPictureInPictureController subclass that owns the engine's PiP
//  lifecycle. The content-source init override at 0x1013ac580 is the only entry the type-metadata
//  inventory surfaces (types.json lists 0 *Swift-managed* stored fields because the navigation /
//  view-controller back-references are weak/optional and the active-controller handle is a static),
//  but the type also carries the start/stop/mute lifecycle and the subtitle + restore delegate
//  hooks that KSPlayerLayer and KSComplexPlayerLayer drive (subtitle wiring: RE
//  KSComplexPlayerLayer_setupSubtitleAndPipDelegate @ 0x1013b6f48). The controller is instantiated
//  from the Metal/FFmpeg sample-buffer pipeline (KSMEPlayer/KSAVPlayer `pipController` accessors).
//

import AVKit

/// The engine's Picture-in-Picture controller.
///
/// RE: class metadata accessor `$s8KSPlayer28KSPictureInPictureControllerCMa` @ 0x1013ac5cc
/// (32 bytes, body 0x1013ac5cc–0x1013ac5eb; calls `_objc_opt_self(&_TtC8KSPlayer28KSPictureInPictureController)`).
///
/// Trivial subclass of `AVPictureInPictureController` with **no stored fields** — it uses the
/// superclass storage. The content source is built from a sample-buffer display layer plus a
/// playback delegate (`AVPictureInPictureControllerContentSource(sampleBufferDisplayLayer:playbackDelegate:)`),
/// i.e. it renders from the Metal/FFmpeg pipeline sample buffers rather than via AVPlayer passthrough.
///
/// `tvOS 14.0` is the availability floor for `AVPictureInPictureController` on tvOS (PiP arrived in
/// tvOS 14); this matches the gating on every other PiP reference in the engine (KSMEPlayer /
/// KSAVPlayer `pipController` accessors, KSPlayerLayer PiP wiring).
@available(tvOS 14.0, *)
public class KSPictureInPictureController: AVPictureInPictureController {
    /// The currently-active PiP controller. PiP is single-instance: starting a new session muffles
    /// and tears down the previous one (see `start(view:)`). Held statically so `mute()` and the
    /// hand-off in `start(view:)` can reach the live controller without a layer reference.
    private static var pipController: KSPictureInPictureController?
    /// The view controller that was on screen when PiP started; restored on stop.
    private var originalViewController: UIViewController?
    /// The layer whose player is driving this PiP session. Strong: PiP must keep the player alive
    /// while in the background. Cleared on stop.
    private var view: KSPlayerLayer?
    /// The (possibly navigation-wrapped) controller PiP popped off the stack, restored on stop.
    private weak var viewController: UIViewController?
    /// The presenter used when PiP dismissed a modally-presented player, re-presented on stop.
    private weak var presentingViewController: UIViewController?
    /// Delegate that supplies rendered subtitle frames for the PiP overlay. Wired from the player
    /// layer in `start(view:)` (the layer adopts `KSPipSubtitleDelegate`). RE: subtitle hand-off in
    /// KSComplexPlayerLayer_setupSubtitleAndPipDelegate @ 0x1013b6f48.
    public weak var subtitleDelegate: KSPipSubtitleDelegate?
    /// Invoked when PiP is about to restore the inline UI — used by `KSComplexPlayerLayer` to
    /// re-sync subtitle state on return from the PiP window.
    public var pipRestoreCallback: (() -> Void)?
    #if canImport(UIKit)
    /// The navigation controller PiP manipulated, captured so the inline player can be pushed back.
    private weak var navigationController: UINavigationController?
    #endif

    /// RE: init(contentSource:) @ 0x1013ac580 (FUN_1013ac580, 1.3.15).
    /// Decompile: after `_objc_opt_self(&_TtC8KSPlayer28KSPictureInPictureController)` (the metadata
    /// accessor, 0x1013ac5cc), invokes `_objc_msgSendSuper2(self, initWithContentSource:, source)` —
    /// a straight forward to the designated superclass initializer with no added behavior.
    ///
    /// The content-source designated initializer is iOS 15.0 / tvOS 15.0 / macOS 12.0+, so this
    /// override carries the stricter floor (the sample-buffer content source the engine passes in is
    /// itself only constructible from that OS version onward).
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    override public init(contentSource: AVPictureInPictureController.ContentSource) {
        super.init(contentSource: contentSource)
    }

    /// Begin a PiP session driven by `view`'s player. Wires the layer as both the
    /// `AVPictureInPictureControllerDelegate` and the subtitle provider, then — when
    /// `KSOptions.isPipPopViewController` is set — pops/dismisses the inline player UI so the system
    /// PiP window takes over. A second start while another session is live mutes the newcomer and
    /// deactivates the prior one (single-instance PiP).
    func start(view: KSPlayerLayer) {
        startPictureInPicture()
        delegate = view
        subtitleDelegate = view
        guard KSOptions.isPipPopViewController else {
            #if canImport(UIKit)
            // Send the app to the background directly when not popping the player view controller.
            runOnMainThread {
                UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
            }
            #endif
            return
        }
        self.view = view
        #if canImport(UIKit)
        runOnMainThread { [weak self] in
            guard let self, let viewController = view.player.view?.viewController else { return }

            originalViewController = viewController
            if let navigationController = viewController.navigationController, navigationController.viewControllers.count == 1 {
                self.viewController = navigationController
            } else {
                self.viewController = viewController
            }
            navigationController = self.viewController?.navigationController
            if let pre = KSPictureInPictureController.pipController {
                view.player.isMuted = true
                pre.view?.isPipActive = false
            } else {
                if let navigationController {
                    navigationController.popViewController(animated: true)
                    #if os(iOS)
                    if navigationController.tabBarController != nil, navigationController.viewControllers.count == 1 {
                        DispatchQueue.main.async { [weak self] in
                            self?.navigationController?.setToolbarHidden(false, animated: true)
                        }
                    }
                    #endif
                } else {
                    presentingViewController = originalViewController?.presentingViewController
                    originalViewController?.dismiss(animated: true)
                }
            }
        }
        #endif
        KSPictureInPictureController.pipController = self
    }

    /// Stop the PiP session. Tears down the AVKit delegate, and — when
    /// `KSOptions.isPipPopViewController` is set — optionally restores the inline player UI that
    /// `start(view:)` popped or dismissed. `restoreUserInterface` is `false` when AVKit reports the
    /// system already restored the UI (`pictureInPictureControllerDidStopPictureInPicture`), `true`
    /// for an explicit programmatic stop. Always fires `pipRestoreCallback` and clears state.
    func stop(restoreUserInterface: Bool) {
        stopPictureInPicture()
        delegate = nil
        guard KSOptions.isPipPopViewController else {
            return
        }
        KSPictureInPictureController.pipController = nil
        if restoreUserInterface {
            #if canImport(UIKit)
            runOnMainThread { [weak self] in
                guard let self, let viewController, let originalViewController else { return }
                if let nav = viewController as? UINavigationController,
                   nav.viewControllers.isEmpty || (nav.viewControllers.count == 1 && nav.viewControllers[0] != originalViewController)
                {
                    nav.viewControllers = [originalViewController]
                }
                if let navigationController {
                    var viewControllers = navigationController.viewControllers
                    if viewControllers.count > 1, let last = viewControllers.last, type(of: last) == type(of: viewController) {
                        viewControllers[viewControllers.count - 1] = viewController
                        navigationController.viewControllers = viewControllers
                    }
                    if viewControllers.firstIndex(of: viewController) == nil {
                        // After a new SwiftUI push the view becomes an empty view, leaving the page
                        // blank — push the captured inline controller back to restore it.
                        navigationController.pushViewController(viewController, animated: true)
                    }
                } else {
                    presentingViewController?.present(originalViewController, animated: true)
                }
            }
            #endif
            view?.player.isMuted = false
            view?.play()
        }

        pipRestoreCallback?()
        originalViewController = nil
        view = nil
    }

    /// Mute the player backing the active PiP session, if any. Called when a new inline playback
    /// starts so two streams don't sound at once.
    static func mute() {
        pipController?.view?.player.isMuted = true
    }
}
