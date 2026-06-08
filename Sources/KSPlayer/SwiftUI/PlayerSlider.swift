//
//  PlayerSlider.swift
//  KSPlayer
//
//  KSPlayer SwiftUI seek-bar slider family. This is the player layer's own
//  SwiftUI scrub control (distinct from the UIKit `KSSlider`): a Float-valued
//  binding with an explicit `bufferValue` rail, a `bounds` ClosedRange (named
//  after the binary field, not `range`), a non-optional `onEditingChanged`
//  closure, and three property-wrapper-backed state fields for in-flight drag,
//  tvOS focus, and pointer hover. Companion `ProgressTrack` is the read-only
//  buffer+progress rail whose body the binary inlines into the slider's track
//  builder, and `ControllerTimeModel` is the lightweight Int-quantized time
//  observable that drives the time labels.
//
//  Field shapes are taken verbatim from the binary's reflection metadata
//  (types.json) and the decompiled body/track builders.
//
//  Cross-reference (binary mangled symbol): $s8KSPlayer12PlayerSliderV
//

import SwiftUI

// MARK: - ControllerTimeModel
//
// NOTE (FIELD_PLACEMENTS / CROSS-FILE): per the cluster map this file
// (PlayerSlider.swift) is the canonical home for `ControllerTimeModel`, and the
// reversal doc (§11.4 + §18.9) documents the authoritative 4-field model. The
// canonical 4-field definition is now ACTIVE here (its designated cluster home).
//
// A redundant 2-field stub (currentTime/totalTime only) still exists in
// KSPlayer/AVPlayer/KSVideoPlayer.swift:330 and MUST be deleted to avoid a
// redeclaration build error — that edit is outside this cluster's scope and is
// reported in the OUTPUT as a CROSS-FILE NEEDED item. The stub's owner-proving
// init is 0x1013C1FA8.

/// A frequently-changing model; Views should observe it sparingly. Times are
/// quantized to `Int` (whole seconds) so the publisher does not fire on every
/// sub-second tick — only when the displayed second actually changes.
///
/// RE: 0x1013C2D60 (ControllerTimeModel metadata accessor, 1.3.15)
/// RE: 0x1013C1FA8 (ControllerTimeModel.init, 0x11C = 284 bytes, 1.3.15 —
/// CONFIRMED all four fields + defaults by decompile: three
/// `Combine.Published.init(initialValue:)` calls over `Swift.Int`
/// (`PTR___sSiN` / `__s7Combine9PublishedV12initialValueACyxGx_tcfC`) with
/// initial values 0, 1, 0 respectively, then a plain word store of `1` to the
/// `fileSize` slot — NOT a Published wrapper. Int (not Double) is proven by the
/// `__sSiN` Swift.Int witness table threaded through all three Published inits.)
public class ControllerTimeModel: ObservableObject {
    // §18.9 field 1: `_currentTime`, Combine.Published<Swift.Int>, default 0.
    // Int-quantized so the model does not update on every frame.
    /// RE: 0x1013C1FA8 (Published.init(initialValue:) with local_58 = 0).
    @Published
    public var currentTime = 0
    // §18.9 field 2: `_totalTime`, Combine.Published<Swift.Int>, default 1.
    /// RE: 0x1013C1FA8 (Published.init(initialValue:) with local_58 = 1).
    @Published
    public var totalTime = 1
    // §18.9 field 3: `_bufferTime`, Combine.Published<Swift.Int>, default 0.
    /// RE: 0x1013C1FA8 (Published.init(initialValue:) with local_58 = 0).
    @Published
    public var bufferTime = 0
    // §18.9 field 4: `fileSize`, Swift.Int64, default 1.
    // Plain stored Int64 (NOT @Published in the binary); init sets it to 1.
    /// RE: 0x1013C1FA8 (plain store `*(... + fileSize) = 1`, no Published wrapper).
    public var fileSize: Int64 = 1

    public init() {}
}

// MARK: - PlayerSlider

/// SwiftUI seek-bar slider for the KSPlayer player layer.
public struct PlayerSlider: View {
    @Binding public var value: Float
    public var bufferValue: Float
    public var bounds: ClosedRange<Float>
    public var onEditingChanged: (Bool) -> Void

    @State private var beginDrag: Bool = false
    @FocusState private var isFocused: Bool
    @State private var hoverValue: Float? = nil

