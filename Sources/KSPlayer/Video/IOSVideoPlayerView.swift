//
//  IOSVideoPlayerView.swift
//  Pods
//
//  Created by kintan on 2018/10/31.
//
#if canImport(UIKit) && canImport(CallKit)
import AVKit
import Combine
import CoreServices
import MediaPlayer
import Network
import UIKit

/// RE: 0x1014ECAF0 (IOSVideoPlayerView, 1.3.15 — corrected §18.0 CMa; the
/// stale §17.1 value 0x1013D03CC lands in an NSLayoutConstraint helper).
/// Superclass chain: IOSVideoPlayerView -> VideoPlayerView (0x10150B5F4) -> PlayerView (0x1013E40E4).
open class IOSVideoPlayerView: VideoPlayerView {
    // MARK: - KSPlayer base ivars (13)

    // Internal (not private): the `+ControlHandlers` extension's
    // `createTransitionAnimator` reads this snapshot of the pre-fullscreen
    // container, and `enter/exitFullScreen` write it.
    weak var originalSuperView: UIView?
    var originalframeConstraints: [NSLayoutConstraint]?
    var originalFrame = CGRect.zero
    private var originalOrientations: UIInterfaceOrientationMask?
    weak var fullScreenDelegate: PlayerViewFullScreenDelegate?
    var isVolume = false
    let volumeView = BrightnessVolume()
    public var volumeViewSlider = UXSlider()
    public var backButton = UIButton()
    public var airplayStatusView: UIView = AirplayStatusView()
    #if !os(xrOS)
    public var routeButton = AVRoutePickerView()
    #endif
    private let routeDetector = AVRouteDetector()
    /// Image view to show video cover
    public var maskImageView = UIImageView()
    public var landscapeButton: UIControl = UIButton()

    // MARK: - Forward v1.3.15 ivars (52 fields per `.reversal/UIComponents.md §1.1`)
    //
    // All field names verified via Ghidra symbol namespace
    // `_TtC8KSPlayer18IOSVideoPlayerView::*` and the decompile of
    // `initFields_and_callSuper @ 0x1014EA3DC`.

    // Buttons (11) ─────────────────────────────────────────────────────────────
    public var aspectFillButton: UIButton = .init(type: .system)
    public var screenShotButton: UIButton = .init(type: .system)
    public var previousButton: UIButton = .init(type: .system)
    public var toolBarPlayButton: UIButton = .init(type: .system)
    public var nextButton: UIButton = .init(type: .system)
    public var audioMenuButton: UIButton = .init(type: .system)
    public var subtitleMenuButton: UIButton = .init(type: .system)
    public var unifiedSettingsButton: UIButton = .init(type: .system)
    public var jumpbackButton: UIButton = .init(type: .system)
    public var playPauseButton: UIButton = .init(type: .system)
    public var jumpForwardButton: UIButton = .init(type: .system)

    // Background containers (4) ────────────────────────────────────────────────
    public let topLeftBackground = UIView()
    public let topRightBackground = UIView()
    public let bottomBackground = UIView()
    public let leftBackgroundView = UIView()

    // Status / format labels (10) ──────────────────────────────────────────────
    public var topStatusBar: UIStackView?
    public var currentItemTitleLabel: UILabel?
    public var codecLabel: UILabel?
    public var resolutionLabel: UILabel?
    public var fpsLabel: UILabel?
    public var bitrateLabel: UILabel?
    public var networkSpeedLabel: UILabel?
    public var networkStatusImageView: UIImageView?
    public var batteryImageView: UIImageView?
    public var displayTitleLabel: UILabel?

    // Video info container + metadata (5) ──────────────────────────────────────
    public let videoInfoContainer: UIStackView = {
        let v = UIStackView()
        v.spacing = 8
        v.alignment = .center
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    public var watchedProgress: Double = 0
    public var itemId: String?
    public var title: String?
    public var selectedAudioTrack: MediaPlayerTrack?

    // Network monitor + overlay views (4) ──────────────────────────────────────
    public let monitor = NWPathMonitor()
    public var screenshotPreviewView: UIView?
    public var bottomSlimProgressView: UIView?
    public var bottomSlimProgressSlider: KSSlider?

    // Prompt/toast (2) ─────────────────────────────────────────────────────────
    public let promptLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 14)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.numberOfLines = 0
        l.alpha = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    public var customDelayItem: DispatchWorkItem?

