//
//  VideoSubtitleView.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — VideoSubtitleView_buildSubtitleBody at
//  0x10149C7D4. SwiftUI overlay that renders the dual-track subtitle
//  display: primary (bottom) + secondary (top, populated by translation
//  or explicit secondary subtitle selection). HDR routing is driven by
//  `SubtitleModel.useHDREffect`; the HDR-aware compositing for image
//  subtitles is handled by `SubtitleBackgroundImageView` /
//  `MetalSubtitleView`.
//

import CoreGraphics
import SwiftUI
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
/// Each part is dispatched to the documented per-part surfaces:
/// `SubtitleLeftView` for image subtitles (bitmap / ASS-image) and
/// `SubtitleRightView` for attributed text. HDR compositing for image
/// subtitles is gated on `SubtitleModel.useHDREffect` — the binary reads
/// the dynamic-range decision from the model, not a view-held field.
///
/// RE: `types.json` roster — `VideoSubtitleView` has exactly one stored
/// field, `_model :: ObservedObject<KSPlayer.SubtitleModel>`.
public struct VideoSubtitleView: View {
    @ObservedObject public var model: SubtitleModel

    public init(model: SubtitleModel) {
        self.model = model
    }

    public var body: some View {
        buildSubtitleBody()
    }

    /// RE: VideoSubtitleView_buildSubtitleBody @ 0x10149C7D4 (1.3.15). The
    /// body is split into the two ForEach branches so each track can carry
    /// its own alignment without interfering with the other. Each part is
    /// rendered through the documented `SubtitleLeftView` (image) /
    /// `SubtitleRightView` (text) surfaces — the bodies of those two helper
    /// views are inlined into this builder in the binary.
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
            subtitlePartContent(part, position: part.textPosition ?? defaultPrimaryPosition)
        }
    }

    @ViewBuilder
    private var secondarySubtitleStack: some View {
        ForEach(model.secondParts) { part in
            subtitlePartContent(part, position: part.textPosition ?? defaultSecondaryPosition)
        }
    }

    /// Dispatch a single `SubtitlePart` to the documented per-part surface.
    /// The binary renders image subtitles via `SubtitleLeftView`
    /// (`SubtitleImageInfo` + `isHDR`) and text subtitles via
    /// `SubtitleRightView` (`NSAttributedString` + `TextPosition` +
    /// `screenWidth`), inlining both into `buildSubtitleBody`.
    ///
    /// The text branch is rendered inline (the binary inlines the
    /// `SubtitleRightView` body) because the project's existing
    /// `SubtitleRightView` (Sources/KSPlayer/SwiftUI/SubtitleRightView.swift)
    /// carries a `String` payload, whereas the documented surface takes an
    /// `NSAttributedString`. See the CROSS-FILE note in this cluster's
    /// reconstruction report.
    @ViewBuilder
    private func subtitlePartContent(_ part: SubtitlePart, position: TextPosition) -> some View {
        Group {
            if let image = part.image, let cgImage = cgImage(from: image) {
                let info = SubtitleImageInfo(
                    rect: imageRect(for: image, origin: part.origin),
                    image: cgImage,
                    displaySize: image.size
                )
                SubtitleLeftView(
                    info: info,
                    isHDR: SubtitleModel.useHDREffect
                )
            } else if let text = part.text {
                Text(AttributedString(text))
                    .foregroundColor(SubtitleModel.effectiveTextColor)
                    .multilineTextAlignment(textAlignment(for: position))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SubtitleModel.effectiveBackgroundColor)
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: alignment(for: position))
        .padding(position.edgeInsets)
    }

    /// Extract the backing `CGImage` from the `UIImage`/`NSImage` typealias.
    /// Platform guard rationale: `UIImage` exposes a no-arg `cgImage`
    /// property, while `NSImage` only offers
    /// `cgImage(forProposedRect:context:hints:)`.
    private func cgImage(from image: UIImage) -> CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #else
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    /// Derive the display rect for a bitmap subtitle. When the part carries
    /// an explicit origin, anchor there; otherwise fall back to a
    /// size-only rect (the host frame modifier handles placement).
    private func imageRect(for image: UIImage, origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: image.size)
    }

    private func textAlignment(for position: TextPosition) -> TextAlignment {
        switch position.horizontalAlign {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func alignment(for position: TextPosition) -> Alignment {
        Alignment(horizontal: position.horizontalAlign, vertical: position.verticalAlign)
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

/// SwiftUI surface that renders an **image** subtitle (bitmap / ASS-image
/// branch) carrying an HDR flag.
///
/// RE: `types.json` roster — `SubtitleLeftView` has exactly two fields:
/// `info :: KSPlayer.SubtitleImageInfo` and `isHDR :: Swift.Bool`. Only
/// its value-witness function is named in the binary
/// (`SubtitleLeftView…Vwca @ 0x10149A8C8`); the body is inlined into
/// `VideoSubtitleView_buildSubtitleBody`. When `isHDR` is set, the HDR/HLG
/// exposure-adjusted compositing is delegated to
/// `SubtitleBackgroundImageView`, which routes through
/// `createHDR_HLG_ExposureAdjustedCGImage`.
public struct SubtitleLeftView: View {
    public var info: SubtitleImageInfo
    public var isHDR: Bool

    public init(info: SubtitleImageInfo, isHDR: Bool) {
        self.info = info
        self.isHDR = isHDR
    }

    public var body: some View {
        SubtitleBackgroundImageView(info: info, isHDR: isHDR)
    }
}

/// Forward-specific SwiftUI surface that renders an HDR/HLG-aware
/// background image behind subtitle overlays for Dolby Vision content. Not
/// present in upstream KSPlayer.
///
/// RE: body getter @ 0x10149aa60 (1.3.15, 1640B). Not in `types.json` /
/// `class_addr_map.json` (standard for SwiftUI View structs without
/// runtime reflection metadata). The body reads the stored
/// `SubtitleImageInfo` geometry and a boolean HDR flag, then:
///   1. HDR path  — `createHDR_HLG_ExposureAdjustedCGImage` →
///      `Image(decorative:scale:orientation:)`.
///   2. non-HDR   — source `CGImage` directly via `Image(decorative:)`.
/// Both call `.resizable(capInsets:resizingMode:.stretch)`. On iOS 17+ the
/// HDR branch additionally applies `Image.dynamicRange(.high)`. Frame
/// sizing/position come from the `SubtitleImageInfo` geometry rect
/// (width/height + midX/midY).
public struct SubtitleBackgroundImageView: View {
    public var info: SubtitleImageInfo
    public var isHDR: Bool

    public init(info: SubtitleImageInfo, isHDR: Bool) {
        self.info = info
        self.isHDR = isHDR
    }

    public var body: some View {
        // Frame sizing via CGRectGetWidth/Height; position via
        // CGRectGetMidX/MidY of the SubtitleImageInfo geometry rect.
        sizedImage
            .frame(width: info.rect.width,
                   height: info.rect.height,
                   alignment: .center)
            .position(x: info.rect.midX, y: info.rect.midY)
    }

    /// RE: `_ConditionalContent<Image, ModifiedImage>` selecting between
    /// the plain resizable image (non-HDR or pre-iOS 17) and the
    /// dynamic-range-modified image (HDR + iOS 17).
    @ViewBuilder
    private var sizedImage: some View {
        let base = resizableImage
        // Platform guard rationale: `Image.dynamicRange(_:)` is iOS 17.0+
        // (and tvOS/macOS 14+); on earlier OSes there is no HDR image
        // modifier, so the plain resizable image is used. RE branch:
        // `__isPlatformVersionAtLeast(2, 0x11, 0, 0)` = iOS 17.0,
        // helper FUN_10149b16c @ 0x10149b16c.
        if isHDR {
            #if os(iOS) || os(tvOS) || os(macOS)
            if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
                base.dynamicRange(.high)
            } else {
                base
            }
            #else
            base
            #endif
        } else {
            base
        }
    }

    /// Resolve the source image (HDR-adjusted when the flag is set) and
    /// wrap it as a resizable, stretch-tiled `SwiftUI.Image`.
    private var resizableImage: Image {
        decorativeImage
            .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
    }

    /// HDR path → exposure-adjusted CGImage; non-HDR path → source CGImage.
    /// Both wrap via `Image(decorative:scale:orientation:)`.
    private var decorativeImage: Image {
        if isHDR,
           let adjusted = createHDR_HLG_ExposureAdjustedCGImage(info.image) {
            return Image(decorative: adjusted, scale: 1.0, orientation: .up)
        }
        return Image(decorative: info.image, scale: 1.0, orientation: .up)
    }
}

/// Produce an HLG exposure-adjusted `CGImage` for an HDR subtitle
/// background image.
///
/// RE: 0x1013cefe8 (1.3.15, 340B). Sole caller is the
/// `SubtitleBackgroundImageView` body getter @ 0x10149aa60. This is an
/// **independent** helper, distinct from `MetalSubtitleView`'s
/// `CIFilter.exposureAdjustFilter` (`DAT_10445876c`) path — per the
/// API-surface-preservation rule it is kept as a separate function and is
/// not fused into the MetalSubtitleView exposure path.
///
/// Six steps (any failure → nil):
///  1. `CGColorSpace(name: kCGColorSpaceITUR_2100_HLG)`.
///  2. `CIImage(cgImage:)` from the input.
///  3. `CIFilter` exposure-adjust, set `inputEV` (`setEV:`).
///  4. read `outputImage` from the filter.
///  5. `CIContext.createCGImage(_:fromRect:format:colorSpace:)` with
///     `kCIFormatRGBAf` (`CIFormat.RGBAf`) and the HLG color space.
///  6. return the exposure-adjusted CGImage.
private func createHDR_HLG_ExposureAdjustedCGImage(_ source: CGImage) -> CGImage? {
    #if canImport(CoreImage)
    // 1. HLG (Rec. 2100) color space.
    guard let hlgColorSpace = CGColorSpace(name: CGColorSpace.itur_2100_HLG) else {
        return nil
    }
    // 2. CIImage from the source CGImage.
    let inputImage = CIImage(cgImage: source)
    // 3. Exposure-adjust filter; set the EV parameter.
    guard let filter = CIFilter(name: "CIExposureAdjust") else {
        return nil
    }
    filter.setValue(inputImage, forKey: kCIInputImageKey)
    filter.setValue(hlgExposureEV, forKey: kCIInputEVKey)
    // 4. Output image.
    guard let outputImage = filter.outputImage else {
        return nil
    }
    // 5. Render to a CGImage in the HLG color space with float RGBA.
    let context = CIContext(options: nil)
    guard let result = context.createCGImage(
        outputImage,
        from: outputImage.extent,
        format: CIFormat.RGBAf,
        colorSpace: hlgColorSpace
    ) else {
        return nil
    }
    // 6. Exposure-adjusted CGImage.
    return result
    #else
    return nil
    #endif
}

/// Exposure value applied by `createHDR_HLG_ExposureAdjustedCGImage`. The
/// 1.3.15 binary drives the EV from the HDR-brightness global; this mirrors
/// the neutral default used by the background-image path before any
/// runtime override is applied.
private var hlgExposureEV: Double { 0.0 }
