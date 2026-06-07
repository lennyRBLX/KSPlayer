//
//  MetalSubtitleView.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — MetalSubtitleView_drawImpl at 0x10149ee10
//  Metal-rendered HDR-aware subtitle compositing view using CIContext + CIRenderDestination.
//  Supports SDR, HDR10/PQ, HLG, and Dolby Vision color spaces with exposure/brightness
//  adjustment for subtitle legibility in HDR content.
//

#if canImport(Metal) && canImport(MetalKit) && canImport(CoreImage)
import Combine
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Metal
import MetalKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - CIImageRender

/// Element type of `MetalSubtitleView.imageInfos`.
///
/// RE: residual type — `CIImageRender` is referenced as the element type of
/// `MetalSubtitleView.imageInfos` (`[CIImageRender]`, ivar table line 1026 and
/// Hard Constraint (c)) but carries no Swift reflection metadata in the 1.3.15
/// binary (`search_functions "CIImageRender"` / `"11CIImageRender"` /
/// `"CIImageRenderV"` all return none). The layout is recovered from usage: the
/// "CIImage + draw position" pairing produced by `layoutSubtitleParts` and
/// consumed by `drawImpl` (which iterates the array at a 0x28 = 40-byte struct
/// stride, consistent with a struct, not an ad-hoc tuple).
// TODO(re-verify): CIImageRender layout (no Ghidra reflection, doc §1774-1782).
public struct CIImageRender {
    /// Rendered subtitle image (text rasterization or bitmap subtitle).
    public var image: CIImage
    /// Bottom-left draw origin in drawable (pixel) coordinates.
    public var position: CGPoint

    public init(image: CIImage, position: CGPoint) {
        self.image = image
        self.position = position
    }
}

/// Metal-rendered subtitle compositing view with HDR-aware brightness correction.
///
/// Uses CIContext + CIRenderDestination (not a traditional render pipeline) to composite
/// subtitle images and rendered text onto a CAMetalLayer drawable. Supports SDR and HDR
/// output with per-subtitle exposure adjustment.
///
/// RE: MTKView subclass, drawImpl at 0x10149ee10 (1340 bytes).
public class MetalSubtitleView: MTKView, MTKViewDelegate {

    // MARK: - Properties
    //
    // Ivar order matches the `types.json` stored-property list for
    // `KSPlayer.MetalSubtitleView : MTKView` (doc §1016-1027) and the
    // drawImpl / layoutSubtitleParts decompiles:
    //   1 cancellables  2 ciContext  3 commandQueue  4 labelMap  5 parts
    //   6 playRatio     7 playerContentMode  8 dynamicRange  9 imageInfos
    //   10 textInfos

    private var cancellables = Set<AnyCancellable>()
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?

    /// Per-line subtitle labels keyed by their line string.
    ///
    /// RE: ivar #4 `labelMap: [String: PaddedLabel]` — read in
    /// `MetalSubtitleView_layoutSubtitleParts @ 0x101498248`. Maps a line key to
    /// the reusable `PaddedLabel` instance used while laying out text parts.
    private var labelMap: [String: PaddedLabel] = [:]

    /// Raw subtitle parts to render.
    public var parts: [SubtitlePart] = [] {
        didSet {
            updateImageInfos()
        }
    }

    /// Play resolution ratio for ASS coordinate mapping.
    public var playRatio: Double = 1.0

    /// Aspect-fit vs aspect-fill scaling mode for subtitle layout.
    ///
    /// RE: ivar #7 `playerContentMode: __C.ContentMode`, default `.scaleAspectFit`
    /// (raw 1). Drives the aspect-fit/aspect-fill branch in
    /// `layoutSubtitleParts` / `drawImpl`.
    public var playerContentMode: UIViewContentMode = .scaleAspectFit

    /// Current dynamic range of the video content.
    public var dynamicRange: DynamicRange = .sdr {
        didSet {
            updateLayerForDynamicRange()
        }
    }

    /// Computed CIImage + position renders ready for compositing.
    ///
    /// RE: ivar #9 `imageInfos: [CIImageRender]` (doc §1026, Hard Constraint c).
    private var imageInfos: [CIImageRender] = []