    // Symbol image configurations (3) ──────────────────────────────────────────
    // Per `initFields_and_callSuper @ 0x1014EA3DC` decompile:
    // - jumpButtonConfig: pointSize 32 (0x4040000000000000), weight 7 (.bold)
    // - playButtonConfig: pointSize 32 (0x4040000000000000), weight 7 (.bold)
    // - toolBarPlayButtonConfig: pointSize 15 (0x402E000000000000), weight 7 (.bold)
    public let jumpButtonConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
    public let playButtonConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
    public let toolBarPlayButtonConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)

    // Layout constraint ivars (8) ──────────────────────────────────────────────
    public var topStatusLeadingConstraint: NSLayoutConstraint?
    public var topStatusTrailingConstraint: NSLayoutConstraint?
    public var topLeftBackgroundLeadingConstraint: NSLayoutConstraint?
    public var topRightBackgroundTrailingConstraint: NSLayoutConstraint?
    public var leftBackgroundViewLeadingConstraint: NSLayoutConstraint?
    public var bottomBackgroundLeadingConstraint: NSLayoutConstraint?
    public var bottomBackgroundTrailingConstraint: NSLayoutConstraint?
    public var bottomBackgroundHeightConstraint: NSLayoutConstraint?

    // Speed tracker (2) ────────────────────────────────────────────────────────
    public var speedUpdateTimer: Timer?
    public var smoothedSpeed: Double = 0

    // Lazy fullscreen overlays (2) ─────────────────────────────────────────────
    // Internal (not private): `+ControlHandlers.dismissSettingsPanel` reads this
    // lazy backing store to slide the panel out and tear it down.
    var _settingsView: SettingsView?
    /// Lazy 400pt sliding settings panel.
    /// RE: `IOSVideoPlayerView_settingsView_lazyGetter @ 0x1014D8530`.
    public var settingsView: SettingsView {
        if let v = _settingsView { return v }
        let v = SettingsView()
        v.playerView = self
        v.onDismiss = { [weak self] in self?.settingsView_onDismiss() }
        _settingsView = v
        return v
    }

    private var _customProgressView: CustomProgressView?
    /// Lazy fullscreen progress view (re-parents `toolBar.timeSlider` + labels).
    public var customProgressView: CustomProgressView {
        if let v = _customProgressView { return v }
        let v = CustomProgressView(playView: self)
        _customProgressView = v
        return v
    }
    override open var isMaskShow: Bool {
        didSet {
            fullScreenDelegate?.player(isMaskShow: isMaskShow, isFullScreen: landscapeButton.isSelected)
        }
    }

    #if !os(xrOS)
    private var brightness: CGFloat = UIScreen.main.brightness {
        didSet {
            UIScreen.main.brightness = brightness
        }
    }
    #endif

    /// RE: 0x1014ECAF0 region (IOSVideoPlayerView.customizeUIComponents, 1.3.15).
    /// Inserts the cover `maskImageView`, wires the landscape + back buttons,
    /// the AirPlay route picker/status, the volume overlay, and registers route
    /// notifications. (The Forward background-view + toolbar wiring documented in
    /// `initFields_and_callSuper @ 0x1014EA3DC` / `buildFullScreenLayout @
    /// 0x1014DC1C4` is built lazily by those reconstructed methods.)
    override open func customizeUIComponents() {
        super.customizeUIComponents()
        if UIDevice.current.userInterfaceIdiom == .phone {
            subtitleLabel.font = .systemFont(ofSize: 14)
        }
        insertSubview(maskImageView, at: 0)
        maskImageView.contentMode = .scaleAspectFit
        toolBar.addArrangedSubview(landscapeButton)
        landscapeButton.tag = PlayerButtonType.landscape.rawValue
        landscapeButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .touchUpInside)
        landscapeButton.tintColor = .white
        if let landscapeButton = landscapeButton as? UIButton {
            landscapeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            landscapeButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .selected)
        }
        backButton.tag = PlayerButtonType.back.rawValue
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .touchUpInside)
        backButton.tintColor = .white
        navigationBar.insertArrangedSubview(backButton, at: 0)

        addSubview(airplayStatusView)
        volumeView.move(to: self)
        #if !targetEnvironment(macCatalyst)
        let tmp = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 0, height: 0))
        if let first = (tmp.subviews.first { $0 is UISlider }) as? UISlider {
            volumeViewSlider = first
        }
        #endif
        backButton.translatesAutoresizingMaskIntoConstraints = false
        landscapeButton.translatesAutoresizingMaskIntoConstraints = false
        maskImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            maskImageView.topAnchor.constraint(equalTo: topAnchor),
            maskImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            maskImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            maskImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 25),
            landscapeButton.widthAnchor.constraint(equalToConstant: 30),
            airplayStatusView.centerXAnchor.constraint(equalTo: centerXAnchor),
            airplayStatusView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        #if !os(xrOS)
        routeButton.isHidden = true
        navigationBar.addArrangedSubview(routeButton)
        routeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            routeButton.widthAnchor.constraint(equalToConstant: 25),
        ])
        #endif
        setupForwardControls()
        addNotification()
    }

    /// RE: 0x1014EA3DC (IOSVideoPlayerView.initFields_and_callSuper, 1.3.15 —
    /// 0x810 = 2064 bytes). The binary's designated initializer allocates the 52
    /// Forward fields (reconstructed as inline stored-property defaults per §1.1),
    /// builds the three symbol configs (`jumpButtonConfig`/`playButtonConfig` 32pt
    /// bold, `toolBarPlayButtonConfig` 15pt bold — also inline), and wires the
    /// background container views in order before calling super. The field
    /// allocation maps to Swift property defaults; the ordered background-view
    /// insertion + button-target wiring that cannot live in a default is done here,
    /// invoked from `customizeUIComponents` (KSPlayer's designated setup hook).
    open func setupForwardControls() {
        // Background containers (fields 25–28), inserted in the documented order.
        for container in [leftBackgroundView, bottomBackground, topLeftBackground, topRightBackground] {
            container.translatesAutoresizingMaskIntoConstraints = false
            container.backgroundColor = .clear
            addSubview(container)
        }
        // Forward toolbar buttons route through the central tag router.
        let forwardButtons: [UIButton] = [
            aspectFillButton, screenShotButton, previousButton, toolBarPlayButton,
            nextButton, audioMenuButton, subtitleMenuButton, unifiedSettingsButton,
            jumpbackButton, playPauseButton, jumpForwardButton,
        ]
        for button in forwardButtons {
            button.tintColor = .white
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(handleButtonAction(_:)), for: .touchUpInside)
        }
        // Jump / play buttons adopt the 32pt-bold symbol configs; the compact
        // toolbar play button uses the 15pt-bold config (per §1.4).
        jumpForwardButton.setImage(UIImage(systemName: "goforward.15", withConfiguration: jumpButtonConfig), for: .normal)
        jumpbackButton.setImage(UIImage(systemName: "gobackward.15", withConfiguration: jumpButtonConfig), for: .normal)
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playButtonConfig), for: .normal)
        toolBarPlayButton.setImage(UIImage(systemName: "play.fill", withConfiguration: toolBarPlayButtonConfig), for: .normal)
        // Status / format labels live in the video-info container, created lazily
        // by `createStatusLabels()`; build them now so the overlay is populated.
        createStatusLabels()
    }

    override open func resetPlayer() {
        super.resetPlayer()
        maskImageView.alpha = 1
        maskImageView.image = nil
        panGesture.isEnabled = false
        #if !os(xrOS)
        routeButton.isHidden = !routeDetector.multipleRoutesDetected
        #endif
    }

    /// RE: 0x1014ECAF0 region (IOSVideoPlayerView.onButtonPressed, 1.3.15).
    /// Base `PlayerButtonType` handler: back exits fullscreen, lock toggles the
    /// mask, landscape toggles fullscreen. The Forward-specific toolbar buttons
    /// (audio/subtitle/settings/aspect/jump/screenshot) route through
    /// `handleButtonAction(_:)` instead — see below.
    override open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
        if type == .back, viewController is PlayerFullScreenViewController {
            updateUI(isFullScreen: false)
            return
        }
        super.onButtonPressed(type: type, button: button)
        if type == .lock {
            button.isSelected.toggle()
            isMaskShow = !button.isSelected
            button.alpha = 1.0
        } else if type == .landscape {
            updateUI(isFullScreen: !landscapeButton.isSelected)
        }
    }

    /// RE: 0x1014DF4C4 (IOSVideoPlayerView.handleButtonAction, 1.3.15 — 0x214 =
    /// 532 bytes). Central button-tag router for the Forward toolbar buttons.
    /// Dispatches by `sender.tag`: the base `PlayerButtonType` tags (back /
    /// landscape / lock / play) fall through to `onButtonPressed`, while the
    /// Forward additions map to their dedicated handlers. Wired by
    /// `buildFullScreenLayout` / `initFields_and_callSuper` on `.touchUpInside`.
    @objc open func handleButtonAction(_ sender: UIButton) {
        if sender === audioMenuButton {
            buildAudioTrackMenu()
        } else if sender === subtitleMenuButton {
            handleSubtitleMenuSetup()
        } else if sender === unifiedSettingsButton {
            handleSettingsButtonTapped()
        } else if sender === aspectFillButton {
            handleAspectFillButtonTapped()
        } else if sender === screenShotButton {
            handleScreenshot()
        } else if sender === jumpForwardButton {
            handleJumpForward()
        } else if sender === jumpbackButton {
            handleJumpBack()
        } else if sender === playPauseButton || sender === toolBarPlayButton {
            handlePlayPause()
        } else if let type = PlayerButtonType(rawValue: sender.tag) {
            // Base PlayerButtonType tags (back/landscape/lock/play) fall through to
            // the tag-typed handler shared with the toolbar/navigation bar.
            onButtonPressed(type: type, button: sender)
        }
    }

    /// RE: 0x1014ECAF0 region (IOSVideoPlayerView, 1.3.15). Typo fix per brief:
    /// `isHorizonal` -> `isHorizontal` (the method name is already corrected).
    /// CROSS-FILE NEEDED: the CGSize extension property is still misspelled
    /// `isHorizonal` in KSPlayer/Sources/KSPlayer/Core/Utility.swift:340 and should
    /// be renamed to `isHorizontal`. That property's ONLY reader is this call site
    /// (verified: no other `.isHorizonal` reference exists in the module), so the
    /// rename is a two-line change — Utility.swift:340 + the line below. Owned by the
    /// Utility.swift cluster, not this one; until it lands the body reads the
    /// still-misspelled CGSize property so this cluster keeps compiling.
    open func isHorizontal() -> Bool {
        playerLayer?.player.naturalSize.isHorizonal ?? true
    }

    /// RE: enter/exit fullscreen orchestration (IOSVideoPlayerView, 1.3.15).
    /// Public entry that toggles fullscreen; delegates the actual presentation to
    /// the API-surface-preserved `enterFullScreen` / `exitFullScreen` pair below
    /// (binary keeps enter @ 0x1014DF7A0 and exit-dismiss @ 0x1014DFFF4 separate).
    open func updateUI(isFullScreen: Bool) {
        guard viewController != nil else {
            return
        }
        landscapeButton.isSelected = isFullScreen
        let horizontal = isHorizontal()
        viewController?.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isFullScreen
        if isFullScreen {
            enterFullScreen()
        } else {
            exitFullScreen()
        }
        let isLandscape = isFullScreen && horizontal
        updateUI(isLandscape: isLandscape)
    }

    /// RE: 0x1014DF7A0 (IOSVideoPlayerView.enterFullScreen, 1.3.15 — 0x774 = 1908
    /// bytes, 10-step flow). Dedicated enter path: snapshot the original
    /// superview/constraints/frame/orientations, re-parent into a
    /// `PlayerFullScreenViewController`, then present. The present-completion is the
    /// separate `enterFullScreen_presentCompletion` per the API-surface rule.
    open func enterFullScreen() {
        guard let viewController, !(viewController is PlayerFullScreenViewController) else {
            return
        }
        originalSuperView = superview
        originalframeConstraints = frameConstraints
        if let originalframeConstraints {
            NSLayoutConstraint.deactivate(originalframeConstraints)
        }
        originalFrame = frame
        originalOrientations = viewController.supportedInterfaceOrientations
        let fullVC = PlayerFullScreenViewController(isHorizontal: isHorizontal())
        fullScreenDelegate = fullVC
        fullVC.view.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: fullVC.view.readableTopAnchor),
            leadingAnchor.constraint(equalTo: fullVC.view.leadingAnchor),
            trailingAnchor.constraint(equalTo: fullVC.view.trailingAnchor),
            bottomAnchor.constraint(equalTo: fullVC.view.bottomAnchor),
        ])
        fullVC.modalPresentationStyle = .fullScreen
        fullVC.modalPresentationCapturesStatusBarAppearance = true
        fullVC.transitioningDelegate = self
        viewController.present(fullVC, animated: true) { [weak self] in
            self?.enterFullScreen_presentCompletion(fullVC)
        }
    }

    /// RE: 0x1013C37A8 (IOSVideoPlayerView enter-fullscreen present-completion,
    /// 1.3.15 — 0x44 = 68 bytes, MainActor). Stores the presented orientation mask
    /// in `KSOptions.supportedInterfaceOrientations`. (The binary stashes the
    /// presented VC in global storage; here the live reference is held by the
    /// responder chain, so only the orientation hand-off remains.)
    open func enterFullScreen_presentCompletion(_ fullVC: PlayerFullScreenViewController?) {
        guard let fullVC else { return }
        KSOptions.supportedInterfaceOrientations = fullVC.supportedInterfaceOrientations
    }

    /// RE: exit-fullscreen dispatch (IOSVideoPlayerView, 1.3.15). Restores the
    /// pre-fullscreen orientation mask and dismisses; the dismiss-completion that
    /// re-parents self is the separate `exitFullScreen_dismissCompletion` @
    /// 0x1014DFFF4 per the API-surface rule.
    open func exitFullScreen() {
        guard let viewController, viewController is PlayerFullScreenViewController else {
            return
        }
        let presentingVC = viewController.presentingViewController ?? viewController
        if let originalOrientations {
            KSOptions.supportedInterfaceOrientations = originalOrientations
        }
        presentingVC.dismiss(animated: true) { [weak self] in
            self?.exitFullScreen_dismissCompletion()
        }
    }

    /// RE: 0x1014DFFF4 (IOSVideoPlayerView exit-fullscreen dismiss-completion,
    /// 1.3.15 — 0x1B8 = 440 bytes). Restores self to `originalSuperView` and
    /// reactivates `originalframeConstraints`; falls back to the saved
    /// `originalFrame` with autoresizing if no constraints were captured.
    open func exitFullScreen_dismissCompletion() {
        originalSuperView?.addSubview(self)
        if let constraints = originalframeConstraints, !constraints.isEmpty {
            NSLayoutConstraint.activate(constraints)
        } else {
            translatesAutoresizingMaskIntoConstraints = true
            frame = originalFrame
        }
    }

    /// RE: 0x1014ECAF0 region (IOSVideoPlayerView.updateUI(isLandscape:), 1.3.15).
    /// Toggles the top mask, playback-rate / subtitle / landscape / lock controls
    /// based on landscape vs. portrait and device idiom, then re-evaluates the pan
    /// gesture via `judgePanGesture`.
    open func updateUI(isLandscape: Bool) {
        if isLandscape {
            topMaskView.isHidden = KSOptions.topBarShowInCase == .none
        } else {
            topMaskView.isHidden = KSOptions.topBarShowInCase != .always
        }
        toolBar.playbackRateButton.isHidden = false
        toolBar.srtButton.isHidden = srtControl.subtitleInfos.isEmpty
        if UIDevice.current.userInterfaceIdiom == .phone {
            if isLandscape {
                landscapeButton.isHidden = true
                toolBar.srtButton.isHidden = srtControl.subtitleInfos.isEmpty
            } else {
                toolBar.srtButton.isHidden = true
                if let image = maskImageView.image {
                    landscapeButton.isHidden = image.size.width < image.size.height
                } else {
                    landscapeButton.isHidden = false
                }
            }
            toolBar.playbackRateButton.isHidden = !isLandscape
        } else {
            landscapeButton.isHidden = true
        }
        lockButton.isHidden = !isLandscape
        judgePanGesture()
    }

    override open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        if state == .readyToPlay {
            UIView.animate(withDuration: 0.3) {
                self.maskImageView.alpha = 0.0
            }
        }
        judgePanGesture()
    }

    override open func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        airplayStatusView.isHidden = !layer.player.isExternalPlaybackActive
        super.player(layer: layer, currentTime: currentTime, totalTime: totalTime)
    }

    override open func set(resource: KSPlayerResource, definitionIndex: Int = 0, isSetUrl: Bool = true) {
        super.set(resource: resource, definitionIndex: definitionIndex, isSetUrl: isSetUrl)
        maskImageView.image(url: resource.cover)
    }

    override open func change(definitionIndex: Int) {
        Task {
            let image = await playerLayer?.player.thumbnailImageAtCurrentTime()
            if let image {
                self.maskImageView.image = UIImage(cgImage: image)
                self.maskImageView.alpha = 1
            }
            super.change(definitionIndex: definitionIndex)
        }
    }

    /// RE: 0x1014E0D84 (IOSVideoPlayerView.panGestureBegan, 1.3.15 — 0xFC = 252
    /// bytes). Direction detect + `tmpPanValue` init: a vertical pan on the right
    /// half arms volume (seeding `tmpPanValue` from the system volume slider), the
    /// left half arms brightness; a horizontal pan delegates to super, which seeds
    /// `tmpPanValue` from the time slider for the seek path.
    override open func panGestureBegan(location point: CGPoint, direction: KSPanDirection) {
        if direction == .vertical {
            if point.x > bounds.size.width / 2 {
                isVolume = true
                tmpPanValue = volumeViewSlider.value
            } else {
                isVolume = false
            }
        } else {
            super.panGestureBegan(location: point, direction: direction)
        }
    }

    /// RE: 0x1014E0E80 (IOSVideoPlayerView.panGestureChanged, 1.3.15 — 0x3A4 = 932
    /// bytes). Three-branch dispatch: vertical+volume adjusts the volume slider
    /// (gated by `KSOptions.enableVolumeGestures`), vertical+brightness adjusts
    /// screen brightness (gated by `KSOptions.enableBrightnessGestures`), and
    /// horizontal delegates to super for the seek branch.
    override open func panGestureChanged(velocity point: CGPoint, direction: KSPanDirection) {
        if direction == .vertical {
            if isVolume {
                if KSOptions.enableVolumeGestures {
                    tmpPanValue += panValue(velocity: point, direction: direction, currentTime: Float(toolBar.currentTime), totalTime: Float(totalTime))
                    tmpPanValue = max(min(tmpPanValue, 1), 0)
                    volumeViewSlider.value = tmpPanValue
                }
            } else if KSOptions.enableBrightnessGestures {
                #if !os(xrOS)
                brightness += CGFloat(panValue(velocity: point, direction: direction, currentTime: Float(toolBar.currentTime), totalTime: Float(totalTime)))
                #endif
            }
        } else {
            super.panGestureChanged(velocity: point, direction: direction)
        }
    }

    /// RE: 0x1014ECAF0 region (IOSVideoPlayerView.judgePanGesture, 1.3.15). Enables
    /// the pan recognizer only when playback is active: in landscape/iPad it
    /// requires `isPlayed && !replay`, otherwise it tracks the toolbar play state.
    open func judgePanGesture() {
        if landscapeButton.isSelected || UIDevice.current.userInterfaceIdiom == .pad {
            panGesture.isEnabled = isPlayed && !replayButton.isSelected
        } else {
            panGesture.isEnabled = toolBar.playButton.isSelected
        }
    }
}

