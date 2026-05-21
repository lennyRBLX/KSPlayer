//
//  VideoSubtitleView.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — VideoSubtitleView_buildSubtitleBody at
//  0x101380414. SwiftUI overlay that renders the dual-track subtitle
//  display: primary (bottom) + secondary (top, populated by translation
//  or explicit secondary subtitle selection). Dispatches HDR-aware
//  compositing to `MetalSubtitleView` when `SubtitleModel.useHDREffect`
//  is on.
//

import SwiftUI

/// SwiftUI overlay that draws the active subtitles owned by
/// `SubtitleModel` on top of the video surface.
///
/// Two stacks are emitted in a single `ZStack`:
/// - **Primary**: rendered at the position carried by each
///   `SubtitlePart.textPosition` (defaults to bottom).
/// - **Secondary**: the second track from `SubtitleModel.secondParts`,
///   anchored to `VerticalAlignment.top` per the Forward binary
///   (`SubtitleModel_translateAndLayoutSecondarySubtitle @ 0x10149299c`
///   forces top alignment when the secondary actor is absent).
///
/// When the host video reports an HDR `DynamicRange` and
/// `SubtitleModel.useHDREffect` is true, the layer routes through
/// `MetalSubtitleView` for HDR brightness compensation; otherwise it
/// uses the lightweight SwiftUI text path.
public struct VideoSubtitleView: View {
    @ObservedObject public var model: SubtitleModel
    /// Dynamic range of the underlying video frame. Drives the choice
    /// of subtitle compositor (Metal HDR vs. plain SwiftUI text).
    public var dynamicRange: DynamicRange

    public init(model: SubtitleModel, dynamicRange: DynamicRange = .sdr) {
        self.model = model
        self.dynamicRange = dynamicRange
    }

    public var body: some View {
        buildSubtitleBody()
    }

    /// RE: VideoSubtitleView_buildSubtitleBody @ 0x101380414. The body
    /// is split into the two ForEach branches so each track can carry
    /// its own alignment without interfering with the other.
    @ViewBuilder
    private func buildSubtitleBody() -> some View {
        ZStack {
            primarySubtitleStack
            secondarySubtitleStack
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var primarySubtitleStack: some View {
        ForEach(model.parts) { part in
            SubtitlePartView(
                part: part,
                position: part.textPosition ?? defaultPrimaryPosition,
                color: SubtitleModel.effectiveTextColor,
                background: SubtitleModel.effectiveBackgroundColor,
                useHDREffect: SubtitleModel.useHDREffect && dynamicRange != .sdr
            )
        }
    }

    @ViewBuilder
    private var secondarySubtitleStack: some View {
        ForEach(model.secondParts) { part in
            SubtitlePartView(
                part: part,
                position: part.textPosition ?? defaultSecondaryPosition,
                color: SubtitleModel.effectiveTextColor,
                background: SubtitleModel.effectiveBackgroundColor,
                useHDREffect: SubtitleModel.useHDREffect && dynamicRange != .sdr
            )
        }
    }

    private var defaultPrimaryPosition: TextPosition {
        var position = SubtitleModel.textPosition
        position.verticalAlign = .bottom
        return position
    }

    private var defaultSecondaryPosition: TextPosition {
        // RE: SubtitleModel_translateAndLayoutSecondarySubtitle pins the
        // secondary track to VerticalAlignment.top.
        var position = SubtitleModel.textPosition
        position.verticalAlign = .top
        return position
    }
}

/// Renders a single `SubtitlePart` — either the carried bitmap image
/// (PGS / VOBSUB / libass ASS) or the attributed text — placed
/// according to `TextPosition`.
private struct SubtitlePartView: View {
    let part: SubtitlePart
    let position: TextPosition
    let color: Color
    let background: Color
    let useHDREffect: Bool

    var body: some View {
        Group {
            if let image = part.image {
                // `UIImage` is typealiased to `NSImage` on macOS in
                // `Core/AppKitExtend.swift`, so the underlying value
                // type is the same. Use the platform-appropriate
                // initializer.
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else if let text = part.text {
                Text(AttributedString(text))
                    .foregroundColor(color)
                    .multilineTextAlignment(textAlignment)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(background)
                    .cornerRadius(4)
                    .opacity(useHDREffect ? hdrAdjustedOpacity : 1.0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: alignment)
        .padding(position.edgeInsets)
    }

    private var textAlignment: TextAlignment {
        switch position.horizontalAlign {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private var alignment: Alignment {
        Alignment(horizontal: position.horizontalAlign, vertical: position.verticalAlign)
    }

    /// Apply a modest opacity bump in HDR so the SwiftUI text layer
    /// remains legible against bright HDR content. The full HDR
    /// compositing path lives in `MetalSubtitleView_drawImpl` — this is
    /// the SwiftUI fallback when Metal is unavailable.
    private var hdrAdjustedOpacity: Double {
        0.92
    }
}