    /// Per-track text info handed to the SwiftUI text-subtitle surface.
    ///
    /// RE: ivar #10 `textInfos: [SubtitleTextInfo]` (Hard Constraint c). The view
    /// holds BOTH `imageInfos` (bitmap/rasterized renders) and `textInfos` (the
    /// attributed-text descriptors used by `VideoSubtitleView`/`SubtitleRightView`).
    public var textInfos: [SubtitleTextInfo] = []

    /// HDR subtitle exposure value (EV). 0 = no adjustment.
    ///
    /// RE: Forward v1.3.15 reads the HDR-EV value from the global `DAT_10445876c`
    /// (Float) — the only HDR-EV global in the binary with live xrefs from
    /// `MetalSubtitleView_drawImpl @ 0x10149ee10`, `renderTextSubtitleToCIImage
    /// @ 0x10149f590`, written by `sub_1009119EC` / `FUN_100a1bd64`. It is NOT one
    /// of the 10 documented MetalSubtitleView ivars, so it is modeled here as a
    /// type-level (global) value rather than a stored instance field to preserve
    /// the documented 10-ivar layout.
    /// (Earlier RE notes named `0x1041F766C` `g_subtitleImageEV`; that address has
    /// zero xrefs in the Ghidra database and has been retired — see
    /// `.reversal/SubtitleSystem.md`.)
    public static var subtitleImageEV: Float = 0.0

