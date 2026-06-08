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
/// RE: 0x1013C1FA8 (ControllerTimeModel.init, 0x11C = 284 bytes, 1.3.15)
public class ControllerTimeModel: ObservableObject {
    // §18.9 field 1: `_currentTime`, Combine.Published<Swift.Int>, default 0.
    // Int-quantized so the model does not update on every frame.
    @Published
    public var currentTime = 0
    // §18.9 field 2: `_totalTime`, Combine.Published<Swift.Int>, default 1.
    @Published
    public var totalTime = 1
    // §18.9 field 3: `_bufferTime`, Combine.Published<Swift.Int>, default 0.
    @Published
    public var bufferTime = 0
    // §18.9 field 4: `fileSize`, Swift.Int64, default 1.
    // Plain stored Int64 (NOT @Published in the binary); init sets it to 1.
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
    /// not record an init signature. The default arguments below
    /// (bufferValue: 0, bounds: 0...1, onEditingChanged: { _ in }) are a
    /// reconstruction convenience and are NOT binary-verified.
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
    /// from a white `Color` plus per-rail opacity). The binary factors this out
    /// into a separate function, so it is preserved as a discrete helper rather
    /// than inlined (API Surface Preservation).
    ///
    /// RE: 0x1008EAC60 (PlayerSlider_initDefaultTrackColor, 1.3.15)
    private static func initDefaultTrackColor() -> Color {
        Color.white
    }

    /// RE: 0x1014B2BFC (PlayerSlider_bodyBuilder, 1.3.15)
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
                    // Snap to a 0.001 grid, then clamp to bounds (matches the
                    // binary's thumb-position quantization at 0x1014B44D0).
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
public struct ProgressTrack: View {
    @Binding public var value: Float
    public var bufferValue: Float
    public var bounds: ClosedRange<Float>
    public var progressColor: Color
    @FocusState public var isFocused: Bool

    /// Field types are authoritative from `types.json` (§18.11). The init
    /// signature is a reconstruction convenience (the rev names only
    /// value-witness functions).
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
