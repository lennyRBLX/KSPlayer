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

// `_TtC8KSPlayer30PlayerFullScreenViewController` — 2 stored properties
// per `.reversal/types.json`: `isHorizonal :: Swift.Bool`,
// `statusHiden :: Swift.Bool`. Both names are typos in the binary
// (correct spellings would be `isHorizontal` / `statusHidden`); per
// CLAUDE.md typo-fix rule the Swift port can rename them, but the
// upstream KSPlayer source preserves the typos here for parity with
// the binary's symbol namespace.
class PlayerFullScreenViewController: UIViewController {
    private let isHorizonal: Bool
    private var statusHiden = false
    init(isHorizonal: Bool) {
        self.isHorizonal = isHorizonal
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        KSOptions.supportedInterfaceOrientations = isHorizonal ? .landscapeRight : .portrait
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override var shouldAutorotate: Bool {
        KSOptions.supportedInterfaceOrientations == .all
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        statusHiden
    }
}

extension PlayerFullScreenViewController: PlayerViewFullScreenDelegate {
    func player(isMaskShow: Bool, isFullScreen: Bool) {
        if isFullScreen {
            statusHiden = !isMaskShow
            setNeedsFocusUpdate()
        }
    }
}

#endif