    // MARK: - Initialization

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        super.init(frame: .zero, device: device)
        setup()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        initDefaultsFatalError()
        guard let device = self.device ?? MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        commandQueue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        ])
        delegate = self
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        #if canImport(UIKit)
        isOpaque = false
        backgroundColor = .clear
        #else
        layer?.isOpaque = false
        #endif
    }

    /// RE: MetalSubtitleView_initDefaults_fatalError at 0x10149e958 (LIVE)
    ///
    /// The Swift designated/required-init defaults routine. In the binary this is
    /// the entry guarded by the `fatalError` path emitted for the unavailable
    /// `init(frame:device:)` / `init(coder:)` overload pair: it seeds the stored
    /// defaults (`playRatio = 1.0`, `playerContentMode = .scaleAspectFit`,
    /// `dynamicRange = .sdr`, empty `labelMap`/`imageInfos`/`textInfos`) before the
    /// MTKView super-init completes. Reconstructed as an explicit defaults seed so
    /// the designated initializers share one source of truth.
    private func initDefaultsFatalError() {
        playRatio = 1.0
        playerContentMode = .scaleAspectFit
        dynamicRange = .sdr
        labelMap.removeAll(keepingCapacity: true)
        imageInfos.removeAll(keepingCapacity: true)
        textInfos.removeAll(keepingCapacity: true)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Layout recalculation on resize
        updateImageInfos()
    }

    public func draw(in view: MTKView) {
        drawImpl()
    }

    // MARK: - Core Rendering

    /// RE: MetalSubtitleView_drawImpl at 0x10149ee10 (1340B)
    ///
    /// Driven from the `drawInMTKView:` MTKViewDelegate callback. Iterates
    /// `imageInfos` (0x28-byte stride); for each element the binary dispatches a
    /// vtable callback `(**(code **)(pcVar3 + 0x10))(...)` that resolves to
    /// `renderTextSubtitleToCIImage_thunk@0x10149ffc4` ->
    /// `renderTextSubtitleToCIImage@0x10149f590` (steps 6a-6b). After the
    /// per-element call returns, drawImpl itself applies Layer 1 HDR exposure
    /// (step 6c) and the final render-to-destination (step 6d), then presents and
    /// commits.
    private func drawImpl() {
        guard let drawable = currentDrawable,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciContext
        else { return }

        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        guard width > 0, height > 0 else { return }

        let destination = CIRenderDestination(
            width: width,
            height: height,
            pixelFormat: colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { [weak self] () -> MTLTexture in
                // RE: textureProviderBlock @ 0x1014a01cc — the mtlTextureProvider
                // block body; forwards to getDrawableTexture (0x10149f34c).
                self?.getDrawableTexture(from: drawable) ?? drawable.texture
            }
        )

        // Clear the destination
        do {
            try ciContext.startTask(toClear: destination)
        } catch {
            return
        }

        // Render each subtitle element
        for info in imageInfos {
            var subtitleImage = info.image

            // Apply HDR exposure (Layer 1) for non-SDR content.
            // RE: bitmask logic inside drawImpl @ 0x10149ee10 (doc §1238-1248):
            //   (0xE >> (dynamicRange & 0xF)) & 1
            // 0xE = 0b1110 -> bit set for dynamicRange 1/2/3 (HDR10/HLG/DV), clear for 0 (SDR).
            let needsHDRAdjust = (0xE >> (dynamicRange.rawValue & 0xF)) & 1 == 1

            if needsHDRAdjust, Self.subtitleImageEV != 0 {
                subtitleImage = applyExposureAdjust(to: subtitleImage, ev: Self.subtitleImageEV)
            }

            do {
                try ciContext.startTask(
                    toRender: subtitleImage,
                    from: subtitleImage.extent,
                    to: destination,
                    at: info.position
                )
            } catch {
                continue
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// RE: MetalSubtitleView_getDrawableTexture at 0x10149f34c (192B, LIVE)
    ///
    /// Returns the `MTLTexture` backing the current drawable. In the binary this
    /// is a standalone accessor invoked from the `mtlTextureProvider` block
    /// (`textureProviderBlock @ 0x1014a01cc`); the source previously inlined the
    /// `drawable.texture` access into the closure.
    private func getDrawableTexture(from drawable: CAMetalDrawable) -> MTLTexture {
        drawable.texture
    }

    // MARK: - Layout

    /// Convert subtitle parts into renderable `CIImageRender` values.
    ///
    /// RE: The Forward binary has no standalone Ghidra entry for
    /// "MetalSubtitleView_layoutAndUpdateImageInfos" — the symbol at
    /// `0x101382710` that Ghidra labelled with that name is a misnamed 36-byte
    /// `AVRoutePickerView` allocation thunk (AirPlay route picker) unrelated to
    /// subtitle layout. The real layout pipeline lives in
    /// `MetalSubtitleView_layoutSubtitleParts @ 0x101498248`; this private helper
    /// is the bitmap/text fan-out that feeds it from the `parts` array.
    private func updateImageInfos() {
        let scale = contentScaleFactor
        imageInfos = layoutSubtitleParts(
            width: drawableSize.width,
            height: drawableSize.height,
            scale: scale,
            playerContentMode: playerContentMode,
            subtitleParts: parts
        )
        #if canImport(UIKit)
        setNeedsDisplay()
        #else
        needsDisplay = true
        #endif
    }

    /// RE: MetalSubtitleView_layoutSubtitleParts at 0x101498248 (4888B, LIVE)
    ///
    /// Takes 5 params (width, height, scale, content-mode, subtitleParts) and
    /// iterates the parts array (0x30-byte stride). Branches on the per-part
    /// flag `uStack_10e & 0x100000000000000` — if set, takes the text path (via
    /// `FUN_101496e4c`, the text-render dispatch that resolves to
    /// `renderTextSubtitleToCIImage`); otherwise the image-subtitle path computes
    /// aspect-fit scaling `min(width/imageWidth, height/imageHeight)`, reads the
    /// global scale factor `DAT_103d097b0` (default 1.0), and applies the position
    /// offsets `DAT_1044587f0` (X) / `DAT_1044587f8` (Y). 3 xrefs incl.
    /// `VideoSubtitleView_buildSubtitleBody`.
    private func layoutSubtitleParts(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        playerContentMode: UIViewContentMode,
        subtitleParts: [SubtitlePart]
    ) -> [CIImageRender] {
        guard width > 0, height > 0 else { return [] }

        // DAT_103d097b0 — subtitle scale factor (bytes verified == 1.0).
        let globalScale = MetalSubtitleView.subtitleScaleFactor
        // DAT_1044587f0 / DAT_1044587f8 — subtitle X / Y position offsets.
        let offsetX = MetalSubtitleView.subtitlePositionOffsetX
        let offsetY = MetalSubtitleView.subtitlePositionOffsetY

        var renders: [CIImageRender] = []
        renders.reserveCapacity(subtitleParts.count)

        for part in subtitleParts {
            // Text path: the per-part flag (uStack_10e & 0x1<<56) selects text
            // rendering. In the reconstruction the discriminator is "has text and
            // no bitmap image", which maps to the same dispatch.
            let isTextPart = part.image == nil && part.text != nil

            if isTextPart, let text = part.text {
                let position = part.textPosition ?? SubtitleModel.textPosition
                guard let ciImage = renderTextSubtitleToCIImage(
                    text,
                    width: width,
                    height: height,
                    scale: scale,
                    alignment: position.horizontalAlign,
                    fontScaleEnabled: true,
                    padding: SubtitleModel.textPosition.edgeInsets
                ) else { continue }

                var point = computeTextPosition(
                    for: part,
                    imageSize: ciImage.extent.size,
                    drawableWidth: width,
                    drawableHeight: height,
                    scale: scale
                )
                point.x += offsetX * scale
                point.y += offsetY * scale
                renders.append(CIImageRender(image: ciImage, position: point))
            } else if let uiImage = part.image, let cgImage = uiImage.cgImage {
                // Bitmap subtitle (PGS / VOBSUB / ASS image render).
                let ciImage = CIImage(cgImage: cgImage)

                // Aspect-fit scaling: min(width/imageWidth, height/imageHeight),
                // multiplied by the global scale factor and the content-mode rule.
                let imageWidth = ciImage.extent.width
                let imageHeight = ciImage.extent.height
                var fitScale = globalScale
                if imageWidth > 0, imageHeight > 0 {
                    let aspect = min(width / imageWidth, height / imageHeight)
                    // .scaleAspectFill uses max() instead of min(); aspect-fit (default) uses min().
                    if playerContentMode == .scaleAspectFill {
                        fitScale = max(width / imageWidth, height / imageHeight) * globalScale
                    } else if playerContentMode == .scaleToFill {
                        fitScale = globalScale
                    } else {
                        fitScale = aspect * globalScale
                    }
                }

                let rendered: CIImage = fitScale == 1.0
                    ? ciImage
                    : ciImage.transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))

                let position = CGPoint(
                    x: part.origin.x * scale + offsetX * scale,
                    y: height - part.origin.y * scale - rendered.extent.height + offsetY * scale
                )
                renders.append(CIImageRender(image: rendered, position: position))
            }
        }

        return renders
    }

    /// Compute position for a text subtitle based on its `TextPosition` alignment.
    private func computeTextPosition(
        for part: SubtitlePart,
        imageSize: CGSize,
        drawableWidth: CGFloat,
        drawableHeight: CGFloat,
        scale: CGFloat
    ) -> CGPoint {
        let position = part.textPosition ?? SubtitleModel.textPosition

        var x: CGFloat
        switch position.horizontalAlign {
        case .leading:
            x = position.leftMargin * scale
        case .trailing:
            x = drawableWidth - imageSize.width - position.rightMargin * scale
        default:
            x = (drawableWidth - imageSize.width) / 2
        }

        var y: CGFloat
        switch position.verticalAlign {
        case .top:
            y = drawableHeight - imageSize.height - position.verticalMargin * scale
        case .center:
            y = (drawableHeight - imageSize.height) / 2
        default: // bottom
            y = position.verticalMargin * scale
        }

        return CGPoint(x: x, y: y)
    }

    // MARK: - Text Rendering

    /// RE: renderTextSubtitleToCIImage at 0x10149f590 (932B, LIVE) — Ghidra `FUN_10149f590`
    ///
    /// Text-subtitle rendering ENTRY point. Takes width, height, scale, alignment
    /// enum, font-scale flag, padding. Returns nil when the attributed string is
    /// empty (`NSAttributedString.length == 0`). Calls `buildAttributedStringImage`
    /// (`0x10149f934`) to get the base `CIImage`. On iOS 17+
    /// (`__isPlatformVersionAtLeast(2, 0x11)`): reads the background-glow alpha
    /// from `DAT_1044587a0`; if alpha > 0 applies a rounded-rect background
    /// (radius = displayScale * 10.0) and translates the result with
    /// `CGAffineTransformMakeTranslation(+6, +3)`. If the HDR flag is set
    /// (`param_5 & 1`), reads `DAT_10445876c`, computes
    /// EV = `((DAT_10445876c + 1.0) / 1.5) * 0.7 + 0.3` and calls
    /// `applyHDRBrightnessAdjust`.
    private func renderTextSubtitleToCIImage(
        _ attributedString: NSAttributedString,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        alignment: HorizontalAlignment,
        fontScaleEnabled: Bool,
        padding: EdgeInsets
    ) -> CIImage? {
        // Empty-string guard (binary checks NSAttributedString.length).
        guard attributedString.length > 0 else { return nil }

        // Stage a: base attributed-string image.
        guard var result = buildAttributedStringImage(
            attributedString,
            width: width,
            height: height,
            scale: scale,
            alignment: alignment,
            fontScaleEnabled: fontScaleEnabled
        ) else { return nil }

        let displayScale = contentScaleFactor

        // Stage b: rounded-rect background glow (iOS 17+ / macOS 14+).
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            // DAT_1044587a0 — subtitle background-glow color.
            let glowColor = MetalSubtitleView.backgroundGlowColor
            let alpha = glowColor.cgColor.alpha
            if alpha > 0 {
                let radius = displayScale * 10.0
                let extent = result.extent.insetBy(dx: -CGFloat(padding.leading) - 6, dy: -CGFloat(padding.top) - 3)
                let ciColor = CIColor(cgColor: glowColor.cgColor)
                var background = CIImage(color: ciColor).cropped(to: extent)
                // Rounded-corner mask via CIFilter (Gaussian-rounded rect).
                if let rounded = CIFilter(name: "CIGaussianBlur") {
                    rounded.setValue(background, forKey: kCIInputImageKey)
                    rounded.setValue(radius, forKey: kCIInputRadiusKey)
                    background = rounded.outputImage?.cropped(to: extent) ?? background
                }
                result = result
                    .transformed(by: CGAffineTransform(translationX: 6, y: 3))
                    .composited(over: background)
            }
        }

        // Stage b': HDR brightness (Layer 2).
        let needsHDRAdjust = (0xE >> (dynamicRange.rawValue & 0xF)) & 1 == 1
        if needsHDRAdjust {
            result = applyHDRBrightnessAdjust(to: result)
        }

        return result
    }

    /// RE: renderTextSubtitleToCIImage thunk at 0x10149ffc4 (64B, LIVE, 2 DATA xrefs)
    ///
    /// Thin wrapper that tail-calls `0x10149f590`. It is the vtable callback target
    /// dispatched from `drawImpl` (`(**(code **)(pcVar3 + 0x10))(...)`). Kept as a
    /// separate forwarding function per the API-Surface-Preservation rule.
    private func renderTextSubtitleToCIImageThunk(
        _ attributedString: NSAttributedString,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        alignment: HorizontalAlignment,
        fontScaleEnabled: Bool,
        padding: EdgeInsets
    ) -> CIImage? {
        renderTextSubtitleToCIImage(
            attributedString,
            width: width,
            height: height,
            scale: scale,
            alignment: alignment,
            fontScaleEnabled: fontScaleEnabled,
            padding: padding
        )
    }

    /// RE: buildAttributedStringImage at 0x10149f934 (1680B, LIVE) — Ghidra `FUN_10149f934`
    ///
    /// Creates an `NSMutableAttributedString`, reads subtitle style from the
    /// `self + 0x20` region (alignment enum at `+0x10`, font scale at `+0x38`/`+0x40`,
    /// override flag at `+0x48`/`+0x30`). When the horizontal alignment is `.center`
    /// it adds a centered `NSMutableParagraphStyle`. Reads the background color
    /// `DAT_1044587b0`; if it is not `UIColor.clearColor` it adds an `NSShadow`
    /// from the shadow globals (`DAT_1044587a8` blur, `DAT_104458790` offset X,
    /// `DAT_104458798` offset Y). Applies the attribute dictionary via
    /// `addAttributes:range:`, calls `renderAttributedStringToBitmap`
    /// (`0x1013cf6e0`) for CoreText rasterization, then wraps the bitmap as a
    /// `CIImage` applying vertical + horizontal alignment offsets.
    private func buildAttributedStringImage(
        _ attributedString: NSAttributedString,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        alignment: HorizontalAlignment,
        fontScaleEnabled: Bool
    ) -> CIImage? {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)

        var attributes: [NSAttributedString.Key: Any] = [:]

        // Centered paragraph style when alignment == .center.
        if alignment == .center {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attributes[.paragraphStyle] = paragraph
        }

        // Background color drives the shadow pass: DAT_1044587b0 compared to clear.
        // UIColor is a typealias for NSColor on AppKit, so UIColor(_:Color) covers
        // both platforms (matching VideoPlayerView's `UIColor(SubtitleModel.textBackgroundColor)`).
        let backgroundColor = SubtitleModel.textBackgroundColor
        if backgroundColor != Color.clear {
            let shadow = NSShadow()
            // DAT_1044587a8 (blur), DAT_104458790 (offX), DAT_104458798 (offY).
            shadow.shadowBlurRadius = MetalSubtitleView.shadowBlurRadius * scale
            shadow.shadowOffset = CGSize(
                width: MetalSubtitleView.shadowOffsetX * scale,
                height: MetalSubtitleView.shadowOffsetY * scale
            )
            shadow.shadowColor = UIColor(backgroundColor)
            attributes[.shadow] = shadow
        }

        if !attributes.isEmpty {
            mutable.addAttributes(attributes, range: fullRange)
        }

        // CoreText rasterization -> bitmap CGImage.
        let maxWidth = width / scale - 40 // margin
        guard let bitmap = renderAttributedStringToBitmap(mutable, maxWidth: maxWidth, scale: scale) else {
            return nil
        }

        // Wrap the bitmap as a CIImage (alignment offsets are applied later by the
        // caller via computeTextPosition / position offsets).
        return CIImage(cgImage: bitmap)
    }

    /// RE: renderAttributedStringToBitmap at 0x1013cf6e0 (588B, LIVE) — Ghidra `FUN_1013cf6e0`
    ///
    /// Pure CoreText rasterizer. Creates a `CTFramesetter` from the attributed
    /// string, calls `CTFramesetterSuggestFrameSizeWithConstraints` (max width =
    /// param_1, max height = DBL_MAX), creates an 8-bit RGBA device-RGB
    /// `CGBitmapContext`, scales the CTM by param_2, draws via `CTFrameDraw`, and
    /// returns `CGBitmapContextCreateImage`. Returns the bitmap CGImage; CIImage
    /// wrapping is done by the caller (`buildAttributedStringImage`).
    private func renderAttributedStringToBitmap(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        scale: CGFloat
    ) -> CGImage? {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let fitRange = UnsafeMutablePointer<CFRange>.allocate(capacity: 1)
        defer { fitRange.deallocate() }
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            fitRange
        )

        let width = Int(ceil(suggestedSize.width * scale))
        let height = Int(ceil(suggestedSize.height * scale))
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)

        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: suggestedSize.width, height: suggestedSize.height),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)

        return context.makeImage()
    }

    // MARK: - HDR Compositing

    /// RE: applyHDRBrightnessAdjust at 0x1014a0368 (572B, LIVE)
    ///
    /// CIFilter chain for HDR subtitle legibility (Layer 2). Formula:
    /// `adjustedBrightness = ((EV + 1.0) / 1.5) * 0.7 + 0.3`, applied via
    /// `CIColorControls` (brightness = -(1 - adjustedBrightness), contrast 1,
    /// saturation 1). 2 callers (`renderTextSubtitleToCIImage @ 0x10149f590`).
    private func applyHDRBrightnessAdjust(to image: CIImage) -> CIImage {
        // EV from global DAT_10445876c.
        let adjustedBrightness = ((Double(Self.subtitleImageEV) + 1.0) / 1.5) * 0.7 + 0.3
        let brightness = -(1.0 - adjustedBrightness)

        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(1.0, forKey: kCIInputContrastKey)
        filter.setValue(1.0, forKey: kCIInputSaturationKey)

        return filter.outputImage ?? image
    }

    /// Apply CIExposureAdjust filter for HDR subtitle visibility (Layer 1).
    ///
    /// RE: invoked inline by `drawImpl @ 0x10149ee10` when `dynamicRange != 0` AND
    /// `DAT_10445876c != 0.0` (doc §1250-1257, `CIFilter.exposureAdjustFilter`).
    private func applyExposureAdjust(to image: CIImage, ev: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(ev, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    // MARK: - Dynamic Range Layer Configuration

    /// RE: MetalSubtitleView_updateLayerForDynamicRange at 0x10149e120 (492B, LIVE)
    ///
    /// Configures `CAMetalLayer.colorspace` via a `DynamicRange -> CGColorSpace`
    /// switch (doc §1276-1292), checks `UIScreen.currentEDRHeadroom > 1.0` for EDR
    /// availability, and sets `wantsExtendedDynamicRangeContent = true` only when
    /// HDR AND headroom > 1.0. 2 callers (`FUN_10149e78c`).
    private func updateLayerForDynamicRange() {
        guard let metalLayer = layer as? CAMetalLayer else { return }

        let colorSpace = dynamicRange.cgColorSpace
        metalLayer.colorspace = colorSpace

        if dynamicRange != .sdr {
            #if os(macOS)
            let headroom = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
            metalLayer.wantsExtendedDynamicRangeContent = headroom > 1.0
            #else
            if #available(iOS 16.0, tvOS 16.0, *) {
                let headroom = UIScreen.main.currentEDRHeadroom
                metalLayer.wantsExtendedDynamicRangeContent = headroom > 1.0
            } else {
                metalLayer.wantsExtendedDynamicRangeContent = true
            }
            #endif
        } else {
            metalLayer.wantsExtendedDynamicRangeContent = false
        }
    }

    #if canImport(UIKit)
    private var contentScaleFactor: CGFloat {
        UIScreen.main.scale
    }
    #else
    private var contentScaleFactor: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2.0
    }
    #endif

    /// Request a redraw with updated parts.
    public func updateSubtitles(_ newParts: [SubtitlePart]) {
        parts = newParts
    }
}

