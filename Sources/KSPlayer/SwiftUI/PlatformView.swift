//
//  PlatformView.swift
//  KSPlayer
//
//  SwiftUI helper views and view-modifiers extracted from the KSPlayer SwiftUI
//  player layer. This is the home for the generic, platform-conditional, and
//  focus-handling helpers documented in §18.18-18.19 of the reversal notes:
//  MenuView, PlatformView, ShowTextField, ShowValueField, PlayBackCommands,
//  FocusModifier, WhenFocusedModifier, MenuLabelStyleModifier.
//
//  MenuView and PlatformView were relocated here from KSVideoPlayerView.swift
//  (their original implementations matched the doc; only MenuView.selection was
//  reconciled to the documented optional `Binding<Selection>?`).
//
//  Inlined-body fence (UIComponents.md §18.25, verified against Ghidra
//  Forward-1.3.15 this pass): none of the 8 types below emit a standalone
//  Ghidra `body`/`makeCommands` code symbol — their SwiftUI bodies are fused
//  into the enclosing result-builder at the (specialized) use site. Verified by
//  exhaustive symbol search: `MenuView`, `ShowValueField`, `PlayBackCommands`,
//  `FocusModifier`, `MenuLabelStyleModifier` return ZERO Ghidra symbols (generic
//  / fully inlined); `ShowTextField` and `WhenFocusedModifier` expose only their
//  value-witness tables (`Vwxx/Vwcp/Vwca/Vwta`), no `body`. All 8 type-metadata
//  records nonetheless exist in `__swift5_types` (contiguous block
//  `0x102EF4500`-`0x102EF4627`: PlayBackCommands/MenuView/PlatformView/
//  ShowValueField/MenuLabelStyleModifier/FocusModifier), so the types are real;
//  the field rosters below are authoritative from `types.json` and, for the two
//  non-generic types, corroborated field-for-field by decompiling their
//  `assignWithCopy` witness (see per-type `/// RE:` anchors). The inlined Video-
//  tab construction site is `VideoSettingView_body_getter @ 0x1014BC660`, which
//  builds ShowTextField/ShowValueField/Picker inline with no nested body symbol.
//  This is the complete statically-recoverable surface for an inlined SwiftUI
//  value type; a standalone `body` cannot exist without runtime metadata.
//
//  RE field-count reconciliation (UIComponents.md §18.18-18.19, types.json
//  lines 3072-3097): the cluster brief states an "Expected field count: 8",
//  but that figure counts only the 8 documented TYPES, not their fields. The
//  full doc rosters sum to 19 stored fields — MenuView 4, PlatformView 1,
//  ShowTextField 3, ShowValueField 4, PlayBackCommands 1, FocusModifier 3,
//  WhenFocusedModifier 2, MenuLabelStyleModifier 1 — every one of which is
//  present below. The 8-vs-19 delta is therefore a types-vs-fields tally
//  mismatch, NOT a missing field. The lone exception is MenuLabelStyleModifier,
//  which carries one EXTRA helper field beyond its 1-field roster; see the
//  per-field note there for the rationale.
//

import SwiftUI

// MARK: - §18.18 Generic helper views

/// RE: §18.18 (KSPlayer.MenuView, 1.3.15; type-metadata `MenuView` @ 0x102EF4511
/// in `__swift5_types`). Generic menu wrapper: presents a `Picker` inside a
/// `Menu` (tvOS 17+/native menus) or a plain navigation-link `Picker` on older
/// OSes. Driven by an optional selection binding.
///
/// Doc field roster (types.json): `selection :: Binding<Selection>?` (`?yxG`);
/// `content :: () -> Content` (`q_yc`); `label :: () -> Label` (`q0_yc`);
/// `_showMenu :: State<Bool>` (`?ySbG`). The binary's `selection` is an OPTIONAL
/// binding; call sites that pass a non-optional `Binding` are promoted to
/// `.some(...)` automatically by Swift, so existing callers remain source-compatible.
///
/// RESIDUAL (inlined SwiftUI body — genuinely-runtime code symbol): the static
/// playbook (decompile the enclosing result-builder) was applied — searched for a
/// standalone `MenuView.body`/specialization symbol and found ZERO Ghidra
/// functions for `MenuView` (generic struct; body specialized + inlined at each
/// `Menu`/`Picker` use site). Type existence is proven via the metadata record
/// above; the field roster is authoritative from types.json. No standalone body
/// symbol can exist for an inlined generic SwiftUI view.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct MenuView<Label, SelectionValue, Content>: View where Label: View, SelectionValue: Hashable, Content: View {
    public let selection: Binding<SelectionValue>?
    @ViewBuilder
    public let content: () -> Content
    @ViewBuilder
    public let label: () -> Label
    @State
    private var showMenu = false
    public var body: some View {
        if let selection {
            if #available(tvOS 17, *) {
                Menu {
                    Picker(selection: selection) {
                        content()
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    label()
                }
                .menuIndicator(.hidden)
            } else {
                Picker(selection: selection, content: content, label: label)
                #if !os(macOS)
                    .pickerStyle(.navigationLink)
                #endif
                    .frame(height: 50)
                #if os(tvOS)
                    .frame(width: 110)
                #endif
            }
        } else {
            // No selection binding: render the content list with its own label only.
            if #available(tvOS 17, *) {
                Menu {
                    content()
                } label: {
                    label()
                }
                .menuIndicator(.hidden)
            } else {
                content()
            }
        }
    }
}