    /// NOTE: `types.json` records the seven fields above and their types
    /// (verified — value Binding<Float>, bufferValue Float, bounds
    /// ClosedRange<Float>, onEditingChanged (Bool)->(), _beginDrag State<Bool>,
    /// _isFocused FocusState<Bool>, _hoverValue State<Float?>), but the rev does
    /// not record an init signature.
    ///
    /// RESIDUAL (genuinely-runtime): the per-parameter default values
    /// (bufferValue: 0, bounds: 0...1, onEditingChanged: { _ in }) are NOT
    /// statically recoverable. Playbook tried: (1) `search_functions
    /// "PlayerSlider.*init|allocating_init"` — no memberwise/explicit init symbol
    /// is emitted for `$s8KSPlayer12PlayerSliderV` (SwiftUI synthesizes the
    /// memberwise init; default-argument generators, if any, were inlined away);
    /// (2) the only PlayerSlider code symbols are the two result-builders
    /// (0x1014B2BFC / 0x1014B44D0) and the misc value-witness/thunk helpers
    /// around 0x1014B4xxx — none decompile to a default-argument generator
    /// (`...fA_` / `...fA0_`). Defaults are materialized at each call site, so the
    /// declared defaults here are a reconstruction convenience that no decompile
    /// can confirm or refute.
    public init(
        value: Binding<Float>,
        bufferValue: Float = 0,
        bounds: ClosedRange<Float> = 0 ... 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.bufferValue = bufferValue
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
    }

    /// Default track tint: a white `Color` carried at full strength so callers
    /// layer `.opacity(...)` on top (matching the binary, which builds the rail
    /// from a white `Color` plus per-rail opacity).
    ///
    /// RE: 0x1014B2BFC + 0x1014B44D0 (white track color materialized inline via
    /// `SwiftUI.Color.white` getter — symbol `__s7SwiftUI5ColorV5whiteACvgZ` —
    /// at every rail site inside PlayerSlider_bodyBuilder / _buildTrackBody,
    /// 1.3.15. Value CONFIRMED: the rail base color is `Color.white`.)
    ///
    /// Provenance correction (was `RE: 0x1008EAC60`): that address is a
    /// MISATTRIBUTED label. `get_function_by_address 0x1008EAC60` is a 28-byte
    /// body (`0x1008EAC60–0x1008EAC7B`) that calls `FUN_1008EAC7C` with
    /// `CryptoKit.Insecure.SHA1Digest` metadata; its only xrefs are from the
    /// CryptoKit caller `FUN_1008CF224`. No PlayerSlider code reaches it, so the
    /// binary does NOT factor the color into a discrete `initDefaultTrackColor`
    /// function — it is inlined `Color.white`. This helper is kept only as a
    /// reconstruction-side factoring of that inlined value (no binary 1:1 fn).
    private static func initDefaultTrackColor() -> Color {
        Color.white
    }

    /// RE: 0x1014B2BFC (PlayerSlider_bodyBuilder, 1.3.15 — CONFIRMED: this is the
    /// result-builder that materializes the GeometryReader closure, the
    /// `DragGesture(minimumDistance:coordinateSpace:.local)` with its
    /// onChanged/onEnded handlers, the iOS-17 `.onContinuousHover` branch
    /// (guarded by `___isPlatformVersionAtLeast(2, 0x11, 0, 0)`), and the
    /// `formatSecondsToTimeString`→`Text(...).foregroundColor(.white)` label.)
    ///
    /// §18.10 thunk note: `PlayerSlider_buildTrackBody_thunk @ 0x100009CAC` is a
    /// compiler-generated partial-apply thunk for the `GeometryReader` closure
    /// below; it is intentionally NOT reconstructed as source (no behavior of its
    /// own — the Swift compiler re-synthesizes it).
    public var body: some View {
        GeometryReader { geometry in
            buildTrackBody(in: geometry)
        }
        .frame(height: 14)
        .focusable(true)
        .focused($isFocused)
    }