// MARK: - MetalSubtitleView globals
//
// The 1.3.15 binary reads these from module-level `DAT_*` slots (doc §1337-1344,
// §2431-2453). Modeled as type-level values to keep them off the documented
// 10-ivar layout while preserving the per-global read sites.
extension MetalSubtitleView {
    /// DAT_103d097b0 — subtitle scale factor (bytes `00 00 00 00 00 00 F0 3F` = 1.0).
    static var subtitleScaleFactor: CGFloat = 1.0
    /// DAT_1044587f0 — subtitle X position offset (read by `layoutSubtitleParts`).
    static var subtitlePositionOffsetX: CGFloat = 0.0
    /// DAT_1044587f8 — subtitle Y position offset (read by `layoutSubtitleParts`).
    static var subtitlePositionOffsetY: CGFloat = 0.0
    /// DAT_1044587a0 — subtitle background-glow color (alpha-checked in renderTextSubtitleToCIImage).
    static var backgroundGlowColor: UIColor = .clear
    /// DAT_1044587a8 — subtitle shadow blur radius (read by `buildAttributedStringImage`).
    static var shadowBlurRadius: CGFloat = 0.0
    /// DAT_104458790 — subtitle shadow offset X (read by `buildAttributedStringImage`).
    static var shadowOffsetX: CGFloat = 0.0
    /// DAT_104458798 — subtitle shadow offset Y (read by `buildAttributedStringImage`).
    static var shadowOffsetY: CGFloat = 0.0
}