extension IOSVideoPlayerView: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented _: UIViewController, presenting _: UIViewController, source _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        createTransitionAnimator(isDismiss: false)
    }

    public func animationController(forDismissed _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        createTransitionAnimator(isDismiss: true)
    }
}

// MARK: - private functions

extension IOSVideoPlayerView {
    private func addNotification() {
//        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routesAvailableDidChange), name: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: nil)
    }

    @objc private func routesAvailableDidChange(notification _: Notification) {
        #if !os(xrOS)
        routeButton.isHidden = !routeDetector.multipleRoutesDetected
        #endif
    }

    @objc private func orientationChanged(notification _: Notification) {
        guard isHorizontal() else {
            return
        }
        updateUI(isFullScreen: UIApplication.isLandscape)
    }
}

public class AirplayStatusView: UIView {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        let airplayicon = UIImageView(image: UIImage(systemName: "airplayvideo"))
        addSubview(airplayicon)
        let airplaymessage = UILabel()
        airplaymessage.backgroundColor = .clear
        airplaymessage.textColor = .white
        airplaymessage.font = .systemFont(ofSize: 14)
        airplaymessage.text = NSLocalizedString("AirPlay 投放中", comment: "")
        airplaymessage.textAlignment = .center
        addSubview(airplaymessage)
        translatesAutoresizingMaskIntoConstraints = false
        airplayicon.translatesAutoresizingMaskIntoConstraints = false
        airplaymessage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 100),
            heightAnchor.constraint(equalToConstant: 115),
            airplayicon.topAnchor.constraint(equalTo: topAnchor),
            airplayicon.centerXAnchor.constraint(equalTo: centerXAnchor),
            airplayicon.widthAnchor.constraint(equalToConstant: 100),
            airplayicon.heightAnchor.constraint(equalToConstant: 100),
            airplaymessage.bottomAnchor.constraint(equalTo: bottomAnchor),
            airplaymessage.leadingAnchor.constraint(equalTo: leadingAnchor),
            airplaymessage.trailingAnchor.constraint(equalTo: trailingAnchor),
            airplaymessage.heightAnchor.constraint(equalToConstant: 15),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public extension KSOptions {
    /// func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask
    static var supportedInterfaceOrientations = UIInterfaceOrientationMask.portrait
}

