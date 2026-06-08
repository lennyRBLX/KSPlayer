//
//  UIKitExtend.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
//  Cluster note (KSPlayerUIViewHelpers): the UIComponents reversal cluster map
//  designates this file as the home for four ObjC-rooted UIKit helper types —
//  `KSSlider`, `ProgressView`, `LayerContainerView`, and `AudioPlayerView`.
//  `KSSlider` lives here (below). The other three were reconstructed by prior
//  runs co-located with the types they are wired into, and are intentionally
//  NOT duplicated here (a second declaration would be a redeclaration error and,
//  for `ProgressView`, would break its deliberate `private` mangling). Their
//  reconstructed homes — recorded here for cluster traceability:
//
//    • ProgressView        RE: 0x1014D6F74 — KSPlayer's own brightness/volume
//        progress-bar widget (6 stored fields, conforms BrightnessVolumeViewProtocol).
//        Reconstructed in `Video/BrightnessVolume.swift` as a `private final class`,
//        co-located with its sole owner `BrightnessVolume.progressView` and its
//        sibling `SystemView` (both share the `P33_46D5…AB2` private discriminator).
//        Keeping it private requires same-file co-location, so it stays there.
//        (init(frame:) 0x1014D7484, init(coder:) 0x1014D6D58, alloc/init 0x101382678,
//         move(to:)/addToSuperview 0x1014D708C, setProgress/update 0x1014D6F94,
//         MainActor guard 0x1014D6E44.)
//
//    • LayerContainerView  RE: 0x1013E5E0C — gradient-overlay host view
//        (0 stored fields; +layerClass → CAGradientLayer). Reconstructed in
//        `Core/Utility.swift`, where it also exposes the `gradientLayer` accessor
//        that VideoPlayerView's top/bottom mask overlays depend on.
//        (+layerClass 0x1013E5B88, init(frame:) 0x1004323B4, init(coder:) 0x1013E5F24.)
//
//    • AudioPlayerView     RE: 0x1013CAF2C — audio-only `PlayerView` subclass
//        (0 stored fields). Reconstructed in `Audio/AudioPlayerView.swift`,
//        beside the rest of the audio-playback UI. (init(frame:) 0x1013CA8E4.)
//
//  MenuController (RE: 0x1014ED910) is likewise NOT here — per the cluster map it
//  belongs to `Video/KSMenu.swift`, which owns it.
//
#if canImport(UIKit)
import UIKit

