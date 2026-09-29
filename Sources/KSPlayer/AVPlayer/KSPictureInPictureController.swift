//
//  KSPictureInPictureController.swift
//  KSPlayer
//
//  Created by kintan on 2023/1/28.
//

import AVKit

@available(tvOS 14.0, *)
@MainActor
public class KSPictureInPictureController: AVPictureInPictureController {
    // ⚑ VTABLE-SHAPE DIVERGENCE (session 60) — slot bodies recovered, member identity is NOT.
    //   Forward metadata @0x1044217e0 (descriptor 0x1039ece54, name _TtC8KSPlayer28KSPictureInPictureController)
    //   carries class_ro_t @0x104421780 with ivars == NULL — the binary class has ZERO stored properties
    //   (independently confirmed by dump_binary_field_types.py: "total fields: 0") — and a 3-entry vtable
    //   whose bodies are each ONE statement:
    //     slot 0 @0x1019c75cc (2 instr) `mov x0,x20; b 0x10346d1c0` -> selref 0x10440e238 -> "startPictureInPicture"
    //     ⚑[tool=ghidra ref=startPictureInPicture:0x1019c75cc result=pinned]
    //     slot 1 @0x1019c75d4  UIControl().sendAction(<selref 0x10440e498 = "suspend">, to: UIApplication.shared, for: nil)
    //     slot 2 @0x1019c7648 (2 instr) `mov x0,x20; b 0x10346d400` -> selref 0x10440e2c8 -> "stopPictureInPicture"
    //     ⚑[tool=ghidra ref=stopPictureInPicture:0x1019c7648 result=pinned]
    //   Both selectors are dispatched EXACTLY ONCE binary-wide (get_xrefs_to on each stub returns a single
    //   UNCONDITIONAL_CALL, from the slot itself), so no larger method contains these calls. The three methods
    //   are not @objc — baseMethodList @0x103471e38 has count=1, imp 0x1019c7588, which is none of them.
    //
    //   ⚠️ SESSION 64 — THE "NAMES ARE UNRECOVERABLE" CONCLUSION ABOVE IS REFUTED, AND IT WAS WRONG THE SAME
    //   WAY THE SubtitlePart NEGATIVE WAS (P133/P135): it rested on nm / reflection / recover_swift_function_name,
    //   none of which can see the ORPHANED EXPORT TRIE. All three slots resolve there by address, and so does a
    //   fourth member the vtable does not carry:
    //     slot 0 @0x1019c75cc  start(layer: KSComplexPlayerLayer) -> ()
    //     slot 1 @0x1019c75d4  didStart(layer: KSComplexPlayerLayer) -> ()
    //     slot 2 @0x1019c7648  stop(restoreUserInterface: Swift.Bool) -> ()
    //     static               play(layer: KSComplexPlayerLayer) -> ()
    //     init(contentSource: AVPictureInPictureControllerContentSource), deinit — and NOTHING else.
    //   ⚑[tool=export_trie_oracle ref=KSPictureInPictureController.start:0x1019c75cc result=name-recovered]
    //   ⚑[tool=export_trie_oracle ref=KSPictureInPictureController.didStart:0x1019c75d4 result=name-recovered]
    //   ⚑[tool=export_trie_oracle ref=KSPictureInPictureController.stop:0x1019c7648 result=name-recovered]
    //   `didStart` corroborates independently: the s63 member sweep already listed it as a name the binary
    //   carries and this source does not declare.
    //
    //   ✅ SESSION 98 — THE BLOCK IS LIFTED AND THE BODIES ARE REDUCED. The standing instruction here was
    //   "do not reduce these until KSComplexPlayerLayer is reconstructed", because the class was gutted
    //   into a thin wrapper and its state had to be FOUND, not assumed deleted. Both halves are now done:
    //     · KSComplexPlayerLayer is declared (KSPlayerLayer.swift), superclass and all three fields
    //       gate-verified — and its fields are urls / isPictureInPictureStoped / enterBackgroundTask,
    //       so the view-controller state did NOT move there;
    //     · it moved nowhere. `originalViewController`, `presentingViewController`,
    //       `navigationController` and `isPipPopViewController` are each ZERO-hit across all 57,138
    //       demangled trie symbols, as are the substrings `ipPop` and `PopView`. Forward 1.3.17 removed
    //       the pop-view-controller restoration feature outright.
    //   With the state located as absent, reducing is the derived answer rather than an assumption, so
    //   slot 0 and slot 2 are now one statement each and the six stored properties are gone.
    // ZERO STORED PROPERTIES, and that is now DERIVED rather than assumed. The six properties that
    // used to sit here (static pipController, originalViewController, view, viewController,
    // presentingViewController, navigationController) are gone, together with `start(view:)` and
    // `mute()`, because the state they carried does not exist ANYWHERE in Forward 1.3.17:
    //   · dump_binary_field_types reports "total fields: 0" for this class;
    //   · `originalViewController`, `presentingViewController`, `navigationController` and
    //     `isPipPopViewController` each return ZERO hits across all 57,138 demangled trie symbols,
    //     as do the substrings `ipPop` and `PopView`;
    //   · this class's complete member list in the trie is exactly seven entries — init, deinit,
    //     start(layer:), didStart(layer:), stop(restoreUserInterface:) and static play(layer:).
    // The two open verdicts both required the removed behaviour to be LOCATED before the source was
    // reduced, "not deleted on assumption". It was located: Forward deleted the pop-view-controller
    // restoration feature outright. It did not move to KSComplexPlayerLayer either — that class has
    // three fields (urls, isPictureInPictureStoped, enterBackgroundTask) and none of them is
    // view-controller state.
    // ⚑[tool=fieldrec ref=KSPlayer.KSPictureInPictureController:0x1039ece54 result=zero-fields]

