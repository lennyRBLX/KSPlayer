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
    //   ⛔ THE BODIES ARE AUDITED DIVERGENT AND THE FIX IS BLOCKED — DO NOT REDUCE THEM.
    //   start and stop are each a bare 2-instruction ObjC tail call against the 8- and 9-statement bodies
    //   below (verdicts KSPictureInPictureController_slot0_1019c75cc / _slot2_1019c7648). The reason is
    //   structural: the binary class has ZERO stored properties, and THREE of its four methods take
    //   `KSComplexPlayerLayer` — a type carrying 44 symbols in the binary and ZERO occurrences anywhere in
    //   this reconstruction. In 1.3.17 this class was gutted into a thin wrapper and its state moved into
    //   that type. Deleting the logic below before locating where the state went would destroy information,
    //   so it stays until KSComplexPlayerLayer is reconstructed. That is the unblocking step, and it is a
    //   new-class job, not a per-slot one.
    nonisolated(unsafe) private static var pipController: KSPictureInPictureController?
    private var originalViewController: UIViewController?
    private var view: KSPlayerLayer?
    private weak var viewController: UIViewController?
    private weak var presentingViewController: UIViewController?
    #if canImport(UIKit)
    private weak var navigationController: UINavigationController?
    #endif

    func stop(restoreUserInterface: Bool) {
        stopPictureInPicture()
        delegate = nil
        guard KSOptions.isPipPopViewController else {
            return
        }
        KSPictureInPictureController.pipController = nil
        if restoreUserInterface {
            #if canImport(UIKit)
            runOnMainThread { [weak self] in
                guard let self, let viewController, let originalViewController else { return }
                if let nav = viewController as? UINavigationController,
                   nav.viewControllers.isEmpty || (nav.viewControllers.count == 1 && nav.viewControllers[0] != originalViewController)
                {
                    nav.viewControllers = [originalViewController]
                }
                if let navigationController {
                    var viewControllers = navigationController.viewControllers
                    if viewControllers.count > 1, let last = viewControllers.last, type(of: last) == type(of: viewController) {
                        viewControllers[viewControllers.count - 1] = viewController
                        navigationController.viewControllers = viewControllers
                    }
                    if viewControllers.firstIndex(of: viewController) == nil {
                        // 新的swiftUI push之后。view会变成是emptyView。所以页面就空白了。
                        navigationController.pushViewController(viewController, animated: true)
                    }
                } else {
                    presentingViewController?.present(originalViewController, animated: true)
                }
            }
            #endif
            view?.player.isMuted = false
            view?.play()
        }

        originalViewController = nil
        view = nil
    }

    func start(view: KSPlayerLayer) {
        startPictureInPicture()
        delegate = view
        guard KSOptions.isPipPopViewController else {
            #if canImport(UIKit)
            // 直接退到后台
            runOnMainThread {
                UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
            }
            #endif
            return
        }
        self.view = view
        #if canImport(UIKit)
        runOnMainThread { [weak self] in
            guard let self, let viewController = view.player.view?.viewController else { return }

            originalViewController = viewController
            if let navigationController = viewController.navigationController, navigationController.viewControllers.count == 1 {
                self.viewController = navigationController
            } else {
                self.viewController = viewController
            }
            navigationController = self.viewController?.navigationController
            if let pre = KSPictureInPictureController.pipController {
                view.player.isMuted = true
                pre.view?.isPipActive = false
            } else {
                if let navigationController {
                    navigationController.popViewController(animated: true)
                    #if os(iOS)
                    if navigationController.tabBarController != nil, navigationController.viewControllers.count == 1 {
                        DispatchQueue.main.async { [weak self] in
                            self?.navigationController?.setToolbarHidden(false, animated: true)
                        }
                    }
                    #endif
                } else {
                    presentingViewController = originalViewController?.presentingViewController
                    originalViewController?.dismiss(animated: true)
                }
            }
        }
        #endif
        KSPictureInPictureController.pipController = self
    }

    static func mute() {
        pipController?.view?.player.isMuted = true
    }
}