// MARK: - PaddedLabel

/// Per-line subtitle label with configurable text inset and an outline/stroke pass.
///
/// RE: `class KSPlayer.PaddedLabel : __C.UILabel` — the value type of
/// `MetalSubtitleView.labelMap` (`[String: PaddedLabel]`). Type-metadata accessor
/// `$s8KSPlayer11PaddedLabelCMa @ 0x1013e794c`. A `UILabel` subclass that insets
/// its text by `padding` and adds a stroke/outline pass for legibility over video.
///
/// Platform guard: `UILabel` exists only on UIKit; AppKit has no direct `UILabel`
/// equivalent, so the AppKit build provides an `NSView`-rooted label that mirrors
/// the same `padding` + outlined-draw behavior.
#if canImport(UIKit)
public class PaddedLabel: UILabel {
    /// Per-edge text inset (top / left / bottom / right).
    ///
    /// RE: `_TtC8KSPlayer11PaddedLabel::padding` — 4 `Double`s read by
    /// `drawText(in:)`.
    public var padding: EdgeInsets = EdgeInsets()

    /// Stroke (outline) color for the legibility pass; nil disables the stroke pass.
    public var strokeColor: UIColor?
    /// Stroke width (in points, multiplied by `displayScale` at draw time).
    public var strokeWidth: CGFloat = 0