    // s109: `required` is DERIVED, and the body is READ — this init used to be recorded as
    // undeclarable on the ground that "adding `required` would put an initializer in the source
    // that the binary does not show". The binary shows it twice over:
    //   · the trie carries BOTH entry points, `…cfC` __allocating_init @0x1019c74e4 and `…cfc`,
    //     the initializing entry, @0x1019c751c. A purely INHERITED ObjC initializer produces only
    //     the allocating thunk; the presence of the initializing entry is what proves a
    //     Swift-written body exists.
    //   · that body is 19 instructions: build an `objc_super` from this class's metadata
    //     (0x1044217e0) and self, then `objc_msgSendSuper2` with selref 0x10440b938 =
    //     "initWithContentSource:", passing the parameter through unchanged. That is
    //     `super.init(contentSource:)` and nothing else — no field is written, consistent with
    //     this class having zero stored properties.
    // `required` itself is not reflection-visible, but it is forced rather than chosen: the
    // witness table makes req3 an Init requirement, this class is the sole conformer and is not
    // final, and Swift satisfies an init requirement on a non-final class only through `required`.
    // ⚑[tool=decode_objc_selector ref=0x10440b938 result=initWithContentSource:]
    // ⚑[tool=export_trie_oracle ref=KSPictureInPictureController.init(contentSource:):0x1019c751c result=initializing-entry-present]
    override public required init(contentSource: AVPictureInPictureController.ContentSource) {
        super.init(contentSource: contentSource)
    }

    // req6. The binary body is TWO instructions — `mov x0,x20` / `b 0x10346d1c0`, whose selref
    // 0x10440e238 is "startPictureInPicture". The 8-statement `start(view:)` above is the
    // un-reduced source-only version and is deliberately left intact: this class has ZERO stored
    // properties in the binary, so that state lives on KSComplexPlayerLayer, and deleting it before
    // those bodies are reconstructed would destroy information.
    public func start(layer _: KSComplexPlayerLayer) {
        startPictureInPicture()
    }

    // req7. Body read from slot 1 @0x1019c75d4: sendAction of selref 0x10440e498 = "suspend".
    public func didStart(layer _: KSComplexPlayerLayer) {
        #if canImport(UIKit)
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        #endif
    }

    // Body read at slot 2 @0x1019c7648: two instructions, `mov x0,x20` / `b <objc stub>`, whose
    // selref 0x10440e2c8 is "stopPictureInPicture". The parameter is declared but never read — the
    // function contains no comparison and no branch — so it is spelled `_`.
    public func stop(restoreUserInterface _: Bool) {
        stopPictureInPicture()
    }
}

