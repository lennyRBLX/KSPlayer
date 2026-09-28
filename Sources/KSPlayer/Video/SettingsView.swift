//
//  SettingsView.swift
//  KSPlayer
//
//  Reconstructed from Forward-TF: KSPlayer.SettingsView (UIView subclass, 25 stored fields,
//  210 vtable slots). #fileID in the binary is "KSPlayer/SettingsView.swift".
//
#if canImport(UIKit) && canImport(CallKit)
import SwiftUI
import UIKit

class SettingsView: UIView {
    // Field vector order (0x1044245a0): four associated-object keys first.
    var switchValueChangedKey: UInt8 = 0
    var textFieldValueChangedKey: UInt8 = 0
    var sliderValueChangedKey: UInt8 = 0
    var buttonActionKey: UInt8 = 0

    let videoTabButton = UIButton(type: .system)
    let audioTabButton = UIButton(type: .system)
    let subtitleTabButton = UIButton(type: .system)
    let closeButton = UIButton(type: .system)

    let contentContainer = UIView()
    let videoContentView = UIView()
    let audioContentView = UIView()
    let subtitleContentView = UIView()

    var currentTab: Tab = .video
    var onDismiss: (() -> Void)?
    weak var playerView: IOSVideoPlayerView?

    var videoTrackButton: UIButton?
    var audioTrackButton: UIButton?

    var subtitleDelayLabel = UILabel()
    var subtitleSizeLabel = UILabel()
    var strokeWidthLabel = UILabel()
    var horizontalMarginLabel = UILabel()
    var verticalMarginLabel = UILabel()
    var leftMarginLabel = UILabel()
    var rightMarginLabel = UILabel()
    var threadCountLabel = UILabel()

    enum Tab: CaseIterable {
        case video
        case audio
        case subtitle

        var title: String {
            switch self {
            case .video:
                return "Video"
            case .audio:
                return "Audio"
            case .subtitle:
                return "Subtitle"
            }
        }
    }

    // 31 get/set computed properties (vtable property entries 17...47). Only the setters of
    // brightness/contrast/saturation (entries 32/33/34 -> slots 97/100/103) survive dead-method
    // elimination; every other accessor slot is _swift_deletedMethodError.
    var hardwareDecode: Bool {
        get { KSOptions.hardwareDecode }
        set { KSOptions.hardwareDecode = newValue }
    }

    var asynchronousDecompression: Bool {
        get { KSOptions.asynchronousDecompression }
        set { KSOptions.asynchronousDecompression = newValue }
    }

    var isAutoPlay: Bool {
        get { KSOptions.isAutoPlay }
        set { KSOptions.isAutoPlay = newValue }
    }

    var isAccurateSeek: Bool {
        get { KSOptions.isAccurateSeek }
        set { KSOptions.isAccurateSeek = newValue }
    }

    var isSeekedAutoPlay: Bool {
        get { KSOptions.isSeekedAutoPlay }
        set { KSOptions.isSeekedAutoPlay = newValue }
    }

    var enableHDRSubtitle: Bool {
        get { KSOptions.enableHDRSubtitle }
        set { KSOptions.enableHDRSubtitle = newValue }
    }

    var isResizeImageSubtitle: Bool {
        get { KSOptions.isResizeImageSubtitle }
        set { KSOptions.isResizeImageSubtitle = newValue }
    }

    var isASSUseImageRender: Bool {
        get { KSOptions.isASSUseImageRender }
        set { KSOptions.isASSUseImageRender = newValue }
    }

    var isSRTUseImageRender: Bool {
        get { KSOptions.isSRTUseImageRender }
        set { KSOptions.isSRTUseImageRender = newValue }
    }

    var preferEffectSubtitle: Bool {
        get { KSOptions.preferEffectSubtitle }
        set { KSOptions.preferEffectSubtitle = newValue }
    }

    var stripSubtitleStyle: Bool {
        get { KSOptions.stripSubtitleStyle }
        set { KSOptions.stripSubtitleStyle = newValue }
    }

    var subtitleImageScale: Double {
        get { KSOptions.subtitleImageScale }
        set { KSOptions.subtitleImageScale = newValue }
    }

    var textBold: Bool {
        get { KSOptions.textBold }
        set { KSOptions.textBold = newValue }
    }

    var textItalic: Bool {
        get { KSOptions.textItalic }
        set { KSOptions.textItalic = newValue }
    }

    var videoSoftDecodeThreadCount: Int {
        get { KSOptions.videoSoftDecodeThreadCount }
        set { KSOptions.videoSoftDecodeThreadCount = newValue }
    }

    var brightness: Float {
        get { playerView?.playerLayer?.options.brightness ?? 1.0 }
        set { playerView?.playerLayer?.options.brightness = newValue }
    }

    var contrast: Float {
        get { playerView?.playerLayer?.options.contrast ?? 1.0 }
        set { playerView?.playerLayer?.options.contrast = newValue }
    }