    /// RE: PaddedLabel.drawText(in:) override at 0x1013e66f0
    ///
    /// Reads `padding` (4 Doubles) and insets the draw rect — `x += padding.left`,
    /// `y += padding.top`, `w -= left+right`, `h -= top+bottom` — then calls
    /// `super.drawText(in:)` via `_objc_msgSendSuper2`. When a stroke color is set
    /// it adds an outline pass: `CGContextSetLineWidth(width * scale)`,
    /// `SetLineJoin`, `SetTextDrawingMode(.stroke)`, drawing stroked-then-filled
    /// text for the subtitle edge outline.
    override public func drawText(in rect: CGRect) {
        let insetRect = CGRect(
            x: rect.origin.x + padding.leading,
            y: rect.origin.y + padding.top,
            width: rect.width - (padding.leading + padding.trailing),
            height: rect.height - (padding.top + padding.bottom)
        )

        // Stroke/outline pass for edge legibility (stroked-then-filled).
        if let strokeColor, strokeWidth > 0, let context = UIGraphicsGetCurrentContext() {
            let scale = window?.screen.scale ?? UIScreen.main.scale
            context.saveGState()
            context.setLineWidth(strokeWidth * scale)
            context.setLineJoin(.round)
            context.setTextDrawingMode(.stroke)
            let savedColor = textColor
            textColor = strokeColor
            super.drawText(in: insetRect)
            textColor = savedColor
            context.restoreGState()

            // Fill pass on top.
            context.saveGState()
            context.setTextDrawingMode(.fill)
            super.drawText(in: insetRect)
            context.restoreGState()
            return
        }

        super.drawText(in: insetRect)
    }
}
#else
public class PaddedLabel: NSView {
    /// Per-edge text inset (top / left / bottom / right).
    public var padding: EdgeInsets = EdgeInsets()

