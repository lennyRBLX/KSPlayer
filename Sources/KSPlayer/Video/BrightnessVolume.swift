//
//  BrightnessVolume.swift
//  KSPlayer
//
//  Created by kintan on 2017/11/3.
//
#if canImport(UIKit)
import UIKit

/// Singleton HUD controller that observes system brightness (KVO on
/// `UIScreen.brightness`) and volume (`AVSystemController` notification) and
/// drives a `BrightnessVolumeViewProtocol` overlay.
/// RE: 0x1014D559C (BrightnessVolume class metadata / `_objc_opt_self` thunk, 1.3.15)
@MainActor
open class BrightnessVolume {
    private var brightnessObservation: NSKeyValueObservation?
    /// RE: 0x1013826AC (BrightnessVolume.shared getter — lazy alloc + init, 1.3.15)
    public static let shared = BrightnessVolume()
    public var progressView: BrightnessVolumeViewProtocol & UIView = ProgressView()
    /// RE: 0x1014D46D4 (BrightnessVolume.init — observeScreenAndVolume, 1.3.15)
    init() {
        // tvOS/xrOS expose no per-display brightness slider, so the KVO probe is gated out there.
        #if !os(tvOS) && !os(xrOS)
        // RE: 0x1014D4BBC (BrightnessVolume KVO callback — brightnessChanged, 1.3.15)
        brightnessObservation = UIScreen.main.observe(\.brightness, options: .new) { [weak self] _, change in
            guard KSOptions.enableBrightnessGestures else { return }
            if let self, let value = change.newValue {
                self.appearView()
                self.progressView.setProgress(Float(value), type: 0)
            }
        }
        #endif
        let name = NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification")
        NotificationCenter.default.addObserver(self, selector: #selector(volumeIsChanged(notification:)), name: name, object: nil)
        progressView.alpha = 0.0
    }

    public func move(to view: UIView) {
        progressView.move(to: view)
    }

    /// Volume-change handler. The `AVSystemController` notification is delivered off
    /// the main actor; because this method is `@objc` on a `@MainActor` class, the
    /// runtime marshals it to the main actor automatically — this is the implicit
    /// equivalent of the binary's discrete MainActor-hop trampoline.
    /// RE: 0x1014D4C3C (BrightnessVolume.volumeIsChanged impl, 1.3.15)
    /// (MainActor hop trampoline: 0x1014D7B80)
    @objc private func volumeIsChanged(notification: NSNotification) {
        guard KSOptions.enableVolumeGestures else { return }
        if let changeReason = notification.userInfo?["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String, changeReason == "ExplicitVolumeChange" {
            if let volume = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? CGFloat {
                appearView()
                progressView.setProgress(Float(volume), type: 1)
            }
        }
    }

    /// Shows the overlay if currently hidden, then schedules the fade-out after a
    /// 3.0s delay. The binary expresses the delay as a Swift Concurrency
    /// continuation (`Task { try? await Task.sleep(...); disAppearView() }`, the
    /// `sleepContinuation` slot); the GCD `asyncAfter` form here is the established
    /// no-op-equivalent collapse of that async plumbing — same 3.0s timed hop to
    /// `disAppearView`.
    /// RE: 0x1014D5038 (BrightnessVolume.appearView — showSystemViewIfHidden, 1.3.15)
    /// (fade-out delay continuation: 0x1014D5204)
    private func appearView() {
        if progressView.alpha == 0.0 {
            progressView.alpha = 1.0
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) { [weak self] () in
                self?.disAppearView()
            }
        }
    }

    /// Fades the overlay back out over 0.8s if it is still fully shown.
    /// RE: 0x1014D5288 (BrightnessVolume.disAppearView — fadeOutSystemView, 1.3.15)
    /// (immediate-hide path: 0x1014D5408)
    private func disAppearView() {
        if progressView.alpha == 1.0 {
            UIView.animate(withDuration: 0.8) { [weak self] () in
                self?.progressView.alpha = 0.0
            }
        }
    }

    /// RE: 0x1014D5504 (BrightnessVolume.deinit, 1.3.15) (deallocating: 0x1014D554C)
    deinit {
        brightnessObservation?.invalidate()
    }
}

