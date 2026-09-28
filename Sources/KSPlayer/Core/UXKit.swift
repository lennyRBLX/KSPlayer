//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
import Foundation
import QuartzCore
import AVFoundation
import CryptoKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.CGSize.within(ratio:):0x1019e7800 result=85-instr]
/// The Forward body at 0x1019e7800 uses d0 = ratio, d1 = width, and d2 = height.
/// Its checked `Int` conversions and integer-equality guard precede the two fit branches;
/// the source below preserves that conversion order and trapping Swift.Int behavior.
extension CGSize {
    public var ratio: Double {
        if width == 0 || height == 0 {
            return 16.0 / 9.0
        }
        return width / height
    }
    public static var one: CGSize {
        CGSize(width: 1, height: 1)
    }
    func within(ratio: Double) -> CGSize {
        guard ratio != 0 else { return self }
        let integerWidth = Int(width)
        let integerAspectWidth = Int(ratio * height)
        guard integerWidth != integerAspectWidth else { return self }
        if width / height < ratio {
            return CGSize(width: Double(integerWidth), height: Double(Int(width / ratio)))
        } else {
            return CGSize(width: Double(integerAspectWidth), height: Double(Int(height)))
        }
    }
    public func convert(rect: CGRect, playRatio: Double, toSize: CGSize) -> CGRect {
        guard height != 0, width != 0, toSize.width != 0, toSize.height != 0 else {
            return rect
        }
        let widthScale = toSize.width / width
        let heightScale = toSize.height / height
        let scale = playRatio > 2.32 && playRatio < 2.34 ? widthScale : min(widthScale, heightScale)
        var result = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale, width: rect.size.width * scale, height: rect.size.height * scale)
        let size = CGSize(width: width * scale, height: height * scale)
        let imageScale = KSOptions.subtitleImageScale
        if imageScale != 1.0 {
            let midX = result.midX
            let midY = result.midY
            result.size.width *= imageScale
            result.size.height *= imageScale
            result.origin.x = midX - result.width * 0.5
            result.origin.y = midY - result.height * 0.5
        }
        result.origin.x += (toSize.width - size.width) * 0.5
        let offsetY = (toSize.height - size.height) * 0.5
        result.origin.y += offsetY
        if result.maxY > toSize.height {
            result.origin.y += offsetY
        }
        result.origin = result.integral.origin
        let offset = KSOptions.subtitleImageOffset
        result.origin.x += offset.width
        result.origin.y += offset.height
        return result
    }
}

/// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.UIFont.with(weight:):0x1019f1e40]
/// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.UIFont.italic.getter:0x1019f2054]
/// These are needed by KSOptions.textFont(width:style:). `italic` is `mov w0, #1; b 0x1019f205c`, and
/// 0x1019f205c is a private helper outside the trie that ORs the symbolic traits. Both bodies send
/// fontWithDescriptor:size: with `pointSize`, and both fall back to `self` when it returns nil.
/// ⚑[tool=forward_fn ref=(extension in KSPlayer):__C.UIFont.with(angle:):0x1019f2150] rotation matrix via
/// fontDescriptorWithMatrix:, same fontWithDescriptor:size: / `self` fallback.
#if canImport(UIKit)
public extension UIFont {
    func with(weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize) as UIFont? ?? self
    }

    var italic: UIFont {
        with(traits: .traitItalic)
    }

    private func with(traits: UIFontDescriptor.SymbolicTraits) -> UIFont { // name inferred
        let symbolicTraits = fontDescriptor.symbolicTraits.union(traits)
        let descriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize) as UIFont? ?? self
    }

    func with(angle: CGFloat) -> UIFont {
        let matrix = CGAffineTransform(rotationAngle: angle)
        var descriptor = fontDescriptor
        descriptor = descriptor.withMatrix(matrix)
        return UIFont(descriptor: descriptor, size: pointSize) as UIFont? ?? self
    }
}
#endif

extension UIView {

    /// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.UIView.didStartPIP(to:):0x10000e52c result=1-instr-empty]
    /// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.UIView.didStopPIP():0x10000e52c result=1-instr-empty]
    /// A no-op DEFAULT PAIR on UIView, distinct from `MetalPlayView.didStartPIP(to:)` /
    /// `didStopPIP()` — the trie carries all four symbols separately. KSComplexPlayerLayer's PiP
    /// delegates call these on `player.view`, whose static type is `UIView`, so the MetalPlayView
    /// pair cannot satisfy those call sites; that is what surfaced these.
    ///
    /// ⚑ EMPTY IS THE READING, not a stub. Both resolve to **0x10000e52c**, which disassembles to
    ///   a bare `ret` and is the image's canonical ICF-folded empty body. Unlike a folded *method*
    ///   body — which carries no per-member information — "this function does nothing" is the
    ///   entire content of an empty body, so the fold is not a loss here.
    ///
    /// ⚑ `@objc` IS REQUIRED, and it is proven by two independent facts rather than by taste:
    ///   1. The call site is an `objc_msgSend` with selector `didStopPIP` (__got 0x10410b928,
    ///      selref 0x10440b138) sent to `player.view` — a dynamic dispatch, which a plain Swift
    ///      extension method never produces.
    ///   2. `MetalPlayView` declares members of the same names. Without `@objc` here the compiler
    ///      rejects that outright — "non-'@objc' instance method … is declared in extension of
    ///      'UIView' and cannot be overridden" — so the original cannot have been non-`@objc`.
    ///   ⚑ The absence of a `…To`-suffixed thunk in the trie is NOT counter-evidence: for an
    ///     `@objc` member on a class that is already ObjC, the ObjC method list can point straight
    ///     at the Swift implementation, so no separate thunk symbol is emitted. An earlier note
    ///     here read that absence as "not @objc"; the compiler refuted it.
    @objc func didStartPIP(to _: UIView) {}

