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

open class IOSVideoPlayerView: VideoPlayerView {
    // MARK: - KSPlayer base ivars (13)

    private weak var originalSuperView: UIView?
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
    private var _settingsView: SettingsView?
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
        addNotification()
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

    open func isHorizonal() -> Bool {
        playerLayer?.player.naturalSize.isHorizonal ?? true
    }

    open func updateUI(isFullScreen: Bool) {
        guard let viewController else {
            return
        }
        landscapeButton.isSelected = isFullScreen
        let isHorizonal = isHorizonal()
        viewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isFullScreen
        if isFullScreen {
            if viewController is PlayerFullScreenViewController {
                return
            }
            originalSuperView = superview
            originalframeConstraints = frameConstraints
            if let originalframeConstraints {
                NSLayoutConstraint.deactivate(originalframeConstraints)
            }
            originalFrame = frame
            originalOrientations = viewController.supportedInterfaceOrientations
            let fullVC = PlayerFullScreenViewController(isHorizonal: isHorizonal)
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
            viewController.present(fullVC, animated: true) {
                KSOptions.supportedInterfaceOrientations = fullVC.supportedInterfaceOrientations
            }
        } else {
            guard viewController is PlayerFullScreenViewController else {
                return
            }
            let presentingVC = viewController.presentingViewController ?? viewController
            if let originalOrientations {
                KSOptions.supportedInterfaceOrientations = originalOrientations
            }
            presentingVC.dismiss(animated: true) {
                self.originalSuperView?.addSubview(self)
                if let constraints = self.originalframeConstraints, !constraints.isEmpty {
                    NSLayoutConstraint.activate(constraints)
                } else {
                    self.translatesAutoresizingMaskIntoConstraints = true
                    self.frame = self.originalFrame
                }
            }
        }
        let isLandscape = isFullScreen && isHorizonal
        updateUI(isLandscape: isLandscape)
    }

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
        if let originalSuperView, let animationView = playerLayer?.player.view {
            return PlayerTransitionAnimator(containerView: originalSuperView, animationView: animationView)
        }
        return nil
    }

    public func animationController(forDismissed _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if let originalSuperView, let animationView = playerLayer?.player.view {
            return PlayerTransitionAnimator(containerView: originalSuperView, animationView: animationView, isDismiss: true)
        } else {
            return nil
        }
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
        guard isHorizonal() else {
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

#if os(iOS)
@MainActor
public class MenuController {
    public init(with builder: UIMenuBuilder) {
        builder.remove(menu: .format)
        builder.insertChild(MenuController.openFileMenu(), atStartOfMenu: .file)
//        builder.insertChild(MenuController.openURLMenu(), atStartOfMenu: .file)
//        builder.insertChild(MenuController.navigationMenu(), atStartOfMenu: .file)
    }

    class func openFileMenu() -> UIMenu {
        let openCommand = UIKeyCommand(input: "O", modifierFlags: .command, action: #selector(IOSVideoPlayerView.openFileAction(_:)))
        openCommand.title = NSLocalizedString("Open File", comment: "")
        let openMenu = UIMenu(title: "",
                              image: nil,
                              identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.openFileMenu"),
                              options: .displayInline,
                              children: [openCommand])
        return openMenu
    }

//    class func openURLMenu() -> UIMenu {
//        let openCommand = UIKeyCommand(input: "O", modifierFlags: [.command, .shift], action: #selector(IOSVideoPlayerView.openURLAction(_:)))
//        openCommand.title = NSLocalizedString("Open URL", comment: "")
//        let openMenu = UIMenu(title: "",
//                              image: nil,
//                              identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.openURLMenu"),
//                              options: .displayInline,
//                              children: [openCommand])
//        return openMenu
//    }
//    class func navigationMenu() -> UIMenu {
//        let arrowKeyChildrenCommands = Arrows.allCases.map { arrow in
//            UIKeyCommand(title: arrow.localizedString(),
//                         image: nil,
//                         action: #selector(IOSVideoPlayerView.navigationMenuAction(_:)),
//                         input: arrow.command,
//                         modifierFlags: .command)
//        }
//        return UIMenu(title: NSLocalizedString("NavigationTitle", comment: ""),
//                      image: nil,
//                      identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.navigationMenu"),
//                      options: [],
//                      children: arrowKeyChildrenCommands)
//    }

    enum Arrows: String, CaseIterable {
        case rightArrow
        case leftArrow
        case upArrow
        case downArrow
        func localizedString() -> String {
            NSLocalizedString("\(rawValue)", comment: "")
        }

        @MainActor
        var command: String {
            switch self {
            case .rightArrow:
                return UIKeyCommand.inputRightArrow
            case .leftArrow:
                return UIKeyCommand.inputLeftArrow
            case .upArrow:
                return UIKeyCommand.inputUpArrow
            case .downArrow:
                return UIKeyCommand.inputDownArrow
            }
        }
    }
}
#endif