/// Conformance contract for the overlay widget behind `BrightnessVolume.progressView`
/// (binary field type `__C.UIView & KSPlayer.BrightnessVolumeViewProtocol`).
/// Both `SystemView` and `ProgressView` conform. `type` follows the binary's
/// `updateForVolumeOrBrightness` convention: `param_2 == 0` is brightness, else volume.
/// RE: 0x1014D559C (BrightnessVolumeViewProtocol — referenced by progressView field, 1.3.15)
public protocol BrightnessVolumeViewProtocol {
    // type: 0 brightness type: 1 volume
    func setProgress(_ progress: Float, type: UInt)
    func move(to view: UIView)
}

/// Frosted iOS-style volume/brightness HUD card (segmented level meter).
/// Private-mangled in the binary
/// (`_TtC8KSPlayerP33_46D5B6E7ED60BB03AC9A474A87A63AB210SystemView`), sharing the
/// `P33_46D5…AB2` discriminator with `ProgressView` — hence kept `private` here.
/// RE: 0x1014D64AC (SystemView class metadata / `_objc_opt_self` thunk, 1.3.15)
private final class SystemView: UIVisualEffectView {
    private let stackView = UIStackView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    /// RE: 0x1014D6B7C (SystemView lazy image accessor — brightnessImage, 1.3.15)
    private lazy var brightnessImage = UIImage(systemName: "sun.max")
    // SF symbol statically recovered from the packed literal at 0x10333d990
    // ("speaker.wave.3.fill", 19 chars) — bridge call's base pointer 0x10333d970
    // is the adjacent "$_volumeOffImage" field-name string; the symbol lives +0x20.
    /// RE: 0x1014D55BC (SystemView lazy image accessor — volumeImage, 1.3.15)
    private lazy var volumeImage = UIImage(systemName: "speaker.wave.3.fill")
    /// RE: 0x1014D73AC (SystemView.init — initWithEffect + field init, 1.3.15)
    private convenience init() {
        self.init(effect: UIBlurEffect(style: .extraLight))
        clipsToBounds = true
        cornerRadius = 10
        imageView.image = brightnessImage
        contentView.addSubview(imageView)
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = UIColor(red: 0.25, green: 0.22, blue: 0.21, alpha: 1)
        titleLabel.textAlignment = .center
        // Binary-faithful initial label: small-string 0xa6bae5aebae4 = "亮度" (CN "brightness").
        // setProgress(_:type:) immediately overwrites it with NSLocalizedString("brightness"),
        // so this hard-coded literal is only the pre-first-update placeholder. Kept verbatim.
        // RE: 0x1014D5668 (SystemView setup — titleLabel default text, 1.3.15)
        titleLabel.text = "亮度"
        contentView.addSubview(titleLabel)
        let longView = UIView()
        longView.backgroundColor = titleLabel.textColor
        contentView.addSubview(longView)
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.axis = .horizontal
        stackView.spacing = 1
        longView.addSubview(stackView)
        for _ in 0 ..< 16 {
            let tipView = UIView()
            tipView.backgroundColor = .white
            stackView.addArrangedSubview(tipView)
            tipView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tipView.heightAnchor.constraint(equalTo: stackView.heightAnchor),
            ])
        }
        translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        longView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 79),
            imageView.heightAnchor.constraint(equalToConstant: 76),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.widthAnchor.constraint(equalTo: widthAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 30),
            longView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            longView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            longView.heightAnchor.constraint(equalToConstant: 7),
            longView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stackView.leadingAnchor.constraint(equalTo: longView.leadingAnchor, constant: 1),
            stackView.trailingAnchor.constraint(equalTo: longView.trailingAnchor, constant: -1),
            stackView.topAnchor.constraint(equalTo: longView.topAnchor, constant: 1),
            stackView.bottomAnchor.constraint(equalTo: longView.bottomAnchor, constant: -1),
        ])
    }

    /// Storyboard/NIB inflation path. Unlike the sibling `ProgressView` (whose coder
    /// init traps), the binary emits a real coder init for `SystemView`: it default-
    /// initializes the three subview fields + the two lazy-image storages and forwards
    /// to `super.init(coder:)` without running the programmatic layout. Swift's inline
    /// property initializers reproduce the field defaults, so the body just forwards.
    /// RE: 0x1014D6340 (SystemView.init(coder:) impl — field init + super, 1.3.15)
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

