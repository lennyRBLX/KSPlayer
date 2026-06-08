//
//  IOSVideoPlayerView+ControlHandlers.swift
//  KSPlayer
//
//  v1.3.15 reconstruction — the player-specific methods added on top of the
//  upstream KSPlayer `IOSVideoPlayerView` class. Method names, sizes, and
//  behavior all sourced from `.reversal/UIComponents.md §1.2` and verified
//  Ghidra decompiles.
//
//  All public methods are `@MainActor` (the binary routes every named method
//  through the MainActor dispatcher @ 0x1014451C4). The CLAUDE.md typo-fix
//  rule applies to identifiers; UserDefaults / persisted string keys keep
//  the binary's original spelling where applicable.
//

// Platform guard rationale: this file extends the UIKit-only `IOSVideoPlayerView`.
// The `&& canImport(CallKit)` clause is inherited verbatim from the core
// `IOSVideoPlayerView.swift` guard (line 7) so the extension is compiled under
// exactly the same condition set as the class it extends — narrowing it here in
// isolation would extend a type that does not exist on a UIKit-without-CallKit
// platform and fail to link. CallKit is *not* referenced by any handler below;
// the dependency lives on the core class, so the guards must move together.
// CROSS-FILE NOTE: tvOS has UIKit but no CallKit, so this guard currently excludes
// the whole IOSVideoPlayerView surface from tvOS. If tvOS support is wanted, both
// this guard and the core file's line-7 guard should narrow to `#if canImport(UIKit)`
// together (with the §13 iOS-17 `singleSelection` calls kept behind their own
// availability guards). Not changed here to keep the two guards in lockstep.
#if canImport(UIKit) && canImport(CallKit)
import AVKit
import Combine
import MediaPlayer
import Network
import UIKit

@MainActor
public extension IOSVideoPlayerView {
    // MARK: - 1. Play / pause (`handlePlayPause_impl @ 0x1014E136C`)

    /// Smart play/pause: playing→pause, finished→replay, paused→play.
    /// RE: `IOSVideoPlayerView_handlePlayPause_impl @ 0x1014E136C` (0x1C0 = 448 bytes).
    @objc func handlePlayPause() {
        guard let layer = playerLayer else { return }
        switch layer.state {
        case .playedToTheEnd:
            layer.seek(time: 0) { [weak layer] _ in layer?.play() }
        case .paused, .error:
            layer.play()
        default:
            layer.pause()
        }
        updatePlayPauseButtonIcon()
    }

    // MARK: - 2. Screenshot capture (`handleScreenshot_impl @ 0x1014E153C`)