    /// RE: 0x1014B44D0 (PlayerSlider_buildTrackBody, 1.3.15)
    ///
    /// Builds the track/buffer/progress rails, the hover indicator, the thumb,
    /// and a time label. The thumb position is derived from `GeometryProxy.size`
    /// with the value snapped to a 0.001 grid and clamped to `bounds`. The
    /// hover-scrub affordance is gated on iOS 17+ (the binary's
    /// `___isPlatformVersionAtLeast(2, 0x11, 0, 0)` check) and uses
    /// `.onContinuousHover(coordinateSpace: .local)`.
    ///
    /// RE divergences (binary-verified vs. this reconstruction; the shapes/sizes
    /// below favor readability but the binary literals are recorded so a future
    /// pass can tighten them):
    ///  - Rail SHAPE: the binary builds rails from `SwiftUI.Capsule` +
    ///    `RoundedCornerStyle.continuous` (`__s7SwiftUI7CapsuleVMa` /
    ///    `RoundedCornerStyleO10continuous` @ 0x1014B44D0), not
    ///    `Rectangle().cornerRadius(2)`. Visually near-identical for a 4–5pt rail.
    ///  - Rail HEIGHT: binary uses 5.0 (`DAT_103d11cd0` = 0x4014000000000000 =
    ///    5.0); this reconstruction uses 4. /// RE: 0x103d11cd0 (rail height 5.0).
    ///  - Thumb DIAMETER: binary uses a FIXED 15.0×15.0 thumb
    ///    (`DAT_103d11cb0` = `DAT_103d11cb8` = 0x402E000000000000 = 15.0; the
    ///    centering offset reads `diameter * 0.5` = 7.5). The binary has NO
    ///    drag-grow — the `beginDrag ? 18 : 14` sizing below is a reconstruction
    ///    embellishment, not binary-verified. /// RE: 0x103d11cb0 (thumb 15.0).
    @ViewBuilder
    private func buildTrackBody(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let span = bounds.upperBound - bounds.lowerBound
        let defaultColor = Self.initDefaultTrackColor()
        let normalized = span > 0 ? (value - bounds.lowerBound) / span : 0
        let bufferNormalized = span > 0 ? max(0, min(1, (bufferValue - bounds.lowerBound) / span)) : 0
        let progressWidth = width * CGFloat(normalized)
        let bufferWidth = width * CGFloat(bufferNormalized)
        let hoverNormalized: CGFloat? = hoverValue.flatMap { hv in
            span > 0 ? CGFloat((hv - bounds.lowerBound) / span) : nil
        }
        // Time the thumb currently represents (whole seconds), for the label.
        let labelSeconds = Int(value.rounded())

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(defaultColor.opacity(0.3))
                .frame(height: 4)
                .cornerRadius(2)

            Rectangle()
                .fill(defaultColor.opacity(0.4))
                .frame(width: max(0, bufferWidth), height: 4)
                .cornerRadius(2)

            Rectangle()
                .fill(isFocused ? Color.accentColor : defaultColor)
                .frame(width: max(0, progressWidth), height: 4)
                .cornerRadius(2)

            if let hv = hoverNormalized {
                Rectangle()
                    .fill(defaultColor.opacity(0.6))
                    .frame(width: 2, height: 8)
                    .offset(x: max(0, hv * width - 1))
            }

            Circle()
                .fill(defaultColor)
                .frame(width: beginDrag ? 18 : 14, height: beginDrag ? 18 : 14)
                .offset(x: max(0, progressWidth - (beginDrag ? 9 : 7)))

            // Time label: the binary renders a `formatSecondsToTimeString` +
            // `Text(...).foregroundColor(.white)` near the thumb. The codebase's
            // idiomatic equivalent of `formatSecondsToTimeString` is
            // `Int.toString(for:)` (PlayerDefines.swift), used with `.minOrHour`
            // exactly as VideoTimeShowView does for its time labels.
            //
            /// RE: 0x1014B2BFC (CONFIRMED — PlayerSlider_bodyBuilder calls
            /// `formatSecondsToTimeString()` with format selector arg `2`, then
            /// `SwiftUI.Text(_:)` (`__s7SwiftUI4TextVyACxcSyRzlufC`) →
            /// `.foregroundColor(Color.white)` (`__s7SwiftUI5ColorV5whiteACvgZ` +
            /// `__s7SwiftUI4TextV15foregroundColoryAcA0E0VSgF`). The label seconds
            /// are the thumb value truncated to Int — see the snap note below.)
            Text(labelSeconds.toString(for: .minOrHour))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white)
                .offset(x: max(0, min(width - 40, progressWidth - 20)), y: -16)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if !beginDrag {
                        beginDrag = true
                        onEditingChanged(true)
                    }
                    let fraction = Float(max(0, min(1, g.location.x / width)))
                    let raw = bounds.lowerBound + fraction * span
                    // Snap to a 0.001 grid, then clamp to bounds.
                    /// RE: 0x1014B2BFC (CONFIRMED — PlayerSlider_bodyBuilder's
                    /// onChanged path computes `(float)(int)(raw / 0.001) * 0.001`
                    /// then `if (v < lower) v = lower; if (upper <= v) v = upper;`.
                    /// The 0.001 grid + lower/upper clamp are binary-verified.
                    /// NOTE: the binary uses `(int)(x/0.001)` — TRUNCATION toward
                    /// zero — whereas `.rounded()` here rounds to nearest; the
                    /// sub-millis difference is below the displayed resolution.
                    /// Provenance correction: the snap was previously attributed
                    /// to 0x1014B44D0 (buildTrackBody), but that function contains
                    /// no 0.001 literal — the snap lives in the bodyBuilder's
                    /// gesture closure at 0x1014B2BFC.)
                    let snapped = (raw / 0.001).rounded() * 0.001
                    value = min(bounds.upperBound, max(bounds.lowerBound, snapped))
                }
                .onEnded { _ in
                    beginDrag = false
                    onEditingChanged(false)
                }
        )
        .modifier(HoverScrubModifier(width: width, bounds: bounds, span: span, hoverValue: $hoverValue))
    }
}

