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
    private weak var originalSuperView: UIView?
    private var originalframeConstraints: [NSLayoutConstraint]?
    private var originalFrame = CGRect.zero
    // ⚑[tool=export_trie_oracle ref=IOSVideoPlayerView.originalOrientations:none result=absent-from-binary]
    // This field is in SOURCE and in NO part of the binary: it has no __swift5_fieldmd record (the
    // class reflects 65, and this is not among them), no `vpfi`, and no getter/setter/modify symbol
    // anywhere in the orphaned export trie — a genuine negative from the one tool that can see the
    // orphan (`nm` and reflection cannot, so every pre-s63 negative taken with those is suspect, P133).
    // Kept rather than deleted: it is READ at `updateUI(isFullScreen:)` below, so removing it means
    // reconstructing that body against the binary, which is a separate unit with its own evidence.
    // Deleting the field and inventing replacement logic would be fabrication; this is the deferral.
    // originalOrientations REMOVED: IOSVideoPlayerView's FieldDescriptor holds 65 records and this
    // is not among them — records 0-3 are originalSuperView, originalframeConstraints,
    // originalFrame, fullScreenDelegate — and no such field symbol exists for the class. Its two
    // uses go with it: the capture in the enter-fullscreen arm and the restore in the exit arm.
    private weak var fullScreenDelegate: PlayerViewFullScreenDelegate?
    private var isVolume = false
    private let volumeView = BrightnessVolume()
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
    // Fields 14-62 of 65 in __swift5_fieldmd order. NAME/ORDER from the field records, ACCESS from
    // the export trie, let/var from each FieldRecord's Flags bit (IsVar 0x2), and every initializer
    // EXPRESSION from that property's own `vpfi` (variable initialization expression) function —
    // the compiler emits one per declaration default, and its body IS the expression. Recovered with
    // scripts/vpfi_initializer_oracle.py; independently re-derived by two audit agents from
    // llvm-objdump + dyld_info fixups, with compiled controls for every enum raw value.
    // ⚠️ `UIButton(type: .system)` is NOT interchangeable with `UIButton()`: they are distinct vpfi
    // bodies (`+buttonWithType:` with x2=1 vs `allocWithZone`+`-init`), and backButton/landscapeButton
    // above sit in the `UIButton()` body — which is what makes these eleven decidable rather than
    // assumed. `.roundedRect` is also raw value 1, so the binary cannot distinguish that spelling.
    public var aspectFillButton = UIButton(type: .system)
    public var screenShotButton = UIButton(type: .system)
    public let previousButton = UIButton(type: .system)
    public let toolBarPlayButton = UIButton(type: .system)
    public let nextButton = UIButton(type: .system)
    public let audioMenuButton = UIButton(type: .system)
    public let subtitleMenuButton = UIButton(type: .system)
    public let unifiedSettingsButton = UIButton(type: .system)
    public let jumpbackButton = UIButton(type: .system)
    public let playPauseButton = UIButton(type: .system)
    public let jumpForwardButton = UIButton(type: .system)
    // The four background vpfi bodies are bit-identical, so each of these four declarations has
    // exactly this effect. Written out rather than routed through a shared factory: a WMO-inlined
    // helper would emit the same four bodies, so the binary cannot distinguish the two spellings and
    // inventing a helper would add a declaration the evidence does not require.
    private let topLeftBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.alpha = 0.4
        return view
    }()

    private let topRightBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.alpha = 0.4
        return view
    }()

    private let bottomBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.alpha = 0.4
        return view
    }()

    private let leftBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.alpha = 0.4
        return view
    }()

    private var topStatusBar: UIStackView?
    private var currentItemTitleLabel: UILabel?
    private var codecLabel: UILabel?
    private var resolutionLabel: UILabel?
    private var fpsLabel: UILabel?
    private var bitrateLabel: UILabel?
    private var networkSpeedLabel: UILabel?
    private var networkStatusImageView: UIImageView?
    private var batteryImageView: UIImageView?
    private var displayTitleLabel: UILabel?
    private let videoInfoContainer: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var watchedProgress: Double = 0
    private var itemId: String?
    public var title: String?
    // `MediaPlayerTrack` is a class-bound protocol, so this existential is 2 words — which the vpfi
    // corroborates independently: its body zeroes BOTH x0 and x1, unlike the 1-word nil the
    // class-reference optionals below get.
    var selectedAudioTrack: (any MediaPlayerTrack)?
    let monitor = NWPathMonitor()
    private var screenshotPreviewView: UIView?
    private var bottomSlimProgressView: UIView?
    private var bottomSlimProgressSlider: KSSlider?
    // `backgroundColor` is never set here — a positively-established absence (all 54 instructions of
    // the vpfi are accounted for), not an omission.
    private let promptLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 5
        label.clipsToBounds = true
        label.alpha = 0
        return label
    }()

    private var customDelayItem: DispatchWorkItem?
    private let jumpButtonConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
    private let playButtonConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
    private let toolBarPlayButtonConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
    private var topStatusLeadingConstraint: NSLayoutConstraint?
    private var topStatusTrailingConstraint: NSLayoutConstraint?
    private var topLeftBackgroundLeadingConstraint: NSLayoutConstraint?
    private var topRightBackgroundTrailingConstraint: NSLayoutConstraint?
    private var leftBackgroundViewLeadingConstraint: NSLayoutConstraint?
    private var bottomBackgroundLeadingConstraint: NSLayoutConstraint?
    private var bottomBackgroundTrailingConstraint: NSLayoutConstraint?
    private var bottomBackgroundHeightConstraint: NSLayoutConstraint?
    private var speedUpdateTimer: Timer?
    private var smoothedSpeed: Double = 0
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer18IOSVideoPlayerViewC026$__lazy_storage_$_settingsD033_99D4461AEE15ECA71DEBF361B80F60DDLLAA08SettingsD0CSgvpfi:0x10002d9d4 result=pinned]
    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer18IOSVideoPlayerViewC032$__lazy_storage_$_customProgressD033_99D4461AEE15ECA71DEBF361B80F60DDLLAA06CustomhD0CSgvpfi:0x10002d9d4 result=pinned]
    // Field slots 63 and 65 are `private lazy var settingsView: SettingsView` and
    // `private lazy var customProgressView: CustomProgressView` — names AND exact types recovered
    // from their getter/setter/modify signatures in the orphan trie. NOT declared here because
    // neither class exists in the reconstruction yet (they are part of the 11-unit SettingsView /
    // CustomProgressView stand-up), so declaring them could not compile. This is a pinned deferral,
    // not an unknown: it refutes the standing note that those two are "NOT_IN_TRIE — no class AND no
    // recoverable name". Both are gate-invisible either way (l2_field_gate drops `$`-prefixed records
    // on the binary side and `lazy` on the source side, symmetrically).
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

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.IOSVideoPlayerView.doubleTapGestureAction():0x101b10d18 result=84-instr]
    /// A genuine behavioural override — `VideoPlayerView.doubleTapGestureAction()` sends
    /// `primaryActionTriggered` and shows the mask, which is nothing like this body.
    ///
    /// Every field here is named by READING the offset global's VALUE against the owning class's
    /// field-offset vector, and the three globals come from three DIFFERENT classes in the chain:
    ///   0x1044f1840 = `VideoPlayerView.doubleTapGesture`
    ///   0x1044e74e8 = `PlayerView.playerLayer`
    ///   0x104c634f0 = `KSPlayerLayer.player`
    /// ⚑[tool=decode_objc_selector ref=0x10440c078 result='locationInView:']
    /// ⚑[tool=decode_objc_selector ref=0x10440a900 result='bounds']
    /// ⚑[tool=bind_oracle ref=__got:0x104108fe0 result=_CGRectGetWidth]
    ///
    /// · `currentPlaybackTime` is reached through the BASE protocol's table, not the main one:
    ///   `wt+0x8` is `MediaPlayback`'s witness table and its `+0x28` slot thunks to
    ///   ⚑[tool=export_trie_oracle ref=0x101a41fe4 result=KSMEPlayer.currentPlaybackTime.getter]
    /// · The seek is `KSPlayerLayer` vtable slot 65 (metadata word +0x2e0),
    ///   ⚑[tool=vtable_walk ref=KSPlayerLayer:slot65 result=seek(time:autoPlay:completion:)]
    ///   called with `w0 = 1` (autoPlay) and `x1 = x2 = 0` (nil completion).
    /// · `fcsel ..., mi` against `width * 0.5` picks **-10.0** on the left half and **+10.0** on
    ///   the right; both constants are `fmov` immediates, not loads.
    ///
    /// ⚑ `playerLayer` is loaded and nil-checked TWICE, which is why this is written as two
    ///   `playerLayer?` accesses rather than one `if let`: the getter call between them is opaque
    ///   to the optimizer, so a single binding would have produced one load.
    override open func doubleTapGestureAction() {
        let point = doubleTapGesture.location(in: self)
        if let currentPlaybackTime = playerLayer?.player.currentPlaybackTime {
            let delta = point.x < bounds.width * 0.5 ? -10.0 : 10.0
            playerLayer?.seek(time: currentPlaybackTime + delta, autoPlay: true, completion: nil)
        }
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.IOSVideoPlayerView.tapGestureAction(_:):0x101b10bc0 result=22-instr]
    /// The whole body is one toggle, and every part of that is read:
    ///   · The dispatch is a MODIFY COROUTINE, not a getter/setter pair — `x0 = sp` hands the
    ///     callee a frame, the call returns a continuation in x0 and a pointer to the value in x1,
    ///     and the second `blr x8` with `w1 = 0` resumes it.
    ///   · Metadata word +0x318 of 0x1044234e8 is
    ///     ⚑[tool=export_trie_oracle ref=0x101b02a70 result=IOSVideoPlayerView.isMaskShow.modify]
    ///   · `ldrb w9` / `bic w9, #1, w9` / `strb w9` is `1 & ~w9`, which for a `Bool` is exactly
    ///     `toggle()`.
    ///
    /// ⚑ THIS LOOKS REDUNDANT AND IS NOT AN ARTIFACT. `VideoPlayerView.tapGestureAction` already
    ///   has the identical body, and the two symbols ICF-fold onto this one address — which is
    ///   precisely what makes the §2o inheritance screen call it an artifact. That screen is
    ///   wrong here: it reads "the same member name appears under two classes at one address" as
    ///   "declared on the ancestor and inherited", and an ICF fold of two IDENTICAL bodies
    ///   produces the same signature. The distinguishing fact is that an inherited member emits
    ///   NO symbol under the subclass at all, and this one has its own —
    ///   `export_trie_oracle --addr 0x101b10bc0 --owner IOSVideoPlayerView` returns OWNER_MATCH.
    ///   So the override is real; only its body happens to equal the superclass's.
    override open func tapGestureAction(_: UITapGestureRecognizer) {
        isMaskShow.toggle()
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.IOSVideoPlayerView.play():0x101b108b8 result=103-instr]
    /// The exact mirror of `pause()` below, and read the same way. Differences worth stating:
    ///
    /// · The literal is **`"pause.fill"`**, not `"play.fill"`: x22 is built by `mov`+3×`movk` to
    ///   the bytes `pause.fi`, with x1 carrying `ll` under count byte **0xEA** (= 0xE0|10).
    ///   It is built ONCE and bridged twice, once per button.
    /// · `super.play()` is settled beyond argument here. `PlayerView.play()` has THREE statements,
    ///   and the binary inlines all three in order: `becomeFirstResponder()` (0x101b108dc,
    ///   ⚑[tool=decode_objc_selector ref=0x10440a828 result='becomeFirstResponder']), the
    ///   `playerLayer?` dispatch through metadata word +0x78, and
    ///   `toolBar.playButton.isSelected = true` (`setSelected:` with `w2 = 1` at 0x101b10940).
    ///   A re-spelled body would have to reproduce the superclass's other two statements by
    ///   coincidence.
    /// · The pairing is the same and is READ, not assumed: global 0x1044f0e98 =
    ///   `playPauseButton` takes 0x1044f0f88 = `playButtonConfig`, and 0x1044f0e68 =
    ///   `toolBarPlayButton` takes 0x1044f0f90 = `toolBarPlayButtonConfig`.
    ///   ⚑ s107 named the two config globals by their VALUE — each holds the field's byte offset,
    ///     and this class's metadata is static, so the offset resolves in the field-offset vector
    ///     directly. That independently reproduced the store-run derivation recorded under
    ///     `pause()`.
    override open func play() {
        super.play()
        playPauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: playButtonConfig), for: .normal)
        toolBarPlayButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: toolBarPlayButtonConfig), for: .normal)
    }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.IOSVideoPlayerView.pause():0x101b10a54 result=91-instr]
    /// Sets the "play.fill" glyph on BOTH play buttons after pausing. Every element is read:
    ///
    /// · `super.pause()` — the body opens with a virtual load of metadata word `+0x78`, which the
    ///   class metadata at 0x1044234e8 resolves to `VideoPlayerView.playerLayer.getter`, then an
    ///   `x0 == nil` skip and a virtual call at `+0x2c0`. With `KSPlayerLayer`'s `VTableOffset = 27
    ///   words`, `+0x2c0` is slot 61 = `KSPlayerLayer.pause()` — i.e. `playerLayer?.pause()`, which
    ///   is verbatim `PlayerView.pause()` inlined.
    ///   ⚑ `super.pause()` and a re-spelled `playerLayer?.pause()` compile to IDENTICAL code, so the
    ///     body alone cannot separate them. The SIBLING settles it: `IOSVideoPlayerView.play()`
    ///     (0x101b108b8) inlines BOTH of `PlayerView.play()`'s statements — the `playerLayer?.play()`
    ///     dispatch AND `toolBar.playButton.isSelected = true` (`setSelected:` with `w2=1` at
    ///     0x101b10940). A re-spelling would not carry the superclass's second statement, so these
    ///     overrides call `super`. That is a reading, not a preference.
    ///   ⚑[tool=export_trie_oracle ref=0x101b2b75c result=VideoPlayerView.playerLayer.getter]
    ///   ⚑[tool=vtable_walk ref=KSPlayerLayer:slot61 result=KSPlayer.KSPlayerLayer.pause()]
    ///
    /// · `"play.fill"` — one small string, built ONCE into x22 and reused by both calls:
    ///   `mov`+3×`movk` give the bytes `play.fil`, with x1 carrying the 9th byte `l` under count
    ///   byte 0xE9 (= 0xE0|9). Bridged via `String._bridgeToObjectiveC`, then sent to classref
    ///   0x104410600 = `UIImage` as `systemImageNamed:withConfiguration:`.
    ///   ⚑[tool=decode_objc_selector ref=0x10440e530 result='systemImageNamed:withConfiguration:']
    ///   ⚑[tool=decode_objc_selector ref=0x10440d540 result='setImage:forState:']
    ///   `forState:` is passed `x3 = 0` = `.normal`.
    ///
    /// · The two buttons are `vpWvd`-named: global 0x1044f0e98 = `playPauseButton`, 0x1044f0e68 =
    ///   `toolBarPlayButton`.
    ///
    /// ⚑ The two CONFIG globals (0x1044f0f88, 0x1044f0f90) have NO `vpWvd` symbol — the class
    ///   exports exactly 18 of them and none is a config — so neither the symbolic route nor
    ///   offset arithmetic (these globals are not index-ordered) can name them. They are named from
    ///   the initializer at 0x101b131d4, which stores three configs in one run:
    ///     0xf98 ← pointSize 32 · 0xf88 ← pointSize 32 · 0xf90 ← pointSize 15 (all weight `w2 = 7`),
    ///   immediately followed by `str xzr` to 0xf58. Field records 49/50/51/52 are
    ///   `jumpButtonConfig`, `playButtonConfig`, `toolBarPlayButtonConfig`,
    ///   `topStatusLeadingConstraint` — so the run is four consecutive fields in record order, and
    ///   TWO of them are pinned independently of that order: 0xf90 by the 15.0 constant (only
    ///   `toolBarPlayButtonConfig`'s `vpfi` at 0x10199b3fc uses 15.0) and 0xf58 by `xzr` (only the
    ///   index-52 Optional can be nil). Those anchors fix the sequence, giving **0xf88 =
    ///   `playButtonConfig`**.
    ///   ⚑ Corroborated a third time by ICF: `playButtonConfig`'s `vpfi` (0x10199ef50) is a bare
    ///     `b` to `jumpButtonConfig`'s body (0x10199b3cc). Two initializers fold only when
    ///     textually identical — and lines 141-142 declare both as
    ///     `(pointSize: 32, weight: .bold)`, which is also why 0xf98 and 0xf88 both receive 32.
    override open func pause() {
        super.pause()
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playButtonConfig), for: .normal)
        toolBarPlayButton.setImage(UIImage(systemName: "play.fill", withConfiguration: toolBarPlayButtonConfig), for: .normal)
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

    // READ IN FULL from 0x101b08f3c-0x101b09494 (1368 B, 342 instr, vtable slot 146). Every one of
    // the 23 `setConstant:` sends, every arm condition and every `setHidden:` receiver is resolved.
    //
    // EIGHT LAYOUT CONSTRAINTS ARE DRIVEN THAT THE SOURCE NEVER MENTIONED. The field names are NOT
    // inferred from the access sites: each `0x1044f0fXX` global was read for the offset it holds and
    // that offset looked up in `field_offset_vector IOSVideoPlayerView` —
    //   0x1044f0f30->0x2d8 topLeftBackgroundLeading · 0x1044f0f38->0x2e0 topRightBackgroundTrailing
    //   0x1044f0f40->0x2e8 leftBackgroundViewLeading · 0x1044f0f48->0x2f0 bottomBackgroundLeading
    //   0x1044f0f50->0x2f8 bottomBackgroundTrailing  · 0x1044f0f58->0x2c8 topStatusLeading
    //   0x1044f0f60->0x2d0 topStatusTrailing         · 0x1044f0f68->0x300 bottomBackgroundHeight
    // Two constants are raw doubles rather than `fmov` immediates and were decoded, not read:
    // `mov x8,#0x800000000000 / movk x8,#0x4040,lsl #48` = 33.0 and `mov x8,#0x4059...` = 100.0.
    // ⚑[tool=field_offset_vector ref=IOSVideoPlayerView.updateUI:0x101b08f3c result=8-constraints-23-sends]
    //
    // THE ARM SPLIT is `UIDevice.current.userInterfaceIdiom` — selectors decode as 'currentDevice'
    // (0x1034604c0) and 'userInterfaceIdiom' (0x10346e920) off the __objc_classrefs UIDevice entry
    // at 0x104410510. `.phone` is raw 0, so `cbz x22` @0x101b090dc sends phone down the non-A path.
    // The binary has THREE constraint blocks and the two non-portrait ones are identical, so this
    // reduces to: portrait-on-phone gets 20/30, everything else 15/25, height 100 throughout.
    // ⚑[tool=decode_objc_selector ref=UIDevice.userInterfaceIdiom:0x10346e920 result=arm-split]
    //
    // ⚠️ THE HEIGHT CONSTRAINT IS FORCE-UNWRAPPED ON THE PORTRAIT PATH ONLY. Blocks A and C reach
    // it by `cbz x0, <skip>` (optional); the portrait path reaches the SHARED send at 0x101b093e8
    // by `cbnz x0, 0x101b093e0` with a `brk #0x1` fallthrough — a nil constraint TRAPS there. The
    // `!` below is that trap, not a stylistic choice.
    //
    // THE SUBTITLE TEST WAS WRONG ON ITS PATH, and the correction is read, not guessed. The binary
    // goes `playerLayer` (PlayerView field @0x8, via global 0x1044e74e8) -> `subtitleModel`
    // (KSPlayerLayer, global 0x104c63500, vpWvd-named) -> a keypath pair 0x10356fd18/0x10356fd40
    // driven through `swift_getKeyPath` and `Combine.Published._enclosingInstance(_:wrapped:storage:)`,
    // then `ldr x22,[x0,#0x10] / cmp x22,#0 / cset w2,eq`. There is no `srtControl` anywhere in the
    // path — and PlayerView's reflection records carry no such field at all.
    // The property IS `subtitleInfos`: a keypath PATTERN is emitted per USE SITE, so its address
    // proves nothing, but resolving the relative pointers at pattern+0x08/+0x0c gives root
    // 0x103c2e927 and value 0x103c2e92d for BOTH this pair and the pair KSSubtitle.swift already
    // records for `subtitleInfos`, while `parts` resolves to a different value type. The shared
    // value descriptor mangles `Say` + symbolic ref + `_pG` = `Array<any Protocol>`.
    // ⚑[tool=export_trie_oracle ref=KSPlayerLayer.subtitleModel:0x104c63500 result=vpWvd-named]
    //
    // REMOVED, because no offset global in the extent resolves to any of them: the whole
    // `landscapeButton` / `lockButton` / `maskImageView.image` block. Those three fields exist
    // (maskImageView 0x168, landscapeButton 0x170, VideoPlayerView.lockButton 0xe0) and the body
    // never loads one. The leading unconditional `srtButton.isHidden` also goes — the binary sets
    // srtButton exactly once, inside the phone arm.
    open func updateUI(isLandscape: Bool) {
        if isLandscape {
            topMaskView.isHidden = KSOptions.topBarShowInCase == .none
        } else {
            topMaskView.isHidden = KSOptions.topBarShowInCase != .always
        }
        toolBar.playbackRateButton.isHidden = false
        if UIDevice.current.userInterfaceIdiom == .phone {
            if isLandscape {
                if let playerLayer {
                    toolBar.srtButton.isHidden = playerLayer.subtitleModel.subtitleInfos.isEmpty
                } else {
                    toolBar.srtButton.isHidden = true
                }
                topLeftBackgroundLeadingConstraint?.constant = 15
                topRightBackgroundTrailingConstraint?.constant = -15
                leftBackgroundViewLeadingConstraint?.constant = 33
                bottomBackgroundLeadingConstraint?.constant = 15
                bottomBackgroundTrailingConstraint?.constant = -15
                topStatusLeadingConstraint?.constant = 25
                topStatusTrailingConstraint?.constant = -25
                bottomBackgroundHeightConstraint?.constant = 100
            } else {
                toolBar.srtButton.isHidden = true
                topLeftBackgroundLeadingConstraint?.constant = 20
                topRightBackgroundTrailingConstraint?.constant = -20
                leftBackgroundViewLeadingConstraint?.constant = 33
                bottomBackgroundLeadingConstraint?.constant = 20
                bottomBackgroundTrailingConstraint?.constant = -20
                topStatusLeadingConstraint?.constant = 30
                topStatusTrailingConstraint?.constant = -30
                bottomBackgroundHeightConstraint!.constant = 100
            }
            toolBar.playbackRateButton.isHidden = !isLandscape
        } else {
            topLeftBackgroundLeadingConstraint?.constant = 15
            topRightBackgroundTrailingConstraint?.constant = -15
            leftBackgroundViewLeadingConstraint?.constant = 33
            bottomBackgroundLeadingConstraint?.constant = 15
            bottomBackgroundTrailingConstraint?.constant = -15
            topStatusLeadingConstraint?.constant = 25
            topStatusTrailingConstraint?.constant = -25
            bottomBackgroundHeightConstraint?.constant = 100
        }
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
        Task { @MainActor in
            let image = await self.playerLayer?.player.thumbnailImageAtCurrentTime()
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

    // showPromptMessage @0x101b0cfb8 (152 instr) and hidePrompt @0x101b0d70c (80 instr).
    // Both live in an EXTENSION, and that is read rather than chosen: neither carries a `…FTq`
    // method descriptor, and a method with no method descriptor has no vtable slot.
    //
    // The whole of showPromptMessage is one `DispatchQueue.main.async`. Its default arguments are
    // visible and are NOT source text: `DispatchQoS.unspecified` and an empty
    // `DispatchWorkItemFlags` built through `SetAlgebra.init(_:)` over `__swiftEmptyArrayStorage`
    // are materialised at the call site of `async(group:qos:flags:execute:)`, and the
    // `_Block_copy`/`_Block_release` pair is just the `@convention(block)` bridge for `execute:`.
    // `[weak self]` is `swift_unknownObjectWeakInit` into a 24-byte box; the reload plus `cbz` in
    // the closure is the `guard let self`.
    //
    // `promptLabel` is not positional: `name_global_by_value(IOSVideoPlayerView, 0x1044f1000)`
    // names the offset global, and the field record `So7UILabelC` says non-optional `UILabel` —
    // which is why nothing here optional-chains. Every number is an inline immediate:
    // 0x4049000000000000 = 50, 0x4042000000000000 = 36, [0x10347fea8] = 0.8, 0.3 twice,
    // alpha 0 then 1, and `fmov d0,#5.0` for the delay.
    //
    // ⚑ The `.identity` assignments are RESETS with no matching non-identity write anywhere in
    //   either method — showPromptMessage's animation and hidePrompt's completion both stamp the
    //   same identity matrix `(1,0),(0,1),(0,0)`. Transcribed as read; no scale was invented to
    //   explain them.
    // ⚑[tool=objc_trampoline_oracle ref=IOSVideoPlayerView.hidePrompt:0x101b0d9c8 result=selector-line-1289]
    // ⚑[tool=recover_field_offsets ref=IOSVideoPlayerView.promptLabel:0x1044f1000 result=promptLabel]
    func showPromptMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            promptLabel.removeFromSuperview()
            promptLabel.text = message
            addSubview(promptLabel)
            promptLabel.translatesAutoresizingMaskIntoConstraints = false
            bringSubviewToFront(promptLabel)
            NSLayoutConstraint.activate([
                promptLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 50),
                promptLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                promptLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
                promptLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            ])
            promptLabel.alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.promptLabel.transform = .identity
                self.promptLabel.alpha = 1
            }
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hidePrompt), object: nil)
            perform(#selector(hidePrompt), with: nil, afterDelay: 5)
        }
    }

    // hidePrompt is reached only through `performSelector:`, so its Swift symbol is unexported and
    // `pin_sweep` cannot see it — `…C10hidePromptyyF` is NOT IN TRIE. The ObjC method list still
    // carries it, which is how it was found. Its two blocks are separate bodies: the animations
    // block @0x101b0d84c (line 1290) sets alpha 0, and the completion block @0x101b0d8fc
    // (line 1292) stamps the identity transform. The completion takes the `Bool` UIKit passes.
    @objc private func hidePrompt() {
        UIView.animate(withDuration: 0.3) {
            self.promptLabel.alpha = 0
        } completion: { _ in
            self.promptLabel.transform = .identity
        }
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
    internal nonisolated(unsafe) static var supportedInterfaceOrientations = UIInterfaceOrientationMask.portrait
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