// `_TtC8KSPlayer8KSSlider` — 5 stored properties per `.reversal/types.json`:
// `tapGesture`, `panGesture`, `delegate`, `trackHeigt`, `isPlayable`.
// `trackHeigt` is a binary typo (correct: `trackHeight`); per CLAUDE.md
// typo-fix rule the Swift port renames it.
/// RE: 0x1013E55FC (KSSlider class metadata, 1.3.15)
// CMa correction (v5.3 R2, G-R2-3): supersedes stale 0x1012D2EB4 (mid-body of
// FUN_10129d8e0); 0x1013E55FC is the verified §18.0 anchor — decompile shows
// `_objc_opt_self(&_TtC8KSPlayer8KSSlider)`.
public class KSSlider: UXSlider {
    private var tapGesture: UITapGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!
    weak var delegate: KSSliderDelegate?
    public var trackHeight = CGFloat(2)
    public var isPlayable = false
    override public init(frame: CGRect) {
        super.init(frame: frame)
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(actionTapGesture(sender:)))
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(actionPanGesture(sender:)))
        addGestureRecognizer(tapGesture)
        addGestureRecognizer(panGesture)
        addTarget(self, action: #selector(progressSliderTouchBegan(_:)), for: .touchDown)
        addTarget(self, action: #selector(progressSliderValueChanged(_:)), for: .valueChanged)
        addTarget(self, action: #selector(progressSliderTouchEnded(_:)), for: [.touchUpInside, .touchCancel, .touchUpOutside, .primaryActionTriggered])
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func trackRect(forBounds bounds: CGRect) -> CGRect {
        var customBounds = super.trackRect(forBounds: bounds)
        customBounds.origin.y -= trackHeight / 2
        customBounds.size.height = trackHeight
        return customBounds
    }

    override open func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let rect = super.thumbRect(forBounds: bounds, trackRect: rect, value: value)
        return rect.insetBy(dx: -20, dy: -20)
    }

    // MARK: - handle UI slider actions

    /// RE: 0x1013E4DA8 (progressSliderTouchBegan_impl, 276 bytes, 1.3.15)
    @objc private func progressSliderTouchBegan(_ sender: KSSlider) {
        guard isPlayable else { return }
        tapGesture.isEnabled = false
        panGesture.isEnabled = false
        // Removed dead `value = value` self-assignment — a Ghidra decompile
        // artifact (no-op), not real behavior. The doc (UIComponents.md §5.1)
        // mandates only: disable tap/pan gestures + emit `.touchDown`. UISlider
        // already clamps `value` to [minimumValue, maximumValue] on set, so no
        // re-clamp is warranted; static recovery of the original op was
        // attempted (Ghidra MCP offline, no cached decompile) and could not
        // confirm any clamp, so none is fabricated.
        delegate?.slider(value: Double(sender.value), event: .touchDown)
    }

    /// RE: 0x1013E4ECC (progressSliderValueChanged_impl, 172 bytes, 1.3.15)
    @objc private func progressSliderValueChanged(_ sender: KSSlider) {
        guard isPlayable else { return }
        delegate?.slider(value: Double(sender.value), event: .valueChanged)
    }

    @objc private func progressSliderTouchEnded(_ sender: KSSlider) {
        guard isPlayable else { return }
        tapGesture.isEnabled = true
        panGesture.isEnabled = true
        delegate?.slider(value: Double(sender.value), event: .touchUpInside)
    }

    /// RE: 0x1013E515C (actionTapGesture_impl, 288 bytes, 1.3.15)
    @objc private func actionTapGesture(sender: UITapGestureRecognizer) {
        //        guard isPlayable else {
        //            return
        //        }
        let touchPoint = sender.location(in: self)
        let value = (maximumValue - minimumValue) * Float(touchPoint.x / frame.size.width)
        self.value = value
        delegate?.slider(value: Double(value), event: .valueChanged)
        delegate?.slider(value: Double(value), event: .touchUpInside)
    }

    /// RE: 0x1013E528C (actionPanGesture_impl, 380 bytes, 1.3.15)
    @objc private func actionPanGesture(sender: UIPanGestureRecognizer) {
        //        guard isPlayable else {
        //            return
        //        }
        let touchPoint = sender.location(in: self)
        let value = (maximumValue - minimumValue) * Float(touchPoint.x / frame.size.width)
        self.value = value
        if sender.state == .began {
            delegate?.slider(value: Double(value), event: .touchDown)
        } else if sender.state == .ended {
            delegate?.slider(value: Double(value), event: .touchUpInside)
        } else {
            delegate?.slider(value: Double(value), event: .valueChanged)
        }
    }
}

#if os(tvOS)
public class UXSlider: UIProgressView {
    @IBInspectable public var value: Float {
        get {
            progress * maximumValue
        }
        set {
            progress = newValue / maximumValue
        }
    }

    @IBInspectable public var maximumValue: Float = 1 {
        didSet {
            refresh()
        }
    }

    @IBInspectable public var minimumValue: Float = 0 {
        didSet {
            refresh()
        }
    }

    open var minimumTrackTintColor: UIColor? {
        get {
            progressTintColor
        }
        set {
            progressTintColor = newValue
        }
    }

    open var maximumTrackTintColor: UIColor? {
        get {
            trackTintColor
        }
        set {
            trackTintColor = newValue
        }
    }

    open func setThumbImage(_: UIImage?, for _: UIControl.State) {}
    open func addTarget(_: Any?, action _: Selector, for _: UIControl.Event) {}

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    // MARK: - private functions

    private func setup() {
        refresh()
    }

    private func refresh() {}
    open func trackRect(forBounds bounds: CGRect) -> CGRect {
        bounds
    }

    open func thumbRect(forBounds bounds: CGRect, trackRect _: CGRect, value _: Float) -> CGRect {
        bounds
    }
}
#else
public typealias UXSlider = UISlider
#endif

public typealias UIViewContentMode = UIView.ContentMode
extension UIButton {
    func fillImage() {
        contentMode = .scaleAspectFill
        contentHorizontalAlignment = .fill
        contentVerticalAlignment = .fill
    }

    var titleFont: UIFont? {
        get {
            titleLabel?.font
        }
        set {
            titleLabel?.font = newValue
        }
    }

    var title: String? {
        get {
            titleLabel?.text
        }
        set {
            titleLabel?.text = newValue
        }
    }
}

extension UIView {
    func image() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, 0.0)
        defer { UIGraphicsEndImageContext() }
        if let context = UIGraphicsGetCurrentContext() {
            layer.render(in: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            return image
        }
        return nil
    }

    public func centerRotate(byDegrees: Double) {
        transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * byDegrees / 180.0))
    }
}
#endif