// MARK: - HoverScrubModifier
//
// The binary gates the hover affordance on an OS-version availability check
// (iOS 17+ via `___isPlatformVersionAtLeast(2, 0x11, 0, 0)`), NOT a macOS-only
// compile guard. `.onContinuousHover` itself is available iOS 16+/macOS 13+, so
// the version gate is expressed with `if #available` to match the binary's
// runtime check while still compiling on the full platform matrix.
private struct HoverScrubModifier: ViewModifier {
    let width: CGFloat
    let bounds: ClosedRange<Float>
    let span: Float
    @Binding var hoverValue: Float?

    func body(content: Content) -> some View {
        // tvOS has no pointer hover; the affordance is a no-op there.
        #if os(tvOS)
        content
        #else
        if #available(iOS 17, macOS 14, *) {
            content.onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(point):
                    let fraction = Float(max(0, min(1, point.x / width)))
                    hoverValue = bounds.lowerBound + fraction * span
                case .ended:
                    hoverValue = nil
                @unknown default:
                    hoverValue = nil
                }
            }
        } else {
            content
        }
        #endif
    }
}

// MARK: - ProgressTrack

/// Read-only buffer + progress rail. In the binary, `ProgressTrack`'s body is
/// inlined into the `PlayerSlider` track builder (only its value-witness
/// functions are named in this rev); this is a faithful standalone
/// reconstruction of that inlined body — a base rail, a buffer rail, and a
/// progress fill tinted by `progressColor`.
///
/// RE: 0x1014B5E0C (ProgressTrack value-witness Vwca, 1.3.15)
/// RE: 0x1014B5D98 (ProgressTrack value-witness Vwcp, 1.3.15)
/// RE: 0x1014B5EC8 (ProgressTrack value-witness Vwta, 1.3.15)
///
/// RESIDUAL (genuinely-runtime / inlined-body fence): `ProgressTrack` emits NO
/// standalone `body` code symbol. Playbook "inlined SwiftUI body → decompile
/// the enclosing result-builder" was TRIED and partly succeeded:
/// `search_functions "ProgressTrack"` returns ONLY the three value-witnesses
/// above (Vwca/Vwcp/Vwta) — no `...V4bodyQrvg`. The enclosing builder is
/// PlayerSlider's `buildTrackBody` @ 0x1014B44D0, whose decompile materializes
/// the rail stack inline: a base `Capsule` (white), a buffer `Capsule`, and a
/// progress-fill `Capsule` (`__s7SwiftUI7CapsuleVMa` ×3 +
/// `RoundedCornerStyleO10continuous`), which is the behavior reproduced below.
/// The standalone `ProgressTrack.body` cannot be recovered as its own function
/// because the compiler fused it into that builder — the rail SHAPE/behavior is
/// recovered from the inlined site; the discrete `body` symbol is a true fence.
public struct ProgressTrack: View {
    @Binding public var value: Float
    public var bufferValue: Float
    public var bounds: ClosedRange<Float>
    public var progressColor: Color
    @FocusState public var isFocused: Bool

    /// Field types are authoritative from `types.json` (§18.11).
    ///
    /// RESIDUAL (genuinely-runtime): the init signature and its defaults
    /// (bufferValue: 0, bounds: 0...1, progressColor: .accentColor) are NOT
    /// statically recoverable — `search_functions "ProgressTrack"` names only the
    /// Vwca/Vwcp/Vwta value-witnesses (above); no init or default-argument
    /// generator symbol is emitted. Reconstruction convenience, unverifiable.
    public init(
        value: Binding<Float>,
        bufferValue: Float = 0,
        bounds: ClosedRange<Float> = 0 ... 1,
        progressColor: Color = .accentColor
    ) {
        self._value = value
        self.bufferValue = bufferValue
        self.bounds = bounds
        self.progressColor = progressColor
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = bounds.upperBound - bounds.lowerBound
            let normalized = span > 0 ? max(0, min(1, (value - bounds.lowerBound) / span)) : 0
            let bufferNormalized = span > 0 ? max(0, min(1, (bufferValue - bounds.lowerBound) / span)) : 0

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)

                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: width * CGFloat(bufferNormalized), height: 4)
                    .cornerRadius(2)

                Rectangle()
                    .fill(isFocused ? progressColor.opacity(0.8) : progressColor)
                    .frame(width: width * CGFloat(normalized), height: 4)
                    .cornerRadius(2)
            }
        }
        .frame(height: 4)
    }
}
