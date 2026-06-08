//
//  SettingsView.swift
//  KSPlayer
//
//  RE-reconstructed tabbed settings panel for video, audio, and
//  subtitle configuration during playback.
//
//  Binary: _TtC8KSPlayer12SettingsView (CMa 0x1014FFF98)
//  RE source: v1.3.15 binary, init entry @ 0x1014F21D4
//
//  Function surface: the doc's UIComponents.md §9.2 lists 9 address-table functions
//  (configureSubviews, buildTabBar, buildVideoSection, buildVideoOptionsSection,
//  buildAudioSection, buildSubtitleSection, initFields_and_callSuper,
//  mainActorDispatch_withSender, switchToTab) plus a roster of named action *Impl
//  handlers (lines 1490-1505). Residual closure (1.3.15) proved that three handlers
//  the prior reconstruction assumed were inlined are in fact real standalone
//  functions: increaseSubtitleSizeImpl @ 0x1014fccc0, increaseStrokeWidthImpl @
//  0x1014fce68, decreaseVerticalMarginImpl @ 0x1014fd02c (each tail-calls a shared
//  +N stepper helper — FUN_1014fce80 for size/stroke, FUN_1014fd27c for margin).
//  The @objc tap trampolines (tabButtonTapped, closeButtonTapped) and the Swift
//  row-builder helpers are not RE-named entries.
//
//  Field surface: types.json confirms 25 stored fields — 4 UInt8 action-key
//  anchors (indices 0-3, modeled here as 4 stored action closures), then the 4
//  buttons at contiguous indices 4-7 (3 tab buttons video/audio/subtitle + close;
//  the Tab enum has exactly 3 cases, so there is NO phantom 4th tab — the doc
//  prose "4 tab buttons + close" is a doc-side arithmetic slip), 4 content
//  containers, currentTab, onDismiss, weak playerView, 2 optional track buttons,
//  and 8 label fields = 25.
//

#if canImport(UIKit)
import UIKit
import Metal
// SwiftUI is used only for `HorizontalAlignment`, which the binary stores as the
// horizontal-alignment global (DAT_1044587c0) and compares against
// `SwiftUI.HorizontalAlignment.leading/center/trailing` in showHorizontalAlignAlertImpl.
import SwiftUI

public class SettingsView: UIView {
    // MARK: - Tabs

    /// The three settings tabs. Raw values match the binary roster (`ENUM_CASES_1.3.15`):
    /// video=0, audio=1, subtitle=2 — these are also the tag values assigned to the
    /// tab buttons, so `Tab(rawValue: sender.tag)` round-trips the tap target.
    /// RE: KSPlayer.SettingsView.Tab (nested enum, CMa 0x1014FFF98)
    public enum Tab: Int {
        case video = 0
        case audio = 1
        case subtitle = 2
    }

    // MARK: - Action Slots
    //
    // The binary's 25-field roster names these four as `switchValueChangedKey`,
    // `textFieldValueChangedKey`, `sliderValueChangedKey`, `buttonActionKey`,
    // each typed Swift.UInt8. Those UInt8 bytes are `objc_setAssociatedObject`
    // key anchors; the real closures live as associated objects keyed by them.
    // We model the action slots directly as stored closures — a behaviorally
    // equivalent Swift idiom that drops the associated-object indirection while
    // preserving the per-control action wiring. The roster names are noted here
    // for traceability against types.json field indices 0-3.
    // RE: switchValueChangedKey/textFieldValueChangedKey/sliderValueChangedKey/buttonActionKey (0x1014FFF98)

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

    // RE: currentTab :: KSPlayer.SettingsView.Tab (field index 12, 0x1014FFF98)
    private var currentTab: Tab = .video
    public var onDismiss: (() -> Void)?
    // RE: weak playerView :: KSPlayer.IOSVideoPlayerView? (field index 14, 0x1014FFF98).
    // Concrete IOSVideoPlayerView (not the PlayerView base) so aspect-fill cycling and
    // other IOSVideoPlayerView-specific behavior is reachable from this panel.
    weak var playerView: IOSVideoPlayerView?

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

