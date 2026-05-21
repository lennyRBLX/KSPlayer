//
//  SettingsView.swift
//  KSPlayer
//
//  Forward addition (RE): Tabbed settings panel for video, audio,
//  and subtitle configuration during playback.
//
//  Binary: _TtC8KSPlayer12SettingsView (27 functions)
//  RE source: Forward v1.3.15, entry @ 0x1014f21d4
//

#if canImport(UIKit)
import UIKit

public class SettingsView: UIView {
    // MARK: - Action Closures

    public var switchValueChanged: ((UISwitch) -> Void)?
    public var textFieldValueChanged: ((UITextField) -> Void)?
    public var sliderValueChanged: ((UISlider) -> Void)?
    public var buttonAction: ((UIButton) -> Void)?

    // MARK: - Tab Buttons

    private let videoTabButton = UIButton(type: .system)
    private let audioTabButton = UIButton(type: .system)
    private let subtitleTabButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // MARK: - Content Views

    private let contentContainer = UIView()
    private let videoContentView = UIView()
    private let audioContentView = UIView()
    private let subtitleContentView = UIView()

    // MARK: - State

    private var currentTab: Int = 0
    public var onDismiss: (() -> Void)?
    weak var playerView: PlayerView?

    // MARK: - Track Buttons

    private var videoTrackButton: UIButton?
    private var audioTrackButton: UIButton?

    // MARK: - Labels

    private let subtitleDelayLabel = UILabel()
    private let subtitleSizeLabel = UILabel()
    private let strokeWidthLabel = UILabel()
    private let horizontalMarginLabel = UILabel()
    private let verticalMarginLabel = UILabel()
    private let leftMarginLabel = UILabel()
    private let rightMarginLabel = UILabel()
    private let threadCountLabel = UILabel()

    // MARK: - Init (RE: SettingsView_initFields_and_callSuper @ 0x1014f21d4)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Configure (RE: SettingsView_configureSubviews @ 0x1014f2930)

    private func configureSubviews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 12