    /// Text rendered by this label.
    public var attributedText: NSAttributedString?
    /// Stroke (outline) color for the legibility pass; nil disables the stroke pass.
    public var strokeColor: NSColor?
    /// Stroke width (in points, multiplied by backingScaleFactor at draw time).
    public var strokeWidth: CGFloat = 0

    /// RE: PaddedLabel.drawText(in:) override at 0x1013e66f0 (AppKit mirror)
    ///
    /// AppKit has no `UILabel.drawText(in:)`, so the inset-then-stroke-then-fill
    /// behavior is reproduced in `draw(_:)` over the same `padding` rect.
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let attributedText else { return }

        let insetRect = CGRect(
            x: bounds.origin.x + padding.leading,
            y: bounds.origin.y + padding.bottom,
            width: bounds.width - (padding.leading + padding.trailing),
            height: bounds.height - (padding.top + padding.bottom)
        )

        guard let context = NSGraphicsContext.current?.cgContext else {
            attributedText.draw(in: insetRect)
            return
        }

        if let strokeColor, strokeWidth > 0 {
            let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            context.saveGState()
            context.setLineWidth(strokeWidth * scale)
            context.setLineJoin(.round)
            context.setTextDrawingMode(.stroke)
            let stroked = NSMutableAttributedString(attributedString: attributedText)
            stroked.addAttribute(
                .foregroundColor,
                value: strokeColor,
                range: NSRange(location: 0, length: stroked.length)
            )
            stroked.draw(in: insetRect)
            context.restoreGState()

            context.saveGState()
            context.setTextDrawingMode(.fill)
            attributedText.draw(in: insetRect)
            context.restoreGState()
            return
        }