// KSPictureInPictureProtocol — descriptor 0x1039ecde0, 10 requirements,
// num_requirements_in_signature 1, has_associated_type false. Sole conformer
// KSPictureInPictureController (conformance 0x1035676b0, witness table 0x1041d45a0, validated).
// This is the type of `pipController` on BOTH KSMEPlayer and KSAVPlayer — the trie prints
// `KSPictureInPictureProtocol?` for the getter, setter, modify, property descriptor and field
// offset of each — and declaring it is what discharges the session-16 divergence on that field.
//
// EIGHT OF THE TEN REQUIREMENT NAMES ARE RECOVERED. Each witness was resolved by address, and the
// ones the trie does not name were resolved by decoding the objc_msgSend stub they tail-call:
//   req0 Getter  0x1019c7680 -> stub 0x1034641e0, selref 0x10440be40 = "isPictureInPictureActive"
//   req1 Method  0x1019c7698 -> `b 0x1019c769c`, and that target is ALSO a real trie negative,
//                with no single selector to name it — IRREDUCIBLE
//   req2 Init    0x1019c779c -> stub 0x103463520, selref 0x10440bb10 = "initWithPlayerLayer:"
//   req3 Init    0x1019c74e4 -> trie: init(contentSource: AVPictureInPictureControllerContentSource)
//   req4 Method  0x1019c77d8 -> stub 0x103463ba0, selref 0x10440bcb0 = "invalidatePlaybackState"
//   req5 Method  0x1019c77e0 -> reaches objc "valueForKey:" (selref 0x10440e8c8); a KVC read names
//                no member — IRREDUCIBLE
//   req6 Method  0x1019c75cc -> trie: start(layer: KSComplexPlayerLayer)
//   req7 Method  0x1019c75d4 -> trie: didStart(layer: KSComplexPlayerLayer)
//   req8 Method  0x1019c7648 -> trie: stop(restoreUserInterface: Swift.Bool)
//   req9 static  0x10000e52c -> static play(layer: KSComplexPlayerLayer). The body is the bare-`ret`
//                ICF fold shared 420 ways, i.e. EMPTY; the owner was disambiguated with
//                `export_trie_oracle --addr 0x10000e52c --owner KSPictureInPictureController`
//                (verdict OWNER_MATCH), never by picking one name out of the fold.
// ⚑[tool=conformance_walker ref=KSPlayer.KSPictureInPictureProtocol:0x1039ecde0 result=8-of-10-named]
//
// req2 IS NOW DECLARED (s109). The note here used to say neither init requirement could be, on the
// strength of the error `init(contentSource:)` produces — "can only be satisfied by a 'required'
// initializer in non-final class" — and generalised that to req2 without trying it. req2 gives a
// DIFFERENT error: "non-failable initializer requirement 'init(playerLayer:)' cannot be satisfied
// by a failable initializer ('init?')", because AVPictureInPictureController's inherited
// `init(playerLayer:)` is failable. Spelled `init?(playerLayer:)` it declares and builds 4/4.
// The `?` is not the compiler's word against the binary's: `KSAVPlayer.configPIP` @0x1019ab4dc
// calls this very witness and then runs `cmp x0,#0` / `csel x21, xzr, x22, eq`, rebuilding a nil
// existential when the instance comes back null — a failable init read straight off the call site.
//
// req3 STILL IS NOT, and req4 is not either. `init(contentSource:)` does hit the `required`
// error above, and adding `required` would put an initializer in the source that the binary does
// not show. req4 (`invalidatePlaybackState`) is iOS 15 / tvOS 15 while this protocol is tvOS 14,
// and every call site already carries its own #available guard. Declared requirements are
// therefore 6 of 10; the other four are pinned above rather than guessed into existence.
@available(tvOS 14.0, *)
@MainActor
// L7 lane 9: all 10 requirements, in witness-table order (wt 0x1041d45a0). req1 0x1019c7698 bridges
// the value (`_bridgeAnythingToObjectiveC` 0x1034595ec) and sends selref 0x10440dee0 = "setValue:forKey:";
// req4 0x1019c77d8 is `mov x0,x20; b` to selref 0x10440bcb0 = "invalidatePlaybackState"; req5 0x1019c77e0
// bridges the key and sends selref 0x10440e8c8 = "valueForKey:" with an indirect Any? result. All three
// are satisfied by the inherited NSObject/AVPictureInPictureController members.
public protocol KSPictureInPictureProtocol: AnyObject {
    var isPictureInPictureActive: Bool { get }
    func setValue(_ value: Any?, forKey key: String)
    init?(playerLayer: AVPlayerLayer)
    init(contentSource: AVPictureInPictureController.ContentSource)
    func invalidatePlaybackState()
    func value(forKey key: String) -> Any?
    func start(layer: KSComplexPlayerLayer)
    func didStart(layer: KSComplexPlayerLayer)
    func stop(restoreUserInterface: Bool)
    static func play(layer: KSComplexPlayerLayer)
}

// L7 lane 9: two internal protocol-extension members, laid out in KSPictureInPictureController.o just ahead
// of the witnesses. 0x1019c7410 (19 insns) takes an owned indirect Any? (x0) plus Self/wt (x1/x2), sends wt+0x10
// setValue(_:forKey: "delegate") and destroys the Any? (0x1019c78a4) = a setter; its getter is dead-stripped.
// 0x1019c7454 (37 insns) sends wt+0x30 value(forKey: "pictureInPictureViewController") (30-byte literal
// 0x103d349e0) and conditionally casts (swift_dynamicCast flags 6) = a getter. Callers: KSComplexPlayerLayer
// configPIPDelegate 0x1019d1e8c, stop 0x1019d268c, reCheckSubtitle, DidStartPictureInPicture 0x1019d609c.
extension KSPictureInPictureProtocol {
    var delegate: Any? {
        get { value(forKey: "delegate") }
        set { setValue(newValue, forKey: "delegate") }
    }

    var pictureInPictureViewController: UIViewController? {
        value(forKey: "pictureInPictureViewController") as? UIViewController
    }
}

@available(tvOS 14.0, *)
extension KSPictureInPictureController: KSPictureInPictureProtocol {

    // req9. EMPTY body — witness 0x10000e52c is the bare `ret` that 420 symbols ICF-fold onto.
    public static func play(layer _: KSComplexPlayerLayer) {}
}
