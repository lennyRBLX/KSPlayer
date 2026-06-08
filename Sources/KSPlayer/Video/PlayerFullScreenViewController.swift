//
//  PlayerFullScreenViewController.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/20.
//
#if canImport(UIKit) && !os(tvOS)

import UIKit

protocol PlayerViewFullScreenDelegate: AnyObject {
    func player(isMaskShow: Bool, isFullScreen: Bool)
}

/// RE: 0x1014F045C (`_objc_opt_self(_TtC8KSPlayer30PlayerFullScreenViewController)`,
/// 1.3.15 CMa — §18.0 / §8.4; the doc's §8.4 in-section `0x1013D3D38` is a stale
/// 1.3.14 carryover, mid-body of an unrelated sort/merge helper).
///
/// `_TtC8KSPlayer30PlayerFullScreenViewController` — 2 stored properties
/// per `.reversal/types.json`: `isHorizonal :: Swift.Bool`,
/// `statusHiden :: Swift.Bool`. Both binary symbols are typos; per the
/// CLAUDE.md typo-fix rule the Swift reconstruction renames them to
/// `isHorizontal` / `statusHidden` (the binary's ivar names are retained
/// only in these comments for cross-reference to `.reversal/`).
class PlayerFullScreenViewController: UIViewController {
    // Binary ivar: `::isHorizonal` (typo) -> `isHorizontal`.
    private let isHorizontal: Bool
    // Binary ivar: `::statusHiden` (typo) -> `statusHidden`.
    private var statusHidden = false
    init(isHorizontal: Bool) {
        self.isHorizontal = isHorizontal
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// RE: 0x1014EFF58 (viewDidLoad, 1.3.15, MainActor). After super.viewDidLoad
    /// the binary writes BOTH halves of the orientation pair under one
    /// `_swift_beginAccess(&DAT_103d0b3e8, …)` lock:
    ///   DAT_103d0b3f0 = 0                       // reset the force-orientation flag
    ///   DAT_103d0b3e8 = isHorizonal ? 8 : 2     // .landscapeRight (8) : .portrait (2)
    /// `DAT_103d0b3e8` is `KSOptions.supportedInterfaceOrientations`; its +0x8
    /// partner `DAT_103d0b3f0` is the companion "force orientation" flag (see
    /// `shouldAutorotate`). The two globals are always accessed as one pair —
    /// every writer (`enterFullScreen`, the VC-orientation setter `FUN_1014dff14`,
    /// the KSVideoPlayerView landscape handler `FUN_1014a5cf0`, and this method)
    /// touches both under the same access lock.
    override func viewDidLoad() {
        super.viewDidLoad()
        // Reset the +0x8 companion flag first (DAT_103d0b3f0 = 0), then set the mask.
        // CROSS-FILE: `KSOptions.isForcingOrientation` is the modeled companion of
        // `supportedInterfaceOrientations` (see CROSS-FILE note in source summary).
        KSOptions.isForcingOrientation = false
        KSOptions.supportedInterfaceOrientations = isHorizontal ? .landscapeRight : .portrait
    }

    /// RE: 0x1014Exxx (viewWillAppear region, 1.3.15). Hides the navigation bar
    /// and disables the idle timer for the fullscreen presentation.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// RE: 0x1014F00CC (shouldAutorotate, 1.3.15, MainActor). The binary returns
    ///   (uint)(DAT_103d0b3e8 == 0x1e) & (DAT_103d0b3f0 ^ 0xff)
    /// i.e. `(supportedInterfaceOrientations == .all) && (forceFlag == 0)`.
    /// 0x1E (30) = portrait|portraitUpsideDown|landscapeLeft|landscapeRight
    /// (2|4|8|16) = `.all`. Autorotation is permitted only when the mask is the
    /// full set AND the +0x8 force-orientation flag is clear. The flag is set to
    /// `true` (with an empty mask) only while tearing down fullscreen
    /// (enterFullScreen exit branch: DAT_103d0b3e8 = 0; DAT_103d0b3f0 = 1), which
    /// pins the interface orientation during the transition.
    override var shouldAutorotate: Bool {
        KSOptions.supportedInterfaceOrientations == .all && !KSOptions.isForcingOrientation
    }

    /// RE: 0x1014F0184 (supportedInterfaceOrientations getter, 1.3.15, MainActor).
    /// Hardcoded `0x1E` in the decompile = `.portrait | .portraitUpsideDown |
    /// .landscapeLeft | .landscapeRight` (2|4|8|16 = 30), which is exactly
    /// `UIInterfaceOrientationMask.all` on iOS. §8.4 selector table, body 0x84 bytes.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    /// RE: 0x1014F0208 (prefersHomeIndicatorAutoHidden getter, 1.3.15, MainActor).
    /// Hardcoded `true`. §8.4 selector table, body 0x84 bytes.
    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    /// RE: 0x1014F00CC-0x1014F042B (1.3.15) — the binary does NOT override
    /// `preferredStatusBarStyle` on this class. The prior reconstruction's
    /// `preferredStatusBarStyle { .lightContent }` was a fabrication; closure
    /// removed it after proving via Ghidra that no such override exists.
    /// `PlayerFullScreenViewController`'s selector cluster is fully contiguous:
    ///   0x1014F00CC shouldAutorotate
    ///   0x1014F0184 supportedInterfaceOrientations
    ///   0x1014F0208 prefersHomeIndicatorAutoHidden
    ///   0x1014F0310 prefersStatusBarHidden
    ///   0x1014F03A4 initWithNibName:bundle:
    /// There is no `preferredStatusBarStyle` getter between `shouldAutorotate`
    /// and the initializer. The ONLY `preferredStatusBarStyle` getter in the
    /// whole binary belongs to a different class — `SwiftUIIntrospect`'s
    /// `IntrospectionPlatformViewController` @ 0x10133299C — and it forwards to a
    /// child VC via objc_msgSend/objc_msgSendSuper2 (it does not return
    /// `.lightContent`). The selector string @ 0x10332CDF0 has only DATA xrefs
    /// (selector-table entries), confirming no method body on this class.
    /// This VC therefore inherits `UIViewController.preferredStatusBarStyle`
    /// (`.default`); no override is reconstructed.

    /// RE: 0x1014F0310 (prefersStatusBarHidden getter, 1.3.15). Reads the VC's own
    /// `statusHidden` ivar (`*(byte*)(self + statusHiden)` in the decompile).
    override var prefersStatusBarHidden: Bool {
        statusHidden
    }
}

extension PlayerFullScreenViewController: PlayerViewFullScreenDelegate {
    func player(isMaskShow: Bool, isFullScreen: Bool) {
        if isFullScreen {
            statusHidden = !isMaskShow
            setNeedsFocusUpdate()
        }
    }
}

#endif