extension SystemView: BrightnessVolumeViewProtocol {
    /// RE: 0x1014D64CC (SystemView.setProgress — updateForVolumeOrBrightness, 1.3.15)
    /// Segmented level meter (verified via decompile, UIComponents.md §18.20 L3173-3175):
    /// each arranged subview lights (`alpha = 1.0`) iff its index is strictly less than
    /// `round(progress * subviewCount)`, else fades out (`alpha = 0.0`). The lit-segment
    /// count is the *rounded* (not truncated) scaled level, and the index test is
    /// exclusive — so a value whose scaled level rounds up (e.g. 0.5 over 16 segments →
    /// `round(8.0)=8` → 8 lit) matches the binary exactly rather than over-lighting.
    public func setProgress(_ progress: Float, type: UInt) {
        if type == 0 {
            imageView.image = brightnessImage
            titleLabel.text = NSLocalizedString("brightness", comment: "")
        } else {
            imageView.image = volumeImage
            titleLabel.text = NSLocalizedString("volume", comment: "")
        }
        let subviews = stackView.arrangedSubviews
        let litCount = Int((progress * Float(subviews.count)).rounded())
        for i in 0 ..< subviews.count {
            subviews[i].alpha = i < litCount ? 1.0 : 0.0
        }
    }

    /// RE: 0x1014D6864 (SystemView.move(to:) — addToSuperviewWithConstraints, 1.3.15)
    public func move(to view: UIView) {
        if superview != view {
            removeFromSuperview()
            view.addSubview(self)
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: view.centerXAnchor),
                centerYAnchor.constraint(equalTo: view.centerYAnchor),
                heightAnchor.constraint(equalToConstant: 155),
                widthAnchor.constraint(equalToConstant: 155),
            ])
        }
    }
}

// KSPlayer's own brightness/volume progress-bar widget (the concrete type
// behind `BrightnessVolume.progressView`). Private-mangled in the binary
// (`_TtC8KSPlayerP33_46D5B6E7ED60BB03AC9A474A87A63AB212ProgressView`),
// sharing the `P33_46D5…AB2` discriminator with `SystemView` — hence kept
// `private` here. Distinct from SwiftUI's `ProgressView`.
/// RE: 0x1014D6F74 (ProgressView class metadata / type accessor, 1.3.15)
private final class ProgressView: UIView {
    private lazy var brightnessImage = UIImage(systemName: "sun.max")
    private lazy var volumeImage = UIImage(systemName: "speaker.fill")
    private lazy var brightnessOffImage = UIImage(systemName: "sun.min")
    private lazy var volumeOffImage = UIImage(systemName: "speaker.slash.fill")
    private let progressView = UIProgressView()
    private let imageView = UIImageView()

    /// RE: 0x1014D7484 (ProgressView.init(frame:) designated init, 1.3.15)
    /// (alloc/init thunk: 0x101382678)
    override init(frame _: CGRect) {
        super.init(frame: .zero)
        addSubview(progressView)
        addSubview(imageView)
        progressView.progressTintColor = UIColor.white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.5)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.centerRotate(byDegrees: -90)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: 115),
            progressView.heightAnchor.constraint(equalToConstant: 2),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.topAnchor.constraint(equalTo: topAnchor, constant: 57),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// RE: 0x1014D6D58 (ProgressView.init?(coder:) — unsupported, fatalError, 1.3.15)
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ProgressView: BrightnessVolumeViewProtocol {
    /// RE: 0x1014D6F94 (ProgressView.updateForVolumeOrBrightness — updates bar + on/off icon, 1.3.15)
    /// (MainActor assertion wrapper: 0x1014D6E44)
    func setProgress(_ progress: Float, type: UInt) {
        progressView.setProgress(progress, animated: false)
        if progress == 0 {
            imageView.image = type == 0 ? brightnessOffImage : volumeOffImage
        } else {
            imageView.image = type == 0 ? brightnessImage : volumeImage
        }
    }

    /// RE: 0x1014D708C (ProgressView.addToSuperviewWithConstraints — pins into a superview, 1.3.15)
    func move(to view: UIView) {
        if superview != view {
            removeFromSuperview()
            view.addSubview(self)
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                trailingAnchor.constraint(equalTo: view.safeTrailingAnchor, constant: -10),
                centerYAnchor.constraint(equalTo: view.centerYAnchor),
                heightAnchor.constraint(equalToConstant: 150),
                widthAnchor.constraint(equalToConstant: 24),
            ])
        }
    }
}
#endif