    var saturation: Float {
        get { playerView?.playerLayer?.options.saturation ?? 1.0 }
        set { playerView?.playerLayer?.options.saturation = newValue }
    }

    var subtitleDelay: Double {
        get { playerView?.playerLayer?.subtitleModel.subtitleDelay ?? 0 }
        set { playerView?.playerLayer?.subtitleModel.subtitleDelay = newValue }
    }

    var subtitleFontSize: Double {
        get { KSOptions.subtitleFontSize }
        set { KSOptions.subtitleFontSize = newValue }
    }

    var textStrokeWidth: CGFloat {
        get { KSOptions.textStrokeWidth }
        set { KSOptions.textStrokeWidth = newValue }
    }

    var textColor: UIColor {
        get { KSOptions.textColor }
        set { KSOptions.textColor = newValue }
    }

    var textBackgroundColor: UIColor {
        get { KSOptions.textBackgroundColor }
        set { KSOptions.textBackgroundColor = newValue }
    }

    var textStrokeColor: UIColor {
        get { KSOptions.textStrokeColor }
        set { KSOptions.textStrokeColor = newValue }
    }

    var textShadowColor: UIColor {
        get { KSOptions.textShadowColor }
        set { KSOptions.textShadowColor = newValue }
    }

    var verticalMargin: CGFloat {
        get { KSOptions.textPosition.verticalMargin }
        set { KSOptions.textPosition.verticalMargin = newValue }
    }

    var leftMargin: CGFloat {
        get { KSOptions.textPosition.leftMargin }
        set { KSOptions.textPosition.leftMargin = newValue }
    }

    var rightMargin: CGFloat {
        get { KSOptions.textPosition.rightMargin }
        set { KSOptions.textPosition.rightMargin = newValue }
    }

    var textPosition: TextPosition {
        get { KSOptions.textPosition }
        set { KSOptions.textPosition = newValue }
    }

    var currentHorizontalAlignValue: String {
        get {
            switch KSOptions.textPosition.horizontalAlign {
            case .leading:
                return "leading"
            case .center:
                return "center"
            case .trailing:
                return "trailing"
            default:
                return "center"
            }
        }
        set { setHorizontalAlign(newValue) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 12
        clipsToBounds = true
        setupTabBar()
        setupContentContainer()
        setupVideoContent()
        setupAudioContent()
        setupSubtitleContent()
        switchTab(to: .video)
    }

    func setupTabBar() {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        for (index, button) in [videoTabButton, audioTabButton, subtitleTabButton].enumerated() {
            let tab = Tab.allCases[index]
            button.setTitle(tab.title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            button.tag = index
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -20),
            stackView.heightAnchor.constraint(equalToConstant: 32),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    func setupContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .clear
        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
        ])
        for view in [videoContentView, audioContentView, subtitleContentView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.backgroundColor = .clear
            view.isHidden = true
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }
    }

    func setupVideoContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        videoContentView.addSubview(scrollView)
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: videoContentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: videoContentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: videoContentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: videoContentView.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        addSectionTitle(y: 0, title: "ContentMode", to: contentView)
        addFixedRow(y: 25, view: createAspectRatioButtons(), to: contentView)
        addSeparator(y: 75, to: contentView)
        addSectionTitle(y: 85, title: "VideoTrack", to: contentView)
        addRow(y: 110, view: createVideoTrackRow(), to: contentView)
        addSeparator(y: 160, to: contentView)
        addSectionTitle(y: 170, title: "Player Settings", to: contentView)
        addRow(y: 195, view: createSwitchRow(title: "Hardware Decode", isOn: KSOptions.hardwareDecode) { [weak self] isOn in
            self?.hardwareDecode = isOn
            if let playerView = self?.playerView {
                let resource = playerView.resource
                let definitionIndex = playerView.currentDefinition
                playerView.resetPlayer()
                if let resource {
                    playerView.set(resource: resource, definitionIndex: definitionIndex)
                }
            }
        }, to: contentView)
        addRow(y: 235, view: createSwitchRow(title: "Async Decompression", isOn: KSOptions.asynchronousDecompression) { [weak self] isOn in
            self?.asynchronousDecompression = isOn
        }, to: contentView)
        addRow(y: 275, view: createSwitchRow(title: "Auto Play", isOn: KSOptions.isAutoPlay) { [weak self] isOn in
            self?.isAutoPlay = isOn
        }, to: contentView)
        addRow(y: 315, view: createSwitchRow(title: "Accurate Seek", isOn: KSOptions.isAccurateSeek) { [weak self] isOn in
            self?.isAccurateSeek = isOn
        }, to: contentView)
        addRow(y: 355, view: createSwitchRow(title: "Auto Play After Seek", isOn: KSOptions.isSeekedAutoPlay) { [weak self] isOn in
            self?.isSeekedAutoPlay = isOn
        }, to: contentView)
        addRow(y: 395, view: createStepperRow(title: "Soft Decoder Threads", label: &threadCountLabel, value: "\(KSOptions.videoSoftDecodeThreadCount)", decreaseAction: #selector(decreaseThreadCount), increaseAction: #selector(increaseThreadCount)), to: contentView)
        addSeparator(y: 445, to: contentView)
        addSectionTitle(y: 455, title: "Color Adjust", to: contentView)
        addRow(y: 480, view: createResetSliderRow(value: playerView?.playerLayer?.options.brightness ?? 1.0, min: -1, max: 1, defaultValue: 1, title: "Brightness") { [weak self] value in
            self?.brightness = value
            self?.playerView?.playerLayer?.options.brightness = value
        }, to: contentView)
        addRow(y: 520, view: createResetSliderRow(value: playerView?.playerLayer?.options.contrast ?? 1.0, min: -1, max: 1, defaultValue: 1, title: "Contrast") { [weak self] value in
            self?.contrast = value
            self?.playerView?.playerLayer?.options.contrast = value
        }, to: contentView)
        addRow(y: 560, view: createResetSliderRow(value: playerView?.playerLayer?.options.saturation ?? 1.0, min: -1, max: 1, defaultValue: 1, title: "Saturation") { [weak self] value in
            self?.saturation = value
            self?.playerView?.playerLayer?.options.saturation = value
        }, to: contentView)
        contentView.heightAnchor.constraint(equalToConstant: 615).isActive = true
    }

    func setupAudioContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        audioContentView.addSubview(scrollView)
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: audioContentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: audioContentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: audioContentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: audioContentView.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        addSectionTitle(y: 0, title: "Audio Track", to: contentView)
        addRow(y: 25, view: createAudioTrackRow(), to: contentView)
        addSeparator(y: 75, to: contentView)
        contentView.heightAnchor.constraint(equalToConstant: 200).isActive = true
    }

