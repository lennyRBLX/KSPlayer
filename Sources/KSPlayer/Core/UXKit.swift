//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
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
    func within(ratio: Double) -> CGSize {
        guard ratio != 0 else { return self }
        let integerWidth = Int(width)
        let integerAspectWidth = Int(ratio * height)
        guard integerWidth != integerAspectWidth else { return self }
        if ratio <= width / height {
            return CGSize(width: Double(integerAspectWidth), height: Double(Int(height)))
        } else {
            return CGSize(width: Double(integerWidth), height: Double(Int(width / ratio)))
        }
    }
}

extension UIView {
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
    }

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

    var cornerRadius: CGFloat {
        get {
            backingLayer?.cornerRadius ?? 0
        }
        set {
            backingLayer?.cornerRadius = newValue
        }
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