    /// White flash (0.1s, alpha 0.8) + medium haptic + async capture.
    /// RE: 0x394 = 916 bytes. Save callback at `image:didFinishSavingWithError: @ 0x1014E28C4`.
    @objc func handleScreenshot() {
        let flash = UIView(frame: bounds)
        flash.backgroundColor = .white
        flash.alpha = 0.8
        addSubview(flash)
        let hg = UIImpactFeedbackGenerator(style: .medium)
        hg.impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            flash.alpha = 0
        }, completion: { _ in
            flash.removeFromSuperview()
        })

        Task { @MainActor in
            guard let image = await playerLayer?.player.thumbnailImageAtCurrentTime() else { return }
            let uiImage = UIImage(cgImage: image)
            UIImageWriteToSavedPhotosAlbum(uiImage, self, #selector(screenshotSaveDidFinish(_:didFinishSavingWithError:contextInfo:)), nil)
            presentScreenshotPreview(uiImage)
        }
    }

    @objc private func screenshotSaveDidFinish(_: UIImage, didFinishSavingWithError error: Error?, contextInfo _: UnsafeRawPointer) {
        if let error {
            showPrompt(NSLocalizedString("Screenshot save failed: \(error.localizedDescription)", comment: ""))
        } else {
            showPrompt(NSLocalizedString("Screenshot saved", comment: ""))
        }
    }

    private func presentScreenshotPreview(_ image: UIImage) {
        let preview = UIImageView(image: image)
        preview.contentMode = .scaleAspectFit
        preview.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        preview.layer.cornerRadius = 8
        preview.layer.masksToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        NSLayoutConstraint.activate([
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            preview.widthAnchor.constraint(equalToConstant: 120),
            preview.heightAnchor.constraint(equalToConstant: 80),
        ])
        screenshotPreviewView = preview

        // Auto-dismiss after 3s with the slide animation defined below.
        let work = DispatchWorkItem { [weak self] in self?.dismissScreenshotPreview() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        customDelayItem = work
    }

    // MARK: - 3. Dismiss screenshot preview (`dismissScreenshotPreview_impl @ 0x1014E2C28`)

    /// Slide 150pt right + fade out (0.3s). RE: 0x164 = 356 bytes.
    @objc func dismissScreenshotPreview() {
        guard let preview = screenshotPreviewView else { return }
        UIView.animate(withDuration: 0.3, animations: {
            preview.transform = CGAffineTransform(translationX: 150, y: 0)
            preview.alpha = 0
        }, completion: { _ in
            preview.removeFromSuperview()
        })
        screenshotPreviewView = nil
    }

    // MARK: - 4. Jump forward (`handleJumpForward_impl @ 0x1014E29A8`)

    /// Seek +10s. Per doc §1.2 the magnitude is a verified `+10s` literal and the
    /// accuracy flag is **read from the player's options** (the instance
    /// `isAccurateSeek`, not a hardcoded value). RE: `handleJumpForward_impl @
    /// 0x1014E29A8` (0x150 = 336 bytes, "Seek +10s (reads accuracy flag from
    /// options)").
    ///
    /// The `±10s` here is the binary-documented value (§1.2 rows 187–188 and the
    /// doubleTap §1.2 row 195 all agree on ±10s). The Components/play-app
    /// `PlayerPreferences.forwardBackwardDuration` (default 15) lived in the app
    /// layer in the binary; KSPlayer (this module) is upstream of the play app and
    /// cannot import it, so this module keeps the §1.2 default of 10.
    /// CROSS-FILE NEEDED: for a user-configurable jump duration, the play app should
    /// pass `PlayerPreferences.forwardBackwardDuration` down to a future settable
    /// hook on this view (e.g. a `jumpDuration` property) rather than hardcoding here.
    @objc func handleJumpForward() {
        // Accuracy read from the player's instance options per §1.2.
        let accurate = playerLayer?.options.isAccurateSeek ?? KSOptions.isAccurateSeek
        seekBy(10, accurate: accurate)
    }

    // MARK: - 5. Jump back (`handleJumpBack_impl @ 0x1014E2B08`)

    /// Seek −10s. Per doc §1.2 the magnitude is a verified `−10s` literal and this
    /// handler **hardcodes `accurate = true`** (unlike `handleJumpForward`, which
    /// reads it from options). RE: `handleJumpBack_impl @ 0x1014E2B08` (0x110 = 272
    /// bytes, "Seek −10s (hardcodes accurate=1)").
    @objc func handleJumpBack() {
        seekBy(-10, accurate: true)
    }

    /// Relative seek helper. Applies `accurate` to the player's **instance**
    /// options (`KSPlayerLayer.options.isAccurateSeek`) — the flag `KSAVPlayer.seek`
    /// actually reads to compute the CMTime tolerance (KSAVPlayer.swift:564 /
    /// KSOptions.swift:143). Mutating the static `KSOptions.isAccurateSeek` here
    /// would be a no-op for tolerance, so the per-instance flag is set instead.
    /// `KSOptions` is a class, so this mutates the shared options object even though
    /// `KSPlayerLayer.options` is `private(set)` (the setter gates reassignment of
    /// the reference, not mutation of the pointed-to object).
    private func seekBy(_ delta: TimeInterval, accurate: Bool) {
        guard let layer = playerLayer else { return }
        let current = layer.player.currentPlaybackTime
        // Apply accuracy to the instance options the seek path reads; restore after.
        let previousAccurate = layer.options.isAccurateSeek
        defer { layer.options.isAccurateSeek = previousAccurate }
        layer.options.isAccurateSeek = accurate
        layer.seek(time: max(0, current + delta), autoPlay: layer.state.isPlaying) { _ in }
    }

    // MARK: - 6. Toast prompt — main-queue hop (`showPrompt @ 0x1014E4400`)

    /// Public toast entry point. Per the binary this is the thin "dispatch to the
    /// main queue with weak self" wrapper; the constraint build + fade-in + 5s
    /// auto-dismiss live in the separate `showPrompt_mainQueue(_:)` below. API
    /// Surface Preservation [v6.0]: the binary kept these as two distinct functions
    /// (0x1014E4400 hops to main, 0x1014E4660 builds the layout), so they are
    /// reconstructed as two calls — this wrapper must NOT inline the layout body.
    /// RE: `IOSVideoPlayerView_showPrompt @ 0x1014E4400` (0x260 = 608 bytes,
    /// "Dispatch to main queue with weak self").
    @objc func showPrompt(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showPrompt_mainQueue(text)
        }
    }

    // MARK: - 7. Toast prompt — main-queue body (`showPrompt_mainQueue_impl @ 0x1014E4660`)

    /// Main-queue body: lazily installs `promptLabel` with its layout constraints
    /// (50pt top, centerX, ≤0.8 width, ≥36pt height), fades it in, then schedules
    /// the 5s auto-dismiss. Kept separate from `showPrompt(_:)` so the queue hop and
    /// the layout/auto-dismiss work stay on their documented binary boundary.
    /// RE: `IOSVideoPlayerView_showPrompt_mainQueue_impl @ 0x1014E4660` (0x4BC =
    /// 1212 bytes, "Builds NSLayoutConstraints (50pt top, centerX, ≤0.8 width, ≥36pt
    /// height); 5s auto-dismiss").
    @objc func showPrompt_mainQueue(_ text: String) {
        if promptLabel.superview == nil {
            addSubview(promptLabel)
            NSLayoutConstraint.activate([
                promptLabel.topAnchor.constraint(equalTo: topAnchor, constant: 50),
                promptLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                promptLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
                promptLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            ])
        }
        promptLabel.text = "  \(text)  "
        UIView.animate(withDuration: 0.2) {
            self.promptLabel.alpha = 1
        }
        // Auto-dismiss after 5 seconds per RE.
        let work = DispatchWorkItem { [weak self] in self?.hidePrompt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
        customDelayItem = work
    }

    // MARK: - 8. Hide prompt (`hidePrompt_impl @ 0x1014E4C08`)

    /// Fade out prompt label (0.3s). RE: 0x148 = 328 bytes.
    @objc func hidePrompt() {
        UIView.animate(withDuration: 0.3) {
            self.promptLabel.alpha = 0
        }
    }

    // MARK: - 9. Open settings panel (`handleSettingsButtonTapped_impl @ 0x1014E5394`)

    /// Opens the 400pt sliding settings panel.
    /// RE: 0x10C = 268 bytes. Shared body with `handleUnifiedSettingsButtonTapped`.
    @objc func handleSettingsButtonTapped() {
        presentSettingsPanel()
    }

    // MARK: - 10. Aspect-fill cycling (`handleAspectFillButtonTapped_impl @ 0x1013C8AE4`)

    /// Cycles `aspectFit → aspectFill → scaleFill` with toast prompts.
    /// RE: 0x134 = 308 bytes (thunk at the cited address; impl elsewhere).
    @objc func handleAspectFillButtonTapped() {
        guard let layer = playerLayer?.player.view?.layer as? AVPlayerLayer else {
            // For non-AVPlayer paths the gravity lives on the MetalPlayView; fall
            // through to a toast that simply announces the cycle.
            showPrompt(NSLocalizedString("Aspect ratio cycle", comment: ""))
            return
        }
        switch layer.videoGravity {
        case .resizeAspect:
            layer.videoGravity = .resizeAspectFill
            showPrompt(NSLocalizedString("Aspect Fill", comment: ""))
        case .resizeAspectFill:
            layer.videoGravity = .resize
            showPrompt(NSLocalizedString("Scale Fill", comment: ""))
        default:
            layer.videoGravity = .resizeAspect
            showPrompt(NSLocalizedString("Aspect Fit", comment: ""))
        }
    }

    // MARK: - 11. Double-tap gesture (`doubleTapGestureAction_impl @ 0x1014E8384`)

    /// YouTube-style half-screen detection: left half = −10s, right half = +10s.
    /// RE: 0x160 = 352 bytes.
    @objc func doubleTapGestureAction(at location: CGPoint) {
        if location.x < bounds.width / 2 {
            handleJumpBack()
        } else {
            handleJumpForward()
        }
    }

    // MARK: - 14. Build fullscreen layout (`buildFullScreenLayout @ 0x1014DC1C4`)

    /// 3 horizontal UIStackViews pinned to `bottomBackground`. RE: 0x14B4 = 5300 bytes.
    /// Top row: definition / audio / subtitle buttons (20pt spacing, 30pt height).
    /// Middle row: video info container + nav stack (10pt spacing, 30pt height).
    /// Bottom row: previous / play / next + spacers (8pt spacing, 35pt height).
    ///
    /// §1.4 correction: the middle row's inter-element spacing is **10pt**, not 7pt
    /// — 7pt is the middle row's leading/trailing inset (set in the constraint block
    /// below), a distinct value the prior rev conflated with spacing.
    @objc func buildFullScreenLayout() {
        addSubview(bottomBackground)
        bottomBackground.translatesAutoresizingMaskIntoConstraints = false

        // Inter-element spacings set once with the §1.4-verified literals.
        let topRow = UIStackView(arrangedSubviews: [toolBar.definitionButton, audioMenuButton, subtitleMenuButton])
        topRow.axis = .horizontal
        topRow.spacing = 20    // 0x4034000000000000
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let midRow = UIStackView(arrangedSubviews: [videoInfoContainer])
        midRow.axis = .horizontal
        midRow.spacing = 10    // 0x4024000000000000 — §1.4: 10pt spacing (7pt is the inset, not spacing)
        midRow.distribution = .equalSpacing
        midRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomRow = UIStackView(arrangedSubviews: [UIView(), previousButton, toolBarPlayButton, nextButton, UIView()])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8  // 0x4020000000000000
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        [topRow, midRow, bottomRow].forEach { bottomBackground.addSubview($0) }

        // Icon names verified via Swift small-string ABI decode in
        // `buildFullScreenLayout @ 0x1014DC1C4`:
        //   audioMenuButton → "speaker.wave.2" (14 chars, marker 0xee)
        //   subtitleMenuButton → "captions.bubble" (15 chars, marker 0xef; NOT "captions.bubble.fill")
        for btn in [audioMenuButton, subtitleMenuButton] {
            let iconName = (btn === audioMenuButton) ? "speaker.wave.2" : "captions.bubble"
            let icon = UIImage(systemName: iconName, withConfiguration: toolBarPlayButtonConfig)
            btn.setImage(icon, for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = .clear
        }

        // Row spacings + midRow distribution are set once at construction above
        // with the §1.4-verified literals; the remaining layout constants (insets,
        // tops, heights) are applied here, all verified via decompile of `0x1014DC1C4`.
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: bottomBackground.topAnchor, constant: 8),       // 0x4020000000000000
            topRow.leadingAnchor.constraint(equalTo: bottomBackground.leadingAnchor, constant: 15), // 0x402E000000000000
            topRow.trailingAnchor.constraint(lessThanOrEqualTo: bottomBackground.trailingAnchor, constant: -15),
            topRow.heightAnchor.constraint(equalToConstant: 30),                                  // 0x403E000000000000

            midRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 14),              // 0x402C000000000000
            midRow.leadingAnchor.constraint(equalTo: bottomBackground.leadingAnchor, constant: 7), // 0x401C000000000000
            midRow.trailingAnchor.constraint(lessThanOrEqualTo: bottomBackground.trailingAnchor, constant: -7),
            midRow.heightAnchor.constraint(equalToConstant: 30),

            bottomRow.topAnchor.constraint(equalTo: midRow.bottomAnchor, constant: 16),           // 0x4030000000000000
            bottomRow.leadingAnchor.constraint(equalTo: bottomBackground.leadingAnchor, constant: 15),
            bottomRow.trailingAnchor.constraint(equalTo: bottomBackground.trailingAnchor, constant: -15),
            bottomRow.bottomAnchor.constraint(equalTo: bottomBackground.bottomAnchor, constant: -4), // 0xC010000000000000
            bottomRow.heightAnchor.constraint(equalToConstant: 35),                               // 0x4041800000000000

            // Audio/subtitle/definition buttons: 35×35pt per binary
            audioMenuButton.widthAnchor.constraint(equalToConstant: 35),
            audioMenuButton.heightAnchor.constraint(equalToConstant: 35),
            subtitleMenuButton.widthAnchor.constraint(equalToConstant: 35),
            subtitleMenuButton.heightAnchor.constraint(equalToConstant: 35),
            toolBar.definitionButton.widthAnchor.constraint(equalToConstant: 35),
            toolBar.definitionButton.heightAnchor.constraint(equalToConstant: 35),

            // Previous/play/next: 30×30pt per binary
            previousButton.widthAnchor.constraint(equalToConstant: 30),
            previousButton.heightAnchor.constraint(equalToConstant: 30),
            toolBarPlayButton.widthAnchor.constraint(equalToConstant: 30),
            toolBarPlayButton.heightAnchor.constraint(equalToConstant: 30),
            nextButton.widthAnchor.constraint(equalToConstant: 30),
            nextButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - 15. Status labels (`createStatusLabels_addToContainer @ 0x1014DD710`)

    /// Creates the 4 format-info labels (codec / resolution / fps / bitrate) and
    /// adds them to `videoInfoContainer`. RE: 0x130 = 304 bytes.
    @objc func createStatusLabels() {
        let make: () -> UILabel = {
            let l = UILabel()
            l.font = .systemFont(ofSize: 11, weight: .medium)
            l.textColor = .white
            return l
        }
        codecLabel = make()
        resolutionLabel = make()
        fpsLabel = make()
        bitrateLabel = make()
        for label in [codecLabel, resolutionLabel, fpsLabel, bitrateLabel].compactMap({ $0 }) {
            videoInfoContainer.addArrangedSubview(label)
        }
    }

    // MARK: - 16. Update format labels (`updateFormatInfoLabels @ 0x1014E8E38`)

    /// Reads a dict produced by `buildVideoTrackInfoDict` and sets text on each
    /// label (or hides if missing). RE: 0x3E4 = 996 bytes.
    @objc func updateFormatInfoLabels(_ info: [String: String]) {
        update(codecLabel, withKey: "Codec Format", from: info)
        update(resolutionLabel, withKey: "Resolution", from: info)
        update(fpsLabel, withKey: "Frame Rate", from: info)
        update(bitrateLabel, withKey: "Bitrate", from: info)
    }

    private func update(_ label: UILabel?, withKey key: String, from info: [String: String]) {
        if let value = info[key], !value.isEmpty {
            label?.text = value
            label?.isHidden = false
        } else {
            label?.isHidden = true
        }
    }

    // MARK: - 17. Set overlay alpha (`setOverlayAlpha @ 0x1014D87BC`)

    /// Apply alpha to 12+ overlay elements at once. RE: 0x20C = 524 bytes.
    @objc func setOverlayAlpha(_ alpha: CGFloat) {
        for view in [topLeftBackground, topRightBackground, bottomBackground, leftBackgroundView] {
            view.alpha = alpha
        }
        for view in [topStatusBar, videoInfoContainer as UIView?, screenshotPreviewView, bottomSlimProgressView] {
            view?.alpha = alpha
        }
        for view in [currentItemTitleLabel, displayTitleLabel, networkSpeedLabel] {
            view?.alpha = alpha
        }
        for view: UIView? in [networkStatusImageView, batteryImageView] {
            view?.alpha = alpha
        }
    }

    // MARK: - 22. Present settings panel (`presentSettingsPanel @ 0x1014FF680`)

    /// Adds settings as a 400pt-wide right-edge panel and slides in via spring.
    /// RE: 0x3B4 = 948 bytes. Spring duration 0.3, damping 0.8 (constants
    /// preserved from previous-rev — animation parameters unverified at
    /// `0x1014FF680`).
    // Animation constants verified via decompile of
    // `presentSettingsPanel @ 0x1014FF680`:
    //   width  = 0x4079000000000000 = 400.0pt
    //   tx     = 0x407A400000000000 = 420.0pt (entry translation)
    //   damping= 0x3FE999999999999A = 0.8 (read from DAT_102E8D1C8)
    //   duration = 0x3FD3333333333333 = 0.3s
    @objc func presentSettingsPanel() {
        let v = settingsView
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor),
            v.bottomAnchor.constraint(equalTo: bottomAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.widthAnchor.constraint(equalToConstant: 400),
        ])
        layoutIfNeeded()
        v.transform = CGAffineTransform(translationX: 420, y: 0)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [], animations: {
            v.transform = .identity
        })
        setOverlayAlpha(0)
    }

    // MARK: - 23. Dismiss settings panel (`dismissSettingsPanel @ 0x1014FFB14`)

    /// Slide-out `+400pt right` + `removeFromSuperview`.
    /// Verified via decompile of `dismissSettingsPanel @ 0x1014FFB14`:
    /// `animateWithDuration:0x3FD3333333333333` (= 0.3s); animation block
    /// applies `transform.tx = 0x4079000000000000` (= 400.0pt);
    /// completion calls `removeFromSuperview`.
    @objc func dismissSettingsPanel() {
        guard let v = _settingsView else { return }
        UIView.animate(withDuration: 0.3, animations: {
            v.transform = CGAffineTransform(translationX: 400, y: 0)
        }, completion: { _ in
            v.removeFromSuperview()
            self.setOverlayAlpha(1)
        })
    }

    // MARK: - 25. Settings dismiss callback (`settingsView_onDismiss @ 0x1014E54A0`)

    /// Loads weak self, dismisses, restores overlay. RE: 0x84 = 132 bytes.
    @objc func settingsView_onDismiss() {
        dismissSettingsPanel()
    }

    // MARK: - 26. Audio track menu (`buildAudioTrackMenu @ 0x1014E5524`)

    /// Builds a single-selection `UIMenu` of audio tracks.
    /// RE: `buildAudioTrackMenu @ 0x1014E5524` (0x524 = 1316 bytes).
    /// §13.1: tracks via `player.tracks(mediaType: .audio)`, one `UIAction`
    /// per track (title from `CustomStringConvertible`, state `.on` if the
    /// track is enabled), wrapped in a `UIMenu` carrying the `.singleSelection`
    /// option (iOS 17+), assigned to `audioMenuButton` with
    /// `showsMenuAsPrimaryAction = true`. Handler is `audioTrackSelected`.
    @objc func buildAudioTrackMenu() {
        guard let player = playerLayer?.player else { return }
        let tracks = player.tracks(mediaType: .audio)
        let actions: [UIAction] = tracks.map { track in
            UIAction(title: track.description,
                     state: track.isEnabled ? .on : .off) { [weak self] _ in
                self?.audioTrackSelected(track)
            }
        }
        // §13.1 step 3: `.singleSelection` makes the menu behave as a radio
        // group. The option is iOS-17 / tvOS-17 only — platform-gated because
        // the iOS/tvOS/macOS constraint forbids API that does not exist on a
        // target's earlier OS floor. macOS gets no UIMenu here (UIKit-only file).
        let menu: UIMenu
        if #available(iOS 17.0, tvOS 17.0, *) {
            menu = UIMenu(title: NSLocalizedString("Audio", comment: ""),
                          options: .singleSelection,
                          children: actions)
        } else {
            menu = UIMenu(title: NSLocalizedString("Audio", comment: ""),
                          children: actions)
        }
        audioMenuButton.menu = menu
        audioMenuButton.showsMenuAsPrimaryAction = true
    }

    // MARK: - 27. Subtitle menu (`handleSubtitleMenuSetup @ 0x1014E5000`)

    /// Guards if menu already exists; builds dual-subtitle sections.
    /// RE: `handleSubtitleMenuSetup @ 0x1014E5000` (0x230 = 560 bytes).
    /// §13.2: (1) returns early if the menu already exists; (2) builds the
    /// First/Second sections via `buildSubtitleMenuSections`; (4) appends a
    /// "None" action that deselects all subtitles and a "Local Subtitle" file
    /// picker; (5) wraps everything in a parent "Subtitles" `UIMenu` carrying
    /// `.singleSelection` (iOS 17+).
    @objc func handleSubtitleMenuSetup() {
        guard subtitleMenuButton.menu == nil else { return }
        let sections = buildSubtitleMenuSections()
        // §13.2 step 4: "None" deselects ALL subtitles (clears the primary slot;
        // the play-app dual-subtitle compositor owns the secondary slot).
        let none = UIAction(title: NSLocalizedString("None", comment: ""),
                            state: srtControl.selectedSubtitleInfo == nil ? .on : .off) { [weak self] _ in
            self?.srtControl.selectedSubtitleInfo = nil
        }
        let local = UIAction(title: NSLocalizedString("Local Subtitle", comment: ""), image: UIImage(systemName: "doc")) { [weak self] _ in
            self?.openLocalSubtitlePicker()
        }
        // §13.2 step 5: parent menu uses `.singleSelection` (iOS-17 / tvOS-17
        // only — platform-gated for the same reason as the audio menu above).
        let inlineActions: UIMenuElement = UIMenu(options: .displayInline, children: [none, local])
        let children: [UIMenuElement] = sections + [inlineActions]
        let menu: UIMenu
        if #available(iOS 17.0, tvOS 17.0, *) {
            menu = UIMenu(title: NSLocalizedString("Subtitles", comment: ""),
                          options: .singleSelection,
                          children: children)
        } else {
            menu = UIMenu(title: NSLocalizedString("Subtitles", comment: ""),
                          children: children)
        }
        subtitleMenuButton.menu = menu
        subtitleMenuButton.showsMenuAsPrimaryAction = true
    }

    // MARK: - 28. Subtitle sections (`buildSubtitleMenuSections @ 0x1014E5BF4`)

    /// "First Subtitle" + "Second Subtitle" sections. Dual-subtitle support.
    /// RE: `buildSubtitleMenuSections @ 0x1014E5BF4` (0x8EC = 2284 bytes).
    ///
    /// §13.2 step 3 — the verified body filters the subtitle-info list by
    /// concrete class: `FFmpegAssetTrack` elements are container-**embedded**
    /// subtitle streams (an `FFmpegAssetTrack` is surfaced as a `SubtitleInfo`
    /// via `extension FFmpegAssetTrack: SubtitleInfo` in EmbedDataSource.swift),
    /// while `URLSubtitleInfo` elements are **external** files / remote search
    /// results. The two groups are placed in their own inline ("Embedded" /
    /// "External") sub-sections inside each of the First/Second parent sections
    /// so the user can tell a baked-in track from a sidecar one. The "Second
    /// Subtitle" actions drive the secondary slot (`isSecondary = true`); the
    /// play-app dual-subtitle compositor owns the actual secondary-track render,
    /// so here the action records the chosen info on the compositor hook.
    @objc func buildSubtitleMenuSections() -> [UIMenuElement] {
        let infos = srtControl.subtitleInfos
        guard !infos.isEmpty else { return [] }

        // §13.2 step 3 class split: embedded (FFmpegAssetTrack) vs external
        // (URLSubtitleInfo). Anything that is neither (e.g. EmptySubtitleInfo)
        // is treated as external so it is never silently dropped.
        let embedded = infos.filter { $0 is FFmpegAssetTrack }
        let external = infos.filter { !($0 is FFmpegAssetTrack) }

        func makeSection(isSecondary: Bool) -> UIMenu {
            let selected = srtControl.selectedSubtitleInfo
            let action: (any SubtitleInfo) -> UIAction = { [weak self] info in
                UIAction(title: info.name,
                         state: (!isSecondary && selected?.subtitleID == info.subtitleID) ? .on : .off) { _ in
                    self?.subtitleSelected(info, isSecondary: isSecondary)
                }
            }
            var groups: [UIMenuElement] = []
            if !embedded.isEmpty {
                groups.append(UIMenu(title: NSLocalizedString("Embedded", comment: ""),
                                     options: .displayInline,
                                     children: embedded.map(action)))
            }
            if !external.isEmpty {
                groups.append(UIMenu(title: NSLocalizedString("External", comment: ""),
                                     options: .displayInline,
                                     children: external.map(action)))
            }
            let title = isSecondary
                ? NSLocalizedString("Second Subtitle", comment: "")
                : NSLocalizedString("First Subtitle", comment: "")
            return UIMenu(title: title, children: groups)
        }

        return [makeSection(isSecondary: false), makeSection(isSecondary: true)]
    }

    /// Routes a subtitle selection to the primary or secondary slot.
    /// Primary (`isSecondary == false`) drives `srtControl.selectedSubtitleInfo`
    /// directly (matching the "None" action and the rest of this file).
    /// Secondary (`isSecondary == true`) goes through the engine's dual-subtitle
    /// API `KSPlayerLayer.setSelectedSubtitleInfo(_:isSecondary:)`, which stores
    /// it on the SubtitleModel's `selectedSecondSubtitleInfo` — the slot the
    /// play-app dual-subtitle compositor reads. RE: extracted from the §13.2
    /// `buildSubtitleMenuSections` per-action closures (API Surface Preservation
    /// — the embedded/external actions both funnel through one selection point).
    private func subtitleSelected(_ info: any SubtitleInfo, isSecondary: Bool) {
        if isSecondary {
            playerLayer?.setSelectedSubtitleInfo(info, isSecondary: true)
        } else {
            srtControl.selectedSubtitleInfo = info
        }
    }

    private func openLocalSubtitlePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.text, .plainText, .data])
        viewController?.present(picker, animated: true)
    }

    // MARK: - 29. Audio track selected (`audioTrackSelected_handler @ 0x1001C2AB4`)

    /// Thin closure forwarder. RE: 0x14 = 20 bytes.
    @objc func audioTrackSelected(_ track: MediaPlayerTrack) {
        playerLayer?.player.select(track: track)
        selectedAudioTrack = track
    }

    // MARK: - 30. Build video track info dict
    //
    // `buildVideoTrackInfoDict` was claimed at `0x1013CCAB0` in the previous rev,
    // but that address resolves to a 32-byte stub. The behavior — populating a
    // dict of "Codec Format" / "Resolution" / "Frame Rate" / "Bitrate" / "Color
    // Depth" — is reproduced here so callers can fill `updateFormatInfoLabels`.

    @objc func buildVideoTrackInfoDict() -> [String: String] {
        guard let track = playerLayer?.player.tracks(mediaType: .video).first else { return [:] }
        var dict: [String: String] = [:]
        dict["Codec Format"] = track.codecType.string
        if track.naturalSize.width > 0 {
            dict["Resolution"] = "\(Int(track.naturalSize.width))x\(Int(track.naturalSize.height))"
        }
        if track.nominalFrameRate > 0 {
            dict["Frame Rate"] = String(format: "%.2fFPS", track.nominalFrameRate)
        }
        if track.bitRate > 0 {
            dict["Bitrate"] = "\(track.bitRate >> 10)Kbps"
        }
        return dict
    }

    // MARK: - 32. Create transition animator (`createTransitionAnimator @ 0x1014ECE78`)

    /// Creates `PlayerTransitionAnimator` for fullscreen transitions.
    /// RE: 0x114 = 276 bytes.
    @objc func createTransitionAnimator(isDismiss: Bool) -> PlayerTransitionAnimator? {
        // The container is the PRE-fullscreen superview captured in
        // `enterFullScreen` (`originalSuperView` ivar), not the live `superview`
        // (which is the fullscreen VC's view mid-transition). Fall back to the
        // live superview only if the snapshot is unavailable.
        guard let container = originalSuperView ?? superview,
              let animationView = playerLayer?.player.view else {
            return nil
        }
        return PlayerTransitionAnimator(containerView: container,
                                        animationView: animationView,
                                        isDismiss: isDismiss)
    }

    // MARK: - Helper: update play/pause button icon

    private func updatePlayPauseButtonIcon() {
        let isPlaying = playerLayer?.state.isPlaying ?? false
        let name = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: name, withConfiguration: playButtonConfig), for: .normal)
        toolBarPlayButton.setImage(UIImage(systemName: name, withConfiguration: toolBarPlayButtonConfig), for: .normal)
    }
}

#endif