    func setupSubtitleContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        subtitleContentView.addSubview(scrollView)
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: subtitleContentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: subtitleContentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: subtitleContentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: subtitleContentView.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        addRow(y: 0, view: createSwitchRow(title: "Enable HDR Subtitle", isOn: KSOptions.enableHDRSubtitle) { [weak self] isOn in
            self?.enableHDRSubtitle = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 40, view: createSwitchRow(title: "Resize Image Subtitle", isOn: KSOptions.isResizeImageSubtitle) { [weak self] isOn in
            self?.isResizeImageSubtitle = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 80, view: createSwitchRow(title: "ASS Use Image Render", isOn: KSOptions.isASSUseImageRender) { [weak self] isOn in
            self?.isASSUseImageRender = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 120, view: createSwitchRow(title: "SRT Use Image Render", isOn: KSOptions.isSRTUseImageRender) { [weak self] isOn in
            self?.isSRTUseImageRender = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 160, view: createSwitchRow(title: "Effect Subtitle Priority", isOn: KSOptions.preferEffectSubtitle) { [weak self] isOn in
            self?.preferEffectSubtitle = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 200, view: createSwitchRow(title: "Strip Subtitle Style", isOn: KSOptions.stripSubtitleStyle) { [weak self] isOn in
            self?.stripSubtitleStyle = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 240, view: createStepperRow(title: "Subtitle Delay", label: &subtitleDelayLabel, value: String(format: "%.1fs", playerView?.playerLayer?.subtitleModel.subtitleDelay ?? 0), decreaseAction: #selector(decreaseSubtitleDelay), increaseAction: #selector(increaseSubtitleDelay)), to: contentView)
        addSeparator(y: 280, to: contentView)
        addSectionTitle(y: 290, title: "Subtitle Font", to: contentView)
        addRow(y: 315, view: createStepperRow(title: "Font Size", label: &subtitleSizeLabel, value: "\(Int(KSOptions.subtitleFontSize))pt", decreaseAction: #selector(decreaseSubtitleSize), increaseAction: #selector(increaseSubtitleSize)), to: contentView)
        addRow(y: 355, view: createSliderRow(value: Float(KSOptions.subtitleImageScale), min: 0.1, max: 1.0, title: "Subtitle Image Scale") { [weak self] value in
            self?.subtitleImageScale = Double(value)
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 395, view: createStepperRow(title: "Text Stroke Width", label: &strokeWidthLabel, value: "\(Int(KSOptions.textStrokeWidth))px", decreaseAction: #selector(decreaseStrokeWidth), increaseAction: #selector(increaseStrokeWidth)), to: contentView)
        addRow(y: 435, view: createSwitchRow(title: "Text Bold", isOn: KSOptions.textBold) { [weak self] isOn in
            self?.textBold = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 475, view: createSwitchRow(title: "Text Italic", isOn: KSOptions.textItalic) { [weak self] isOn in
            self?.textItalic = isOn
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addSeparator(y: 525, to: contentView)
        addSectionTitle(y: 535, title: "Position", to: contentView)
        addRow(y: 560, view: createStepperRow(title: "Vertical Offset", label: &verticalMarginLabel, value: "\(Int(KSOptions.textPosition.verticalMargin))px", decreaseAction: #selector(decreaseVerticalMargin), increaseAction: #selector(increaseVerticalMargin)), to: contentView)
        addRow(y: 600, view: createStepperRow(title: "Left Margin", label: &leftMarginLabel, value: "\(Int(KSOptions.textPosition.leftMargin))px", decreaseAction: #selector(decreaseLeftMargin), increaseAction: #selector(increaseLeftMargin)), to: contentView)
        addRow(y: 640, view: createStepperRow(title: "Right Margin", label: &rightMarginLabel, value: "\(Int(KSOptions.textPosition.rightMargin))px", decreaseAction: #selector(decreaseRightMargin), increaseAction: #selector(increaseRightMargin)), to: contentView)
        addRow(y: 680, view: createHorizontalAlignRow(), to: contentView)
        addSeparator(y: 730, to: contentView)
        addSectionTitle(y: 740, title: "Color", to: contentView)
        addRow(y: 765, view: createColorRow(title: "Subtitle Color", currentColor: KSOptions.textColor) { [weak self] color in
            self?.textColor = color
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 815, view: createColorRow(title: "Subtitle Bg Color", currentColor: KSOptions.textBackgroundColor) { [weak self] color in
            self?.textBackgroundColor = color
            self?.refreshSubtitleStyle()
        }, to: contentView)
        addRow(y: 865, view: createColorRow(title: "Text Stroke Color", currentColor: KSOptions.textStrokeColor) { [weak self] color in
            self?.textStrokeColor = color
            self?.refreshSubtitleStyle()
        }, to: contentView)
        // Faithful to Forward: this closure is ICF-folded with the "Subtitle Color" one
        // (0x101b2a808 branches to 0x101b2a600, which this row passes directly), so the shadow
        // row writes textColor, not textShadowColor.
        addRow(y: 915, view: createColorRow(title: "Text Shadow Color", currentColor: KSOptions.textShadowColor) { [weak self] color in
            self?.textColor = color
            self?.refreshSubtitleStyle()
        }, to: contentView)
        contentView.heightAnchor.constraint(equalToConstant: 965).isActive = true
    }

    func createAspectRatioButtons() -> UIView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        let titles = ["Default", "Scale To Fill", "Scale Aspect Fill"]
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            if index == 0 {
                button.backgroundColor = .white
                button.setTitleColor(.black, for: .normal)
            } else {
                button.backgroundColor = .clear
                button.setTitleColor(.white, for: .normal)
            }
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.cgColor
            button.layer.cornerRadius = 6
            button.tag = index
            button.addTarget(self, action: #selector(aspectRatioButtonTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
        return stackView
    }

    func createVideoTrackRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setTitle("Video Track", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        videoTrackButton = button
        container.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateVideoTrackMenu(_ button: UIButton) {
        guard let playerView else {
            return
        }
        guard let playerLayer = playerView.playerLayer else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateVideoTrackMenu(button)
            }
            return
        }
        let player = playerLayer.player
        let tracks = player.tracks(mediaType: .video)
        let currentTrack = tracks.first { $0.isEnabled }
        var actions = [UIAction]()
        for (index, track) in tracks.enumerated() {
            let title = track.description.isEmpty ? "Video Track \(index + 1)" : track.description
            let action = UIAction(title: title, state: track.isEnabled ? .on : .off) { [weak self] _ in
                player.select(track: track)
                button.setTitle(title, for: .normal)
                self?.updateVideoTrackMenu(button)
            }
            actions.append(action)
        }
        if actions.isEmpty {
            actions.append(UIAction(title: "无可用视频轨道", attributes: .disabled) { _ in })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.updateVideoTrackMenu(button)
            }
        }
        button.menu = UIMenu(title: "Video Track", children: actions)
        button.showsMenuAsPrimaryAction = true
        if let currentTrack {
            button.setTitle(currentTrack.description.isEmpty ? "Video Track" : currentTrack.description, for: .normal)
        }
    }

    @objc func showVideoTrackAlert(_ sender: UIButton) {
        guard let player = playerView?.playerLayer?.player else {
            return
        }
        presentVideoTrackAlert(tracks: player.tracks(mediaType: .video), player: player, sender: sender)
    }

    func presentVideoTrackAlert(tracks: [MediaPlayerTrack], player: MediaPlayerProtocol, sender: UIButton) {
        let alert = UIAlertController(title: "Video Track", message: nil, preferredStyle: .actionSheet)
        if tracks.isEmpty {
            let action = UIAlertAction(title: "无可用视频轨道", style: .default)
            action.isEnabled = false
            alert.addAction(action)
        } else {
            for (index, track) in tracks.enumerated() {
                let trackName = track.description.isEmpty ? "Video Track \(index + 1)" : track.description
                let title = track.isEnabled ? "✓ " + trackName : trackName
                let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                    player.select(track: track)
                    sender.setTitle(trackName, for: .normal)
                    self?.updateVideoTrackMenu(sender)
                }
                alert.addAction(action)
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        var responder = playerView?.next
        while let current = responder {
            if let viewController = current as? UIViewController {
                viewController.present(alert, animated: true)
                return
            }
            responder = current.next
        }
    }

    @objc func showAudioTrackAlert(_ sender: UIButton) {
        guard let player = playerView?.playerLayer?.player else {
            return
        }
        presentAudioTrackAlert(tracks: player.tracks(mediaType: .audio), player: player, sender: sender)
    }

    func presentAudioTrackAlert(tracks: [MediaPlayerTrack], player: MediaPlayerProtocol, sender: UIButton) {
        let alert = UIAlertController(title: "Audio Track", message: nil, preferredStyle: .actionSheet)
        if tracks.isEmpty {
            let action = UIAlertAction(title: "无可用音频轨道", style: .default)
            action.isEnabled = false
            alert.addAction(action)
        } else {
            for (index, track) in tracks.enumerated() {
                let trackName = track.description.isEmpty ? "Audio Track \(index + 1)" : track.description
                let title = track.isEnabled ? "✓ " + trackName : trackName
                let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                    player.select(track: track)
                    sender.setTitle(trackName, for: .normal)
                    self?.updateAudioTrackMenu(sender)
                }
                alert.addAction(action)
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        var responder = playerView?.next
        while let current = responder {
            if let viewController = current as? UIViewController {
                viewController.present(alert, animated: true)
                return
            }
            responder = current.next
        }
    }

    func createAudioTrackRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setTitle("Audio Track", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        audioTrackButton = button
        container.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateAudioTrackMenu(_ button: UIButton) {
        guard let playerView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateAudioTrackMenu(button)
            }
            return
        }
        guard let playerLayer = playerView.playerLayer else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateAudioTrackMenu(button)
            }
            return
        }
        let player = playerLayer.player
        let tracks = player.tracks(mediaType: .audio)
        let currentTrack = tracks.first { $0.isEnabled }
        var actions = [UIAction]()
        for (index, track) in tracks.enumerated() {
            let title = track.description.isEmpty ? "Audio Track \(index + 1)" : track.description
            let action = UIAction(title: title, state: track.isEnabled ? .on : .off) { [weak self] _ in
                player.select(track: track)
                button.setTitle(title, for: .normal)
                self?.updateAudioTrackMenu(button)
            }
            actions.append(action)
        }
        if actions.isEmpty {
            actions.append(UIAction(title: "无可用音频轨道", attributes: .disabled) { _ in })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.updateAudioTrackMenu(button)
            }
        }
        button.menu = UIMenu(title: "Audio Track", children: actions)
        button.showsMenuAsPrimaryAction = true
        if let currentTrack {
            button.setTitle(currentTrack.description.isEmpty ? "Audio Track" : currentTrack.description, for: .normal)
        }
    }

    func createHorizontalAlignRow() -> UIView {
        let options = [("Leading", "leading"), ("Center", "center"), ("Trailing", "trailing")]
        let current = currentHorizontalAlignValue
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setTitle(options.first { $0.1 == current }?.0 ?? "Center", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        var actions = [UIAction]()
        for (title, value) in options {
            let action = UIAction(title: title, state: value == current ? .on : .off) { [weak self] _ in
                self?.setHorizontalAlign(value)
                button.setTitle(title, for: .normal)
                self?.updateHorizontalAlignMenu(button)
                self?.refreshSubtitleStyle()
            }
            actions.append(action)
        }
        button.menu = UIMenu(title: "Horizontal Align", children: actions)
        button.showsMenuAsPrimaryAction = true
        container.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateHorizontalAlignMenu(_ button: UIButton) {
        let options = [("Leading", "leading"), ("Center", "center"), ("Trailing", "trailing")]
        let current = currentHorizontalAlignValue
        var actions = [UIAction]()
        for (title, value) in options {
            let action = UIAction(title: title, state: value == current ? .on : .off) { [weak self] _ in
                self?.setHorizontalAlign(value)
                button.setTitle(title, for: .normal)
                self?.updateHorizontalAlignMenu(button)
                self?.refreshSubtitleStyle()
            }
            actions.append(action)
        }
        // Forward materialises this title from the "center" literal's storage: it really is "Center".
        button.menu = UIMenu(title: "Center", children: actions)
    }

    @objc func showHorizontalAlignAlert(_ sender: UIButton) {
        let options = [("Leading", "leading"), ("Center", "center"), ("Trailing", "trailing")]
        let current = currentHorizontalAlignValue
        let alert = UIAlertController(title: "Horizontal Align", message: nil, preferredStyle: .actionSheet)
        for (title, value) in options {
            let actionTitle = value == current ? "✓ " + title : title
            let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
                self?.setHorizontalAlign(value)
                sender.setTitle(title, for: .normal)
                self?.refreshSubtitleStyle()
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        var responder = playerView?.next
        while let current = responder {
            if let viewController = current as? UIViewController {
                viewController.present(alert, animated: true)
                return
            }
            responder = current.next
        }
    }

    func setHorizontalAlign(_ value: String) {
        let alignment: HorizontalAlignment
        switch value {
        case "leading":
            alignment = .leading
        case "center":
            alignment = .center
        case "trailing":
            alignment = .trailing
        default:
            alignment = .center
        }
        KSOptions.textPosition.horizontalAlign = alignment
    }

    @objc func switchValueChanged(_ sender: UISwitch) {
        if let action = objc_getAssociatedObject(sender, &switchValueChangedKey) as? (Bool) -> Void {
            action(sender.isOn)
        }
    }

    @objc func textFieldValueChanged(_ sender: UITextField) {
        if let action = objc_getAssociatedObject(sender, &textFieldValueChangedKey) as? (String) -> Void {
            action(sender.text ?? "")
        }
    }

    @objc func sliderValueChanged(_ sender: UISlider) {
        if let action = objc_getAssociatedObject(sender, &sliderValueChangedKey) as? (Float) -> Void {
            action(sender.value)
        }
    }

    @objc func buttonActionTriggered(_ sender: UIButton) {
        if let action = objc_getAssociatedObject(sender, &buttonActionKey) as? () -> Void {
            action()
        }
    }

    @objc func decreaseSubtitleDelay() {
        subtitleDelay = max(subtitleDelay - 0.5, 0)
        subtitleDelayLabel.text = String(format: "%.1fs", subtitleDelay)
    }

    @objc func increaseSubtitleDelay() {
        subtitleDelay = min(subtitleDelay + 0.5, 100)
        subtitleDelayLabel.text = String(format: "%.1fs", subtitleDelay)
    }

    @objc func decreaseSubtitleSize() {
        KSOptions.subtitleFontSize = Double(max(Int(KSOptions.subtitleFontSize) - 1, 1))
        subtitleSizeLabel.text = "\(Int(KSOptions.subtitleFontSize))pt"
        refreshSubtitleStyle()
    }

    @objc func increaseSubtitleSize() {
        KSOptions.subtitleFontSize = Double(min(Int(KSOptions.subtitleFontSize) + 1, 50))
        subtitleSizeLabel.text = "\(Int(KSOptions.subtitleFontSize))pt"
        refreshSubtitleStyle()
    }

    @objc func decreaseStrokeWidth() {
        KSOptions.textStrokeWidth = CGFloat(max(Int(KSOptions.textStrokeWidth) - 1, 0))
        strokeWidthLabel.text = "\(Int(KSOptions.textStrokeWidth))px"
        refreshSubtitleStyle()
    }

    @objc func increaseStrokeWidth() {
        KSOptions.textStrokeWidth = CGFloat(min(Int(KSOptions.textStrokeWidth) + 1, 50))
        strokeWidthLabel.text = "\(Int(KSOptions.textStrokeWidth))px"
        refreshSubtitleStyle()
    }

    @objc func decreaseVerticalMargin() {
        KSOptions.textPosition.verticalMargin = CGFloat(max(Int(KSOptions.textPosition.verticalMargin) - 10, 0))
        verticalMarginLabel.text = "\(Int(KSOptions.textPosition.verticalMargin))px"
        refreshSubtitleStyle()
    }

    @objc func increaseVerticalMargin() {
        KSOptions.textPosition.verticalMargin = CGFloat(min(Int(KSOptions.textPosition.verticalMargin) + 10, 1000))
        verticalMarginLabel.text = "\(Int(KSOptions.textPosition.verticalMargin))px"
        refreshSubtitleStyle()
    }

    @objc func decreaseLeftMargin() {
        KSOptions.textPosition.leftMargin = CGFloat(max(Int(KSOptions.textPosition.leftMargin) - 10, 0))
        leftMarginLabel.text = "\(Int(KSOptions.textPosition.leftMargin))px"
        refreshSubtitleStyle()
    }

    @objc func increaseLeftMargin() {
        KSOptions.textPosition.leftMargin = CGFloat(min(Int(KSOptions.textPosition.leftMargin) + 10, 1000))
        leftMarginLabel.text = "\(Int(KSOptions.textPosition.leftMargin))px"
        refreshSubtitleStyle()
    }

    @objc func decreaseRightMargin() {
        KSOptions.textPosition.rightMargin = CGFloat(max(Int(KSOptions.textPosition.rightMargin) - 10, 0))
        rightMarginLabel.text = "\(Int(KSOptions.textPosition.rightMargin))px"
        refreshSubtitleStyle()
    }

    @objc func increaseRightMargin() {
        KSOptions.textPosition.rightMargin = CGFloat(min(Int(KSOptions.textPosition.rightMargin) + 10, 1000))
        rightMarginLabel.text = "\(Int(KSOptions.textPosition.rightMargin))px"
        refreshSubtitleStyle()
    }

    @objc func decreaseThreadCount() {
        KSOptions.videoSoftDecodeThreadCount = max(KSOptions.videoSoftDecodeThreadCount - 1, 1)
        threadCountLabel.text = "\(KSOptions.videoSoftDecodeThreadCount)"
    }

    @objc func increaseThreadCount() {
        KSOptions.videoSoftDecodeThreadCount = min(KSOptions.videoSoftDecodeThreadCount + 1, 16)
        threadCountLabel.text = "\(KSOptions.videoSoftDecodeThreadCount)"
    }

    func applyVideoAdjustments() {
        guard let playerView else {
            return
        }
        playerView.playerLayer?.options.brightness = brightness
        playerView.playerLayer?.options.contrast = contrast
        playerView.playerLayer?.options.saturation = saturation
    }

    func createStepperRow(title: String, label: inout UILabel, value: String, decreaseAction: Selector, increaseAction: Selector) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        let decreaseButton = createStepperButton(title: "−", action: decreaseAction)
        let increaseButton = createStepperButton(title: "+", action: increaseAction)
        label.text = value
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.widthAnchor.constraint(equalToConstant: 60).isActive = true
        label.backgroundColor = .clear
        label.layer.cornerRadius = 0
        let controlStack = UIStackView(arrangedSubviews: [decreaseButton, label, increaseButton])
        controlStack.spacing = 8
        controlStack.alignment = .center
        let rowStack = UIStackView(arrangedSubviews: [titleLabel, controlStack])
        rowStack.axis = .horizontal
        rowStack.spacing = 40
        rowStack.distribution = .equalSpacing
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.heightAnchor.constraint(equalToConstant: 40),
        ])
        return rowStack
    }

    func createStepperButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        button.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.3)
        button.layer.cornerRadius = 6
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func refreshSubtitleStyle() {
        switch KSOptions.textPosition.horizontalAlign {
        case .leading:
            KSOptions.textPosition.horizontalAlign = .leading
        case .center:
            KSOptions.textPosition.horizontalAlign = .center
        case .trailing:
            KSOptions.textPosition.horizontalAlign = .trailing
        default:
            KSOptions.textPosition.horizontalAlign = .leading
        }
        switch KSOptions.textPosition.verticalAlign {
        case .top:
            KSOptions.textPosition.verticalAlign = .top
        case .center:
            KSOptions.textPosition.verticalAlign = .center
        case .bottom:
            KSOptions.textPosition.verticalAlign = .bottom
        default:
            KSOptions.textPosition.verticalAlign = .bottom
        }
        let textColor = KSOptions.textColor
        KSOptions.textColor = textColor
        let textBackgroundColor = KSOptions.textBackgroundColor
        KSOptions.textBackgroundColor = textBackgroundColor
        let textShadowColor = KSOptions.textShadowColor
        KSOptions.textShadowColor = textShadowColor
        let textStrokeColor = KSOptions.textStrokeColor
        KSOptions.textStrokeColor = textStrokeColor
    }

    private func addSectionTitle(y: CGFloat, title: String, to container: UIView) {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        ])
    }

    private func addFixedRow(y: CGFloat, view: UIView, to container: UIView) {
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func addSeparator(y: CGFloat, to container: UIView) {
        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func addRow(y: CGFloat, view: UIView, to container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func createSwitchRow(title: String, isOn: Bool, action: ((Bool) -> Void)?) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = .systemGreen
        toggle.translatesAutoresizingMaskIntoConstraints = false
        if let action {
            toggle.addAction(UIAction { _ in
                action(toggle.isOn)
            }, for: .valueChanged)
        }
        row.addSubview(label)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 40),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func createSliderRow(value: Float, min: Float, max: Float, title: String, onChange: ((Float) -> Void)?) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.1f", value)
        valueLabel.textColor = .white
        valueLabel.font = UIFont.systemFont(ofSize: 12)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        if let onChange {
            slider.addAction(UIAction { _ in
                valueLabel.text = String(format: "%.1f", slider.value)
                onChange(slider.value)
            }, for: .valueChanged)
        }
        row.addSubview(titleLabel)
        row.addSubview(slider)
        row.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 80),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            slider.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 50),
        ])
        return row
    }

    private func createResetSliderRow(value: Float, min: Float, max: Float, defaultValue: Float, title: String, onChange: ((Float) -> Void)?) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = UILabel()
        valueLabel.text = "\(Int(value * 100))"
        valueLabel.textColor = .white
        valueLabel.font = UIFont.systemFont(ofSize: 12)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("Reset", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        resetButton.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.3)
        resetButton.layer.cornerRadius = 6
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addAction(UIAction { _ in
            slider.value = defaultValue
            valueLabel.text = "\(Int(defaultValue * 100))"
            onChange?(defaultValue)
        }, for: .touchUpInside)
        if let onChange {
            slider.addAction(UIAction { _ in
                valueLabel.text = "\(Int(slider.value * 100))"
                onChange(slider.value)
            }, for: .valueChanged)
        }
        row.addSubview(titleLabel)
        row.addSubview(slider)
        row.addSubview(valueLabel)
        row.addSubview(resetButton)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 60),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            slider.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 30),
            resetButton.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 10),
            resetButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            resetButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            resetButton.widthAnchor.constraint(equalToConstant: 50),
            resetButton.heightAnchor.constraint(equalToConstant: 28),
        ])
        return row
    }

    private func createColorRow(title: String, currentColor: UIColor, action: @escaping (UIColor) -> Void) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        let previewButton = UIButton(type: .custom)
        previewButton.backgroundColor = currentColor
        previewButton.layer.cornerRadius = 12
        previewButton.layer.borderWidth = 2
        previewButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        let colors: [UIColor] = [.white, .black, .red, .green, .blue, .yellow, .orange, .purple, .clear]
        for (index, color) in colors.enumerated() {
            let button = UIButton(type: .custom)
            button.backgroundColor = color
            button.layer.cornerRadius = 8
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            if color == .clear {
                button.backgroundColor = .clear
                button.layer.borderWidth = 2
                button.layer.borderColor = UIColor.white.cgColor
                let slash = UIView()
                slash.backgroundColor = .red
                slash.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(slash)
                NSLayoutConstraint.activate([
                    slash.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    slash.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    slash.widthAnchor.constraint(equalToConstant: 20),
                    slash.heightAnchor.constraint(equalToConstant: 2),
                ])
                slash.transform = CGAffineTransform(rotationAngle: .pi / 4)
            }
            button.addAction(UIAction { _ in
                previewButton.backgroundColor = color
                action(color)
            }, for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 16),
                button.heightAnchor.constraint(equalToConstant: 16),
            ])
            stackView.addArrangedSubview(button)
        }
        row.addSubview(label)
        row.addSubview(previewButton)
        row.addSubview(stackView)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 40),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 80),
            previewButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            previewButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            previewButton.widthAnchor.constraint(equalToConstant: 24),
            previewButton.heightAnchor.constraint(equalToConstant: 24),
            stackView.leadingAnchor.constraint(equalTo: previewButton.trailingAnchor, constant: 15),
            stackView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -10),
        ])
        return row
    }

    @objc func tabButtonTapped(_ sender: UIButton) {
        let tab = Tab.allCases[sender.tag]
        switchTab(to: tab)
    }

    @objc func aspectRatioButtonTapped(_ sender: UIButton) {
        if let stackView = sender.superview as? UIStackView {
            for view in stackView.arrangedSubviews {
                if let button = view as? UIButton {
                    let isSelected = button.tag == sender.tag
                    button.backgroundColor = isSelected ? .white : .clear
                    button.setTitleColor(isSelected ? .black : .white, for: .normal)
                }
            }
        }
        switch sender.tag {
        case 1:
            playerView?.playerLayer?.player.contentMode = .scaleToFill
        case 2:
            playerView?.playerLayer?.player.contentMode = .scaleAspectFill
        default:
            playerView?.playerLayer?.player.contentMode = .scaleAspectFit
        }
    }

    @objc func closeButtonTapped() {
        onDismiss?()
    }

    func switchTab(to tab: Tab) {
        currentTab = tab
        let buttons = [videoTabButton, audioTabButton, subtitleTabButton]
        for (index, button) in buttons.enumerated() {
            if Tab.allCases[index] == tab {
                button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
                button.layer.cornerRadius = 8
                button.layer.masksToBounds = true
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = .clear
                button.layer.cornerRadius = 0
                button.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
            }
        }
        let contentViews = [videoContentView, audioContentView, subtitleContentView]
        for (index, view) in contentViews.enumerated() {
            view.isHidden = Tab.allCases[index] != tab
        }
    }

    func show(in view: UIView) {
        view.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topAnchor.constraint(equalTo: view.topAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthAnchor.constraint(equalToConstant: 400),
        ])
        view.layoutIfNeeded()
        transform = CGAffineTransform(translationX: 420, y: 0)
        alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.transform = .identity
            self.alpha = 1
        })
        if let videoTrackButton {
            updateVideoTrackMenu(videoTrackButton)
        }
        if let audioTrackButton {
            updateAudioTrackMenu(audioTrackButton)
        }
        applyVideoAdjustments()
        refreshSubtitleStyle()
    }

    func dismiss() {
        let width: CGFloat = 400
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: width + 20, y: 0)
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}
#endif
