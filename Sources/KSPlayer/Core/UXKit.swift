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