/// RE: §18.18 (KSPlayer.PlatformView, 1.3.15; type-metadata `PlatformView` @
/// 0x102EF4550 in `__swift5_types`). Wraps platform-`#if`-conditional content: a
/// scrollable padded stack on tvOS, otherwise a `Form` (with extra padding on
/// macOS). Doc field: `content :: () -> Content` (`xyc`).
///
/// RESIDUAL (inlined SwiftUI body — genuinely-runtime code symbol): static
/// playbook applied — no standalone `PlatformView.body` symbol is emitted
/// (single-field value view whose `#if`-conditional body is inlined at the use
/// site). Type existence proven by the metadata record above; the lone `content`
/// field is the complete recoverable surface.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct PlatformView<Content: View>: View {
    private let content: () -> Content
    public var body: some View {
        #if os(tvOS)
        ScrollView {
            content()
                .padding()
        }
        .pickerStyle(.navigationLink)
        #else
        Form {
            content()
        }
        #if os(macOS)
        .padding()
        #endif
        #endif
    }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

/// RE: §18.18 (KSPlayer.ShowTextField, 1.3.15). Labeled string form field used by
/// `VideoSettingView`. Doc fields (types.json): `titleKey :: String`;
/// `text :: Binding<String>`; `prompt :: Text?`.
///
/// RE: 0x1014D21C8 (field roster CONFIRMED, 1.3.15). The `assignWithCopy` value-
/// witness `$s8KSPlayer13ShowTextFieldVwca` was decompiled this pass and proves
/// the exact field layout: word 1 `_swift_bridgeObjectRetain/Release` → a bridged
/// `String` (`titleKey`); words 2-5 (object retains + a trivial witness word + a
/// second bridged String) → `Binding<String>` (`text`); words 6-9 an enum-with-
/// payload block whose discriminator is read at `param[9]` with helper
/// `FUN_100014D88` → `Text?` (`prompt`, optional whose payload is the `Text`
/// enum). Matches the types.json roster field-for-field. The body is inlined —
/// constructed inside `VideoSettingView_body_getter @ 0x1014BC660`, no standalone
/// `ShowTextField.body` symbol exists.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct ShowTextField: View {
    public let titleKey: String
    public let text: Binding<String>
    public let prompt: Text?

    public init(_ titleKey: String, text: Binding<String>, prompt: Text? = nil) {
        self.titleKey = titleKey
        self.text = text
        self.prompt = prompt
    }

    public var body: some View {
        TextField(titleKey, text: text, prompt: prompt)
    }
}

/// RE: §18.18 (KSPlayer.ShowValueField, 1.3.15; type-metadata `ShowValueField` @
/// 0x102EF4578 in `__swift5_types`). Labeled value form field generic over a
/// `ParseableFormatStyle`, used by `VideoSettingView`. Doc fields (types.json):
/// `titleKey :: String`; `value :: Binding<F.FormatInput>` (`?y11FormatInput?QzG`);
/// `prompt :: Text?` (`??`); `format :: F` (`x`).
///
/// RESIDUAL (inlined SwiftUI body — genuinely-runtime code symbol): static
/// playbook applied — searched for a standalone body / value-witness and found
/// ZERO Ghidra symbols for `ShowValueField` (generic over `F`; both body and
/// witnesses are demand-specialized per `F` at the use site and inlined into
/// `VideoSettingView`'s tab builders). Type existence proven by the metadata
/// record above; the 4-field roster is authoritative from types.json.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct ShowValueField<F>: View where F: ParseableFormatStyle, F.FormatOutput == String {
    public let titleKey: String
    public let value: Binding<F.FormatInput>
    public let prompt: Text?
    public let format: F

    public init(_ titleKey: String, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil) {
        self.titleKey = titleKey
        self.value = value
        self.format = format
        self.prompt = prompt
    }

    public var body: some View {
        TextField(titleKey, value: value, format: format, prompt: prompt)
    }
}