    @objc func didStopPIP() {}

    var backingLayer: CALayer? {
        #if !canImport(UIKit)
        wantsLayer = true
        #endif
        return layer
    }

    #if canImport(UIKit)
    // ⚑[tool=member_add ref=UIView.backingScaleFactor:0x1019f2398 result=dne; Forward order backingLayer 0x1019f237c < this < viewController 0x1019f23e4]
    var backingScaleFactor: CGFloat { @used get { UITraitCollection.current.displayScale } }
    #endif

    var cornerRadius: CGFloat {
        get {
            backingLayer?.cornerRadius ?? 0
        }
        set {
            backingLayer?.cornerRadius = newValue
        }
    }
    /// ⚑[tool=export_trie_oracle ref=(extension in KSPlayer):__C.UIView.addSub(view:):0x1019f245c result=162-instr]
    /// The binary carries this extension and the source did not — it surfaced because
    /// `MetalPlayView.didStartPIP` fails to compile without it. All three calls are decoded from
    /// their selrefs / bind table, none guessed:
    ///   · `bl 0x10346d9a0` → selref 0x10440e430 = **`superview`**, sent to the ARGUMENT (`view`),
    ///     then `objc_retainAutoreleasedReturnValue`. A nil result (`cbz x0`) falls straight through
    ///     to the add, which is why the nil case adds rather than returns.
    ///   · `bl 0x103458674` → __got 0x104113618 =
    ///     `static NSObject.== (NSObject, NSObject) -> Bool`, comparing that superview with `self`
    ///     (`objc_retain_x20` / `objc_retain_x19` supply the two operands). `tbz w20,#0` returns
    ///     when they ARE equal.
    ///   · `bl 0x10345df80` → selref 0x10440a5a8 = **`addSubview:`**, sent to `self` with `view`.
    /// ⚑[tool=decode_objc_selector ref=0x10440e430 result='superview']
    /// ⚑[tool=decode_objc_selector ref=0x10440a5a8 result='addSubview:']
    /// ⚑[tool=bind_oracle ref=__got:0x104113618 result=NSObject.==]
    ///
    /// ⚑ It is `addSubview` guarded by an identity check, NOT a bare `addSubview` — re-adding a
    ///   view already owned by `self` is what the guard suppresses. Substituting a plain
    ///   `addSubview` compiles and drops that.
    /// ⚑ Placed in this file because it must build on both platforms (MetalPlayView is
    ///   cross-platform); UIKitExtend.swift's UIView extension is UIKit-only.
    func addSub(view: UIView) {
        if view.superview == self {
            return
        }
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: leftAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }
}

@objc public enum ControlEvents: Int {
    case touchDown
    case touchUpInside
    case touchCancel
    case valueChanged
    case primaryActionTriggered
    case mouseEntered
    case mouseExited
}

protocol KSSliderDelegate: AnyObject {
    /**
     call when slider action trigged
     - parameter value:      progress
     - parameter event:       action
     */
    func slider(value: Double, event: ControlEvents)
}

open class LayerContainerView: UIView {
    #if canImport(UIKit)
    override open class var layerClass: AnyClass {
        CAGradientLayer.self
    }
    #else
    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer = CAGradientLayer()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    #endif
    public var gradientLayer: CAGradientLayer {
        // swiftlint:disable force_cast
        layer as! CAGradientLayer
        // swiftlint:enable force_cast
    }
}

// DisplayLinkProtocol abstracts UIKit's CADisplayLink (iOS/tvOS/visionOS) and the CVDisplayLink-backed macOS
// shim (the `CADisplayLink` class in MetalPlayView.swift) behind one interface, so MetalPlayView.displayLink can
// hold either. Reconstructed from the binary protocol descriptor @0x1039ee41c (class-bound = AnyObject; 13
// witness requirements; iOS conformance WT @0x1041d64d0). NOTE (binary-indifferent): timestamp/duration are 2 of
// CADisplayLink's 3 get-only timing properties {timestamp, duration, targetTimestamp} — protocol requirement
// names are absent from Swift metadata and these two getter witnesses are dead-stubbed, so the exact pair (and
// their order) is not binary-observable; any 2 recompile to the identical witness table. {timestamp, duration}
// chosen as the primitives (targetTimestamp = timestamp + duration, the shim's derived convenience).
protocol DisplayLinkProtocol: AnyObject {
    var isPaused: Bool { get set }                             // witness i0-2 (i1 set = setPaused:)
    var preferredFramesPerSecond: Int { get set }             // witness i3-5 (dead-stubbed: the pre-iOS-15 fps branch)
    var preferredFrameRateRange: CAFrameRateRange { get set }  // witness i6-8 (i7 set = setPreferredFrameRateRange:)
    var timestamp: TimeInterval { get }                       // witness i9  (binary-indifferent, see note)
    var duration: TimeInterval { get }                        // witness i10 (binary-indifferent, see note)
    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) // witness i11 (called concretely in init)
    func invalidate()                                         // witness i12 (= invalidate)
}

// One unguarded conformance covers both platforms: on iOS/tvOS/visionOS `CADisplayLink` is UIKit's (its native
// properties satisfy every requirement); on macOS it is the CVDisplayLink-backed shim (whose members do). Either
// way an empty extension. Binary iOS conformance WT @0x1041d64d0 (10 dead-stubbed + 3 live witnesses:
// setPaused: / setPreferredFrameRateRange: / invalidate).
extension CADisplayLink: DisplayLinkProtocol {}