        attributedText.draw(in: insetRect)
    }
}
#endif

// MARK: - DynamicRange Color Space Extension

extension DynamicRange {
    /// Maps dynamic range to the appropriate CGColorSpace for subtitle rendering.
    ///
    /// RE: the `DynamicRange -> CGColorSpace` switch is the body of
    /// `MetalSubtitleView_updateLayerForDynamicRange @ 0x10149e120` (doc
    /// §1276-1292), factored here as a reusable computed property. (The previously
    /// cited standalone `DynamicRange_toCGColorSpace @ 0x1013c7150` is not
    /// catalogued in the MetalSubtitleView cluster; treat that address as
    /// cross-cluster / unverified for this file.)
    /// Uses the binary-accurate contiguous KSPlayer scheme (sdr=0, hdr10=1, hlg=2,
    /// dolbyVision=3); the classify-only `hdr10Fallback(4)` is never a stored
    /// `DynamicRange` and never reaches this mapping.
    var cgColorSpace: CGColorSpace {
        switch self {
        case .sdr:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .hdr10:
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020) ?? CGColorSpaceCreateDeviceRGB()
            }
        case .hlg, .dolbyVision:
            // DV uses HLG transfer for subtitles, not PQ (per RE doc §1290-1292).
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? CGColorSpaceCreateDeviceRGB()
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020) ?? CGColorSpaceCreateDeviceRGB()
            }
        }
    }
}
#endif
