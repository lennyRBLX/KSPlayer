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
import Foundation
import Metal
import MetalKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Metal-rendered subtitle compositing view with HDR-aware brightness correction.
///
/// Uses CIContext + CIRenderDestination (not a traditional render pipeline) to composite
/// subtitle images and rendered text onto a CAMetalLayer drawable. Supports SDR and HDR
/// output with per-subtitle exposure adjustment.
///
/// RE: MTKView subclass, drawImpl at 0x10149ee10 (1340 bytes).
public class MetalSubtitleView: MTKView, MTKViewDelegate {

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?

    /// Raw subtitle parts to render.
    public var parts: [SubtitlePart] = [] {
        didSet {
            updateImageInfos()
        }
    }

    /// Computed CIImage + position pairs ready for rendering.
    private var imageInfos: [(image: CIImage, position: CGPoint)] = []

    /// Play resolution ratio for ASS coordinate mapping.
    public var playRatio: Double = 1.0

    /// Current dynamic range of the video content.
    public var dynamicRange: DynamicRange = .sdr {
        didSet {
            updateLayerForDynamicRange()
        }
    }

    /// HDR subtitle exposure value (EV). 0 = no adjustment.
    /// RE: Forward v1.3.15 reads this from `DAT_10445876c` (Float) — the
    /// only HDR-EV global in the binary with live xrefs from
    /// `MetalSubtitleView_drawImpl @ 0x10149ee10` and `FUN_10149f590`.
    /// (Earlier RE notes named `0x1041F766C` `g_subtitleImageEV`; that
    /// address has zero xrefs in the Ghidra database and has been
    /// retired — see `.reversal/SubtitleSystem.md`.)
    public var subtitleImageEV: Float = 0.0

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

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Layout recalculation on resize
        updateImageInfos()
    }

    public func draw(in view: MTKView) {
        drawImpl()
    }

    // MARK: - Core Rendering

    /// RE: MetalSubtitleView_drawImpl at 0x101382A50
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
            mtlTextureProvider: { () -> MTLTexture in
                drawable.texture
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

            // Apply HDR brightness adjustment for non-SDR content
            // RE: bitmask logic at 0x101382D94: (0xE >> (dynamicRange & 0xF)) & 1
            let needsHDRAdjust = dynamicRange != .sdr

            if needsHDRAdjust, subtitleImageEV != 0 {
                subtitleImage = applyExposureAdjust(to: subtitleImage, ev: subtitleImageEV)
            }

            if needsHDRAdjust {
                subtitleImage = applyHDRBrightnessAdjust(to: subtitleImage)
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

    // MARK: - Layout

    /// Convert subtitle parts into renderable CIImage + position pairs.
    ///
    /// RE: The Forward binary has no standalone Ghidra entry for
    /// "MetalSubtitleView_layoutAndUpdateImageInfos" — the symbol at
    /// `0x101382710` that Ghidra labelled with that name is a misnamed
    /// 36-byte `AVRoutePickerView` allocation thunk unrelated to
    /// subtitle layout. The layout pipeline this method implements
    /// lives inline inside `MetalSubtitleView_drawImpl @ 0x10149ee10`
    /// and `MetalSubtitleView_layoutSubtitleParts @ 0x101498248`.
    private func updateImageInfos() {
        var newInfos: [(image: CIImage, position: CGPoint)] = []
        let scale = contentScaleFactor

        for part in parts {
            if let uiImage = part.image, let cgImage = uiImage.cgImage {
                // Bitmap subtitle (PGS/VOBSUB/ASS image render)
                let ciImage = CIImage(cgImage: cgImage)
                let position = CGPoint(
                    x: part.origin.x * scale,
                    y: drawableSize.height - part.origin.y * scale - ciImage.extent.height
                )
                newInfos.append((ciImage, position))
            } else if let text = part.text {
                // Text subtitle — render attributed string to CIImage
                if let ciImage = renderAttributedStringToCIImage(text, scale: scale) {
                    let position = computeTextPosition(for: part, imageSize: ciImage.extent.size, scale: scale)
                    let composited = compositeSubtitleWithBackground(ciImage)
                    newInfos.append((composited, position))
                }
            }
        }

        imageInfos = newInfos
        #if canImport(UIKit)
        setNeedsDisplay()
        #else
        needsDisplay = true
        #endif
    }

    // MARK: - Text Rendering

    /// RE: The Forward binary has no standalone Ghidra entry for
    /// "MetalSubtitleView_renderAttributedStringToCIImage" — the
    /// symbol at `0x101383568` that Ghidra labelled with that name is
    /// a misnamed 11-byte `Hashable.hash(into:)` witness for an
    /// unrelated `_CFObject`-bridged type (tail-calls `FUN_1002dd9d8`
    /// = `Swift.Hasher` init + `_CFObject.hash(into:)` + finalize).
    /// The real attributed-string → `CIImage` work lives inline inside
    /// `drawImpl @ 0x10149ee10` and feeds `imageInfos` via
    /// `compositeSubtitleWithBackground`. This Swift helper is the
    /// reconstruction's standalone version of that inline body.
    private func renderAttributedStringToCIImage(_ attributedString: NSAttributedString, scale: CGFloat) -> CIImage? {
        let maxWidth = drawableSize.width / scale - 40 // margin
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

        let path = CGPath(rect: CGRect(x: 0, y: 0, width: suggestedSize.width, height: suggestedSize.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedString.length), path, nil)
        CTFrameDraw(frame, context)

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    /// Compute position for text subtitle based on TextPosition alignment.
    private func computeTextPosition(for part: SubtitlePart, imageSize: CGSize, scale: CGFloat) -> CGPoint {
        let position = part.textPosition ?? SubtitleModel.textPosition
        let drawableWidth = drawableSize.width
        let drawableHeight = drawableSize.height

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

    // MARK: - HDR Compositing

    /// RE: compositeSubtitleWithBackground at 0x1013831D0
    /// Adds rounded-rect background and HDR brightness correction.
    private func compositeSubtitleWithBackground(_ image: CIImage) -> CIImage {
        var result = image

        // Add semi-transparent background if configured
        let bgColor = SubtitleModel.effectiveBackgroundColor
        if bgColor != .clear {
            let extent = image.extent.insetBy(dx: -10, dy: -6)
            // Create CIColor from the background color for compositing
            let ciColor: CIColor
            #if canImport(UIKit)
            if #available(iOS 17.0, tvOS 17.0, *) {
                ciColor = CIColor(color: UIColor(bgColor))
            } else {
                ciColor = CIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            }
            #else
            if #available(macOS 14.0, *) {
                ciColor = CIColor(color: NSColor(bgColor))
            } else {
                ciColor = CIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            }
            #endif
            let bgImage = CIImage(color: ciColor).cropped(to: extent)
            result = image.composited(over: bgImage)
        }

        return result
    }

    /// RE: applyHDRBrightnessAdjust at 0x101383F90
    /// Formula: adjustedBrightness = ((subtitleImageEV + 1.0) / 1.5) * 0.7 + 0.3
    private func applyHDRBrightnessAdjust(to image: CIImage) -> CIImage {
        let adjustedBrightness = ((Double(subtitleImageEV) + 1.0) / 1.5) * 0.7 + 0.3
        let brightness = -(1.0 - adjustedBrightness)

        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(1.0, forKey: kCIInputContrastKey)
        filter.setValue(1.0, forKey: kCIInputSaturationKey)

        return filter.outputImage ?? image
    }

    /// Apply CIExposureAdjust filter for HDR subtitle visibility.
    private func applyExposureAdjust(to image: CIImage, ev: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(ev, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    // MARK: - Dynamic Range Layer Configuration

    /// RE: updateLayerForDynamicRange at 0x101381D60
    /// Configures CAMetalLayer color space and EDR based on content dynamic range.
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

// MARK: - DynamicRange Color Space Extension

extension DynamicRange {
    /// RE: DynamicRange_toCGColorSpace at 0x1013c7150
    /// Maps dynamic range to the appropriate CGColorSpace for subtitle rendering.
    /// Note: Three DynamicRange enum schemes exist (Forward compact / Upstream / Components).
    /// This extension uses the upstream scheme (sdr=0, hdr10=2, hlg=3, dolbyVision=5).
    var cgColorSpace: CGColorSpace {
        switch self {
        case .sdr:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .hdr10, .hdr10Fallback:
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020) ?? CGColorSpaceCreateDeviceRGB()
            }
        case .hlg, .dolbyVision:
            // DV uses HLG transfer for subtitles, not PQ (per RE doc)
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? CGColorSpaceCreateDeviceRGB()
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020) ?? CGColorSpaceCreateDeviceRGB()
            }
        }
    }
}
#endif
