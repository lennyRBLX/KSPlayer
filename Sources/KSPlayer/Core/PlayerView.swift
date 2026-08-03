//
//  PlayerView.swift
//  VoiceNote
//
//  Created by kintan on 2018/8/16.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import AVFoundation

public enum PlayerButtonType: Int {
    case play = 101
    case pause
    case back
    case srt
    case landscape
    case replay
    case lock
    case rate
    case definition
    case pictureInPicture
    case audioSwitch
    case videoSwitch
}

public protocol PlayerControllerDelegate: AnyObject {
    func playerController(state: KSPlayerState)
    func playerController(currentTime: TimeInterval, totalTime: TimeInterval)
    func playerController(finish error: Error?)
    func playerController(maskShow: Bool)
    func playerController(action: PlayerButtonType)
    // `bufferedCount: 0` indicates first time loading
    func playerController(bufferedCount: Int, consumeTime: TimeInterval)
    func playerController(seek: TimeInterval)
}

open class PlayerView: UIView, KSPlayerLayerDelegate, @preconcurrency KSSliderDelegate {
    public typealias ControllerDelegate = PlayerControllerDelegate
    // s100 — Forward's observer tears down the PREVIOUS layer; it does not wire the new one.
    // Body 0x101a01924 (52 instr): store the new value, then `cbz` on the old and, when non-nil,
    // weak-assign nil into its `delegate` (0x101a0199c, with `str xzr,[x19,#0x8]` clearing the
    // existential's witness word first) and dispatch KSPlayerLayer metadata +0x2d0, which
    // `vtable_walk KSPlayerLayer --metadata-offset 0x2d0` resolves to slot 63 impl 0x1019cccd8 =
    // `KSPlayerLayer.stop()`.
    // ⚠️ The receiver of that dispatch is the OLD layer, not self: x20 arrives as swiftself but is
    // OVERWRITTEN at 0x101a0195c (`ldr x20,[x20,x21]`). Ghidra also mis-attributes the call's
    // argument. Read it from the disassembler.
    // The delegate is wired at CONSTRUCTION instead, in `set(url:options:)` (0x1019fe194), which
    // weak-assigns self together with the `PlayerView : KSPlayerLayerDelegate` witness table
    // (0x1041d6308) on the URL-equality reuse path — so dropping the old `playerLayer?.delegate =
    // self` here does not leave the delegate unwired.
    public var playerLayer: KSPlayerLayer? {
        didSet {
            oldValue?.delegate = nil
            oldValue?.stop()
        }
    }

    // Spelled with the underlying protocol name, not the ControllerDelegate alias above: the
    // reflection field record erases the typealias and stores PlayerControllerDelegate, so this
    // is the same type either way, and the l2 field gate compares against the stored name.
    public weak var delegate: PlayerControllerDelegate?
    public let toolBar = PlayerToolBar()
    public let srtControl = SubtitleModel()
    // Listen to play time change
    public var playTimeDidChange: ((TimeInterval, TimeInterval) -> Void)?
    public var backBlock: (() -> Void)?
    public convenience init() {
        #if os(macOS)
        self.init(frame: .zero)
        #else
        self.init(frame: CGRect(origin: .zero, size: KSOptions.sceneSize))
        #endif
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        toolBar.timeSlider.delegate = self
        toolBar.addTarget(self, action: #selector(onButtonPressed(_:)))
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func onButtonPressed(_ button: UIButton) {
        guard let type = PlayerButtonType(rawValue: button.tag) else { return }

        #if os(macOS)
        if let menu = button.menu,
           let item = button.menu?.items.first(where: { $0.state == .on })
        {
            menu.popUp(positioning: item,
                       at: button.frame.origin,
                       in: self)
        } else {
            onButtonPressed(type: type, button: button)
        }
        #elseif os(tvOS)
        onButtonPressed(type: type, button: button)
        #else
        if #available(iOS 14.0, *), button.menu != nil {
            return
        }
        onButtonPressed(type: type, button: button)
        #endif
    }

    open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
        var type = type
        if type == .play, button.isSelected {
            type = .pause
        }
        switch type {
        case .back:
            backBlock?()
        case .play, .replay:
            play()
        case .pause:
            pause()
        default:
            break
        }
        delegate?.playerController(action: type)
    }

    #if canImport(UIKit)
    override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let presse = presses.first else {
            return
        }
        switch presse.type {
        case .playPause:
            if let playerLayer, playerLayer.state.isPlaying {
                pause()
            } else {
                play()
            }
        default: super.pressesBegan(presses, with: event)
        }
    }
    #endif
    open func play() {
        becomeFirstResponder()
        playerLayer?.play()
        toolBar.playButton.isSelected = true
    }

    open func pause() {
        playerLayer?.pause()
    }

    open func seek(time: TimeInterval, completion: (@MainActor @Sendable (Bool) -> Void)?) {
        playerLayer?.seek(time: time, completion: completion)
    }

    open func resetPlayer() {
        playerLayer = nil
        totalTime = 0.0
    }

    open func set(url: URL, options: KSOptions) {
        srtControl.url = url
        toolBar.currentTime = 0
        totalTime = 0
        playerLayer = KSPlayerLayer(url: url, options: options)
    }

    // MARK: - KSSliderDelegate

    open func slider(value: Double, event: ControlEvents) {
        if event == .valueChanged {
            toolBar.currentTime = value
        } else if event == .touchUpInside {
            seek(time: value) { [weak self] _ in
                self?.delegate?.playerController(seek: value)
            }
        }
    }

    // MARK: - KSPlayerLayerDelegate

    open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        delegate?.playerController(state: state)
        if state == .readyToPlay {
            totalTime = layer.player.duration
            toolBar.isSeekable = layer.player.seekable
            toolBar.playButton.isSelected = true
        } else if state == .playedToTheEnd || state == .paused || state == .error {
            toolBar.playButton.isSelected = false
        }
    }

    open func player(layer _: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        delegate?.playerController(currentTime: currentTime, totalTime: totalTime)
        playTimeDidChange?(currentTime, totalTime)
        toolBar.currentTime = currentTime
        self.totalTime = totalTime
    }

    open func player(layer _: KSPlayerLayer, finish error: Error?) {
        delegate?.playerController(finish: error)
    }

    open func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        delegate?.playerController(bufferedCount: bufferedCount, consumeTime: consumeTime)
    }

    open func playerDidClear(layer _: KSPlayerLayer) {}
}

public extension PlayerView {
    var totalTime: TimeInterval {
        get {
            toolBar.totalTime
        }
        set {
            toolBar.totalTime = newValue
        }
    }
}

extension UIView {
    var viewController: UIViewController? {
        var next = next
        while next != nil {
            if let viewController = next as? UIViewController {
                return viewController
            }
            next = next?.next
        }
        return nil
    }
}