extension UIApplication {
    static var isLandscape: Bool {
        UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isLandscape ?? false
    }
}

// MARK: - menu

extension IOSVideoPlayerView {
    override open var canBecomeFirstResponder: Bool {
        true
    }

    override open func canPerformAction(_ action: Selector, withSender _: Any?) -> Bool {
        if action == #selector(IOSVideoPlayerView.openFileAction) {
            return true
        }
        return true
    }

    @objc fileprivate func openFileAction(_: AnyObject) {
        let documentPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeAudio, kUTTypeMovie, kUTTypePlainText] as [String], in: .open)
        documentPicker.delegate = self
        viewController?.present(documentPicker, animated: true, completion: nil)
    }
}

extension IOSVideoPlayerView: UIDocumentPickerDelegate {
    public func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            if url.isMovie || url.isAudio {
                set(url: url, options: KSOptions())
            } else {
                srtControl.selectedSubtitleInfo = URLSubtitleInfo(url: url)
            }
        }
    }
}

#endif

// NOTE: `MenuController` (RE 0x1014ED910) was relocated to
// `KSMenu.swift` per the UIComponents cluster map, which designates that
// file as its canonical home. The previous copy here also carried
// upstream sample-code scaffolding (`Arrows` enum, commented-out
// `openURLMenu()` / `navigationMenu()`) that has no RE-derived backing in
// the 1.3.15 binary (Ghidra names only `buildSubtitleMenu` and
// `buildOpenFileMenu`), so it was dropped during the move.