        switchToTab(.video)
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        // Button tags are assigned to match Tab raw values (0/1/2) in buildTabBar().
        guard let tab = Tab(rawValue: sender.tag) else { return }
        switchToTab(tab)
    }

    @objc private func closeButtonTapped() {
        onDismiss?()
    }

    // MARK: - Tab Switching (RE: SettingsView_switchToTab @ 0x1014FF1D8)

    /// Selects a tab: records it, highlights the matching tab button (rounded white
    /// pill background, white title) while clearing the others (clear background,
    /// white title at 0.7 alpha), and hides every content view except the selected one.
    ///
    /// RE: 0x1014FF1D8 (SettingsView.switchToTab, 1.3.15). Writes `currentTab` first
    /// (0x1014ff1f4), loops the 3 tab buttons [video, audio, subtitle] comparing each
    /// button index `(&DAT_103d08338)[i]` against the selected raw value, then hides
    /// the 3 content views [video, audio, subtitle]. The decompile's title-color
    /// constants were read directly and CORRECT the prior reconstruction (which used a
    /// dark label on the active tab "for legibility" — a divergence from the binary):
    ///   - active tab: backgroundColor = whiteColor; layer.cornerRadius = 8.0
    ///     (`0x4020000000000000`); layer.masksToBounds = true; titleColor = whiteColor
    ///     (the binary really does set white-on-white, matching the original doc note —
    ///     the "self-inconsistent" reading was wrong).
    ///   - inactive tab: backgroundColor = clearColor; layer.cornerRadius = 0;
    ///     titleColor = whiteColor at alpha 0.7 (`0x3fe6666666666666` = 0.7).
    /// `setTitleColor:forState:` is issued for `.normal` (state 0) on every iteration.
    func switchToTab(_ tab: Tab) {
        currentTab = tab

        // Highlight the active tab button; clear the rest.
        let tabButtons = [videoTabButton, audioTabButton, subtitleTabButton]
        for (index, button) in tabButtons.enumerated() {
            if index == tab.rawValue {
                button.backgroundColor = .white
                button.layer.cornerRadius = 8
                button.layer.masksToBounds = true
                // RE: active title is whiteColor (white pill, white label) — verbatim
                // from 0x1014FF1D8, not a contrast-adjusted black.
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = .clear
                button.layer.cornerRadius = 0
                // RE: inactive title is whiteColor at 0.7 alpha (0x3fe6666666666666).
                button.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
            }
        }

        videoContentView.isHidden = tab != .video
        audioContentView.isHidden = tab != .audio
        subtitleContentView.isHidden = tab != .subtitle
    }

    // MARK: - Main-Actor Sender Dispatch (RE: SettingsView_mainActorDispatch_withSender @ 0x1014F8D98)

    /// Forwards a UI control sender (`UISwitch` / `UISlider` / `UIButton` /
    /// `UITextField`) onto the main actor before invoking the supplied action
    /// closure. The binary emits this as a discrete `@MainActor`-isolated
    /// trampoline: it asserts the current executor is the main actor
    /// (`_swift_task_isCurrentExecutor`; reports an unexpected-executor fault
    /// tagged `"KSPlayer/SettingsView.swift"` if not), retains the sender and the
    /// closure context, then calls the stored action with the sender. Kept
    /// separate from the per-control `*Impl` handlers per the API-surface
    /// preservation rule.
    /// RE: 0x1014F8D98
    @MainActor
    func mainActorDispatch<Sender: AnyObject>(_ sender: Sender, action: @MainActor (Sender) -> Void) {
        // On the main actor the executor assertion in the binary is satisfied by
        // this method's isolation; the call below mirrors `(*in_x4)(sender, ...)`.
        /// RE: 0x1014F8D98 (SettingsView.mainActorDispatch, 1.3.15). ARC shape now
        /// byte-verified: the decompile asserts the executor via
        /// `_swift_task_isCurrentExecutor` and, on mismatch, calls
        /// `_swift_task_reportUnexpectedExecutor("KSPlayer/SettingsView.swift", 0x1b, 1, …)`
        /// (string length 0x1b = 27). It then retains exactly two refs —
        /// `_objc_retain` x23 (the sender) and `_objc_retain` x21 (the closure
        /// context) — issues the indirect call `(*in_x4)(sender, context)`, and
        /// balances with `_swift_release` (context) + `_objc_release` ×2 (sender,
        /// context). The two-retain forwarded-context shape is confirmed, not inferred.
        action(sender)
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
        alignBtn.addTarget(self, action: #selector(showHorizontalAlignAlertImpl(_:)), for: .touchUpInside)

        let aspectBtn = UIButton(type: .system)
        aspectBtn.setTitle("Aspect Ratio", for: .normal)
        aspectBtn.addTarget(self, action: #selector(aspectRatioButtonTappedImpl(_:)), for: .touchUpInside)

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

        // Delay + size + stroke + margin steppers.
        //
        // Each +/- pair drives the SAME parameter. The 1.3.15 decompile of
        // buildSubtitleSection (0x1014F5910, 5944 bytes) wires four matched
        // increment/decrement selector pairs onto these rows. The prior
        // reconstruction mis-wired the +increase action of Subtitle Size and
        // Stroke Width to increaseSubtitleDelayImpl (which bumps DELAY, not
        // size/stroke) and the -decrease of Vertical Margin to
        // decreaseSubtitleSizeImpl (which shrinks SIZE, not margin). Corrected
        // here so each stepper bumps its own parameter.
        //
        // Note: the binary's named-impl roster (UIComponents.md lines 1490-1505)
        // symbolizes only one direction for size (decrease), stroke (decrease),
        // and vertical margin (increase). The opposite directions lived inline
        // in the 5944-byte body without a standalone symbol; they are
        // reconstructed below as increaseSubtitleSizeImpl / increaseStrokeWidthImpl
        // / decreaseVerticalMarginImpl, mirroring their documented siblings.
        let delayRow = makeStepperRow(title: "Subtitle Delay",
                                      decreaseAction: #selector(decreaseSubtitleDelayImpl),
                                      increaseAction: #selector(increaseSubtitleDelayImpl))
        let sizeRow = makeStepperRow(title: "Subtitle Size",
                                     decreaseAction: #selector(decreaseSubtitleSizeImpl),
                                     increaseAction: #selector(increaseSubtitleSizeImpl))
        let strokeRow = makeStepperRow(title: "Stroke Width",
                                       decreaseAction: #selector(decreaseStrokeWidthImpl),
                                       increaseAction: #selector(increaseStrokeWidthImpl))
        let marginRow = makeStepperRow(title: "Vertical Margin",
                                       decreaseAction: #selector(decreaseVerticalMarginImpl),
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

    /// RE: 0x1014FC4D8 (SettingsView.decreaseSubtitleDelayImpl, 1.3.15). The decompile
    /// reads/writes `playerView.playerLayer.subtitleModel.subtitleDelay` (the
    /// `SubtitleModel`, NOT `player.subtitleDelay`): `delay = max(0.0, delay - 0.5)`
    /// (floor clamp at 0.0 at 0x1014fc5a4), then sets the label with format `"%.1fs"`
    /// (binary format literal `0x7366312e25` = "%.1fs", trailing "s"). The label value
    /// is re-fetched from `subtitleModel.subtitleDelay` after the write.
    @objc func decreaseSubtitleDelayImpl() {
        guard let model = playerView?.playerLayer?.subtitleModel else { return }
        model.subtitleDelay = max(0.0, model.subtitleDelay - 0.5)
        subtitleDelayLabel.text = String(format: "%.1fs", model.subtitleDelay)
    }

    /// RE: 0x1014FC79C (SettingsView.increaseSubtitleDelayImpl, 1.3.15). Mirror of the
    /// decrement against `subtitleModel.subtitleDelay`: `delay = min(100.0, delay + 0.5)`
    /// (ceiling clamp at 100.0 at 0x1014fc844); label format `"%.1fs"` (same literal).
    @objc func increaseSubtitleDelayImpl() {
        guard let model = playerView?.playerLayer?.subtitleModel else { return }
        model.subtitleDelay = min(100.0, model.subtitleDelay + 0.5)
        subtitleDelayLabel.text = String(format: "%.1fs", model.subtitleDelay)
    }

    // MARK: - Subtitle stepper accumulators
    //
    // RE: 0x1014FCB3C / 0x1014fccc0 / 0x1014FCCE8 / 0x1014fce68 / 0x1014FD004 /
    // 0x1014fd02c (1.3.15). The size / stroke / vertical-margin steppers do NOT
    // mutate `KSOptions.textFontSize` / `textStrokeWidth` / `textYAlign` (the prior
    // reconstruction did — `KSOptions.textStrokeWidth` and `.textYAlign` do not even
    // exist as KSOptions members, so that code could not compile). The binary backs
    // each control with a module-level mutable `double` accumulator stepped by an
    // integer amount and rendered as `"<Int><unit>"`:
    //   - size   -> global DAT_103d097a0 (also read by the SRT/ASS renderers and
    //               written by SubtitleModel.applySystemCaptionAppearance), unit "pt"
    //   - stroke -> global DAT_104458788 (same renderer-shared font-stroke global),
    //               unit "px"
    //   - margin -> global DAT_1044587e0 (subtitle vertical margin), unit "px"
    // Modeled here as `private static var` on SettingsView — a behaviorally
    // equivalent Swift idiom for the binary's file-scope globals, same modeling
    // decision used for the action slots above. The globals' live values are seeded
    // elsewhere (SubtitleModel.applySystemCaptionAppearance writes DAT_103d097a0 /
    // DAT_104458788); the steppers clamp relative to whatever the global holds. The
    // literal initializers below are reconstruction seed defaults, not decompiled
    // constants (the seeding sites were not byte-read in this pass).
    private static var subtitleSizeValue: Int = 20
    private static var strokeWidthValue: Int = 0
    private static var verticalMarginValue: Int = 0

    /// RE: 0x1014FCB3C (SettingsView.decreaseSubtitleSizeImpl, 1.3.15). Integer
    /// decrement of the size global: `size = max(1, Int(size) - 1)` (floor clamp `< 2`
    /// → 1 at 0x1014fcbb0). Label = `"\(Int(size))pt"` (suffix literal `0x7470` = "pt").
    @objc func decreaseSubtitleSizeImpl() {
        Self.subtitleSizeValue = max(1, Self.subtitleSizeValue - 1)
        subtitleSizeLabel.text = "\(Self.subtitleSizeValue)pt"
    }

    /// RE: 0x1014fccc0 (the +Subtitle-Size handler; a real standalone function, NOT
    /// inlined as the prior reconstruction assumed — it tail-calls the shared +1
    /// helper FUN_1014fce80). `size = min(50, Int(size) + 1)` (ceiling clamp `> 0x31`
    /// → 0x32=50 at 0x1014fcf90); label suffix "pt" (0x7470).
    @objc func increaseSubtitleSizeImpl() {
        Self.subtitleSizeValue = min(50, Self.subtitleSizeValue + 1)
        subtitleSizeLabel.text = "\(Self.subtitleSizeValue)pt"
    }

    /// RE: 0x1014FCCE8 (SettingsView.decreaseStrokeWidthImpl, 1.3.15). Integer
    /// decrement of the stroke global with a branchless `max(_, 0)` floor at
    /// 0x1014fcd30: `stroke = max(0, Int(stroke) - 1)`. Label = `"\(Int(stroke))px"`
    /// (suffix literal `0x7870` = "px"). Step is 1 (integer), NOT 0.5, and the value
    /// is rendered as an Int — not `%.1f`.
    @objc func decreaseStrokeWidthImpl() {
        Self.strokeWidthValue = max(0, Self.strokeWidthValue - 1)
        strokeWidthLabel.text = "\(Self.strokeWidthValue)px"
    }

    /// RE: 0x1014fce68 (the +Stroke-Width handler; a real standalone function tail-
    /// calling the same +1 helper FUN_1014fce80). `stroke = min(50, Int(stroke) + 1)`
    /// (ceiling clamp 0x32=50); label suffix "px" (0x7870).
    @objc func increaseStrokeWidthImpl() {
        Self.strokeWidthValue = min(50, Self.strokeWidthValue + 1)
        strokeWidthLabel.text = "\(Self.strokeWidthValue)px"
    }

    /// RE: 0x1014FD004 (SettingsView.increaseVerticalMarginImpl, 1.3.15). Despite the
    /// symbol name, this handler DECREMENTS the margin global by 10 via helper
    /// FUN_1014fd0bc: `margin = max(0, Int(margin) - 10)` (subtract 10 at 0x1014fd1ec,
    /// branchless max-0 floor). Label = `"\(Int(margin))px"` (suffix 0x7870). It does
    /// NOT set `KSOptions.textYAlign = .bottom` / "Bottom" (the prior reconstruction's
    /// guess — refuted by decompile). The named increase/decrease pair is inverted in
    /// the binary relative to effect; both the symbol name and the -10 step are kept
    /// verbatim as binary facts.
    @objc func increaseVerticalMarginImpl() {
        Self.verticalMarginValue = max(0, Self.verticalMarginValue - 10)
        verticalMarginLabel.text = "\(Self.verticalMarginValue)px"
    }

    /// RE: 0x1014fd02c (the named decreaseVerticalMargin handler; a real standalone
    /// function — NOT inlined — tail-calling helper FUN_1014fd27c). It INCREMENTS the
    /// margin global by 10: `margin = min(1000, Int(margin) + 10)` (add 10, ceiling
    /// clamp `> 999` → 1000 at 0x1014fd3d8); label suffix "px" (0x7870). Refutes the
    /// prior `KSOptions.textYAlign = .top` / "Top" guess.
    @objc func decreaseVerticalMarginImpl() {
        Self.verticalMarginValue = min(1000, Self.verticalMarginValue + 10)
        verticalMarginLabel.text = "\(Self.verticalMarginValue)px"
    }

    // MARK: - Thread Count (RE: 0x1014FD42C, 0x1014FD510)
    //
    // RE: backed by module-level Int global DAT_103d097d0 (not by parsing the label
    // text, which the prior reconstruction did). Modeled as a `private static var`
    // accumulator, matching the size/stroke/margin modeling above.
    private static var threadCountValue: Int = 1

    /// RE: 0x1014FD42C (SettingsView.decreaseThreadCountImpl, 1.3.15). `count =
    /// max(1, count - 1)` (floor clamp `< 2` → 1 at 0x1014fd47c); label = `"\(count)"`
    /// (Int description, no unit suffix). The backing store is the Int global
    /// DAT_103d097d0; the prior `Int(threadCountLabel.text ...)` round-trip was a guess.
    @objc func decreaseThreadCountImpl() {
        Self.threadCountValue = max(1, Self.threadCountValue - 1)
        threadCountLabel.text = "\(Self.threadCountValue)"
    }

    /// RE: 0x1014FD510 (SettingsView.increaseThreadCountImpl, 1.3.15). `count =
    /// min(16, count + 1)` (ceiling clamp `> 0xf` → 0x10=16 at 0x1014fd560); label =
    /// `"\(count)"`. The +16 ceiling was absent from the prior reconstruction.
    @objc func increaseThreadCountImpl() {
        Self.threadCountValue = min(16, Self.threadCountValue + 1)
        threadCountLabel.text = "\(Self.threadCountValue)"
    }

    // MARK: - Alerts (RE: 0x1014FB9B4, 0x100150550)

    /// Module-level current horizontal-alignment store (binary global DAT_1044587c0),
    /// compared in the alert against SwiftUI `HorizontalAlignment.leading/center/
    /// trailing`. Modeled as a `private static var` to match the binary's file-scope
    /// global, consistent with the stepper accumulators above.
    /// RE: 0x1044587c0 (read/written by showHorizontalAlignAlertImpl @ 0x1014fbac8).
    private static var horizontalAlignment: HorizontalAlignment = .center

    /// RE: 0x1014FB9B4 (SettingsView.showHorizontalAlignAlertImpl, 1.3.15). The prior
    /// `buttonAction?(UIButton())` stub is refuted by decompile: the real body builds a
    /// `UIAlertController` (actionSheet) with three `UIAlertAction`s titled
    /// "Leading"/"Center"/"Trailing" (title array `s_Leading_103d08420`, compared by
    /// value `0x676e696461656c`="leading"/`0x7265746e6563`="center"/
    /// `0x676e696c69617274`="trailing" against the global DAT_1044587c0), plus a
    /// "Cancel" action (style `.cancel`, title literal `0x88b6e6968fe5`). It sets the
    /// popover `sourceRect` to the sender's bounds, walks the responder chain from
    /// `playerView` up to the first `UIViewController`, and presents the sheet there.
    /// Each option's handler writes the chosen alignment back into DAT_1044587c0.
    @objc func showHorizontalAlignAlertImpl(_ sender: UIButton) {
        let alert = UIAlertController(title: "Horizontal Alignment", message: nil, preferredStyle: .actionSheet)
        let options: [(String, HorizontalAlignment)] = [
            ("Leading", .leading), ("Center", .center), ("Trailing", .trailing),
        ]
        for (title, alignment) in options {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                Self.horizontalAlignment = alignment
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        // RE: walk the responder chain from playerView to the owning view controller.
        var responder: UIResponder? = playerView
        while let current = responder {
            if let viewController = current as? UIViewController {
                viewController.present(alert, animated: true)
                break
            }
            responder = current.next
        }
    }

    /// RE: 0x100150550 (SettingsView.showVideoTrackAlertImpl, 1.3.15). A thin forwarder:
    /// the decompile tail-calls a generic dispatch trampoline `FUN_100150564(URL-type-
    /// metadata, FUN_10014a6b8)` which invokes the shared video-track-selection handler
    /// `FUN_10014a6b8` with the stored video-track button. The track-picker UI itself
    /// lives in that shared handler (built once and reused across track buttons), not in
    /// this function. Modeled here by forwarding the video-track button into the
    /// `buttonAction` slot, which is where this panel's owner installs the track-picker
    /// presentation. CROSS-FILE: the concrete picker is `FUN_10014a6b8` (track-selection
    /// action, owned outside this file).
    @objc func showVideoTrackAlertImpl() {
        buttonAction?(videoTrackButton ?? UIButton())
    }

    // MARK: - Aspect Ratio (RE: SettingsView_aspectRatioButtonTappedImpl @ 0x1014FECF0)

    /// RE: 0x1014FECF0 (SettingsView.aspectRatioButtonTappedImpl, 1.3.15). Refutes the
    /// prior `buttonAction?(UIButton())` stub. Real behavior, in two parts:
    /// 1. Segmented selection visual: fetch `sender.superview as UIStackView`, iterate
    ///    its arranged `UIButton`s, and recolor each (backgroundColor + titleColor) by
    ///    whether its `tag` matches `sender.tag` (loop at 0x1014feef0). The two `UIColor`
    ///    factory selectors for the recolor were not byte-decoded in this pass — the
    ///    selected/unselected colors below mirror `switchToTab`'s verified pill scheme
    ///    (white pill / clear), which is the same visual idiom; treat the specific
    ///    color choice as not-yet-pinned (see RESIDUAL note in the closure report).
    /// 2. Apply the mode to the player: read `sender.tag` and set
    ///    `playerLayer.player.contentMode` (the `MediaPlayerProtocol.contentMode`
    ///    setter, reached via the player vtable slot +0xD8 at 0x1014ff0c8) by mapping
    ///    tag → `UIViewContentMode` raw value: tag 0 → 1 (.scaleAspectFit),
    ///    tag 1 → 0 (.scaleToFill), tag 2 → 2 (.scaleAspectFill). This mapping IS
    ///    verified from the immediate constants at 0x1014feff0..0x1014ff0a0.
    @objc func aspectRatioButtonTappedImpl(_ sender: UIButton) {
        // Part 1: highlight the selected segment within the sender's stack view.
        // RESIDUAL (genuinely-runtime color selectors not byte-read): the exact
        // UIColor factories for selected/unselected were elided in the decompile;
        // colors below follow the verified switchToTab pill scheme as a placeholder.
        if let stack = sender.superview as? UIStackView {
            for case let button as UIButton in stack.arrangedSubviews {
                let isSelected = button.tag == sender.tag
                button.backgroundColor = isSelected ? .white : .clear
                button.setTitleColor(isSelected ? .black : .white, for: .normal)
            }
        }
        // Part 2: map the tag to UIViewContentMode and apply to the player.
        // RE: tag→rawValue mapping is 0→1, 1→0, 2→2 (0x1014feff0..0x1014ff0a0).
        let mode: UIViewContentMode
        switch sender.tag {
        case 0: mode = .scaleAspectFit
        case 1: mode = .scaleToFill
        case 2: mode = .scaleAspectFill
        default: return
        }
        playerView?.playerLayer?.player.contentMode = mode
    }

    // MARK: - Adjust Buffer (RE: SettingsView_updateAdjustBuffer @ 0x1014FD5F8)

    /// RE: 0x1014FD5F8 (SettingsView.updateAdjustBuffer, 1.3.15). Refutes the prior
    /// empty "preferredForwardBufferDuration tuning hook" stub. Called from
    /// `IOSVideoPlayerView.presentSettingsPanel` (0x1014ffa0c). The real body reads
    /// `playerView.playerLayer.options` (`KSOptions`) and, in three passes (one each for
    /// brightness, contrast, saturation), packs the triple `{brightness, contrast,
    /// saturation}` as three `Float`s (16-byte struct, length 0x10) into a Metal buffer
    /// via `device.makeBuffer(bytes:length:options:)` (`newBufferWithBytes:length:option:`
    /// on the shared `MTLDevice` global DAT_104458f68), labels the buffer "adjust"
    /// (literal `0x7473756a6461`), and stores it into `KSOptions.adjustBuffer`, syncing
    /// the value across the player layers' option objects.
    @objc func updateAdjustBuffer() {
        guard let options = playerView?.playerLayer?.options,
              let device = MTLCreateSystemDefaultDevice() else { return }
        var components = SIMD3<Float>(options.brightness, options.contrast, options.saturation)
        let buffer = withUnsafeBytes(of: &components) { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: 16, options: [])
        }
        buffer?.label = "adjust"
        options.adjustBuffer = buffer
    }
}
#endif
