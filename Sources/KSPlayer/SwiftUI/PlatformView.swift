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

/// RE: §18.18 (KSPlayer.MenuView, 1.3.15). Generic menu wrapper: presents a
/// `Picker` inside a `Menu` (tvOS 17+/native menus) or a plain navigation-link
/// `Picker` on older OSes. Driven by an optional selection binding.
///
/// Doc field roster (types.json): `selection :: Binding<Selection>?` (`?yxG`);
/// `content :: () -> Content` (`q_yc`); `label :: () -> Label` (`q0_yc`);
/// `_showMenu :: State<Bool>` (`?ySbG`). The binary's `selection` is an OPTIONAL
/// binding; call sites that pass a non-optional `Binding` are promoted to
/// `.some(...)` automatically by Swift, so existing callers remain source-compatible.
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

/// RE: §18.18 (KSPlayer.PlatformView, 1.3.15). Wraps platform-`#if`-conditional
/// content: a scrollable padded stack on tvOS, otherwise a `Form` (with extra
/// padding on macOS). Doc field: `content :: () -> Content` (`xyc`).
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

/// RE: §18.18 (KSPlayer.ShowTextField, 1.3.15; value-witness
/// `$s8KSPlayer13ShowTextFieldVwca @ 0x1014D21C8`). Labeled string form field
/// used by `VideoSettingView`. Doc fields (types.json): `titleKey :: String`;
/// `text :: Binding<String>`; `prompt :: Text?`.
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

/// RE: §18.18 (KSPlayer.ShowValueField, 1.3.15). Labeled value form field generic
/// over a `ParseableFormatStyle`, used by `VideoSettingView`. Doc fields
/// (types.json): `titleKey :: String`; `value :: Binding<F.FormatInput>`
/// (`?y11FormatInput?QzG`); `prompt :: Text?` (`??`); `format :: F` (`x`).
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
/// RE: §18.18 (KSPlayer.PlayBackCommands, 1.3.15). A `SwiftUI.Commands` (NOT a
/// `View`) providing play/pause/seek menu-bar + hardware-key commands, driven by
/// the focused `KSVideoPlayer.Coordinator`. Doc field (types.json):
/// `_config :: FocusedObject<KSVideoPlayer.Coordinator>`.
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
/// RE: §18.19 (KSPlayer.FocusModifier, 1.3.15). Binds a generic `Value` into a
/// `FocusState<Value?>` and mirrors the resulting focus into a local `State<Bool>`.
/// Doc fields (types.json): `_binding :: FocusState<Value?>` (`?yxSgG`);
/// `value :: Value` (`x`); `_focused :: State<Bool>` (`?ySbG`).
///
/// tvOS/macOS only — `FocusState` driven navigation is a tvOS/macOS concern.
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

/// RE: §18.19 (KSPlayer.WhenFocusedModifier, 1.3.15; value-witness
/// `$s8KSPlayer19WhenFocusedModifierVwca @ 0x1014D28B8`). Reads the environment
/// `isFocused` and mirrors it into a `Binding<Bool>` so a parent can observe focus.
///
/// Doc fields (types.json): `_isFocused :: Environment<Bool>`;
/// `_isFocuse :: Binding<Bool>` — the binary preserves the typo "isFocuse";
/// per the auto-fix-typos rule and doc note (line 3096) the Swift port renames
/// the binding to `isFocusedBinding` to avoid clashing with the sibling
/// `isFocused` environment value.
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

/// RE: §18.19 (KSPlayer.MenuLabelStyleModifier, 1.3.15). Styles a menu label
/// based on local focus state. Doc field (types.json): `_isFocus :: State<Bool>`
/// — the binary's abbreviated `_isFocus` is renamed to `isFocused` per the
/// auto-fix-typos rule and doc note (line 3097).
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