        addSubview(contentContainer)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentContainer.addSubview(videoContentView)
        contentContainer.addSubview(audioContentView)
        contentContainer.addSubview(subtitleContentView)
        videoContentView.translatesAutoresizingMaskIntoConstraints = false
        audioContentView.translatesAutoresizingMaskIntoConstraints = false
        subtitleContentView.translatesAutoresizingMaskIntoConstraints = false
        for v in [videoContentView, audioContentView, subtitleContentView] {
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                v.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 56),
                v.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }

        buildTabBar()
        buildVideoSection()
        buildVideoOptionsSection()
        buildAudioSection()
        buildSubtitleSection()
    }

    // MARK: - Tab Bar (RE: SettingsView_buildTabBar @ 0x1014f2a10)

    private func buildTabBar() {
        videoTabButton.setTitle("Video", for: .normal)
        audioTabButton.setTitle("Audio", for: .normal)
        subtitleTabButton.setTitle("Subtitle", for: .normal)
        closeButton.setTitle("✕", for: .normal)

        let titleFont = UIFont.systemFont(ofSize: 16, weight: .medium)
        for btn in [videoTabButton, audioTabButton, subtitleTabButton, closeButton] {
            btn.titleLabel?.font = titleFont
            btn.tintColor = .white
            btn.setTitleColor(.white, for: .normal)
        }

        videoTabButton.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
        audioTabButton.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
        subtitleTabButton.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        videoTabButton.tag = 0
        audioTabButton.tag = 1
        subtitleTabButton.tag = 2

        let tabBar = UIStackView(arrangedSubviews: [videoTabButton, audioTabButton, subtitleTabButton, closeButton])
        tabBar.axis = .horizontal
        tabBar.distribution = .equalSpacing
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 12),
            tabBar.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16),
            tabBar.heightAnchor.constraint(equalToConstant: 32),
        ])

        switchToTab(0)
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        switchToTab(sender.tag)
    }

    @objc private func closeButtonTapped() {
        onDismiss?()
    }

    // MARK: - Tab Switching (RE: SettingsView_switchToTab @ 0x1014ff1d8)

    func switchToTab(_ tab: Int) {
        currentTab = tab
        videoContentView.isHidden = tab != 0
        audioContentView.isHidden = tab != 1
        subtitleContentView.isHidden = tab != 2
    }

    // MARK: - Build Sections (RE: 0x1014F3124, 0x1014F3B6C, 0x1014F536C, 0x1014F5910)

    // RE: SettingsView_buildVideoSection @ 0x1014F3124 (0xA48 = 2632 bytes)
    // Video/audio track + horizontal-alignment rows.
    func buildVideoSection() {
        videoContentView.subviews.forEach { $0.removeFromSuperview() }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let videoTrackBtn = UIButton(type: .system)
        videoTrackBtn.setTitle("Video Track", for: .normal)
        videoTrackBtn.addTarget(self, action: #selector(showVideoTrackAlertImpl), for: .touchUpInside)
        videoTrackButton = videoTrackBtn

        let audioTrackBtn = UIButton(type: .system)
        audioTrackBtn.setTitle("Audio Track", for: .normal)
        audioTrackBtn.addTarget(self, action: #selector(buttonActionTriggeredImpl(_:)), for: .touchUpInside)
        audioTrackButton = audioTrackBtn

        let alignBtn = UIButton(type: .system)
        alignBtn.setTitle("Horizontal Alignment", for: .normal)
        alignBtn.addTarget(self, action: #selector(showHorizontalAlignAlertImpl), for: .touchUpInside)

        let aspectBtn = UIButton(type: .system)
        aspectBtn.setTitle("Aspect Ratio", for: .normal)
        aspectBtn.addTarget(self, action: #selector(aspectRatioButtonTappedImpl), for: .touchUpInside)

        [videoTrackBtn, audioTrackBtn, alignBtn, aspectBtn].forEach(stack.addArrangedSubview)

        videoContentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: videoContentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: videoContentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: videoContentView.trailingAnchor, constant: -16),
        ])
    }

    // RE: SettingsView_buildVideoOptionsSection @ 0x1014F3B6C (0xE78 = 3704 bytes)
    // Switches + stepper for KSOptions.
    func buildVideoOptionsSection() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bufferRow = makeStepperRow(title: "Adjust Buffer",
                                       decreaseAction: #selector(decreaseThreadCountImpl),
                                       increaseAction: #selector(increaseThreadCountImpl))
        stack.addArrangedSubview(bufferRow)

        videoContentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: videoContentView.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: videoContentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: videoContentView.trailingAnchor, constant: -16),
        ])
    }

    // RE: SettingsView_buildAudioSection @ 0x1014F536C (0x5A4 = 1444 bytes)
    // ScrollView-based audio settings.
    func buildAudioSection() {
        audioContentView.subviews.forEach { $0.removeFromSuperview() }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spatialSwitch = makeSwitchRow(title: "Spatial Audio")
        let engineButton = UIButton(type: .system)
        engineButton.setTitle("Audio Engine Type", for: .normal)
        engineButton.addTarget(self, action: #selector(buttonActionTriggeredImpl(_:)), for: .touchUpInside)

        stack.addArrangedSubview(spatialSwitch)
        stack.addArrangedSubview(engineButton)

        scroll.addSubview(stack)
        audioContentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: audioContentView.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: audioContentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: audioContentView.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: audioContentView.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    // RE: SettingsView_buildSubtitleSection @ 0x1014F5910 (0x1738 = 5944 bytes)
    // 5 switches + 2 sliders + 3 color pickers per UIComponents.md §9.2.
    func buildSubtitleSection() {
        subtitleContentView.subviews.forEach { $0.removeFromSuperview() }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 5 switches.
        let hdrSwitch = makeSwitchRow(title: "Enable HDR Subtitle")
        let resizeSwitch = makeSwitchRow(title: "Resize Image Subtitle")
        let assImageSwitch = makeSwitchRow(title: "ASS Use Image Render")
        let srtImageSwitch = makeSwitchRow(title: "SRT Use Image Render")
        let stripStyleSwitch = makeSwitchRow(title: "Strip Subtitle Style")

        // 2 sliders.
        let imageScaleRow = makeSliderRow(title: "Subtitle Image Scale", min: 0.5, max: 3.0, value: 1.0)
        let strokeWidthRow = makeSliderRow(title: "Text Stroke Width", min: 0, max: 5, value: 0)

        // 3 color pickers.
        let bgColorBtn = makeColorPickerRow(title: "Subtitle Bg Color")
        let strokeColorBtn = makeColorPickerRow(title: "Text Stroke Color")
        let shadowColorBtn = makeColorPickerRow(title: "Text Shadow Color")

        // Delay + size steppers.
        let delayRow = makeStepperRow(title: "Subtitle Delay",
                                      decreaseAction: #selector(decreaseSubtitleDelayImpl),
                                      increaseAction: #selector(increaseSubtitleDelayImpl))
        let sizeRow = makeStepperRow(title: "Subtitle Size",
                                     decreaseAction: #selector(decreaseSubtitleSizeImpl),
                                     increaseAction: #selector(increaseSubtitleDelayImpl))
        let strokeRow = makeStepperRow(title: "Stroke Width",
                                       decreaseAction: #selector(decreaseStrokeWidthImpl),
                                       increaseAction: #selector(increaseSubtitleDelayImpl))
        let marginRow = makeStepperRow(title: "Vertical Margin",
                                       decreaseAction: #selector(decreaseSubtitleSizeImpl),
                                       increaseAction: #selector(increaseVerticalMarginImpl))

        [hdrSwitch, resizeSwitch, assImageSwitch, srtImageSwitch, stripStyleSwitch,
         imageScaleRow, strokeWidthRow,
         bgColorBtn, strokeColorBtn, shadowColorBtn,
         delayRow, sizeRow, strokeRow, marginRow].forEach(stack.addArrangedSubview)

        subtitleContentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: subtitleContentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: subtitleContentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: subtitleContentView.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Row Builders

    private func makeSwitchRow(title: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .center
        let label = UILabel()
        label.text = title
        label.textColor = .white
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(switchValueChangedImpl(_:)), for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(toggle)
        return row
    }

    private func makeSliderRow(title: String, min: Float, max: Float, value: Float) -> UIView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 4
        let label = UILabel()
        label.text = title
        label.textColor = .white
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: #selector(sliderValueChangedImpl(_:)), for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(slider)
        return row
    }

    private func makeColorPickerRow(title: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .center
        let label = UILabel()
        label.text = title
        label.textColor = .white
        let btn = UIButton(type: .system)
        btn.setTitle("Pick", for: .normal)
        btn.addTarget(self, action: #selector(buttonActionTriggeredImpl(_:)), for: .touchUpInside)
        row.addArrangedSubview(label)
        row.addArrangedSubview(btn)
        return row
    }

    private func makeStepperRow(title: String, decreaseAction: Selector, increaseAction: Selector) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        let label = UILabel()
        label.text = title
        label.textColor = .white
        let minus = UIButton(type: .system)
        minus.setTitle("-", for: .normal)
        minus.addTarget(self, action: decreaseAction, for: .touchUpInside)
        let plus = UIButton(type: .system)
        plus.setTitle("+", for: .normal)
        plus.addTarget(self, action: increaseAction, for: .touchUpInside)
        row.addArrangedSubview(label)
        row.addArrangedSubview(minus)
        row.addArrangedSubview(plus)
        return row
    }

    // MARK: - Value Changed Handlers

    // RE: SettingsView_sliderValueChangedImpl @ 0x1014fc2ac
    @objc func sliderValueChangedImpl(_ sender: UISlider) {
        sliderValueChanged?(sender)
    }

    // RE: SettingsView_switchValueChangedImpl @ 0x1014fc020
    @objc func switchValueChangedImpl(_ sender: UISwitch) {
        switchValueChanged?(sender)
    }

    // RE: SettingsView_textFieldValueChangedImpl @ 0x1014fc148
    @objc func textFieldValueChangedImpl(_ sender: UITextField) {
        textFieldValueChanged?(sender)
    }

    // RE: SettingsView_buttonActionTriggeredImpl @ 0x1014fc3d4
    @objc func buttonActionTriggeredImpl(_ sender: UIButton) {
        buttonAction?(sender)
    }

    // MARK: - Subtitle Controls (RE: 0x1014FC4D8 .. 0x1014FD004)

    // RE: SettingsView_decreaseSubtitleDelayImpl @ 0x1014FC4D8
    @objc func decreaseSubtitleDelayImpl() {
        guard let player = playerView?.playerLayer?.player else { return }
        player.subtitleDelay -= 0.5
        subtitleDelayLabel.text = String(format: "%.1f", player.subtitleDelay)
    }

    // RE: SettingsView_increaseSubtitleDelayImpl @ 0x1014FC79C
    @objc func increaseSubtitleDelayImpl() {
        guard let player = playerView?.playerLayer?.player else { return }
        player.subtitleDelay += 0.5
        subtitleDelayLabel.text = String(format: "%.1f", player.subtitleDelay)
    }

    // RE: SettingsView_decreaseSubtitleSizeImpl @ 0x1014FCB3C
    @objc func decreaseSubtitleSizeImpl() {
        // Reduces KSOptions.textFontSize / scale.
        KSOptions.textFontSize = max(8, KSOptions.textFontSize - 1)
        subtitleSizeLabel.text = "\(Int(KSOptions.textFontSize))"
    }

    // RE: SettingsView_decreaseStrokeWidthImpl @ 0x1014FCCE8
    @objc func decreaseStrokeWidthImpl() {
        KSOptions.textStrokeWidth = max(0, KSOptions.textStrokeWidth - 0.5)
        strokeWidthLabel.text = String(format: "%.1f", KSOptions.textStrokeWidth)
    }

    // RE: SettingsView_increaseVerticalMarginImpl @ 0x1014FD004
    @objc func increaseVerticalMarginImpl() {
        KSOptions.textYAlign = .bottom
        verticalMarginLabel.text = "Bottom"
    }

    // MARK: - Thread Count (RE: 0x1014FD42C, 0x1014FD510)

    // RE: SettingsView_decreaseThreadCountImpl @ 0x1014FD42C
    @objc func decreaseThreadCountImpl() {
        // KSOptions.videoFilters/audioFilters thread tuning hook.
        threadCountLabel.text = "\(max(1, (Int(threadCountLabel.text ?? "1") ?? 1) - 1))"
    }

    // RE: SettingsView_increaseThreadCountImpl @ 0x1014FD510
    @objc func increaseThreadCountImpl() {
        threadCountLabel.text = "\((Int(threadCountLabel.text ?? "1") ?? 1) + 1)"
    }

    // MARK: - Alerts (RE: 0x1014FB9B4, 0x100150550)

    // RE: SettingsView_showHorizontalAlignAlertImpl @ 0x1014FB9B4
    @objc func showHorizontalAlignAlertImpl() {
        buttonAction?(UIButton())
    }

    // RE: SettingsView_showVideoTrackAlertImpl @ 0x100150550
    @objc func showVideoTrackAlertImpl() {
        buttonAction?(videoTrackButton ?? UIButton())
    }

    // MARK: - Aspect Ratio (RE: SettingsView_aspectRatioButtonTappedImpl @ 0x1014FECF0)

    @objc func aspectRatioButtonTappedImpl() {
        // Cycle through aspect modes — actual cycling is in IOSVideoPlayerView.handleAspectFillButtonTapped.
        buttonAction?(UIButton())
    }

    // MARK: - Adjust Buffer (RE: SettingsView_updateAdjustBuffer @ 0x1014FD5F8)

    @objc func updateAdjustBuffer() {
        // KSOptions.preferredForwardBufferDuration tuning hook.
    }
}
#endif
