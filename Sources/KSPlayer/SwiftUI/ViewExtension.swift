//
//  ViewExtension.swift
//  KSPlayer
//
//  ⚑ THE FILE NAME IS DERIVED, NOT CHOSEN. `FocusModifier`'s own `#fileID` literal reads
//  "KSPlayer/ViewExtension.swift" (lines 171 and 174), and no such file existed in the
//  reconstruction. `#fileID` carries module + file name only, so the file NAME is read from the
//  binary while the DIRECTORY is a placement judgement — recorded here rather than implied.
//  ⚑ approved=jweaver for the directory choice; `Sources/KSPlayer/SwiftUI/` is where this module's
//  other SwiftUI view types already live.
//

import SwiftUI

/// ⚑ RECOVERED TYPE — nominal descriptor 0x1039f3078. Nothing of this name or shape existed in the
/// reconstruction, and `VideoControllerView.body` cannot be spelled without it: that body applies
/// `FocusModifier(_binding: $model.focusableView, value: .controller, _focused: FocusState<Bool>())`.
///
/// The generic signature is READ, not inferred: one generic parameter carrying exactly one
/// requirement, `$sSHMp` = `Swift.Hashable`. The `Hashable` bound is what makes the two `==`
/// comparisons in the body below legal, so it is load-bearing rather than decorative.
///
/// Field records, in binary order — the property-wrapper backing stores are what reflection sees,
/// and the source declares the wrapped types:
///   0 `_binding` : `Binding<Value?>`      -> `@Binding var binding: Value?`
///   1 `value`    : `Value`, flags=0 (let) -> `let value: Value`
///   2 `_focused` : `FocusState<Bool>`     -> `@FocusState var focused: Bool`
///
/// `ViewModifier` conformance witness table 0x10356fa30, slot [5] -> `body(content:)` @0x101af8a2c.
/// ⚑ These types carry NO trie symbols at all — `VideoControllerView` has zero, and this one is
/// reached the same way, through its witness table rather than by name. Do not look for a name.
/// ⚑[tool=decode_witness_table ref=FocusModifier.ViewModifier:0x10356fa30 result=slot5-body-0x101af8a2c]
///
/// The body is a two-way binding between an external `Value?` selection and SwiftUI's own
/// `@FocusState`: an incoming selection focuses this view when it matches `value`, and gaining focus
/// publishes `value` back — while LOSING focus clears the selection only if it still holds `value`,
/// which is what stops one view's blur from stealing another view's selection.
struct FocusModifier<Value: Hashable>: ViewModifier {
    @Binding
    var binding: Value?
    let value: Value
    @FocusState
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: binding) { _, newValue in
                focused = newValue == value
            }
            .onChange(of: focused) { _, newValue in
                if newValue {
                    binding = value
                } else if binding == value {
                    binding = nil
                }
            }
    }
}