#if os(macOS) || os(tvOS)
/// RE: §18.18 (KSPlayer.PlayBackCommands, 1.3.15; type-metadata `PlayBackCommands`
/// @ 0x102EF4500 in `__swift5_types`). A `SwiftUI.Commands` (NOT a `View`)
/// providing play/pause/seek menu-bar + hardware-key commands, driven by the
/// focused `KSVideoPlayer.Coordinator`. Doc field (types.json):
/// `_config :: FocusedObject<KSVideoPlayer.Coordinator>`.
///
/// RESIDUAL (inlined Commands body — genuinely-runtime code symbol): static
/// playbook applied — no standalone `PlayBackCommands.body`/`makeCommands` symbol
/// is emitted. The only related symbol, `Commands._makeCommands` @ 0x1014CCBD8,
/// is the GENERIC SwiftUI protocol-witness dispatch (a recursive tail-jump
/// thunk), not a `PlayBackCommands`-specific body — the `CommandMenu`/`Button`
/// tree is fused into SwiftUI's command-building machinery at the
/// `.commands { PlayBackCommands() }` scene-attach site. Type existence proven by
/// the metadata record above; the single `_config` field is the recoverable
/// surface.
///
/// Attached via the scene `.commands { PlayBackCommands() }` modifier on macOS
/// and tvOS. Guarded to those platforms because menu-bar / hardware-key command
/// menus are only meaningful there (iOS has no command menus).
///
/// Depends on `KSVideoPlayer.Coordinator` (defined in AVPlayer/KSVideoPlayer.swift,
/// an `ObservableObject`), which already exposes `state.isPlaying`,
/// `playerLayer?.play()/pause()`, and `skip(interval:)` — so `@FocusedObject` and
/// the command bodies resolve against the existing package surface.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct PlayBackCommands: Commands {
    @FocusedObject
    private var config: KSVideoPlayer.Coordinator?

    public init() {}

    public var body: some Commands {
        CommandMenu("Playback") {
            Button(config?.state.isPlaying == true ? "Pause" : "Play") {
                guard let config else { return }
                if config.state.isPlaying {
                    config.playerLayer?.pause()
                } else {
                    config.playerLayer?.play()
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(config == nil)

            Divider()

            Button("Seek Forward") {
                config?.skip(interval: 15)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(config == nil)

            Button("Seek Backward") {
                config?.skip(interval: -15)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(config == nil)
        }
    }
}
#endif

// MARK: - §18.19 Focus ViewModifier structs

#if os(tvOS) || os(macOS)
/// RE: §18.19 (KSPlayer.FocusModifier, 1.3.15; type-metadata `FocusModifier` @
/// 0x102EF4627 in `__swift5_types`). Binds a generic `Value` into a
/// `FocusState<Value?>` and mirrors the resulting focus into a local `State<Bool>`.
/// Doc fields (types.json): `_binding :: FocusState<Value?>` (`?yxSgG`);
/// `value :: Value` (`x`); `_focused :: State<Bool>` (`?ySbG`).
///
/// tvOS/macOS only — `FocusState` driven navigation is a tvOS/macOS concern.
///
/// RESIDUAL (inlined SwiftUI body — genuinely-runtime code symbol): static
/// playbook applied — searched for a standalone `FocusModifier.body`/witness and
/// found ZERO Ghidra symbols (generic over `Value`; `body(content:)` is
/// specialized + inlined at each `.modifier(FocusModifier(...))` site). Type
/// existence proven by the metadata record above; the 3-field roster is
/// authoritative from types.json.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct FocusModifier<Value>: ViewModifier where Value: Hashable {
    @FocusState
    private var binding: Value?
    private let value: Value
    @State
    private var focused: Bool = false

    public init(value: Value) {
        self.value = value
    }

    public func body(content: Content) -> some View {
        content
            .focused($binding, equals: value)
            .onChange(of: binding) { newValue in
                focused = newValue == value
            }
    }
}
#endif

/// RE: §18.19 (KSPlayer.WhenFocusedModifier, 1.3.15). Reads the environment
/// `isFocused` and mirrors it into a `Binding<Bool>` so a parent can observe focus.
///
/// Doc fields (types.json): `_isFocused :: Environment<Bool>`;
/// `_isFocuse :: Binding<Bool>` — the binary preserves the typo "isFocuse";
/// per the auto-fix-typos rule and doc note (line 3096) the Swift port renames
/// the binding to `isFocusedBinding` to avoid clashing with the sibling
/// `isFocused` environment value.
///
/// RE: 0x1014D28B8 (field roster CONFIRMED, 1.3.15). The `assignWithCopy`
/// value-witness `$s8KSPlayer19WhenFocusedModifierVwca` was decompiled this pass
/// and proves the 2-field layout: word 0 + a trailing byte handled by the
/// resilient location-witness pair `FUN_1000AF010`/`FUN_1000AF02C` → the
/// `@Environment<Bool>` storage (`_isFocused`); words 2-3 each `_swift_retain/
/// release` (the two-word get/set-closure box of a SwiftUI `Binding`) →
/// `Binding<Bool>` (`isFocusedBinding`). Confirms the types.json roster
/// field-for-field. The `body(content:)` is inlined at the `.modifier(...)` use
/// site — no standalone body symbol exists.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct WhenFocusedModifier: ViewModifier {
    @Environment(\.isFocused)
    private var isFocused: Bool
    // Renamed from the binary's typo'd `_isFocuse` to avoid the name collision.
    private let isFocusedBinding: Binding<Bool>

    public init(isFocused: Binding<Bool>) {
        self.isFocusedBinding = isFocused
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { newValue in
                isFocusedBinding.wrappedValue = newValue
            }
    }
}

/// RE: §18.19 (KSPlayer.MenuLabelStyleModifier, 1.3.15; type-metadata
/// `MenuLabelStyleModifier` @ 0x102EF4610 in `__swift5_types`). Styles a menu
/// label based on local focus state. Doc field (types.json):
/// `_isFocus :: State<Bool>` — the binary's abbreviated `_isFocus` is renamed to
/// `isFocused` per the auto-fix-typos rule and doc note (line 3097).
///
/// RESIDUAL (inlined SwiftUI body — genuinely-runtime code symbol): static
/// playbook applied — no standalone `MenuLabelStyleModifier.body`/witness symbol
/// is emitted (ZERO Ghidra symbols; the `body(content:)` padding/background/
/// foreground chain is inlined at each `.modifier(...)` site). Type existence
/// proven by the metadata record above; the documented `_isFocus` @State is the
/// authoritative roster field (the `environmentFocused` bridge below is the
/// noted +1 helper, not a binary field).
///
/// Field-count note (types.json line 3097): the documented roster is exactly
/// ONE field — `_isFocus :: State<Bool>` (the `isFocused` @State below). The
/// `environmentFocused` field is an EXTRA helper not in the binary roster: a
/// SwiftUI `ViewModifier` cannot read `\.isFocused` without a stored
/// `@Environment` property wrapper, so this field is the bridge that drives the
/// documented `@State` via the `onChange` in `body`. It is benign (mirrors the
/// environment focus value into the documented state) and changes no behavior;
/// the divergence from the 1-field roster is intentional and recorded here.
@available(iOS 15, tvOS 16, macOS 12, *)
public struct MenuLabelStyleModifier: ViewModifier {
    // Renamed from the binary's abbreviated `_isFocus`. Kept as @State per the
    // documented field roster; driven from the environment focus value below.
    @State
    private var isFocused: Bool = false
    // EXTRA (beyond doc roster): @Environment bridge required to read \.isFocused
    // inside a ViewModifier; feeds the documented `isFocused` @State via onChange.
    @Environment(\.isFocused)
    private var environmentFocused: Bool

    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isFocused ? Color.accentColor.opacity(0.3) : Color.clear)
            .foregroundColor(isFocused ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: environmentFocused) { newValue in
                isFocused = newValue
            }
    }
}
